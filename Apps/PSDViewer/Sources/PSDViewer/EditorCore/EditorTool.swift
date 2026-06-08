import Foundation

/// Describes the active editor tool. Does not handle input events.
enum EditorTool: Equatable, Sendable, CaseIterable {
    case inspect
    case moveLayer
    case brush
    case eraser
    case hand
    case zoom
}
