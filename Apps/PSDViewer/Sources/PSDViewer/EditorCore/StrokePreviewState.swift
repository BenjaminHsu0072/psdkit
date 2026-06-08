import Foundation
import PSDKit

/// E5-consumable metadata produced when a stroke ends.
struct PendingStrokeCommit: Equatable, Sendable {
    let documentSessionID: UUID
    let documentRevision: UInt64
    let layerID: String
    let layerUUID: UUID?
    let layerPixelRevision: UInt64
    let mode: BrushStrokeMode
    let brushSnapshot: BrushSettings
    let rasterizationPlan: BrushRasterizationPlan
    let dabCount: Int
    let sampleCount: Int
    let dirtyRegion: EditorDirtyRegion
    let layerFrame: PSDRect
}

/// Active stroke preview contract passed to MetalBackend via render snapshot inputs.
struct ActiveStrokePreview: Equatable, Sendable {
    let plan: BrushRasterizationPlan
    let phase: StrokeSessionPhase
    let brush: BrushSettings
}

/// Observable brush preview diagnostics (testable without GPU readback).
struct StrokePreviewDiagnostics: Equatable, Sendable {
    var dabCount: Int = 0
    var dirtyRegion: EditorDirtyRegion = .empty
    var activeLayerID: String?
    var lastStrokeResult: String = ""
    var rejectionReason: String?
    var isPreviewActive: Bool = false
    var pendingCommitLayerID: String?

    static let empty = StrokePreviewDiagnostics()
}
