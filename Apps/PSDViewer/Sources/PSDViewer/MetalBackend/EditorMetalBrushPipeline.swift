import CoreGraphics
import Foundation
import Metal
import simd

struct EditorBrushPipelineDiagnostics: Equatable, Sendable {
    var lastStampedDabCount: Int = 0
    var lastStrokeMode: BrushStrokeMode?
    var activeLayerID: String?
    var workingTextureBytes: UInt64 = 0

    var summaryLine: String {
        let mode = lastStrokeMode.map { String(describing: $0) } ?? "-"
        return "dabs=\(lastStampedDabCount) mode=\(mode) layer=\(activeLayerID ?? "-")"
    }
}

struct BrushDabGPU {
    var center: SIMD2<Float>
    var radius: Float
    var dabAlpha: Float
    var strokeOpacity: Float
    var color: SIMD4<Float>
    var hardness: Float
    var mode: Int32
}

/// Transient stroke textures for preview only. Does not mutate `LayerTextureCache`.
final class EditorMetalBrushPipeline {
    private let device: MTLDevice
    private let stampPipeline: MTLComputePipelineState
    private let copyPipeline: MTLComputePipelineState

    private var activeStrokeTexture: MTLTexture?
    private var workingLayerTexture: MTLTexture?
    private var textureWidth = 0
    private var textureHeight = 0

    private(set) var diagnostics = EditorBrushPipelineDiagnostics()

    var hasTransientStrokeTextures: Bool {
        activeStrokeTexture != nil || workingLayerTexture != nil
    }

    init(device: MTLDevice, library: MTLLibrary) throws {
        self.device = device
        guard let stampFunction = library.makeFunction(name: "stampBrushDabsKernel"),
              let copyFunction = library.makeFunction(name: "copyTextureKernel")
        else {
            throw EditorMetalRendererError.pipelineCreationFailed
        }
        stampPipeline = try device.makeComputePipelineState(function: stampFunction)
        copyPipeline = try device.makeComputePipelineState(function: copyFunction)
    }

    func clearStroke() {
        activeStrokeTexture = nil
        workingLayerTexture = nil
        textureWidth = 0
        textureHeight = 0
        diagnostics = EditorBrushPipelineDiagnostics()
    }

    /// Returns a working layer texture = `base` + stamped `plan` for preview composite.
    func workingTexture(
        base: MTLTexture,
        plan: BrushRasterizationPlan,
        brush: BrushSettings,
        commandBuffer: MTLCommandBuffer
    ) throws -> MTLTexture {
        let width = plan.layerPixelWidth
        let height = plan.layerPixelHeight
        let working = try ensureWorkingLayerTexture(width: width, height: height)

        try copyTexture(from: base, to: working, commandBuffer: commandBuffer)
        try stampComposite(plan: plan, brush: brush, onto: working, commandBuffer: commandBuffer)

        // Keep an isolated stroke-only texture for E5 handoff without touching layer cache.
        let stroke = try ensureActiveStrokeTexture(width: width, height: height)
        try stampIsolated(plan: plan, brush: brush, onto: stroke, commandBuffer: commandBuffer)

        diagnostics.lastStampedDabCount = plan.dabCount
        diagnostics.lastStrokeMode = plan.mode
        diagnostics.activeLayerID = plan.layerID
        diagnostics.workingTextureBytes = UInt64(width * height * 4) * 2
        return working
    }

    private func ensureActiveStrokeTexture(width: Int, height: Int) throws -> MTLTexture {
        if let activeStrokeTexture,
           textureWidth == width,
           textureHeight == height {
            clearTexture(activeStrokeTexture)
            return activeStrokeTexture
        }
        let texture = try makeTexture(width: width, height: height)
        clearTexture(texture)
        activeStrokeTexture = texture
        textureWidth = width
        textureHeight = height
        return texture
    }

    private func ensureWorkingLayerTexture(width: Int, height: Int) throws -> MTLTexture {
        if let workingLayerTexture,
           textureWidth == width,
           textureHeight == height {
            return workingLayerTexture
        }
        let texture = try makeTexture(width: width, height: height)
        workingLayerTexture = texture
        return texture
    }

    private func makeTexture(width: Int, height: Int) throws -> MTLTexture {
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
        return texture
    }

    private func stampIsolated(
        plan: BrushRasterizationPlan,
        brush: BrushSettings,
        onto texture: MTLTexture,
        commandBuffer: MTLCommandBuffer
    ) throws {
        try dispatchStamp(
            plan: plan,
            brush: brush,
            texture: texture,
            composite: false,
            commandBuffer: commandBuffer
        )
    }

    private func stampComposite(
        plan: BrushRasterizationPlan,
        brush: BrushSettings,
        onto texture: MTLTexture,
        commandBuffer: MTLCommandBuffer
    ) throws {
        try dispatchStamp(
            plan: plan,
            brush: brush,
            texture: texture,
            composite: true,
            commandBuffer: commandBuffer
        )
    }

    private func dispatchStamp(
        plan: BrushRasterizationPlan,
        brush: BrushSettings,
        texture: MTLTexture,
        composite: Bool,
        commandBuffer: MTLCommandBuffer
    ) throws {
        guard !plan.dabs.isEmpty else { return }
        guard let encoder = commandBuffer.makeComputeCommandEncoder() else { return }

        let hardness = Float(min(max(CGFloat(brush.hardness) / 100.0, 0), 1))
        let gpuDabs = plan.dabs.map { dab -> BrushDabGPU in
            let mode: Int32
            switch (plan.mode, composite) {
            case (.brush, false): mode = 0
            case (.eraser, false): mode = 1
            case (.brush, true): mode = 2
            case (.eraser, true): mode = 3
            }
            return BrushDabGPU(
                center: SIMD2(Float(dab.center.x), Float(dab.center.y)),
                radius: Float(dab.radius),
                dabAlpha: Float(dab.alpha),
                strokeOpacity: Float(brush.opacity),
                color: SIMD4(
                    Float(dab.color.red),
                    Float(dab.color.green),
                    Float(dab.color.blue),
                    Float(dab.color.alpha)
                ),
                hardness: hardness,
                mode: mode
            )
        }

        encoder.setComputePipelineState(stampPipeline)
        encoder.setTexture(texture, index: 0)

        // Stamp one dab per dispatch so src-over / destination-out compositing stays ordered.
        let threadgroupSize = MTLSize(width: 1, height: 1, depth: 1)
        let singleDabGroups = MTLSize(width: 1, height: 1, depth: 1)
        for dab in gpuDabs {
            var singleDab = dab
            var dabCount = UInt32(1)
            encoder.setBytes(&singleDab, length: MemoryLayout<BrushDabGPU>.stride, index: 0)
            encoder.setBytes(&dabCount, length: MemoryLayout<UInt32>.stride, index: 1)
            encoder.dispatchThreadgroups(singleDabGroups, threadsPerThreadgroup: threadgroupSize)
        }
        encoder.endEncoding()
    }

    private func copyTexture(
        from source: MTLTexture,
        to destination: MTLTexture,
        commandBuffer: MTLCommandBuffer
    ) throws {
        guard let encoder = commandBuffer.makeComputeCommandEncoder() else { return }
        encoder.setComputePipelineState(copyPipeline)
        encoder.setTexture(source, index: 0)
        encoder.setTexture(destination, index: 1)

        let threadgroupSize = MTLSize(width: 8, height: 8, depth: 1)
        let threadgroups = MTLSize(
            width: (source.width + 7) / 8,
            height: (source.height + 7) / 8,
            depth: 1
        )
        encoder.dispatchThreadgroups(threadgroups, threadsPerThreadgroup: threadgroupSize)
        encoder.endEncoding()
    }

    private func clearTexture(_ texture: MTLTexture) {
        let width = texture.width
        let height = texture.height
        let pixelData = [UInt8](repeating: 0, count: width * height * 4)
        pixelData.withUnsafeBytes { raw in
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
    }
}
