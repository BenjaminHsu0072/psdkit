import XCTest
@testable import PSDKit

final class CompatibilityReportTests: XCTestCase {
    private var manifest: GoldenManifest!

    override func setUpWithError() throws {
        manifest = try GoldenLoader.loadManifest()
    }

    func testSupportedSubsetHasEmptyReportViaURL() throws {
        let entry = try requireSupportedFixture(tag: "single")
        let url = GoldenLoader.fixtureURL(for: entry)
        let doc = try PSDDocument.load(url: url)
        assertEmptyCompatibilityReport(doc.compatibilityReport)
    }

    func testSupportedSubsetHasEmptyReportViaData() throws {
        let entry = try requireSupportedFixture(tag: "single")
        let url = GoldenLoader.fixtureURL(for: entry)
        let data = try Data(contentsOf: url)
        let doc = try PSDDocument.load(data: data)
        assertEmptyCompatibilityReport(doc.compatibilityReport)
    }

    func testCreateDocumentHasEmptyReport() throws {
        let doc = try PSDDocument.create(width: 8, height: 8)
        assertEmptyCompatibilityReport(doc.compatibilityReport)
    }

    func testMaskReportsWarning() throws {
        let entry = try requireSupportedFixture(tag: "single")
        var data = try Data(contentsOf: GoldenLoader.fixtureURL(for: entry))
        data = try setFirstLayerMaskFlagsByte(in: data, flags: 0x08)

        let doc = try PSDDocument.load(data: data)
        let pixel = try XCTUnwrap(doc.root.children.first as? PixelLayer)
        XCTAssertEqual(pixel.name, entry.layers[0].name)
        XCTAssertGreaterThan(pixel.frame.width, 0)

        XCTAssertTrue(doc.compatibilityReport.hasLossyChanges)
        let maskIssues = doc.compatibilityReport.issues.filter { $0.kind == .unsupportedMask }
        XCTAssertEqual(maskIssues.count, 1)
        XCTAssertEqual(maskIssues[0].severity, .warning)
        XCTAssertEqual(maskIssues[0].layerName, entry.layers[0].name)
        XCTAssertEqual(maskIssues[0].message, "Layer mask is not supported; mask was ignored.")
    }

    func testLayerEffectsReportWarning() throws {
        let entry = try requireSupportedFixture(tag: "single")
        var data = try Data(contentsOf: GoldenLoader.fixtureURL(for: entry))
        data = try injectFirstLayerTaggedBlock(in: data, key: "lfx2", payload: Data(repeating: 0, count: 8))

        let doc = try PSDDocument.load(data: data)
        let pixel = try XCTUnwrap(doc.root.children.first as? PixelLayer)
        XCTAssertEqual(pixel.name, entry.layers[0].name)
        XCTAssertGreaterThan(pixel.frame.width, 0)

        XCTAssertTrue(doc.compatibilityReport.hasLossyChanges)
        let effectIssues = doc.compatibilityReport.issues.filter { $0.kind == .unsupportedLayerEffect }
        XCTAssertEqual(effectIssues.count, 1)
        XCTAssertEqual(effectIssues[0].severity, .warning)
        XCTAssertEqual(effectIssues[0].layerName, entry.layers[0].name)
        XCTAssertEqual(
            effectIssues[0].message,
            "Layer effects are not supported; effects were ignored."
        )
    }

    /// Patches the first layer-record blend key in a golden PSD (`8BIM` + fourCC).
    func testMissingRGBChannelDataReportsDroppedLayer() throws {
        let entry = try requireSupportedFixture(tag: "single")
        var file = try PSDFile.read(data: Data(contentsOf: GoldenLoader.fixtureURL(for: entry)))
        guard var layerInfo = file.layerAndMask.layerInfo else {
            XCTFail("expected layer info")
            return
        }
        var layer = layerInfo.layers[0]
        layer.channelData.removeValue(forKey: ChannelID.red.rawValue)
        layer.channelData.removeValue(forKey: ChannelID.green.rawValue)
        layer.channelData.removeValue(forKey: ChannelID.blue.rawValue)
        layer.channelInfo = layer.channelInfo.map { info in
            if info.id >= 0 && info.id <= 2 {
                return ChannelInfo(id: info.id, length: 0)
            }
            return info
        }
        layerInfo.layers[0] = layer
        file.layerAndMask.layerInfo = layerInfo

        let doc = try DocumentBuilder.makeDocument(from: file)
        XCTAssertTrue(doc.root.children.isEmpty)

        XCTAssertTrue(doc.compatibilityReport.hasLossyChanges)
        let kindIssues = doc.compatibilityReport.issues.filter { $0.kind == .unsupportedLayerKind }
        let droppedIssues = doc.compatibilityReport.issues.filter { $0.kind == .droppedLayer }
        XCTAssertEqual(kindIssues.count, 1)
        XCTAssertEqual(droppedIssues.count, 1)
        XCTAssertEqual(kindIssues[0].severity, .warning)
        XCTAssertEqual(droppedIssues[0].severity, .warning)
        XCTAssertEqual(kindIssues[0].layerName, entry.layers[0].name)
        XCTAssertEqual(droppedIssues[0].layerName, entry.layers[0].name)
        XCTAssertEqual(
            kindIssues[0].message,
            "This layer type is not supported; layer was dropped."
        )
        XCTAssertEqual(
            droppedIssues[0].message,
            "Layer was omitted from the editable document."
        )
    }

    func testSmartObjectTaggedBlockReportsDropped() throws {
        let entry = try requireSupportedFixture(tag: "single")
        for key in ["SoLd", "PlLd"] {
            var data = try Data(contentsOf: GoldenLoader.fixtureURL(for: entry))
            data = try injectFirstLayerTaggedBlock(in: data, key: key, payload: Data(repeating: 0, count: 16))

            let doc = try PSDDocument.load(data: data)
            XCTAssertTrue(doc.root.children.isEmpty, "expected dropped layer for \(key)")

            XCTAssertTrue(doc.compatibilityReport.hasLossyChanges)
            let kindIssues = doc.compatibilityReport.issues.filter { $0.kind == .unsupportedLayerKind }
            let droppedIssues = doc.compatibilityReport.issues.filter { $0.kind == .droppedLayer }
            XCTAssertEqual(kindIssues.count, 1, key)
            XCTAssertEqual(droppedIssues.count, 1, key)
            XCTAssertEqual(kindIssues[0].layerName, entry.layers[0].name, key)
            XCTAssertEqual(
                kindIssues[0].message,
                "Smart Objects are not supported; layer was dropped.",
                key
            )
            XCTAssertEqual(
                droppedIssues[0].message,
                "Layer was omitted from the editable document.",
                key
            )
        }
    }

    func testTextLayerTaggedBlockReportsDropped() throws {
        let entry = try requireSupportedFixture(tag: "single")
        var data = try Data(contentsOf: GoldenLoader.fixtureURL(for: entry))
        data = try injectFirstLayerTaggedBlock(in: data, key: "TySh", payload: Data(repeating: 0, count: 16))

        let doc = try PSDDocument.load(data: data)
        XCTAssertTrue(doc.root.children.isEmpty)

        XCTAssertTrue(doc.compatibilityReport.hasLossyChanges)
        let kindIssues = doc.compatibilityReport.issues.filter { $0.kind == .unsupportedLayerKind }
        let droppedIssues = doc.compatibilityReport.issues.filter { $0.kind == .droppedLayer }
        XCTAssertEqual(kindIssues.count, 1)
        XCTAssertEqual(droppedIssues.count, 1)
        XCTAssertEqual(kindIssues[0].layerName, entry.layers[0].name)
        XCTAssertEqual(
            kindIssues[0].message,
            "Text layers are not supported; layer was dropped."
        )
        XCTAssertEqual(
            droppedIssues[0].message,
            "Layer was omitted from the editable document."
        )
    }

    func testZeroSizeTextLayerStillReportsDropped() throws {
        var file = try PSDFile.read(data: Data(contentsOf: GoldenLoader.fixtureURL(
            for: try requireSupportedFixture(tag: "single")
        )))
        guard var layerInfo = file.layerAndMask.layerInfo else {
            XCTFail("expected layer info")
            return
        }
        var layer = layerInfo.layers[0]
        layer.top = 0
        layer.left = 0
        layer.bottom = 0
        layer.right = 0
        layer.name = "ZeroText"
        layer.extraData = makeLayerExtra(
            name: "ZeroText",
            taggedBlocks: [("TySh", Data(repeating: 0, count: 16))]
        )
        layerInfo.layers[0] = layer
        file.layerAndMask.layerInfo = layerInfo

        let doc = try DocumentBuilder.makeDocument(from: file)
        XCTAssertTrue(doc.root.children.isEmpty)
        XCTAssertTrue(doc.compatibilityReport.hasLossyChanges)
        XCTAssertEqual(
            doc.compatibilityReport.issues.filter { $0.kind == .unsupportedLayerKind }.count,
            1
        )
        XCTAssertEqual(
            doc.compatibilityReport.issues.filter { $0.kind == .droppedLayer }.count,
            1
        )
        XCTAssertEqual(
            doc.compatibilityReport.issues.first { $0.kind == .unsupportedLayerKind }?.layerName,
            "ZeroText"
        )
    }

    func testZeroSizeAdjustmentLayerStillReportsDropped() throws {
        var file = try PSDFile.read(data: Data(contentsOf: GoldenLoader.fixtureURL(
            for: try requireSupportedFixture(tag: "single")
        )))
        guard var layerInfo = file.layerAndMask.layerInfo else {
            XCTFail("expected layer info")
            return
        }
        var layer = layerInfo.layers[0]
        layer.top = 0
        layer.left = 0
        layer.bottom = 0
        layer.right = 0
        layer.name = "Levels"
        layer.extraData = makeLayerExtra(
            name: "Levels",
            taggedBlocks: [("levl", Data(repeating: 0, count: 8))]
        )
        layerInfo.layers[0] = layer
        file.layerAndMask.layerInfo = layerInfo

        let doc = try DocumentBuilder.makeDocument(from: file)
        XCTAssertTrue(doc.root.children.isEmpty)
        XCTAssertTrue(doc.compatibilityReport.hasLossyChanges)
        let kindIssue = try XCTUnwrap(
            doc.compatibilityReport.issues.first { $0.kind == .unsupportedLayerKind }
        )
        XCTAssertEqual(kindIssue.layerName, "Levels")
        XCTAssertEqual(
            kindIssue.message,
            "Adjustment layers are not supported; layer was dropped."
        )
        XCTAssertEqual(doc.compatibilityReport.issues.filter { $0.kind == .droppedLayer }.count, 1)
    }

    func testUnpairedSectionDividerThrowsCorruptStructure() throws {
        let entry = try requireSupportedFixture(tag: "single")
        var file = try PSDFile.read(data: Data(contentsOf: GoldenLoader.fixtureURL(for: entry)))
        guard var layerInfo = file.layerAndMask.layerInfo else {
            XCTFail("expected layer info")
            return
        }
        let divider = LayerRecord(
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
            name: "Group",
            extraData: makeLayerExtra(
                name: "Group",
                taggedBlocks: [("lsct", Data([0, 0, 0, 1]))]
            ),
            channelData: [:],
            channelCompressions: [:]
        )
        layerInfo.layers.append(divider)
        layerInfo.layerCount = Int16(layerInfo.layers.count)
        file.layerAndMask.layerInfo = layerInfo

        XCTAssertThrowsError(try DocumentBuilder.makeDocument(from: file)) { error in
            guard case .corruptStructure? = error as? PSDError else {
                XCTFail("expected corruptStructure, got \(error)")
                return
            }
        }
    }

    func testUnsupportedBlendModeReportsWarning() throws {
        let entry = try requireSupportedFixture(tag: "single")
        let baseURL = GoldenLoader.fixtureURL(for: entry)
        var data = try Data(contentsOf: baseURL)
        data = try replaceFirstLayerBlendKey(in: data, from: "norm", to: "scrn")

        let doc = try PSDDocument.load(data: data)
        let pixel = try XCTUnwrap(doc.root.children.first as? PixelLayer)
        XCTAssertEqual(pixel.blendMode, .normal)
        XCTAssertEqual(pixel.name, entry.layers[0].name)

        XCTAssertTrue(doc.compatibilityReport.hasLossyChanges)
        let blendIssues = doc.compatibilityReport.issues.filter { $0.kind == .unsupportedBlendMode }
        XCTAssertEqual(blendIssues.count, 1)
        XCTAssertEqual(blendIssues[0].severity, .warning)
        XCTAssertEqual(blendIssues[0].layerName, entry.layers[0].name)
        XCTAssertEqual(
            blendIssues[0].message,
            "Unsupported blend mode; layer was imported as Normal."
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
        precondition(key.count == 4)
        var w = BinaryWriter()
        w.writeFixedString("8BIM", length: 4)
        w.writeFixedString(key, length: 4)
        w.writeUInt32(UInt32(payload.count))
        w.write(payload)
        if payload.count % 2 != 0 { w.writeUInt8(0) }
        return w.data
    }

    private func requireSupportedFixture(tag: String) throws -> GoldenFixture {
        let subset = manifest.fixtures.filter { $0.tags.contains(tag) && $0.v1ReadSupported }
        guard let entry = subset.first else {
            XCTFail("No supported fixture tagged '\(tag)'")
            throw NSError(domain: "CompatibilityReportTests", code: 1)
        }
        return entry
    }

    private func assertEmptyCompatibilityReport(_ report: PSDCompatibilityReport) {
        XCTAssertTrue(report.issues.isEmpty)
        XCTAssertFalse(report.hasLossyChanges)
    }

    /// Sets the 20-byte layer mask flags byte (bit 3/4 indicate a real user mask).
    private func setFirstLayerMaskFlagsByte(in data: Data, flags: UInt8) throws -> Data {
        let maskBody = Data([
            0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 8, 0, 0, 0, 8, 0, 0, 0, 0,
        ])
        var needle = Data()
        needle.append(contentsOf: [0, 0, 0, 20])
        needle.append(maskBody)
        guard let range = data.range(of: needle) else {
            throw NSError(
                domain: "CompatibilityReportTests",
                code: 3,
                userInfo: [NSLocalizedDescriptionKey: "first layer mask stub not found"]
            )
        }
        var mutated = data
        let flagsIndex = range.upperBound - 3
        mutated[flagsIndex] = flags
        return mutated
    }

    /// Replaces blend-range bytes after the mask with empty blend + original Pascal name + tagged block.
    private func injectFirstLayerTaggedBlock(
        in data: Data,
        key: String,
        payload: Data
    ) throws -> Data {
        precondition(key.count == 4)
        let extraStart = try firstLayerExtraStart(in: data)
        let extraLen = Int(data.readUInt32BE(at: extraStart - 4))
        let maskLen = Int(data.readUInt32BE(at: extraStart))
        let tailStart = extraStart + 4 + maskLen
        let tailLen = extraLen - (4 + maskLen)
        guard tailLen > 0, tailStart + tailLen <= data.count else {
            throw NSError(
                domain: "CompatibilityReportTests",
                code: 5,
                userInfo: [NSLocalizedDescriptionKey: "unexpected first layer extra layout"]
            )
        }

        let tail = Data(data[tailStart ..< tailStart + tailLen])
        var offset = 0
        let blendLen = Int(tail.readUInt32BE(at: offset))
        offset += 4 + blendLen
        guard offset < tail.count else {
            throw NSError(
                domain: "CompatibilityReportTests",
                code: 7,
                userInfo: [NSLocalizedDescriptionKey: "missing pascal name in layer extra"]
            )
        }
        let pascalLen = Int(tail[offset])
        let pascalBytes = 1 + pascalLen
        let pascalPadded = (pascalBytes + 3) & ~3
        guard offset + pascalPadded <= tail.count else {
            throw NSError(
                domain: "CompatibilityReportTests",
                code: 8,
                userInfo: [NSLocalizedDescriptionKey: "invalid pascal name padding"]
            )
        }
        let pascal = tail[offset ..< offset + pascalPadded]

        var block = Data("8BIM".utf8)
        block.append(contentsOf: key.utf8)
        var lengthBE = UInt32(payload.count).bigEndian
        block.append(Data(bytes: &lengthBE, count: 4))
        block.append(payload)
        if payload.count % 2 != 0 { block.append(0) }

        var replacement = Data()
        var zeroBlend = UInt32(0).bigEndian
        replacement.append(Data(bytes: &zeroBlend, count: 4))
        replacement.append(pascal)
        replacement.append(block)
        guard replacement.count <= tailLen else {
            throw NSError(
                domain: "CompatibilityReportTests",
                code: 6,
                userInfo: [NSLocalizedDescriptionKey: "effect block does not fit layer extra tail"]
            )
        }
        if replacement.count < tailLen {
            replacement.append(Data(repeating: 0, count: tailLen - replacement.count))
        }

        var mutated = data
        mutated.replaceSubrange(tailStart ..< tailStart + tailLen, with: replacement)
        return mutated
    }

    private func firstLayerExtraStart(in data: Data) throws -> Int {
        let maskBody = Data([
            0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 8, 0, 0, 0, 8, 0, 0, 0, 0,
        ])
        var needle = Data()
        needle.append(contentsOf: [0, 0, 0, 20])
        needle.append(maskBody)
        guard let range = data.range(of: needle) else {
            throw NSError(
                domain: "CompatibilityReportTests",
                code: 4,
                userInfo: [NSLocalizedDescriptionKey: "first layer extra not found"]
            )
        }
        return range.lowerBound
    }

    private func replaceFirstLayerBlendKey(
        in data: Data,
        from: String,
        to: String
    ) throws -> Data {
        precondition(from.count == 4 && to.count == 4)
        var needle = Data("8BIM".utf8)
        needle.append(contentsOf: from.utf8)
        guard let range = data.range(of: needle) else {
            throw NSError(
                domain: "CompatibilityReportTests",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "blend key signature \(from) not found"]
            )
        }
        var replacement = Data("8BIM".utf8)
        replacement.append(contentsOf: to.utf8)
        var mutated = data
        mutated.replaceSubrange(range, with: replacement)
        return mutated
    }
}

private extension Data {
    func readUInt32BE(at offset: Int) -> UInt32 {
        precondition(offset + 4 <= count)
        return UInt32(self[offset]) << 24 | UInt32(self[offset + 1]) << 16
            | UInt32(self[offset + 2]) << 8 | UInt32(self[offset + 3])
    }
}

