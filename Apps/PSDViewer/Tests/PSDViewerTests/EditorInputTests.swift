import CoreGraphics
import XCTest
import PSDKit
@testable import PSDViewer

final class EditorInputTests: XCTestCase {
    private let viewport = EditorViewport(
        canvasSize: CGSize(width: 100, height: 100),
        viewSize: CGSize(width: 200, height: 200),
        scale: 2,
        translation: CGPoint(x: 0, y: 0)
    )

    private let frame = PSDRect(left: 10, top: 10, right: 60, bottom: 60)

    func testPointerSampleCanvasPointMatchesViewport() {
        let event = RawPointerEvent(
            viewPoint: CGPoint(x: 40, y: 30),
            phase: .began,
            pressure: 0,
            timestamp: 0,
            device: .mouse
        )
        let sample = InputCoordinateMapper.makeSample(from: event, viewport: viewport, layerFrame: frame)
        let expected = viewport.viewToCanvas(event.viewPoint)
        XCTAssertEqual(sample.canvasPoint.x, expected.x, accuracy: 0.0001)
        XCTAssertEqual(sample.canvasPoint.y, expected.y, accuracy: 0.0001)
    }

    func testPressureClampAndMouseDefault() {
        XCTAssertEqual(InputPressure.normalized(-0.5, device: .mouse), 1.0, accuracy: 0.0001)
        XCTAssertEqual(InputPressure.normalized(0, device: .mouse), 1.0, accuracy: 0.0001)
        XCTAssertEqual(InputPressure.normalized(1.5, device: .tablet), 1.0, accuracy: 0.0001)
        XCTAssertEqual(InputPressure.normalized(0.4, device: .tablet), 0.4, accuracy: 0.0001)
    }

    func testStrokeControllerIgnoresNonDrawableTool() {
        var session = StrokeSession()
        let context = StrokeInputContext(
            viewport: viewport,
            activeTool: .inspect,
            brushSettings: .defaults,
            drawContext: StrokeDrawContext(layerID: "0", layerFrame: frame, isEditable: true)
        )
        let event = RawPointerEvent(
            viewPoint: CGPoint(x: 20, y: 20),
            phase: .began,
            pressure: 0,
            timestamp: 0
        )
        let result = StrokeInputController.handle(event: event, session: &session, context: context)
        XCTAssertFalse(result.didChange)
        XCTAssertEqual(session.phase, .idle)
        XCTAssertEqual(result.diagnostics.rejectedReason, "non-drawable-tool")
    }

    func testStrokeControllerBeginMoveEndForBrushTool() {
        var session = StrokeSession()
        let context = StrokeInputContext(
            viewport: viewport,
            activeTool: .brush,
            brushSettings: .defaults,
            drawContext: StrokeDrawContext(layerID: "0", layerFrame: frame, isEditable: true)
        )

        let began = RawPointerEvent(viewPoint: CGPoint(x: 40, y: 40), phase: .began, pressure: 0, timestamp: 0)
        XCTAssertTrue(StrokeInputController.handle(event: began, session: &session, context: context).didChange)
        XCTAssertTrue(session.isRecording)

        let moved = RawPointerEvent(viewPoint: CGPoint(x: 44, y: 42), phase: .moved, pressure: 0, timestamp: 0.1)
        XCTAssertTrue(StrokeInputController.handle(event: moved, session: &session, context: context).didChange)

        let ended = RawPointerEvent(viewPoint: CGPoint(x: 48, y: 44), phase: .ended, pressure: 0, timestamp: 0.2)
        XCTAssertTrue(StrokeInputController.handle(event: ended, session: &session, context: context).didChange)
        XCTAssertEqual(session.phase, .ended)
        XCTAssertEqual(session.samples.count, 3)
    }

    func testCancelledStrokeDoesNotBecomeCommitEligible() {
        var session = StrokeSession()
        let context = StrokeInputContext(
            viewport: viewport,
            activeTool: .brush,
            brushSettings: .defaults,
            drawContext: StrokeDrawContext(layerID: "0", layerFrame: frame, isEditable: true)
        )
        _ = StrokeInputController.handle(
            event: RawPointerEvent(viewPoint: CGPoint(x: 30, y: 30), phase: .began, pressure: 0, timestamp: 0),
            session: &session,
            context: context
        )
        _ = StrokeInputController.handle(
            event: RawPointerEvent(viewPoint: CGPoint(x: 32, y: 32), phase: .cancelled, pressure: 0, timestamp: 0.1),
            session: &session,
            context: context
        )
        XCTAssertEqual(session.phase, .cancelled)
        XCTAssertFalse(session.isCommitEligible)
    }

    func testBeginRejectedWithoutEditableLayer() {
        var session = StrokeSession()
        let context = StrokeInputContext(
            viewport: viewport,
            activeTool: .brush,
            brushSettings: .defaults,
            drawContext: nil
        )
        let result = StrokeInputController.handle(
            event: RawPointerEvent(viewPoint: CGPoint(x: 20, y: 20), phase: .began, pressure: 0, timestamp: 0),
            session: &session,
            context: context
        )
        XCTAssertFalse(result.didChange)
        XCTAssertEqual(result.diagnostics.rejectedReason, "no-target-layer")
    }

    func testBeginRejectedOutsideLayerBounds() {
        var session = StrokeSession()
        let context = StrokeInputContext(
            viewport: viewport,
            activeTool: .brush,
            brushSettings: .defaults,
            drawContext: StrokeDrawContext(layerID: "0", layerFrame: frame, isEditable: true)
        )
        let result = StrokeInputController.handle(
            event: RawPointerEvent(viewPoint: CGPoint(x: 10, y: 10), phase: .began, pressure: 0, timestamp: 0),
            session: &session,
            context: context
        )
        XCTAssertFalse(result.didChange)
        XCTAssertEqual(session.phase, .idle)
        XCTAssertFalse(session.isCommitEligible)
        XCTAssertEqual(result.diagnostics.rejectedReason, "out-of-bounds-begin")
        XCTAssertEqual(result.diagnostics.lastEventSummary, "rejected begin: outside layer bounds")
    }

    func testBeginAcceptedInsideLayerBounds() {
        var session = StrokeSession()
        let context = StrokeInputContext(
            viewport: viewport,
            activeTool: .brush,
            brushSettings: .defaults,
            drawContext: StrokeDrawContext(layerID: "0", layerFrame: frame, isEditable: true)
        )
        let result = StrokeInputController.handle(
            event: RawPointerEvent(viewPoint: CGPoint(x: 40, y: 40), phase: .began, pressure: 0, timestamp: 0),
            session: &session,
            context: context
        )
        XCTAssertTrue(result.didChange)
        XCTAssertTrue(session.isRecording)
        XCTAssertFalse(session.isCommitEligible)
        XCTAssertNil(result.diagnostics.rejectedReason)
    }

    func testOutOfBoundsMoveIgnoredDuringActiveStroke() {
        var session = StrokeSession()
        let context = StrokeInputContext(
            viewport: viewport,
            activeTool: .brush,
            brushSettings: .defaults,
            drawContext: StrokeDrawContext(layerID: "0", layerFrame: frame, isEditable: true)
        )

        _ = StrokeInputController.handle(
            event: RawPointerEvent(viewPoint: CGPoint(x: 40, y: 40), phase: .began, pressure: 0, timestamp: 0),
            session: &session,
            context: context
        )
        let moveResult = StrokeInputController.handle(
            event: RawPointerEvent(viewPoint: CGPoint(x: 10, y: 10), phase: .moved, pressure: 0, timestamp: 0.1),
            session: &session,
            context: context
        )
        XCTAssertFalse(moveResult.didChange)
        XCTAssertTrue(session.isRecording)
        XCTAssertEqual(session.samples.count, 1)
        XCTAssertEqual(moveResult.diagnostics.rejectedReason, "out-of-bounds-move")
    }

    func testOutOfBoundsEndDoesNotAppendFinalSampleOrExpandDirtyBounds() {
        var session = StrokeSession()
        let context = StrokeInputContext(
            viewport: viewport,
            activeTool: .brush,
            brushSettings: .defaults,
            drawContext: StrokeDrawContext(layerID: "0", layerFrame: frame, isEditable: true)
        )

        _ = StrokeInputController.handle(
            event: RawPointerEvent(viewPoint: CGPoint(x: 40, y: 40), phase: .began, pressure: 0, timestamp: 0),
            session: &session,
            context: context
        )
        _ = StrokeInputController.handle(
            event: RawPointerEvent(viewPoint: CGPoint(x: 44, y: 42), phase: .moved, pressure: 0, timestamp: 0.1),
            session: &session,
            context: context
        )
        let dirtyBoundsBeforeEnd = session.estimatedDirtyBounds
        XCTAssertEqual(session.samples.count, 2)

        let endResult = StrokeInputController.handle(
            event: RawPointerEvent(viewPoint: CGPoint(x: 10, y: 10), phase: .ended, pressure: 0, timestamp: 0.2),
            session: &session,
            context: context
        )

        XCTAssertTrue(endResult.didChange)
        XCTAssertEqual(session.phase, .ended)
        XCTAssertEqual(session.samples.count, 2)
        XCTAssertTrue(session.isCommitEligible)
        XCTAssertEqual(session.estimatedDirtyBounds, dirtyBoundsBeforeEnd)
        XCTAssertEqual(endResult.diagnostics.lastEventSummary, "stroke ended (2 samples)")
        XCTAssertNil(endResult.diagnostics.rejectedReason)
    }

    @MainActor
    func testToolSwitchFromBrushToEraserCancelsActiveStroke() {
        let model = DocumentModel()
        model.editorState.setTool(.brush)
        seedActiveStroke(on: model)

        model.setEditorTool(.eraser)

        XCTAssertEqual(model.editorState.activeTool, .eraser)
        XCTAssertEqual(model.editorState.strokeSession.phase, .cancelled)
        XCTAssertFalse(model.editorState.strokeSession.isCommitEligible)
        XCTAssertEqual(model.editorState.inputDiagnostics.lastEventSummary, "stroke cancelled: tool changed")
    }

    @MainActor
    func testToolSwitchToNonDrawableCancelsActiveStroke() {
        let model = DocumentModel()
        model.editorState.setTool(.brush)
        seedActiveStroke(on: model)

        model.setEditorTool(.inspect)

        XCTAssertEqual(model.editorState.activeTool, .inspect)
        XCTAssertEqual(model.editorState.strokeSession.phase, .cancelled)
        XCTAssertFalse(model.editorState.strokeSession.isCommitEligible)
    }

    @MainActor
    func testToolSwitchWithoutActiveStrokeDoesNotError() {
        let model = DocumentModel()
        model.setEditorTool(.brush)
        model.setEditorTool(.eraser)
        model.setEditorTool(.hand)

        XCTAssertEqual(model.editorState.activeTool, .hand)
        XCTAssertEqual(model.editorState.strokeSession.phase, .idle)
    }

    @MainActor
    func testRepeatedSetEditorToolSameToolIsNoOp() {
        let model = DocumentModel()
        model.setEditorTool(.brush)
        seedActiveStroke(on: model)

        let sessionBefore = model.editorState.strokeSession
        let diagnosticsBefore = model.editorState.inputDiagnostics

        model.setEditorTool(.brush)

        XCTAssertEqual(model.editorState.activeTool, .brush)
        XCTAssertEqual(model.editorState.strokeSession, sessionBefore)
        XCTAssertEqual(model.editorState.inputDiagnostics, diagnosticsBefore)
        XCTAssertTrue(model.editorState.strokeSession.isRecording)
    }

    @MainActor
    private func seedActiveStroke(on model: DocumentModel) {
        var session = StrokeSession()
        let sample = PointerSample(
            timestamp: 0,
            phase: .began,
            viewPoint: CGPoint(x: 20, y: 20),
            canvasPoint: CGPoint(x: 20, y: 20),
            layerLocalPoint: CGPoint(x: 10, y: 10),
            pressure: 1,
            tilt: .none,
            device: .mouse,
            modifiers: [],
            isInsideTargetLayer: true
        )
        XCTAssertTrue(session.begin(
            target: StrokeTarget(layerID: "0", layerFrame: frame),
            brush: .defaults,
            initialSample: sample
        ))
        model.editorState.strokeSession = session
    }
}
