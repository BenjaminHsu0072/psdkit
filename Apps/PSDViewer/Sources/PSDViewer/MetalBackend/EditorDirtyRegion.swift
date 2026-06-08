import CoreGraphics
import Foundation
import PSDKit

/// Describes which portion of a layer texture is stale. E4/E5 may supply stroke rects.
enum EditorDirtyRegion: Equatable, Sendable {
    case empty
    case fullLayer
    case unionRect(PSDRect)

    var isEmpty: Bool {
        switch self {
        case .empty:
            return true
        case .fullLayer, .unionRect:
            return false
        }
    }

    /// Merges two dirty regions into a single union rect when possible.
    func union(with other: EditorDirtyRegion) -> EditorDirtyRegion {
        switch (self, other) {
        case (.empty, let rhs):
            return rhs
        case (let lhs, .empty):
            return lhs
        case (.fullLayer, _), (_, .fullLayer):
            return .fullLayer
        case (.unionRect(let lhs), .unionRect(let rhs)):
            return .unionRect(lhs.union(rhs))
        }
    }
}

private extension PSDRect {
    func union(_ other: PSDRect) -> PSDRect {
        PSDRect(
            left: min(left, other.left),
            top: min(top, other.top),
            right: max(right, other.right),
            bottom: max(bottom, other.bottom)
        )
    }
}
