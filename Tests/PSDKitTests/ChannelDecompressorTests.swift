import XCTest
@testable import PSDKit

final class ChannelDecompressorTests: XCTestCase {
    func testRLECompressDecompressRoundTrip() throws {
        let width = 4
        let height = 3
        var raw = Data()
        for row in 0 ..< height {
            for col in 0 ..< width {
                raw.append(UInt8((row * width + col) % 251))
            }
        }

        let compressed = try ChannelDecompressor.compress(
            raw: raw,
            compression: .rle,
            width: width,
            height: height
        )
        let decoded = try ChannelDecompressor.decompress(
            data: compressed,
            compression: .rle,
            width: width,
            height: height
        )
        XCTAssertEqual(decoded, raw)
    }

    func testRLECompressDecompressSolidRows() throws {
        let width = 8
        let height = 4
        let raw = Data(repeating: 0xAB, count: width * height)

        let compressed = try ChannelDecompressor.compress(
            raw: raw,
            compression: .rle,
            width: width,
            height: height
        )
        let decoded = try ChannelDecompressor.decompress(
            data: compressed,
            compression: .rle,
            width: width,
            height: height
        )
        XCTAssertEqual(decoded, raw)
    }

    func testPackBitsDecodeIntoMatchesReturnValue() {
        let raw = Data(repeating: 0xCD, count: 64)
        let encoded = PackBitsCodec.encode(raw)

        let expected = PackBitsCodec.decode(encoded, size: raw.count)
        var buffer = Data(count: raw.count)
        let written = PackBitsCodec.decode(encoded, into: &buffer, writeOffset: 0, size: raw.count)
        XCTAssertEqual(written, raw.count)
        XCTAssertEqual(buffer, expected)
    }

    func testRLETruncatedRowCountTableThrows() throws {
        let width = 4
        let height = 2
        let raw = Data(repeating: 0x11, count: width * height)
        let compressed = try ChannelDecompressor.compress(
            raw: raw,
            compression: .rle,
            width: width,
            height: height
        )
        let tableBytes = height * 2
        let truncated = compressed.prefix(tableBytes - 1)

        XCTAssertThrowsError(
            try ChannelDecompressor.decompress(
                data: truncated,
                compression: .rle,
                width: width,
                height: height
            )
        ) { error in
            guard case .corruptStructure? = error as? PSDError else {
                XCTFail("expected corruptStructure, got \(error)")
                return
            }
        }
    }

    func testRLETruncatedRowPayloadThrows() throws {
        let width = 4
        let height = 2
        let raw = Data(repeating: 0x22, count: width * height)
        let compressed = try ChannelDecompressor.compress(
            raw: raw,
            compression: .rle,
            width: width,
            height: height
        )
        let truncated = compressed.dropLast(1)

        XCTAssertThrowsError(
            try ChannelDecompressor.decompress(
                data: Data(truncated),
                compression: .rle,
                width: width,
                height: height
            )
        ) { error in
            guard case .corruptStructure? = error as? PSDError else {
                XCTFail("expected corruptStructure, got \(error)")
                return
            }
        }
    }

    func testRLETruncatedPackBitsRowThrows() throws {
        var compressed = Data()
        compressed.append(contentsOf: [0, 1]) // one row, payload length 1
        compressed.append(0x00) // PackBits header only; decodes 0 of 4 bytes

        XCTAssertThrowsError(
            try ChannelDecompressor.decompress(
                data: compressed,
                compression: .rle,
                width: 4,
                height: 1
            )
        ) { error in
            guard case .corruptStructure(let message)? = error as? PSDError else {
                XCTFail("expected corruptStructure, got \(error)")
                return
            }
            XCTAssertTrue(message.contains("PackBits decode short"))
        }
    }

    func testRLETrailingExtraCompressedBytesAllowed() throws {
        let width = 4
        let height = 2
        let raw = Data(repeating: 0x33, count: width * height)
        var compressed = try ChannelDecompressor.compress(
            raw: raw,
            compression: .rle,
            width: width,
            height: height
        )
        compressed.append(0xFF)

        let decoded = try ChannelDecompressor.decompress(
            data: compressed,
            compression: .rle,
            width: width,
            height: height
        )
        XCTAssertEqual(decoded, raw)
    }
}
