import CoreGraphics
import Foundation

/// CPU replay of E4 dab stamping. Matches Metal `stampBrushDabsKernel` composite modes.
enum StrokePixelRasterizer {
    static func rasterize(
        plan: BrushRasterizationPlan,
        brush: BrushSettings,
        onto rgba: inout Data,
        width: Int,
        height: Int
    ) {
        guard width > 0, height > 0 else { return }
        guard rgba.count >= width * height * 4 else { return }
        guard !plan.dabs.isEmpty else { return }

        let hardness = Float(min(max(CGFloat(brush.hardness) / 100.0, 0), 1))
        let strokeOpacity = Float(brush.opacity)

        for dab in plan.dabs {
            stampCompositeDab(
                dab,
                mode: plan.mode,
                hardness: hardness,
                strokeOpacity: strokeOpacity,
                onto: &rgba,
                width: width,
                height: height
            )
        }
    }

    private static func stampCompositeDab(
        _ dab: BrushDab,
        mode: BrushStrokeMode,
        hardness: Float,
        strokeOpacity: Float,
        onto rgba: inout Data,
        width: Int,
        height: Int
    ) {
        let radius = Float(dab.radius)
        guard radius > 0 else { return }

        let minX = max(0, Int(floor(dab.center.x - dab.radius)))
        let minY = max(0, Int(floor(dab.center.y - dab.radius)))
        let maxX = min(width - 1, Int(ceil(dab.center.x + dab.radius)))
        let maxY = min(height - 1, Int(ceil(dab.center.y + dab.radius)))
        guard minX <= maxX, minY <= maxY else { return }

        let dabColor = RGBAFloat(
            red: Float(dab.color.red),
            green: Float(dab.color.green),
            blue: Float(dab.color.blue),
            alpha: Float(dab.color.alpha)
        )

        for y in minY ... maxY {
            for x in minX ... maxX {
                let pixel = CGPoint(x: CGFloat(x) + 0.5, y: CGFloat(y) + 0.5)
                let dist = hypot(Float(pixel.x - dab.center.x), Float(pixel.y - dab.center.y))
                let mask = radialMask(dist: dist, radius: radius, hardness: hardness)
                guard mask > 0 else { continue }

                let src = brushSource(
                    mask: mask,
                    dabAlpha: Float(dab.alpha),
                    strokeOpacity: strokeOpacity,
                    color: dabColor
                )
                let dst = readPixel(rgba: rgba, width: width, x: x, y: y)
                let out: RGBAFloat
                switch mode {
                case .brush:
                    out = compositeSrcOver(dst: dst, src: src)
                case .eraser:
                    out = compositeDestinationOut(dst: dst, srcAlpha: src.alpha)
                }
                writePixel(out, into: &rgba, width: width, x: x, y: y)
            }
        }
    }

    private struct RGBAFloat: Equatable {
        var red: Float
        var green: Float
        var blue: Float
        var alpha: Float
    }

    private static func radialMask(dist: Float, radius: Float, hardness: Float) -> Float {
        guard radius > 0 else { return 0 }
        let t = min(max(dist / radius, 0), 1)
        let inner = hardness
        if t <= inner { return 1 }
        if inner >= 1 { return 0 }
        return 1 - ((t - inner) / (1 - inner))
    }

    private static func brushSource(
        mask: Float,
        dabAlpha: Float,
        strokeOpacity: Float,
        color: RGBAFloat
    ) -> RGBAFloat {
        let alpha = mask * dabAlpha * strokeOpacity
        return RGBAFloat(
            red: color.red * alpha,
            green: color.green * alpha,
            blue: color.blue * alpha,
            alpha: alpha
        )
    }

    private static func compositeSrcOver(dst: RGBAFloat, src: RGBAFloat) -> RGBAFloat {
        let inverse = 1 - src.alpha
        return RGBAFloat(
            red: src.red + dst.red * inverse,
            green: src.green + dst.green * inverse,
            blue: src.blue + dst.blue * inverse,
            alpha: src.alpha + dst.alpha * inverse
        )
    }

    private static func compositeDestinationOut(dst: RGBAFloat, srcAlpha: Float) -> RGBAFloat {
        let factor = 1 - srcAlpha
        return RGBAFloat(
            red: dst.red * factor,
            green: dst.green * factor,
            blue: dst.blue * factor,
            alpha: dst.alpha * factor
        )
    }

    private static func readPixel(rgba: Data, width: Int, x: Int, y: Int) -> RGBAFloat {
        let index = (y * width + x) * 4
        return RGBAFloat(
            red: Float(rgba[index]) / 255,
            green: Float(rgba[index + 1]) / 255,
            blue: Float(rgba[index + 2]) / 255,
            alpha: Float(rgba[index + 3]) / 255
        )
    }

    private static func writePixel(_ color: RGBAFloat, into rgba: inout Data, width: Int, x: Int, y: Int) {
        let index = (y * width + x) * 4
        rgba[index] = UInt8(clamping: Int((min(max(color.red, 0), 1) * 255).rounded()))
        rgba[index + 1] = UInt8(clamping: Int((min(max(color.green, 0), 1) * 255).rounded()))
        rgba[index + 2] = UInt8(clamping: Int((min(max(color.blue, 0), 1) * 255).rounded()))
        rgba[index + 3] = UInt8(clamping: Int((min(max(color.alpha, 0), 1) * 255).rounded()))
    }
}
