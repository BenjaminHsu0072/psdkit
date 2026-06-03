import PSDKit
import SwiftUI

struct LayerInspectorView: View {
    @EnvironmentObject private var model: DocumentModel
    let layerIndex: Int

    @State private var nameDraft = ""
    @State private var opacityPercent: Double = 100

    var body: some View {
        Group {
            if let layer = layer(at: layerIndex) {
                Form {
                    Section("Layer") {
                        TextField("Name", text: $nameDraft, onCommit: commitName)
                            .onSubmit(commitName)
                        HStack {
                            Text("Opacity")
                            Slider(value: $opacityPercent, in: 0 ... 100, step: 1)
                                .onChange(of: opacityPercent) { _ in
                                    commitOpacity()
                                }
                            Text("\(Int(opacityPercent))%")
                                .monospacedDigit()
                                .frame(width: 40, alignment: .trailing)
                        }
                        LabeledContent("Blend") {
                            Text(layer.blendMode.rawValue)
                                .foregroundStyle(.secondary)
                        }
                        LabeledContent("Bounds") {
                            Text("\(layer.frame.width)×\(layer.frame.height) @ (\(layer.frame.left), \(layer.frame.top))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .formStyle(.grouped)
                .onAppear { syncFromLayer(layer) }
                .onChange(of: model.documentRevision) { _ in
                    if let layer = layer(at: layerIndex) {
                        syncFromLayer(layer)
                    }
                }
                .onChange(of: layerIndex) { _ in
                    if let layer = layer(at: layerIndex) {
                        syncFromLayer(layer)
                    }
                }
            } else {
                Text("Select a pixel layer")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
            }
        }
    }

    private func layer(at index: Int) -> PixelLayer? {
        guard let document = model.document,
              index >= 0, index < document.root.children.count
        else { return nil }
        return document.root.children[index] as? PixelLayer
    }

    private func syncFromLayer(_ layer: PixelLayer) {
        nameDraft = layer.name
        opacityPercent = Double(layer.opacity) / 255.0 * 100.0
    }

    private func commitName() {
        model.renameLayer(at: layerIndex, to: nameDraft)
    }

    private func commitOpacity() {
        let value = UInt8(min(255, max(0, Int((opacityPercent / 100.0 * 255.0).rounded()))))
        model.setLayerOpacity(at: layerIndex, opacity: value)
    }
}
