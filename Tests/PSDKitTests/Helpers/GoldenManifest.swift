import Foundation
import XCTest

struct GoldenManifest: Decodable {
    let version: Int
    let fixtures: [GoldenFixture]
    let rejections: [GoldenRejection]
}

struct GoldenFixture: Decodable {
    let id: String
    let file: String
    let description: String
    let tags: [String]
    let v1ReadSupported: Bool
    let v1WriteRoundtrip: String
    let fileSha256: String
    let fileSize: Int
    let header: GoldenHeader
    let layerCount: Int
    let layers: [GoldenLayer]

    enum CodingKeys: String, CodingKey {
        case id, file, description, tags
        case v1ReadSupported = "v1_read_supported"
        case v1WriteRoundtrip = "v1_write_roundtrip"
        case fileSha256 = "file_sha256"
        case fileSize = "file_size"
        case header
        case layerCount = "layer_count"
        case layers
    }
}

struct GoldenHeader: Decodable {
    let width: Int
    let height: Int
    let channels: Int
    let depth: Int
    let version: Int
    let colorMode: Int

    enum CodingKeys: String, CodingKey {
        case width, height, channels, depth, version
        case colorMode = "color_mode"
    }
}

struct GoldenLayer: Decodable {
    let index: Int
    let name: String
    let kind: String
    let bbox: GoldenBBox
    let width: Int
    let height: Int
    let opacity: Int
    let visible: Bool
    let blendMode: String
    let rgbaFile: String?
    let pixelByteCount: Int
    let skipNameCheck: Bool

    enum CodingKeys: String, CodingKey {
        case index, name, kind, bbox, width, height, opacity, visible
        case blendMode = "blend_mode"
        case rgbaFile = "rgba_file"
        case pixelByteCount = "pixel_byte_count"
        case skipNameCheck = "skip_name_check"
    }
}

struct GoldenBBox: Decodable {
    let left: Int
    let top: Int
    let right: Int
    let bottom: Int
}

struct GoldenRejection: Decodable {
    let id: String
    let file: String
    let expectedError: String

    enum CodingKeys: String, CodingKey {
        case id, file
        case expectedError = "expected_error"
    }
}

enum GoldenLoader {
    static func loadManifest() throws -> GoldenManifest {
        guard let url = Bundle.module.url(forResource: "manifest", withExtension: "json", subdirectory: "Golden") else {
            throw XCTSkip("Run: python3 Scripts/generate_test_fixtures.py")
        }
        return try JSONDecoder().decode(GoldenManifest.self, from: Data(contentsOf: url))
    }

    static func fixtureURL(for entry: GoldenFixture) -> URL {
        guard let url = Bundle.module.url(
            forResource: entry.file.replacingOccurrences(of: ".psd", with: ""),
            withExtension: "psd",
            subdirectory: "Fixtures"
        ) else {
            fatalError("Missing fixture \(entry.file)")
        }
        return url
    }

    static func goldenRGBAURL(fileName: String) -> URL {
        guard let url = Bundle.module.url(
            forResource: fileName.replacingOccurrences(of: ".rgba", with: ""),
            withExtension: "rgba",
            subdirectory: "Golden/rgba"
        ) else {
            fatalError("Missing golden rgba \(fileName)")
        }
        return url
    }

    static func rejectionURL(for entry: GoldenRejection) -> URL {
        let name = (entry.file as NSString).lastPathComponent.replacingOccurrences(of: ".psd", with: "")
        guard let url = Bundle.module.url(
            forResource: name,
            withExtension: "psd",
            subdirectory: "Golden/rejections"
        ) else {
            fatalError("Missing rejection \(entry.file)")
        }
        return url
    }
}
