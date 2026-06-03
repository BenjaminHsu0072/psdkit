import XCTest
@testable import PSDKit

enum GoldenAssertions {
    static func assertDocumentMatchesGolden(_ doc: PSDDocument, entry: GoldenFixture) throws {
        XCTAssertEqual(doc.canvasSize.width, entry.header.width, entry.id)
        XCTAssertEqual(doc.canvasSize.height, entry.header.height, entry.id)

        let pixels = doc.root.children.compactMap { $0 as? PixelLayer }
        XCTAssertEqual(pixels.count, entry.layerCount, entry.id)

        for (layer, golden) in zip(pixels, entry.layers) {
            if !golden.skipNameCheck {
                XCTAssertEqual(layer.name, golden.name, entry.id)
            }
            XCTAssertEqual(layer.frame.left, golden.bbox.left, entry.id)
            XCTAssertEqual(layer.frame.top, golden.bbox.top, entry.id)
            XCTAssertEqual(layer.frame.right, golden.bbox.right, entry.id)
            XCTAssertEqual(layer.frame.bottom, golden.bbox.bottom, entry.id)
            XCTAssertEqual(layer.opacity, UInt8(clamping: golden.opacity), entry.id)
            XCTAssertEqual(layer.isVisible, golden.visible, entry.id)
            XCTAssertEqual(layer.frame.width, golden.width, entry.id)
            XCTAssertEqual(layer.frame.height, golden.height, entry.id)

            if let rgbaFile = golden.rgbaFile {
                let expected = try Data(contentsOf: GoldenLoader.goldenRGBAURL(fileName: rgbaFile))
                XCTAssertEqual(layer.pixels.rgba, expected, "\(entry.id) layer \(golden.index) pixels")
                XCTAssertEqual(layer.pixels.rgba.count, golden.pixelByteCount, entry.id)
            }
        }
    }
}
