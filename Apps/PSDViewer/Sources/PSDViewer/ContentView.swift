import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var model: DocumentModel

    var body: some View {
        NavigationSplitView {
            layerList
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
                Divider()
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

    private var layerList: some View {
        List(selection: $model.selectedLayerIndex) {
            if model.layerNames.isEmpty {
                Text("No document")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array(model.layerNames.enumerated()), id: \.offset) { index, name in
                    HStack {
                        Button {
                            model.toggleLayerVisibility(at: index)
                        } label: {
                            Image(systemName: visibilityIcon(at: index))
                        }
                        .buttonStyle(.borderless)
                        Text(name)
                    }
                    .tag(index)
                }
            }
        }
        .listStyle(.sidebar)
        .frame(minWidth: 200)
    }

    private func visibilityIcon(at index: Int) -> String {
        guard let document = model.document, index < document.root.children.count else {
            return "eye.slash"
        }
        return document.root.children[index].isVisible ? "eye" : "eye.slash"
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
