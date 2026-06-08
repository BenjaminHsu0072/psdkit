import CoreGraphics
import Foundation
import PSDKit

/// Single source of truth for canvas/view transforms (E1 S1-03).
/// ScrollView and other UI containers must not hold independent pan/zoom state.
struct EditorViewport: Equatable, Sendable {
    var canvasSize: CGSize
    var viewSize: CGSize
    /// View points per canvas pixel.
    var scale: CGFloat
    /// View-space position of the canvas origin (top-left).
    var translation: CGPoint

    static let minScale: CGFloat = 0.05
    static let maxScale: CGFloat = 64.0

    init(
        canvasSize: CGSize,
        viewSize: CGSize = .zero,
        scale: CGFloat = 1.0,
        translation: CGPoint = .zero
    ) {
        self.canvasSize = canvasSize
        self.viewSize = viewSize
        self.scale = scale
        self.translation = translation
    }

    init(canvasPixelSize: PSDSize, viewSize: CGSize = .zero) {
        self.init(
            canvasSize: CGSize(width: canvasPixelSize.width, height: canvasPixelSize.height),
            viewSize: viewSize
        )
    }

    static func `default`(canvasPixelSize: PSDSize) -> EditorViewport {
        EditorViewport(canvasPixelSize: canvasPixelSize)
    }

    mutating func updateViewSize(_ size: CGSize) {
        viewSize = size
    }

    mutating func fitToView(padding: CGFloat = 0) {
        guard canvasSize.width > 0, canvasSize.height > 0,
              viewSize.width > padding * 2, viewSize.height > padding * 2
        else { return }

        let availableWidth = viewSize.width - padding * 2
        let availableHeight = viewSize.height - padding * 2
        let fitScale = min(
            availableWidth / canvasSize.width,
            availableHeight / canvasSize.height
        )
        scale = clampScale(fitScale)
        translation = CGPoint(
            x: (viewSize.width - canvasSize.width * scale) / 2,
            y: (viewSize.height - canvasSize.height * scale) / 2
        )
    }

    mutating func pan(by delta: CGPoint) {
        translation.x += delta.x
        translation.y += delta.y
    }

    mutating func zoom(by factor: CGFloat, anchorInView: CGPoint) {
        guard factor > 0, factor.isFinite else { return }
        let anchorCanvas = viewToCanvas(anchorInView)
        scale = clampScale(scale * factor)
        let anchorAfterZoom = canvasToView(anchorCanvas)
        translation.x += anchorInView.x - anchorAfterZoom.x
        translation.y += anchorInView.y - anchorAfterZoom.y
    }

    func canvasToView(_ point: CGPoint) -> CGPoint {
        CGPoint(
            x: translation.x + point.x * scale,
            y: translation.y + point.y * scale
        )
    }

    func viewToCanvas(_ point: CGPoint) -> CGPoint {
        guard scale > 0 else { return .zero }
        return CGPoint(
            x: (point.x - translation.x) / scale,
            y: (point.y - translation.y) / scale
        )
    }

    func canvasRectToView(_ rect: CGRect) -> CGRect {
        let origin = canvasToView(rect.origin)
        return CGRect(
            x: origin.x,
            y: origin.y,
            width: rect.width * scale,
            height: rect.height * scale
        )
    }

    private func clampScale(_ value: CGFloat) -> CGFloat {
        min(max(value, Self.minScale), Self.maxScale)
    }
}
