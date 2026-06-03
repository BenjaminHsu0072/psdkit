import XCTest
@testable import PSDKit

final class PassthroughTests: XCTestCase {
    func testLoadedDataMatchesFileOnDisk() throws {
        let manifest = try GoldenLoader.loadManifest()
        let entry = manifest.fixtures.first { $0.id == "single-rle-8x8" }!
        let url = GoldenLoader.fixtureURL(for: entry)
        let disk = try Data(contentsOf: url)
        let doc = try PSDDocument.load(url: url)
        let out = try doc.data()
        XCTAssertEqual(out.count, disk.count)
        XCTAssertEqual(out, disk, "PSDDocument.data() must passthrough exact file bytes")
    }
}
