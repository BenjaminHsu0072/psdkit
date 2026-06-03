import XCTest
@testable import PSDKit

final class FileHeaderTests: XCTestCase {
    func testHeaderRoundTrip() throws {
        let header = FileHeader.newRGB(width: 100, height: 50, channels: 4)
        var writer = BinaryWriter()
        header.write(to: &writer)
        XCTAssertEqual(writer.data.count, FileHeader.fixedSize)

        var reader = BinaryReader(data: writer.data)
        let parsed = try FileHeader.read(from: &reader)
        XCTAssertEqual(parsed.width, 100)
        XCTAssertEqual(parsed.height, 50)
        XCTAssertEqual(parsed.depth, 8)
        XCTAssertEqual(parsed.colorMode, .rgb)
    }
}
