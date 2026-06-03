import AppKit
import Foundation
import PSDKit
import SwiftUI

@MainActor
final class DocumentModel: ObservableObject {
    @Published private(set) var document: PSDDocument?
    @Published private(set) var fileURL: URL?
    @Published private(set) var previewImage: NSImage?
    @Published private(set) var statusMessage = "Open a PSD file to begin."
    @Published private(set) var errorMessage: String?

    var layerNames: [String] {
        guard let document else { return [] }
        return document.root.children.map(\.name)
    }

    func presentOpenPanel() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.data]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.title = "Open PSD"
        panel.message = "8-bit RGB(A) bitmap layers (PSD v1)"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        open(url: url)
    }

    func open(url: URL) {
        do {
            let doc = try PSDDocument.load(url: url)
            document = doc
            fileURL = url
            errorMessage = nil
            statusMessage = "Loaded \(url.lastPathComponent) — \(doc.root.children.count) layer(s)"
            refreshPreview()
        } catch {
            document = nil
            fileURL = nil
            previewImage = nil
            errorMessage = error.localizedDescription
            statusMessage = "Failed to open file."
        }
    }

    func saveDocument() {
        guard let document, let fileURL else { return }
        do {
            try document.save(to: fileURL)
            statusMessage = "Saved \(fileURL.lastPathComponent)"
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
            statusMessage = "Save failed."
        }
    }

    func refreshPreview() {
        guard let document else {
            previewImage = nil
            return
        }
        do {
            previewImage = try PreviewRenderer.makeImage(from: document)
        } catch {
            previewImage = nil
            errorMessage = error.localizedDescription
        }
    }

    func toggleLayerVisibility(at index: Int) {
        guard let document, index >= 0, index < document.root.children.count else { return }
        let layer = document.root.children[index]
        layer.isVisible.toggle()
        document.markContentModified()
        refreshPreview()
        statusMessage = "\(layer.name) visibility: \(layer.isVisible ? "on" : "off")"
    }
}
