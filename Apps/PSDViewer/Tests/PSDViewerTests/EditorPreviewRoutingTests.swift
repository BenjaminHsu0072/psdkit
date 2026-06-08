import PSDKit
import XCTest
@testable import PSDViewer

final class EditorPreviewRoutingTests: XCTestCase {
    func testSupportedSnapshotUsesMetalPath() throws {
        let document = try PSDDocument.makeMidtermStandardDocument()
        let snapshot = EditorRenderSnapshotBuilder.build(from: document, documentRevision: 1)

        XCTAssertNil(
            EditorPreviewRouting.cpuFallbackReason(
                snapshot: snapshot,
                userPrefersMetal: true
            )
        )
    }

    func testUserDisabledMetalRequestsCPUFallback() throws {
        let document = try PSDDocument.create(width: 4, height: 4)
        let snapshot = EditorRenderSnapshotBuilder.build(from: document, documentRevision: 0)

        XCTAssertEqual(
            EditorPreviewRouting.cpuFallbackReason(
                snapshot: snapshot,
                userPrefersMetal: false
            ),
            .userDisabledMetal
        )
    }

    func testUnsupportedBlendRequestsCPUFallback() throws {
        let document = try makeDocumentWithUnsupportedBlend()
        let snapshot = EditorRenderSnapshotBuilder.build(from: document, documentRevision: 0)

        XCTAssertEqual(
            EditorPreviewRouting.cpuFallbackReason(
                snapshot: snapshot,
                userPrefersMetal: true
            ),
            .unsupportedBlendMode(.unknown)
        )
    }

    func testMetalBlendEncoderRejectsUnsupportedModes() {
        XCTAssertEqual(EditorMetalBlendMode.encode(.normal), EditorMetalBlendMode.normal)
        XCTAssertEqual(EditorMetalBlendMode.encode(.multiply), EditorMetalBlendMode.multiply)
        XCTAssertEqual(EditorMetalBlendMode.encode(.add), EditorMetalBlendMode.add)
        XCTAssertNil(EditorMetalBlendMode.encode(.passThrough))
        XCTAssertNil(EditorMetalBlendMode.encode(.unknown))
    }

    private func makeDocumentWithUnsupportedBlend() throws -> PSDDocument {
        let root = GroupLayer(name: "")
        let layer = try PixelLayer(
            name: "Unsupported",
            frame: PSDRect(left: 0, top: 0, right: 1, bottom: 1),
            pixels: PixelBuffer(width: 1, height: 1, rgba: Data([255, 0, 0, 255])),
            blendMode: .unknown
        )
        root.append(layer)
        return try PSDDocument.create(canvasSize: PSDSize(width: 1, height: 1), root: root)
    }
}
