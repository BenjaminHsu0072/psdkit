import Foundation
import PSDKit

/// Blend modes supported on the default Metal preview path (E1 frozen subset).
enum EditorPreviewBlendSupport {
    static func isMetalSupported(_ mode: BlendMode) -> Bool {
        switch mode {
        case .normal, .multiply, .add:
            return true
        case .passThrough, .unknown:
            return false
        }
    }

    static func firstUnsupportedBlend(in snapshot: EditorRenderSnapshot) -> BlendMode? {
        for layer in snapshot.layers where layer.kind == .pixel && layer.isVisible {
            if !isMetalSupported(layer.blendMode) {
                return layer.blendMode
            }
        }
        return nil
    }
}
