import XCTest
@testable import PSDKit

/// TDD write tests — expand as encoder matures.
final class GoldenWriteTests: XCTestCase {
    private var manifest: GoldenManifest!

    override func setUpWithError() throws {
        manifest = try GoldenLoader.loadManifest()
    }

    func testPassthroughRoundTripBytes() throws {
        let passthrough = manifest.fixtures.filter { $0.v1WriteRoundtrip == "passthrough" }
        XCTAssertGreaterThanOrEqual(passthrough.count, 5)

        for entry in passthrough {
            let url = GoldenLoader.fixtureURL(for: entry)
            let original = try Data(contentsOf: url)
            let doc = try PSDDocument.load(url: url)
            let out = try doc.data(writeMode: .passthrough)
            XCTAssertEqual(out, original, entry.id)
            XCTAssertEqual(out.count, entry.fileSize, entry.id)
        }
    }

    func testPassthroughReloadMetadataStable() throws {
        for entry in manifest.fixtures where entry.v1WriteRoundtrip == "passthrough" {
            let url = GoldenLoader.fixtureURL(for: entry)
            let doc1 = try PSDDocument.load(url: url)
            let temp = FileManager.default.temporaryDirectory
                .appendingPathComponent("psdkit-\(entry.id).psd")
            try doc1.save(to: temp, writeMode: .passthrough)
            let doc2 = try PSDDocument.load(url: temp)
            XCTAssertEqual(doc2.canvasSize.width, entry.header.width, entry.id)
            XCTAssertEqual(
                doc2.root.children.compactMap { $0 as? PixelLayer }.count,
                entry.layerCount,
                entry.id
            )
            try? FileManager.default.removeItem(at: temp)
        }
    }

    func testSemanticWriteRebuildsPixels() throws {
        let semantic = manifest.fixtures.filter { $0.v1WriteRoundtrip == "semantic" }
        XCTAssertFalse(semantic.isEmpty, "Add semantic fixtures in generate_test_fixtures.py")

        for entry in semantic where entry.v1ReadSupported {
            let url = GoldenLoader.fixtureURL(for: entry)
            let doc = try PSDDocument.load(url: url)
            let temp = FileManager.default.temporaryDirectory
                .appendingPathComponent("psdkit-semantic-\(entry.id).psd")
            try doc.save(to: temp, writeMode: .semantic)
            let reloaded = try PSDDocument.load(url: temp)
            try GoldenAssertions.assertDocumentMatchesGolden(reloaded, entry: entry)
            try? FileManager.default.removeItem(at: temp)
        }
    }

    func testSemanticWritePhotoshopCompatible() throws {
        throw XCTSkip("Manual PS validation — enable after semantic writer stabilizes")
    }
}
