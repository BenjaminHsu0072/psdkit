import AppKit
import CoreGraphics
import Foundation
import PSDKit

enum ImageImport {
    /// Decodes PNG (or any image `NSImage` supports) to straight RGBA8888.
    static func loadRGBA(from url: URL) throws -> (data: Data, width: Int, height: Int) {
        guard let image = NSImage(contentsOf: url) else {
            throw PSDError.corruptStructure("could not decode image")
        }
        return try loadRGBA(from: image)
    }

    static func loadRGBA(from image: NSImage) throws -> (data: Data, width: Int, height: Int) {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            throw PSDError.corruptStructure("image has no bitmap representation")
        }
        return try loadRGBA(from: cgImage)
    }

    static func loadRGBA(from cgImage: CGImage) throws -> (data: Data, width: Int, height: Int) {
        let width = cgImage.width
        let height = cgImage.height
        guard width > 0, height > 0 else {
            throw PSDError.corruptStructure("image dimensions must be positive")
        }

        var rgba = Data(count: width * height * 4)
        let ok = rgba.withUnsafeMutableBytes { raw -> Bool in
            guard let base = raw.baseAddress else { return false }
            guard let context = CGContext(
                data: base,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else {
                return false
            }
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard ok else {
            throw PSDError.corruptStructure("failed to rasterize image")
        }
        unpremultiplyRGBA(&rgba)
        return (rgba, width, height)
    }

    private static func unpremultiplyRGBA(_ data: inout Data) {
        data.withUnsafeMutableBytes { raw in
            let bytes = raw.bindMemory(to: UInt8.self)
            let count = bytes.count / 4
            for i in 0 ..< count {
                let a = bytes[i * 4 + 3]
                guard a > 0, a < 255 else { continue }
                let scale = 255.0 / Double(a)
                bytes[i * 4] = UInt8(min(255, Int(Double(bytes[i * 4]) * scale + 0.5)))
                bytes[i * 4 + 1] = UInt8(min(255, Int(Double(bytes[i * 4 + 1]) * scale + 0.5)))
                bytes[i * 4 + 2] = UInt8(min(255, Int(Double(bytes[i * 4 + 2]) * scale + 0.5)))
            }
        }
    }
}
