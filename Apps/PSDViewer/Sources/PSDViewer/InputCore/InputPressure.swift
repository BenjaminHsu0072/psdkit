import CoreGraphics
import Foundation

/// Normalizes tablet/mouse pressure for stroke sampling. E4 consumes the clamped value.
enum InputPressure {
    static let mouseDefault: CGFloat = 1.0

    static func normalized(_ raw: CGFloat, device: PointerDeviceKind) -> CGFloat {
        let value: CGFloat
        switch device {
        case .tablet:
            value = raw
        case .mouse, .trackpad, .unknown:
            value = raw > 0 ? raw : mouseDefault
        }
        return min(max(value, 0), 1)
    }
}
