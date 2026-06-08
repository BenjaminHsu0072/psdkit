import AppKit
import Foundation
import PSDKit
import SwiftUI

@MainActor
final class DocumentModel: ObservableObject {
    enum ReplacePixelSizePolicy {
        case matchImageSize
        case keepExistingFrame
    }

    struct GroupDestination: Identifiable, Hashable {
        let id: String
        let title: String
        let path: LayerPath?
    }

    fileprivate struct SnapshotRecord: Equatable {
        let path: String
        let kind: String
        let name: String
        let isVisible: Bool
        let opacity: UInt8
        let blendMode: String
        let frame: PSDRect
        let pixelDigest: Int?

        var signature: String {
            "\(path)|\(kind)|\(name)|\(isVisible)|\(opacity)|\(blendMode)|\(frame.left),\(frame.top),\(frame.right),\(frame.bottom)|\(pixelDigest.map(String.init) ?? "-")"
        }
    }

    struct SnapshotEntry: Identifiable, Equatable {
        let id: UUID
        let label: String
        let createdAt: Date
        fileprivate let records: [SnapshotRecord]
    }

    struct ManualValidationChecklistItem: Identifiable, Hashable {
        let id: String
        let title: String
    }

    struct ManualValidationChecklistSection: Identifiable, Hashable {
        let id: String
        let title: String
        let items: [ManualValidationChecklistItem]
    }

    @Published private(set) var document: PSDDocument?
    @Published private(set) var fileURL: URL?
    @Published private(set) var previewImage: NSImage?
    @Published private(set) var renderSnapshot: EditorRenderSnapshot?
    @Published private(set) var snapshotPixels = EditorSnapshotPixelProvider()
    @Published var editorViewport = EditorViewport(canvasSize: .zero)
    @Published private(set) var usesMetalPreview = true
    @Published private(set) var previewFallbackReason: String?
    @Published private(set) var statusMessage = "Open a PSD file to begin."
    @Published private(set) var errorMessage: String?
    /// Shown when `compatibilityReport` indicates lossy import (session-only; not saved to PSD).
    @Published private(set) var compatibilityWarningMessage: String?
    /// Layer path selection id for sidebar `List` (e.g. `"0"`, `"1/0"`).
    @Published var selectedLayerID: String?
    /// Bumped when layer metadata changes so SwiftUI refreshes the sidebar.
    @Published private(set) var documentRevision = 0
    @Published var isShowingCompatibilityReport = false
    @Published var isShowingLossySaveConfirmation = false
    @Published var isShowingUnsavedCloseConfirmation = false
    @Published var isShowingDeleteGroupConfirmation = false
    @Published var isShowingReplacePixelSizePolicyDialog = false
    @Published var isShowingSnapshotPanel = false
    @Published var isShowingManualValidationChecklist = false
    @Published var isShowingPhotoshopRoundtripAssistant = false
    @Published private(set) var snapshots: [SnapshotEntry] = []
    @Published private(set) var snapshotDiffDescription = "Capture at least two snapshots to inspect differences."
    @Published private(set) var manualValidationState: [String: Bool] = [:]
    @Published private(set) var collapsedGroupIDs: Set<String> = []
    @Published var editorState = EditorState()
    @Published private(set) var activeStrokePreview: ActiveStrokePreview?
    @Published private(set) var strokePreviewRevision: UInt64 = 0
    @Published private(set) var pendingStrokeCommit: PendingStrokeCommit?
    @Published private(set) var strokePreviewDiagnostics = StrokePreviewDiagnostics()
    @Published private(set) var writebackState: EditorWritebackState = .idleClean
    @Published private(set) var writebackDiagnostics = StrokeWritebackDiagnostics()

    private let userDefaults: UserDefaults
    private var documentSessionID = UUID()
    private var editorAdapter: PSDDocumentEditorAdapter?
    private let editorCommandDispatcher = EditorCommandDispatcher()
    private static let manualValidationStateKey = "PSDViewer.ManualValidation.P1ChecklistState"
    private static let useMetalPreviewKey = "PSDViewer.UseMetalPreview"

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        if userDefaults.object(forKey: Self.useMetalPreviewKey) == nil {
            userDefaults.register(defaults: [Self.useMetalPreviewKey: true])
        }
        manualValidationState = Self.loadManualValidationState(from: userDefaults)
    }

    var userPrefersMetalPreview: Bool {
        get { userDefaults.bool(forKey: Self.useMetalPreviewKey) }
        set {
            userDefaults.set(newValue, forKey: Self.useMetalPreviewKey)
            refreshPreview()
        }
    }

    static let manualValidationChecklistSections: [ManualValidationChecklistSection] = [
        ManualValidationChecklistSection(
            id: "structure",
            title: "Structure Edits",
            items: [
                ManualValidationChecklistItem(id: "p1-add-layer", title: "Add pixel layer inside target group and roundtrip"),
                ManualValidationChecklistItem(id: "p1-delete-layer", title: "Delete pixel layer and roundtrip"),
                ManualValidationChecklistItem(id: "p1-cross-group-move", title: "Move layer across groups and roundtrip"),
                ManualValidationChecklistItem(id: "p1-reorder-siblings", title: "Reorder siblings and verify stack order roundtrip"),
            ]
        ),
        ManualValidationChecklistSection(
            id: "properties",
            title: "Property And Pixel Edits",
            items: [
                ManualValidationChecklistItem(id: "p1-frame", title: "Edit frame values and verify preview + reopen"),
                ManualValidationChecklistItem(id: "p1-blend", title: "Switch blend mode (normal/multiply/add) and roundtrip"),
                ManualValidationChecklistItem(id: "p1-visibility", title: "Toggle visibility (root and nested) and roundtrip"),
                ManualValidationChecklistItem(id: "p1-replace-png", title: "Replace selected pixels from PNG with size policy"),
            ]
        ),
        ManualValidationChecklistSection(
            id: "workflow",
            title: "Workflow Gates",
            items: [
                ManualValidationChecklistItem(id: "p1-snapshots", title: "Capture Before/After snapshots and inspect diff"),
                ManualValidationChecklistItem(id: "p1-three-cycles", title: "Run at least 3 edit-save-reopen cycles"),
                ManualValidationChecklistItem(id: "p1-photoshop-helper", title: "Follow Photoshop roundtrip assistant end-to-end"),
            ]
        ),
    ]

    var layerItems: [LayerListItem] {
        guard let document else { return [] }
        let all = LayerListFlattener.flatten(root: document.root)
        guard !collapsedGroupIDs.isEmpty else { return all }
        return all.filter { item in
            for collapsedID in collapsedGroupIDs {
                guard let collapsed = LayerPath(selectionID: collapsedID) else { continue }
                if isStrictDescendant(item.path.indices, of: collapsed.indices) {
                    return false
                }
            }
            return true
        }
    }

    var totalLayerCount: Int {
        guard let document else { return 0 }
        return LayerListFlattener.flatten(root: document.root).count
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

    var canRemoveSelectedLayer: Bool {
        selectedLayer is PixelLayer
    }

    var hasUnsavedChanges: Bool {
        document?.hasUnsavedChanges ?? false
    }

    var hasActiveStrokeRecording: Bool {
        editorState.strokeSession.isRecording
    }

    var isWritebackFlushFailed: Bool {
        if case .flushFailed = writebackState { return true }
        return false
    }

    /// Unflushed editor work that must not be silently discarded on close.
    var hasUnflushedEditorWork: Bool {
        pendingStrokeCommit != nil || hasActiveStrokeRecording || isWritebackFlushFailed
    }

    var requiresCloseConfirmation: Bool {
        hasUnsavedChanges || hasUnflushedEditorWork
    }

    var canUndoStrokeEdit: Bool {
        editorAdapter?.canUndo == true && pendingStrokeCommit == nil && writebackState != .flushing
    }

    var canRedoStrokeEdit: Bool {
        editorAdapter?.canRedo == true && pendingStrokeCommit == nil && writebackState != .flushing
    }

    var navigationTitle: String {
        let base = fileURL?.lastPathComponent ?? "PSDViewer"
        return hasUnsavedChanges ? "\(base) *" : base
    }

    var statusSummary: String {
        let pathText = fileURL?.path ?? "Untitled"
        let layers = totalLayerCount
        let dirtyText = hasUnsavedChanges ? "Edited" : "Saved"
        return "\(pathText) • \(layers) layer(s) • \(dirtyText)"
    }

    var compatibilityIssues: [PSDCompatibilityIssue] {
        document?.compatibilityReport.issues ?? []
    }

    var hasCompatibilityDetails: Bool {
        guard let document else { return false }
        return document.compatibilityReport.hasLossyChanges || !document.compatibilityReport.issues.isEmpty
    }

    var canMoveSelectedLayer: Bool {
        selectedLayer != nil
    }

    var canMoveSelectedLayerUp: Bool {
        guard let document, let path = selectedLayerPath else { return false }
        guard let context = siblingContext(for: path, in: document) else { return false }
        return context.index < context.parent.children.count - 1
    }

    var canMoveSelectedLayerDown: Bool {
        guard let document, let path = selectedLayerPath else { return false }
        guard let context = siblingContext(for: path, in: document) else { return false }
        return context.index > 0
    }

    var selectedGroupDestinationID: String {
        guard let selected = selectedLayerPath else { return "root" }
        let parentPath = Array(selected.indices.dropLast())
        return parentPath.isEmpty ? "root" : LayerPath(indices: parentPath).selectionID
    }

    var canDeleteSelectedGroup: Bool {
        selectedLayer is GroupLayer
    }

    var replacePolicyTargetLayerName: String? {
        guard let context = pendingReplacePixelsContext, let document else { return nil }
        return (LayerListFlattener.resolveLayer(in: document.root, path: context.path) as? PixelLayer)?.name
    }

    var manualValidationChecklistProgressText: String {
        let total = Self.manualValidationChecklistSections.reduce(0) { $0 + $1.items.count }
        let done = manualValidationState.values.filter { $0 }.count
        return "\(done) / \(total)"
    }

    var hasSnapshotDiff: Bool {
        !snapshotDiffDescription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var groupMoveDestinations: [GroupDestination] {
        guard let document else { return [] }
        var destinations: [GroupDestination] = [
            GroupDestination(id: "root", title: "Root", path: nil),
        ]
        let selected = selectedLayer
        collectGroupDestinations(
            from: document.root,
            pathPrefix: [],
            selectedLayer: selected,
            into: &destinations
        )
        return destinations
    }

    var currentDocumentDirectoryURL: URL {
        if let fileURL {
            return fileURL.deletingLastPathComponent()
        }
        return FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser
    }

    var suggestedRoundtripExportURL: URL {
        currentDocumentDirectoryURL.appendingPathComponent("midterm-roundtrip-p1.psd")
    }

    private struct PendingSaveContext {
        let url: URL
        let updateFileURL: Bool
        let successPrefix: String
    }

    private struct PendingReplacePixelsContext {
        let path: LayerPath
        let pngURL: URL
    }

    private var pendingSaveContext: PendingSaveContext?
    private var pendingReplacePixelsContext: PendingReplacePixelsContext?
    private var pendingCloseAction: (() -> Void)?
    private var pendingDeleteGroupPath: LayerPath?
    var shouldRequireLossySaveConfirmation: ((PSDDocument) -> Bool)?
    /// Overrides `EditorPreviewRouting.cpuFallbackReason` in tests; nil uses production routing.
    var previewRoutingFallbackReasonProvider: (
        (EditorRenderSnapshot, Bool) -> EditorPreviewRouting.FallbackReason?
    )?
    private var lastMetalDrawErrorMessage: String?

    @MainActor
    private struct SessionState {
        let document: PSDDocument?
        let fileURL: URL?
        let previewImage: NSImage?
        let renderSnapshot: EditorRenderSnapshot?
        let snapshotPixels: EditorSnapshotPixelProvider
        let editorViewport: EditorViewport
        let usesMetalPreview: Bool
        let previewFallbackReason: String?
        let selectedLayerID: String?
        let compatibilityWarningMessage: String?
        let statusMessage: String
        let errorMessage: String?

        static func capture(from model: DocumentModel) -> SessionState {
            SessionState(
                document: model.document,
                fileURL: model.fileURL,
                previewImage: model.previewImage,
                renderSnapshot: model.renderSnapshot,
                snapshotPixels: model.snapshotPixels,
                editorViewport: model.editorViewport,
                usesMetalPreview: model.usesMetalPreview,
                previewFallbackReason: model.previewFallbackReason,
                selectedLayerID: model.selectedLayerID,
                compatibilityWarningMessage: model.compatibilityWarningMessage,
                statusMessage: model.statusMessage,
                errorMessage: model.errorMessage
            )
        }

        func restore(into model: DocumentModel) {
            model.document = document
            model.fileURL = fileURL
            model.previewImage = previewImage
            model.renderSnapshot = renderSnapshot
            model.snapshotPixels = snapshotPixels
            model.editorViewport = editorViewport
            model.usesMetalPreview = usesMetalPreview
            model.previewFallbackReason = previewFallbackReason
            model.selectedLayerID = selectedLayerID
            model.compatibilityWarningMessage = compatibilityWarningMessage
            model.statusMessage = statusMessage
            model.errorMessage = errorMessage
        }
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
            clearTransientPanelsForNewSession()
            syncEditorSelectionFromSidebar()
            bumpDocument()
            refreshPreview()
        } catch let error as PSDError {
            errorMessage = error.userMessage
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func generateStandardTestDocument() {
        do {
            let doc = try PSDDocument.makeMidtermStandardDocument()
            loadDocumentForTests(doc, statusMessage: "Generated midterm standard document (\(doc.canvasSize.width)×\(doc.canvasSize.height))")
        } catch let error as PSDError {
            errorMessage = error.userMessage
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func loadDocumentForTests(
        _ document: PSDDocument,
        selectedLayerID: String? = nil,
        statusMessage: String? = nil
    ) {
        self.document = document
        fileURL = nil
        self.selectedLayerID = selectedLayerID ?? LayerListFlattener.flatten(root: document.root).first?.id
        errorMessage = nil
        compatibilityWarningMessage = Self.compatibilitySummary(from: document.compatibilityReport)
        if let statusMessage {
            self.statusMessage = statusMessage
        }
        clearTransientPanelsForNewSession()
        syncEditorSelectionFromSidebar()
        bumpDocument()
        refreshPreview()
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
        let previousState = SessionState.capture(from: self)
        do {
            let doc = try PSDDocument.load(url: url)
            document = doc
            fileURL = url
            selectedLayerID = LayerListFlattener.flatten(root: doc.root).first?.id
            errorMessage = nil
            compatibilityWarningMessage = Self.compatibilitySummary(from: doc.compatibilityReport)
            statusMessage = "Loaded \(url.lastPathComponent) — \(doc.root.children.count) layer(s)"
            clearTransientPanelsForNewSession()
            syncEditorSelectionFromSidebar()
            bumpDocument()
            refreshPreview()
        } catch let error as PSDError {
            previousState.restore(into: self)
            errorMessage = error.userMessage
            statusMessage = previousState.document == nil
                ? "Failed to open file."
                : "Failed to open file. Current document remains unchanged."
        } catch {
            previousState.restore(into: self)
            errorMessage = error.localizedDescription
            statusMessage = previousState.document == nil
                ? "Failed to open file."
                : "Failed to open file. Current document remains unchanged."
        }
    }

    func saveDocument() {
        guard document != nil else { return }
        guard guardNoActiveStrokeRecording(for: "Save") else { return }
        guard flushPendingWritebackBeforeSave() else { return }
        if let fileURL {
            requestSave(
                to: fileURL,
                updateFileURL: false,
                successPrefix: "Saved"
            )
        } else {
            saveDocumentAs()
        }
    }

    func saveDocumentAs() {
        guard document != nil else { return }
        guard guardNoActiveStrokeRecording(for: "Save") else { return }
        guard flushPendingWritebackBeforeSave() else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.data]
        panel.nameFieldStringValue = "Untitled.psd"
        panel.title = "Export PSD"
        panel.message = "Save 8-bit RGB PSD"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        requestSave(
            to: url,
            updateFileURL: true,
            successPrefix: "Exported"
        )
    }

    func saveDocumentAs(urlOverrideForTests url: URL) {
        guard document != nil else { return }
        guard guardNoActiveStrokeRecording(for: "Save") else { return }
        guard flushPendingWritebackBeforeSave() else { return }
        requestSave(
            to: url,
            updateFileURL: true,
            successPrefix: "Exported"
        )
    }

    func selectLayerInSidebar(id: String?) {
        selectedLayerID = id
        editorState.selectLayer(id: id)
    }

    func setEditorTool(_ tool: EditorTool) {
        guard tool != editorState.activeTool else { return }

        if editorState.strokeSession.isRecording {
            var session = editorState.strokeSession
            _ = session.cancel(reasonSample: nil)
            editorState.strokeSession = session
            editorState.inputDiagnostics.lastEventSummary = "stroke cancelled: tool changed"
            clearActiveStrokePreview(reason: "stroke cancelled: tool changed")
        }
        editorState.setTool(tool)
    }

    func handleRawPointerEvent(_ event: RawPointerEvent) {
        let context = StrokeInputContext(
            viewport: editorViewport,
            activeTool: editorState.activeTool,
            brushSettings: editorState.brushSettings,
            drawContext: strokeDrawContext()
        )
        var session = editorState.strokeSession
        let result = StrokeInputController.handle(
            event: event,
            session: &session,
            context: context
        )
        editorState.applyInputResult(result)
        updateStrokePreviewAfterInput()
    }

    var inputDiagnosticsSummary: String? {
        let diagnostics = editorState.inputDiagnostics
        guard !diagnostics.lastEventSummary.isEmpty else { return nil }
        var parts = [diagnostics.lastEventSummary]
        if let point = diagnostics.lastCanvasPoint {
            parts.append(String(format: "canvas (%.1f, %.1f)", point.x, point.y))
        }
        if let pressure = diagnostics.lastPressure {
            parts.append(String(format: "p=%.2f", pressure))
        }
        parts.append("samples=\(diagnostics.sampleCount)")
        return parts.joined(separator: " · ")
    }

    private func strokeDrawContext() -> StrokeDrawContext? {
        guard canEditSelectedLayerInInspector,
              let layer = selectedPixelLayer,
              let layerID = selectedLayerID
        else { return nil }
        return StrokeDrawContext(
            layerID: layerID,
            layerFrame: layer.frame,
            isEditable: true
        )
    }

    private func resetEditorInputState() {
        editorState.strokeSession.reset()
        editorState.inputDiagnostics = .empty
        clearActiveStrokePreview(reason: "editor input reset")
        pendingStrokeCommit = nil
        strokePreviewDiagnostics = .empty
        syncWritebackState()
    }

    @discardableResult
    func commitPendingStroke() -> StrokeWritebackResult {
        guard let pending = pendingStrokeCommit else {
            writebackDiagnostics.lastResult = "no pending commit"
            return .noPendingCommit
        }
        guard let document else {
            let message = "no open document"
            writebackState = .flushFailed(message: message)
            writebackDiagnostics.lastResult = message
            return .failure(message)
        }
        guard let path = LayerPath(selectionID: pending.layerID),
              let layer = LayerListFlattener.resolveLayer(in: document.root, path: path) as? PixelLayer
        else {
            writebackDiagnostics.lastStaleReason = .layerNotFound
            writebackDiagnostics.rejectedCommitCount += 1
            writebackDiagnostics.lastResult = StrokeWritebackStaleReason.layerNotFound.diagnosticMessage
            writebackState = .flushFailed(message: writebackDiagnostics.lastResult)
            statusMessage = "Stroke writeback rejected: \(writebackDiagnostics.lastResult)"
            return .stale(.layerNotFound)
        }

        let context = StrokeWritebackContext(
            documentSessionID: documentSessionID,
            documentRevision: UInt64(documentRevision),
            layerID: pending.layerID,
            layerUUID: layer.id,
            layerPixelRevision: EditorPixelRevisionDigest.digest(rgba: layer.pixels.rgba)
        )
        if let stale = StrokeWritebackValidator.validate(pending: pending, against: context) {
            writebackDiagnostics.lastStaleReason = stale
            writebackDiagnostics.rejectedCommitCount += 1
            writebackDiagnostics.lastResult = stale.diagnosticMessage
            writebackState = .flushFailed(message: stale.diagnosticMessage)
            statusMessage = "Stroke writeback rejected: \(stale.diagnosticMessage)"
            return .stale(stale)
        }

        guard let rect = pending.dirtyRegion.layerLocalRect(
            pixelWidth: layer.pixels.width,
            pixelHeight: layer.pixels.height
        ) else {
            writebackDiagnostics.lastStaleReason = .emptyDirtyRegion
            writebackDiagnostics.rejectedCommitCount += 1
            writebackDiagnostics.lastResult = StrokeWritebackStaleReason.emptyDirtyRegion.diagnosticMessage
            writebackState = .flushFailed(message: writebackDiagnostics.lastResult)
            statusMessage = "Stroke writeback rejected: \(writebackDiagnostics.lastResult)"
            return .stale(.emptyDirtyRegion)
        }

        guard let adapter = makeOrUpdateEditorAdapter() else {
            let message = "editor adapter unavailable"
            writebackState = .flushFailed(message: message)
            writebackDiagnostics.lastResult = message
            return .failure(message)
        }

        writebackState = .flushing
        let command = CommitStrokeCommand(pending: pending, context: context)
        let commandResult = editorCommandDispatcher.dispatch(command, through: adapter)

        switch commandResult {
        case .success:
            pendingStrokeCommit = nil
            writebackDiagnostics.commitCount += 1
            writebackDiagnostics.lastStaleReason = nil
            writebackDiagnostics.lastReadbackRect = rect
            writebackDiagnostics.lastReadbackPixelCount = rect.width * rect.height
            writebackDiagnostics.lastResult = "stroke committed"
            syncWritebackState()
            bumpDocument()
            refreshPreview()
            bumpStrokePreviewRevision()
            strokePreviewDiagnostics.pendingCommitLayerID = nil
            statusMessage = "Stroke committed to \(layer.name)"
            errorMessage = nil
            return .success
        case .failure(let error):
            let message = writebackFailureMessage(for: error)
            writebackDiagnostics.rejectedCommitCount += 1
            writebackDiagnostics.lastResult = message
            writebackState = .flushFailed(message: message)
            statusMessage = "Stroke writeback failed: \(message)"
            return .failure(message)
        }
    }

    func undoStrokeEdit() {
        guard flushPendingWritebackBeforeMutation() else { return }
        guard let adapter = makeOrUpdateEditorAdapter(),
              let entry = adapter.popUndoEntry()
        else {
            statusMessage = "Nothing to undo."
            return
        }
        let result = editorCommandDispatcher.dispatch(
            ApplyPixelPatchCommand(patch: entry.inversePatch),
            through: adapter
        )
        guard result == .success else {
            statusMessage = "Undo failed."
            return
        }
        bumpDocument()
        refreshPreview()
        bumpStrokePreviewRevision()
        syncWritebackState()
        statusMessage = "Undid \(entry.label)"
    }

    func redoStrokeEdit() {
        guard flushPendingWritebackBeforeMutation() else { return }
        guard let adapter = makeOrUpdateEditorAdapter(),
              let entry = adapter.popRedoEntry()
        else {
            statusMessage = "Nothing to redo."
            return
        }
        let result = editorCommandDispatcher.dispatch(
            ApplyPixelPatchCommand(patch: entry.forwardPatch),
            through: adapter
        )
        guard result == .success else {
            statusMessage = "Redo failed."
            return
        }
        bumpDocument()
        refreshPreview()
        bumpStrokePreviewRevision()
        syncWritebackState()
        statusMessage = "Redid \(entry.label)"
    }

    private func makeOrUpdateEditorAdapter() -> PSDDocumentEditorAdapter? {
        guard let document else {
            editorAdapter = nil
            return nil
        }
        if let existing = editorAdapter {
            return existing
        }
        let adapter = PSDDocumentEditorAdapter(
            document: document,
            documentSessionID: documentSessionID,
            documentRevision: UInt64(documentRevision)
        )
        editorAdapter = adapter
        return adapter
    }

    @discardableResult
    private func guardNoActiveStrokeRecording(for operation: String) -> Bool {
        guard hasActiveStrokeRecording else { return true }
        statusMessage = "\(operation) blocked: finish or cancel the current stroke first."
        return false
    }

    @discardableResult
    private func flushPendingWritebackBeforeSave() -> Bool {
        guard pendingStrokeCommit != nil else { return true }
        switch commitPendingStroke() {
        case .success, .noPendingCommit:
            return true
        case .stale, .failure:
            statusMessage = "Save blocked until stroke writeback succeeds."
            return false
        }
    }

    @discardableResult
    private func flushPendingWritebackBeforeMutation() -> Bool {
        guard pendingStrokeCommit != nil else { return true }
        switch commitPendingStroke() {
        case .success, .noPendingCommit:
            return true
        case .stale, .failure:
            statusMessage = "Complete or cancel pending stroke before undo/redo."
            return false
        }
    }

    private func syncWritebackState() {
        if pendingStrokeCommit != nil {
            writebackState = .pendingFlush
            return
        }
        if case .flushFailed = writebackState {
            return
        }
        if document?.hasUnsavedChanges == true {
            writebackState = .idleDirty
        } else {
            writebackState = .idleClean
        }
    }

    private func writebackFailureMessage(for error: EditorCommandError) -> String {
        switch error {
        case .staleWriteback(let reason):
            writebackDiagnostics.lastStaleReason = reason
            return reason.diagnosticMessage
        case .patchApplyFailed(let message):
            return message
        case .layerNotFound:
            writebackDiagnostics.lastStaleReason = .layerNotFound
            return StrokeWritebackStaleReason.layerNotFound.diagnosticMessage
        case .invalidParameter(let message):
            return message
        case .unsupportedBlendMode:
            return "unsupported blend mode"
        case .notImplemented:
            return "not implemented"
        }
    }

    private func updateStrokePreviewAfterInput() {
        let session = editorState.strokeSession
        let tool = editorState.activeTool

        switch session.phase {
        case .active:
            rebuildActiveStrokePreview(session: session, tool: tool)
        case .ended:
            if session.isCommitEligible {
                finalizePendingStrokeCommit(from: session, tool: tool)
            } else {
                clearActiveStrokePreview(reason: "stroke ended without commit eligibility")
            }
            editorState.strokeSession.reset()
        case .cancelled:
            clearActiveStrokePreview(reason: "stroke cancelled")
            editorState.strokeSession.reset()
        case .idle:
            break
        }
        bumpStrokePreviewRevision()
    }

    private func rebuildActiveStrokePreview(session: StrokeSession, tool: EditorTool) {
        guard usesMetalPreview else {
            if let plan = BrushDabPlanner.plan(from: session, tool: tool) {
                strokePreviewDiagnostics = StrokePreviewDiagnostics(
                    dabCount: plan.dabCount,
                    dirtyRegion: plan.dirtyRegion,
                    activeLayerID: plan.layerID,
                    lastStrokeResult: "recorded",
                    rejectionReason: "brush-preview-unavailable-cpu-fallback",
                    isPreviewActive: false,
                    pendingCommitLayerID: pendingStrokeCommit?.layerID
                )
            } else {
                strokePreviewDiagnostics.rejectionReason = "brush-preview-unavailable-cpu-fallback"
            }
            activeStrokePreview = nil
            return
        }

        guard let plan = BrushDabPlanner.plan(from: session, tool: tool) else {
            clearActiveStrokePreview(reason: "no dab plan")
            return
        }

        activeStrokePreview = ActiveStrokePreview(
            plan: plan,
            phase: session.phase,
            brush: session.brushSnapshot
        )
        strokePreviewDiagnostics = StrokePreviewDiagnostics(
            dabCount: plan.dabCount,
            dirtyRegion: plan.dirtyRegion,
            activeLayerID: plan.layerID,
            lastStrokeResult: "preview-active",
            rejectionReason: nil,
            isPreviewActive: true,
            pendingCommitLayerID: pendingStrokeCommit?.layerID
        )
    }

    private func finalizePendingStrokeCommit(from session: StrokeSession, tool: EditorTool) {
        guard let plan = BrushDabPlanner.plan(from: session, tool: tool) else {
            clearActiveStrokePreview(reason: "ended without dab plan")
            return
        }

        if let existingPending = pendingStrokeCommit {
            switch commitPendingStroke() {
            case .success, .noPendingCommit:
                break
            case .stale(let reason):
                strokePreviewDiagnostics.rejectionReason = "prior-pending-flush-stale"
                strokePreviewDiagnostics.pendingCommitLayerID = existingPending.layerID
                clearActiveStrokePreview(reason: "new stroke rejected; prior pending retained")
                statusMessage = "New stroke not committed: prior stroke writeback failed (\(reason.diagnosticMessage))"
                return
            case .failure(let message):
                strokePreviewDiagnostics.rejectionReason = "prior-pending-flush-failed"
                strokePreviewDiagnostics.pendingCommitLayerID = existingPending.layerID
                clearActiveStrokePreview(reason: "new stroke rejected; prior pending retained")
                statusMessage = "New stroke not committed: prior stroke writeback failed (\(message))"
                return
            }
        }

        guard let snapshot = renderSnapshot else {
            clearActiveStrokePreview(reason: "ended without render snapshot")
            return
        }

        let layerSnapshot = snapshot.layers.first(where: { $0.id == plan.layerID })
        pendingStrokeCommit = PendingStrokeCommit(
            documentSessionID: snapshot.documentSessionID,
            documentRevision: UInt64(documentRevision),
            layerID: plan.layerID,
            layerUUID: layerSnapshot?.layerUUID,
            layerPixelRevision: layerSnapshot?.pixelRevision ?? 0,
            mode: plan.mode,
            brushSnapshot: session.brushSnapshot,
            rasterizationPlan: plan,
            dabCount: plan.dabCount,
            sampleCount: plan.sampleCount,
            dirtyRegion: plan.dirtyRegion,
            layerFrame: plan.layerFrame
        )
        writebackState = .pendingFlush
        clearActiveStrokePreview(reason: "stroke ended; pending commit retained")
        strokePreviewDiagnostics = StrokePreviewDiagnostics(
            dabCount: plan.dabCount,
            dirtyRegion: plan.dirtyRegion,
            activeLayerID: plan.layerID,
            lastStrokeResult: "ended-pending-commit",
            rejectionReason: usesMetalPreview ? nil : "brush-preview-unavailable-cpu-fallback",
            isPreviewActive: false,
            pendingCommitLayerID: plan.layerID
        )
    }

    private func clearActiveStrokePreview(reason: String) {
        activeStrokePreview = nil
        if strokePreviewDiagnostics.lastStrokeResult.isEmpty {
            strokePreviewDiagnostics.lastStrokeResult = reason
        } else if !reason.isEmpty {
            strokePreviewDiagnostics.lastStrokeResult = reason
        }
        strokePreviewDiagnostics.isPreviewActive = false
        strokePreviewDiagnostics.dabCount = 0
        strokePreviewDiagnostics.activeLayerID = nil
    }

    private func bumpStrokePreviewRevision() {
        strokePreviewRevision &+= 1
    }

    private func syncEditorSelectionFromSidebar() {
        editorState.selectLayer(id: selectedLayerID)
    }

    func refreshPreview() {
        guard let document else {
            previewImage = nil
            renderSnapshot = nil
            snapshotPixels = EditorSnapshotPixelProvider()
            usesMetalPreview = false
            previewFallbackReason = nil
            return
        }

        syncEditorViewportCanvasSize(with: document)

        let snapshot = EditorRenderSnapshotBuilder.build(
            from: document,
            documentSessionID: documentSessionID,
            documentRevision: UInt64(documentRevision),
            selectedLayerID: selectedLayerID,
            viewport: editorViewport
        )
        renderSnapshot = snapshot
        snapshotPixels = EditorSnapshotPixelProvider.build(from: document, snapshot: snapshot)

        let resolveFallback = previewRoutingFallbackReasonProvider
            ?? EditorPreviewRouting.cpuFallbackReason
        if let fallback = resolveFallback(snapshot, userPrefersMetalPreview) {
            usesMetalPreview = false
            previewFallbackReason = fallback.statusMessage
            do {
                previewImage = try PreviewRenderer.makeImage(from: document)
            } catch let error as PSDError {
                previewImage = nil
                errorMessage = error.userMessage
            } catch {
                previewImage = nil
                errorMessage = error.localizedDescription
            }
        } else {
            usesMetalPreview = true
            previewFallbackReason = nil
            previewImage = nil
        }
    }

    func fitPreviewToView(padding: CGFloat = 24) {
        editorViewport.fitToView(padding: padding)
    }

    func reportMetalPreviewDrawError(_ error: Error) {
        let message = "Metal preview draw failed: \(error.localizedDescription)"
        guard lastMetalDrawErrorMessage != message else { return }
        lastMetalDrawErrorMessage = message
        statusMessage = message
    }

    func continueLossySave() {
        guard let context = pendingSaveContext else { return }
        isShowingLossySaveConfirmation = false
        pendingSaveContext = nil
        performSave(using: context)
        if pendingCloseAction != nil, !hasUnsavedChanges {
            continueCloseWithoutSaving()
        }
    }

    func cancelLossySave() {
        pendingSaveContext = nil
        isShowingLossySaveConfirmation = false
        pendingCloseAction = nil
        statusMessage = "Save canceled."
    }

    func requestCloseDocument(_ action: @escaping () -> Void) {
        if isWritebackFlushFailed {
            statusMessage = "Close blocked: stroke writeback failed. Retry writeback or cancel."
            return
        }
        if hasActiveStrokeRecording {
            pendingCloseAction = action
            isShowingUnsavedCloseConfirmation = true
            statusMessage = "Finish or cancel the current stroke before closing."
            return
        }
        if requiresCloseConfirmation {
            pendingCloseAction = action
            isShowingUnsavedCloseConfirmation = true
            return
        }
        action()
    }

    func continueCloseWithoutSaving() {
        isShowingUnsavedCloseConfirmation = false
        let action = pendingCloseAction
        pendingCloseAction = nil
        action?()
    }

    func saveAndCloseDocument() {
        guard document != nil else {
            continueCloseWithoutSaving()
            return
        }
        if isWritebackFlushFailed {
            statusMessage = "Close blocked: stroke writeback failed. Retry writeback or cancel."
            return
        }
        guard guardNoActiveStrokeRecording(for: "Save and close") else { return }
        saveDocument()
        guard pendingStrokeCommit == nil else {
            statusMessage = "Close blocked until stroke writeback succeeds."
            return
        }
        if isWritebackFlushFailed {
            statusMessage = "Close blocked: stroke writeback failed. Retry writeback or cancel."
            return
        }
        if !hasUnsavedChanges {
            continueCloseWithoutSaving()
        } else {
            statusMessage = "Document still has unsaved changes."
        }
    }

    func cancelCloseDocument() {
        pendingCloseAction = nil
        isShowingUnsavedCloseConfirmation = false
        statusMessage = "Close canceled."
    }

    func showCompatibilityReport() {
        isShowingCompatibilityReport = true
    }

    func isGroupCollapsed(at path: LayerPath) -> Bool {
        collapsedGroupIDs.contains(path.selectionID)
    }

    func toggleGroupCollapsed(at path: LayerPath) {
        guard let document,
              LayerListFlattener.resolveLayer(in: document.root, path: path) is GroupLayer
        else { return }
        let id = path.selectionID
        if collapsedGroupIDs.contains(id) {
            collapsedGroupIDs.remove(id)
        } else {
            collapsedGroupIDs.insert(id)
        }
    }

    func addGroup() {
        guard let document else { return }
        let parent = preferredInsertionParent(in: document)
        let group = GroupLayer(name: "Group \(parent.children.count + 1)")
        document.appendLayer(group, to: parent)
        bumpDocument()
        selectedLayerID = selectionID(for: group.id, in: document.root)
        refreshPreview()
        statusMessage = "Added group \(group.name)"
        errorMessage = nil
    }

    func renameGroup(at path: LayerPath, to name: String) {
        guard let document,
              let group = LayerListFlattener.resolveLayer(in: document.root, path: path) as? GroupLayer
        else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        group.name = trimmed
        markDirty()
        statusMessage = "Renamed group to \"\(trimmed)\""
    }

    func setGroupOpacity(at path: LayerPath, opacity: UInt8) {
        guard let document,
              let group = LayerListFlattener.resolveLayer(in: document.root, path: path) as? GroupLayer
        else { return }
        group.opacity = opacity
        markDirty()
        statusMessage = "\(group.name) opacity: \(opacity)"
    }

    func setGroupBlendMode(at path: LayerPath, blendMode: PSDKit.BlendMode) {
        guard let document,
              let group = LayerListFlattener.resolveLayer(in: document.root, path: path) as? GroupLayer
        else { return }
        switch blendMode {
        case .normal, .multiply, .add, .passThrough:
            group.blendMode = blendMode
            markDirty()
            statusMessage = "\(group.name) blend: \(BlendModeDisplayName.text(for: blendMode))"
        case .unknown:
            statusMessage = "Unsupported group blend mode."
        }
    }

    func requestDeleteSelectedGroup() {
        guard canDeleteSelectedGroup else {
            statusMessage = "Select a group to remove."
            return
        }
        pendingDeleteGroupPath = selectedLayerPath
        isShowingDeleteGroupConfirmation = true
    }

    func confirmDeleteSelectedGroup() {
        defer {
            isShowingDeleteGroupConfirmation = false
            pendingDeleteGroupPath = nil
        }
        guard let document,
              let path = pendingDeleteGroupPath,
              let group = LayerListFlattener.resolveLayer(in: document.root, path: path) as? GroupLayer
        else { return }
        let name = group.name
        document.removeLayer(group)
        selectNeighborAfterRemoving(path: path, in: document)
        bumpDocument()
        refreshPreview()
        statusMessage = "Removed group \(name)"
        errorMessage = nil
    }

    func cancelDeleteSelectedGroup() {
        pendingDeleteGroupPath = nil
        isShowingDeleteGroupConfirmation = false
        statusMessage = "Delete group canceled."
    }

    func moveSelectedLayer(to destinationPath: LayerPath?) {
        guard let document, let selected = selectedLayer, let selectedPath = selectedLayerPath else { return }
        guard let sourceContext = siblingContext(for: selectedPath, in: document) else { return }
        let destinationParent: GroupLayer
        if let destinationPath {
            guard let resolved = LayerListFlattener.resolveLayer(in: document.root, path: destinationPath) as? GroupLayer else {
                statusMessage = "Invalid destination group."
                return
            }
            destinationParent = resolved
        } else {
            destinationParent = document.root
        }
        if let selectedGroup = selected as? GroupLayer, wouldCreateGroupCycle(group: selectedGroup, destination: destinationParent) {
            statusMessage = "Cannot move a group into itself or its descendants."
            return
        }

        let destinationCount = destinationParent.children.count
        let insertionIndex: Int
        if sourceContext.parent === destinationParent, sourceContext.index < destinationCount {
            insertionIndex = destinationCount - 1
        } else {
            insertionIndex = destinationCount
        }

        document.insertLayer(selected, to: destinationParent, at: insertionIndex)
        bumpDocument()
        selectedLayerID = selectionID(for: selected.id, in: document.root)
        refreshPreview()
        statusMessage = "Moved \(selected.name) to \(destinationPath == nil ? "Root" : destinationParent.name)"
        errorMessage = nil
    }

    func moveSelectedLayer(to destinationID: String) {
        if destinationID == "root" {
            moveSelectedLayer(to: nil)
            return
        }
        guard let destinationPath = LayerPath(selectionID: destinationID) else {
            statusMessage = "Invalid destination group."
            return
        }
        moveSelectedLayer(to: destinationPath)
    }

    func moveSelectedLayerUp() {
        guard let document, let selected = selectedLayer, let path = selectedLayerPath else { return }
        guard let context = siblingContext(for: path, in: document) else { return }
        let targetIndex = context.index + 1
        guard targetIndex < context.parent.children.count else { return }
        document.insertLayer(selected, to: context.parent, at: targetIndex)
        bumpDocument()
        selectedLayerID = selectionID(for: selected.id, in: document.root)
        refreshPreview()
        statusMessage = "Moved \(selected.name) up"
    }

    func moveSelectedLayerDown() {
        guard let document, let selected = selectedLayer, let path = selectedLayerPath else { return }
        guard let context = siblingContext(for: path, in: document) else { return }
        let targetIndex = context.index - 1
        guard targetIndex >= 0 else { return }
        document.insertLayer(selected, to: context.parent, at: targetIndex)
        bumpDocument()
        selectedLayerID = selectionID(for: selected.id, in: document.root)
        refreshPreview()
        statusMessage = "Moved \(selected.name) down"
    }

    func requestReplaceSelectedLayerPixelsFromPNG() {
        guard let path = selectedLayerPath else {
            statusMessage = "Select a pixel layer first."
            return
        }
        requestReplaceLayerPixelsFromPNG(at: path)
    }

    func replaceSelectedLayerPixelsFromPNG(policy: ReplacePixelSizePolicy = .matchImageSize) {
        guard let path = selectedLayerPath else {
            statusMessage = "Select a pixel layer first."
            return
        }
        replaceLayerPixelsFromPNG(at: path, policy: policy)
    }

    func requestReplaceLayerPixelsFromPNG(at path: LayerPath) {
        guard let document,
              LayerListFlattener.resolveLayer(in: document.root, path: path) as? PixelLayer != nil
        else {
            statusMessage = "Select a pixel layer first."
            return
        }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.title = "Replace Layer Pixels from PNG"
        panel.message = "Choose PNG source for replacement"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        pendingReplacePixelsContext = PendingReplacePixelsContext(path: path, pngURL: url)
        isShowingReplacePixelSizePolicyDialog = true
    }

    func confirmReplaceLayerPixels(policy: ReplacePixelSizePolicy) {
        guard let context = pendingReplacePixelsContext else { return }
        pendingReplacePixelsContext = nil
        isShowingReplacePixelSizePolicyDialog = false
        replaceLayerPixelsFromPNG(at: context.path, url: context.pngURL, policy: policy)
    }

    func cancelReplaceLayerPixels() {
        pendingReplacePixelsContext = nil
        isShowingReplacePixelSizePolicyDialog = false
        statusMessage = "Replace pixels canceled."
    }

    func toggleLayerVisibility(at path: LayerPath) {
        guard let item = layerItems.first(where: { $0.path == path }) else { return }
        guard LayerViewerPolicy.canToggleVisibility(for: item) else {
            statusMessage = "Select a pixel layer to toggle visibility."
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
              LayerViewerPolicy.editPolicy(path: path, layer: layer) == .editablePixel
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
              LayerViewerPolicy.editPolicy(path: path, layer: layer) == .editablePixel
        else { return }
        layer.opacity = opacity
        markDirty()
        statusMessage = "\(layer.name) opacity: \(opacity)"
    }

    func setLayerBlendMode(at path: LayerPath, blendMode: PSDKit.BlendMode) {
        guard let document,
              let layer = LayerListFlattener.resolveLayer(in: document.root, path: path) as? PixelLayer,
              LayerViewerPolicy.editPolicy(path: path, layer: layer) == .editablePixel
        else { return }
        switch blendMode {
        case .normal, .multiply, .add:
            layer.blendMode = blendMode
            markDirty()
            statusMessage = "\(layer.name) blend: \(BlendModeDisplayName.text(for: blendMode))"
        case .passThrough, .unknown:
            statusMessage = "Unsupported blend mode for pixel layer."
        }
    }

    func setLayerFrame(at path: LayerPath, left: Int, top: Int, width: Int, height: Int) {
        guard width > 0, height > 0 else {
            statusMessage = "Layer frame width/height must be greater than zero."
            return
        }
        guard let document,
              let layer = LayerListFlattener.resolveLayer(in: document.root, path: path) as? PixelLayer,
              LayerViewerPolicy.editPolicy(path: path, layer: layer) == .editablePixel
        else { return }

        do {
            if layer.frame.width != width || layer.frame.height != height {
                let resized = try resizePixelBuffer(layer.pixels, width: width, height: height)
                layer.pixels = resized
            }
            layer.frame = PSDRect(left: left, top: top, right: left + width, bottom: top + height)
            markDirty()
            statusMessage = "\(layer.name) frame updated"
        } catch let error as PSDError {
            errorMessage = error.userMessage
            statusMessage = "Frame update failed."
        } catch {
            errorMessage = error.localizedDescription
            statusMessage = "Frame update failed."
        }
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
            let parent = preferredInsertionParent(in: document)
            document.appendLayer(layer, to: parent)
            bumpDocument()
            selectedLayerID = selectionID(for: layer.id, in: document.root)
            refreshPreview()
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

    func replaceLayerPixelsFromPNG(at path: LayerPath, policy: ReplacePixelSizePolicy = .matchImageSize) {
        guard let document,
              LayerListFlattener.resolveLayer(in: document.root, path: path) as? PixelLayer != nil
        else {
            statusMessage = "Select a pixel layer first."
            return
        }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.title = "Replace Layer Pixels from PNG"
        panel.message = "Choose PNG source for replacement"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        replaceLayerPixelsFromPNG(at: path, url: url, policy: policy)
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
            let parent = preferredInsertionParent(in: document)
            document.appendLayer(layer, to: parent)
            bumpDocument()
            selectedLayerID = selectionID(for: layer.id, in: document.root)
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
        guard let document, let layer = selectedLayer, let path = selectedLayerPath else {
            statusMessage = "Select a layer to remove."
            return
        }
        guard layer is PixelLayer else {
            statusMessage = "Group deletion is not enabled in this phase."
            return
        }
        let removedName = layer.name
        document.removeLayer(layer)
        selectNeighborAfterRemoving(path: path, in: document)
        bumpDocument()
        refreshPreview()
        statusMessage = "Removed \(removedName)"
        errorMessage = nil
    }

    func captureSnapshot(label: String) {
        guard let document else { return }
        let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            statusMessage = "Snapshot label cannot be empty."
            return
        }
        let records = snapshotRecords(from: document.root, prefix: [])
        let entry = SnapshotEntry(
            id: UUID(),
            label: trimmed,
            createdAt: Date(),
            records: records
        )
        snapshots.append(entry)
        if snapshots.count >= 2 {
            let before = snapshots[snapshots.count - 2]
            let after = snapshots[snapshots.count - 1]
            snapshotDiffDescription = Self.makeSnapshotDiffDescription(
                from: before,
                to: after
            )
        } else {
            snapshotDiffDescription = "Captured \(trimmed). Capture one more snapshot to inspect differences."
        }
        statusMessage = "Captured snapshot \"\(trimmed)\""
    }

    func clearSnapshots() {
        snapshots.removeAll()
        snapshotDiffDescription = "Capture at least two snapshots to inspect differences."
        statusMessage = "Snapshots cleared."
    }

    func setManualValidationItem(id: String, checked: Bool) {
        manualValidationState[id] = checked
        persistManualValidationState()
    }

    func resetManualValidationChecklist() {
        manualValidationState = [:]
        persistManualValidationState()
        statusMessage = "Manual validation checklist reset."
    }

    func revealSuggestedRoundtripExportInFinder() {
        NSWorkspace.shared.activateFileViewerSelecting([suggestedRoundtripExportURL])
    }

    func openHardRejectSmokeFixturesFromGolden() {
        var base = URL(fileURLWithPath: #filePath)
        for _ in 0 ..< 5 {
            base.deleteLastPathComponent()
        }
        let goldenPath = base.appendingPathComponent("Tests/PSDKitTests/Golden/rejections")
        guard FileManager.default.fileExists(atPath: goldenPath.path) else {
            statusMessage = "Golden hard-reject fixtures folder not found."
            return
        }
        NSWorkspace.shared.open(goldenPath)
        statusMessage = "Opened Golden hard-reject fixtures folder."
    }

    private func markDirty() {
        document?.markContentModified()
        bumpDocument()
        refreshPreview()
    }

    private func bumpDocument() {
        documentRevision += 1
    }

    private func syncEditorViewportCanvasSize(with document: PSDDocument) {
        let canvasSize = CGSize(
            width: document.canvasSize.width,
            height: document.canvasSize.height
        )
        guard editorViewport.canvasSize != canvasSize else { return }
        editorViewport = EditorViewport(
            canvasSize: canvasSize,
            viewSize: editorViewport.viewSize,
            scale: editorViewport.scale,
            translation: editorViewport.translation
        )
    }

    private func clearTransientPanelsForNewSession() {
        documentSessionID = UUID()
        editorAdapter = nil
        writebackDiagnostics = .empty
        writebackState = .idleClean
        resetEditorInputState()
        isShowingCompatibilityReport = false
        isShowingLossySaveConfirmation = false
        isShowingUnsavedCloseConfirmation = false
        isShowingDeleteGroupConfirmation = false
        isShowingReplacePixelSizePolicyDialog = false
        collapsedGroupIDs = []
        pendingSaveContext = nil
        pendingReplacePixelsContext = nil
        pendingDeleteGroupPath = nil
        pendingCloseAction = nil
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

    private func requestSave(to url: URL, updateFileURL: Bool, successPrefix: String) {
        guard let document else { return }
        let context = PendingSaveContext(
            url: url,
            updateFileURL: updateFileURL,
            successPrefix: successPrefix
        )
        let requiresLossyConfirmation = shouldRequireLossySaveConfirmation?(document)
            ?? document.compatibilityReport.hasLossyChanges
        if requiresLossyConfirmation && document.hasUnsavedChanges {
            pendingSaveContext = context
            isShowingLossySaveConfirmation = true
            statusMessage = "This document includes lossy compatibility changes. Confirm before saving."
            return
        }
        performSave(using: context)
    }

    private func performSave(using context: PendingSaveContext) {
        guard let document else { return }
        do {
            try document.save(to: context.url)
            if context.updateFileURL {
                fileURL = context.url
            }
            statusMessage = "\(context.successPrefix) \(context.url.lastPathComponent)"
            errorMessage = nil
            bumpDocument()
            refreshPreview()
            syncWritebackState()
        } catch let error as PSDError {
            errorMessage = error.userMessage
            statusMessage = "Save failed."
        } catch {
            errorMessage = error.localizedDescription
            statusMessage = "Save failed."
        }
    }

    private func replaceLayerPixelsFromPNG(at path: LayerPath, url: URL, policy: ReplacePixelSizePolicy) {
        guard let document,
              let layer = LayerListFlattener.resolveLayer(in: document.root, path: path) as? PixelLayer
        else {
            statusMessage = "Select a pixel layer first."
            return
        }
        do {
            let (rgba, width, height) = try ImageImport.loadRGBA(from: url)
            let left = layer.frame.left
            let top = layer.frame.top
            if policy == .matchImageSize {
                layer.pixels = try PixelBuffer(width: width, height: height, rgba: rgba)
                layer.frame = PSDRect(left: left, top: top, right: left + width, bottom: top + height)
            } else {
                let fitted = try fitRGBA(
                    source: rgba,
                    sourceWidth: width,
                    sourceHeight: height,
                    targetWidth: layer.frame.width,
                    targetHeight: layer.frame.height
                )
                layer.pixels = try PixelBuffer(
                    width: layer.frame.width,
                    height: layer.frame.height,
                    rgba: fitted
                )
            }
            markDirty()
            statusMessage = "Replaced pixels for \(layer.name) using \(url.lastPathComponent)"
            errorMessage = nil
        } catch let error as PSDError {
            errorMessage = error.userMessage
            statusMessage = "Replace pixels failed."
        } catch {
            errorMessage = error.localizedDescription
            statusMessage = "Replace pixels failed."
        }
    }

    private func preferredInsertionParent(in document: PSDDocument) -> GroupLayer {
        guard let selected = selectedLayer else { return document.root }
        if let group = selected as? GroupLayer {
            return group
        }
        return selected.parent ?? document.root
    }

    private func selectionID(for layerID: UUID, in root: GroupLayer) -> String? {
        pathForLayer(id: layerID, in: root, prefix: [])?.selectionID
    }

    private func siblingContext(for path: LayerPath, in document: PSDDocument) -> (parent: GroupLayer, index: Int)? {
        guard let index = path.indices.last else { return nil }
        let parentPath = Array(path.indices.dropLast())
        let parent: GroupLayer
        if parentPath.isEmpty {
            parent = document.root
        } else if let resolved = LayerListFlattener.resolveLayer(
            in: document.root,
            path: LayerPath(indices: parentPath)
        ) as? GroupLayer {
            parent = resolved
        } else {
            return nil
        }
        guard index >= 0, index < parent.children.count else { return nil }
        return (parent, index)
    }

    private func wouldCreateGroupCycle(group: GroupLayer, destination: GroupLayer) -> Bool {
        if group === destination { return true }
        var ancestor = destination.parent
        while let current = ancestor {
            if current === group { return true }
            ancestor = current.parent
        }
        return false
    }

    private func pathForLayer(id: UUID, in group: GroupLayer, prefix: [Int]) -> LayerPath? {
        for (index, child) in group.children.enumerated() {
            let path = prefix + [index]
            if child.id == id {
                return LayerPath(indices: path)
            }
            if let nested = child as? GroupLayer,
               let nestedPath = pathForLayer(id: id, in: nested, prefix: path)
            {
                return nestedPath
            }
        }
        return nil
    }

    private func collectGroupDestinations(
        from group: GroupLayer,
        pathPrefix: [Int],
        selectedLayer: (any LayerProtocol)?,
        into destinations: inout [GroupDestination]
    ) {
        for (index, child) in group.children.enumerated() {
            guard let nested = child as? GroupLayer else { continue }
            if let selectedGroup = selectedLayer as? GroupLayer,
               (nested === selectedGroup || wouldCreateGroupCycle(group: selectedGroup, destination: nested))
            {
                continue
            }
            let path = pathPrefix + [index]
            let layerPath = LayerPath(indices: path)
            let title = nested.name.isEmpty ? "Unnamed Group (\(layerPath.selectionID))" : nested.name
            destinations.append(
                GroupDestination(
                    id: layerPath.selectionID,
                    title: title,
                    path: layerPath
                )
            )
            collectGroupDestinations(
                from: nested,
                pathPrefix: path,
                selectedLayer: selectedLayer,
                into: &destinations
            )
        }
    }

    private func isStrictDescendant(_ candidate: [Int], of ancestor: [Int]) -> Bool {
        guard candidate.count > ancestor.count else { return false }
        return Array(candidate.prefix(ancestor.count)) == ancestor
    }

    private func snapshotRecords(from group: GroupLayer, prefix: [Int]) -> [SnapshotRecord] {
        var result: [SnapshotRecord] = []
        for (index, child) in group.children.enumerated() {
            let current = prefix + [index]
            let path = current.map(String.init).joined(separator: "/")
            if let pixel = child as? PixelLayer {
                result.append(
                    SnapshotRecord(
                        path: path,
                        kind: "pixel",
                        name: pixel.name,
                        isVisible: pixel.isVisible,
                        opacity: pixel.opacity,
                        blendMode: pixel.blendMode.fourCC,
                        frame: pixel.frame,
                        pixelDigest: pixel.pixels.rgba.hashValue
                    )
                )
            } else if let nested = child as? GroupLayer {
                result.append(
                    SnapshotRecord(
                        path: path,
                        kind: "group",
                        name: nested.name,
                        isVisible: nested.isVisible,
                        opacity: nested.opacity,
                        blendMode: nested.blendMode.fourCC,
                        frame: nested.frame,
                        pixelDigest: nil
                    )
                )
                result.append(contentsOf: snapshotRecords(from: nested, prefix: current))
            }
        }
        return result
    }

    private static func makeSnapshotDiffDescription(from before: SnapshotEntry, to after: SnapshotEntry) -> String {
        var lines: [String] = []
        let beforeMap = Dictionary(uniqueKeysWithValues: before.records.map { ($0.path, $0) })
        let afterMap = Dictionary(uniqueKeysWithValues: after.records.map { ($0.path, $0) })
        let allPaths = Set(beforeMap.keys).union(afterMap.keys).sorted()
        for path in allPaths {
            let lhs = beforeMap[path]
            let rhs = afterMap[path]
            switch (lhs, rhs) {
            case let (l?, r?):
                if l.signature != r.signature {
                    lines.append("[changed] \(path): \(l.name) -> \(r.name)")
                }
            case let (l?, nil):
                lines.append("[removed] \(path): \(l.name)")
            case let (nil, r?):
                lines.append("[added] \(path): \(r.name)")
            case (nil, nil):
                continue
            }
        }
        if lines.isEmpty {
            return "No differences between \"\(before.label)\" and \"\(after.label)\"."
        }
        let header = "Diff \(before.label) -> \(after.label)"
        return ([header] + lines).joined(separator: "\n")
    }

    private static func loadManualValidationState(from defaults: UserDefaults) -> [String: Bool] {
        guard let raw = defaults.dictionary(forKey: manualValidationStateKey) as? [String: Bool] else {
            return [:]
        }
        return raw
    }

    private func persistManualValidationState() {
        userDefaults.set(manualValidationState, forKey: Self.manualValidationStateKey)
    }

    private func selectNeighborAfterRemoving(path: LayerPath, in document: PSDDocument) {
        guard !path.indices.isEmpty else {
            selectedLayerID = nil
            return
        }
        let removedIndex = path.indices.last ?? 0
        let parentPathIndices = Array(path.indices.dropLast())
        let parent: GroupLayer
        if parentPathIndices.isEmpty {
            parent = document.root
        } else if let resolved = LayerListFlattener.resolveLayer(
            in: document.root,
            path: LayerPath(indices: parentPathIndices)
        ) as? GroupLayer {
            parent = resolved
        } else {
            selectedLayerID = nil
            return
        }

        if parent.children.isEmpty {
            selectedLayerID = parentPathIndices.isEmpty
                ? nil
                : LayerPath(indices: parentPathIndices).selectionID
            return
        }
        let newIndex = min(removedIndex, parent.children.count - 1)
        selectedLayerID = LayerPath(indices: parentPathIndices + [newIndex]).selectionID
    }

    private func resizePixelBuffer(_ source: PixelBuffer, width: Int, height: Int) throws -> PixelBuffer {
        let resampled = try PixelBufferResampler.resampleRGBA(
            source: source.rgba,
            sourceWidth: source.width,
            sourceHeight: source.height,
            targetWidth: width,
            targetHeight: height
        )
        return try PixelBuffer(width: width, height: height, rgba: resampled)
    }

    private func fitRGBA(
        source: Data,
        sourceWidth: Int,
        sourceHeight: Int,
        targetWidth: Int,
        targetHeight: Int
    ) throws -> Data {
        guard source.count == sourceWidth * sourceHeight * 4 else {
            throw PSDError.corruptStructure("invalid source RGBA byte count")
        }
        var result = Data(repeating: 0, count: targetWidth * targetHeight * 4)
        let copyWidth = min(sourceWidth, targetWidth)
        let copyHeight = min(sourceHeight, targetHeight)
        for y in 0 ..< copyHeight {
            for x in 0 ..< copyWidth {
                let sourceOffset = (y * sourceWidth + x) * 4
                let targetOffset = (y * targetWidth + x) * 4
                result[targetOffset] = source[sourceOffset]
                result[targetOffset + 1] = source[sourceOffset + 1]
                result[targetOffset + 2] = source[sourceOffset + 2]
                result[targetOffset + 3] = source[sourceOffset + 3]
            }
        }
        return result
    }
}
