import PSDKit
import SwiftUI

@main
struct PSDViewerApp: App {
    @StateObject private var model = DocumentModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(model)
                .frame(minWidth: 800, minHeight: 520)
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Document") { model.newDocument() }
                    .keyboardShortcut("n", modifiers: [.command, .shift])
            }
            CommandGroup(after: .newItem) {
                Button("Open…") { model.presentOpenPanel() }
                    .keyboardShortcut("o", modifiers: .command)
                Button("Generate Standard Test Document…") { model.generateStandardTestDocument() }
                    .keyboardShortcut("g", modifiers: [.command, .shift])
                Button("Save") { model.saveDocument() }
                    .keyboardShortcut("s", modifiers: .command)
                Button("Export…") { model.saveDocumentAs() }
                    .keyboardShortcut("s", modifiers: [.command, .shift])
                Button("Close") {
                    model.requestCloseDocument {
                        NSApplication.shared.keyWindow?.close()
                    }
                }
                .keyboardShortcut("w", modifiers: .command)
                .disabled(model.document == nil)
            }
            CommandGroup(after: .importExport) {
                Button("Import PNG as Layer…") { model.importPNGAsLayer() }
                    .keyboardShortcut("i", modifiers: [.command, .shift])
                    .disabled(model.document == nil)
                Button("Replace Selected Layer from PNG…") { model.requestReplaceSelectedLayerPixelsFromPNG() }
                    .keyboardShortcut("r", modifiers: [.command, .shift])
                    .disabled(model.selectedPixelLayer == nil)
                Divider()
                Button("Compatibility Report…") { model.showCompatibilityReport() }
                    .keyboardShortcut("w", modifiers: [.command, .option, .shift])
                    .disabled(!model.hasCompatibilityDetails)
                Button("Snapshot / Diff…") { model.isShowingSnapshotPanel = true }
                    .keyboardShortcut("d", modifiers: [.command, .shift])
                    .disabled(model.document == nil)
                Button("Manual Validation…") { model.isShowingManualValidationChecklist = true }
                    .keyboardShortcut("m", modifiers: [.command, .shift])
                Button("Photoshop Roundtrip…") { model.isShowingPhotoshopRoundtripAssistant = true }
                    .keyboardShortcut("p", modifiers: [.command, .shift])
                Divider()
                Button("Add Group") { model.addGroup() }
                    .keyboardShortcut("k", modifiers: [.command, .shift])
                    .disabled(model.document == nil)
                Button("Delete Selected Group…") { model.requestDeleteSelectedGroup() }
                    .keyboardShortcut(.delete, modifiers: [.command, .option])
                    .disabled(!model.canDeleteSelectedGroup)
                Button("Toggle Group Collapse") {
                    if let path = model.selectedLayerPath {
                        model.toggleGroupCollapsed(at: path)
                    }
                }
                .keyboardShortcut("\\", modifiers: [.command, .option])
                .disabled(!(model.selectedLayer is GroupLayer))
                Button("Move Selected Layer Up") { model.moveSelectedLayerUp() }
                    .keyboardShortcut(.upArrow, modifiers: [.command, .option])
                    .disabled(!model.canMoveSelectedLayerUp)
                Button("Move Selected Layer Down") { model.moveSelectedLayerDown() }
                    .keyboardShortcut(.downArrow, modifiers: [.command, .option])
                    .disabled(!model.canMoveSelectedLayerDown)
            }
            CommandMenu("Editor") {
                Button("Inspect Tool") { model.setEditorTool(.inspect) }
                    .keyboardShortcut("v", modifiers: [])
                Button("Brush Tool") { model.setEditorTool(.brush) }
                    .keyboardShortcut("b", modifiers: [])
                Button("Eraser Tool") { model.setEditorTool(.eraser) }
                    .keyboardShortcut("e", modifiers: [])
                Button("Hand Tool") { model.setEditorTool(.hand) }
                    .keyboardShortcut("h", modifiers: [])
                Divider()
                Button("Undo Stroke") { model.undoStrokeEdit() }
                    .keyboardShortcut("z", modifiers: .command)
                    .disabled(!model.canUndoStrokeEdit)
                Button("Redo Stroke") { model.redoStrokeEdit() }
                    .keyboardShortcut("z", modifiers: [.command, .shift])
                    .disabled(!model.canRedoStrokeEdit)
            }
        }
    }
}
