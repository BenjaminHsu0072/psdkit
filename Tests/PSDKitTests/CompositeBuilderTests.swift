import XCTest
@testable import PSDKit

final class CompositeBuilderTests: XCTestCase {
    private let canvasSize = PSDSize(width: 1, height: 1)

    // MARK: - Blend mode compositing (hand-calculated 8-bit)
    func testCompositeSingleRedLayer() throws {
        let url = try fixtureURL("single-rle-8x8.psd")
        let doc = try PSDDocument.load(url: url)
        let layers = doc.root.children.compactMap { $0 as? PixelLayer }
        let rgba = CompositeBuilder.compositeRGBA(canvasSize: doc.canvasSize, layers: layers)
        XCTAssertEqual(rgba[0], 255)
        XCTAssertEqual(rgba[1], 0)
        XCTAssertEqual(rgba[2], 0)
    }

    func testSemanticWriteRebuildsCompositeImageData() throws {
        let url = try fixtureURL("single-rle-8x8.psd")
        let doc = try PSDDocument.load(url: url)
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent("composite-semantic.psd")
        try doc.save(to: temp, writeMode: .semantic)
        let reloaded = try PSDFile.read(data: Data(contentsOf: temp))
        XCTAssertEqual(reloaded.imageData.compression, .raw)
        let planeSize = 8 * 8
        XCTAssertEqual(reloaded.imageData.data.count, planeSize * 3)
        XCTAssertEqual(reloaded.imageData.data[0], 255)
        XCTAssertEqual(reloaded.imageData.data[planeSize], 0)
        XCTAssertEqual(reloaded.imageData.data[planeSize * 2], 0)
        try? FileManager.default.removeItem(at: temp)
    }

    func testMultiplyBlendsChannels() throws {
        let bottom = try solidPixelLayer(r: 128, g: 64, b: 32, blendMode: .normal)
        let top = try solidPixelLayer(r: 200, g: 100, b: 50, blendMode: .multiply)
        let rgba = CompositeBuilder.compositeRGBA(
            canvasSize: canvasSize,
            layers: [bottom, top]
        )
        // (src*dst+127)/255: R (200*128)=100, G (100*64)=25, B (50*32)=6
        XCTAssertEqual(rgba[0], 100)
        XCTAssertEqual(rgba[1], 25)
        XCTAssertEqual(rgba[2], 6)
        XCTAssertEqual(rgba[3], 255)
    }

    func testAddSaturatesChannels() throws {
        let bottom = try solidPixelLayer(r: 200, g: 100, b: 50, blendMode: .normal)
        let top = try solidPixelLayer(r: 100, g: 200, b: 250, blendMode: .add)
        let rgba = CompositeBuilder.compositeRGBA(
            canvasSize: canvasSize,
            layers: [bottom, top]
        )
        XCTAssertEqual(rgba[0], 255)
        XCTAssertEqual(rgba[1], 255)
        XCTAssertEqual(rgba[2], 255)
    }

    func testOpacityWithMultiply() throws {
        let bottom = try solidPixelLayer(r: 100, g: 100, b: 100, blendMode: .normal)
        let top = try solidPixelLayer(
            r: 200, g: 0, b: 0,
            blendMode: .multiply,
            opacity: 128
        )
        let rgba = CompositeBuilder.compositeRGBA(
            canvasSize: canvasSize,
            layers: [bottom, top]
        )
        // blend R = (200*100+127)/255 = 78; srcA = 128/255 → round(78*128/255 + 100*127/255) = 89
        // G/B multiply kernel is 0, then 50% over bottom 100 → 50
        XCTAssertEqual(rgba[0], 89)
        XCTAssertEqual(rgba[1], 50)
        XCTAssertEqual(rgba[2], 50)
    }

    func testPerPixelAlphaWithAdd() throws {
        let bottom = try solidPixelLayer(r: 50, g: 50, b: 50, alpha: 255, blendMode: .normal)
        let top = try solidPixelLayer(
            r: 200, g: 200, b: 200,
            alpha: 128,
            blendMode: .add
        )
        let rgba = CompositeBuilder.compositeRGBA(
            canvasSize: canvasSize,
            layers: [bottom, top]
        )
        // blend = 250; srcA = 128/255 → round(250*128/255 + 50*127/255) = 150
        XCTAssertEqual(rgba[0], 150)
        XCTAssertEqual(rgba[1], 150)
        XCTAssertEqual(rgba[2], 150)
    }

    func testSemanticWriteMultiplyCompositeDiffersFromNormal() throws {
        let multiplyComposite = try compositeRedChannel(
            topBlendMode: .multiply,
            writeMode: .semantic
        )
        let normalComposite = try compositeRedChannel(
            topBlendMode: .normal,
            writeMode: .semantic
        )
        XCTAssertEqual(multiplyComposite, 89)
        XCTAssertEqual(normalComposite, 200)
        XCTAssertNotEqual(multiplyComposite, normalComposite)
    }

    func testSemanticWriteAddCompositeDiffersFromNormal() throws {
        let addComposite = try compositeRedChannel(
            bottom: (200, 100, 50),
            top: (100, 200, 250),
            topBlendMode: .add,
            writeMode: .semantic
        )
        let normalComposite = try compositeRedChannel(
            bottom: (200, 100, 50),
            top: (100, 200, 250),
            topBlendMode: .normal,
            writeMode: .semantic
        )
        XCTAssertEqual(addComposite, 255)
        XCTAssertEqual(normalComposite, 100)
        XCTAssertNotEqual(addComposite, normalComposite)
    }

    func testOpacityChangeUpdatesComposite() throws {
        let url = try fixtureURL("single-rle-8x8.psd")
        let doc = try PSDDocument.load(url: url)
        guard let layer = doc.root.children.first as? PixelLayer else {
            XCTFail("missing layer")
            return
        }
        layer.opacity = 0
        doc.markContentModified()
        let data = try doc.data()
        let file = try PSDFile.read(data: data)
        // Full transparency → white background
        XCTAssertEqual(file.imageData.data[0], 255)
        XCTAssertEqual(file.imageData.data[1], 255)
        XCTAssertEqual(file.imageData.data[2], 255)
    }

    func testCompositePreviewIncludesNestedLayers() throws {
        let doc = try PSDDocument.makeMidtermStandardDocument()
        let preview = doc.compositePreviewRGBA()
        XCTAssertEqual(preview.count, doc.canvasSize.width * doc.canvasSize.height * 4)
        // Group A contains 2-level nested pixels; preview must not collapse to a flat-gray background.
        XCTAssertNotEqual(preview[0], 240)
        XCTAssertNotEqual(preview[1], 240)
        XCTAssertNotEqual(preview[2], 240)
    }

    func testCompositePreviewRespectsGroupVisibilityAndOpacity() throws {
        let doc = try PSDDocument.makeMidtermStandardDocument()
        guard let groupA = doc.root.children.first(where: { $0.name == "Group A" }) as? GroupLayer else {
            XCTFail("missing Group A")
            return
        }
        let baseline = doc.compositePreviewRGBA()
        groupA.isVisible = false
        let hiddenGroup = doc.compositePreviewRGBA()
        XCTAssertNotEqual(hiddenGroup, baseline)

        groupA.isVisible = true
        groupA.opacity = 128
        let halfOpacity = doc.compositePreviewRGBA()
        XCTAssertNotEqual(halfOpacity, baseline)
    }

    private func solidPixelLayer(
        r: UInt8,
        g: UInt8,
        b: UInt8,
        alpha: UInt8 = 255,
        blendMode: BlendMode = .normal,
        opacity: UInt8 = 255
    ) throws -> PixelLayer {
        try PixelLayer(
            name: "pixel",
            frame: PSDRect(left: 0, top: 0, right: 1, bottom: 1),
            pixels: PixelBuffer(width: 1, height: 1, rgba: Data([r, g, b, alpha])),
            opacity: opacity,
            blendMode: blendMode
        )
    }

    private func compositeRedChannel(
        bottom: (UInt8, UInt8, UInt8) = (100, 100, 100),
        top: (UInt8, UInt8, UInt8) = (200, 0, 0),
        topBlendMode: BlendMode,
        writeMode: PSDWriteMode
    ) throws -> UInt8 {
        let root = GroupLayer(name: "")
        root.append(
            try solidPixelLayer(
                r: bottom.0, g: bottom.1, b: bottom.2,
                blendMode: .normal
            )
        )
        root.append(
            try solidPixelLayer(
                r: top.0, g: top.1, b: top.2,
                blendMode: topBlendMode,
                opacity: topBlendMode == .multiply ? 128 : 255
            )
        )
        let file = PSDFile(
            header: FileHeader.newRGB(width: 1, height: 1, channels: 3),
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
        let data = try doc.data(writeMode: writeMode)
        let written = try PSDFile.read(data: data)
        return written.imageData.data[0]
    }

    private func fixtureURL(_ name: String) throws -> URL {
        let base = name.replacingOccurrences(of: ".psd", with: "")
        guard let url = Bundle.module.url(forResource: base, withExtension: "psd", subdirectory: "Fixtures") else {
            throw XCTSkip("Missing fixture \(name)")
        }
        return url
    }
}
