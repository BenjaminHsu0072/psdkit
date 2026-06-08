import CoreGraphics
import Foundation
import PSDKit

struct StrokeDrawContext: Equatable, Sendable {
    let layerID: String
    let layerFrame: PSDRect
    let isEditable: Bool
}

struct StrokeInputContext: Equatable, Sendable {
    let viewport: EditorViewport
    let activeTool: EditorTool
    let brushSettings: BrushSettings
    let drawContext: StrokeDrawContext?
}

struct InputDiagnostics: Equatable, Sendable {
    var lastEventSummary: String = ""
    var activePhase: StrokeSessionPhase = .idle
    var sampleCount: Int = 0
    var lastCanvasPoint: CGPoint?
    var lastPressure: CGFloat?
    var rejectedReason: String?

    static let empty = InputDiagnostics()
}

struct InputHandlingResult: Equatable, Sendable {
    let session: StrokeSession
    let diagnostics: InputDiagnostics
    let didChange: Bool
}

/// Pure stroke input state machine. No AppKit, Metal, or pixel writes.
///
/// Layer boundary policy (E3, pre-E4):
/// - `began`: reject when the canvas point is outside the target layer frame.
/// - `moved`: ignore out-of-bounds samples while a stroke stays active (no append).
/// - `ended`: always end an active stroke; skip appending a final out-of-bounds sample.
enum StrokeInputController {
    static func isDrawableTool(_ tool: EditorTool) -> Bool {
        tool == .brush || tool == .eraser
    }

    static func handle(
        event: RawPointerEvent,
        session: inout StrokeSession,
        context: StrokeInputContext
    ) -> InputHandlingResult {
        var diagnostics = InputDiagnostics(
            activePhase: session.phase,
            sampleCount: session.samples.count,
            lastCanvasPoint: session.samples.last?.canvasPoint,
            lastPressure: session.samples.last?.pressure
        )

        let layerFrame = context.drawContext?.layerFrame
        let sample = InputCoordinateMapper.makeSample(
            from: event,
            viewport: context.viewport,
            layerFrame: layerFrame
        )
        diagnostics.lastCanvasPoint = sample.canvasPoint
        diagnostics.lastPressure = sample.pressure

        guard isDrawableTool(context.activeTool) else {
            diagnostics.lastEventSummary = "ignored: tool=\(context.activeTool)"
            diagnostics.rejectedReason = "non-drawable-tool"
            return InputHandlingResult(session: session, diagnostics: diagnostics, didChange: false)
        }

        switch sample.phase {
        case .began:
            return handleBegin(sample: sample, session: &session, context: context, diagnostics: &diagnostics)
        case .moved:
            return handleMove(sample: sample, session: &session, diagnostics: &diagnostics)
        case .ended:
            return handleEnd(sample: sample, session: &session, diagnostics: &diagnostics)
        case .cancelled:
            return handleCancel(sample: sample, session: &session, diagnostics: &diagnostics)
        }
    }

    private static func handleBegin(
        sample: PointerSample,
        session: inout StrokeSession,
        context: StrokeInputContext,
        diagnostics: inout InputDiagnostics
    ) -> InputHandlingResult {
        guard let drawContext = context.drawContext, drawContext.isEditable else {
            diagnostics.lastEventSummary = "rejected begin: no editable pixel layer"
            diagnostics.rejectedReason = "no-target-layer"
            return InputHandlingResult(session: session, diagnostics: diagnostics, didChange: false)
        }

        if sample.isInsideTargetLayer == false {
            diagnostics.lastEventSummary = "rejected begin: outside layer bounds"
            diagnostics.rejectedReason = "out-of-bounds-begin"
            return InputHandlingResult(session: session, diagnostics: diagnostics, didChange: false)
        }

        if session.phase == .active {
            _ = session.cancel(reasonSample: sample)
        } else if session.phase != .idle {
            session.reset()
        }

        let target = StrokeTarget(layerID: drawContext.layerID, layerFrame: drawContext.layerFrame)
        let began = session.begin(target: target, brush: context.brushSettings, initialSample: sample)
        diagnostics.activePhase = session.phase
        diagnostics.sampleCount = session.samples.count
        diagnostics.lastEventSummary = began
            ? "stroke began on \(drawContext.layerID)"
            : "rejected begin: invalid session state"
        diagnostics.rejectedReason = began ? nil : "invalid-session-state"
        return InputHandlingResult(session: session, diagnostics: diagnostics, didChange: began)
    }

    private static func handleMove(
        sample: PointerSample,
        session: inout StrokeSession,
        diagnostics: inout InputDiagnostics
    ) -> InputHandlingResult {
        guard session.isRecording else {
            diagnostics.lastEventSummary = "ignored move: no active stroke"
            diagnostics.rejectedReason = "no-active-stroke"
            return InputHandlingResult(session: session, diagnostics: diagnostics, didChange: false)
        }

        if sample.isInsideTargetLayer == false {
            diagnostics.lastEventSummary = "ignored move: outside layer bounds"
            diagnostics.rejectedReason = "out-of-bounds-move"
            return InputHandlingResult(session: session, diagnostics: diagnostics, didChange: false)
        }

        let appended = session.append(sample)
        diagnostics.activePhase = session.phase
        diagnostics.sampleCount = session.samples.count
        diagnostics.lastEventSummary = appended ? "stroke move #\(session.samples.count)" : "rejected move"
        diagnostics.rejectedReason = appended ? nil : "append-failed"
        return InputHandlingResult(session: session, diagnostics: diagnostics, didChange: appended)
    }

    private static func handleEnd(
        sample: PointerSample,
        session: inout StrokeSession,
        diagnostics: inout InputDiagnostics
    ) -> InputHandlingResult {
        guard session.isRecording else {
            diagnostics.lastEventSummary = "ignored end: no active stroke"
            diagnostics.rejectedReason = "no-active-stroke"
            return InputHandlingResult(session: session, diagnostics: diagnostics, didChange: false)
        }

        let finalSample = sample.isInsideTargetLayer == false ? nil : sample
        let result = session.end(finalSample: finalSample)
        diagnostics.activePhase = session.phase
        diagnostics.sampleCount = session.samples.count
        diagnostics.lastEventSummary = "stroke ended (\(session.samples.count) samples)"
        diagnostics.rejectedReason = nil
        let changed = if case .ended = result { true } else { false }
        return InputHandlingResult(session: session, diagnostics: diagnostics, didChange: changed)
    }

    private static func handleCancel(
        sample: PointerSample,
        session: inout StrokeSession,
        diagnostics: inout InputDiagnostics
    ) -> InputHandlingResult {
        let result = session.cancel(reasonSample: sample)
        diagnostics.activePhase = session.phase
        diagnostics.sampleCount = session.samples.count
        diagnostics.lastEventSummary = "stroke cancelled"
        diagnostics.rejectedReason = nil
        let changed = if case .cancelled = result { true } else { false }
        return InputHandlingResult(session: session, diagnostics: diagnostics, didChange: changed)
    }
}
