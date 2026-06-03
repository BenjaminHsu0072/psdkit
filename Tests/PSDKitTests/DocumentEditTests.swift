import XCTest
@testable import PSDKit

final class DocumentEditTests: XCTestCase {
    func testAppendPixelLayer() throws {
        let url = try fixtureURL("single-rle-8x8.psd")
        let doc = try PSDDocument.load(url: url)
        XCTAssertEqual(doc.root.children.count, 1)

        let overlay = try PixelLayer(
            name: "Overlay",
            frame: PSDRect(left: 0, top: 0, right: 4, bottom: 4),
            pixels: PixelBuffer(width: 4, height: 4, rgba: Data(repeating: 0, count: 64))
        )
        try doc.appendPixelLayer(overlay)
        XCTAssertEqual(doc.root.children.count, 2)
        XCTAssertTrue(doc.isContentDirty)

        let data = try doc.data()
        let reloaded = try PSDDocument.load(data: data)
        XCTAssertEqual(reloaded.root.children.compactMap { $0 as? PixelLayer }.count, 2)
        XCTAssertEqual(reloaded.root.children.last?.name, "Overlay")
    }

    func testRemovePixelLayer() throws {
        let url = try fixtureURL("two-layers.psd")
        let doc = try PSDDocument.load(url: url)
        XCTAssertEqual(doc.root.children.count, 2)

        guard let top = doc.root.children.last as? PixelLayer else {
            XCTFail("expected pixel layer")
            return
        }
        try doc.removePixelLayer(top)
        XCTAssertEqual(doc.root.children.count, 1)

        let data = try doc.data()
        let reloaded = try PSDDocument.load(data: data)
        XCTAssertEqual(reloaded.root.children.compactMap { $0 as? PixelLayer }.count, 1)
    }

    func testUnicodeLayerNameRoundTrip() throws {
        let url = try fixtureURL("layer-name-unicode.psd")
        let doc = try PSDDocument.load(url: url)
        guard let layer = doc.root.children.first as? PixelLayer else {
            XCTFail("missing layer")
            return
        }
        XCTAssertEqual(layer.name, "图层α")

        let temp = FileManager.default.temporaryDirectory.appendingPathComponent("unicode-roundtrip.psd")
        try doc.save(to: temp, writeMode: .semantic)
        let reloaded = try PSDDocument.load(url: temp)
        XCTAssertEqual((reloaded.root.children.first as? PixelLayer)?.name, "图层α")
        try? FileManager.default.removeItem(at: temp)
    }

    private func fixtureURL(_ name: String) throws -> URL {
        let base = name.replacingOccurrences(of: ".psd", with: "")
        guard let url = Bundle.module.url(forResource: base, withExtension: "psd", subdirectory: "Fixtures") else {
            throw XCTSkip("Missing fixture \(name)")
        }
        return url
    }
}
