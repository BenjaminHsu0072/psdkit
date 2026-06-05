import PSDKit
import SwiftUI

struct SelectedLayerFrameOverlay: View {
    @EnvironmentObject private var model: DocumentModel

    let layer: PixelLayer
    let path: LayerPath
    let imagePixelSize: CGSize
    let displayedSize: CGSize

    private enum DragKind: Equatable {
        case move
        case resize(ResizeHandle)
    }

    @State private var dragKind: DragKind?
    @State private var dragTranslation: CGSize = .zero

    var body: some View {
        let displayed = safeDisplayedSize
        let baseFrame = layer.frame
        let preview = previewFrame(baseFrame: baseFrame, displayed: displayed)
        let frameWidth = CGFloat(preview.width)
        let frameHeight = CGFloat(preview.height)

        ZStack(alignment: .topLeading) {
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
