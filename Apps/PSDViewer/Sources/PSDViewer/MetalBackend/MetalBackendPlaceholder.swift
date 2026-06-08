import Foundation

// MARK: - MetalBackend module boundary
//
// Allowed imports: Foundation, CoreGraphics, Metal, MetalKit, QuartzCore, RenderCore types, PSDKit (blend enums only).
// Forbidden: PSD file save, SwiftUI, DocumentModel.
//
// E1: read-only Metal preview renderer and shaders.
// E2: layer texture cache, invalidation, and diagnostics.

enum MetalBackendModule {
    static let phase = "E2-layer-texture-cache"
}
