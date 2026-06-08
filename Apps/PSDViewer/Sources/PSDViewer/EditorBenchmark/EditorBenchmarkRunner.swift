import CoreGraphics
import Foundation
import Metal
import PSDKit

struct EditorBenchmarkOptions {
    var warmupIterations: Int = 1
    var measuredIterations: Int = 5
    var outputPath: String?
}

enum EditorBenchmarkRunner {
    static func run(options: EditorBenchmarkOptions) throws {
        let metalAvailable = EditorMetalRenderer.canInitialize()
        var notes: [String] = []
        if !metalAvailable {
            notes.append("Metal unavailable; metalComposite and texture cache metrics omitted")
        }

        let document = try PSDDocument.makeMidtermStandardDocument()
        var snapshotBuildSamples: [Double] = []
        var cpuCompositeSamples: [Double] = []
        var metalCompositeSamples: [Double] = []
        var brushRasterSamples: [Double] = []

        var snapshot = EditorRenderSnapshotBuilder.build(from: document, documentRevision: 1)
        var provider = EditorSnapshotPixelProvider.build(from: document, snapshot: snapshot)

        let totalIterations = options.warmupIterations + options.measuredIterations
        for iteration in 0 ..< totalIterations {
            let isWarmup = iteration < options.warmupIterations

            let buildStart = CFAbsoluteTimeGetCurrent()
            snapshot = EditorRenderSnapshotBuilder.build(from: document, documentRevision: UInt64(iteration + 1))
            provider = EditorSnapshotPixelProvider.build(from: document, snapshot: snapshot)
            let buildElapsed = CFAbsoluteTimeGetCurrent() - buildStart
            if !isWarmup { snapshotBuildSamples.append(buildElapsed) }

            let cpuStart = CFAbsoluteTimeGetCurrent()
            _ = try EditorSnapshotCompositor.compositeRGBA(snapshot: snapshot, pixels: provider)
            let cpuElapsed = CFAbsoluteTimeGetCurrent() - cpuStart
            if !isWarmup { cpuCompositeSamples.append(cpuElapsed) }

            if metalAvailable {
                let metalStart = CFAbsoluteTimeGetCurrent()
                let renderer = try EditorMetalRenderer.makeDefault()
                _ = try renderer.compositeRGBA(snapshot: snapshot, pixels: provider)
                let metalElapsed = CFAbsoluteTimeGetCurrent() - metalStart
                if !isWarmup { metalCompositeSamples.append(metalElapsed) }
            }

            let plan = benchmarkBrushPlan()
            var rgba = Data(repeating: 0, count: plan.layerPixelWidth * plan.layerPixelHeight * 4)
            let brushStart = CFAbsoluteTimeGetCurrent()
            StrokePixelRasterizer.rasterize(
                plan: plan,
                brush: .defaults,
                onto: &rgba,
                width: plan.layerPixelWidth,
                height: plan.layerPixelHeight
            )
            let brushElapsed = CFAbsoluteTimeGetCurrent() - brushStart
            if !isWarmup { brushRasterSamples.append(brushElapsed) }
        }

        var textureDiagnostics: EditorTextureCacheDiagnosticsReport?
        var brushDiagnostics: EditorBrushDiagnosticsReport?
        if metalAvailable {
            let renderer = try EditorMetalRenderer.makeDefault()
            _ = try renderer.compositeRGBA(snapshot: snapshot, pixels: provider)
            let cache = renderer.textureCacheDiagnostics
            textureDiagnostics = EditorTextureCacheDiagnosticsReport(
                textureCount: cache.textureCount,
                uploadCount: cache.uploadCount,
                hitCount: cache.hitCount,
                missCount: cache.missCount,
                estimatedMemoryBytes: cache.estimatedMemoryBytes
            )

            if let device = MTLCreateSystemDefaultDevice(),
               let library = try? device.makeLibrary(source: EditorMetalShaderSource.library, options: nil) {
                let pipeline = try EditorMetalBrushPipeline(device: device, library: library)
                let plan = benchmarkBrushPlan()
                let base = try makeClearTexture(device: device, width: plan.layerPixelWidth, height: plan.layerPixelHeight)
                if let commandBuffer = device.makeCommandQueue()?.makeCommandBuffer() {
                    _ = try pipeline.workingTexture(base: base, plan: plan, brush: .defaults, commandBuffer: commandBuffer)
                    commandBuffer.commit()
                    commandBuffer.waitUntilCompleted()
                }
                let brush = pipeline.diagnostics
                brushDiagnostics = EditorBrushDiagnosticsReport(
                    lastStampedDabCount: brush.lastStampedDabCount,
                    workingTextureBytes: brush.workingTextureBytes
                )
            }
        }

        let report = EditorBenchmarkReport(
            fixture: "midterm-standard-document",
            environment: captureEnvironment(
                warmupIterations: options.warmupIterations,
                measuredIterations: options.measuredIterations,
                metalAvailable: metalAvailable
            ),
            metrics: EditorBenchmarkMetrics(
                snapshotBuild: EditorTimingStats(samples: snapshotBuildSamples),
                cpuComposite: EditorTimingStats(samples: cpuCompositeSamples),
                metalComposite: metalCompositeSamples.isEmpty ? nil : EditorTimingStats(samples: metalCompositeSamples),
                brushCPURasterize: EditorTimingStats(samples: brushRasterSamples),
                textureCacheAfterMetalComposite: textureDiagnostics,
                brushDiagnosticsAfterStamp: brushDiagnostics,
                notes: notes
            ),
            generatedAt: ISO8601DateFormatter().string(from: Date())
        )

        let outputData = try EditorBenchmarkOutput.encodeJSON(report)
        if let outputPath = options.outputPath {
            let url = URL(fileURLWithPath: outputPath)
            try outputData.write(to: url, options: [.atomic])
            fputs("Wrote editor benchmark report to \(url.path)\n", stderr)
        } else {
            print(String(decoding: outputData, as: UTF8.self))
        }
    }

    private static func captureEnvironment(
        warmupIterations: Int,
        measuredIterations: Int,
        metalAvailable: Bool
    ) -> EditorBenchmarkEnvironment {
        EditorBenchmarkEnvironment(
            osVersion: ProcessInfo.processInfo.operatingSystemVersionString,
            hardware: hardwareSummary(),
            physicalMemoryBytes: physicalMemoryBytes(),
            swiftVersion: swiftToolchainVersion(),
            buildConfiguration: {
                #if DEBUG
                return "debug"
                #else
                return "release"
                #endif
            }(),
            warmupIterations: warmupIterations,
            measuredIterations: measuredIterations,
            metalAvailable: metalAvailable,
            statistics: "P50, P95, min, max over measured iterations (linear interpolation); no pass/fail thresholds"
        )
    }

    private static func hardwareSummary() -> String {
        var size = 0
        sysctlbyname("hw.model", nil, &size, nil, 0)
        var model = [CChar](repeating: 0, count: size)
        sysctlbyname("hw.model", &model, &size, nil, 0)
        let modelName = String(cString: model)
        let cpus = ProcessInfo.processInfo.processorCount
        let ramGB = Double(physicalMemoryBytes()) / 1_073_741_824.0
        return String(format: "%@, %d logical CPUs, %.1f GB RAM", modelName, cpus, ramGB)
    }

    private static func physicalMemoryBytes() -> UInt64 {
        UInt64(ProcessInfo.processInfo.physicalMemory)
    }

    private static func swiftToolchainVersion() -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/swift")
        process.arguments = ["--version"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try? process.run()
        process.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func benchmarkBrushPlan() -> BrushRasterizationPlan {
        let dabs = [
            BrushDab(
                center: CGPoint(x: 16, y: 16),
                radius: 10,
                alpha: 0.8,
                color: EditorColor(red: 1, green: 0, blue: 0, alpha: 1)
            ),
            BrushDab(
                center: CGPoint(x: 18, y: 18),
                radius: 10,
                alpha: 0.8,
                color: EditorColor(red: 0, green: 0, blue: 1, alpha: 1)
            ),
            BrushDab(
                center: CGPoint(x: 14, y: 14),
                radius: 10,
                alpha: 0.8,
                color: EditorColor(red: 0, green: 1, blue: 0, alpha: 1)
            ),
        ]
        let dirtyRegion = dabs.reduce(EditorDirtyRegion.empty) { partial, dab in
            partial.union(with: .unionRect(PSDRect(
                left: Int(floor(dab.bounds.minX)),
                top: Int(floor(dab.bounds.minY)),
                right: Int(ceil(dab.bounds.maxX)),
                bottom: Int(ceil(dab.bounds.maxY))
            )))
        }
        return BrushRasterizationPlan(
            strokePlan: BrushStrokePlan(mode: .brush, dabs: dabs, dirtyRegion: dirtyRegion),
            layerID: "0",
            layerFrame: PSDRect(left: 0, top: 0, right: 32, bottom: 32),
            layerPixelWidth: 32,
            layerPixelHeight: 32,
            sampleCount: 3
        )
    }

    private static func makeClearTexture(device: MTLDevice, width: Int, height: Int) throws -> MTLTexture {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm,
            width: width,
            height: height,
            mipmapped: false
        )
        descriptor.usage = [.shaderRead, .shaderWrite]
        guard let texture = device.makeTexture(descriptor: descriptor) else {
            throw EditorMetalRendererError.textureAllocationFailed
        }
        let bytes = [UInt8](repeating: 0, count: width * height * 4)
        bytes.withUnsafeBytes { raw in
            guard let baseAddress = raw.baseAddress else { return }
            texture.replace(
                region: MTLRegion(
                    origin: MTLOrigin(x: 0, y: 0, z: 0),
                    size: MTLSize(width: width, height: height, depth: 1)
                ),
                mipmapLevel: 0,
                withBytes: baseAddress,
                bytesPerRow: width * 4
            )
        }
        return texture
    }
}
