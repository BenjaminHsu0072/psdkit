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
                .disabled(model.document == nil || model.selectedLayerIndex == nil)
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
        List(selection: $model.selectedLayerIndex) {
            if model.layerItems.isEmpty {
                Text("No document")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(model.layerItems) { item in
                    HStack {
                        Button {
                            model.toggleLayerVisibility(at: item.id)
                        } label: {
                            Image(systemName: item.isVisible ? "eye" : "eye.slash")
                        }
                        .buttonStyle(.borderless)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.name)
                                .lineLimit(1)
                            Text("Opacity \(Int(item.opacity))")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .tag(item.id)
                }
            }
        }
        .listStyle(.sidebar)
        .frame(minHeight: 160)
        .id(model.documentRevision)
    }

    private var layerInspector: some View {
        Group {
            if let index = model.selectedLayerIndex {
                LayerInspectorView(layerIndex: index)
            } else {
                Text("Select a layer to edit name and opacity.")
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
                ContentUnavailableView(
                    "No Preview",
                    systemImage: "photo",
                    description: Text("Open an 8-bit RGB PSD file.")
                )
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
