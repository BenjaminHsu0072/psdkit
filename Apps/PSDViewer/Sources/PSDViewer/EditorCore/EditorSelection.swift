import Foundation

/// Unified editor selection. Replaces scattered `selectedLayerID` checks in core logic.
enum EditorSelection: Equatable, Sendable {
    case none
    case layer(id: String)

    var layerID: String? {
        switch self {
        case .none:
            nil
        case .layer(let id):
            id
        }
    }

    static func from(layerID: String?) -> EditorSelection {
        guard let layerID else { return .none }
        return .layer(id: layerID)
    }
}
