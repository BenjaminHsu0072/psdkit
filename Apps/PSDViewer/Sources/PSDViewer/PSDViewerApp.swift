import SwiftUI

@main
struct PSDViewerApp: App {
    @StateObject private var model = DocumentModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(model)
                .frame(minWidth: 720, minHeight: 480)
        }
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandGroup(after: .newItem) {
                Button("Open…") { model.presentOpenPanel() }
                    .keyboardShortcut("o", modifiers: .command)
                Button("Save") { model.saveDocument() }
                    .keyboardShortcut("s", modifiers: .command)
                    .disabled(model.document == nil)
            }
        }
    }
}
