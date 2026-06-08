import Foundation

/// Single undoable pixel edit. Forward/inverse patches are layer-local dirty rectangles.
struct EditorUndoEntry: Equatable, Sendable {
    let id: UUID
    let label: String
    let forwardPatch: LayerPixelPatch
    let inversePatch: LayerPixelPatch
    let affectedLayerIDs: [String]
    let timestamp: Date

    init(
        id: UUID = UUID(),
        label: String,
        forwardPatch: LayerPixelPatch,
        inversePatch: LayerPixelPatch,
        affectedLayerIDs: [String],
        timestamp: Date = Date()
    ) {
        self.id = id
        self.label = label
        self.forwardPatch = forwardPatch
        self.inversePatch = inversePatch
        self.affectedLayerIDs = affectedLayerIDs
        self.timestamp = timestamp
    }
}

/// Minimal stroke undo/redo stack owned by DocumentModel, not the renderer.
struct EditorUndoHistory: Equatable, Sendable {
    private(set) var undoStack: [EditorUndoEntry] = []
    private(set) var redoStack: [EditorUndoEntry] = []

    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }

    mutating func push(_ entry: EditorUndoEntry) {
        undoStack.append(entry)
        redoStack.removeAll()
    }

    mutating func popUndo() -> EditorUndoEntry? {
        guard let entry = undoStack.popLast() else { return nil }
        redoStack.append(entry)
        return entry
    }

    mutating func popRedo() -> EditorUndoEntry? {
        guard let entry = redoStack.popLast() else { return nil }
        undoStack.append(entry)
        return entry
    }

    mutating func clear() {
        undoStack.removeAll()
        redoStack.removeAll()
    }
}
