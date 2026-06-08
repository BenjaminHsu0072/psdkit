import Foundation
import Metal
import PSDKit

/// Decides whether the default preview uses Metal or CPU fallback.
enum EditorPreviewRouting {
    enum FallbackReason: Equatable {
        case metalUnavailable
        case rendererInitFailed
        case unsupportedBlendMode(BlendMode)
        case userDisabledMetal

        var statusMessage: String {
            switch self {
            case .metalUnavailable:
                return "Metal preview unavailable (no GPU device). Using CPU fallback."
            case .rendererInitFailed:
                return "Metal preview initialization failed. Using CPU fallback."
            case .unsupportedBlendMode(let mode):
                return "Blend mode \(BlendModeDisplayName.text(for: mode)) is not supported on Metal preview. Using CPU fallback."
            case .userDisabledMetal:
                return "Metal preview disabled. Using CPU fallback."
            }
        }
    }

    static func cpuFallbackReason(
        snapshot: EditorRenderSnapshot,
        userPrefersMetal: Bool
    ) -> FallbackReason? {
        if !userPrefersMetal {
            return .userDisabledMetal
        }
        guard MTLCreateSystemDefaultDevice() != nil else {
            return .metalUnavailable
        }
        guard EditorMetalRenderer.canInitialize() else {
            return .rendererInitFailed
        }
        if let blend = EditorPreviewBlendSupport.firstUnsupportedBlend(in: snapshot) {
            return .unsupportedBlendMode(blend)
        }
        return nil
    }
}
