import XCTest
@testable import PSDKit

final class CompositeBuilderTests: XCTestCase {
    func testCompositeSingleRedLayer() throws {
        let url = try fixtureURL("single-rle-8x8.psd")
        let doc = try PSDDocument.load(url: url)
        let layers = doc.root.children.compactMap { $0 as? PixelLayer }
        let rgba = CompositeBuilder.compositeRGBA(canvasSize: doc.canvasSize, layers: layers)
        XCTAssertEqual(rgba[0], 255)
        XCTAssertEqual(rgba[1], 0)
        XCTAssertEqual(rgba[2], 0)
    }

    func testSemanticWriteRebuildsCompositeImageData() throws {
        let url = try fixtureURL("single-rle-8x8.psd")
        let doc = try PSDDocument.load(url: url)
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent("composite-semantic.psd")
        try doc.save(to: temp, writeMode: .semantic)
        let reloaded = try PSDFile.read(data: Data(contentsOf: temp))
        XCTAssertEqual(reloaded.imageData.compression, .raw)
        let planeSize = 8 * 8
        XCTAssertEqual(reloaded.imageData.data.count, planeSize * 3)
        XCTAssertEqual(reloaded.imageData.data[0], 255)
        XCTAssertEqual(reloaded.imageData.data[planeSize], 0)
        XCTAssertEqual(reloaded.imageData.data[planeSize * 2], 0)
        try? FileManager.default.removeItem(at: temp)
    }

    func testOpacityChangeUpdatesComposite() throws {
        let url = try fixtureURL("single-rle-8x8.psd")
        let doc = try PSDDocument.load(url: url)
        guard let layer = doc.root.children.first as? PixelLayer else {
            XCTFail("missing layer")
            return
        }
        layer.opacity = 0
        doc.markContentModified()
        let data = try doc.data()
        let file = try PSDFile.read(data: data)
        let planeSize = 8 * 8
        // Full transparency → white background
        XCTAssertEqual(file.imageData.data[0], 255)
        XCTAssertEqual(file.imageData.data[1], 255)
        XCTAssertEqual(file.imageData.data[2], 255)
    }

    private func fixtureURL(_ name: String) throws -> URL {
        let base = name.replacingOccurrences(of: ".psd", with: "")
        guard let url = Bundle.module.url(forResource: base, withExtension: "psd", subdirectory: "Fixtures") else {
            throw XCTSkip("Missing fixture \(name)")
        }
        return url
    }
}
