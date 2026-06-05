import Foundation
import PSDKit

/// Viewer-side edit/toggle boundaries for the M3 nested-group display phase.
enum LayerViewerEditPolicy: Equatable, Sendable {
    case editablePixel
    case readOnly(ReadOnlyReason)

    enum ReadOnlyReason: Equatable, Sendable {
        case group
        case nestedPixel
    }

    var isEditable: Bool {
        if case .editablePixel = self { return true }
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
            return isRootLevel(path: item.path) ? .editablePixel : .editablePixel
        }
    }

    static func editPolicy(path: LayerPath, layer: any LayerProtocol) -> LayerViewerEditPolicy {
        if layer is GroupLayer {
            return .readOnly(.group)
        }
        return isRootLevel(path: path) ? .editablePixel : .editablePixel
    }

    static func canToggleVisibility(for item: LayerListItem) -> Bool {
        item.displayKind == .pixel
    }
}
