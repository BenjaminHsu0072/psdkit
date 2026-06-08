import Foundation

/// Editor state machine: tool, selection, brush parameters, and input session snapshot.
struct EditorState: Equatable, Sendable {
    var selection: EditorSelection = .none
    var activeTool: EditorTool = .inspect
    var brushSettings: BrushSettings = .defaults
    var strokeSession: StrokeSession = StrokeSession()
    var inputDiagnostics: InputDiagnostics = .empty

    var selectedLayerID: String? {
        selection.layerID
    }

    mutating func selectLayer(id: String?) {
        selection = EditorSelection.from(layerID: id)
    }

    mutating func setTool(_ tool: EditorTool) {
        activeTool = tool
    }

    mutating func applyInputResult(_ result: InputHandlingResult) {
        strokeSession = result.session
        inputDiagnostics = result.diagnostics
    }
}
