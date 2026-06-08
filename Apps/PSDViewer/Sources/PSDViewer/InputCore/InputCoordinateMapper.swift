import CoreGraphics
import Foundation
import PSDKit

/// Maps pointer locations through `EditorViewport` (single transform owner).
enum InputCoordinateMapper {
    static func canvasPoint(viewPoint: CGPoint, viewport: EditorViewport) -> CGPoint {
        viewport.viewToCanvas(viewPoint)
    }

    static func viewPoint(canvasPoint: CGPoint, viewport: EditorViewport) -> CGPoint {
        viewport.canvasToView(canvasPoint)
    }

    static func layerLocalPoint(canvasPoint: CGPoint, frame: PSDRect) -> CGPoint {
        CGPoint(
            x: canvasPoint.x - CGFloat(frame.left),
            y: canvasPoint.y - CGFloat(frame.top)
        )
    }

    static func canvasPoint(layerLocalPoint: CGPoint, frame: PSDRect) -> CGPoint {
        CGPoint(
            x: layerLocalPoint.x + CGFloat(frame.left),
            y: layerLocalPoint.y + CGFloat(frame.top)
        )
    }

    static func mappedPoints(
        viewPoint: CGPoint,
        viewport: EditorViewport,
        layerFrame: PSDRect?
    ) -> (canvas: CGPoint, layerLocal: CGPoint?, insideLayer: Bool?) {
        let canvas = canvasPoint(viewPoint: viewPoint, viewport: viewport)
        guard let layerFrame else {
            return (canvas, nil, nil)
        }
        let local = layerLocalPoint(canvasPoint: canvas, frame: layerFrame)
        let inside = isInsideLayer(canvasPoint: canvas, frame: layerFrame)
        return (canvas, local, inside)
    }

    static func isInsideLayer(canvasPoint: CGPoint, frame: PSDRect) -> Bool {
        canvasPoint.x >= CGFloat(frame.left)
            && canvasPoint.x < CGFloat(frame.right)
            && canvasPoint.y >= CGFloat(frame.top)
            && canvasPoint.y < CGFloat(frame.bottom)
    }

    static func isInsideLayer(layerLocalPoint: CGPoint, frame: PSDRect) -> Bool {
        layerLocalPoint.x >= 0
            && layerLocalPoint.x < CGFloat(frame.width)
            && layerLocalPoint.y >= 0
            && layerLocalPoint.y < CGFloat(frame.height)
    }

    static func makeSample(
        from event: RawPointerEvent,
        viewport: EditorViewport,
        layerFrame: PSDRect?
    ) -> PointerSample {
        let mapped = mappedPoints(viewPoint: event.viewPoint, viewport: viewport, layerFrame: layerFrame)
        return PointerSample(
            timestamp: event.timestamp,
            phase: event.phase,
            viewPoint: event.viewPoint,
            canvasPoint: mapped.canvas,
            layerLocalPoint: mapped.layerLocal,
            pressure: InputPressure.normalized(event.pressure, device: event.device),
            tilt: event.tilt,
            device: event.device,
            modifiers: event.modifiers,
            isInsideTargetLayer: mapped.insideLayer
        )
    }
}
