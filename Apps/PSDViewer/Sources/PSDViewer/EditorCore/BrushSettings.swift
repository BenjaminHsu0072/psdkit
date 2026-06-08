import CoreGraphics
import Foundation

/// Platform-neutral brush color (no AppKit/SwiftUI).
struct EditorColor: Equatable, Sendable {
    var red: CGFloat
    var green: CGFloat
    var blue: CGFloat
    var alpha: CGFloat

    static let black = EditorColor(red: 0, green: 0, blue: 0, alpha: 1)
}

/// Pure Swift brush parameters aligned with MetalLinePOC semantics (no Metal/AppKit).
struct BrushSettings: Equatable, Sendable {
    var size: CGFloat = 32
    var hardness: Int = 50
    /// Dab spacing factor: spacing = diameter × spacing.
    var spacing: CGFloat = 0.09
    var flow: CGFloat = 0.6
    /// Whole-stroke opacity applied at commit time.
    var opacity: CGFloat = 1.0
    var sizePressure: CGFloat = 1.0
    var minSize: CGFloat = 0.15
    var flowPressure: CGFloat = 1.0
    var minFlow: CGFloat = 0.15
    var color: EditorColor = .black

    static let defaults = BrushSettings()

    func radius(for pressure: CGFloat) -> CGFloat {
        let p = min(max(pressure, 0), 1)
        let minF = min(max(minSize, 0), 1)
        let pressureRadius = (size / 2) * (minF + (1 - minF) * p)
        let constantRadius = size / 2
        let sp = min(max(sizePressure, 0), 1)
        return max(lerp(constantRadius, pressureRadius, sp), 0.5)
    }

    func dabAlpha(for pressure: CGFloat) -> CGFloat {
        let p = min(max(pressure, 0), 1)
        let base = min(max(flow, 0), 1)
        let minF = min(max(minFlow, 0), 1)
        let pressureFlow = base * (minF + (1 - minF) * p)
        let fp = min(max(flowPressure, 0), 1)
        return lerp(base, pressureFlow, fp)
    }

    func spacingDistance(forRadius radius: CGFloat) -> CGFloat {
        var factor = min(max(spacing, 0.01), 0.5)
        if radius < 3 {
            let t = min(max((3 - radius) / 3, 0), 1)
            factor *= (1 - t * 0.5)
        }
        return max(radius * 2 * factor, 0.35)
    }

    private func lerp(_ a: CGFloat, _ b: CGFloat, _ t: CGFloat) -> CGFloat {
        a + (b - a) * t
    }
}
