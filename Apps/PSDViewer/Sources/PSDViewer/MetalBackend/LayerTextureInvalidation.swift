import Foundation

/// Why layer textures or the cache scope were invalidated.
enum LayerTextureInvalidationReason: Equatable, Sendable, CustomStringConvertible {
    case documentRevisionChanged
    case layerPixelRevisionChanged
    case layerRemoved
    case layerSizeChanged
    case canvasSizeChanged
    case memoryPressure
    case manualClear
    case documentReloaded

    var description: String {
        switch self {
        case .documentRevisionChanged:
            return "documentRevisionChanged"
        case .layerPixelRevisionChanged:
            return "layerPixelRevisionChanged"
        case .layerRemoved:
            return "layerRemoved"
        case .layerSizeChanged:
            return "layerSizeChanged"
        case .canvasSizeChanged:
            return "canvasSizeChanged"
        case .memoryPressure:
            return "memoryPressure"
        case .manualClear:
            return "manualClear"
        case .documentReloaded:
            return "documentReloaded"
        }
    }
}
