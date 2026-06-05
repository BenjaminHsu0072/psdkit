import PSDKit
import SwiftUI

struct LayerInspectorView: View {
    private enum InspectorFocusField: Hashable {
        case pixelName
        case frameLeft
        case frameTop
        case frameWidth
        case frameHeight
        case groupName
    }

    @EnvironmentObject private var model: DocumentModel
    @FocusState private var focusedField: InspectorFocusField?

    @State private var nameDraft = ""
    @State private var opacityPercent: Double = 100
    @State private var blendModeSelection: PSDKit.BlendMode = .normal
    @State private var frameLeft = ""
    @State private var frameTop = ""
    @State private var frameWidth = ""
    @State private var frameHeight = ""
    @State private var groupNameDraft = ""
    @State private var groupOpacityPercent: Double = 100
    @State private var groupBlendModeSelection: PSDKit.BlendMode = .passThrough

    var body: some View {
        Group {
            if let pixel = model.selectedPixelLayer, let path = model.selectedLayerPath {
                switch model.selectedLayerEditPolicy {
                case .editablePixel:
                    editablePixelInspector(pixel, path: path)
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
                    .focused($focusedField, equals: .pixelName)
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
                Picker("Blend", selection: $blendModeSelection) {
                    Text("Normal").tag(PSDKit.BlendMode.normal)
                    Text("Multiply").tag(PSDKit.BlendMode.multiply)
                    Text("Linear Dodge (Add)").tag(PSDKit.BlendMode.add)
                }
                .pickerStyle(.menu)
                .onChange(of: blendModeSelection) { value in
                    model.setLayerBlendMode(at: path, blendMode: value)
                }
                LabeledContent("Bounds") {
                    Text("\(layer.frame.width)×\(layer.frame.height)")
                        .foregroundStyle(.secondary)
                }
            }

            Section("Frame") {
                HStack {
                    TextField("Left", text: $frameLeft)
                        .focused($focusedField, equals: .frameLeft)
                    TextField("Top", text: $frameTop)
                        .focused($focusedField, equals: .frameTop)
                }
                HStack {
                    TextField("Width", text: $frameWidth)
                        .focused($focusedField, equals: .frameWidth)
                    TextField("Height", text: $frameHeight)
                        .focused($focusedField, equals: .frameHeight)
                }
                .textFieldStyle(.roundedBorder)
                Button("Apply Frame") {
                    commitFrame(path: path)
                }
            }
            Section {
                Button("Replace from PNG…") {
                    model.requestReplaceLayerPixelsFromPNG(at: path)
                }
            }
        }
        .formStyle(.grouped)
        .onAppear { syncFromPixelLayer(layer, respectingFocus: false) }
        .onChange(of: model.documentRevision) { _ in
            if model.canEditSelectedLayerInInspector, let current = model.selectedPixelLayer {
                syncFromPixelLayer(current, respectingFocus: true)
            }
        }
        .onChange(of: model.selectedLayerID) { _ in
            focusedField = nil
            if model.canEditSelectedLayerInInspector, let current = model.selectedPixelLayer {
                syncFromPixelLayer(current, respectingFocus: false)
            }
        }
        .onChange(of: focusedField) { newValue in
            if newValue == nil {
                syncFocusedDraftsFromModel()
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
                if let path = model.selectedLayerPath {
                    TextField("Name", text: $groupNameDraft)
                        .focused($focusedField, equals: .groupName)
                        .onSubmit { commitGroupName(path: path) }
                    HStack {
                        Text("Opacity")
                        Slider(value: $groupOpacityPercent, in: 0 ... 100, step: 1)
                            .onChange(of: groupOpacityPercent) { _ in
                                commitGroupOpacity(path: path)
                            }
                        Text("\(Int(groupOpacityPercent))%")
                            .monospacedDigit()
                            .frame(width: 40, alignment: .trailing)
                    }
                    Picker("Blend", selection: $groupBlendModeSelection) {
                        Text("Pass Through").tag(PSDKit.BlendMode.passThrough)
                        Text("Normal").tag(PSDKit.BlendMode.normal)
                        Text("Multiply").tag(PSDKit.BlendMode.multiply)
                        Text("Linear Dodge (Add)").tag(PSDKit.BlendMode.add)
                    }
                    .pickerStyle(.menu)
                    .onChange(of: groupBlendModeSelection) { value in
                        model.setGroupBlendMode(at: path, blendMode: value)
                    }
                } else {
                    LabeledContent("Name") {
                        Text(group.name.isEmpty ? "—" : group.name)
                    }
                    LabeledContent("Opacity") {
                        Text("\(Int(Double(group.opacity) / 255.0 * 100.0))%")
                            .foregroundStyle(.secondary)
                    }
                }
                LabeledContent("Children") {
                    Text("\(group.children.count)")
                        .foregroundStyle(.secondary)
                }
            }
            Section {
                Button("Delete Group…", role: .destructive) {
                    model.requestDeleteSelectedGroup()
                }
                .disabled(!model.canDeleteSelectedGroup)
            }
        }
        .formStyle(.grouped)
        .onAppear { syncFromGroupLayer(group, respectingFocus: false) }
        .onChange(of: model.documentRevision) { _ in
            if let current = model.selectedLayer as? GroupLayer {
                syncFromGroupLayer(current, respectingFocus: true)
            }
        }
        .onChange(of: model.selectedLayerID) { _ in
            focusedField = nil
            if let current = model.selectedLayer as? GroupLayer {
                syncFromGroupLayer(current, respectingFocus: false)
            }
        }
        .onChange(of: focusedField) { newValue in
            if newValue == nil {
                syncFocusedDraftsFromModel()
            }
        }
    }

    private func syncFromPixelLayer(_ layer: PixelLayer, respectingFocus: Bool) {
        if !respectingFocus || focusedField != .pixelName {
            nameDraft = layer.name
        }
        opacityPercent = Double(layer.opacity) / 255.0 * 100.0
        blendModeSelection = layer.blendMode
        if !respectingFocus || !isFrameFieldFocused {
            frameLeft = "\(layer.frame.left)"
            frameTop = "\(layer.frame.top)"
            frameWidth = "\(layer.frame.width)"
            frameHeight = "\(layer.frame.height)"
        }
    }

    private func syncFromGroupLayer(_ group: GroupLayer, respectingFocus: Bool) {
        if !respectingFocus || focusedField != .groupName {
            groupNameDraft = group.name
        }
        groupOpacityPercent = Double(group.opacity) / 255.0 * 100.0
        groupBlendModeSelection = group.blendMode
    }

    private var isFrameFieldFocused: Bool {
        switch focusedField {
        case .frameLeft, .frameTop, .frameWidth, .frameHeight:
            return true
        default:
            return false
        }
    }

    private func syncFocusedDraftsFromModel() {
        if model.canEditSelectedLayerInInspector, let layer = model.selectedPixelLayer {
            syncFromPixelLayer(layer, respectingFocus: false)
        } else if let group = model.selectedLayer as? GroupLayer {
            syncFromGroupLayer(group, respectingFocus: false)
        }
    }

    private func commitName(path: LayerPath) {
        model.renameLayer(at: path, to: nameDraft)
    }

    private func commitOpacity(path: LayerPath) {
        let value = UInt8(min(255, max(0, Int((opacityPercent / 100.0 * 255.0).rounded()))))
        model.setLayerOpacity(at: path, opacity: value)
    }

    private func commitFrame(path: LayerPath) {
        guard let left = Int(frameLeft),
              let top = Int(frameTop),
              let width = Int(frameWidth),
              let height = Int(frameHeight)
        else { return }
        model.setLayerFrame(at: path, left: left, top: top, width: width, height: height)
    }

    private func commitGroupName(path: LayerPath) {
        model.renameGroup(at: path, to: groupNameDraft)
    }

    private func commitGroupOpacity(path: LayerPath) {
        let value = UInt8(min(255, max(0, Int((groupOpacityPercent / 100.0 * 255.0).rounded()))))
        model.setGroupOpacity(at: path, opacity: value)
    }
}
