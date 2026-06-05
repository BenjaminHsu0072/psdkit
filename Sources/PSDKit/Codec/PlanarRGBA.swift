import Foundation

enum PlanarRGBA {
    /// Interleave R,G,B,(optional A) planes into RGBA8888 row-major.
    static func interleave(
        red: Data,
        green: Data,
        blue: Data,
        alpha: Data?,
        width: Int,
        height: Int
    ) throws -> Data {
        let count = width * height
        var rgba = Data(count: count * 4)
        try interleave(
            red: red,
            green: green,
            blue: blue,
            alpha: alpha,
            width: width,
            height: height,
            into: &rgba
        )
        return rgba
    }

    /// Writes RGBA8888 row-major into a pre-allocated buffer (`rgba.count >= width * height * 4`).
    static func interleave(
        red: Data,
        green: Data,
        blue: Data,
        alpha: Data?,
        width: Int,
        height: Int,
        into rgba: inout Data
    ) throws {
        let count = width * height
        guard red.count >= count, green.count >= count, blue.count >= count else {
            throw PSDError.corruptStructure("plane size mismatch")
        }
        if let alpha, alpha.count < count {
            throw PSDError.corruptStructure("alpha plane too short")
        }
        guard rgba.count >= count * 4 else {
            throw PSDError.corruptStructure("rgba buffer too short")
        }
        rgba.withUnsafeMutableBytes { dest in
            let out = dest.bindMemory(to: UInt8.self)
            red.withUnsafeBytes { r in
                green.withUnsafeBytes { g in
                    blue.withUnsafeBytes { b in
                        let rp = r.bindMemory(to: UInt8.self)
                        let gp = g.bindMemory(to: UInt8.self)
                        let bp = b.bindMemory(to: UInt8.self)
                        if let alpha {
                            alpha.withUnsafeBytes { a in
                                let ap = a.bindMemory(to: UInt8.self)
                                for i in 0 ..< count {
                                    out[i * 4] = rp[i]
                                    out[i * 4 + 1] = gp[i]
                                    out[i * 4 + 2] = bp[i]
                                    out[i * 4 + 3] = ap[i]
                                }
                            }
                        } else {
                            for i in 0 ..< count {
                                out[i * 4] = rp[i]
                                out[i * 4 + 1] = gp[i]
                                out[i * 4 + 2] = bp[i]
                                out[i * 4 + 3] = 255
                            }
                        }
                    }
                }
            }
        }
    }

    static func deinterleave(_ rgba: Data, width: Int, height: Int) throws -> (r: Data, g: Data, b: Data, a: Data) {
        let count = width * height
        var r = Data(count: count)
        var g = Data(count: count)
        var b = Data(count: count)
        var a = Data(count: count)
        try deinterleave(
            rgba,
            width: width,
            height: height,
            intoRed: &r,
            intoGreen: &g,
            intoBlue: &b,
            intoAlpha: &a
        )
        return (r, g, b, a)
    }

    /// Writes planar R,G,B,A from RGBA8888 into pre-allocated buffers.
    static func deinterleave(
        _ rgba: Data,
        width: Int,
        height: Int,
        intoRed red: inout Data,
        intoGreen green: inout Data,
        intoBlue blue: inout Data,
        intoAlpha alpha: inout Data
    ) throws {
        let count = width * height
        guard rgba.count >= count * 4 else {
            throw PSDError.corruptStructure("rgba buffer too short")
        }
        guard red.count >= count, green.count >= count, blue.count >= count, alpha.count >= count else {
            throw PSDError.corruptStructure("plane buffer too short")
        }
        rgba.withUnsafeBytes { src in
            let bytes = src.bindMemory(to: UInt8.self)
            red.withUnsafeMutableBytes { r in
                green.withUnsafeMutableBytes { g in
                    blue.withUnsafeMutableBytes { b in
                        alpha.withUnsafeMutableBytes { a in
                            let rp = r.bindMemory(to: UInt8.self)
                            let gp = g.bindMemory(to: UInt8.self)
                            let bp = b.bindMemory(to: UInt8.self)
                            let ap = a.bindMemory(to: UInt8.self)
                            for i in 0 ..< count {
                                rp[i] = bytes[i * 4]
                                gp[i] = bytes[i * 4 + 1]
                                bp[i] = bytes[i * 4 + 2]
                                ap[i] = bytes[i * 4 + 3]
                            }
                        }
                    }
                }
            }
        }
    }

    /// Writes planar R,G,B from RGBA8888 into pre-allocated buffers (alpha ignored).
    static func deinterleaveRGB(
        _ rgba: Data,
        width: Int,
        height: Int,
        intoRed red: inout Data,
        intoGreen green: inout Data,
        intoBlue blue: inout Data
    ) throws {
        let count = width * height
        guard rgba.count >= count * 4 else {
            throw PSDError.corruptStructure("rgba buffer too short")
        }
        guard red.count >= count, green.count >= count, blue.count >= count else {
            throw PSDError.corruptStructure("plane buffer too short")
        }
        rgba.withUnsafeBytes { src in
            let bytes = src.bindMemory(to: UInt8.self)
            red.withUnsafeMutableBytes { r in
                green.withUnsafeMutableBytes { g in
                    blue.withUnsafeMutableBytes { b in
                        let rp = r.bindMemory(to: UInt8.self)
                        let gp = g.bindMemory(to: UInt8.self)
                        let bp = b.bindMemory(to: UInt8.self)
                        for i in 0 ..< count {
                            rp[i] = bytes[i * 4]
                            gp[i] = bytes[i * 4 + 1]
                            bp[i] = bytes[i * 4 + 2]
                        }
                    }
                }
            }
        }
    }

    /// Writes interleaved RGB planar data (R plane, then G, then B) into `planar` (`planar.count >= count * 3`).
    static func packRGBPlanes(
        red: Data,
        green: Data,
        blue: Data,
        into planar: inout Data
    ) throws {
        let count = red.count
        guard green.count >= count, blue.count >= count, planar.count >= count * 3 else {
            throw PSDError.corruptStructure("plane buffer too short")
        }
        for i in 0 ..< count {
            planar[i] = red[i]
            planar[count + i] = green[i]
            planar[count * 2 + i] = blue[i]
        }
    }
}
