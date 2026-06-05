import CoreGraphics
import Foundation

enum ResizeHandle: CaseIterable, Equatable, Hashable {
    case topLeft
    case top
    case topRight
    case right
    case bottomRight
    case bottom
    case bottomLeft
    case left
}

enum PreviewCoordinateMapper {
    static func psdDelta(
        from translation: CGSize,
        imagePixelSize: CGSize,
        displayedSize: CGSize
    ) -> (dx: Int, dy: Int) {
        guard imagePixelSize.width > 0,
              imagePixelSize.height > 0,
              displayedSize.width > 0,
              displayedSize.height > 0
        else { return (0, 0) }

        let scaleX = imagePixelSize.width / displayedSize.width
        let scaleY = imagePixelSize.height / displayedSize.height
        return (
            Int((translation.width * scaleX).rounded()),
            Int((translation.height * scaleY).rounded())
        )
    }

    static func movedOrigin(
        left: Int,
        top: Int,
        translation: CGSize,
        imagePixelSize: CGSize,
        displayedSize: CGSize
    ) -> (left: Int, top: Int) {
        let delta = psdDelta(
            from: translation,
            imagePixelSize: imagePixelSize,
            displayedSize: displayedSize
        )
        return (left + delta.dx, top + delta.dy)
    }

    static func resizedFrame(
        left: Int,
        top: Int,
        width: Int,
        height: Int,
        handle: ResizeHandle,
        translation: CGSize,
        imagePixelSize: CGSize,
        displayedSize: CGSize
    ) -> (left: Int, top: Int, width: Int, height: Int) {
        let delta = psdDelta(
            from: translation,
            imagePixelSize: imagePixelSize,
            displayedSize: displayedSize
        )
        let dx = delta.dx
        let dy = delta.dy

        var newLeft = left
        var newTop = top
        var newWidth = width
        var newHeight = height

        switch handle {
        case .topLeft:
            newLeft = left + dx
            newTop = top + dy
            newWidth = width - dx
            newHeight = height - dy
        case .top:
            newTop = top + dy
            newHeight = height - dy
        case .topRight:
            newTop = top + dy
            newWidth = width + dx
            newHeight = height - dy
        case .right:
            newWidth = width + dx
        case .bottomRight:
            newWidth = width + dx
            newHeight = height + dy
        case .bottom:
            newHeight = height + dy
        case .bottomLeft:
            newLeft = left + dx
            newWidth = width - dx
            newHeight = height + dy
        case .left:
            newLeft = left + dx
            newWidth = width - dx
        }

        if newWidth < 1 {
            if handleAdjustsLeft(handle) {
                newLeft = left + width - 1
            }
            newWidth = 1
        }
        if newHeight < 1 {
            if handleAdjustsTop(handle) {
                newTop = top + height - 1
            }
            newHeight = 1
        }

        return (newLeft, newTop, newWidth, newHeight)
    }

    private static func handleAdjustsLeft(_ handle: ResizeHandle) -> Bool {
        switch handle {
        case .topLeft, .left, .bottomLeft:
            return true
        default:
            return false
        }
    }

    private static func handleAdjustsTop(_ handle: ResizeHandle) -> Bool {
        switch handle {
        case .topLeft, .top, .topRight:
            return true
        default:
            return false
        }
    }
}
