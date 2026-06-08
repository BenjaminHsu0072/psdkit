import Foundation

// MARK: - InputCore module boundary
//
// Allowed imports: Foundation, CoreGraphics, PSDKit (layer frame only).
// Forbidden: SwiftUI, AppKit, Metal, MetalKit, PSD pixel writes.
//
// AppKit bridging lives in `StrokeInputBridge` (App Shell).

enum InputCoreModule {
    static let phase = "E3-input-sampling"
}
