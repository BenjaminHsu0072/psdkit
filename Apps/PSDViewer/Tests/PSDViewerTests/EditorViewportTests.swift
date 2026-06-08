import CoreGraphics
import XCTest
@testable import PSDViewer

final class EditorViewportTests: XCTestCase {
    func testFitCentersCanvasInView() {
        var viewport = EditorViewport(
            canvasSize: CGSize(width: 100, height: 50),
            viewSize: CGSize(width: 200, height: 200)
        )
        viewport.fitToView()

        XCTAssertEqual(viewport.scale, 2.0, accuracy: 0.0001)
        XCTAssertEqual(viewport.translation.x, 0, accuracy: 0.0001)
        XCTAssertEqual(viewport.translation.y, 50, accuracy: 0.0001)
    }

    func testPanUpdatesTranslation() {
        var viewport = EditorViewport(
            canvasSize: CGSize(width: 64, height: 64),
            viewSize: CGSize(width: 128, height: 128),
            scale: 1,
            translation: CGPoint(x: 10, y: 20)
        )

        viewport.pan(by: CGPoint(x: 5, y: -3))
        XCTAssertEqual(viewport.translation.x, 15, accuracy: 0.0001)
        XCTAssertEqual(viewport.translation.y, 17, accuracy: 0.0001)
    }

    func testAnchorZoomKeepsCanvasPointFixed() {
        var viewport = EditorViewport(
            canvasSize: CGSize(width: 100, height: 100),
            viewSize: CGSize(width: 200, height: 200),
            scale: 1,
            translation: CGPoint(x: 50, y: 50)
        )
        let anchor = CGPoint(x: 100, y: 100)
        let before = viewport.viewToCanvas(anchor)

        viewport.zoom(by: 2.0, anchorInView: anchor)
        let after = viewport.viewToCanvas(anchor)

        XCTAssertEqual(before.x, after.x, accuracy: 0.0001)
        XCTAssertEqual(before.y, after.y, accuracy: 0.0001)
        XCTAssertEqual(viewport.scale, 2.0, accuracy: 0.0001)
    }

    func testViewCanvasRoundtrip() {
        let viewport = EditorViewport(
            canvasSize: CGSize(width: 80, height: 60),
            viewSize: CGSize(width: 300, height: 200),
            scale: 2.5,
            translation: CGPoint(x: 12, y: 34)
        )
        let samples = [
            CGPoint(x: 0, y: 0),
            CGPoint(x: 17.5, y: 42.25),
            CGPoint(x: 79.9, y: 59.1),
        ]

        for canvasPoint in samples {
            let roundtrip = viewport.viewToCanvas(viewport.canvasToView(canvasPoint))
            XCTAssertEqual(roundtrip.x, canvasPoint.x, accuracy: 0.0001)
            XCTAssertEqual(roundtrip.y, canvasPoint.y, accuracy: 0.0001)
        }
    }

    func testCanvasRectToViewScalesWithViewport() {
        let viewport = EditorViewport(
            canvasSize: CGSize(width: 100, height: 100),
            viewSize: CGSize(width: 200, height: 200),
            scale: 2,
            translation: CGPoint(x: 10, y: 20)
        )
        let viewRect = viewport.canvasRectToView(CGRect(x: 5, y: 10, width: 20, height: 15))
        XCTAssertEqual(viewRect.origin.x, 20, accuracy: 0.0001)
        XCTAssertEqual(viewRect.origin.y, 40, accuracy: 0.0001)
        XCTAssertEqual(viewRect.size.width, 40, accuracy: 0.0001)
        XCTAssertEqual(viewRect.size.height, 30, accuracy: 0.0001)
    }
}
