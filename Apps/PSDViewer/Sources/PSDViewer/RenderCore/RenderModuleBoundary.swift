import Foundation

// MARK: - RenderCore module boundary
//
// Allowed imports: Foundation, CoreGraphics, Metal, MetalKit, PSDKit.
// Forbidden references: DocumentModel, SwiftUI view state.
//
// Responsibilities:
// - Render input contracts (EditorRenderSnapshot, layer snapshots).
// - Snapshot building from PSDDocument (not DocumentModel).
//
// Does NOT own: save dialogs, input sampling, undo/redo UI.

enum RenderCoreModule {}
