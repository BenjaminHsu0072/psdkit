import Metal
import PSDKit
import XCTest
@testable import PSDViewer

final class LayerTextureCacheTests: XCTestCase {
    private var device: MTLDevice!

    override func setUpWithError() throws {
        try super.setUpWithError()
        guard let metalDevice = MTLCreateSystemDefaultDevice() else {
            throw XCTSkip("Metal unavailable in test environment")
        }
        device = metalDevice
    }

    func testLayerReorderWithStableUUIDDoesNotReupload() throws {
        let cache = LayerTextureCache(device: device)
        let layerUUID = UUID()
        let pathA = makeLayer(
            id: "0",
            layerUUID: layerUUID,
            revision: 42,
            width: 2,
            height: 2
        )
        let pathB = makeLayer(
            id: "1",
            layerUUID: layerUUID,
            revision: 42,
            width: 2,
            height: 2
        )
        let payload = makePayload(width: 2, height: 2, fill: 15)
        let snapshot = makeSnapshot(documentRevision: 2, canvas: PSDSize(width: 4, height: 4), layers: [pathB])

        cache.prepareForSnapshot(snapshot)
        _ = try cache.texture(for: pathA, payload: payload)
        _ = try cache.texture(for: pathB, payload: payload)

        XCTAssertEqual(cache.diagnostics.uploadCount, 1)
        XCTAssertEqual(cache.diagnostics.hitCount, 1)
        XCTAssertFalse(cache.diagnostics.lastInvalidationReasons.contains(.layerRemoved))
    }

    func testGroupHiddenThenShownRetainsTextureWithoutReupload() throws {
        let cache = LayerTextureCache(device: device)
        let layerUUID = UUID()
        let visibleLayer = makeLayer(
            id: "0/0",
            layerUUID: layerUUID,
            revision: 1,
            width: 2,
            height: 2,
            isVisible: true
        )
        let hiddenLayer = makeLayer(
            id: "0/0",
            layerUUID: layerUUID,
            revision: 1,
            width: 2,
            height: 2,
            isVisible: false
        )
        let payload = makePayload(width: 2, height: 2, fill: 16)
        let sessionID = UUID()
        let visibleSnapshot = makeSnapshot(
            documentSessionID: sessionID,
            documentRevision: 1,
            canvas: PSDSize(width: 4, height: 4),
            layers: [visibleLayer]
        )
        let hiddenSnapshot = makeSnapshot(
            documentSessionID: sessionID,
            documentRevision: 2,
            canvas: PSDSize(width: 4, height: 4),
            layers: [hiddenLayer]
        )
        let shownSnapshot = makeSnapshot(
            documentSessionID: sessionID,
            documentRevision: 3,
            canvas: PSDSize(width: 4, height: 4),
            layers: [visibleLayer]
        )

        cache.prepareForSnapshot(visibleSnapshot)
        _ = try cache.texture(for: visibleLayer, payload: payload)
        XCTAssertEqual(cache.diagnostics.uploadCount, 1)

        cache.prepareForSnapshot(hiddenSnapshot)
        let keepKey = try XCTUnwrap(LayerTextureCacheKey(layer: hiddenLayer, payload: payload))
        cache.prune(keeping: [keepKey])
        XCTAssertEqual(cache.diagnostics.textureCount, 1)

        cache.prepareForSnapshot(shownSnapshot)
        _ = try cache.texture(for: visibleLayer, payload: payload)

        XCTAssertEqual(cache.diagnostics.uploadCount, 1)
        XCTAssertEqual(cache.diagnostics.hitCount, 1)
        XCTAssertFalse(cache.diagnostics.lastInvalidationReasons.contains(.layerRemoved))
    }

    func testSameLayerUUIDAndPixelRevisionHitsCache() throws {
        let cache = LayerTextureCache(device: device)
        let layer = makeLayer(id: "0", revision: 42, width: 2, height: 2)
        let payload = makePayload(width: 2, height: 2, fill: 1)
        let snapshot = makeSnapshot(documentRevision: 1, canvas: PSDSize(width: 4, height: 4), layers: [layer])

        cache.prepareForSnapshot(snapshot)
        _ = try cache.texture(for: layer, payload: payload)
        _ = try cache.texture(for: layer, payload: payload)

        XCTAssertEqual(cache.diagnostics.uploadCount, 1)
        XCTAssertEqual(cache.diagnostics.hitCount, 1)
        XCTAssertEqual(cache.diagnostics.missCount, 1)
        XCTAssertEqual(cache.diagnostics.textureCount, 1)
    }

    func testPixelRevisionChangeTriggersReupload() throws {
        let cache = LayerTextureCache(device: device)
        let layerUUID = UUID()
        let initialLayer = makeLayer(id: "0", layerUUID: layerUUID, revision: 10, width: 2, height: 2)
        let updatedLayer = makeLayer(id: "0", layerUUID: layerUUID, revision: 11, width: 2, height: 2)
        let payload = makePayload(width: 2, height: 2, fill: 2)
        let snapshot = makeSnapshot(documentRevision: 1, canvas: PSDSize(width: 4, height: 4), layers: [updatedLayer])

        cache.prepareForSnapshot(snapshot)
        _ = try cache.texture(for: initialLayer, payload: payload)
        _ = try cache.texture(for: updatedLayer, payload: payload)

        XCTAssertEqual(cache.diagnostics.uploadCount, 2)
        XCTAssertEqual(cache.diagnostics.hitCount, 0)
        XCTAssertTrue(
            cache.diagnostics.lastInvalidationReasons.contains(.layerPixelRevisionChanged)
        )
    }

    func testLayerSizeChangeDoesNotWronglyReuseTexture() throws {
        let cache = LayerTextureCache(device: device)
        let layerUUID = UUID()
        let sameRevision: UInt64 = 99
        let smallLayer = makeLayer(id: "0", layerUUID: layerUUID, revision: sameRevision, width: 2, height: 2)
        let largeLayer = makeLayer(id: "0", layerUUID: layerUUID, revision: sameRevision, width: 4, height: 4)
        let smallPayload = makePayload(width: 2, height: 2, fill: 3)
        let largePayload = makePayload(width: 4, height: 4, fill: 4)
        let snapshot = makeSnapshot(documentRevision: 1, canvas: PSDSize(width: 8, height: 8), layers: [largeLayer])

        cache.prepareForSnapshot(snapshot)
        let first = try cache.texture(for: smallLayer, payload: smallPayload)
        let second = try cache.texture(for: largeLayer, payload: largePayload)

        XCTAssertEqual(first.width, 2)
        XCTAssertEqual(second.width, 4)
        XCTAssertEqual(cache.diagnostics.uploadCount, 2)
        XCTAssertTrue(cache.diagnostics.lastInvalidationReasons.contains(.layerSizeChanged))
    }

    func testLayerRemovalStillPrunesByUUID() throws {
        let cache = LayerTextureCache(device: device)
        let removedUUID = UUID()
        let keptUUID = UUID()
        let removedLayer = makeLayer(id: "0", layerUUID: removedUUID, revision: 1, width: 2, height: 2)
        let keptLayer = makeLayer(id: "1", layerUUID: keptUUID, revision: 2, width: 2, height: 2)
        let payloadRemoved = makePayload(width: 2, height: 2, fill: 5)
        let payloadKept = makePayload(width: 2, height: 2, fill: 6)
        let snapshot = makeSnapshot(documentRevision: 1, canvas: PSDSize(width: 4, height: 4), layers: [keptLayer])

        cache.prepareForSnapshot(snapshot)
        _ = try cache.texture(for: removedLayer, payload: payloadRemoved)
        _ = try cache.texture(for: keptLayer, payload: payloadKept)
        XCTAssertEqual(cache.diagnostics.textureCount, 2)

        let keepKey = try XCTUnwrap(LayerTextureCacheKey(layer: keptLayer, payload: payloadKept))
        cache.prune(keeping: [keepKey])

        XCTAssertEqual(cache.diagnostics.textureCount, 1)
        XCTAssertEqual(cache.diagnostics.pruneCount, 1)
        XCTAssertTrue(cache.diagnostics.lastInvalidationReasons.contains(.layerRemoved))
    }

    func testPruneRemovesLayerAndRecordsReason() throws {
        let cache = LayerTextureCache(device: device)
        let layerA = makeLayer(id: "0", revision: 1, width: 2, height: 2)
        let layerB = makeLayer(id: "1", revision: 2, width: 2, height: 2)
        let payloadA = makePayload(width: 2, height: 2, fill: 5)
        let payloadB = makePayload(width: 2, height: 2, fill: 6)
        let snapshot = makeSnapshot(documentRevision: 1, canvas: PSDSize(width: 4, height: 4), layers: [layerA, layerB])

        cache.prepareForSnapshot(snapshot)
        _ = try cache.texture(for: layerA, payload: payloadA)
        _ = try cache.texture(for: layerB, payload: payloadB)
        XCTAssertEqual(cache.diagnostics.textureCount, 2)

        let keepA = try XCTUnwrap(LayerTextureCacheKey(layer: layerA, payload: payloadA))
        cache.prune(keeping: [keepA])

        XCTAssertEqual(cache.diagnostics.textureCount, 1)
        XCTAssertEqual(cache.diagnostics.pruneCount, 1)
        XCTAssertTrue(cache.diagnostics.lastInvalidationReasons.contains(.layerRemoved))
    }

    func testDocumentRevisionChangeDoesNotClearCache() throws {
        let cache = LayerTextureCache(device: device)
        let layer = makeLayer(id: "0", revision: 1, width: 2, height: 2)
        let payload = makePayload(width: 2, height: 2, fill: 7)
        let sessionID = UUID()
        let firstSnapshot = makeSnapshot(
            documentSessionID: sessionID,
            documentRevision: 1,
            canvas: PSDSize(width: 4, height: 4),
            layers: [layer]
        )
        let secondSnapshot = makeSnapshot(
            documentSessionID: sessionID,
            documentRevision: 2,
            canvas: PSDSize(width: 4, height: 4),
            layers: [layer]
        )

        cache.prepareForSnapshot(firstSnapshot)
        _ = try cache.texture(for: layer, payload: payload)
        XCTAssertEqual(cache.diagnostics.textureCount, 1)
        XCTAssertEqual(cache.diagnostics.uploadCount, 1)

        cache.prepareForSnapshot(secondSnapshot)
        _ = try cache.texture(for: layer, payload: payload)

        XCTAssertEqual(cache.diagnostics.textureCount, 1)
        XCTAssertEqual(cache.diagnostics.uploadCount, 1)
        XCTAssertEqual(cache.diagnostics.hitCount, 1)
        XCTAssertFalse(cache.diagnostics.lastInvalidationReasons.contains(.documentRevisionChanged))
        XCTAssertFalse(cache.diagnostics.lastInvalidationReasons.contains(.documentReloaded))
    }

    func testDocumentSessionChangeClearsCache() throws {
        let cache = LayerTextureCache(device: device)
        let layer = makeLayer(id: "0", revision: 1, width: 2, height: 2)
        let payload = makePayload(width: 2, height: 2, fill: 12)
        let firstSnapshot = makeSnapshot(
            documentSessionID: UUID(),
            documentRevision: 1,
            canvas: PSDSize(width: 4, height: 4),
            layers: [layer]
        )
        let secondSnapshot = makeSnapshot(
            documentSessionID: UUID(),
            documentRevision: 1,
            canvas: PSDSize(width: 4, height: 4),
            layers: [layer]
        )

        cache.prepareForSnapshot(firstSnapshot)
        _ = try cache.texture(for: layer, payload: payload)
        XCTAssertEqual(cache.diagnostics.textureCount, 1)

        cache.prepareForSnapshot(secondSnapshot)
        XCTAssertEqual(cache.diagnostics.textureCount, 0)
        XCTAssertTrue(cache.diagnostics.lastInvalidationReasons.contains(.documentReloaded))
    }

    func testVisibilityToggleRetainsTextureWithoutReupload() throws {
        let cache = LayerTextureCache(device: device)
        let layerUUID = UUID()
        let visibleLayer = makeLayer(id: "0", layerUUID: layerUUID, revision: 1, width: 2, height: 2, isVisible: true)
        let hiddenLayer = makeLayer(id: "0", layerUUID: layerUUID, revision: 1, width: 2, height: 2, isVisible: false)
        let payload = makePayload(width: 2, height: 2, fill: 13)
        let sessionID = UUID()
        let visibleSnapshot = makeSnapshot(
            documentSessionID: sessionID,
            documentRevision: 1,
            canvas: PSDSize(width: 4, height: 4),
            layers: [visibleLayer]
        )
        let hiddenSnapshot = makeSnapshot(
            documentSessionID: sessionID,
            documentRevision: 2,
            canvas: PSDSize(width: 4, height: 4),
            layers: [hiddenLayer]
        )
        let visibleAgainSnapshot = makeSnapshot(
            documentSessionID: sessionID,
            documentRevision: 3,
            canvas: PSDSize(width: 4, height: 4),
            layers: [visibleLayer]
        )

        cache.prepareForSnapshot(visibleSnapshot)
        _ = try cache.texture(for: visibleLayer, payload: payload)
        XCTAssertEqual(cache.diagnostics.uploadCount, 1)

        cache.prepareForSnapshot(hiddenSnapshot)
        let keepKey = try XCTUnwrap(LayerTextureCacheKey(layer: hiddenLayer, payload: payload))
        cache.prune(keeping: [keepKey])
        XCTAssertEqual(cache.diagnostics.textureCount, 1)

        cache.prepareForSnapshot(visibleAgainSnapshot)
        _ = try cache.texture(for: visibleLayer, payload: payload)

        XCTAssertEqual(cache.diagnostics.uploadCount, 1)
        XCTAssertEqual(cache.diagnostics.hitCount, 1)
        XCTAssertFalse(cache.diagnostics.lastInvalidationReasons.contains(.layerRemoved))
    }

    func testPropertyEditWithDocumentRevisionBumpDoesNotReupload() throws {
        let cache = LayerTextureCache(device: device)
        let layerUUID = UUID()
        let baseLayer = makeLayer(
            id: "0",
            layerUUID: layerUUID,
            revision: 20,
            width: 2,
            height: 2,
            opacity: 255,
            blend: .normal,
            isVisible: true
        )
        let editedLayer = makeLayer(
            id: "0",
            layerUUID: layerUUID,
            revision: 20,
            width: 2,
            height: 2,
            opacity: 64,
            blend: .multiply,
            isVisible: true,
            frame: PSDRect(left: 1, top: 1, right: 3, bottom: 3)
        )
        let payload = makePayload(width: 2, height: 2, fill: 14)
        let sessionID = UUID()
        let beforeEdit = makeSnapshot(
            documentSessionID: sessionID,
            documentRevision: 1,
            canvas: PSDSize(width: 4, height: 4),
            layers: [baseLayer]
        )
        let afterEdit = makeSnapshot(
            documentSessionID: sessionID,
            documentRevision: 2,
            canvas: PSDSize(width: 4, height: 4),
            layers: [editedLayer]
        )

        cache.prepareForSnapshot(beforeEdit)
        _ = try cache.texture(for: baseLayer, payload: payload)
        cache.prepareForSnapshot(afterEdit)
        _ = try cache.texture(for: editedLayer, payload: payload)

        XCTAssertEqual(cache.diagnostics.uploadCount, 1)
        XCTAssertEqual(cache.diagnostics.hitCount, 1)
        XCTAssertFalse(cache.diagnostics.lastInvalidationReasons.contains(.documentReloaded))
        XCTAssertFalse(cache.diagnostics.lastInvalidationReasons.contains(.layerPixelRevisionChanged))
    }

    func testCanvasSizeChangeRecordsInvalidationWithoutWrongReuse() throws {
        let cache = LayerTextureCache(device: device)
        let layer = makeLayer(id: "0", revision: 5, width: 2, height: 2)
        let payload = makePayload(width: 2, height: 2, fill: 8)
        let sessionID = UUID()
        let smallCanvas = makeSnapshot(
            documentSessionID: sessionID,
            documentRevision: 1,
            canvas: PSDSize(width: 4, height: 4),
            layers: [layer]
        )
        let largeCanvas = makeSnapshot(
            documentSessionID: sessionID,
            documentRevision: 1,
            canvas: PSDSize(width: 8, height: 8),
            layers: [layer]
        )

        cache.prepareForSnapshot(smallCanvas)
        _ = try cache.texture(for: layer, payload: payload)
        cache.prepareForSnapshot(largeCanvas)
        _ = try cache.texture(for: layer, payload: payload)

        XCTAssertEqual(cache.diagnostics.uploadCount, 1)
        XCTAssertEqual(cache.diagnostics.hitCount, 1)
        XCTAssertTrue(cache.diagnostics.lastInvalidationReasons.contains(.canvasSizeChanged))
    }

    func testManualClearResetsTexturesAndRecordsReason() throws {
        let cache = LayerTextureCache(device: device)
        let layer = makeLayer(id: "0", revision: 1, width: 2, height: 2)
        let payload = makePayload(width: 2, height: 2, fill: 9)
        let snapshot = makeSnapshot(documentRevision: 1, canvas: PSDSize(width: 4, height: 4), layers: [layer])

        cache.prepareForSnapshot(snapshot)
        _ = try cache.texture(for: layer, payload: payload)
        cache.clear(reason: .manualClear)

        XCTAssertEqual(cache.diagnostics.textureCount, 0)
        XCTAssertEqual(cache.diagnostics.clearCount, 1)
        XCTAssertEqual(cache.diagnostics.lastInvalidationReasons.last, .manualClear)
    }

    func testUploadCreatesFullLayerDirtyRecord() throws {
        let cache = LayerTextureCache(device: device)
        let layer = makeLayer(id: "0", revision: 3, width: 2, height: 2)
        let payload = makePayload(width: 2, height: 2, fill: 10)
        let snapshot = makeSnapshot(documentRevision: 1, canvas: PSDSize(width: 4, height: 4), layers: [layer])

        cache.prepareForSnapshot(snapshot)
        _ = try cache.texture(for: layer, payload: payload)
        let key = try XCTUnwrap(LayerTextureCacheKey(layer: layer, payload: payload))
        let record = try XCTUnwrap(cache.record(for: key))

        XCTAssertEqual(record.dirtyRegion, .fullLayer)
        XCTAssertEqual(record.pixelRevision, 3)
        XCTAssertEqual(record.size, PSDSize(width: 2, height: 2))
    }

    func testPropertyOnlyChangesDoNotReuploadTextures() throws {
        let cache = LayerTextureCache(device: device)
        let layerUUID = UUID()
        let baseLayer = makeLayer(
            id: "0",
            layerUUID: layerUUID,
            revision: 20,
            width: 2,
            height: 2,
            opacity: 255,
            blend: .normal
        )
        let changedLayer = makeLayer(
            id: "0",
            layerUUID: layerUUID,
            revision: 20,
            width: 2,
            height: 2,
            opacity: 128,
            blend: .multiply
        )
        let payload = makePayload(width: 2, height: 2, fill: 11)
        let snapshot = makeSnapshot(documentRevision: 1, canvas: PSDSize(width: 4, height: 4), layers: [changedLayer])

        cache.prepareForSnapshot(snapshot)
        _ = try cache.texture(for: baseLayer, payload: payload)
        _ = try cache.texture(for: changedLayer, payload: payload)

        XCTAssertEqual(cache.diagnostics.uploadCount, 1)
        XCTAssertEqual(cache.diagnostics.hitCount, 1)
        XCTAssertFalse(cache.diagnostics.lastInvalidationReasons.contains(.layerPixelRevisionChanged))
    }

    func testMetalBackendDoesNotReferencePSDDocument() throws {
        let metalBackendDir = moduleDirectory(named: "MetalBackend")
        let files = try swiftFiles(in: metalBackendDir)
        XCTAssertFalse(files.isEmpty)
        for file in files {
            let content = try String(contentsOf: file, encoding: .utf8)
            XCTAssertFalse(
                content.contains("PSDDocument"),
                "\(file.lastPathComponent) must not reference PSDDocument"
            )
        }
    }

    private func makeLayer(
        id: String,
        layerUUID: UUID = UUID(),
        revision: UInt64,
        width: Int,
        height: Int,
        opacity: UInt8 = 255,
        blend: BlendMode = .normal,
        isVisible: Bool = true,
        frame: PSDRect? = nil
    ) -> EditorLayerSnapshot {
        EditorLayerSnapshot(
            id: id,
            layerUUID: layerUUID,
            name: "Layer-\(id)",
            kind: .pixel,
            depth: 0,
            stackOrder: 0,
            frame: frame ?? PSDRect(left: 0, top: 0, right: width, bottom: height),
            isVisible: isVisible,
            opacity: opacity,
            blendMode: blend,
            pixelRevision: revision,
            pixelSource: .documentLayerUUID(layerUUID)
        )
    }

    private func makePayload(width: Int, height: Int, fill: UInt8) -> EditorSnapshotPixelProvider.PixelPayload {
        var rgba = Data(repeating: 0, count: width * height * 4)
        for index in 0 ..< width * height {
            let base = index * 4
            rgba[base] = fill
            rgba[base + 1] = fill
            rgba[base + 2] = fill
            rgba[base + 3] = 255
        }
        return EditorSnapshotPixelProvider.PixelPayload(data: rgba, width: width, height: height)
    }

    private func makeSnapshot(
        documentSessionID: UUID = UUID(),
        documentRevision: UInt64,
        canvas: PSDSize,
        layers: [EditorLayerSnapshot]
    ) -> EditorRenderSnapshot {
        EditorRenderSnapshot(
            canvasSize: canvas,
            layers: layers,
            documentSessionID: documentSessionID,
            documentRevision: documentRevision,
            selectedLayerID: nil,
            viewport: .default(canvasPixelSize: canvas)
        )
    }

    private func moduleDirectory(named name: String) -> URL {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0 ..< 3 {
            url.deleteLastPathComponent()
        }
        return url.appendingPathComponent("Sources/PSDViewer/\(name)", isDirectory: true)
    }

    private func swiftFiles(in directory: URL) throws -> [URL] {
        let contents = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        )
        return contents.filter { $0.pathExtension == "swift" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
    }
}
