import AppKit
import CoreGraphics
import Foundation
import PSDKit

enum PreviewRenderer {
    static func makeImage(from document: PSDDocument) throws -> NSImage {
        let rgba = document.compositePreviewRGBA()
        let w = document.canvasSize.width
        let h = document.canvasSize.height
        guard let provider = CGDataProvider(data: rgba as CFData) else {
            throw PSDError.corruptStructure("preview data provider failed")
        }
        guard let cgImage = CGImage(
            width: w,
            height: h,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: w * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: true,
            intent: .defaultIntent
        ) else {
            throw PSDError.corruptStructure("preview CGImage failed")
        }
        return NSImage(cgImage: cgImage, size: NSSize(width: w, height: h))
    }
}
