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

    func testOpacityRoundTrip() throws {
        let url = try fixtureURL("layer-opacity-50.psd")
        let doc = try PSDDocument.load(url: url)
        guard let layer = doc.root.children.first as? PixelLayer else {
            XCTFail("missing layer")
            return
        }
        XCTAssertEqual(layer.opacity, 128)
        layer.opacity = 200
        doc.markContentModified()
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent("opacity-edit.psd")
        try doc.save(to: temp)
        let reloaded = try PSDDocument.load(url: temp)
        XCTAssertEqual((reloaded.root.children.first as? PixelLayer)?.opacity, 200)
        try? FileManager.default.removeItem(at: temp)
    }

    func testVisibilityRoundTrip() throws {
        let url = try fixtureURL("layer-hidden.psd")
        let doc = try PSDDocument.load(url: url)
        guard let visible = doc.root.children.first as? PixelLayer,
              let hidden = doc.root.children.last as? PixelLayer
        else {
            XCTFail("expected two pixel layers")
            return
        }
        XCTAssertTrue(visible.isVisible)
        XCTAssertFalse(hidden.isVisible)

        visible.isVisible = false
        hidden.isVisible = true
        doc.markContentModified()

        let temp = FileManager.default.temporaryDirectory.appendingPathComponent("visibility-edit.psd")
        try doc.save(to: temp)
        let reloaded = try PSDDocument.load(url: temp)
        let rVisible = reloaded.root.children.first as? PixelLayer
        let rHidden = reloaded.root.children.last as? PixelLayer
        XCTAssertEqual(rVisible?.isVisible, false)
        XCTAssertEqual(rHidden?.isVisible, true)
        try? FileManager.default.removeItem(at: temp)
    }

    func testRenameLayerRoundTrip() throws {
        let url = try fixtureURL("two-layers.psd")
        let doc = try PSDDocument.load(url: url)
        guard let layer = doc.root.children.first as? PixelLayer else {
            XCTFail("missing layer")
            return
        }
        layer.name = "RenamedBottom"
        doc.markContentModified()
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent("rename-edit.psd")
        try doc.save(to: temp)
        let reloaded = try PSDDocument.load(url: temp)
        XCTAssertEqual(reloaded.root.children.first?.name, "RenamedBottom")
        try? FileManager.default.removeItem(at: temp)
    }

    func testLayerOffsetBoundsSemanticRoundTrip() throws {
        let manifest = try GoldenLoader.loadManifest()
        guard let entry = manifest.fixtures.first(where: { $0.id == "layer-offset-10x10-on-32" }) else {
            throw XCTSkip("fixture not in manifest")
        }
        let url = GoldenLoader.fixtureURL(for: entry)
        let doc = try PSDDocument.load(url: url)
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent("offset-semantic.psd")
        try doc.save(to: temp, writeMode: .semantic)
        let reloaded = try PSDDocument.load(url: temp)
        try GoldenAssertions.assertDocumentMatchesGolden(reloaded, entry: entry)
        try? FileManager.default.removeItem(at: temp)
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
