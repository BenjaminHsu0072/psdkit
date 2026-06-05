import XCTest
@testable import PSDKit

final class BlendModeTests: XCTestCase {
    private var manifest: GoldenManifest!

    override func setUpWithError() throws {
        manifest = try GoldenLoader.loadManifest()
    }

    func testMultiplyFourCCMapping() {
        XCTAssertEqual(BlendMode(fourCC: "mul "), .multiply)
        XCTAssertEqual(BlendMode.multiply.fourCC, "mul ")
    }

    func testAddFourCCMapping() {
        XCTAssertEqual(BlendMode(fourCC: "lddg"), .add)
        XCTAssertEqual(BlendMode.add.fourCC, "lddg")
    }

    func testReadsMultiplyFromPSD() throws {
        let doc = try loadFirstLayerBlendPatched(from: "norm", to: "mul ")
        let pixel = try XCTUnwrap(doc.root.children.first as? PixelLayer)
        XCTAssertEqual(pixel.blendMode, .multiply)
        assertEmptyCompatibilityReport(doc.compatibilityReport)
    }

    func testReadsAddFromPSD() throws {
        let doc = try loadFirstLayerBlendPatched(from: "norm", to: "lddg")
        let pixel = try XCTUnwrap(doc.root.children.first as? PixelLayer)
        XCTAssertEqual(pixel.blendMode, .add)
        assertEmptyCompatibilityReport(doc.compatibilityReport)
    }

    func testSemanticWritePreservesMultiply() throws {
        let data = try semanticData(blendMode: .multiply)
        let file = try PSDFile.read(data: data)
        let record = try XCTUnwrap(file.layerAndMask.layerInfo?.layers.first)
        XCTAssertEqual(record.blendMode, .multiply)
        XCTAssertTrue(data.contains(Data("8BIM".utf8) + Data("mul ".utf8)))
    }

    func testSemanticWritePreservesAdd() throws {
        let data = try semanticData(blendMode: .add)
        let file = try PSDFile.read(data: data)
        let record = try XCTUnwrap(file.layerAndMask.layerInfo?.layers.first)
        XCTAssertEqual(record.blendMode, .add)
        XCTAssertTrue(data.contains(Data("8BIM".utf8) + Data("lddg".utf8)))
    }

    func testPixelPassThroughStillReportsWarning() throws {
        let doc = try loadFirstLayerBlendPatched(from: "norm", to: "pass")
        let pixel = try XCTUnwrap(doc.root.children.first as? PixelLayer)
        XCTAssertEqual(pixel.blendMode, .normal)
        XCTAssertTrue(doc.compatibilityReport.hasLossyChanges)
        let blendIssues = doc.compatibilityReport.issues.filter { $0.kind == .unsupportedBlendMode }
        XCTAssertEqual(blendIssues.count, 1)
    }

    // MARK: - Helpers

    private func loadFirstLayerBlendPatched(from: String, to: String) throws -> PSDDocument {
        let entry = try requireSupportedFixture(tag: "single")
        var data = try Data(contentsOf: GoldenLoader.fixtureURL(for: entry))
        data = try replaceFirstLayerBlendKey(in: data, from: from, to: to)
        return try PSDDocument.load(data: data)
    }

    private func semanticData(blendMode: BlendMode) throws -> Data {
        let root = GroupLayer(name: "")
        let rgba = Data(repeating: 255, count: 8 * 8 * 4)
        let layer = try PSDDocument.makePixelLayer(
            name: "Blend",
            frame: PSDRect(left: 0, top: 0, right: 8, bottom: 8),
            rgba: rgba,
            blendMode: blendMode
        )
        root.append(layer)

        let file = PSDFile(
            header: FileHeader.newRGB(width: 8, height: 8, channels: 3),
            colorModeData: Data(),
            imageResources: Data(),
            layerAndMask: LayerAndMaskInformation(
                layerInfo: nil,
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
        return try doc.data(writeMode: .semantic)
    }

    private func requireSupportedFixture(tag: String) throws -> GoldenFixture {
        let subset = manifest.fixtures.filter { $0.tags.contains(tag) && $0.v1ReadSupported }
        guard let entry = subset.first else {
            XCTFail("No supported fixture tagged '\(tag)'")
            throw NSError(domain: "BlendModeTests", code: 1)
        }
        return entry
    }

    private func assertEmptyCompatibilityReport(_ report: PSDCompatibilityReport) {
        XCTAssertTrue(report.issues.isEmpty)
        XCTAssertFalse(report.hasLossyChanges)
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
                domain: "BlendModeTests",
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
