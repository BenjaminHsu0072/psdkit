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
        guard red.count >= count, green.count >= count, blue.count >= count else {
            throw PSDError.corruptStructure("plane size mismatch")
        }
        if let alpha, alpha.count < count {
            throw PSDError.corruptStructure("alpha plane too short")
        }
        var rgba = Data(count: count * 4)
        rgba.withUnsafeMutableBytes { dest in
            let out = dest.bindMemory(to: UInt8.self)
            for i in 0 ..< count {
                out[i * 4] = red[i]
                out[i * 4 + 1] = green[i]
                out[i * 4 + 2] = blue[i]
                out[i * 4 + 3] = alpha?[i] ?? 255
            }
        }
        return rgba
    }

    static func deinterleave(_ rgba: Data, width: Int, height: Int) throws -> (r: Data, g: Data, b: Data, a: Data) {
        let count = width * height
        guard rgba.count >= count * 4 else {
            throw PSDError.corruptStructure("rgba buffer too short")
        }
        var r = Data(count: count)
        var g = Data(count: count)
        var b = Data(count: count)
        var a = Data(count: count)
        rgba.withUnsafeBytes { src in
            let bytes = src.bindMemory(to: UInt8.self)
            for i in 0 ..< count {
                r[i] = bytes[i * 4]
                g[i] = bytes[i * 4 + 1]
                b[i] = bytes[i * 4 + 2]
                a[i] = bytes[i * 4 + 3]
            }
        }
        return (r, g, b, a)
    }
}
