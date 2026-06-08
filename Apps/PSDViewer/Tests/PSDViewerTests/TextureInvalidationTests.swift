import PSDKit
import XCTest
@testable import PSDViewer

final class TextureInvalidationTests: XCTestCase {
    func testInvalidationReasonDescriptionsAreStable() {
        XCTAssertEqual(
            LayerTextureInvalidationReason.documentRevisionChanged.description,
            "documentRevisionChanged"
        )
        XCTAssertEqual(
            LayerTextureInvalidationReason.layerPixelRevisionChanged.description,
            "layerPixelRevisionChanged"
        )
        XCTAssertEqual(
            LayerTextureInvalidationReason.layerRemoved.description,
            "layerRemoved"
        )
        XCTAssertEqual(
            LayerTextureInvalidationReason.layerSizeChanged.description,
            "layerSizeChanged"
        )
        XCTAssertEqual(
            LayerTextureInvalidationReason.canvasSizeChanged.description,
            "canvasSizeChanged"
        )
        XCTAssertEqual(
            LayerTextureInvalidationReason.memoryPressure.description,
            "memoryPressure"
        )
        XCTAssertEqual(
            LayerTextureInvalidationReason.manualClear.description,
            "manualClear"
        )
        XCTAssertEqual(
            LayerTextureInvalidationReason.documentReloaded.description,
            "documentReloaded"
        )
    }

    func testCacheKeyUsesStableLayerUUIDAndDimensions() {
        let layerUUID = UUID()
        let layer = EditorLayerSnapshot(
            id: "1/0",
            layerUUID: layerUUID,
            name: "A",
            kind: .pixel,
            depth: 0,
            stackOrder: 0,
            frame: PSDRect(left: 0, top: 0, right: 3, bottom: 2),
            isVisible: true,
            opacity: 255,
            blendMode: .normal,
            pixelRevision: 7,
            pixelSource: .documentLayerUUID(layerUUID)
        )
        let payload = EditorSnapshotPixelProvider.PixelPayload(
            data: Data(repeating: 0, count: 3 * 2 * 4),
            width: 3,
            height: 2
        )

        let key = LayerTextureCacheKey(layer: layer, payload: payload)
        XCTAssertEqual(key?.layerUUID, layerUUID)
        XCTAssertEqual(key?.pixelRevision, 7)
        XCTAssertEqual(key?.pixelWidth, 3)
        XCTAssertEqual(key?.pixelHeight, 2)
    }
}
