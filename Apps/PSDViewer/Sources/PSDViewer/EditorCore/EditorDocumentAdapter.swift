import Foundation
import PSDKit

/// Shields EditorCore from App Shell and UI. No save dialogs, alerts, or Metal textures.
protocol EditorDocumentAdapter: AnyObject {
    var canvasSize: PSDSize { get }
    var documentRevision: UInt64 { get }
    var documentSessionID: UUID { get }

    func setLayerOpacity(id: String, opacity: UInt8) -> EditorCommandResult
    func setLayerBlendMode(id: String, blendMode: BlendMode) -> EditorCommandResult
    func setLayerFrame(id: String, frame: PSDRect) -> EditorCommandResult

    func layerRGBA(layerID: String) throws -> Data
    func replaceLayerRGBA(layerID: String, rgba: Data, width: Int, height: Int) throws -> Bool
    func extractPixelPatch(layerID: String, rect: PSDRect, revision: UInt64) throws -> LayerPixelPatch
    func applyPixelPatch(_ patch: LayerPixelPatch) throws -> LayerPixelPatch
    func recordUndoEntry(_ entry: EditorUndoEntry)
    func popUndoEntry() -> EditorUndoEntry?
    func popRedoEntry() -> EditorUndoEntry?
    var canUndo: Bool { get }
    var canRedo: Bool { get }

    func notifyContentModified()
}

/// PSDKit-backed adapter for tests and App Shell wiring.
final class PSDDocumentEditorAdapter: EditorDocumentAdapter {
    let document: PSDDocument
    let documentSessionID: UUID
    private(set) var documentRevision: UInt64
    private var undoHistory = EditorUndoHistory()

    var canvasSize: PSDSize { document.canvasSize }
    var canUndo: Bool { undoHistory.canUndo }
    var canRedo: Bool { undoHistory.canRedo }

    init(document: PSDDocument, documentSessionID: UUID = UUID(), documentRevision: UInt64 = 0) {
        self.document = document
        self.documentSessionID = documentSessionID
        self.documentRevision = documentRevision
    }

    func setLayerOpacity(id: String, opacity: UInt8) -> EditorCommandResult {
        guard let layer = resolvePixelLayer(id: id) else {
            return .failure(.layerNotFound)
        }
        layer.opacity = opacity
        notifyContentModified()
        return .success
    }

    func setLayerBlendMode(id: String, blendMode: BlendMode) -> EditorCommandResult {
        guard let layer = resolvePixelLayer(id: id) else {
            return .failure(.layerNotFound)
        }
        switch blendMode {
        case .normal, .multiply, .add:
            layer.blendMode = blendMode
            notifyContentModified()
            return .success
        case .passThrough, .unknown:
            return .failure(.unsupportedBlendMode)
        }
    }

    func setLayerFrame(id: String, frame: PSDRect) -> EditorCommandResult {
        guard frame.width > 0, frame.height > 0 else {
            return .failure(.invalidParameter("frame dimensions must be positive"))
        }
        guard let layer = resolvePixelLayer(id: id) else {
            return .failure(.layerNotFound)
        }
        layer.frame = frame
        notifyContentModified()
        return .success
    }

    func layerRGBA(layerID: String) throws -> Data {
        guard let layer = resolvePixelLayer(id: layerID) else {
            throw PixelPatchError.layerNotFound
        }
        return layer.pixels.rgba
    }

    func replaceLayerRGBA(layerID: String, rgba: Data, width: Int, height: Int) throws -> Bool {
        guard let layer = resolvePixelLayer(id: layerID) else { return false }
        layer.pixels = try PixelBuffer(width: width, height: height, rgba: rgba)
        return true
    }

    func extractPixelPatch(layerID: String, rect: PSDRect, revision: UInt64) throws -> LayerPixelPatch {
        guard let layer = resolvePixelLayer(id: layerID) else {
            throw PixelPatchError.layerNotFound
        }
        return try PixelPatchApplier.extractPatch(
            from: layer,
            layerID: layerID,
            rect: rect,
            revision: revision
        )
    }

    func applyPixelPatch(_ patch: LayerPixelPatch) throws -> LayerPixelPatch {
        guard let layer = resolvePixelLayer(id: patch.layerID) else {
            throw PixelPatchError.layerNotFound
        }
        return try PixelPatchApplier.apply(patch: patch, to: layer)
    }

    func recordUndoEntry(_ entry: EditorUndoEntry) {
        undoHistory.push(entry)
    }

    func popUndoEntry() -> EditorUndoEntry? {
        undoHistory.popUndo()
    }

    func popRedoEntry() -> EditorUndoEntry? {
        undoHistory.popRedo()
    }

    func notifyContentModified() {
        document.markContentModified()
        documentRevision += 1
    }

    private func resolvePixelLayer(id: String) -> PixelLayer? {
        guard let path = LayerPath(selectionID: id) else { return nil }
        return LayerListFlattener.resolveLayer(in: document.root, path: path) as? PixelLayer
    }
}

/// In-memory adapter for unit tests without PSD file I/O.
final class MockEditorDocumentAdapter: EditorDocumentAdapter {
    struct LayerRecord: Equatable, Sendable {
        var opacity: UInt8
        var blendMode: BlendMode
        var frame: PSDRect
        var rgba: Data? = nil
        var width: Int = 0
        var height: Int = 0
    }

    var canvasSize: PSDSize
    let documentSessionID: UUID
    private(set) var documentRevision: UInt64
    var layers: [String: LayerRecord]
    private(set) var contentModifiedCount = 0
    private var undoHistory = EditorUndoHistory()

    var canUndo: Bool { undoHistory.canUndo }
    var canRedo: Bool { undoHistory.canRedo }

    init(
        canvasSize: PSDSize = PSDSize(width: 64, height: 64),
        documentSessionID: UUID = UUID(),
        documentRevision: UInt64 = 0,
        layers: [String: LayerRecord] = [:]
    ) {
        self.canvasSize = canvasSize
        self.documentSessionID = documentSessionID
        self.documentRevision = documentRevision
        self.layers = layers
    }

    func setLayerOpacity(id: String, opacity: UInt8) -> EditorCommandResult {
        guard var record = layers[id] else { return .failure(.layerNotFound) }
        record.opacity = opacity
        layers[id] = record
        notifyContentModified()
        return .success
    }

    func setLayerBlendMode(id: String, blendMode: BlendMode) -> EditorCommandResult {
        guard var record = layers[id] else { return .failure(.layerNotFound) }
        switch blendMode {
        case .normal, .multiply, .add:
            record.blendMode = blendMode
            layers[id] = record
            notifyContentModified()
            return .success
        case .passThrough, .unknown:
            return .failure(.unsupportedBlendMode)
        }
    }

    func setLayerFrame(id: String, frame: PSDRect) -> EditorCommandResult {
        guard frame.width > 0, frame.height > 0 else {
            return .failure(.invalidParameter("frame dimensions must be positive"))
        }
        guard var record = layers[id] else { return .failure(.layerNotFound) }
        record.frame = frame
        layers[id] = record
        notifyContentModified()
        return .success
    }

    func layerRGBA(layerID: String) throws -> Data {
        guard let record = layers[layerID], let rgba = record.rgba else {
            throw PixelPatchError.layerNotFound
        }
        return rgba
    }

    func replaceLayerRGBA(layerID: String, rgba: Data, width: Int, height: Int) throws -> Bool {
        guard var record = layers[layerID] else { return false }
        record.rgba = rgba
        record.width = width
        record.height = height
        layers[layerID] = record
        return true
    }

    func extractPixelPatch(layerID: String, rect: PSDRect, revision: UInt64) throws -> LayerPixelPatch {
        guard let record = layers[layerID], let rgba = record.rgba else {
            throw PixelPatchError.layerNotFound
        }
        return try PixelPatchApplier.extractPatch(
            from: rgba,
            width: record.width,
            height: record.height,
            layerID: layerID,
            rect: rect,
            revision: revision
        )
    }

    func applyPixelPatch(_ patch: LayerPixelPatch) throws -> LayerPixelPatch {
        guard var record = layers[patch.layerID], var rgba = record.rgba else {
            throw PixelPatchError.layerNotFound
        }
        let beforeRevision = EditorPixelRevisionDigest.digest(rgba: rgba)
        let inverse = try PixelPatchApplier.extractPatch(
            from: rgba,
            width: record.width,
            height: record.height,
            layerID: patch.layerID,
            rect: patch.rect,
            revision: beforeRevision
        )
        try validate(patch: patch, width: record.width, height: record.height)
        for row in 0 ..< patch.rect.height {
            let srcRow = row * patch.rect.width * 4
            let dstRow = (patch.rect.top + row) * record.width * 4 + patch.rect.left * 4
            let byteCount = patch.rect.width * 4
            rgba.replaceSubrange(dstRow ..< dstRow + byteCount, with: patch.rgba[srcRow ..< srcRow + byteCount])
        }
        record.rgba = rgba
        layers[patch.layerID] = record
        return inverse
    }

    func recordUndoEntry(_ entry: EditorUndoEntry) {
        undoHistory.push(entry)
    }

    func popUndoEntry() -> EditorUndoEntry? {
        undoHistory.popUndo()
    }

    func popRedoEntry() -> EditorUndoEntry? {
        undoHistory.popRedo()
    }

    func notifyContentModified() {
        contentModifiedCount += 1
        documentRevision += 1
    }

    private func validate(patch: LayerPixelPatch, width: Int, height: Int) throws {
        guard patch.rect.left >= 0, patch.rect.top >= 0,
              patch.rect.right <= width, patch.rect.bottom <= height,
              patch.rgba.count == patch.expectedByteCount
        else {
            throw PixelPatchError.rectOutOfBounds
        }
    }
}
