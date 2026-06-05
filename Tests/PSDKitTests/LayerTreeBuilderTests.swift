import XCTest
@testable import PSDKit

final class LayerTreeBuilderTests: XCTestCase {
    func testReadsSiblingMixedGroup() throws {
        let bg = try makePixelRecord(name: "BG")
        let a1 = try makePixelRecord(name: "A-1")
        let a2 = try makePixelRecord(name: "A-2")
        let fg = try makePixelRecord(name: "FG")
        let records = [
            bg,
            makeSectionRecord(name: "Group A", kind: .bounding),
            a1,
            a2,
            makeSectionRecord(name: "Group A", kind: .openFolder),
            fg,
        ]

        let doc = try makeDocument(records: records)
        XCTAssertEqual(doc.root.children.map(\.name), ["BG", "Group A", "FG"])
        let group = try XCTUnwrap(doc.root.children[1] as? GroupLayer)
        XCTAssertEqual(group.children.map(\.name), ["A-1", "A-2"])
        XCTAssertIdentical(group.parent, doc.root)
        XCTAssertIdentical((group.children[0] as? PixelLayer)?.parent, group)
        XCTAssertIdentical((group.children[1] as? PixelLayer)?.parent, group)
    }

    func testReadsEmptyGroup() throws {
        let records = [
            try makePixelRecord(name: "BG"),
            makeSectionRecord(name: "Empty Group", kind: .bounding),
            makeSectionRecord(name: "Empty Group", kind: .openFolder),
            try makePixelRecord(name: "FG"),
        ]

        let doc = try makeDocument(records: records)
        XCTAssertEqual(doc.root.children.map(\.name), ["BG", "Empty Group", "FG"])
        let group = try XCTUnwrap(doc.root.children[1] as? GroupLayer)
        XCTAssertTrue(group.children.isEmpty)
    }

    func testRejectsFolderEndWithoutStart() throws {
        let records = [
            try makePixelRecord(name: "BG"),
            makeSectionRecord(name: "Orphan", kind: .openFolder),
        ]

        XCTAssertThrowsError(try makeDocument(records: records)) { error in
            assertCorruptStructure(error)
        }
    }

    func testRejectsUnclosedGroup() throws {
        let records = [
            try makePixelRecord(name: "BG"),
            makeSectionRecord(name: "Group A", kind: .bounding),
            try makePixelRecord(name: "A-1"),
        ]

        XCTAssertThrowsError(try makeDocument(records: records)) { error in
            assertCorruptStructure(error)
        }
    }

    func testRejectsMismatchedGroupNames() throws {
        let records = [
            makeSectionRecord(name: "Group A", kind: .bounding),
            makeSectionRecord(name: "Group B", kind: .openFolder),
        ]

        XCTAssertThrowsError(try makeDocument(records: records)) { error in
            assertCorruptStructure(error)
        }
    }

    func testFlatFixtureRootChildrenHaveParent() throws {
        let url = try fixtureURL("two-layers.psd")
        let doc = try PSDDocument.load(url: url)
        for child in doc.root.children {
            XCTAssertIdentical(child.parent, doc.root)
        }
        XCTAssertEqual(doc.root.children.count, 2)
    }

    func testReadsNestedTwoLevelGroup() throws {
        let records = [
            try makePixelRecord(name: "BG"),
            makeSectionRecord(name: "Outer", kind: .bounding),
            makeSectionRecord(name: "Inner", kind: .bounding),
            try makePixelRecord(name: "A-1"),
            try makePixelRecord(name: "A-2"),
            makeSectionRecord(name: "Inner", kind: .openFolder),
            try makePixelRecord(name: "Outer-Leaf"),
            makeSectionRecord(name: "Outer", kind: .openFolder),
            try makePixelRecord(name: "FG"),
        ]

        let doc = try makeDocument(records: records)
        XCTAssertEqual(doc.root.children.map(\.name), ["BG", "Outer", "FG"])

        let outer = try XCTUnwrap(doc.root.children[1] as? GroupLayer)
        XCTAssertEqual(outer.children.map(\.name), ["Inner", "Outer-Leaf"])
        XCTAssertIdentical(outer.parent, doc.root)

        let inner = try XCTUnwrap(outer.children[0] as? GroupLayer)
        XCTAssertEqual(inner.children.map(\.name), ["A-1", "A-2"])
        XCTAssertIdentical(inner.parent, outer)

        let a1 = try XCTUnwrap(inner.children[0] as? PixelLayer)
        let a2 = try XCTUnwrap(inner.children[1] as? PixelLayer)
        let outerLeaf = try XCTUnwrap(outer.children[1] as? PixelLayer)
        XCTAssertIdentical(a1.parent, inner)
        XCTAssertIdentical(a2.parent, inner)
        XCTAssertIdentical(outerLeaf.parent, outer)
    }

    func testReadsNestedThreeLevelGroup() throws {
        let records = [
            try makePixelRecord(name: "L0"),
            makeSectionRecord(name: "G1", kind: .bounding),
            makeSectionRecord(name: "G2", kind: .bounding),
            makeSectionRecord(name: "G3", kind: .bounding),
            try makePixelRecord(name: "Deep"),
            makeSectionRecord(name: "G3", kind: .openFolder),
            try makePixelRecord(name: "Mid"),
            makeSectionRecord(name: "G2", kind: .openFolder),
            try makePixelRecord(name: "Top-in-G1"),
            makeSectionRecord(name: "G1", kind: .openFolder),
            try makePixelRecord(name: "L-top"),
        ]

        let doc = try makeDocument(records: records)
        XCTAssertEqual(doc.root.children.map(\.name), ["L0", "G1", "L-top"])

        let g1 = try XCTUnwrap(doc.root.children[1] as? GroupLayer)
        XCTAssertEqual(g1.children.map(\.name), ["G2", "Top-in-G1"])
        XCTAssertIdentical(g1.parent, doc.root)

        let g2 = try XCTUnwrap(g1.children[0] as? GroupLayer)
        XCTAssertEqual(g2.children.map(\.name), ["G3", "Mid"])
        XCTAssertIdentical(g2.parent, g1)

        let g3 = try XCTUnwrap(g2.children[0] as? GroupLayer)
        XCTAssertEqual(g3.children.map(\.name), ["Deep"])
        XCTAssertIdentical(g3.parent, g2)

        let deep = try XCTUnwrap(g3.children[0] as? PixelLayer)
        let mid = try XCTUnwrap(g2.children[1] as? PixelLayer)
        let topInG1 = try XCTUnwrap(g1.children[1] as? PixelLayer)
        XCTAssertIdentical(deep.parent, g3)
        XCTAssertIdentical(mid.parent, g2)
        XCTAssertIdentical(topInG1.parent, g1)
    }

    func testClosedFolderClosesGroupWithoutChangingTreeSemantics() throws {
        let records = [
            try makePixelRecord(name: "BG"),
            makeSectionRecord(name: "Group A", kind: .bounding),
            try makePixelRecord(name: "A-1"),
            try makePixelRecord(name: "A-2"),
            makeSectionRecord(name: "Group A", kind: .closedFolder),
            try makePixelRecord(name: "FG"),
        ]

        let doc = try makeDocument(records: records)
        XCTAssertEqual(doc.root.children.map(\.name), ["BG", "Group A", "FG"])
        let group = try XCTUnwrap(doc.root.children[1] as? GroupLayer)
        XCTAssertEqual(group.children.map(\.name), ["A-1", "A-2"])
        XCTAssertIdentical(group.parent, doc.root)
        XCTAssertIdentical((group.children[0] as? PixelLayer)?.parent, group)
        XCTAssertIdentical((group.children[1] as? PixelLayer)?.parent, group)
    }

    func testReadsNestedMixedOpenAndClosedFolders() throws {
        let records = [
            try makePixelRecord(name: "BG"),
            makeSectionRecord(name: "Outer", kind: .bounding),
            makeSectionRecord(name: "Inner", kind: .bounding),
            try makePixelRecord(name: "Inner-1"),
            makeSectionRecord(name: "Inner", kind: .closedFolder),
            try makePixelRecord(name: "Outer-1"),
            makeSectionRecord(name: "Outer", kind: .openFolder),
            try makePixelRecord(name: "FG"),
        ]

        let doc = try makeDocument(records: records)
        XCTAssertEqual(doc.root.children.map(\.name), ["BG", "Outer", "FG"])

        let outer = try XCTUnwrap(doc.root.children[1] as? GroupLayer)
        XCTAssertEqual(outer.children.map(\.name), ["Inner", "Outer-1"])
        XCTAssertIdentical(outer.parent, doc.root)

        let inner = try XCTUnwrap(outer.children[0] as? GroupLayer)
        XCTAssertEqual(inner.children.map(\.name), ["Inner-1"])
        XCTAssertIdentical(inner.parent, outer)
        XCTAssertIdentical((inner.children[0] as? PixelLayer)?.parent, inner)
        XCTAssertIdentical((outer.children[1] as? PixelLayer)?.parent, outer)
    }

    // MARK: - Helpers

    private func makeDocument(records: [LayerRecord]) throws -> PSDDocument {
        let file = PSDFile(
            header: FileHeader.newRGB(width: 8, height: 8, channels: 3),
            colorModeData: Data(),
            imageResources: Data(),
            layerAndMask: LayerAndMaskInformation(
                layerInfo: LayerInfo(layerCount: Int16(records.count), layers: records),
                globalMaskRaw: Data(),
                taggedBlocksRaw: Data()
            ),
            imageData: ImageDataSection(compression: .raw, data: Data()),
            sourceData: Data()
        )
        return try DocumentBuilder.makeDocument(from: file)
    }

    private func makePixelRecord(name: String) throws -> LayerRecord {
        let pixel = try PixelLayer(
            name: name,
            frame: PSDRect(left: 0, top: 0, right: 2, bottom: 2),
            pixels: PixelBuffer(width: 2, height: 2, rgba: Data(repeating: 255, count: 16))
        )
        return try LayerRecordFactory.makeRecord(from: pixel)
    }

    private func makeSectionRecord(name: String, kind: LayerExtra.SectionDividerKind) -> LayerRecord {
        let type: UInt32
        switch kind {
        case .bounding: type = 3
        case .openFolder: type = 1
        case .closedFolder: type = 2
        }
        let payload = Data([
            UInt8(type >> 24), UInt8(type >> 16), UInt8(type >> 8), UInt8(type),
        ])
        return LayerRecord(
            top: 0,
            left: 0,
            bottom: 0,
            right: 0,
            channelInfo: [],
            blendMode: .passThrough,
            opacity: 255,
            clipping: .base,
            flags: LayerFlags(
                transparencyProtected: false,
                visible: true,
                pixelDataIrrelevant: false
            ),
            name: name,
            extraData: makeLayerExtra(name: name, taggedBlocks: [("lsct", payload)]),
            channelData: [:],
            channelCompressions: [:]
        )
    }

    private func makeLayerExtra(name: String, taggedBlocks: [(key: String, payload: Data)] = []) -> Data {
        var w = BinaryWriter()
        w.writeUInt32(0)
        w.writeUInt32(0)
        w.writePascalString(name, padding: 4)
        for block in taggedBlocks {
            w.write(encodeTaggedBlock(key: block.key, payload: block.payload))
        }
        w.pad(to: 2)
        return w.data
    }

    private func encodeTaggedBlock(key: String, payload: Data) -> Data {
        var w = BinaryWriter()
        w.writeFixedString("8BIM", length: 4)
        w.writeFixedString(key, length: 4)
        w.writeUInt32(UInt32(payload.count))
        w.write(payload)
        if payload.count % 2 != 0 { w.writeUInt8(0) }
        return w.data
    }

    private func assertCorruptStructure(_ error: Error, file: StaticString = #filePath, line: UInt = #line) {
        guard case .corruptStructure? = error as? PSDError else {
            XCTFail("expected corruptStructure, got \(error)", file: file, line: line)
            return
        }
    }

    private func fixtureURL(_ name: String) throws -> URL {
        let base = name.replacingOccurrences(of: ".psd", with: "")
        guard let url = Bundle.module.url(forResource: base, withExtension: "psd", subdirectory: "Fixtures") else {
            throw XCTSkip("Missing fixture \(name)")
        }
        return url
    }
}
