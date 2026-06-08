import CoreGraphics
import XCTest
import PSDKit
@testable import PSDViewer

@MainActor
final class StrokePreviewLifecycleTests: XCTestCase {
    func testStrokeEndedDoesNotModifyPSDPixelsOrMarkDirty() throws {
        let model = DocumentModel()
        model.generateStandardTestDocument()
        model.setEditorTool(.brush)

        guard let layer = model.selectedPixelLayer else {
            XCTFail("expected selected pixel layer")
            return
        }
        let digestBefore = EditorPixelRevisionDigest.digest(rgba: layer.pixels.rgba)
        let dirtyBefore = model.hasUnsavedChanges

        model.editorViewport = EditorViewport(
            canvasSize: CGSize(width: 16, height: 16),
            viewSize: CGSize(width: 160, height: 160),
            scale: 10,
            translation: .zero
        )

        model.handleRawPointerEvent(RawPointerEvent(viewPoint: CGPoint(x: 50, y: 50), phase: .began, pressure: 0, timestamp: 0))
        model.handleRawPointerEvent(RawPointerEvent(viewPoint: CGPoint(x: 80, y: 80), phase: .moved, pressure: 0, timestamp: 0.1))
        model.handleRawPointerEvent(RawPointerEvent(viewPoint: CGPoint(x: 100, y: 100), phase: .ended, pressure: 0, timestamp: 0.2))

        XCTAssertEqual(model.editorState.strokeSession.phase, .idle)
        XCTAssertNotNil(model.pendingStrokeCommit)
        XCTAssertNil(model.activeStrokePreview)
        XCTAssertEqual(model.hasUnsavedChanges, dirtyBefore)

        guard let pending = model.pendingStrokeCommit else { return }
        XCTAssertGreaterThan(pending.dabCount, 0)
        XCTAssertGreaterThan(pending.sampleCount, 0)
        XCTAssertFalse(pending.dirtyRegion.isEmpty)
        XCTAssertEqual(model.strokePreviewDiagnostics.lastStrokeResult, "ended-pending-commit")

        guard let snapshot = model.renderSnapshot else {
            XCTFail("expected render snapshot")
            return
        }
        XCTAssertEqual(pending.documentSessionID, snapshot.documentSessionID)
        XCTAssertEqual(pending.documentRevision, snapshot.documentRevision)
        let layerSnapshot = snapshot.layers.first(where: { $0.id == pending.layerID })
        XCTAssertEqual(pending.layerPixelRevision, layerSnapshot?.pixelRevision)
        XCTAssertEqual(pending.layerUUID, layerSnapshot?.layerUUID)

        let digestAfter = EditorPixelRevisionDigest.digest(rgba: layer.pixels.rgba)
        XCTAssertEqual(digestBefore, digestAfter)
    }

    func testActiveStrokeUpdatesPreviewDiagnosticsOnMetalPath() {
        let model = DocumentModel()
        model.generateStandardTestDocument()
        model.setEditorTool(.brush)
        model.editorViewport = EditorViewport(
            canvasSize: CGSize(width: 16, height: 16),
            viewSize: CGSize(width: 160, height: 160),
            scale: 10,
            translation: .zero
        )

        model.handleRawPointerEvent(RawPointerEvent(viewPoint: CGPoint(x: 50, y: 50), phase: .began, pressure: 0, timestamp: 0))

        if model.usesMetalPreview {
            XCTAssertTrue(model.strokePreviewDiagnostics.isPreviewActive)
            XCTAssertGreaterThan(model.strokePreviewDiagnostics.dabCount, 0)
            XCTAssertNotNil(model.activeStrokePreview)
        } else {
            XCTAssertEqual(
                model.strokePreviewDiagnostics.rejectionReason,
                "brush-preview-unavailable-cpu-fallback"
            )
        }
    }

    func testCancelledStrokeClearsPreviewWithoutPendingCommit() {
        let model = DocumentModel()
        model.generateStandardTestDocument()
        model.setEditorTool(.brush)
        model.editorViewport = EditorViewport(
            canvasSize: CGSize(width: 16, height: 16),
            viewSize: CGSize(width: 160, height: 160),
            scale: 10,
            translation: .zero
        )

        model.handleRawPointerEvent(RawPointerEvent(viewPoint: CGPoint(x: 50, y: 50), phase: .began, pressure: 0, timestamp: 0))
        model.handleRawPointerEvent(RawPointerEvent(viewPoint: CGPoint(x: 50, y: 50), phase: .cancelled, pressure: 0, timestamp: 0.1))

        XCTAssertNil(model.pendingStrokeCommit)
        XCTAssertNil(model.activeStrokePreview)
        XCTAssertFalse(model.strokePreviewDiagnostics.isPreviewActive)
        XCTAssertEqual(model.strokePreviewDiagnostics.dabCount, 0)
        XCTAssertEqual(model.strokePreviewDiagnostics.lastStrokeResult, "stroke cancelled")
    }

    func testCPUFallbackRejectsBrushPreviewWithoutWritingPixels() throws {
        let suite = "psdviewer-cpu-brush-\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suite) else {
            XCTFail("unable to create user defaults suite")
            return
        }
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }

        let model = DocumentModel(userDefaults: defaults)
        model.generateStandardTestDocument()
        model.userPrefersMetalPreview = false
        model.refreshPreview()
        XCTAssertFalse(model.usesMetalPreview)

        model.setEditorTool(.brush)
        guard let layer = model.selectedPixelLayer else {
            XCTFail("missing layer")
            return
        }
        let digestBefore = EditorPixelRevisionDigest.digest(rgba: layer.pixels.rgba)

        model.editorViewport = EditorViewport(
            canvasSize: CGSize(width: 16, height: 16),
            viewSize: CGSize(width: 160, height: 160),
            scale: 10,
            translation: .zero
        )
        model.handleRawPointerEvent(RawPointerEvent(viewPoint: CGPoint(x: 50, y: 50), phase: .began, pressure: 0, timestamp: 0))
        XCTAssertEqual(
            model.strokePreviewDiagnostics.rejectionReason,
            "brush-preview-unavailable-cpu-fallback"
        )

        let dirtyBefore = model.hasUnsavedChanges
        model.handleRawPointerEvent(RawPointerEvent(viewPoint: CGPoint(x: 100, y: 100), phase: .ended, pressure: 0, timestamp: 0.2))

        XCTAssertNotNil(model.pendingStrokeCommit)
        XCTAssertEqual(model.hasUnsavedChanges, dirtyBefore)

        let digestAfter = EditorPixelRevisionDigest.digest(rgba: layer.pixels.rgba)
        XCTAssertEqual(digestBefore, digestAfter)
    }
}
