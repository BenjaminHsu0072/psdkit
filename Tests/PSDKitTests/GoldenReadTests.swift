import XCTest
@testable import PSDKit

/// TDD read tests: golden PSDs from psd-tools + per-layer RGBA reference files.
final class GoldenReadTests: XCTestCase {
    private var manifest: GoldenManifest!

    override func setUpWithError() throws {
        manifest = try GoldenLoader.loadManifest()
    }

    func testAllGoldenFixturesReadable() throws {
        for entry in manifest.fixtures where entry.v1ReadSupported {
            let url = GoldenLoader.fixtureURL(for: entry)
            let doc = try PSDDocument.load(url: url)
            try GoldenAssertions.assertDocumentMatchesGolden(doc, entry: entry)
        }
    }

    func testGoldenFixturesByTag() throws {
        let requiredTags = ["single", "multi", "rle", "raw", "opacity", "bounds", "unicode"]
        for tag in requiredTags {
            let subset = manifest.fixtures.filter { $0.tags.contains(tag) && $0.v1ReadSupported }
            XCTAssertFalse(subset.isEmpty, "No fixtures tagged '\(tag)'")
            for entry in subset {
                let url = GoldenLoader.fixtureURL(for: entry)
                let doc = try PSDDocument.load(url: url)
                try GoldenAssertions.assertDocumentMatchesGolden(doc, entry: entry)
            }
        }
    }
}
