import Foundation
import PSDKit

/// Viewer-side edit/toggle boundaries for the M3 nested-group display phase.
enum LayerViewerEditPolicy: Equatable, Sendable {
    case editableRootPixel
    case readOnly(ReadOnlyReason)

    enum ReadOnlyReason: Equatable, Sendable {
        case group
        case nestedPixel
    }

    var isEditable: Bool {
        if case .editableRootPixel = self { return true }
        return false
    }
}

enum LayerViewerPolicy {
    static func isRootLevel(path: LayerPath) -> Bool {
        path.indices.count == 1
    }

    static func editPolicy(for item: LayerListItem) -> LayerViewerEditPolicy {
        switch item.displayKind {
        case .group:
            return .readOnly(.group)
        case .pixel:
            return isRootLevel(path: item.path) ? .editableRootPixel : .readOnly(.nestedPixel)
        }
    }

    static func editPolicy(path: LayerPath, layer: any LayerProtocol) -> LayerViewerEditPolicy {
        if layer is GroupLayer {
            return .readOnly(.group)
        }
        return isRootLevel(path: path) ? .editableRootPixel : .readOnly(.nestedPixel)
    }

    /// Only root-level pixel layers may toggle visibility in this Viewer phase.
    static func canToggleVisibility(for item: LayerListItem) -> Bool {
        item.displayKind == .pixel && isRootLevel(path: item.path)
    }
}
