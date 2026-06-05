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
    /// Shown when `compatibilityReport` indicates lossy import (session-only; not saved to PSD).
    @Published private(set) var compatibilityWarningMessage: String?
    /// Layer path selection id for sidebar `List` (e.g. `"0"`, `"1/0"`).
    @Published var selectedLayerID: String?
    /// Bumped when layer metadata changes so SwiftUI refreshes the sidebar.
    @Published private(set) var documentRevision = 0

    var layerItems: [LayerListItem] {
        guard let document else { return [] }
        return LayerListFlattener.flatten(root: document.root)
    }

    var selectedLayerPath: LayerPath? {
        guard let selectedLayerID else { return nil }
        return LayerPath(selectionID: selectedLayerID)
    }

    var selectedLayer: (any LayerProtocol)? {
        guard let document, let path = selectedLayerPath else { return nil }
        return LayerListFlattener.resolveLayer(in: document.root, path: path)
    }

    var selectedPixelLayer: PixelLayer? {
        selectedLayer as? PixelLayer
    }

    var selectedLayerEditPolicy: LayerViewerEditPolicy? {
        guard let path = selectedLayerPath, let layer = selectedLayer else { return nil }
        return LayerViewerPolicy.editPolicy(path: path, layer: layer)
    }

    var canEditSelectedLayerInInspector: Bool {
        selectedLayerEditPolicy?.isEditable == true
    }

    /// Root-level pixel layer only (matches `removePixelLayer` persistence).
    var canRemoveSelectedLayer: Bool {
        canEditSelectedLayerInInspector
    }

    func newDocument(width: Int = 256, height: Int = 256) {
        do {
            let doc = try PSDDocument.create(width: width, height: height)
            document = doc
            fileURL = nil
            selectedLayerID = nil
            errorMessage = nil
            compatibilityWarningMessage = nil
            statusMessage = "New document \(width)×\(height)"
            bumpDocument()
            refreshPreview()
        } catch let error as PSDError {
            errorMessage = error.userMessage
        } catch {
            errorMessage = error.localizedDescription
        }
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
            selectedLayerID = LayerListFlattener.flatten(root: doc.root).first?.id
            errorMessage = nil
            compatibilityWarningMessage = Self.compatibilitySummary(from: doc.compatibilityReport)
            statusMessage = "Loaded \(url.lastPathComponent) — \(doc.root.children.count) layer(s)"
            bumpDocument()
            refreshPreview()
        } catch let error as PSDError {
            document = nil
            fileURL = nil
            previewImage = nil
            selectedLayerID = nil
            compatibilityWarningMessage = nil
            errorMessage = error.userMessage
            statusMessage = "Failed to open file."
        } catch {
            document = nil
            fileURL = nil
            previewImage = nil
            selectedLayerID = nil
            compatibilityWarningMessage = nil
            errorMessage = error.localizedDescription
            statusMessage = "Failed to open file."
        }
    }

    func saveDocument() {
        guard let document else { return }
        if let fileURL {
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
        } else {
            saveDocumentAs()
        }
    }

    func saveDocumentAs() {
        guard let document else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.data]
        panel.nameFieldStringValue = "Untitled.psd"
        panel.title = "Export PSD"
        panel.message = "Save 8-bit RGB PSD"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try document.save(to: url)
            fileURL = url
            statusMessage = "Exported \(url.lastPathComponent)"
            errorMessage = nil
        } catch let error as PSDError {
            errorMessage = error.userMessage
            statusMessage = "Export failed."
        } catch {
            errorMessage = error.localizedDescription
            statusMessage = "Export failed."
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

    func toggleLayerVisibility(at path: LayerPath) {
        guard let item = layerItems.first(where: { $0.path == path }) else { return }
        guard LayerViewerPolicy.canToggleVisibility(for: item) else {
            statusMessage = "仅支持切换根级像素层的可见性。"
            return
        }
        guard let document,
              let layer = LayerListFlattener.resolveLayer(in: document.root, path: path)
        else { return }
        layer.isVisible.toggle()
        markDirty()
        statusMessage = "\(layer.name) visibility: \(layer.isVisible ? "on" : "off")"
    }

    func renameLayer(at path: LayerPath, to name: String) {
        guard let document,
              let layer = LayerListFlattener.resolveLayer(in: document.root, path: path) as? PixelLayer,
              LayerViewerPolicy.editPolicy(path: path, layer: layer) == .editableRootPixel
        else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        layer.name = trimmed
        markDirty()
        statusMessage = "Renamed layer to \"\(trimmed)\""
    }

    func setLayerOpacity(at path: LayerPath, opacity: UInt8) {
        guard let document,
              let layer = LayerListFlattener.resolveLayer(in: document.root, path: path) as? PixelLayer,
              LayerViewerPolicy.editPolicy(path: path, layer: layer) == .editableRootPixel
        else { return }
        layer.opacity = opacity
        markDirty()
        statusMessage = "\(layer.name) opacity: \(opacity)"
    }

    func importPNGAsLayer() {
        guard let document else { return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.title = "Import PNG"
        panel.message = "Adds image as a new pixel layer at top-left"
        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            let (rgba, width, height) = try ImageImport.loadRGBA(from: url)
            let baseName = url.deletingPathExtension().lastPathComponent
            let layer = try PixelLayer(
                name: baseName.isEmpty ? "Imported" : baseName,
                frame: PSDRect(left: 0, top: 0, right: width, bottom: height),
                pixels: PixelBuffer(width: width, height: height, rgba: rgba)
            )
            try document.appendPixelLayer(layer)
            selectedLayerID = LayerPath(indices: [document.root.children.count - 1]).selectionID
            markDirty()
            statusMessage = "Imported \(url.lastPathComponent) (\(width)×\(height))"
            errorMessage = nil
        } catch let error as PSDError {
            errorMessage = error.userMessage
            statusMessage = "Import failed."
        } catch {
            errorMessage = error.localizedDescription
            statusMessage = "Import failed."
        }
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
            selectedLayerID = LayerPath(indices: [document.root.children.count - 1]).selectionID
            markDirty()
            statusMessage = "Added \(layer.name)"
            errorMessage = nil
        } catch let error as PSDError {
            errorMessage = error.userMessage
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func removeSelectedLayer() {
        guard let document, let layer = selectedPixelLayer,
              let path = selectedLayerPath, path.indices.count == 1
        else {
            statusMessage = selectedLayer is GroupLayer
                ? "Select a root pixel layer to remove."
                : "Select a pixel layer to remove."
            return
        }
        do {
            let name = layer.name
            try document.removePixelLayer(layer)
            let removedIndex = path.indices[0]
            let newCount = document.root.children.count
            selectedLayerID = newCount == 0
                ? nil
                : LayerPath(indices: [min(removedIndex, newCount - 1)]).selectionID
            markDirty()
            statusMessage = "Removed \(name)"
            errorMessage = nil
        } catch let error as PSDError {
            errorMessage = error.userMessage
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func markDirty() {
        document?.markContentModified()
        bumpDocument()
        refreshPreview()
    }

    private func bumpDocument() {
        documentRevision += 1
    }

    /// User-facing summary for Viewer; `nil` when the opened PSD is fully within the supported subset.
    static func compatibilitySummary(from report: PSDCompatibilityReport) -> String? {
        guard report.hasLossyChanges || !report.issues.isEmpty else { return nil }
        var text = "部分 PSD 特性不受支持，已降级、忽略或丢弃。"
        let count = report.issues.count
        if count > 1 {
            text += "（\(count) 项警告）"
        } else if count == 1, let first = report.issues.first {
            text += " \(first.message)"
        }
        return text
    }
}
