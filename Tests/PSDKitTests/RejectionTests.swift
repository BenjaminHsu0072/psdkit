import XCTest
@testable import PSDKit

final class RejectionTests: XCTestCase {
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
