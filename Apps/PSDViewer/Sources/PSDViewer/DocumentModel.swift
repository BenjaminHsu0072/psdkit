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
    @Published var selectedLayerIndex: Int?

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
            selectedLayerIndex = doc.root.children.isEmpty ? nil : 0
            errorMessage = nil
            statusMessage = "Loaded \(url.lastPathComponent) — \(doc.root.children.count) layer(s)"
            refreshPreview()
        } catch let error as PSDError {
            document = nil
            fileURL = nil
            previewImage = nil
            selectedLayerIndex = nil
            errorMessage = error.userMessage
            statusMessage = "Failed to open file."
        } catch {
            document = nil
            fileURL = nil
            previewImage = nil
            selectedLayerIndex = nil
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
        } catch let error as PSDError {
            errorMessage = error.userMessage
            statusMessage = "Save failed."
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
        } catch let error as PSDError {
            previewImage = nil
            errorMessage = error.userMessage
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

    func addPixelLayer() {
        guard let document else { return }
        do {
            let w = document.canvasSize.width
            let h = document.canvasSize.height
            var rgba = Data(count: w * h * 4)
            for i in 0 ..< (w * h) {
                rgba[i * 4] = 80
                rgba[i * 4 + 1] = 160
                rgba[i * 4 + 2] = 220
                rgba[i * 4 + 3] = 128
            }
            let layer = try PixelLayer(
                name: "New Layer \(document.root.children.count + 1)",
                frame: PSDRect(left: 0, top: 0, right: w, bottom: h),
                pixels: PixelBuffer(width: w, height: h, rgba: rgba)
            )
            try document.appendPixelLayer(layer)
            selectedLayerIndex = document.root.children.count - 1
            refreshPreview()
            statusMessage = "Added \(layer.name)"
            errorMessage = nil
        } catch let error as PSDError {
            errorMessage = error.userMessage
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func removeSelectedLayer() {
        guard let document, let index = selectedLayerIndex,
              index >= 0, index < document.root.children.count,
              let layer = document.root.children[index] as? PixelLayer
        else {
            statusMessage = "Select a pixel layer to remove."
            return
        }
        do {
            let name = layer.name
            try document.removePixelLayer(layer)
            selectedLayerIndex = document.root.children.isEmpty
                ? nil
                : min(index, document.root.children.count - 1)
            refreshPreview()
            statusMessage = "Removed \(name)"
            errorMessage = nil
        } catch let error as PSDError {
            errorMessage = error.userMessage
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
