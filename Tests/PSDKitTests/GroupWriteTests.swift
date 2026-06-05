import XCTest
@testable import PSDKit

final class GroupWriteTests: XCTestCase {
    func testFlattensGroupToSectionDividerRecords() throws {
        let doc = try makeSiblingMixedDocument()
        let synced = try DocumentBuilder.syncRawFile(from: doc)
        let records = try XCTUnwrap(synced.layerAndMask.layerInfo?.layers)

        assertRecords(
            records,
            [
                ("BG", nil),
                ("Group A", .bounding),
                ("A-1", nil),
                ("A-2", nil),
                ("Group A", .openFolder),
                ("FG", nil),
            ]
        )
    }

    func testWritesEmptyGroupSectionDividerPair() throws {
        let root = GroupLayer(name: "")
        root.append(try makePixelLayer(name: "BG"))
        root.append(GroupLayer(name: "Empty Group"))
        root.append(try makePixelLayer(name: "FG"))

        let doc = try makeDocument(root: root)
        let synced = try DocumentBuilder.syncRawFile(from: doc)
        let records = try XCTUnwrap(synced.layerAndMask.layerInfo?.layers)

        assertRecords(
            records,
            [
                ("BG", nil),
                ("Empty Group", .bounding),
                ("Empty Group", .openFolder),
                ("FG", nil),
            ]
        )
    }

    func testNestedGroupRecordOrder() throws {
        let root = GroupLayer(name: "")
        root.append(try makePixelLayer(name: "BG"))

        let outer = GroupLayer(name: "Outer")
        let inner = GroupLayer(name: "Inner")
        inner.append(try makePixelLayer(name: "A-1"))
        inner.append(try makePixelLayer(name: "A-2"))
        outer.append(inner)
        outer.append(try makePixelLayer(name: "Outer-Leaf"))
        root.append(outer)
        root.append(try makePixelLayer(name: "FG"))

        let doc = try makeDocument(root: root)
        let synced = try DocumentBuilder.syncRawFile(from: doc)
        let records = try XCTUnwrap(synced.layerAndMask.layerInfo?.layers)

        assertRecords(
            records,
            [
                ("BG", nil),
                ("Outer", .bounding),
                ("Inner", .bounding),
                ("A-1", nil),
                ("A-2", nil),
                ("Inner", .openFolder),
                ("Outer-Leaf", nil),
                ("Outer", .openFolder),
                ("FG", nil),
            ]
        )
    }

    func testGroupSemanticRoundTripInMemory() throws {
        let doc = try makeSiblingMixedDocument()
        doc.markContentModified()
        let data = try doc.data(writeMode: .semantic)
        let reloaded = try PSDDocument.load(data: data)

        XCTAssertEqual(reloaded.root.children.map(\.name), ["BG", "Group A", "FG"])
        let group = try XCTUnwrap(reloaded.root.children[1] as? GroupLayer)
        XCTAssertEqual(group.children.map(\.name), ["A-1", "A-2"])
        XCTAssertIdentical(group.parent, reloaded.root)
    }

    func testFlatSemanticWriteStillMatchesGolden() throws {
        let manifest = try GoldenLoader.loadManifest()
        guard let entry = manifest.fixtures.first(where: { $0.id == "layer-offset-10x10-on-32" }) else {
            throw XCTSkip("fixture not in manifest")
        }
        let url = GoldenLoader.fixtureURL(for: entry)
        let doc = try PSDDocument.load(url: url)
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent("group-write-flat-semantic.psd")
        try doc.save(to: temp, writeMode: .semantic)
        let reloaded = try PSDDocument.load(url: temp)
        try GoldenAssertions.assertDocumentMatchesGolden(reloaded, entry: entry)
        try? FileManager.default.removeItem(at: temp)
    }

    // MARK: - Helpers

    private func makeSiblingMixedDocument() throws -> PSDDocument {
        let root = GroupLayer(name: "")
        root.append(try makePixelLayer(name: "BG"))

        let groupA = GroupLayer(name: "Group A")
        groupA.append(try makePixelLayer(name: "A-1"))
        groupA.append(try makePixelLayer(name: "A-2"))
        root.append(groupA)
        root.append(try makePixelLayer(name: "FG"))

        return try makeDocument(root: root)
    }

    private func makeDocument(root: GroupLayer) throws -> PSDDocument {
        let file = PSDFile(
            header: FileHeader.newRGB(width: 8, height: 8, channels: 3),
            colorModeData: Data(),
            imageResources: Data(),
            layerAndMask: LayerAndMaskInformation(
                layerInfo: LayerInfo(layerCount: 0, layers: []),
                globalMaskRaw: Data(),
                taggedBlocksRaw: Data()
            ),
            imageData: ImageDataSection(compression: .raw, data: Data()),
            sourceData: Data()
        )
        let doc = PSDDocument(
            canvasSize: file.header.canvasSize,
            colorMode: file.header.colorMode,
            root: root,
            rawFile: file
        )
        doc.markContentModified()
        return doc
    }

    private func makePixelLayer(name: String) throws -> PixelLayer {
        try PixelLayer(
            name: name,
            frame: PSDRect(left: 0, top: 0, right: 2, bottom: 2),
            pixels: PixelBuffer(width: 2, height: 2, rgba: Data(repeating: 255, count: 16))
        )
    }

    private func assertRecords(
        _ records: [LayerRecord],
        _ expected: [(name: String, section: LayerExtra.SectionDividerKind?)]
    ) {
        XCTAssertEqual(records.count, expected.count)
        for (record, item) in zip(records, expected) {
            XCTAssertEqual(record.name, item.name)
            XCTAssertEqual(LayerExtra.sectionDividerKind(for: record), item.section)
            if item.section == nil {
                XCTAssertGreaterThan(record.width, 0)
                XCTAssertGreaterThan(record.height, 0)
            } else {
                XCTAssertEqual(record.width, 0)
                XCTAssertEqual(record.height, 0)
            }
        }
    }
}
