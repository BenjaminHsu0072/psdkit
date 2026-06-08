import Foundation
import Metal
import PSDKit

/// Stable cache key for a layer's GPU texture. Property-only changes are excluded.
struct LayerTextureCacheKey: Hashable, Equatable, Sendable {
    let layerUUID: UUID
    let pixelRevision: UInt64
    let pixelWidth: Int
    let pixelHeight: Int

    init(layerUUID: UUID, pixelRevision: UInt64, pixelWidth: Int, pixelHeight: Int) {
        self.layerUUID = layerUUID
        self.pixelRevision = pixelRevision
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
    }

    init?(layer: EditorLayerSnapshot, payload: EditorSnapshotPixelProvider.PixelPayload) {
        guard layer.kind == .pixel else { return nil }
        self.init(
            layerUUID: layer.layerUUID,
            pixelRevision: layer.pixelRevision,
            pixelWidth: payload.width,
            pixelHeight: payload.height
        )
    }
}

/// Snapshot scope used to detect document/canvas switches that must not reuse stale textures.
struct LayerTextureCacheScope: Equatable, Sendable {
    let documentSessionID: UUID
    let canvasSize: PSDSize
}

struct LayerTextureRecord: Equatable {
    let key: LayerTextureCacheKey
    let pixelRevision: UInt64
    let size: PSDSize
    let dirtyRegion: EditorDirtyRegion
    let lastUploadedAt: Date

    static func == (lhs: LayerTextureRecord, rhs: LayerTextureRecord) -> Bool {
        lhs.key == rhs.key
            && lhs.pixelRevision == rhs.pixelRevision
            && lhs.size == rhs.size
            && lhs.dirtyRegion == rhs.dirtyRegion
    }
}

struct LayerTextureCacheDiagnostics: Equatable, Sendable {
    var textureCount: Int = 0
    var hitCount: UInt64 = 0
    var missCount: UInt64 = 0
    var uploadCount: UInt64 = 0
    var pruneCount: UInt64 = 0
    var clearCount: UInt64 = 0
    var lastInvalidationReasons: [LayerTextureInvalidationReason] = []
    var estimatedMemoryBytes: UInt64 = 0

    var summaryLine: String {
        "tex=\(textureCount) hit=\(hitCount) miss=\(missCount) up=\(uploadCount) prune=\(pruneCount)"
    }
}

/// Manages PSD layer → Metal texture uploads keyed by layer identity and pixel revision.
final class LayerTextureCache {
    private let device: MTLDevice
    private var textures: [LayerTextureCacheKey: MTLTexture] = [:]
    private var records: [LayerTextureCacheKey: LayerTextureRecord] = [:]
    private var scope: LayerTextureCacheScope?
    private(set) var diagnostics = LayerTextureCacheDiagnostics()

    private let maxInvalidationHistory = 16

    init(device: MTLDevice) {
        self.device = device
    }

    func prepareForSnapshot(_ snapshot: EditorRenderSnapshot) {
        let newScope = LayerTextureCacheScope(
            documentSessionID: snapshot.documentSessionID,
            canvasSize: snapshot.canvasSize
        )
        defer { scope = newScope }

        guard let scope else { return }
        if scope.documentSessionID != newScope.documentSessionID {
            clear(reason: .documentReloaded)
            return
        }
        if scope.canvasSize != newScope.canvasSize {
            recordInvalidation(.canvasSizeChanged)
        }
    }

    func texture(
        for layer: EditorLayerSnapshot,
        payload: EditorSnapshotPixelProvider.PixelPayload
    ) throws -> MTLTexture {
        guard let key = LayerTextureCacheKey(layer: layer, payload: payload) else {
            throw EditorMetalRendererError.textureAllocationFailed
        }

        if let cached = textures[key] {
            diagnostics.hitCount += 1
            refreshDiagnostics()
            return cached
        }

        if let staleKey = textures.keys.first(where: { $0.layerUUID == key.layerUUID && $0 != key }) {
            if staleKey.pixelRevision != key.pixelRevision {
                recordInvalidation(.layerPixelRevisionChanged)
            } else if staleKey.pixelWidth != key.pixelWidth || staleKey.pixelHeight != key.pixelHeight {
                recordInvalidation(.layerSizeChanged)
            }
            textures.removeValue(forKey: staleKey)
            records.removeValue(forKey: staleKey)
        }

        let texture = try uploadTexture(payload: payload)
        textures[key] = texture
        records[key] = LayerTextureRecord(
            key: key,
            pixelRevision: key.pixelRevision,
            size: PSDSize(width: payload.width, height: payload.height),
            dirtyRegion: .fullLayer,
            lastUploadedAt: Date()
        )
        diagnostics.missCount += 1
        diagnostics.uploadCount += 1
        refreshDiagnostics()
        return texture
    }

    func prune(keeping layerKeys: Set<LayerTextureCacheKey>) {
        let staleKeys = textures.keys.filter { !layerKeys.contains($0) }
        guard !staleKeys.isEmpty else { return }

        for key in staleKeys {
            textures.removeValue(forKey: key)
            records.removeValue(forKey: key)
            recordInvalidation(.layerRemoved)
        }
        diagnostics.pruneCount += 1
        refreshDiagnostics()
    }

    func clear(reason: LayerTextureInvalidationReason) {
        guard !textures.isEmpty else {
            recordInvalidation(reason)
            return
        }
        textures.removeAll(keepingCapacity: false)
        records.removeAll(keepingCapacity: false)
        diagnostics.clearCount += 1
        recordInvalidation(reason)
        refreshDiagnostics()
    }

    func record(for key: LayerTextureCacheKey) -> LayerTextureRecord? {
        records[key]
    }

    private func uploadTexture(payload: EditorSnapshotPixelProvider.PixelPayload) throws -> MTLTexture {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm,
            width: payload.width,
            height: payload.height,
            mipmapped: false
        )
        descriptor.usage = [.shaderRead]
        guard let texture = device.makeTexture(descriptor: descriptor) else {
            throw EditorMetalRendererError.textureAllocationFailed
        }

        let bytesPerRow = payload.width * 4
        payload.data.withUnsafeBytes { raw in
            guard let baseAddress = raw.baseAddress else { return }
            texture.replace(
                region: MTLRegion(
                    origin: MTLOrigin(x: 0, y: 0, z: 0),
                    size: MTLSize(width: payload.width, height: payload.height, depth: 1)
                ),
                mipmapLevel: 0,
                withBytes: baseAddress,
                bytesPerRow: bytesPerRow
            )
        }
        return texture
    }

    private func recordInvalidation(_ reason: LayerTextureInvalidationReason) {
        diagnostics.lastInvalidationReasons.append(reason)
        if diagnostics.lastInvalidationReasons.count > maxInvalidationHistory {
            diagnostics.lastInvalidationReasons.removeFirst(
                diagnostics.lastInvalidationReasons.count - maxInvalidationHistory
            )
        }
    }

    private func refreshDiagnostics() {
        diagnostics.textureCount = textures.count
        diagnostics.estimatedMemoryBytes = textures.reduce(into: 0) { total, entry in
            let texture = entry.value
            total += UInt64(texture.width * texture.height * 4)
        }
    }
}
