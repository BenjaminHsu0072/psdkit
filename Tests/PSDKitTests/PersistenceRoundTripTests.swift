import XCTest
@testable import PSDKit

final class PersistenceRoundTripTests: XCTestCase {
    func testCreateOpenSaveOpenPreservesSnapshot() throws {
        let original = try MidtermStandardDocument.make()
        let before = DocumentSnapshot.capture(from: original)

        original.markContentModified()
        let data = try original.data(writeMode: .semantic)
        let reloaded = try PSDDocument.load(data: data)
        let after = DocumentSnapshot.capture(from: reloaded)

        before.assertEqual(to: after)
    }

    func testCreateSaveToFileOpenPreservesSnapshot() throws {
        let original = try MidtermStandardDocument.make()
        let before = DocumentSnapshot.capture(from: original)

        let temp = try makeTempPSDURL("midterm-standard-roundtrip")
        defer { try? FileManager.default.removeItem(at: temp) }

        original.markContentModified()
        try original.save(to: temp, writeMode: .semantic)

        let reloaded = try PSDDocument.load(url: temp)
        let after = DocumentSnapshot.capture(from: reloaded)

        before.assertEqual(to: after)
    }

    /// Three cumulative `open → edit → semantic save → open` cycles with snapshot verification each round.
    func testThreeEditSaveCycles() throws {
        let temp = try makeTempPSDURL("midterm-three-edit-cycles")
        defer { try? FileManager.default.removeItem(at: temp) }

        let seed = try MidtermStandardDocument.make()
        seed.markContentModified()
        try seed.save(to: temp, writeMode: .semantic)

        var doc = try PSDDocument.load(url: temp)

        // Round 1 — in-place metadata: rename, frame, opacity, blend, visibility.
        let bg = try XCTUnwrap(findPixel(named: "BG", in: doc.root))
        let red = try XCTUnwrap(findPixel(named: "Red", in: doc.root))
        let top = try XCTUnwrap(findPixel(named: "Top", in: doc.root))
        let glow = try XCTUnwrap(findPixel(named: "Glow", in: doc.root))

        bg.name = "Background"
        bg.frame = PSDRect(left: 0, top: 0, right: 14, bottom: 14)
        try cropPixelBufferToTopLeft(of: bg)
        red.opacity = 128
        red.blendMode = .normal
        top.isVisible = true
        glow.frame = PSDRect(left: 0, top: 0, right: 12, bottom: 12)
        try cropPixelBufferToTopLeft(of: glow)
        doc.markContentModified()

        let expectedRound1 = DocumentSnapshot.capture(from: doc)
        doc = try semanticSaveAndReload(doc, to: temp)
        DocumentSnapshot.capture(from: doc).assertEqual(to: expectedRound1)

        // Round 2 — pixel edit and further blend/opacity changes (requires round 1 reload).
        let background = try XCTUnwrap(findPixel(named: "Background", in: doc.root))
        let redRound2 = try XCTUnwrap(findPixel(named: "Red", in: doc.root))
        let topRound2 = try XCTUnwrap(findPixel(named: "Top", in: doc.root))

        try patchPixel(background, index: 0, red: 0, green: 200, blue: 0, alpha: 255)
        redRound2.blendMode = .add
        redRound2.opacity = 64
        topRound2.blendMode = .multiply
        topRound2.opacity = 180
        doc.markContentModified()

        let expectedRound2 = DocumentSnapshot.capture(from: doc)
        doc = try semanticSaveAndReload(doc, to: temp)
        DocumentSnapshot.capture(from: doc).assertEqual(to: expectedRound2)

        // Round 3 — structure: add to group, delete from group, move between groups.
        let groupA = try XCTUnwrap(findGroup(named: "Group A", in: doc.root))
        let groupB = try XCTUnwrap(findGroup(named: "Group B", in: doc.root))
        let redRound3 = try XCTUnwrap(findPixel(named: "Red", in: doc.root))
        let glowRound3 = try XCTUnwrap(findPixel(named: "Glow", in: doc.root))

        let stamp = try PSDDocument.makeSolidLayer(
            name: "Stamp",
            canvasSize: doc.canvasSize,
            red: 255,
            green: 255,
            blue: 0,
            alpha: 255
        )
        doc.appendLayer(stamp, to: groupA)
        doc.removeLayer(glowRound3)
        doc.insertLayer(redRound3, to: groupB, at: 0)

        let expectedRound3 = DocumentSnapshot.capture(from: doc)
        doc = try semanticSaveAndReload(doc, to: temp)
        DocumentSnapshot.capture(from: doc).assertEqual(to: expectedRound3)

        XCTAssertNil(findPixel(named: "Glow", in: doc.root))
        let reloadedGroupA = try XCTUnwrap(findGroup(named: "Group A", in: doc.root))
        let reloadedGroupB = try XCTUnwrap(findGroup(named: "Group B", in: doc.root))
        let reloadedRed = try XCTUnwrap(findPixel(named: "Red", in: doc.root))
        XCTAssertIdentical(reloadedRed.parent, reloadedGroupB)
        XCTAssertFalse(reloadedGroupA.children.contains { $0.id == reloadedRed.id })
        XCTAssertNotNil(findPixel(named: "Stamp", in: reloadedGroupA))
    }

    func testInPlacePropertyEditRequiresDirtyMark() throws {
        let temp = try makeTempPSDURL("midterm-dirty-negative")
        defer { try? FileManager.default.removeItem(at: temp) }

        let seed = try MidtermStandardDocument.make()
        seed.markContentModified()
        try seed.save(to: temp, writeMode: .semantic)

        let baseline = DocumentSnapshot.capture(from: try PSDDocument.load(url: temp))

        let doc = try PSDDocument.load(url: temp)
        XCTAssertFalse(doc.isContentDirty)
        let bg = try XCTUnwrap(findPixel(named: "BG", in: doc.root))
        bg.name = "ShouldNotPersist"
        bg.opacity = 1
        bg.blendMode = .add
        bg.isVisible = false

        try doc.save(to: temp, writeMode: .passthrough)

        let reloaded = try PSDDocument.load(url: temp)
        DocumentSnapshot.capture(from: reloaded).assertEqual(to: baseline)
        XCTAssertEqual(findPixel(named: "BG", in: reloaded.root)?.name, "BG")
        XCTAssertEqual(findPixel(named: "BG", in: reloaded.root)?.opacity, 255)
    }

    /// Semantic save must not embed PSDKit-private manifest, custom image resources, or non-standard tagged blocks.
    func testNoPrivateMetadataIsWritten() throws {
        let doc = try MidtermStandardDocument.make()
        doc.markContentModified()
        let data = try doc.data(writeMode: .semantic)
        let file = try PSDFile.read(data: data)
        SemanticPSDMetadataInspector.assertNoPrivateMetadata(in: file)
    }

    func testExplicitSemanticSavePersistsWithoutDirtyMark() throws {
        let temp = try makeTempPSDURL("midterm-explicit-semantic")
        defer { try? FileManager.default.removeItem(at: temp) }

        let seed = try MidtermStandardDocument.make()
        seed.markContentModified()
        try seed.save(to: temp, writeMode: .semantic)

        let doc = try PSDDocument.load(url: temp)
        XCTAssertFalse(doc.isContentDirty)
        let top = try XCTUnwrap(findPixel(named: "Top", in: doc.root))
        top.isVisible = true
        top.name = "TopVisible"

        let expected = DocumentSnapshot.capture(from: doc)
        let reloaded = try saveAndReload(doc, to: temp, writeMode: .semantic)
        DocumentSnapshot.capture(from: reloaded).assertEqual(to: expected)
    }

    // MARK: - Helpers

    private func makeTempPSDURL(_ name: String) throws -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("\(name)-\(UUID().uuidString).psd")
    }

    private func semanticSaveAndReload(_ doc: PSDDocument, to url: URL) throws -> PSDDocument {
        try saveAndReload(doc, to: url, writeMode: .semantic)
    }

    private func saveAndReload(_ doc: PSDDocument, to url: URL, writeMode: PSDWriteMode) throws -> PSDDocument {
        try doc.save(to: url, writeMode: writeMode)
        return try PSDDocument.load(url: url)
    }

    private func findPixel(named name: String, in group: GroupLayer) -> PixelLayer? {
        for child in group.children {
            if let pixel = child as? PixelLayer, pixel.name == name {
                return pixel
            }
            if let nested = child as? GroupLayer, let found = findPixel(named: name, in: nested) {
                return found
            }
        }
        return nil
    }

    private func findGroup(named name: String, in group: GroupLayer) -> GroupLayer? {
        for child in group.children {
            if let nested = child as? GroupLayer {
                if nested.name == name { return nested }
                if let found = findGroup(named: name, in: nested) { return found }
            }
        }
        return nil
    }

    /// Crops in-memory RGBA to `layer.frame.width` × `layer.frame.height` from the top-left.
    private func cropPixelBufferToTopLeft(of layer: PixelLayer) throws {
        let w = layer.frame.width
        let h = layer.frame.height
        let srcW = layer.pixels.width
        let src = layer.pixels.rgba
        var dst = Data(count: w * h * 4)
        for y in 0 ..< h {
            for x in 0 ..< w {
                let srcOff = (y * srcW + x) * 4
                let dstOff = (y * w + x) * 4
                dst[dstOff] = src[srcOff]
                dst[dstOff + 1] = src[srcOff + 1]
                dst[dstOff + 2] = src[srcOff + 2]
                dst[dstOff + 3] = src[srcOff + 3]
            }
        }
        layer.pixels = try PixelBuffer(width: w, height: h, rgba: dst)
    }

    private func patchPixel(
        _ layer: PixelLayer,
        index: Int,
        red: UInt8,
        green: UInt8,
        blue: UInt8,
        alpha: UInt8
    ) throws {
        var rgba = layer.pixels.rgba
        let offset = index * 4
        guard offset + 3 < rgba.count else {
            throw PSDError.corruptStructure("pixel index out of range")
        }
        rgba[offset] = red
        rgba[offset + 1] = green
        rgba[offset + 2] = blue
        rgba[offset + 3] = alpha
        layer.pixels = try PixelBuffer(
            width: layer.pixels.width,
            height: layer.pixels.height,
            rgba: rgba
        )
    }
}
