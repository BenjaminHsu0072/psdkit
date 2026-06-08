import AppKit
import MetalKit
import SwiftUI

/// SwiftUI bridge for read-only Metal preview (default E1 preview path).
struct EditorMetalPreviewView: NSViewRepresentable {
    let snapshot: EditorRenderSnapshot
    let pixels: EditorSnapshotPixelProvider
    @Binding var viewport: EditorViewport
    var activeTool: EditorTool = .inspect
    var strokePreview: ActiveStrokePreview?
    var strokePreviewRevision: UInt64 = 0
    var onRawPointerEvent: ((RawPointerEvent) -> Void)?
    var onDrawError: ((Error) -> Void)?

    func makeNSView(context: Context) -> EditorMetalPreviewHostView {
        let view = EditorMetalPreviewHostView()
        view.configure(renderer: context.coordinator.renderer)
        view.onDrawError = onDrawError
        return view
    }

    func updateNSView(_ nsView: EditorMetalPreviewHostView, context: Context) {
        nsView.snapshot = snapshot
        nsView.pixels = pixels
        nsView.viewport = viewport
        nsView.activeTool = activeTool
        nsView.strokePreview = strokePreview
        nsView.strokePreviewRevision = strokePreviewRevision
        nsView.onViewportChanged = { viewport = $0 }
        nsView.onRawPointerEvent = onRawPointerEvent
        nsView.onDrawError = onDrawError
        nsView.requestMetalRedraw()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    @MainActor
    final class Coordinator {
        let renderer: EditorMetalRenderer?

        init() {
            renderer = try? EditorMetalRenderer.makeDefault()
        }
    }
}

/// AppKit host for MTKView. Keeps viewport as the sole transform owner.
final class EditorMetalPreviewHostView: NSView {
    var snapshot: EditorRenderSnapshot?
    var pixels: EditorSnapshotPixelProvider = EditorSnapshotPixelProvider()
    var viewport: EditorViewport = EditorViewport(canvasSize: .zero)
    var activeTool: EditorTool = .inspect
    var strokePreview: ActiveStrokePreview?
    var strokePreviewRevision: UInt64 = 0
    var onViewportChanged: ((EditorViewport) -> Void)?
    var onRawPointerEvent: ((RawPointerEvent) -> Void)?
    var onDrawError: ((Error) -> Void)?

    private var metalView: MTKView?
    private var lastReportedDrawErrorKey: String?
    private var renderer: EditorMetalRenderer?
    private var trackingArea: NSTrackingArea?
    private var isPanning = false
    private var lastPanLocation: CGPoint?

    override var acceptsFirstResponder: Bool { true }

    func configure(renderer: EditorMetalRenderer?) {
        self.renderer = renderer
        subviews.forEach { $0.removeFromSuperview() }
        metalView = nil

        guard let renderer else {
            needsDisplay = true
            return
        }

        let view = MTKView(frame: bounds, device: renderer.device)
        view.autoresizingMask = [.width, .height]
        view.colorPixelFormat = .bgra8Unorm
        view.clearColor = MTLClearColor(red: 0.18, green: 0.18, blue: 0.18, alpha: 1)
        view.isPaused = true
        view.enableSetNeedsDisplay = true
        view.delegate = self
        addSubview(view)
        metalView = view
        syncViewSize()
    }

    override func layout() {
        super.layout()
        syncViewSize()
        requestMetalRedraw()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea {
            removeTrackingArea(trackingArea)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.activeInKeyWindow, .mouseMoved, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        if shouldPan(for: event) {
            isPanning = true
            lastPanLocation = convert(event.locationInWindow, from: nil)
            return
        }
        forwardPointerEvent(event, phase: .began)
    }

    override func mouseDragged(with event: NSEvent) {
        if isPanning, let lastPanLocation {
            let current = convert(event.locationInWindow, from: nil)
            var next = viewport
            next.pan(by: CGPoint(x: current.x - lastPanLocation.x, y: current.y - lastPanLocation.y))
            viewport = next
            onViewportChanged?(next)
            self.lastPanLocation = current
            requestMetalRedraw()
            return
        }
        forwardPointerEvent(event, phase: .moved)
    }

    override func mouseUp(with event: NSEvent) {
        if isPanning {
            isPanning = false
            lastPanLocation = nil
            return
        }
        forwardPointerEvent(event, phase: .ended)
    }

    override func tabletPoint(with event: NSEvent) {
        let phase: PointerSamplePhase
        switch event.phase {
        case .began:
            phase = .began
        case .ended, .cancelled:
            phase = .ended
        default:
            phase = .moved
        }
        forwardPointerEvent(event, phase: phase)
    }

    override func rightMouseDown(with event: NSEvent) {
        forwardPointerEvent(event, phase: .cancelled)
    }

    private func shouldPan(for event: NSEvent) -> Bool {
        activeTool == .hand || event.modifierFlags.contains(.option)
    }

    private func forwardPointerEvent(_ event: NSEvent, phase: PointerSamplePhase) {
        guard snapshot != nil else { return }
        let viewPoint = convert(event.locationInWindow, from: nil)
        let raw = StrokeInputBridge.rawEvent(from: event, phase: phase, viewPoint: viewPoint)
        onRawPointerEvent?(raw)
    }

    override func scrollWheel(with event: NSEvent) {
        guard snapshot != nil else { return }
        var next = viewport
        if event.modifierFlags.contains(.command) || event.hasPreciseScrollingDeltas {
            let anchor = convert(event.locationInWindow, from: nil)
            let factor = exp(-event.scrollingDeltaY * 0.01)
            next.zoom(by: factor, anchorInView: anchor)
        } else {
            next.pan(by: CGPoint(x: event.scrollingDeltaX, y: -event.scrollingDeltaY))
        }
        viewport = next
        onViewportChanged?(next)
        requestMetalRedraw()
    }

    override func magnify(with event: NSEvent) {
        guard snapshot != nil else { return }
        var next = viewport
        let anchor = convert(event.locationInWindow, from: nil)
        next.zoom(by: 1.0 + event.magnification, anchorInView: anchor)
        viewport = next
        onViewportChanged?(next)
        requestMetalRedraw()
    }

    func requestMetalRedraw() {
        guard let metalView else { return }
        metalView.setNeedsDisplay(metalView.bounds)
    }

    private func syncViewSize() {
        guard viewport.viewSize != bounds.size else { return }
        var next = viewport
        next.updateViewSize(bounds.size)
        if next.scale == 1, next.translation == .zero, bounds.width > 0, bounds.height > 0 {
            next.fitToView(padding: 24)
        }
        viewport = next
        onViewportChanged?(next)
    }
}

extension EditorMetalPreviewHostView: MTKViewDelegate {
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        syncViewSize()
    }

    func draw(in view: MTKView) {
        guard let renderer,
              let snapshot,
              let drawable = view.currentDrawable
        else { return }

        do {
            try renderer.draw(
                snapshot: snapshot,
                pixels: pixels,
                viewport: viewport,
                strokePreview: strokePreview,
                into: drawable
            )
            lastReportedDrawErrorKey = nil
        } catch {
            let errorKey = String(reflecting: error)
            guard lastReportedDrawErrorKey != errorKey else { return }
            lastReportedDrawErrorKey = errorKey
            fputs("EditorMetalPreviewHostView draw failed: \(error)\n", stderr)
            onDrawError?(error)
        }
    }
}
