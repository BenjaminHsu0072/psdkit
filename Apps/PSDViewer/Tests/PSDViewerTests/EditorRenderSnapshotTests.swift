import PSDKit
import XCTest
@testable import PSDViewer

final class EditorRenderSnapshotTests: XCTestCase {
    func testBuildFromMidtermStandardDocument() throws {
        let document = try PSDDocument.makeMidtermStandardDocument()
        let snapshot = EditorRenderSnapshotBuilder.build(
            from: document,
            documentRevision: 7,
            selectedLayerID: "1/1/0"
        )

        XCTAssertEqual(snapshot.canvasSize, document.canvasSize)
        XCTAssertEqual(snapshot.documentRevision, 7)
        XCTAssertEqual(snapshot.selectedLayerID, "1/1/0")

        let names = snapshot.layers.map(\.name)
        XCTAssertEqual(names, ["BG", "Group A", "Red", "Group B", "Glow", "Top"])

        let pixelLayers = snapshot.layers.filter { $0.kind == .pixel }
        XCTAssertEqual(pixelLayers.count, 4)
        XCTAssertTrue(pixelLayers.allSatisfy {
            if case .documentLayerUUID = $0.pixelSource { return true }
            return false
        })
        let hiddenTop = try XCTUnwrap(pixelLayers.first { $0.name == "Top" })
        XCTAssertFalse(hiddenTop.isVisible)
    }

    func testNestedPixelLayerInheritsGroupOpacity() throws {
        let root = GroupLayer(name: "")
        let group = GroupLayer(name: "Nested")
        group.opacity = 128
        let inner = try makePixel(name: "Inner")
        group.append(inner)
        root.append(group)
        let doc = try PSDDocument.create(canvasSize: PSDSize(width: 8, height: 8), root: root)

        let snapshot = EditorRenderSnapshotBuilder.build(from: doc, documentRevision: 1)
        let pixel = try XCTUnwrap(snapshot.layers.first { $0.kind == .pixel && $0.name == "Inner" })

        XCTAssertEqual(pixel.opacity, 128)
    }

    func testNestedPixelLayerRetainedWithEffectiveVisibilityWhenGroupHidden() throws {
        let root = GroupLayer(name: "")
        let group = GroupLayer(name: "Hidden")
        group.isVisible = false
        let inner = try makePixel(name: "Inner")
        group.append(inner)
        root.append(group)
        let doc = try PSDDocument.create(canvasSize: PSDSize(width: 8, height: 8), root: root)

        let snapshot = EditorRenderSnapshotBuilder.build(from: doc, documentRevision: 1)
        let pixel = try XCTUnwrap(snapshot.layers.first { $0.kind == .pixel && $0.name == "Inner" })

        XCTAssertEqual(pixel.id, "0/0")
        XCTAssertEqual(pixel.layerUUID, inner.id)
        XCTAssertFalse(pixel.isVisible)
        if case .documentLayerUUID(let uuid) = pixel.pixelSource {
            XCTAssertEqual(uuid, inner.id)
        } else {
            XCTFail("Expected documentLayerUUID pixel source")
        }
    }

    func testGroupHiddenThenShownPreservesLayerUUID() throws {
        let root = GroupLayer(name: "")
        let group = GroupLayer(name: "Toggle")
        let inner = try makePixel(name: "Inner")
        group.append(inner)
        root.append(group)
        let doc = try PSDDocument.create(canvasSize: PSDSize(width: 8, height: 8), root: root)

        let visibleSnapshot = EditorRenderSnapshotBuilder.build(from: doc, documentRevision: 1)
        group.isVisible = false
        let hiddenSnapshot = EditorRenderSnapshotBuilder.build(from: doc, documentRevision: 2)
        group.isVisible = true
        let shownSnapshot = EditorRenderSnapshotBuilder.build(from: doc, documentRevision: 3)

        let hiddenPixel = try XCTUnwrap(hiddenSnapshot.layers.first { $0.layerUUID == inner.id })
        XCTAssertFalse(hiddenPixel.isVisible)

        let shownPixel = try XCTUnwrap(shownSnapshot.layers.first { $0.layerUUID == inner.id })
        XCTAssertTrue(shownPixel.isVisible)
        XCTAssertEqual(shownPixel.layerUUID, visibleSnapshot.layers.first { $0.layerUUID == inner.id }?.layerUUID)
    }

    func testLayerReorderChangesPathButPreservesLayerUUID() throws {
        let root = GroupLayer(name: "")
        let first = try makePixel(name: "First")
        let second = try makePixel(name: "Second")
        root.append(first)
        root.append(second)
        let doc = try PSDDocument.create(canvasSize: PSDSize(width: 8, height: 8), root: root)

        let beforeMove = EditorRenderSnapshotBuilder.build(from: doc, documentRevision: 1)
        let firstBefore = try XCTUnwrap(beforeMove.layers.first { $0.layerUUID == first.id })
        XCTAssertEqual(firstBefore.id, "0")

        root.remove(second)
        root.insert(second, at: 0)

        let afterMove = EditorRenderSnapshotBuilder.build(from: doc, documentRevision: 2)
        let firstAfter = try XCTUnwrap(afterMove.layers.first { $0.layerUUID == first.id })
        let secondAfter = try XCTUnwrap(afterMove.layers.first { $0.layerUUID == second.id })

        XCTAssertEqual(firstAfter.id, "1")
        XCTAssertEqual(secondAfter.id, "0")
        XCTAssertEqual(firstAfter.layerUUID, first.id)
        XCTAssertEqual(firstAfter.pixelRevision, firstBefore.pixelRevision)
        if case .documentLayerUUID(let uuid) = firstAfter.pixelSource {
            XCTAssertEqual(uuid, first.id)
        } else {
            XCTFail("Expected documentLayerUUID pixel source")
        }
    }

    func testNestedPixelLayerPathsAndStackOrder() throws {
        let root = GroupLayer(name: "")
        let group = GroupLayer(name: "Nested")
        let inner = try makePixel(name: "Inner")
        group.append(inner)
        root.append(try makePixel(name: "RootPixel"))
        root.append(group)
        let doc = try PSDDocument.create(canvasSize: PSDSize(width: 8, height: 8), root: root)

        let snapshot = EditorRenderSnapshotBuilder.build(
            from: doc,
            documentRevision: 1,
            selectedLayerID: "1/0"
        )

        XCTAssertEqual(snapshot.layers.map(\.id), ["0", "1", "1/0"])
        XCTAssertEqual(snapshot.layers.map(\.stackOrder), [0, 1, 2])
        XCTAssertEqual(snapshot.layers[2].depth, 1)
        XCTAssertEqual(snapshot.layers[2].name, "Inner")
        XCTAssertEqual(snapshot.selectedLayerID, "1/0")
    }

    func testGroupLayerHasNoPixelSource() throws {
        let root = GroupLayer(name: "")
        root.append(GroupLayer(name: "G"))
        let doc = try PSDDocument.create(canvasSize: PSDSize(width: 4, height: 4), root: root)

        let snapshot = EditorRenderSnapshotBuilder.build(from: doc, documentRevision: 0)
        let group = try XCTUnwrap(snapshot.layers.first)

        XCTAssertEqual(group.kind, .group)
        XCTAssertEqual(group.pixelSource, .none)
        XCTAssertEqual(group.pixelRevision, 0)
    }

    func testViewportDefaults() throws {
        let doc = try PSDDocument.create(width: 4, height: 4)
        let snapshot = EditorRenderSnapshotBuilder.build(from: doc, documentRevision: 0)

        XCTAssertEqual(snapshot.viewport.canvasSize, CGSize(width: 4, height: 4))
        XCTAssertEqual(snapshot.viewport.scale, 1.0)
    }

    func testPixelRevisionDigestIsStableForSameRGBA() {
        let rgba = Data([10, 20, 30, 255, 40, 50, 60, 128])
        let first = EditorPixelRevisionDigest.digest(rgba: rgba)
        let second = EditorPixelRevisionDigest.digest(rgba: rgba)

        XCTAssertEqual(first, second)
        XCTAssertNotEqual(first, 0)
    }

    func testPixelRevisionDigestChangesWhenPixelsChange() {
        let baseline = Data([1, 2, 3, 4])
        let changed = Data([1, 2, 3, 5])

        XCTAssertNotEqual(
            EditorPixelRevisionDigest.digest(rgba: baseline),
            EditorPixelRevisionDigest.digest(rgba: changed)
        )
    }

    func testPixelProviderRecordsMissingDocumentLayerUUID() throws {
        let doc = try PSDDocument.create(width: 4, height: 4)
        let missingUUID = UUID()
        let ghostLayer = EditorLayerSnapshot(
            id: "0",
            layerUUID: missingUUID,
            name: "Ghost",
            kind: .pixel,
            depth: 0,
            stackOrder: 0,
            frame: PSDRect(left: 0, top: 0, right: 4, bottom: 4),
            isVisible: true,
            opacity: 255,
            blendMode: .normal,
            pixelRevision: 1,
            pixelSource: .documentLayerUUID(missingUUID)
        )
        let snapshot = EditorRenderSnapshot(
            canvasSize: PSDSize(width: 4, height: 4),
            layers: [ghostLayer],
            documentSessionID: UUID(),
            documentRevision: 1,
            selectedLayerID: nil,
            viewport: EditorViewport(canvasPixelSize: PSDSize(width: 4, height: 4))
        )

        let provider = EditorSnapshotPixelProvider.build(from: doc, snapshot: snapshot)

        XCTAssertEqual(provider.diagnostics.missingDocumentLayerUUIDs, [missingUUID])
        XCTAssertEqual(provider.diagnostics.missingDocumentLayerUUIDCount, 1)
        XCTAssertNil(provider.rgba(for: ghostLayer))
    }

    func testPixelProviderDoesNotRecordMissingWhenAllLayersResolve() throws {
        let doc = try PSDDocument.makeMidtermStandardDocument()
        let snapshot = EditorRenderSnapshotBuilder.build(from: doc, documentRevision: 1)
        let provider = EditorSnapshotPixelProvider.build(from: doc, snapshot: snapshot)

        XCTAssertTrue(provider.diagnostics.missingDocumentLayerUUIDs.isEmpty)
        XCTAssertEqual(provider.diagnostics.missingDocumentLayerUUIDCount, 0)

        let pixelLayer = try XCTUnwrap(snapshot.layers.first { $0.kind == .pixel && $0.name == "Red" })
        XCTAssertNotNil(provider.rgba(for: pixelLayer))
    }

    func testPixelRevisionReflectsLayerPixelContent() throws {
        let root = GroupLayer(name: "")
        let pixelA = try makePixel(name: "A", rgba: Data([1, 0, 0, 255, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]))
        let pixelB = try makePixel(name: "B", rgba: Data([2, 0, 0, 255, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]))
        root.append(pixelA)
        root.append(pixelB)
        let doc = try PSDDocument.create(canvasSize: PSDSize(width: 2, height: 2), root: root)

        let snapshot = EditorRenderSnapshotBuilder.build(from: doc, documentRevision: 0)
        let revisions = snapshot.layers.filter { $0.kind == .pixel }.map(\.pixelRevision)

        XCTAssertEqual(revisions.count, 2)
        XCTAssertNotEqual(revisions[0], revisions[1])
        XCTAssertEqual(
            revisions[0],
            EditorPixelRevisionDigest.digest(rgba: pixelA.pixels.rgba)
        )
        XCTAssertEqual(
            revisions[1],
            EditorPixelRevisionDigest.digest(rgba: pixelB.pixels.rgba)
        )
    }

    private func makePixel(name: String, rgba: Data = Data(count: 16)) throws -> PixelLayer {
        try PixelLayer(
            name: name,
            frame: PSDRect(left: 0, top: 0, right: 2, bottom: 2),
            pixels: PixelBuffer(width: 2, height: 2, rgba: rgba)
        )
    }
}
