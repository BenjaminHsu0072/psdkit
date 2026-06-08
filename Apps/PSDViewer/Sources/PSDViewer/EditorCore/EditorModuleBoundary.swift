import Foundation

// MARK: - EditorCore module boundary
//
// Allowed imports: Foundation, CoreGraphics, PSDKit.
// Forbidden imports: SwiftUI, AppKit, Metal, MetalKit.
//
// Responsibilities:
// - Editor state (tool, selection, brush settings).
// - Command protocol and dispatcher.
// - Document adapter for PSDKit mutation without UI or save dialogs.
//
// Does NOT own: rendering, input sampling, file save UI, Metal textures.

enum EditorCoreModule {}
