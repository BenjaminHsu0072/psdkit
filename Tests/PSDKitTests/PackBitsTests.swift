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

    func testDecodeIntoPreallocatedBuffer() {
        let raw = Data([0, 1, 2, 3, 4, 5, 6, 7, 8, 9])
        let encoded = PackBitsCodec.encode(raw)
        var buffer = Data(count: raw.count + 4)
        let written = PackBitsCodec.decode(encoded, into: &buffer, writeOffset: 2, size: raw.count)
        XCTAssertEqual(written, raw.count)
        XCTAssertEqual(buffer.prefix(2), Data([0, 0]))
        XCTAssertEqual(Data(buffer.dropFirst(2).prefix(raw.count)), raw)
    }

    func testDecodeIntoReturnsWrittenByteCount() {
        let raw = Data(repeating: 0xAB, count: 16)
        let encoded = PackBitsCodec.encode(raw)
        var buffer = Data(count: raw.count)
        XCTAssertEqual(PackBitsCodec.decode(encoded, into: &buffer, writeOffset: 0, size: raw.count), raw.count)
        XCTAssertEqual(buffer, raw)
    }

    func testDecodeIntoRejectsOutOfBoundsSlice() {
        let raw = Data([10, 20, 30, 40])
        let encoded = PackBitsCodec.encode(raw)
        var buffer = Data(count: 2)
        XCTAssertEqual(PackBitsCodec.decode(encoded, into: &buffer, writeOffset: 0, size: raw.count), 0)
    }

    func testDecodeTruncatedInputReportsShortWrite() {
        var buffer = Data(count: 8)
        XCTAssertEqual(PackBitsCodec.decode(Data([0x00]), into: &buffer, writeOffset: 0, size: 8), 0)
        XCTAssertEqual(buffer, Data(count: 8))
    }
}
