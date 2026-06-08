import CoreGraphics
import XCTest
import PSDKit
@testable import PSDViewer

final class StrokeSessionTests: XCTestCase {
    private let frame = PSDRect(left: 0, top: 0, right: 100, bottom: 100)

    func testBeginMoveEndLifecycle() {
        var session = StrokeSession()
        let began = makeSample(phase: .began, canvas: CGPoint(x: 10, y: 10))
        let target = StrokeTarget(layerID: "0", layerFrame: frame)

        XCTAssertTrue(session.begin(target: target, brush: .defaults, initialSample: began))
        XCTAssertEqual(session.phase, .active)
        XCTAssertEqual(session.samples.count, 1)

        let moved = makeSample(phase: .moved, canvas: CGPoint(x: 12, y: 11))
        XCTAssertTrue(session.append(moved))
        XCTAssertEqual(session.samples.count, 2)

        let ended = makeSample(phase: .ended, canvas: CGPoint(x: 14, y: 12))
        let result = session.end(finalSample: ended)
        guard case .ended = result else {
            return XCTFail("Expected ended result")
        }
        XCTAssertEqual(session.phase, .ended)
        XCTAssertEqual(session.samples.count, 3)
        XCTAssertTrue(session.isCommitEligible)
        XCTAssertNotNil(session.estimatedDirtyBounds)
    }

    func testCancelClearsDirtyBoundsAndIsNotCommitEligible() {
        var session = StrokeSession()
        let target = StrokeTarget(layerID: "0", layerFrame: frame)
        XCTAssertTrue(session.begin(
            target: target,
            brush: .defaults,
            initialSample: makeSample(phase: .began, canvas: CGPoint(x: 5, y: 5))
        ))
        XCTAssertTrue(session.append(makeSample(phase: .moved, canvas: CGPoint(x: 6, y: 6))))

        let result = session.cancel(reasonSample: makeSample(phase: .cancelled, canvas: CGPoint(x: 7, y: 7)))
        guard case .cancelled = result else {
            return XCTFail("Expected cancelled result")
        }
        XCTAssertEqual(session.phase, .cancelled)
        XCTAssertFalse(session.isCommitEligible)
        XCTAssertNil(session.estimatedDirtyBounds)
    }

    func testAppendRejectedWhenIdle() {
        var session = StrokeSession()
        XCTAssertFalse(session.append(makeSample(phase: .moved, canvas: CGPoint(x: 1, y: 1))))
    }

    func testDirtyBoundsExpandWithBrushRadius() {
        var session = StrokeSession()
        let brush = BrushSettings(size: 20)
        let target = StrokeTarget(layerID: "0", layerFrame: frame)
        XCTAssertTrue(session.begin(
            target: target,
            brush: brush,
            initialSample: makeSample(phase: .began, canvas: CGPoint(x: 50, y: 50), pressure: 1)
        ))
        XCTAssertTrue(session.append(makeSample(phase: .moved, canvas: CGPoint(x: 80, y: 80), pressure: 1)))

        guard let bounds = session.estimatedDirtyBounds else {
            return XCTFail("Expected dirty bounds")
        }
        XCTAssertLessThan(bounds.minX, 50)
        XCTAssertGreaterThan(bounds.maxX, 80)
    }

    private func makeSample(
        phase: PointerSamplePhase,
        canvas: CGPoint,
        pressure: CGFloat = 1
    ) -> PointerSample {
        PointerSample(
            timestamp: 0,
            phase: phase,
            viewPoint: canvas,
            canvasPoint: canvas,
            layerLocalPoint: canvas,
            pressure: pressure,
            tilt: .none,
            device: .mouse,
            modifiers: [],
            isInsideTargetLayer: true
        )
    }
}
