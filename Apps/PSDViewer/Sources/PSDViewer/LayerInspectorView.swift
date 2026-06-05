import PSDKit
import SwiftUI

struct LayerInspectorView: View {
    @EnvironmentObject private var model: DocumentModel

    @State private var nameDraft = ""
    @State private var opacityPercent: Double = 100

    var body: some View {
        Group {
            if let pixel = model.selectedPixelLayer, let path = model.selectedLayerPath {
                switch model.selectedLayerEditPolicy {
                case .editableRootPixel:
                    editablePixelInspector(pixel, path: path)
                case .readOnly(.nestedPixel):
                    readOnlyPixelInspector(pixel)
                default:
                    readOnlyPixelInspector(pixel)
                }
            } else if let group = model.selectedLayer as? GroupLayer {
                groupInspector(group)
            } else {
                Text("Layer not found")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
            }
        }
    }

    @ViewBuilder
    private func editablePixelInspector(_ layer: PixelLayer, path: LayerPath) -> some View {
        Form {
            Section("Pixel Layer") {
                TextField("Name", text: $nameDraft, onCommit: { commitName(path: path) })
                    .onSubmit { commitName(path: path) }
                HStack {
                    Text("Opacity")
                    Slider(value: $opacityPercent, in: 0 ... 100, step: 1)
                        .onChange(of: opacityPercent) { _ in
                            commitOpacity(path: path)
                        }
                    Text("\(Int(opacityPercent))%")
                        .monospacedDigit()
                        .frame(width: 40, alignment: .trailing)
                }
                LabeledContent("Blend") {
                    Text(BlendModeDisplayName.text(for: layer.blendMode))
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
        .onAppear { syncFromPixelLayer(layer) }
        .onChange(of: model.documentRevision) { _ in
            if model.canEditSelectedLayerInInspector, let current = model.selectedPixelLayer {
                syncFromPixelLayer(current)
            }
        }
        .onChange(of: model.selectedLayerID) { _ in
            if model.canEditSelectedLayerInInspector, let current = model.selectedPixelLayer {
                syncFromPixelLayer(current)
            }
        }
    }

    @ViewBuilder
    private func readOnlyPixelInspector(_ layer: PixelLayer) -> some View {
        Form {
            Section("Pixel Layer") {
                LabeledContent("Name") {
                    Text(layer.name)
                }
                LabeledContent("Opacity") {
                    Text("\(Int(Double(layer.opacity) / 255.0 * 100.0))%")
                        .foregroundStyle(.secondary)
                }
                LabeledContent("Blend") {
                    Text(BlendModeDisplayName.text(for: layer.blendMode))
                        .foregroundStyle(.secondary)
                }
                LabeledContent("Bounds") {
                    Text("\(layer.frame.width)×\(layer.frame.height) @ (\(layer.frame.left), \(layer.frame.top))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Section {
                Text("嵌套图层编辑尚未在本 Viewer 中启用；后续版本将支持组内编辑。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    @ViewBuilder
    private func groupInspector(_ group: GroupLayer) -> some View {
        Form {
            Section("Group") {
                LabeledContent("Name") {
                    Text(group.name.isEmpty ? "—" : group.name)
                }
                LabeledContent("Opacity") {
                    Text("\(Int(Double(group.opacity) / 255.0 * 100.0))%")
                        .foregroundStyle(.secondary)
                }
                LabeledContent("Children") {
                    Text("\(group.children.count)")
                        .foregroundStyle(.secondary)
                }
                LabeledContent("Blend") {
                    Text(BlendModeDisplayName.text(for: group.blendMode))
                        .foregroundStyle(.secondary)
                }
            }
            Section {
                Text("组属性编辑尚未在本 Viewer 中启用。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private func syncFromPixelLayer(_ layer: PixelLayer) {
        nameDraft = layer.name
        opacityPercent = Double(layer.opacity) / 255.0 * 100.0
    }

    private func commitName(path: LayerPath) {
        model.renameLayer(at: path, to: nameDraft)
    }

    private func commitOpacity(path: LayerPath) {
        let value = UInt8(min(255, max(0, Int((opacityPercent / 100.0 * 255.0).rounded()))))
        model.setLayerOpacity(at: path, opacity: value)
    }
}
