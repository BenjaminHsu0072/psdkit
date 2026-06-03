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
                Button("Save") { model.saveDocument() }
                    .keyboardShortcut("s", modifiers: .command)
                Button("Export…") { model.saveDocumentAs() }
                    .keyboardShortcut("s", modifiers: [.command, .shift])
            }
            CommandGroup(after: .importExport) {
                Button("Import PNG as Layer…") { model.importPNGAsLayer() }
                    .keyboardShortcut("i", modifiers: [.command, .shift])
                    .disabled(model.document == nil)
            }
        }
    }
}
