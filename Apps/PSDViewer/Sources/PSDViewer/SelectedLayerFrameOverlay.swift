import PSDKit
import SwiftUI

/// Layer frame overlay. Uses `EditorViewport` on the Metal preview path (single transform owner).
/// CPU fallback keeps legacy image-size mapping via `imagePixelSize` / `displayedSize`.
struct SelectedLayerFrameOverlay: View {
    @EnvironmentObject private var model: DocumentModel

    let layer: PixelLayer
    let path: LayerPath
    private let viewport: EditorViewport?
    private let imagePixelSize: CGSize
    private let displayedSize: CGSize

    init(layer: PixelLayer, path: LayerPath, viewport: EditorViewport) {
        self.layer = layer
        self.path = path
        self.viewport = viewport
        self.imagePixelSize = viewport.canvasSize
        self.displayedSize = viewport.canvasSize
    }

    init(layer: PixelLayer, path: LayerPath, imagePixelSize: CGSize, displayedSize: CGSize) {
        self.layer = layer
        self.path = path
        self.viewport = nil
        self.imagePixelSize = imagePixelSize
        self.displayedSize = displayedSize
    }

    private enum DragKind: Equatable {
        case move
        case resize(ResizeHandle)
    }

    @State private var dragKind: DragKind?
    @State private var dragTranslation: CGSize = .zero

    var body: some View {
        if let viewport {
            viewportBody(viewport: viewport)
        } else {
            legacyBody
        }
    }

    private func viewportBody(viewport: EditorViewport) -> some View {
        let baseFrame = layer.frame
        let preview = previewFrame(baseFrame: baseFrame, viewport: viewport)
        let viewRect = viewport.canvasRectToView(
            CGRect(
                x: preview.left,
                y: preview.top,
                width: preview.width,
                height: preview.height
            )
        )

        return ZStack(alignment: .topLeading) {
            Rectangle()
                .strokeBorder(Color.accentColor, lineWidth: 2)
                .background(Color.accentColor.opacity(0.08))
                .frame(width: viewRect.width, height: viewRect.height)
                .position(x: viewRect.midX, y: viewRect.midY)
                .contentShape(Rectangle())
                .gesture(moveGesture(baseFrame: baseFrame, viewport: viewport))

            ForEach(ResizeHandle.allCases, id: \.self) { handle in
                viewportResizeHandle(
                    handle: handle,
                    preview: preview,
                    baseFrame: baseFrame,
                    viewport: viewport
                )
            }
        }
        .frame(width: viewport.viewSize.width, height: viewport.viewSize.height, alignment: .topLeading)
        .onChange(of: model.selectedLayerID) { _ in
            resetDragState()
        }
        .onChange(of: model.documentRevision) { _ in
            if dragKind != nil {
                resetDragState()
            }
        }
    }

    private var legacyBody: some View {
        let displayed = safeDisplayedSize
        let baseFrame = layer.frame
        let preview = previewFrame(baseFrame: baseFrame, displayed: displayed)
        let frameWidth = CGFloat(preview.width)
        let frameHeight = CGFloat(preview.height)

        return ZStack(alignment: .topLeading) {
            Rectangle()
                .strokeBorder(Color.accentColor, lineWidth: 2)
                .background(Color.accentColor.opacity(0.08))
                .frame(width: frameWidth, height: frameHeight)
                .position(
                    x: CGFloat(preview.left) + frameWidth / 2,
                    y: CGFloat(preview.top) + frameHeight / 2
                )
                .contentShape(Rectangle())
                .gesture(moveGesture(baseFrame: baseFrame, displayed: displayed))

            ForEach(ResizeHandle.allCases, id: \.self) { handle in
                resizeHandle(
                    handle: handle,
                    preview: preview,
                    baseFrame: baseFrame,
                    displayed: displayed
                )
            }
        }
        .frame(width: displayed.width, height: displayed.height, alignment: .topLeading)
        .onChange(of: model.selectedLayerID) { _ in
            resetDragState()
        }
        .onChange(of: model.documentRevision) { _ in
            if dragKind != nil {
                resetDragState()
            }
        }
    }

    private var safeDisplayedSize: CGSize {
        CGSize(
            width: max(1, displayedSize.width),
            height: max(1, displayedSize.height)
        )
    }

    private func previewFrame(
        baseFrame: PSDRect,
        viewport: EditorViewport
    ) -> (left: Int, top: Int, width: Int, height: Int) {
        guard let dragKind, dragTranslation != .zero else {
            return (
                baseFrame.left,
                baseFrame.top,
                baseFrame.width,
                baseFrame.height
            )
        }

        switch dragKind {
        case .move:
            let delta = canvasDelta(from: dragTranslation, viewport: viewport)
            return (
                baseFrame.left + delta.dx,
                baseFrame.top + delta.dy,
                baseFrame.width,
                baseFrame.height
            )
        case .resize(let handle):
            return viewportResizedFrame(
                left: baseFrame.left,
                top: baseFrame.top,
                width: baseFrame.width,
                height: baseFrame.height,
                handle: handle,
                translation: dragTranslation,
                viewport: viewport
            )
        }
    }

    private func canvasDelta(from translation: CGSize, viewport: EditorViewport) -> (dx: Int, dy: Int) {
        guard viewport.scale > 0 else { return (0, 0) }
        return (
            Int((translation.width / viewport.scale).rounded()),
            Int((translation.height / viewport.scale).rounded())
        )
    }

    private func viewportResizedFrame(
        left: Int,
        top: Int,
        width: Int,
        height: Int,
        handle: ResizeHandle,
        translation: CGSize,
        viewport: EditorViewport
    ) -> (left: Int, top: Int, width: Int, height: Int) {
        let delta = canvasDelta(from: translation, viewport: viewport)
        return PreviewCoordinateMapper.resizedFrame(
            left: left,
            top: top,
            width: width,
            height: height,
            handle: handle,
            translation: CGSize(width: CGFloat(delta.dx), height: CGFloat(delta.dy)),
            imagePixelSize: viewport.canvasSize,
            displayedSize: viewport.canvasSize
        )
    }

    private func viewportHandlePosition(
        _ handle: ResizeHandle,
        preview: (left: Int, top: Int, width: Int, height: Int),
        viewport: EditorViewport
    ) -> CGPoint {
        let viewRect = viewport.canvasRectToView(
            CGRect(
                x: preview.left,
                y: preview.top,
                width: preview.width,
                height: preview.height
            )
        )
        let left = viewRect.minX
        let top = viewRect.minY
        let right = viewRect.maxX
        let bottom = viewRect.maxY
        let midX = viewRect.midX
        let midY = viewRect.midY

        switch handle {
        case .topLeft:
            return CGPoint(x: left, y: top)
        case .top:
            return CGPoint(x: midX, y: top)
        case .topRight:
            return CGPoint(x: right, y: top)
        case .right:
            return CGPoint(x: right, y: midY)
        case .bottomRight:
            return CGPoint(x: right, y: bottom)
        case .bottom:
            return CGPoint(x: midX, y: bottom)
        case .bottomLeft:
            return CGPoint(x: left, y: bottom)
        case .left:
            return CGPoint(x: left, y: midY)
        }
    }

    private func viewportResizeHandle(
        handle: ResizeHandle,
        preview: (left: Int, top: Int, width: Int, height: Int),
        baseFrame: PSDRect,
        viewport: EditorViewport
    ) -> some View {
        let point = viewportHandlePosition(handle, preview: preview, viewport: viewport)

        return ZStack {
            Color.clear
                .frame(width: 20, height: 20)
            RoundedRectangle(cornerRadius: 2)
                .fill(Color.white)
                .overlay(
                    RoundedRectangle(cornerRadius: 2)
                        .strokeBorder(Color.accentColor, lineWidth: 1.5)
                )
                .frame(width: 10, height: 10)
        }
        .position(x: point.x, y: point.y)
        .highPriorityGesture(resizeGesture(handle: handle, baseFrame: baseFrame, viewport: viewport))
    }

    private func moveGesture(baseFrame: PSDRect, viewport: EditorViewport) -> some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { value in
                dragKind = .move
                dragTranslation = value.translation
            }
            .onEnded { value in
                let delta = canvasDelta(from: value.translation, viewport: viewport)
                model.setLayerFrame(
                    at: path,
                    left: baseFrame.left + delta.dx,
                    top: baseFrame.top + delta.dy,
                    width: baseFrame.width,
                    height: baseFrame.height
                )
                resetDragState()
            }
    }

    private func resizeGesture(
        handle: ResizeHandle,
        baseFrame: PSDRect,
        viewport: EditorViewport
    ) -> some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                dragKind = .resize(handle)
                dragTranslation = value.translation
            }
            .onEnded { value in
                let frame = viewportResizedFrame(
                    left: baseFrame.left,
                    top: baseFrame.top,
                    width: baseFrame.width,
                    height: baseFrame.height,
                    handle: handle,
                    translation: value.translation,
                    viewport: viewport
                )
                model.setLayerFrame(
                    at: path,
                    left: frame.left,
                    top: frame.top,
                    width: frame.width,
                    height: frame.height
                )
                resetDragState()
            }
    }

    private func previewFrame(
        baseFrame: PSDRect,
        displayed: CGSize
    ) -> (left: Int, top: Int, width: Int, height: Int) {
        guard let dragKind, dragTranslation != .zero else {
            return (
                baseFrame.left,
                baseFrame.top,
                baseFrame.width,
                baseFrame.height
            )
        }

        switch dragKind {
        case .move:
            let origin = PreviewCoordinateMapper.movedOrigin(
                left: baseFrame.left,
                top: baseFrame.top,
                translation: dragTranslation,
                imagePixelSize: imagePixelSize,
                displayedSize: displayed
            )
            return (origin.left, origin.top, baseFrame.width, baseFrame.height)
        case .resize(let handle):
            return PreviewCoordinateMapper.resizedFrame(
                left: baseFrame.left,
                top: baseFrame.top,
                width: baseFrame.width,
                height: baseFrame.height,
                handle: handle,
                translation: dragTranslation,
                imagePixelSize: imagePixelSize,
                displayedSize: displayed
            )
        }
    }

    private func handlePosition(
        _ handle: ResizeHandle,
        preview: (left: Int, top: Int, width: Int, height: Int)
    ) -> CGPoint {
        let left = CGFloat(preview.left)
        let top = CGFloat(preview.top)
        let right = left + CGFloat(preview.width)
        let bottom = top + CGFloat(preview.height)
        let midX = left + CGFloat(preview.width) / 2
        let midY = top + CGFloat(preview.height) / 2

        switch handle {
        case .topLeft:
            return CGPoint(x: left, y: top)
        case .top:
            return CGPoint(x: midX, y: top)
        case .topRight:
            return CGPoint(x: right, y: top)
        case .right:
            return CGPoint(x: right, y: midY)
        case .bottomRight:
            return CGPoint(x: right, y: bottom)
        case .bottom:
            return CGPoint(x: midX, y: bottom)
        case .bottomLeft:
            return CGPoint(x: left, y: bottom)
        case .left:
            return CGPoint(x: left, y: midY)
        }
    }

    private func resizeHandle(
        handle: ResizeHandle,
        preview: (left: Int, top: Int, width: Int, height: Int),
        baseFrame: PSDRect,
        displayed: CGSize
    ) -> some View {
        let point = handlePosition(handle, preview: preview)

        return ZStack {
            Color.clear
                .frame(width: 20, height: 20)
            RoundedRectangle(cornerRadius: 2)
                .fill(Color.white)
                .overlay(
                    RoundedRectangle(cornerRadius: 2)
                        .strokeBorder(Color.accentColor, lineWidth: 1.5)
                )
                .frame(width: 10, height: 10)
        }
        .position(x: point.x, y: point.y)
        .highPriorityGesture(resizeGesture(handle: handle, baseFrame: baseFrame, displayed: displayed))
    }

    private func moveGesture(baseFrame: PSDRect, displayed: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { value in
                dragKind = .move
                dragTranslation = value.translation
            }
            .onEnded { value in
                let origin = PreviewCoordinateMapper.movedOrigin(
                    left: baseFrame.left,
                    top: baseFrame.top,
                    translation: value.translation,
                    imagePixelSize: imagePixelSize,
                    displayedSize: displayed
                )
                model.setLayerFrame(
                    at: path,
                    left: origin.left,
                    top: origin.top,
                    width: baseFrame.width,
                    height: baseFrame.height
                )
                resetDragState()
            }
    }

    private func resizeGesture(
        handle: ResizeHandle,
        baseFrame: PSDRect,
        displayed: CGSize
    ) -> some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                dragKind = .resize(handle)
                dragTranslation = value.translation
            }
            .onEnded { value in
                let frame = PreviewCoordinateMapper.resizedFrame(
                    left: baseFrame.left,
                    top: baseFrame.top,
                    width: baseFrame.width,
                    height: baseFrame.height,
                    handle: handle,
                    translation: value.translation,
                    imagePixelSize: imagePixelSize,
                    displayedSize: displayed
                )
                model.setLayerFrame(
                    at: path,
                    left: frame.left,
                    top: frame.top,
                    width: frame.width,
                    height: frame.height
                )
                resetDragState()
            }
    }

    private func resetDragState() {
        dragKind = nil
        dragTranslation = .zero
    }
}
