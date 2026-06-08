import CoreGraphics
import Foundation
import Metal
import PSDKit
import QuartzCore

enum EditorMetalRendererError: Error, Equatable {
    case metalUnavailable
    case pipelineCreationFailed
    case textureAllocationFailed
}

/// Read-only preview renderer consuming `EditorRenderSnapshot` only.
final class EditorMetalRenderer {
    let device: MTLDevice

    private let commandQueue: MTLCommandQueue
    private let compositePipeline: MTLComputePipelineState
    private let displayPipeline: MTLRenderPipelineState
    private let displaySampler: MTLSamplerState
    private let layerTextureCache: LayerTextureCache
    let brushPipeline: EditorMetalBrushPipeline
    private var compositeTexture: MTLTexture?
    private var compositeCacheKey: CompositeCacheKey?

    var textureCacheDiagnostics: LayerTextureCacheDiagnostics {
        layerTextureCache.diagnostics
    }

    var brushPipelineDiagnostics: EditorBrushPipelineDiagnostics {
        brushPipeline.diagnostics
    }

    init(device: MTLDevice) throws {
        self.device = device
        guard let queue = device.makeCommandQueue() else {
            throw EditorMetalRendererError.metalUnavailable
        }
        commandQueue = queue
        layerTextureCache = LayerTextureCache(device: device)

        guard let library = try? device.makeLibrary(source: EditorMetalShaderSource.library, options: nil) else {
            throw EditorMetalRendererError.pipelineCreationFailed
        }
        guard let compositeFunction = library.makeFunction(name: "compositeLayerKernel") else {
            throw EditorMetalRendererError.pipelineCreationFailed
        }
        compositePipeline = try device.makeComputePipelineState(function: compositeFunction)
        brushPipeline = try EditorMetalBrushPipeline(device: device, library: library)

        let vertexFunction = library.makeFunction(name: "editorPreviewVertex")
        let fragmentFunction = library.makeFunction(name: "editorPreviewFragment")
        let pipelineDescriptor = MTLRenderPipelineDescriptor()
        pipelineDescriptor.vertexFunction = vertexFunction
        pipelineDescriptor.fragmentFunction = fragmentFunction
        pipelineDescriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        displayPipeline = try device.makeRenderPipelineState(descriptor: pipelineDescriptor)

        let samplerDescriptor = MTLSamplerDescriptor()
        samplerDescriptor.minFilter = .nearest
        samplerDescriptor.magFilter = .nearest
        samplerDescriptor.sAddressMode = .clampToEdge
        samplerDescriptor.tAddressMode = .clampToEdge
        guard let sampler = device.makeSamplerState(descriptor: samplerDescriptor) else {
            throw EditorMetalRendererError.pipelineCreationFailed
        }
        displaySampler = sampler
    }

    private static var cachedCanInitialize: Bool?

    static func makeDefault() throws -> EditorMetalRenderer {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw EditorMetalRendererError.metalUnavailable
        }
        return try EditorMetalRenderer(device: device)
    }

    static func canInitialize() -> Bool {
        if let cachedCanInitialize {
            return cachedCanInitialize
        }
        let result = (try? makeDefault()) != nil
        cachedCanInitialize = result
        return result
    }

    func draw(
        snapshot: EditorRenderSnapshot,
        pixels: EditorSnapshotPixelProvider,
        viewport: EditorViewport,
        strokePreview: ActiveStrokePreview? = nil,
        into drawable: CAMetalDrawable
    ) throws {
        let canvasWidth = snapshot.canvasSize.width
        let canvasHeight = snapshot.canvasSize.height
        guard canvasWidth > 0, canvasHeight > 0 else {
            clearDrawable(drawable)
            return
        }

        let composite = try ensureCompositeTexture(width: canvasWidth, height: canvasHeight)
        try rebuildCompositeIfNeeded(
            snapshot: snapshot,
            pixels: pixels,
            strokePreview: strokePreview,
            into: composite
        )

        guard let commandBuffer = commandQueue.makeCommandBuffer() else { return }
        let renderPass = MTLRenderPassDescriptor()
        renderPass.colorAttachments[0].texture = drawable.texture
        renderPass.colorAttachments[0].loadAction = .clear
        renderPass.colorAttachments[0].storeAction = .store
        renderPass.colorAttachments[0].clearColor = MTLClearColor(red: 0.18, green: 0.18, blue: 0.18, alpha: 1)

        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPass) else { return }
        encoder.setRenderPipelineState(displayPipeline)

        var uniforms = EditorViewportUniforms(
            canvasSize: SIMD2(Float(canvasWidth), Float(canvasHeight)),
            viewSize: SIMD2(Float(viewport.viewSize.width), Float(viewport.viewSize.height)),
            scale: Float(viewport.scale),
            translation: SIMD2(Float(viewport.translation.x), Float(viewport.translation.y)),
            drawableSize: SIMD2(Float(drawable.texture.width), Float(drawable.texture.height))
        )
        encoder.setVertexBytes(&uniforms, length: MemoryLayout<EditorViewportUniforms>.stride, index: 0)

        var checkerSize: Float = 8
        encoder.setFragmentBytes(&checkerSize, length: MemoryLayout<Float>.stride, index: 0)
        encoder.setFragmentTexture(composite, index: 0)
        encoder.setFragmentSamplerState(displaySampler, index: 0)

        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6)
        encoder.endEncoding()

        commandBuffer.present(drawable)
        commandBuffer.commit()
    }

    func syncStrokePreviewTransientState(strokePreview: ActiveStrokePreview?) {
        let isActive = strokePreview?.phase == .active
        if isActive != true {
            brushPipeline.clearStroke()
        }
    }

    /// Canvas RGBA for E6 validation and benchmark baselines. Not used by the display path.
    func compositeRGBA(
        snapshot: EditorRenderSnapshot,
        pixels: EditorSnapshotPixelProvider,
        strokePreview: ActiveStrokePreview? = nil
    ) throws -> Data {
        let canvasWidth = snapshot.canvasSize.width
        let canvasHeight = snapshot.canvasSize.height
        guard canvasWidth > 0, canvasHeight > 0 else { return Data() }

        let composite = try ensureCompositeTexture(width: canvasWidth, height: canvasHeight)
        try rebuildCompositeIfNeeded(
            snapshot: snapshot,
            pixels: pixels,
            strokePreview: strokePreview,
            into: composite
        )
        return readTextureRGBA(composite)
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

    private func rebuildCompositeIfNeeded(
        snapshot: EditorRenderSnapshot,
        pixels: EditorSnapshotPixelProvider,
        strokePreview: ActiveStrokePreview?,
        into composite: MTLTexture
    ) throws {
        layerTextureCache.prepareForSnapshot(snapshot)
        syncStrokePreviewTransientState(strokePreview: strokePreview)

        let cacheKey = CompositeCacheKey(snapshot: snapshot, strokePreview: strokePreview)
        if cacheKey == compositeCacheKey { return }
        compositeCacheKey = cacheKey

        guard let commandBuffer = commandQueue.makeCommandBuffer() else { return }

        let orderedLayers = snapshot.layers
            .filter { $0.kind == .pixel && $0.isVisible }
            .sorted { $0.stackOrder < $1.stackOrder }

        var pruneKeys = Set<LayerTextureCacheKey>()
        for layer in snapshot.layers where layer.kind == .pixel {
            guard let payload = pixels.rgba(for: layer) else { continue }
            if let key = LayerTextureCacheKey(layer: layer, payload: payload) {
                pruneKeys.insert(key)
            }
        }

        var previewTextures: [String: MTLTexture] = [:]
        if let strokePreview, strokePreview.phase == .active {
            if let layer = orderedLayers.first(where: { $0.id == strokePreview.plan.layerID }),
               let payload = pixels.rgba(for: layer) {
                let base = try layerTextureCache.texture(for: layer, payload: payload)
                let working = try brushPipeline.workingTexture(
                    base: base,
                    plan: strokePreview.plan,
                    brush: strokePreview.brush,
                    commandBuffer: commandBuffer
                )
                previewTextures[layer.id] = working
            }
        }

        fillTexture(composite, color: SIMD4<UInt8>(255, 255, 255, 255))

        guard let encoder = commandBuffer.makeComputeCommandEncoder() else { return }

        for layer in orderedLayers {
            guard let payload = pixels.rgba(for: layer) else { continue }
            let source: MTLTexture
            if let preview = previewTextures[layer.id] {
                source = preview
            } else {
                source = try layerTextureCache.texture(for: layer, payload: payload)
            }

            guard let encodedBlend = EditorMetalBlendMode.encode(layer.blendMode) else {
                continue
            }

            var uniforms = LayerCompositeUniforms(
                canvasSize: SIMD2(Float(snapshot.canvasSize.width), Float(snapshot.canvasSize.height)),
                blendMode: Int32(encodedBlend),
                layerOpacity: Float(layer.opacity) / 255.0,
                frameRect: SIMD4(
                    Float(layer.frame.left),
                    Float(layer.frame.top),
                    Float(layer.frame.width),
                    Float(layer.frame.height)
                )
            )

            encoder.setComputePipelineState(compositePipeline)
            encoder.setTexture(source, index: 0)
            encoder.setTexture(composite, index: 1)
            encoder.setBytes(&uniforms, length: MemoryLayout<LayerCompositeUniforms>.stride, index: 0)

            let threadgroupSize = MTLSize(width: 8, height: 8, depth: 1)
            let threadgroups = MTLSize(
                width: (snapshot.canvasSize.width + 7) / 8,
                height: (snapshot.canvasSize.height + 7) / 8,
                depth: 1
            )
            encoder.dispatchThreadgroups(threadgroups, threadsPerThreadgroup: threadgroupSize)
        }
        layerTextureCache.prune(keeping: pruneKeys)
        encoder.endEncoding()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
    }

    private func ensureCompositeTexture(width: Int, height: Int) throws -> MTLTexture {
        if let compositeTexture,
           compositeTexture.width == width,
           compositeTexture.height == height {
            return compositeTexture
        }

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
        compositeTexture = texture
        compositeCacheKey = nil
        return texture
    }

    private func fillTexture(_ texture: MTLTexture, color: SIMD4<UInt8>) {
        let width = texture.width
        let height = texture.height
        var pixelData = [UInt8](repeating: 0, count: width * height * 4)
        for index in 0 ..< width * height {
            let base = index * 4
            pixelData[base] = color.x
            pixelData[base + 1] = color.y
            pixelData[base + 2] = color.z
            pixelData[base + 3] = color.w
        }
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

    private func clearDrawable(_ drawable: CAMetalDrawable) {
        guard let commandBuffer = commandQueue.makeCommandBuffer() else { return }
        let renderPass = MTLRenderPassDescriptor()
        renderPass.colorAttachments[0].texture = drawable.texture
        renderPass.colorAttachments[0].loadAction = .clear
        renderPass.colorAttachments[0].storeAction = .store
        renderPass.colorAttachments[0].clearColor = MTLClearColor(red: 0.18, green: 0.18, blue: 0.18, alpha: 1)
        commandBuffer.makeRenderCommandEncoder(descriptor: renderPass)?.endEncoding()
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }
}

struct CompositeCacheKey: Equatable {
    let documentRevision: UInt64
    let layerSignature: [LayerSignature]
    let strokePreviewSignature: StrokePreviewSignature?

    struct LayerSignature: Equatable {
        let layerUUID: UUID
        let pixelRevision: UInt64
        let isVisible: Bool
        let opacity: UInt8
        let blendMode: BlendMode
        let frame: PSDRect
        let stackOrder: Int
    }

    struct StrokePreviewSignature: Equatable {
        let layerID: String
        let phase: StrokeSessionPhase
        let dabCount: Int
        let sampleCount: Int
        let dirtyRegion: EditorDirtyRegion
    }

    init(snapshot: EditorRenderSnapshot, strokePreview: ActiveStrokePreview?) {
        documentRevision = snapshot.documentRevision
        layerSignature = snapshot.layers.map {
            LayerSignature(
                layerUUID: $0.layerUUID,
                pixelRevision: $0.pixelRevision,
                isVisible: $0.isVisible,
                opacity: $0.opacity,
                blendMode: $0.blendMode,
                frame: $0.frame,
                stackOrder: $0.stackOrder
            )
        }
        if let strokePreview, strokePreview.phase == .active {
            strokePreviewSignature = StrokePreviewSignature(
                layerID: strokePreview.plan.layerID,
                phase: strokePreview.phase,
                dabCount: strokePreview.plan.dabCount,
                sampleCount: strokePreview.plan.sampleCount,
                dirtyRegion: strokePreview.plan.dirtyRegion
            )
        } else {
            strokePreviewSignature = nil
        }
    }
}

private struct EditorViewportUniforms {
    var canvasSize: SIMD2<Float>
    var viewSize: SIMD2<Float>
    var scale: Float
    var translation: SIMD2<Float>
    var drawableSize: SIMD2<Float>
}

private struct LayerCompositeUniforms {
    var canvasSize: SIMD2<Float>
    var blendMode: Int32
    var layerOpacity: Float
    var frameRect: SIMD4<Float>
}
