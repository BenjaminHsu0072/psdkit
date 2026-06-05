import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var model: DocumentModel

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            previewPane
        }
        .navigationTitle(model.fileURL?.lastPathComponent ?? "PSDViewer")
        .toolbar {
            ToolbarItemGroup {
                Button("New") { model.newDocument() }
                Button("Open") { model.presentOpenPanel() }
                Button("Save") { model.saveDocument() }
                    .disabled(model.document == nil)
                Button("Export…") { model.saveDocumentAs() }
                    .disabled(model.document == nil)
                Divider()
                Button {
                    model.importPNGAsLayer()
                } label: {
                    Label("Import PNG", systemImage: "photo.on.rectangle.angled")
                }
                .disabled(model.document == nil)
                Button {
                    model.addPixelLayer()
                } label: {
                    Label("Add Layer", systemImage: "plus.square.on.square")
                }
                .disabled(model.document == nil)
                Button {
                    model.removeSelectedLayer()
                } label: {
                    Label("Remove", systemImage: "minus.square")
                }
                .disabled(model.document == nil || !model.canRemoveSelectedLayer)
            }
        }
    }

    private var sidebar: some View {
        VStack(spacing: 0) {
            layerList
            Divider()
            layerInspector
        }
        .frame(minWidth: 240)
    }

    private var layerList: some View {
        List(selection: $model.selectedLayerID) {
            if model.layerItems.isEmpty {
                Text("No document")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(model.layerItems) { item in
                    HStack(spacing: 6) {
                        Button {
                            model.toggleLayerVisibility(at: item.path)
                        } label: {
                            Image(systemName: item.isVisible ? "eye" : "eye.slash")
                        }
                        .buttonStyle(.borderless)
                        .disabled(!LayerViewerPolicy.canToggleVisibility(for: item))
                        .help(LayerViewerPolicy.canToggleVisibility(for: item)
                            ? "Toggle visibility"
                            : "仅根级像素层可切换可见性")

                        Image(systemName: item.displayKind == .group ? "folder.fill" : "square.stack.3d.up.fill")
                            .foregroundStyle(item.displayKind == .group ? .secondary : .primary)
                            .font(.caption)
                            .frame(width: 14)

                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 4) {
                                Text(item.name)
                                    .lineLimit(1)
                                if item.displayKind == .group {
                                    Text("组")
                                        .font(.caption2)
                                        .padding(.horizontal, 4)
                                        .padding(.vertical, 1)
                                        .background(.quaternary, in: Capsule())
                                }
                            }
                            Text(layerSubtitle(for: item))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.leading, CGFloat(item.depth) * 14)
                    .tag(item.id)
                }
            }
        }
        .listStyle(.sidebar)
        .frame(minHeight: 160)
        .id(model.documentRevision)
    }

    private func layerSubtitle(for item: LayerListItem) -> String {
        switch item.displayKind {
        case .group:
            let count = item.childCount ?? 0
            return count == 0 ? "Group · empty" : "Group · \(count) layer\(count == 1 ? "" : "s")"
        case .pixel:
            return "Opacity \(Int(item.opacity))"
        }
    }

    private var layerInspector: some View {
        Group {
            if model.selectedLayerPath != nil {
                LayerInspectorView()
            } else {
                Text("Select a layer to view properties.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding()
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .frame(minHeight: 180, maxHeight: 280)
    }

    private var previewPane: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let error = model.errorMessage {
                Text(error)
                    .foregroundStyle(.red)
                    .font(.callout)
            }
            if let warning = model.compatibilityWarningMessage {
                Label(warning, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text(model.statusMessage)
                .font(.callout)
                .foregroundStyle(.secondary)

            if let image = model.previewImage {
                ScrollView([.horizontal, .vertical]) {
                    Image(nsImage: image)
                        .interpolation(.none)
                        .background(checkerboard)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "photo")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                    Text("No Preview")
                        .font(.headline)
                    Text("Open an 8-bit RGB PSD file.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding()
    }

    private var checkerboard: some View {
        Canvas { context, size in
            let tile: CGFloat = 8
            for y in stride(from: 0, to: size.height, by: tile) {
                for x in stride(from: 0, to: size.width, by: tile) {
                    let dark = (Int(x / tile) + Int(y / tile)) % 2 == 0
                    context.fill(
                        Path(CGRect(x: x, y: y, width: tile, height: tile)),
                        with: .color(dark ? .gray.opacity(0.25) : .white.opacity(0.5))
                    )
                }
            }
        }
    }
}
