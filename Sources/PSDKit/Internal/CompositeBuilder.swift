import Foundation

/// Builds merged RGB composite image data (Image Data section) from pixel layers.
enum CompositeBuilder {
    /// `255 * 255`; matches `Double(pixelAlpha) / 255 * Double(layerOpacity) / 255` in legacy compositing.
    private static let alphaScale = 65_025
    private static let alphaRoundBias = alphaScale / 2

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
        try PlanarRGBA.deinterleaveRGB(
            rgba,
            width: canvasSize.width,
            height: canvasSize.height,
            intoRed: &r,
            intoGreen: &g,
            intoBlue: &b
        )
        var planar = Data(count: count * 3)
        try PlanarRGBA.packRGBPlanes(red: r, green: g, blue: b, into: &planar)
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

    /// Bottom-to-top composite with per-layer blend mode, pixel alpha, and layer opacity.
    static func compositeRGBA(canvasSize: PSDSize, layers: [PixelLayer]) -> Data {
        let w = canvasSize.width
        let h = canvasSize.height
        let count = w * h
        var canvas = [UInt8](repeating: 255, count: count * 4)
        for layer in layers where layer.isVisible {
            compositeLayer(layer: layer, into: &canvas, canvasWidth: w, canvasHeight: h)
        }
        return Data(canvas)
    }

    private static func compositeLayer(
        layer: PixelLayer,
        into canvas: inout [UInt8],
        canvasWidth: Int,
        canvasHeight: Int
    ) {
        let layerW = layer.frame.width
        let layerH = layer.frame.height
        guard layerW > 0, layerH > 0 else { return }

        let layerOpacity = layer.opacity
        let blendMode = effectiveBlendMode(layer.blendMode)
        let frameLeft = layer.frame.left
        let frameTop = layer.frame.top

        let clipLeft = max(0, frameLeft)
        let clipRight = min(canvasWidth, frameLeft + layerW)
        let clipTop = max(0, frameTop)
        let clipBottom = min(canvasHeight, frameTop + layerH)
        guard clipLeft < clipRight, clipTop < clipBottom else { return }

        let pixelBytes = layerW * layerH * 4
        layer.pixels.rgba.withUnsafeBytes { raw in
            guard raw.count >= pixelBytes else { return }
            let pixels = raw.bindMemory(to: UInt8.self)

            for cy in clipTop ..< clipBottom {
                let y = cy - frameTop
                let srcRow = y * layerW * 4
                let dstRow = cy * canvasWidth * 4
                for cx in clipLeft ..< clipRight {
                    let x = cx - frameLeft
                    let si = srcRow + x * 4
                    let di = dstRow + cx * 4

                    let pixelAlpha = pixels[si + 3]
                    let effective = Int(pixelAlpha) * Int(layerOpacity)
                    let invEffective = alphaScale - effective

                    for c in 0 ..< 3 {
                        let src = pixels[si + c]
                        let dst = canvas[di + c]
                        let blended = blendChannel(src: src, dst: dst, mode: blendMode)
                        let value = Int(blended) * effective + Int(dst) * invEffective + alphaRoundBias
                        canvas[di + c] = UInt8(clamping: value / alphaScale)
                    }
                    let alphaValue = Int(pixelAlpha) * Int(layerOpacity) * 255
                        + Int(canvas[di + 3]) * invEffective + alphaRoundBias
                    canvas[di + 3] = UInt8(clamping: alphaValue / alphaScale)
                }
            }
        }
    }

    /// Preview-only fallback: pixel layers should not carry group-only modes.
    private static func effectiveBlendMode(_ mode: BlendMode) -> BlendMode {
        switch mode {
        case .normal, .multiply, .add:
            return mode
        case .passThrough, .unknown:
            return .normal
        }
    }

    /// 8-bit blend-mode kernel; multiply rounds half-up via `(a*b+127)/255`.
    private static func blendChannel(src: UInt8, dst: UInt8, mode: BlendMode) -> UInt8 {
        switch mode {
        case .normal, .passThrough, .unknown:
            return src
        case .multiply:
            return UInt8((Int(src) * Int(dst) + 127) / 255)
        case .add:
            return UInt8(min(255, Int(src) + Int(dst)))
        }
    }
}
