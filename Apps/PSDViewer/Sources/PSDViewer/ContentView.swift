import PSDKit
import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var model: DocumentModel
    @Environment(\.dismiss) private var dismiss

    @State private var selectedMoveDestinationID = "root"
    @State private var snapshotLabelDraft = "Before"

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            previewPane
        }
        .background(
            WindowCloseGuardView(model: model)
                .frame(width: 0, height: 0)
        )
        .navigationTitle(model.navigationTitle)
        .toolbar {
            ToolbarItemGroup {
                Button("New") { model.newDocument() }
                Button("Open") { model.presentOpenPanel() }
                Button {
                    model.generateStandardTestDocument()
                } label: {
                    Label("Generate Standard", systemImage: "doc.badge.plus")
                }
                Button("Save") { model.saveDocument() }
                    .disabled(model.document == nil)
                Button("Export…") { model.saveDocumentAs() }
                    .disabled(model.document == nil)
                Button("Close") {
                    model.requestCloseDocument { dismiss() }
                }
                .disabled(model.document == nil)
                Button("Compatibility Report…") { model.showCompatibilityReport() }
                    .disabled(!model.hasCompatibilityDetails)
                Button("Snapshot / Diff…") { model.isShowingSnapshotPanel = true }
                    .disabled(model.document == nil)
                Button("Manual Validation…") { model.isShowingManualValidationChecklist = true }
                Button("Photoshop Roundtrip…") { model.isShowingPhotoshopRoundtripAssistant = true }

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
                    model.addGroup()
                } label: {
                    Label("Add Group", systemImage: "folder.badge.plus")
                }
                .disabled(model.document == nil)
                Button {
                    model.removeSelectedLayer()
                } label: {
                    Label("Remove Layer", systemImage: "minus.square")
                }
                .disabled(model.document == nil || !model.canRemoveSelectedLayer)
                Button("Delete Group…") {
                    model.requestDeleteSelectedGroup()
                }
                .disabled(model.document == nil || !model.canDeleteSelectedGroup)
                Button("Toggle Group Collapse") {
                    if let path = model.selectedLayerPath {
                        model.toggleGroupCollapsed(at: path)
                    }
                }
                .disabled(!(model.selectedLayer is GroupLayer))
                Button("Move Up") { model.moveSelectedLayerUp() }
                    .disabled(!model.canMoveSelectedLayerUp)
                Button("Move Down") { model.moveSelectedLayerDown() }
                    .disabled(!model.canMoveSelectedLayerDown)
            }
        }
        .alert("Lossy Save Confirmation", isPresented: $model.isShowingLossySaveConfirmation) {
            Button("View Details") {
                model.showCompatibilityReport()
            }
            Button("Cancel Save", role: .cancel) {
                model.cancelLossySave()
            }
            Button("Continue Save") {
                model.continueLossySave()
            }
        } message: {
            Text("This PSD includes unsupported features that were downgraded or dropped on load.")
        }
        .alert("Unsaved Changes", isPresented: $model.isShowingUnsavedCloseConfirmation) {
            Button("Cancel", role: .cancel) {
                model.cancelCloseDocument()
            }
            Button("Close Without Saving", role: .destructive) {
                model.continueCloseWithoutSaving()
            }
            Button("Save And Close") {
                model.saveAndCloseDocument()
            }
        } message: {
            Text("The current document has unsaved edits.")
        }
        .alert("Delete Group", isPresented: $model.isShowingDeleteGroupConfirmation) {
            Button("Cancel", role: .cancel) {
                model.cancelDeleteSelectedGroup()
            }
            Button("Delete", role: .destructive) {
                model.confirmDeleteSelectedGroup()
            }
        } message: {
            Text("Deleting a group removes all descendant layers.")
        }
        .alert("Replace Pixels Size Policy", isPresented: $model.isShowingReplacePixelSizePolicyDialog) {
            Button("Keep Existing Frame") {
                model.confirmReplaceLayerPixels(policy: .keepExistingFrame)
            }
            Button("Match PNG Size") {
                model.confirmReplaceLayerPixels(policy: .matchImageSize)
            }
            Button("Cancel", role: .cancel) {
                model.cancelReplaceLayerPixels()
            }
        } message: {
            Text("Target: \(model.replacePolicyTargetLayerName ?? "Layer"). Choose replacement sizing strategy.")
        }
        .sheet(isPresented: $model.isShowingCompatibilityReport) {
            compatibilityReportSheet
        }
        .sheet(isPresented: $model.isShowingSnapshotPanel) {
            snapshotPanel
        }
        .sheet(isPresented: $model.isShowingManualValidationChecklist) {
            manualValidationChecklistSheet
        }
        .sheet(isPresented: $model.isShowingPhotoshopRoundtripAssistant) {
            photoshopRoundtripSheet
        }
        .onAppear {
            selectedMoveDestinationID = model.selectedGroupDestinationID
        }
        .onChange(of: model.selectedLayerID) { _ in
            selectedMoveDestinationID = model.selectedGroupDestinationID
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
                        if item.displayKind == .group {
                            Button {
                                model.toggleGroupCollapsed(at: item.path)
                            } label: {
                                Image(systemName: model.isGroupCollapsed(at: item.path) ? "chevron.right" : "chevron.down")
                            }
                            .buttonStyle(.borderless)
                            .frame(width: 14)
                        } else {
                            Color.clear.frame(width: 14, height: 14)
                        }

                        Button {
                            model.toggleLayerVisibility(at: item.path)
                        } label: {
                            Image(systemName: item.isVisible ? "eye" : "eye.slash")
                        }
                        .buttonStyle(.borderless)
                        .disabled(!LayerViewerPolicy.canToggleVisibility(for: item))
                        .help(LayerViewerPolicy.canToggleVisibility(for: item)
                            ? "Toggle visibility"
                            : "Select a pixel layer to toggle visibility")

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
                    .contextMenu {
                        if item.displayKind == .pixel {
                            Button("Replace from PNG…") {
                                model.requestReplaceLayerPixelsFromPNG(at: item.path)
                            }
                            Button("Delete Layer", role: .destructive) {
                                model.selectedLayerID = item.id
                                model.removeSelectedLayer()
                            }
                        } else {
                            Button("Delete Group…", role: .destructive) {
                                model.selectedLayerID = item.id
                                model.requestDeleteSelectedGroup()
                            }
                        }
                    }
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
        .frame(minHeight: 180, maxHeight: 320)
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
            Text(model.statusSummary)
                .font(.caption)
                .foregroundStyle(.secondary)
            moveControls

            if let image = model.previewImage {
                let imagePixelSize = CGSize(width: image.size.width, height: image.size.height)
                ScrollView([.horizontal, .vertical]) {
                    ZStack(alignment: .topLeading) {
                        Image(nsImage: image)
                            .interpolation(.none)
                            .background(checkerboard)
                        if model.canEditSelectedLayerInInspector,
                           let layer = model.selectedPixelLayer,
                           let path = model.selectedLayerPath
                        {
                            SelectedLayerFrameOverlay(
                                layer: layer,
                                path: path,
                                imagePixelSize: imagePixelSize,
                                displayedSize: imagePixelSize
                            )
                        }
                    }
                    .overlay {
                        Rectangle()
                            .stroke(Color.secondary.opacity(0.35), lineWidth: 1)
                    }
                    .padding(24)
                }
                .background(Color.gray.opacity(0.18))
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

    private var moveControls: some View {
        HStack(spacing: 10) {
            Text("Move to")
                .font(.caption)
                .foregroundStyle(.secondary)
            Picker("Move to", selection: $selectedMoveDestinationID) {
                ForEach(model.groupMoveDestinations) { destination in
                    Text(destination.title).tag(destination.id)
                }
            }
            .labelsHidden()
            .frame(maxWidth: 220)
            Button("Move") {
                model.moveSelectedLayer(to: selectedMoveDestinationID)
            }
            .disabled(!model.canMoveSelectedLayer)
            Button("Up") { model.moveSelectedLayerUp() }
                .disabled(!model.canMoveSelectedLayerUp)
            Button("Down") { model.moveSelectedLayerDown() }
                .disabled(!model.canMoveSelectedLayerDown)
        }
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

    private var compatibilityReportSheet: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                if model.compatibilityIssues.isEmpty {
                    Label("支持子集内，无警告", systemImage: "checkmark.seal.fill")
                        .foregroundStyle(.green)
                } else {
                    List(Array(model.compatibilityIssues.enumerated()), id: \.offset) { pair in
                        let issue = pair.element
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(issue.severity.label)
                                    .font(.caption)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(issue.severity.color.opacity(0.2), in: Capsule())
                                Text(issue.kind.label)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            if let layerName = issue.layerName {
                                Text(layerName)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Text(issue.message)
                                .font(.callout)
                        }
                        .padding(.vertical, 4)
                    }
                }
                HStack {
                    Spacer()
                    Button("Done") { model.isShowingCompatibilityReport = false }
                }
            }
            .padding()
            .frame(minWidth: 540, minHeight: 360)
            .navigationTitle("Compatibility Report")
        }
    }

    private var snapshotPanel: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    TextField("Snapshot label", text: $snapshotLabelDraft)
                    Button("Capture") {
                        model.captureSnapshot(label: snapshotLabelDraft)
                        if snapshotLabelDraft == "Before" {
                            snapshotLabelDraft = "After"
                        }
                    }
                    .disabled(model.document == nil)
                    Button("Clear") {
                        model.clearSnapshots()
                    }
                    .disabled(model.snapshots.isEmpty)
                }
                List(model.snapshots) { entry in
                    HStack {
                        Text(entry.label)
                        Spacer()
                        Text(entry.createdAt.formatted(date: .omitted, time: .standard))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                Text(model.snapshotDiffDescription)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                HStack {
                    Spacer()
                    Button("Done") { model.isShowingSnapshotPanel = false }
                }
            }
            .padding()
            .frame(minWidth: 560, minHeight: 380)
            .navigationTitle("Snapshot / Diff")
        }
    }

    private var manualValidationChecklistSheet: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Progress: \(model.manualValidationChecklistProgressText)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Reset") {
                        model.resetManualValidationChecklist()
                    }
                }
                List {
                    ForEach(DocumentModel.manualValidationChecklistSections) { section in
                        Section(section.title) {
                            ForEach(section.items) { item in
                                Toggle(
                                    item.title,
                                    isOn: Binding(
                                        get: { model.manualValidationState[item.id] ?? false },
                                        set: { model.setManualValidationItem(id: item.id, checked: $0) }
                                    )
                                )
                            }
                        }
                    }
                }
                HStack {
                    Spacer()
                    Button("Done") { model.isShowingManualValidationChecklist = false }
                }
            }
            .padding()
            .frame(minWidth: 640, minHeight: 460)
            .navigationTitle("Manual Validation")
        }
    }

    private var photoshopRoundtripSheet: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 14) {
                Text("Suggested Export")
                    .font(.headline)
                Text(model.suggestedRoundtripExportURL.path)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)

                HStack {
                    Button("Reveal in Finder") {
                        model.revealSuggestedRoundtripExportInFinder()
                    }
                    Button("Open Hard Reject Smoke Pack") {
                        model.openHardRejectSmokeFixturesFromGolden()
                    }
                }

                Divider()

                Text("Roundtrip Steps")
                    .font(.headline)
                VStack(alignment: .leading, spacing: 6) {
                    Text("1. Export PSD from Viewer to `midterm-roundtrip-p1.psd`.")
                    Text("2. Open in Photoshop and check layer tree, blend, and visibility.")
                    Text("3. Save As from Photoshop and reopen in Viewer.")
                    Text("4. Verify compatibility report and perform one edit-save-reopen.")
                }
                .font(.callout)

                Spacer()
                HStack {
                    Spacer()
                    Button("Done") { model.isShowingPhotoshopRoundtripAssistant = false }
                }
            }
            .padding()
            .frame(minWidth: 620, minHeight: 360)
            .navigationTitle("Photoshop Roundtrip")
        }
    }
}

private extension PSDCompatibilityIssue.Severity {
    var label: String {
        switch self {
        case .info: return "Info"
        case .warning: return "Warning"
        case .error: return "Error"
        }
    }

    var color: Color {
        switch self {
        case .info: return .blue
        case .warning: return .orange
        case .error: return .red
        }
    }
}

private extension PSDCompatibilityIssue.Kind {
    var label: String {
        switch self {
        case .unsupportedLayerKind: return "unsupportedLayerKind"
        case .unsupportedBlendMode: return "unsupportedBlendMode"
        case .unsupportedMask: return "unsupportedMask"
        case .unsupportedLayerEffect: return "unsupportedLayerEffect"
        case .unsupportedCompression: return "unsupportedCompression"
        case .droppedLayer: return "droppedLayer"
        case .rasterizedOrFlattenedContent: return "rasterizedOrFlattenedContent"
        }
    }
}
