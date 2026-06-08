import CoreGraphics
import XCTest
import PSDKit
@testable import PSDViewer

final class InputCoordinateMapperTests: XCTestCase {
    func testViewToCanvasUsesEditorViewport() {
        let viewport = EditorViewport(
            canvasSize: CGSize(width: 100, height: 100),
            viewSize: CGSize(width: 200, height: 200),
            scale: 2,
            translation: CGPoint(x: 10, y: 20)
        )
        let viewPoint = CGPoint(x: 30, y: 40)
        let canvas = InputCoordinateMapper.canvasPoint(viewPoint: viewPoint, viewport: viewport)
        XCTAssertEqual(canvas.x, 10, accuracy: 0.0001)
        XCTAssertEqual(canvas.y, 10, accuracy: 0.0001)
    }

    func testCanvasToLayerLocalAppliesFrameOffset() {
        let frame = PSDRect(left: 20, top: 30, right: 120, bottom: 80)
        let local = InputCoordinateMapper.layerLocalPoint(
            canvasPoint: CGPoint(x: 45, y: 55),
            frame: frame
        )
        XCTAssertEqual(local.x, 25, accuracy: 0.0001)
        XCTAssertEqual(local.y, 25, accuracy: 0.0001)
    }

    func testLayerLocalRoundtripPreservesCanvasPoint() {
        let frame = PSDRect(left: 10, top: 15, right: 110, bottom: 115)
        let original = CGPoint(x: 42.5, y: 77.25)
        let local = InputCoordinateMapper.layerLocalPoint(canvasPoint: original, frame: frame)
        let roundtrip = InputCoordinateMapper.canvasPoint(layerLocalPoint: local, frame: frame)
        XCTAssertEqual(roundtrip.x, original.x, accuracy: 0.0001)
        XCTAssertEqual(roundtrip.y, original.y, accuracy: 0.0001)
    }

    func testInsideLayerDetectionForOffsetLayer() {
        let frame = PSDRect(left: 50, top: 40, right: 150, bottom: 140)
        XCTAssertTrue(InputCoordinateMapper.isInsideLayer(canvasPoint: CGPoint(x: 60, y: 50), frame: frame))
        XCTAssertFalse(InputCoordinateMapper.isInsideLayer(canvasPoint: CGPoint(x: 10, y: 10), frame: frame))
        XCTAssertFalse(InputCoordinateMapper.isInsideLayer(canvasPoint: CGPoint(x: 150, y: 50), frame: frame))
    }

    func testMakeSamplePreservesFractionalCoordinates() {
        let viewport = EditorViewport(
            canvasSize: CGSize(width: 200, height: 200),
            viewSize: CGSize(width: 400, height: 400),
            scale: 1.5,
            translation: CGPoint(x: 5, y: 7)
        )
        let frame = PSDRect(left: 0, top: 0, right: 200, bottom: 200)
        let event = RawPointerEvent(
            viewPoint: CGPoint(x: 20.25, y: 30.75),
            phase: .began,
            pressure: 0,
            timestamp: 1.5,
            device: .mouse
        )
        let sample = InputCoordinateMapper.makeSample(from: event, viewport: viewport, layerFrame: frame)
        XCTAssertEqual(sample.canvasPoint.x, 10.1666, accuracy: 0.001)
        XCTAssertEqual(sample.canvasPoint.y, 15.8333, accuracy: 0.001)
        XCTAssertEqual(sample.layerLocalPoint?.x ?? -1, sample.canvasPoint.x, accuracy: 0.001)
        XCTAssertEqual(sample.pressure, 1.0, accuracy: 0.0001)
        XCTAssertEqual(sample.isInsideTargetLayer, true)
    }
}
