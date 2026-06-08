import Foundation
import PSDKit
import XCTest
@testable import PSDViewer

@MainActor
final class DocumentModelCompatibilityTests: XCTestCase {
    func testCompatibilitySummaryNilWhenFullySupported() {
        XCTAssertNil(DocumentModel.compatibilitySummary(from: .empty))
    }

    func testCompatibilitySummaryIncludesSingleIssueMessage() {
        let report = PSDCompatibilityReport(
            issues: [
                PSDCompatibilityIssue(
                    severity: .warning,
                    kind: .unsupportedMask,
                    layerName: "Layer 1",
                    message: "Layer mask is not supported; mask was ignored."
                ),
            ],
            hasLossyChanges: true
        )
        let summary = DocumentModel.compatibilitySummary(from: report)
        XCTAssertEqual(
            summary,
            "部分 PSD 特性不受支持，已降级、忽略或丢弃。 Layer mask is not supported; mask was ignored."
        )
    }

    func testCompatibilitySummaryCountsMultipleIssues() {
        let report = PSDCompatibilityReport(
            issues: [
                PSDCompatibilityIssue(
                    severity: .warning,
                    kind: .unsupportedBlendMode,
                    layerName: "A",
                    message: "Unsupported blend mode; layer was imported as Normal."
                ),
                PSDCompatibilityIssue(
                    severity: .warning,
                    kind: .droppedLayer,
                    layerName: "B",
                    message: "Layer was omitted from the editable document."
                ),
            ],
            hasLossyChanges: true
        )
        let summary = DocumentModel.compatibilitySummary(from: report)
        XCTAssertEqual(
            summary,
            "部分 PSD 特性不受支持，已降级、忽略或丢弃。（2 项警告）"
        )
    }

    func testOpenFailureKeepsExistingDocumentSession() throws {
        let model = DocumentModel()
        model.generateStandardTestDocument()
        let beforeTitle = model.navigationTitle
        let beforeSummary = model.statusSummary
        let beforeLayerCount = model.layerItems.count

        let missing = FileManager.default.temporaryDirectory.appendingPathComponent("missing-\(UUID().uuidString).psd")
        model.open(url: missing)

        XCTAssertEqual(model.layerItems.count, beforeLayerCount)
        XCTAssertEqual(model.navigationTitle, beforeTitle)
        XCTAssertEqual(model.statusSummary, beforeSummary)
        XCTAssertNotNil(model.errorMessage)
        XCTAssertTrue(model.statusMessage.contains("remains unchanged"))
    }

    func testLossySaveCancelKeepsDirtyAndNoWrite() throws {
        let model = DocumentModel()
        model.generateStandardTestDocument()
        let temp = makeTempPSDURL("lossy-cancel")
        defer { try? FileManager.default.removeItem(at: temp) }
        try model.document?.save(to: temp)

        model.open(url: temp)
        model.shouldRequireLossySaveConfirmation = { _ in true }
        guard let path = model.selectedLayerPath else {
            XCTFail("missing selected layer path")
            return
        }
        model.renameLayer(at: path, to: "Dirty Rename")
        XCTAssertTrue(model.hasUnsavedChanges)

        model.saveDocumentAs(urlOverrideForTests: temp)
        XCTAssertTrue(model.isShowingLossySaveConfirmation)

        let beforeStat = try fileModificationDate(temp)
        model.cancelLossySave()
        let afterStat = try fileModificationDate(temp)

        XCTAssertEqual(beforeStat, afterStat)
        XCTAssertTrue(model.hasUnsavedChanges)
        XCTAssertEqual(model.statusMessage, "Save canceled.")
    }

    func testLossySaveViewDetailsAndCancelKeepsDialogStateExpected() throws {
        let model = DocumentModel()
        model.generateStandardTestDocument()
        let temp = makeTempPSDURL("lossy-details-cancel")
        defer { try? FileManager.default.removeItem(at: temp) }
        try model.document?.save(to: temp)
        model.open(url: temp)
        model.shouldRequireLossySaveConfirmation = { _ in true }
        guard let path = model.selectedLayerPath else {
            XCTFail("missing selected layer path")
            return
        }
        model.renameLayer(at: path, to: "Needs Details")
        model.saveDocumentAs(urlOverrideForTests: temp)

        XCTAssertTrue(model.isShowingLossySaveConfirmation)
        model.showCompatibilityReport()
        XCTAssertTrue(model.isShowingCompatibilityReport)

        model.cancelLossySave()
        XCTAssertFalse(model.isShowingLossySaveConfirmation)
        XCTAssertTrue(model.hasUnsavedChanges)
    }

    func testLossySaveContinueWritesAndClearsDirty() throws {
        let model = DocumentModel()
        model.generateStandardTestDocument()
        let temp = makeTempPSDURL("lossy-continue")
        defer { try? FileManager.default.removeItem(at: temp) }
        try model.document?.save(to: temp)

        model.open(url: temp)
        model.shouldRequireLossySaveConfirmation = { _ in true }
        guard let path = model.selectedLayerPath else {
            XCTFail("missing selected layer path")
            return
        }
        model.renameLayer(at: path, to: "Continue Rename")
        XCTAssertTrue(model.hasUnsavedChanges)

        model.saveDocumentAs(urlOverrideForTests: temp)
        XCTAssertTrue(model.isShowingLossySaveConfirmation)

        model.continueLossySave()
        XCTAssertFalse(model.hasUnsavedChanges)
        XCTAssertFalse(model.isShowingLossySaveConfirmation)
    }

    func testLossySaveViewDetailsShowsReport() throws {
        let model = DocumentModel()
        model.generateStandardTestDocument()
        let temp = makeTempPSDURL("lossy-details")
        defer { try? FileManager.default.removeItem(at: temp) }
        try model.document?.save(to: temp)

        model.open(url: temp)
        model.shouldRequireLossySaveConfirmation = { _ in true }
        guard let path = model.selectedLayerPath else {
            XCTFail("missing selected layer path")
            return
        }
        model.renameLayer(at: path, to: "Need Details")
        model.saveDocumentAs(urlOverrideForTests: temp)

        XCTAssertTrue(model.isShowingLossySaveConfirmation)
        model.showCompatibilityReport()
        XCTAssertTrue(model.isShowingCompatibilityReport)
    }

    func testManualValidationChecklistPersistsViaInjectedUserDefaults() {
        let suite = "psdviewer-tests-\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suite) else {
            XCTFail("unable to create user defaults suite")
            return
        }
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }

        let model = DocumentModel(userDefaults: defaults)
        model.setManualValidationItem(id: "p1-snapshots", checked: true)
        model.setManualValidationItem(id: "p1-frame", checked: true)

        let restored = DocumentModel(userDefaults: defaults)
        XCTAssertEqual(restored.manualValidationState["p1-snapshots"], true)
        XCTAssertEqual(restored.manualValidationState["p1-frame"], true)
    }

    func testSnapshotDiffReportsChangedLayerName() {
        let model = DocumentModel()
        model.generateStandardTestDocument()
        model.captureSnapshot(label: "Before")

        guard let path = model.selectedLayerPath else {
            XCTFail("missing selected layer path")
            return
        }
        model.renameLayer(at: path, to: "Renamed")
        model.captureSnapshot(label: "After")

        XCTAssertEqual(model.snapshots.count, 2)
        XCTAssertTrue(model.snapshotDiffDescription.contains("[changed]"))
        XCTAssertTrue(model.snapshotDiffDescription.contains("Before"))
        XCTAssertTrue(model.snapshotDiffDescription.contains("After"))
    }

    func testGroupCollapseHidesDescendantsAndRestores() {
        let model = DocumentModel()
        model.generateStandardTestDocument()

        guard let groupA = model.layerItems.first(where: { $0.displayKind == .group && $0.name == "Group A" }) else {
            XCTFail("missing Group A")
            return
        }
        let initialNames = model.layerItems.map(\.name)
        XCTAssertTrue(initialNames.contains("Red"))

        model.toggleGroupCollapsed(at: groupA.path)
        let collapsedNames = model.layerItems.map(\.name)
        XCTAssertFalse(collapsedNames.contains("Red"))

        model.toggleGroupCollapsed(at: groupA.path)
        let expandedNames = model.layerItems.map(\.name)
        XCTAssertTrue(expandedNames.contains("Red"))
    }

    func testSelectedGroupDestinationIDTracksParentPath() {
        let model = DocumentModel()
        model.generateStandardTestDocument()

        guard let red = model.layerItems.first(where: { $0.name == "Red" }) else {
            XCTFail("missing Red layer")
            return
        }
        model.selectedLayerID = red.id
        XCTAssertNotEqual(model.selectedGroupDestinationID, "root")
    }

    func testRequestCloseWithoutDirtyRunsActionImmediately() {
        let model = DocumentModel()
        model.generateStandardTestDocument()
        let temp = makeTempPSDURL("close-clean")
        defer { try? FileManager.default.removeItem(at: temp) }
        try? model.document?.save(to: temp)

        var closed = false
        model.requestCloseDocument { closed = true }
        XCTAssertTrue(closed)
        XCTAssertFalse(model.isShowingUnsavedCloseConfirmation)
    }

    func testRequestCloseWithDirtyRequiresConfirmation() {
        let model = DocumentModel()
        model.generateStandardTestDocument()
        guard let path = model.selectedLayerPath else {
            XCTFail("missing selected layer path")
            return
        }
        model.renameLayer(at: path, to: "Dirty for close")

        var closed = false
        model.requestCloseDocument { closed = true }
        XCTAssertFalse(closed)
        XCTAssertTrue(model.isShowingUnsavedCloseConfirmation)
    }

    func testGroupAddMoveReorderDeleteFlow() {
        let model = DocumentModel()
        model.generateStandardTestDocument()

        model.addGroup()
        guard let groupPath = model.selectedLayerPath else {
            XCTFail("new group should be selected")
            return
        }
        XCTAssertTrue(model.canDeleteSelectedGroup)

        model.addPixelLayer()
        guard model.selectedLayerPath != nil else {
            XCTFail("new layer should be selected")
            return
        }

        let destinations = model.groupMoveDestinations
        guard let target = destinations.first(where: { $0.id != "root" }) else {
            XCTFail("expected at least one group destination")
            return
        }
        model.moveSelectedLayer(to: target.id)
        XCTAssertEqual(model.statusMessage.contains("Moved"), true)

        model.moveSelectedLayerDown()
        model.moveSelectedLayerUp()
        XCTAssertTrue(model.statusMessage.contains("Moved"))

        model.selectedLayerID = groupPath.selectionID
        model.requestDeleteSelectedGroup()
        XCTAssertTrue(model.isShowingDeleteGroupConfirmation)
        model.confirmDeleteSelectedGroup()
        XCTAssertFalse(model.isShowingDeleteGroupConfirmation)
    }

    func testResetManualValidationChecklistClearsProgress() {
        let model = DocumentModel(userDefaults: UserDefaults(suiteName: "psdviewer-reset-\(UUID().uuidString)") ?? .standard)
        model.setManualValidationItem(id: "p1-snapshots", checked: true)
        XCTAssertEqual(model.manualValidationChecklistProgressText.hasPrefix("1"), true)
        model.resetManualValidationChecklist()
        XCTAssertEqual(model.manualValidationState["p1-snapshots"], nil)
    }

    func testRefreshPreviewRoutesToMetalWhenRoutingAllows() {
        let model = DocumentModel()
        model.previewRoutingFallbackReasonProvider = { _, _ in nil }
        model.generateStandardTestDocument()

        XCTAssertTrue(model.usesMetalPreview)
        XCTAssertNotNil(model.renderSnapshot)
        XCTAssertNil(model.previewImage)
        XCTAssertNil(model.previewFallbackReason)
    }

    func testRefreshPreviewFallsBackToCPUForUnsupportedBlend() throws {
        let suite = "psdviewer-unsupported-blend-\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suite) else {
            XCTFail("unable to create user defaults suite")
            return
        }
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }

        let model = DocumentModel(userDefaults: defaults)
        XCTAssertTrue(model.userPrefersMetalPreview)
        model.loadDocumentForTests(try makeDocumentWithUnsupportedBlend())

        XCTAssertFalse(model.usesMetalPreview)
        XCTAssertNotNil(model.renderSnapshot)
        XCTAssertNotNil(model.previewImage)
        XCTAssertEqual(
            model.previewFallbackReason,
            EditorPreviewRouting.FallbackReason.unsupportedBlendMode(.unknown).statusMessage
        )
    }

    func testRefreshPreviewFallsBackToCPUWhenUserDisablesMetal() {
        let suite = "psdviewer-metal-pref-\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suite) else {
            XCTFail("unable to create user defaults suite")
            return
        }
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }

        let model = DocumentModel(userDefaults: defaults)
        model.previewRoutingFallbackReasonProvider = { _, userPrefersMetal in
            userPrefersMetal ? nil : .userDisabledMetal
        }
        model.generateStandardTestDocument()
        XCTAssertTrue(model.usesMetalPreview)

        model.userPrefersMetalPreview = false

        XCTAssertFalse(model.usesMetalPreview)
        XCTAssertNotNil(model.previewImage)
        XCTAssertEqual(
            model.previewFallbackReason,
            EditorPreviewRouting.FallbackReason.userDisabledMetal.statusMessage
        )
    }

    private func makeDocumentWithUnsupportedBlend() throws -> PSDDocument {
        let root = GroupLayer(name: "")
        let layer = try PixelLayer(
            name: "Unsupported",
            frame: PSDRect(left: 0, top: 0, right: 1, bottom: 1),
            pixels: PixelBuffer(width: 1, height: 1, rgba: Data([255, 0, 0, 255])),
            blendMode: .unknown
        )
        root.append(layer)
        return try PSDDocument.create(canvasSize: PSDSize(width: 1, height: 1), root: root)
    }

    private func makeTempPSDURL(_ prefix: String) -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("\(prefix)-\(UUID().uuidString).psd")
    }

    private func fileModificationDate(_ url: URL) throws -> Date {
        let values = try url.resourceValues(forKeys: [.contentModificationDateKey])
        return values.contentModificationDate ?? Date.distantPast
    }
}
