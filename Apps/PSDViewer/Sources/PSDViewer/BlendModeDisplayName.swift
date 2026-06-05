import PSDKit

enum BlendModeDisplayName {
    static func text(for mode: BlendMode) -> String {
        switch mode {
        case .normal: return "Normal"
        case .multiply: return "Multiply"
        case .add: return "Linear Dodge (Add)"
        case .passThrough: return "Pass Through"
        case .unknown: return "Unknown"
        }
    }
}
