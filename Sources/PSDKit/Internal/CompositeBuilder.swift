import Foundation

/// Builds merged RGB composite image data (Image Data section) from pixel layers.
enum CompositeBuilder {
    static func buildImageData(
        canvasSize: PSDSize,
        layers: [PixelLayer],
        compression: Compression,
        depth: Int = 8,
        psdVersion: Int = 1
    ) throws -> ImageDataSection {
        let rgba = compositeRGBA(canvasSize: canvasSize, layers: layers)
        let count = canvasSize.width * canvasSize.height
        var r = Data(count: count)
        var g = Data(count: count)
        var b = Data(count: count)
        rgba.withUnsafeBytes { src in
            let bytes = src.bindMemory(to: UInt8.self)
            for i in 0 ..< count {
                r[i] = bytes[i * 4]
                g[i] = bytes[i * 4 + 1]
                b[i] = bytes[i * 4 + 2]
            }
        }
        let planar = r + g + b
        let compressed = try ChannelDecompressor.compress(
            raw: planar,
            compression: compression,
            width: canvasSize.width,
            height: canvasSize.height * 3,
            depth: depth,
            psdVersion: psdVersion
        )
        return ImageDataSection(compression: compression, data: compressed)
    }

    /// Bottom-to-top normal blend with per-layer opacity.
    static func compositeRGBA(canvasSize: PSDSize, layers: [PixelLayer]) -> Data {
        let w = canvasSize.width
        let h = canvasSize.height
        let count = w * h
        var canvas = [UInt8](repeating: 255, count: count * 4)
        for layer in layers where layer.isVisible {
            alphaBlend(layer: layer, into: &canvas, canvasWidth: w, canvasHeight: h)
        }
        return Data(canvas)
    }

    private static func alphaBlend(
        layer: PixelLayer,
        into canvas: inout [UInt8],
        canvasWidth: Int,
        canvasHeight: Int
    ) {
        let layerW = layer.frame.width
        let layerH = layer.frame.height
        guard layerW > 0, layerH > 0 else { return }
        let opacity = Double(layer.opacity) / 255.0
        let pixels = [UInt8](layer.pixels.rgba.prefix(layerW * layerH * 4))

        for y in 0 ..< layerH {
            let cy = layer.frame.top + y
            guard cy >= 0, cy < canvasHeight else { continue }
            for x in 0 ..< layerW {
                let cx = layer.frame.left + x
                guard cx >= 0, cx < canvasWidth else { continue }
                let si = (y * layerW + x) * 4
                let di = (cy * canvasWidth + cx) * 4
                guard si + 3 < pixels.count else { continue }

                let srcA = Double(pixels[si + 3]) / 255.0 * opacity
                let invA = 1.0 - srcA
                for c in 0 ..< 3 {
                    let src = Double(pixels[si + c])
                    let dst = Double(canvas[di + c])
                    canvas[di + c] = UInt8(clamping: Int(src * srcA + dst * invA + 0.5))
                }
                canvas[di + 3] = UInt8(
                    clamping: Int(Double(pixels[si + 3]) * opacity + Double(canvas[di + 3]) * invA + 0.5)
                )
            }
        }
    }
}
