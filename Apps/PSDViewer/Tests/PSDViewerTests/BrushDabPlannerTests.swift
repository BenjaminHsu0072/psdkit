import CoreGraphics
import XCTest
import PSDKit
@testable import PSDViewer

final class BrushDabPlannerTests: XCTestCase {
    private let frame = PSDRect(left: 0, top: 0, right: 32, bottom: 32)

    func testDabGenerationIsDeterministic() {
        let session = makeSession(samples: lineSamples())
        let first = BrushDabPlanner.plan(from: session, tool: .brush)
        let second = BrushDabPlanner.plan(from: session, tool: .brush)

        XCTAssertEqual(first, second)
        XCTAssertGreaterThan(first?.dabCount ?? 0, 1)
    }

    func testPressureAffectsDabRadiusAndAlpha() throws {
        var lowBrush = BrushSettings.defaults
        lowBrush.size = 20
        lowBrush.flow = 0.8
        lowBrush.sizePressure = 1
        lowBrush.flowPressure = 1

        let lowSample = makeSample(at: CGPoint(x: 10, y: 10), pressure: 0.1)
        let highSample = makeSample(at: CGPoint(x: 10, y: 10), pressure: 1.0)

        var lowSession = StrokeSession()
        XCTAssertTrue(lowSession.begin(target: target(), brush: lowBrush, initialSample: lowSample))
        var highSession = StrokeSession()
        XCTAssertTrue(highSession.begin(target: target(), brush: lowBrush, initialSample: highSample))

        let lowPlan = BrushDabPlanner.plan(from: lowSession, tool: .brush)
        let highPlan = BrushDabPlanner.plan(from: highSession, tool: .brush)

        let lowDab = try XCTUnwrap(lowPlan?.dabs.first)
        let highDab = try XCTUnwrap(highPlan?.dabs.first)
        XCTAssertLessThan(lowDab.radius, highDab.radius)
        XCTAssertLessThan(lowDab.alpha, highDab.alpha)
    }

    func testPressureClampUsesMinimumFactors() throws {
        var brush = BrushSettings.defaults
        brush.size = 40
        brush.minSize = 0.5
        brush.minFlow = 0.5
        brush.sizePressure = 1
        brush.flowPressure = 1

        let sample = makeSample(at: CGPoint(x: 8, y: 8), pressure: -1)
        var session = StrokeSession()
        XCTAssertTrue(session.begin(target: target(), brush: brush, initialSample: sample))
        let dab = try XCTUnwrap(BrushDabPlanner.plan(from: session, tool: .brush)?.dabs.first)

        XCTAssertEqual(dab.radius, brush.radius(for: 0), accuracy: 0.0001)
        XCTAssertEqual(dab.alpha, brush.dabAlpha(for: 0), accuracy: 0.0001)
    }

    func testOutOfBoundsSamplesDoNotExpandPlan() {
        let outside = makeSample(at: CGPoint(x: 40, y: 40), pressure: 1, inside: false)
        var session = StrokeSession()
        XCTAssertTrue(session.begin(target: target(), brush: .defaults, initialSample: outside))
        XCTAssertNil(BrushDabPlanner.plan(from: session, tool: .brush))
    }

    func testPartiallyOutOfBoundsDabsClipDirtyRegion() throws {
        let nearEdge = makeSample(at: CGPoint(x: 1, y: 1), pressure: 1)
        var session = StrokeSession()
        XCTAssertTrue(session.begin(target: target(), brush: .defaults, initialSample: nearEdge))
        let plan = try XCTUnwrap(BrushDabPlanner.plan(from: session, tool: .brush))

        if case .unionRect(let rect) = plan.dirtyRegion {
            XCTAssertGreaterThanOrEqual(rect.left, 0)
            XCTAssertGreaterThanOrEqual(rect.top, 0)
            XCTAssertLessThanOrEqual(rect.right, frame.width)
            XCTAssertLessThanOrEqual(rect.bottom, frame.height)
        } else {
            XCTFail("expected union dirty region")
        }
    }

    func testBrushAndEraserModesAreDistinct() throws {
        let session = makeSession(samples: [makeSample(at: CGPoint(x: 12, y: 12), pressure: 0.5)])
        let brushPlan = try XCTUnwrap(BrushDabPlanner.plan(from: session, tool: .brush))
        let eraserPlan = try XCTUnwrap(BrushDabPlanner.plan(from: session, tool: .eraser))

        XCTAssertEqual(brushPlan.mode, .brush)
        XCTAssertEqual(eraserPlan.mode, .eraser)
        XCTAssertEqual(brushPlan.dabs.count, eraserPlan.dabs.count)
        XCTAssertEqual(brushPlan.dabs.first?.color.alpha, 1)
        XCTAssertEqual(eraserPlan.dabs.first?.color.alpha, 0)
    }

    func testInspectToolDoesNotProducePlan() {
        let session = makeSession(samples: lineSamples())
        XCTAssertNil(BrushDabPlanner.plan(from: session, tool: .inspect))
    }

    func testSampleCountDistinctFromDabCountForExpandedStroke() throws {
        let session = makeSession(samples: lineSamples())
        let plan = try XCTUnwrap(BrushDabPlanner.plan(from: session, tool: .brush))

        XCTAssertEqual(plan.sampleCount, lineSamples().count)
        XCTAssertGreaterThan(plan.dabCount, plan.sampleCount)
    }

    private func target() -> StrokeTarget {
        StrokeTarget(layerID: "0", layerFrame: frame)
    }

    private func makeSession(samples: [PointerSample]) -> StrokeSession {
        var session = StrokeSession()
        guard let first = samples.first else {
            XCTFail("missing samples")
            return session
        }
        XCTAssertTrue(session.begin(target: target(), brush: .defaults, initialSample: first))
        for sample in samples.dropFirst() {
            XCTAssertTrue(session.append(sample))
        }
        return session
    }

    private func lineSamples() -> [PointerSample] {
        [
            makeSample(at: CGPoint(x: 4, y: 4), pressure: 0.2, phase: .began),
            makeSample(at: CGPoint(x: 8, y: 6), pressure: 0.5, phase: .moved),
            makeSample(at: CGPoint(x: 14, y: 10), pressure: 0.8, phase: .moved),
            makeSample(at: CGPoint(x: 20, y: 14), pressure: 1.0, phase: .moved),
        ]
    }

    private func makeSample(
        at localPoint: CGPoint,
        pressure: CGFloat,
        phase: PointerSamplePhase = .began,
        inside: Bool = true
    ) -> PointerSample {
        PointerSample(
            timestamp: 0,
            phase: phase,
            viewPoint: localPoint,
            canvasPoint: CGPoint(x: localPoint.x + CGFloat(frame.left), y: localPoint.y + CGFloat(frame.top)),
            layerLocalPoint: localPoint,
            pressure: pressure,
            tilt: .none,
            device: .mouse,
            modifiers: [],
            isInsideTargetLayer: inside
        )
    }
}
