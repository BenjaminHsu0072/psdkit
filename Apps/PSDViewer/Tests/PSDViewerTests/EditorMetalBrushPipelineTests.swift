import CoreGraphics
import Metal
import XCTest
import PSDKit
@testable import PSDViewer

final class EditorMetalBrushPipelineTests: XCTestCase {
    func testOverlappingEraserDabStampProducesDeterministicHash() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw XCTSkip("Metal device unavailable")
        }
        guard let library = try? device.makeLibrary(source: EditorMetalShaderSource.library, options: nil) else {
            throw XCTSkip("Metal shader library unavailable")
        }

        let pipeline = try EditorMetalBrushPipeline(device: device, library: library)
        let plan = overlappingEraserPlan()
        let brush = BrushSettings.defaults
        let base = try makeOpaqueTexture(device: device, width: plan.layerPixelWidth, height: plan.layerPixelHeight)

        var hashes: [UInt64] = []
        for _ in 0 ..< 3 {
            guard let commandBuffer = device.makeCommandQueue()?.makeCommandBuffer() else {
                XCTFail("unable to create command buffer")
                return
            }
            let working = try pipeline.workingTexture(
                base: base,
                plan: plan,
                brush: brush,
                commandBuffer: commandBuffer
            )
            commandBuffer.commit()
            commandBuffer.waitUntilCompleted()
            hashes.append(textureRGBAHash(working))
        }

        XCTAssertEqual(hashes.count, 3)
        XCTAssertEqual(hashes[0], hashes[1])
        XCTAssertEqual(hashes[1], hashes[2])
        XCTAssertEqual(pipeline.diagnostics.lastStrokeMode, .eraser)
        XCTAssertGreaterThan(pipeline.diagnostics.lastStampedDabCount, 1)
    }

    func testCompositeCacheKeyDiffersWhenSampleCountChangesWithSameDabCount() throws {
        let document = try PSDDocument.create(width: 32, height: 32)
        let snapshot = EditorRenderSnapshotBuilder.build(from: document, documentRevision: 1)
        let plan = overlappingBrushPlan()
        XCTAssertGreaterThan(plan.dabCount, 1)

        let planFewerSamples = BrushRasterizationPlan(
            strokePlan: plan.strokePlan,
            layerID: plan.layerID,
            layerFrame: plan.layerFrame,
            layerPixelWidth: plan.layerPixelWidth,
            layerPixelHeight: plan.layerPixelHeight,
            sampleCount: 2
        )
        let planMoreSamples = BrushRasterizationPlan(
            strokePlan: plan.strokePlan,
            layerID: plan.layerID,
            layerFrame: plan.layerFrame,
            layerPixelWidth: plan.layerPixelWidth,
            layerPixelHeight: plan.layerPixelHeight,
            sampleCount: 5
        )
        XCTAssertEqual(planFewerSamples.dabCount, planMoreSamples.dabCount)
        XCTAssertNotEqual(planFewerSamples.sampleCount, planMoreSamples.sampleCount)

        let previewFewerSamples = ActiveStrokePreview(
            plan: planFewerSamples,
            phase: .active,
            brush: .defaults
        )
        let previewMoreSamples = ActiveStrokePreview(
            plan: planMoreSamples,
            phase: .active,
            brush: .defaults
        )

        let keyFewerSamples = CompositeCacheKey(snapshot: snapshot, strokePreview: previewFewerSamples)
        let keyMoreSamples = CompositeCacheKey(snapshot: snapshot, strokePreview: previewMoreSamples)
        XCTAssertNotEqual(keyFewerSamples, keyMoreSamples)
    }

    func testOverlappingDabStampProducesDeterministicHash() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw XCTSkip("Metal device unavailable")
        }
        guard let library = try? device.makeLibrary(source: EditorMetalShaderSource.library, options: nil) else {
            throw XCTSkip("Metal shader library unavailable")
        }

        let pipeline = try EditorMetalBrushPipeline(device: device, library: library)
        let plan = overlappingBrushPlan()
        let brush = BrushSettings.defaults
        let base = try makeClearTexture(device: device, width: plan.layerPixelWidth, height: plan.layerPixelHeight)

        var hashes: [UInt64] = []
        for _ in 0 ..< 3 {
            guard let commandBuffer = device.makeCommandQueue()?.makeCommandBuffer() else {
                XCTFail("unable to create command buffer")
                return
            }
            let working = try pipeline.workingTexture(
                base: base,
                plan: plan,
                brush: brush,
                commandBuffer: commandBuffer
            )
            commandBuffer.commit()
            commandBuffer.waitUntilCompleted()
            hashes.append(textureRGBAHash(working))
        }

        XCTAssertEqual(hashes.count, 3)
        XCTAssertEqual(hashes[0], hashes[1])
        XCTAssertEqual(hashes[1], hashes[2])
        XCTAssertGreaterThan(pipeline.diagnostics.lastStampedDabCount, 1)
    }

    func testClearStrokeRemovesTransientTextures() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw XCTSkip("Metal device unavailable")
        }
        guard let library = try? device.makeLibrary(source: EditorMetalShaderSource.library, options: nil) else {
            throw XCTSkip("Metal shader library unavailable")
        }

        let pipeline = try EditorMetalBrushPipeline(device: device, library: library)
        let plan = overlappingBrushPlan()
        let brush = BrushSettings.defaults
        let base = try makeClearTexture(device: device, width: plan.layerPixelWidth, height: plan.layerPixelHeight)

        guard let commandBuffer = device.makeCommandQueue()?.makeCommandBuffer() else {
            XCTFail("unable to create command buffer")
            return
        }
        _ = try pipeline.workingTexture(base: base, plan: plan, brush: brush, commandBuffer: commandBuffer)
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()

        XCTAssertTrue(pipeline.hasTransientStrokeTextures)
        XCTAssertGreaterThan(pipeline.diagnostics.lastStampedDabCount, 0)

        pipeline.clearStroke()

        XCTAssertFalse(pipeline.hasTransientStrokeTextures)
        XCTAssertEqual(pipeline.diagnostics.lastStampedDabCount, 0)
    }

    func testCPURasterizerMatchesGPUBrushPipelineWithinTolerance() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw XCTSkip("Metal device unavailable")
        }
        guard let library = try? device.makeLibrary(source: EditorMetalShaderSource.library, options: nil) else {
            throw XCTSkip("Metal shader library unavailable")
        }

        let pipeline = try EditorMetalBrushPipeline(device: device, library: library)
        let plan = overlappingBrushPlan()
        let brush = BrushSettings.defaults
        let width = plan.layerPixelWidth
        let height = plan.layerPixelHeight

        var cpuRGBA = Data(repeating: 0, count: width * height * 4)
        StrokePixelRasterizer.rasterize(
            plan: plan,
            brush: brush,
            onto: &cpuRGBA,
            width: width,
            height: height
        )

        let base = try makeClearTexture(device: device, width: width, height: height)
        guard let commandBuffer = device.makeCommandQueue()?.makeCommandBuffer() else {
            XCTFail("unable to create command buffer")
            return
        }
        let gpuTexture = try pipeline.workingTexture(
            base: base,
            plan: plan,
            brush: brush,
            commandBuffer: commandBuffer
        )
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()

        let gpuRGBA = readTextureRGBA(gpuTexture)
        XCTAssertEqual(cpuRGBA.count, gpuRGBA.count)
        XCTAssertTrue(
            rgbaApproximatelyEqual(cpuRGBA, gpuRGBA, perChannelTolerance: 1),
            "CPU and GPU raster outputs diverged beyond tolerance"
        )
    }

    func testRendererClearsTransientTexturesWhenStrokePreviewInactive() throws {
        guard EditorMetalRenderer.canInitialize() else {
            throw XCTSkip("Metal renderer unavailable")
        }
        let renderer = try EditorMetalRenderer.makeDefault()
        let plan = overlappingBrushPlan()
        let base = try makeClearTexture(
            device: renderer.device,
            width: plan.layerPixelWidth,
            height: plan.layerPixelHeight
        )
        guard let commandBuffer = renderer.device.makeCommandQueue()?.makeCommandBuffer() else {
            XCTFail("unable to create command buffer")
            return
        }
        _ = try renderer.brushPipeline.workingTexture(
            base: base,
            plan: plan,
            brush: .defaults,
            commandBuffer: commandBuffer
        )
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        XCTAssertGreaterThan(renderer.brushPipelineDiagnostics.lastStampedDabCount, 0)
        XCTAssertTrue(renderer.brushPipeline.hasTransientStrokeTextures)

        renderer.syncStrokePreviewTransientState(strokePreview: nil)
        XCTAssertEqual(renderer.brushPipelineDiagnostics.lastStampedDabCount, 0)
        XCTAssertFalse(renderer.brushPipeline.hasTransientStrokeTextures)
    }

    private func overlappingEraserPlan() -> BrushRasterizationPlan {
        let dabs = [
            BrushDab(
                center: CGPoint(x: 16, y: 16),
                radius: 10,
                alpha: 0.8,
                color: EditorColor(red: 0, green: 0, blue: 0, alpha: 0)
            ),
            BrushDab(
                center: CGPoint(x: 18, y: 18),
                radius: 10,
                alpha: 0.8,
                color: EditorColor(red: 0, green: 0, blue: 0, alpha: 0)
            ),
            BrushDab(
                center: CGPoint(x: 14, y: 14),
                radius: 10,
                alpha: 0.8,
                color: EditorColor(red: 0, green: 0, blue: 0, alpha: 0)
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
            strokePlan: BrushStrokePlan(mode: .eraser, dabs: dabs, dirtyRegion: dirtyRegion),
            layerID: "0",
            layerFrame: PSDRect(left: 0, top: 0, right: 32, bottom: 32),
            layerPixelWidth: 32,
            layerPixelHeight: 32,
            sampleCount: 3
        )
    }

    private func overlappingBrushPlan() -> BrushRasterizationPlan {
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

    private func makeOpaqueTexture(device: MTLDevice, width: Int, height: Int) throws -> MTLTexture {
        let texture = try makeClearTexture(device: device, width: width, height: height)
        let bytes = [UInt8](repeating: 255, count: width * height * 4)
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

    private func makeClearTexture(device: MTLDevice, width: Int, height: Int) throws -> MTLTexture {
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

    private func textureRGBAHash(_ texture: MTLTexture) -> UInt64 {
        EditorPixelRevisionDigest.digest(rgba: readTextureRGBA(texture))
    }

    private func readTextureRGBA(_ texture: MTLTexture) -> Data {
        let width = texture.width
        let height = texture.height
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        bytes.withUnsafeMutableBytes { raw in
            guard let baseAddress = raw.baseAddress else { return }
            texture.getBytes(
                baseAddress,
                bytesPerRow: width * 4,
                from: MTLRegion(
                    origin: MTLOrigin(x: 0, y: 0, z: 0),
                    size: MTLSize(width: width, height: height, depth: 1)
                ),
                mipmapLevel: 0
            )
        }
        return Data(bytes)
    }

    private func rgbaApproximatelyEqual(
        _ lhs: Data,
        _ rhs: Data,
        perChannelTolerance: Int
    ) -> Bool {
        guard lhs.count == rhs.count else { return false }
        for index in lhs.indices {
            if abs(Int(lhs[index]) - Int(rhs[index])) > perChannelTolerance {
                return false
            }
        }
        return true
    }
}
