import XCTest
@testable import PSDKit

final class PlanarRGBATests: XCTestCase {
    func testInterleaveIntoMatchesReturnValue() throws {
        let width = 3
        let height = 2
        let count = width * height
        let red = Data((0 ..< count).map { UInt8($0) })
        let green = Data((0 ..< count).map { UInt8($0 + 10) })
        let blue = Data((0 ..< count).map { UInt8($0 + 20) })
        let alpha = Data((0 ..< count).map { UInt8($0 + 30) })

        let expected = try PlanarRGBA.interleave(
            red: red,
            green: green,
            blue: blue,
            alpha: alpha,
            width: width,
            height: height
        )
        var buffer = Data(count: count * 4)
        try PlanarRGBA.interleave(
            red: red,
            green: green,
            blue: blue,
            alpha: alpha,
            width: width,
            height: height,
            into: &buffer
        )
        XCTAssertEqual(buffer, expected)
    }

    func testDeinterleaveIntoMatchesReturnValue() throws {
        let width = 2
        let height = 2
        let rgba = Data([
            1, 2, 3, 4,
            5, 6, 7, 8,
            9, 10, 11, 12,
            13, 14, 15, 16,
        ])
        let expected = try PlanarRGBA.deinterleave(rgba, width: width, height: height)

        var r = Data(count: width * height)
        var g = Data(count: width * height)
        var b = Data(count: width * height)
        var a = Data(count: width * height)
        try PlanarRGBA.deinterleave(
            rgba,
            width: width,
            height: height,
            intoRed: &r,
            intoGreen: &g,
            intoBlue: &b,
            intoAlpha: &a
        )
        XCTAssertEqual(r, expected.r)
        XCTAssertEqual(g, expected.g)
        XCTAssertEqual(b, expected.b)
        XCTAssertEqual(a, expected.a)
    }

    func testDeinterleaveRGBAndPackPlanes() throws {
        let rgba = Data([
            10, 20, 30, 255,
            40, 50, 60, 128,
        ])
        var r = Data(count: 2)
        var g = Data(count: 2)
        var b = Data(count: 2)
        try PlanarRGBA.deinterleaveRGB(
            rgba,
            width: 2,
            height: 1,
            intoRed: &r,
            intoGreen: &g,
            intoBlue: &b
        )
        var planar = Data(count: 6)
        try PlanarRGBA.packRGBPlanes(red: r, green: g, blue: b, into: &planar)
        XCTAssertEqual(planar, Data([10, 40, 20, 50, 30, 60]))
    }

    func testInterleaveWithoutAlphaUses255() throws {
        let rgba = try PlanarRGBA.interleave(
            red: Data([1, 2]),
            green: Data([3, 4]),
            blue: Data([5, 6]),
            alpha: nil,
            width: 2,
            height: 1
        )
        XCTAssertEqual(rgba, Data([1, 3, 5, 255, 2, 4, 6, 255]))
    }
}
