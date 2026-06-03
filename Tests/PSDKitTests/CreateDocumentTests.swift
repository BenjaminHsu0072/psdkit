import XCTest
@testable import PSDKit

final class CreateDocumentTests: XCTestCase {
    func testCreateEmptyCanvasExportsBytes() throws {
        let doc = try PSDDocument.create(width: 16, height: 16)
        XCTAssertEqual(doc.canvasSize.width, 16)
        XCTAssertTrue(doc.root.children.isEmpty)
        let data = try doc.data()
        XCTAssertGreaterThan(data.count, 26)
        XCTAssertTrue(data.starts(with: Data("8BPS".utf8)))
    }

    func testCreateSingleLayerRoundTrip() throws {
        let size = PSDSize(width: 8, height: 8)
        let layer = try PSDDocument.makeSolidLayer(
            name: "Red",
            canvasSize: size,
            red: 255,
            green: 0,
            blue: 0,
            alpha: 255
        )
        let doc = try PSDDocument.create(canvasSize: size, layers: [layer])
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent("created-red.psd")
        try doc.save(to: temp)

        let loaded = try PSDDocument.load(url: temp)
        XCTAssertEqual(loaded.canvasSize, size)
        let pixels = loaded.root.children.compactMap { $0 as? PixelLayer }
        XCTAssertEqual(pixels.count, 1)
        XCTAssertEqual(pixels[0].name, "Red")
        XCTAssertEqual(pixels[0].pixels.rgba[0], 255)
        XCTAssertEqual(pixels[0].pixels.rgba[1], 0)
        XCTAssertEqual(pixels[0].pixels.rgba[2], 0)
        try? FileManager.default.removeItem(at: temp)
    }

    func testCreateMultiLayerBottomToTop() throws {
        let size = PSDSize(width: 4, height: 4)
        let back = try PSDDocument.makeSolidLayer(
            name: "Back",
            canvasSize: size,
            red: 0,
            green: 0,
            blue: 255
        )
        var frontPixels = [UInt8](repeating: 0, count: 16)
        for i in 0 ..< 4 {
            frontPixels[i * 4] = 255
            frontPixels[i * 4 + 3] = 255
        }
        let frontLayer = try PixelLayer(
            name: "Front",
            frame: PSDRect(left: 0, top: 0, right: 2, bottom: 2),
            pixels: PixelBuffer(width: 2, height: 2, rgba: Data(frontPixels))
        )

        let doc = try PSDDocument.create(canvasSize: size, layers: [back, frontLayer])
        let data = try doc.data()
        let loaded = try PSDDocument.load(data: data)
        XCTAssertEqual(loaded.root.children.count, 2)
        XCTAssertEqual(loaded.root.children[0].name, "Back")
        XCTAssertEqual(loaded.root.children[1].name, "Front")
    }

    func testAppendToNewDocumentThenExport() throws {
        let doc = try PSDDocument.create(width: 8, height: 8)
        let layer = try PSDDocument.makeSolidLayer(
            name: "Added",
            canvasSize: doc.canvasSize,
            red: 0,
            green: 255,
            blue: 0
        )
        try doc.appendPixelLayer(layer)
        let data = try doc.data()
        let loaded = try PSDDocument.load(data: data)
        XCTAssertEqual(loaded.root.children.count, 1)
        XCTAssertEqual((loaded.root.children[0] as? PixelLayer)?.name, "Added")
    }

    func testMakePixelLayerFromRGBAFile() throws {
        var rgba = Data(count: 16 * 4)
        for i in 0 ..< 16 {
            rgba[i * 4] = 10
            rgba[i * 4 + 1] = 20
            rgba[i * 4 + 2] = 30
            rgba[i * 4 + 3] = 255
        }
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("layer.rgba")
        try rgba.write(to: file)

        let frame = PSDRect(left: 1, top: 1, right: 3, bottom: 3)
        let layer = try PSDDocument.makePixelLayer(name: "FromFile", frame: frame, rgbaFileURL: file)
        XCTAssertEqual(layer.frame, frame)
        XCTAssertEqual(layer.pixels.width, 2)
        XCTAssertEqual(layer.pixels.rgba[0], 10)

        try? FileManager.default.removeItem(at: file)
    }

    func testCreateFromExportedLayers() throws {
        let size = PSDSize(width: 8, height: 8)
        let back = try PSDDocument.makeSolidLayer(
            name: "Background",
            canvasSize: size,
            red: 40,
            green: 40,
            blue: 40
        )
        var frontBytes = Data(repeating: 0, count: 4 * 4)
        for i in 0 ..< 4 {
            frontBytes[i * 4] = 200
            frontBytes[i * 4 + 3] = 255
        }
        let inputs: [LayerRGBAInput] = [
            LayerRGBAInput(name: back.name, frame: back.frame, rgba: back.pixels.rgba),
            LayerRGBAInput(name: "Sprite", left: 0, top: 0, width: 2, height: 2, rgba: frontBytes),
        ]
        let doc = try PSDDocument.create(canvasSize: size, exportedLayers: inputs)
        let data = try doc.data()
        let loaded = try PSDDocument.load(data: data)
        XCTAssertEqual(loaded.root.children.count, 2)
        XCTAssertEqual(loaded.root.children[1].name, "Sprite")
        let sprite = loaded.root.children[1] as! PixelLayer
        XCTAssertEqual(sprite.frame.width, 2)
        XCTAssertEqual(sprite.pixels.rgba[0], 200)
    }
}
