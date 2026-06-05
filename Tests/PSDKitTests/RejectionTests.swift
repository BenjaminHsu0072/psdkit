import XCTest
@testable import PSDKit

final class RejectionTests: XCTestCase {
    func testUnsupportedCompressionThrows() throws {
        let manifest = try GoldenLoader.loadManifest()
        let subset = manifest.fixtures.filter { $0.tags.contains("single") && $0.v1ReadSupported }
        guard let entry = subset.first else {
            XCTFail("No supported fixture tagged 'single'")
            return
        }
        let base = try Data(contentsOf: GoldenLoader.fixtureURL(for: entry))

        var zipLayerData = base
        let layerCompressionOffset = try firstLayerChannelCompressionOffset(in: base)
        zipLayerData.replaceSubrange(
            layerCompressionOffset ..< layerCompressionOffset + 2,
            with: Data([0x00, 0x02])
        )
        XCTAssertThrowsError(try PSDDocument.load(data: zipLayerData)) { error in
            guard case .unsupportedCompression(2)? = error as? PSDError else {
                XCTFail("expected unsupportedCompression(2) for zip layer channel, got \(error)")
                return
            }
        }

        var unknownImageData = base
        let imageCompressionOffset = try imageDataCompressionOffset(in: base)
        unknownImageData.replaceSubrange(
            imageCompressionOffset ..< imageCompressionOffset + 2,
            with: Data([0x00, 0x63])
        )
        XCTAssertThrowsError(try PSDDocument.load(data: unknownImageData)) { error in
            guard case .unsupportedCompression(99)? = error as? PSDError else {
                XCTFail("expected unsupportedCompression(99) for unknown image compression, got \(error)")
                return
            }
        }
    }

    func testAllGoldenRejections() throws {
        let manifest = try GoldenLoader.loadManifest()
        for entry in manifest.rejections {
            let url = GoldenLoader.rejectionURL(for: entry)
            do {
                _ = try PSDDocument.load(url: url)
                XCTFail("Expected error \(entry.expectedError) for \(entry.id)")
            } catch let error as PSDError {
                XCTAssertEqual(psdErrorCaseName(error), entry.expectedError, entry.id)
            } catch {
                XCTFail("Unexpected error type for \(entry.id): \(error)")
            }
        }
    }

    /// Offset of the first layer's first channel compression uint16 (big-endian).
    private func firstLayerChannelCompressionOffset(in data: Data) throws -> Int {
        var reader = BinaryReader(data: data)
        let header = try FileHeader.read(from: &reader)
        _ = try reader.readLengthBlockUInt32()
        _ = try reader.readLengthBlockUInt32()
        _ = try reader.readUInt32() // layer+mask section length
        let layerInfoLength = Int(try reader.readUInt32())
        guard layerInfoLength > 0 else {
            throw NSError(
                domain: "RejectionTests",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "expected layer info"]
            )
        }
        let layerCount = abs(Int(try reader.readInt16()))
        for _ in 0 ..< layerCount {
            _ = try LayerRecord.read(from: &reader, psdVersion: Int(header.version))
        }
        let offset = reader.offset
        guard offset + 1 < data.count else {
            throw NSError(
                domain: "RejectionTests",
                code: 3,
                userInfo: [NSLocalizedDescriptionKey: "missing channel compression"]
            )
        }
        let marker = (data[offset], data[offset + 1])
        guard marker == (0x00, 0x00) || marker == (0x00, 0x01) else {
            throw NSError(
                domain: "RejectionTests",
                code: 4,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "unexpected channel compression marker at \(offset): \(marker.0) \(marker.1)",
                ]
            )
        }
        return offset
    }

    /// Offset of the composite image data compression uint16 (big-endian).
    private func imageDataCompressionOffset(in data: Data) throws -> Int {
        var reader = BinaryReader(data: data)
        _ = try FileHeader.read(from: &reader)
        _ = try reader.readLengthBlockUInt32()
        _ = try reader.readLengthBlockUInt32()
        let sectionStart = reader.offset
        let sectionLength = Int(try reader.readUInt32())
        let sectionEnd = sectionStart + 4 + sectionLength
        let layerInfoLength = Int(try reader.readUInt32())
        if layerInfoLength > 0 {
            try reader.seek(to: reader.offset + layerInfoLength)
        }
        if reader.offset + 4 <= sectionEnd {
            let maskLen = try reader.readUInt32()
            if maskLen > 0 {
                try reader.seek(to: reader.offset + Int(maskLen))
            }
        }
        if reader.offset < sectionEnd {
            try reader.seek(to: sectionEnd)
        }
        guard reader.offset + 2 <= data.count else {
            throw NSError(
                domain: "RejectionTests",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "missing image data compression"]
            )
        }
        return reader.offset
    }

    private func psdErrorCaseName(_ error: PSDError) -> String {
        switch error {
        case .invalidSignature: return "invalidSignature"
        case .unsupportedVersion: return "unsupportedVersion"
        case .unsupportedBitDepth: return "unsupportedBitDepth"
        case .unsupportedColorMode: return "unsupportedColorMode"
        case .unsupportedCompression: return "unsupportedCompression"
        case .unsupportedLayerKind: return "unsupportedLayerKind"
        case .corruptStructure: return "corruptStructure"
        case .unexpectedEOF: return "unexpectedEOF"
        case .io: return "io"
        }
    }
}
