import XCTest
@testable import PSDKit

struct PackBitsGoldenFile: Decodable {
    let version: Int
    let cases: [PackBitsGoldenCase]
}

struct PackBitsGoldenCase: Decodable {
    let name: String
    let rawHex: String
    let encodedHex: String
    let size: Int

    enum CodingKeys: String, CodingKey {
        case name
        case rawHex = "raw_hex"
        case encodedHex = "encoded_hex"
        case size
    }
}

final class PackBitsGoldenTests: XCTestCase {
    private var golden: PackBitsGoldenFile!

    override func setUpWithError() throws {
        guard let url = Bundle.module.url(forResource: "packbits", withExtension: "json", subdirectory: "Golden") else {
            throw XCTSkip("Run Scripts/generate_test_fixtures.py")
        }
        golden = try JSONDecoder().decode(PackBitsGoldenFile.self, from: Data(contentsOf: url))
    }

    func testAllPackBitsGoldenVectors() throws {
        for testCase in golden.cases {
            let raw = Data(hexString: testCase.rawHex) ?? Data()
            let encoded = Data(hexString: testCase.encodedHex) ?? Data()
            XCTAssertEqual(raw.count, testCase.size, testCase.name)

            let roundTrip = PackBitsCodec.encode(raw)
            let decoded = PackBitsCodec.decode(roundTrip, size: raw.count)
            XCTAssertEqual(decoded, raw, testCase.name)

            // psd-tools reference encoding (may differ in edge cases but must decode to same raw)
            let decodedFromRef = PackBitsCodec.decode(encoded, size: raw.count)
            XCTAssertEqual(decodedFromRef, raw, "\(testCase.name) reference decode")
        }
    }
}

private extension Data {
    init?(hexString: String) {
        let len = hexString.count / 2
        var data = Data(capacity: len)
        var index = hexString.startIndex
        for _ in 0 ..< len {
            let next = hexString.index(index, offsetBy: 2)
            guard let byte = UInt8(hexString[index ..< next], radix: 16) else { return nil }
            data.append(byte)
            index = next
        }
        self = data
    }
}
