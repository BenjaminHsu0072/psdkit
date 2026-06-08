import CoreGraphics
import Foundation
import PSDKit

enum EditorLayerKind: Equatable, Sendable {
    case pixel
    case group
}

/// Describes how a renderer obtains pixel data for a layer.
enum EditorPixelSource: Equatable, Sendable {
    case none
    case documentLayerUUID(UUID)
    case rgbaData(data: Data, width: Int, height: Int)
}

struct EditorLayerSnapshot: Equatable, Sendable, Identifiable {
    let id: String
    let layerUUID: UUID
    let name: String
    let kind: EditorLayerKind
    let depth: Int
    /// Global stack order: 0 = bottom of document.
    let stackOrder: Int
    let frame: PSDRect
    let isVisible: Bool
    let opacity: UInt8
    let blendMode: BlendMode
    /// Per-layer pixel revision. E0 uses RGBA digest; PSDKit has no native revision field.
    let pixelRevision: UInt64
    let pixelSource: EditorPixelSource
}

struct EditorRenderSnapshot: Equatable, Sendable {
    let canvasSize: PSDSize
    let layers: [EditorLayerSnapshot]
    /// Stable identity for the loaded document session; unchanged across property edits.
    let documentSessionID: UUID
    let documentRevision: UInt64
    let selectedLayerID: String?
    let viewport: EditorViewport
}
