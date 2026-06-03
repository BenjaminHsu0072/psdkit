import XCTest
@testable import PSDKit

final class FixtureTests: XCTestCase {
    private func fixtureURL(_ name: String) -> URL {
        let bundle = Bundle.module
        guard let url = bundle.url(forResource: name, withExtension: "psd", subdirectory: "Fixtures") else {
            fatalError("missing fixture \(name)")
        }
        return url
    }

    func testMinimalRGBA() throws {
        let doc = try PSDDocument.load(url: fixtureURL("minimal-rgba"))
        XCTAssertEqual(doc.canvasSize.width, 8)
        XCTAssertEqual(doc.canvasSize.height, 8)
        let pixels = doc.root.children.compactMap { $0 as? PixelLayer }
        XCTAssertEqual(pixels.count, 1)
        XCTAssertEqual(pixels[0].name, "Red")
        XCTAssertEqual(pixels[0].frame.width, 8)
        XCTAssertEqual(pixels[0].pixels.rgba[0], 255)
        XCTAssertEqual(pixels[0].pixels.rgba[3], 255)
    }

    func testTwoLayers() throws {
        let doc = try PSDDocument.load(url: fixtureURL("two-layers"))
        XCTAssertEqual(doc.canvasSize.width, 16)
        let pixels = doc.root.children.compactMap { $0 as? PixelLayer }
        XCTAssertEqual(pixels.count, 2)
        XCTAssertEqual(pixels[0].name, "Green")
        XCTAssertEqual(pixels[1].name, "Blue")
        XCTAssertEqual(pixels[1].opacity, 200)
        XCTAssertEqual(pixels[1].frame.left, 2)
        XCTAssertEqual(pixels[1].frame.top, 2)
        XCTAssertEqual(pixels[1].frame.width, 10)
    }
}
