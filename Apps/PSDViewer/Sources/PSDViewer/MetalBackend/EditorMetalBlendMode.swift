import Foundation
import PSDKit

enum EditorMetalBlendMode {
    static let normal = 0
    static let multiply = 1
    static let add = 2

    static func encode(_ mode: BlendMode) -> Int? {
        switch mode {
        case .normal:
            return normal
        case .multiply:
            return multiply
        case .add:
            return add
        case .passThrough, .unknown:
            return nil
        }
    }
}
