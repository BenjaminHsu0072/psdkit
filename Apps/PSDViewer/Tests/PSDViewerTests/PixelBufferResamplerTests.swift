import Foundation
import PSDKit
import XCTest
@testable import PSDViewer

final class PixelBufferResamplerTests: XCTestCase {
    func testUpscale2x2To4x4SamplesAllQuadrants() throws {
        let source = makeQuadrant2x2RGBA()
        let result = try PixelBufferResampler.resampleRGBA(
            source: source,
            sourceWidth: 2,
            sourceHeight: 2,
            targetWidth: 4,
            targetHeight: 4
        )

        XCTAssertEqual(result.count, 4 * 4 * 4)
        assertRGBA(in: result, width: 4, x: 0, y: 0, r: 255, g: 0, b: 0, a: 255)
        assertRGBA(in: result, width: 4, x: 3, y: 0, r: 0, g: 255, b: 0, a: 255)
        assertRGBA(in: result, width: 4, x: 0, y: 3, r: 0, g: 0, b: 255, a: 255)
        assertRGBA(in: result, width: 4, x: 3, y: 3, r: 255, g: 255, b: 0, a: 255)
    }

    func testDownscale4x4To2x2SamplesAcrossSource() throws {
        let source = makeQuadrant4x4RGBA()
        let result = try PixelBufferResampler.resampleRGBA(
            source: source,
            sourceWidth: 4,
            sourceHeight: 4,
            targetWidth: 2,
            targetHeight: 2
        )

        XCTAssertEqual(result.count, 2 * 2 * 4)
        assertRGBA(in: result, width: 2, x: 0, y: 0, r: 255, g: 0, b: 0, a: 255)
        assertRGBA(in: result, width: 2, x: 1, y: 0, r: 0, g: 255, b: 0, a: 255)
        assertRGBA(in: result, width: 2, x: 0, y: 1, r: 0, g: 0, b: 255, a: 255)
        assertRGBA(in: result, width: 2, x: 1, y: 1, r: 255, g: 255, b: 0, a: 255)
    }

    func testRejectsInvalidSourceByteCount() {
        XCTAssertThrowsError(
            try PixelBufferResampler.resampleRGBA(
                source: Data(count: 3),
                sourceWidth: 2,
                sourceHeight: 2,
                targetWidth: 4,
                targetHeight: 4
            )
        )
    }

    private func makeQuadrant2x2RGBA() -> Data {
        var rgba = Data(count: 2 * 2 * 4)
        setRGBA(in: &rgba, width: 2, x: 0, y: 0, r: 255, g: 0, b: 0, a: 255)
        setRGBA(in: &rgba, width: 2, x: 1, y: 0, r: 0, g: 255, b: 0, a: 255)
        setRGBA(in: &rgba, width: 2, x: 0, y: 1, r: 0, g: 0, b: 255, a: 255)
        setRGBA(in: &rgba, width: 2, x: 1, y: 1, r: 255, g: 255, b: 0, a: 255)
        return rgba
    }

    private func makeQuadrant4x4RGBA() -> Data {
        var rgba = Data(count: 4 * 4 * 4)
        for y in 0 ..< 2 {
            for x in 0 ..< 2 {
                setRGBA(in: &rgba, width: 4, x: x, y: y, r: 255, g: 0, b: 0, a: 255)
            }
        }
        for y in 0 ..< 2 {
            for x in 2 ..< 4 {
                setRGBA(in: &rgba, width: 4, x: x, y: y, r: 0, g: 255, b: 0, a: 255)
            }
        }
        for y in 2 ..< 4 {
            for x in 0 ..< 2 {
                setRGBA(in: &rgba, width: 4, x: x, y: y, r: 0, g: 0, b: 255, a: 255)
            }
        }
        for y in 2 ..< 4 {
            for x in 2 ..< 4 {
                setRGBA(in: &rgba, width: 4, x: x, y: y, r: 255, g: 255, b: 0, a: 255)
            }
        }
        return rgba
    }

    private func setRGBA(
        in data: inout Data,
        width: Int,
        x: Int,
        y: Int,
        r: UInt8,
        g: UInt8,
        b: UInt8,
        a: UInt8
    ) {
        let offset = (y * width + x) * 4
        data[offset] = r
        data[offset + 1] = g
        data[offset + 2] = b
        data[offset + 3] = a
    }

    private func assertRGBA(
        in data: Data,
        width: Int,
        x: Int,
        y: Int,
        r: UInt8,
        g: UInt8,
        b: UInt8,
        a: UInt8,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let offset = (y * width + x) * 4
        XCTAssertEqual(data[offset], r, file: file, line: line)
        XCTAssertEqual(data[offset + 1], g, file: file, line: line)
        XCTAssertEqual(data[offset + 2], b, file: file, line: line)
        XCTAssertEqual(data[offset + 3], a, file: file, line: line)
    }
}

@MainActor
final class DocumentModelFrameResizeTests: XCTestCase {
    func testSetLayerFrameUpscaleResamplesPixels() throws {
        let model = try makeModelWithQuadrantLayer()
        guard let path = model.selectedLayerPath else {
            XCTFail("missing selected layer path")
            return
        }

        model.setLayerFrame(at: path, left: 0, top: 0, width: 4, height: 4)

        guard let layer = model.selectedPixelLayer else {
            XCTFail("missing selected pixel layer")
            return
        }
        XCTAssertEqual(layer.pixels.width, 4)
        XCTAssertEqual(layer.pixels.height, 4)
        assertRGBA(
            in: layer.pixels,
            x: 3,
            y: 3,
            r: 255,
            g: 255,
            b: 0,
            a: 255,
            message: "bottom-right should come from source quadrant, not transparent padding"
        )
    }

    func testSetLayerFrameDownscaleProducesTargetSize() throws {
        let layer = try makeQuadrantPixelLayer(width: 4, height: 4)
        let doc = try PSDDocument.create(width: 8, height: 8, layers: [layer])
        let model = try openDocument(doc)

        guard let path = model.selectedLayerPath else {
            XCTFail("missing selected layer path")
            return
        }

        model.setLayerFrame(at: path, left: 0, top: 0, width: 2, height: 2)

        guard let updated = model.selectedPixelLayer else {
            XCTFail("missing selected pixel layer")
            return
        }
        XCTAssertEqual(updated.pixels.width, 2)
        XCTAssertEqual(updated.pixels.height, 2)
        assertRGBA(in: updated.pixels, x: 1, y: 1, r: 255, g: 255, b: 0, a: 255)
    }

    func testSetLayerFrameMoveOnlyPreservesPixels() throws {
        let model = try makeModelWithQuadrantLayer()
        guard let path = model.selectedLayerPath,
              let before = model.selectedPixelLayer
        else {
            XCTFail("missing selected layer")
            return
        }
        let beforeRGBA = before.pixels.rgba

        model.setLayerFrame(at: path, left: 2, top: 3, width: 2, height: 2)

        guard let updated = model.selectedPixelLayer else {
            XCTFail("missing selected pixel layer")
            return
        }
        XCTAssertEqual(updated.pixels.rgba, beforeRGBA)
        XCTAssertEqual(updated.frame.left, 2)
        XCTAssertEqual(updated.frame.top, 3)
        XCTAssertEqual(updated.frame.width, 2)
        XCTAssertEqual(updated.frame.height, 2)
    }

    private func makeModelWithQuadrantLayer() throws -> DocumentModel {
        let layer = try makeQuadrantPixelLayer(width: 2, height: 2)
        let doc = try PSDDocument.create(width: 8, height: 8, layers: [layer])
        return try openDocument(doc)
    }

    private func openDocument(_ document: PSDDocument) throws -> DocumentModel {
        let temp = FileManager.default.temporaryDirectory
            .appendingPathComponent("frame-resize-\(UUID().uuidString).psd")
        defer { try? FileManager.default.removeItem(at: temp) }
        try document.save(to: temp)

        let model = DocumentModel()
        model.open(url: temp)
        return model
    }

    private func makeQuadrantPixelLayer(width: Int, height: Int) throws -> PixelLayer {
        var rgba = Data(count: width * height * 4)
        if width == 2, height == 2 {
            setRGBA(in: &rgba, width: 2, x: 0, y: 0, r: 255, g: 0, b: 0, a: 255)
            setRGBA(in: &rgba, width: 2, x: 1, y: 0, r: 0, g: 255, b: 0, a: 255)
            setRGBA(in: &rgba, width: 2, x: 0, y: 1, r: 0, g: 0, b: 255, a: 255)
            setRGBA(in: &rgba, width: 2, x: 1, y: 1, r: 255, g: 255, b: 0, a: 255)
        } else if width == 4, height == 4 {
            for y in 0 ..< 2 {
                for x in 0 ..< 2 {
                    setRGBA(in: &rgba, width: 4, x: x, y: y, r: 255, g: 0, b: 0, a: 255)
                }
            }
            for y in 0 ..< 2 {
                for x in 2 ..< 4 {
                    setRGBA(in: &rgba, width: 4, x: x, y: y, r: 0, g: 255, b: 0, a: 255)
                }
            }
            for y in 2 ..< 4 {
                for x in 0 ..< 2 {
                    setRGBA(in: &rgba, width: 4, x: x, y: y, r: 0, g: 0, b: 255, a: 255)
                }
            }
            for y in 2 ..< 4 {
                for x in 2 ..< 4 {
                    setRGBA(in: &rgba, width: 4, x: x, y: y, r: 255, g: 255, b: 0, a: 255)
                }
            }
        }
        return try PixelLayer(
            name: "Quadrant",
            frame: PSDRect(left: 0, top: 0, right: width, bottom: height),
            pixels: PixelBuffer(width: width, height: height, rgba: rgba)
        )
    }

    private func setRGBA(
        in data: inout Data,
        width: Int,
        x: Int,
        y: Int,
        r: UInt8,
        g: UInt8,
        b: UInt8,
        a: UInt8
    ) {
        let offset = (y * width + x) * 4
        data[offset] = r
        data[offset + 1] = g
        data[offset + 2] = b
        data[offset + 3] = a
    }

    private func assertRGBA(
        in buffer: PixelBuffer,
        x: Int,
        y: Int,
        r: UInt8,
        g: UInt8,
        b: UInt8,
        a: UInt8,
        message: String? = nil,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let offset = (y * buffer.width + x) * 4
        let data = buffer.rgba
        let label = message ?? ""
        XCTAssertEqual(data[offset], r, label, file: file, line: line)
        XCTAssertEqual(data[offset + 1], g, label, file: file, line: line)
        XCTAssertEqual(data[offset + 2], b, label, file: file, line: line)
        XCTAssertEqual(data[offset + 3], a, label, file: file, line: line)
    }
}
