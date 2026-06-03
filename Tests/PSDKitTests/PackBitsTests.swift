import XCTest
@testable import PSDKit

final class PackBitsTests: XCTestCase {
    func testRoundTripSolidRun() throws {
        let raw = Data(repeating: 0xAB, count: 100)
        let encoded = PackBitsCodec.encode(raw)
        let decoded = PackBitsCodec.decode(encoded, size: raw.count)
        XCTAssertEqual(decoded, raw)
    }

    func testRoundTripLiteral() throws {
        var raw = Data()
        for i in 0 ..< 50 {
            raw.append(UInt8(i % 251))
        }
        let encoded = PackBitsCodec.encode(raw)
        let decoded = PackBitsCodec.decode(encoded, size: raw.count)
        XCTAssertEqual(decoded, raw)
    }

    func testEmpty() {
        XCTAssertEqual(PackBitsCodec.encode(Data()), Data())
        XCTAssertEqual(PackBitsCodec.decode(Data(), size: 0), Data())
    }
}
