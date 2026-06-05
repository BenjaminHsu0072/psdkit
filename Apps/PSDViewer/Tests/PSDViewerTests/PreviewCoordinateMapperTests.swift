import CoreGraphics
import XCTest
@testable import PSDViewer

final class PreviewCoordinateMapperTests: XCTestCase {
    func testPsdDeltaOneToOneDisplay() {
        let delta = PreviewCoordinateMapper.psdDelta(
            from: CGSize(width: 12.4, height: -3.6),
            imagePixelSize: CGSize(width: 512, height: 256),
            displayedSize: CGSize(width: 512, height: 256)
        )
        XCTAssertEqual(delta.dx, 12)
        XCTAssertEqual(delta.dy, -4)
    }

    func testPsdDeltaScalesWithDisplayedSize() {
        let delta = PreviewCoordinateMapper.psdDelta(
            from: CGSize(width: 50, height: 25),
            imagePixelSize: CGSize(width: 200, height: 100),
            displayedSize: CGSize(width: 100, height: 50)
        )
        XCTAssertEqual(delta.dx, 100)
        XCTAssertEqual(delta.dy, 50)
    }

    func testMovedOriginAppliesScaledTranslation() {
        let origin = PreviewCoordinateMapper.movedOrigin(
            left: 10,
            top: 20,
            translation: CGSize(width: 5, height: 5),
            imagePixelSize: CGSize(width: 100, height: 100),
            displayedSize: CGSize(width: 50, height: 50)
        )
        XCTAssertEqual(origin.left, 20)
        XCTAssertEqual(origin.top, 30)
    }

    func testResizedFrameBottomRightIncreasesWidthAndHeight() {
        let frame = PreviewCoordinateMapper.resizedFrame(
            left: 10,
            top: 20,
            width: 40,
            height: 30,
            handle: .bottomRight,
            translation: CGSize(width: 8, height: 6),
            imagePixelSize: CGSize(width: 100, height: 100),
            displayedSize: CGSize(width: 100, height: 100)
        )
        XCTAssertEqual(frame.left, 10)
        XCTAssertEqual(frame.top, 20)
        XCTAssertEqual(frame.width, 48)
        XCTAssertEqual(frame.height, 36)
    }

    func testResizedFrameTopLeftAdjustsOriginAndSize() {
        let frame = PreviewCoordinateMapper.resizedFrame(
            left: 10,
            top: 20,
            width: 40,
            height: 30,
            handle: .topLeft,
            translation: CGSize(width: 5, height: 4),
            imagePixelSize: CGSize(width: 100, height: 100),
            displayedSize: CGSize(width: 100, height: 100)
        )
        XCTAssertEqual(frame.left, 15)
        XCTAssertEqual(frame.top, 24)
        XCTAssertEqual(frame.width, 35)
        XCTAssertEqual(frame.height, 26)
    }

    func testResizedFrameLeftClampsToMinimumWidth() {
        let frame = PreviewCoordinateMapper.resizedFrame(
            left: 10,
            top: 20,
            width: 40,
            height: 30,
            handle: .left,
            translation: CGSize(width: 100, height: 0),
            imagePixelSize: CGSize(width: 100, height: 100),
            displayedSize: CGSize(width: 100, height: 100)
        )
        XCTAssertEqual(frame.left, 49)
        XCTAssertEqual(frame.top, 20)
        XCTAssertEqual(frame.width, 1)
        XCTAssertEqual(frame.height, 30)
    }

    func testResizedFrameTopClampsToMinimumHeight() {
        let frame = PreviewCoordinateMapper.resizedFrame(
            left: 10,
            top: 20,
            width: 40,
            height: 30,
            handle: .top,
            translation: CGSize(width: 0, height: 50),
            imagePixelSize: CGSize(width: 100, height: 100),
            displayedSize: CGSize(width: 100, height: 100)
        )
        XCTAssertEqual(frame.left, 10)
        XCTAssertEqual(frame.top, 49)
        XCTAssertEqual(frame.width, 40)
        XCTAssertEqual(frame.height, 1)
    }

    func testResizedFrameScalesWithDisplayedSize() {
        let frame = PreviewCoordinateMapper.resizedFrame(
            left: 0,
            top: 0,
            width: 20,
            height: 10,
            handle: .bottomRight,
            translation: CGSize(width: 25, height: 10),
            imagePixelSize: CGSize(width: 200, height: 100),
            displayedSize: CGSize(width: 100, height: 50)
        )
        XCTAssertEqual(frame.left, 0)
        XCTAssertEqual(frame.top, 0)
        XCTAssertEqual(frame.width, 70)
        XCTAssertEqual(frame.height, 30)
    }
}
