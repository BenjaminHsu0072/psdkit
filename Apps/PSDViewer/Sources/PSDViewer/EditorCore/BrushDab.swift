import CoreGraphics
import Foundation
import PSDKit

/// Brush vs eraser semantics for preview stamping. Eraser clears alpha (destination-out preview).
enum BrushStrokeMode: Equatable, Sendable {
    case brush
    case eraser
}

/// Single brush stamp in layer-local coordinates.
struct BrushDab: Equatable, Sendable {
    let center: CGPoint
    let radius: CGFloat
    /// Per-dab alpha from flow/pressure before whole-stroke opacity.
    let alpha: CGFloat
    let color: EditorColor

    var bounds: CGRect {
        CGRect(
            x: center.x - radius,
            y: center.y - radius,
            width: radius * 2,
            height: radius * 2
        )
    }
}

/// Deterministic dab sequence derived from stroke samples.
struct BrushStrokePlan: Equatable, Sendable {
    let mode: BrushStrokeMode
    let dabs: [BrushDab]
    let dirtyRegion: EditorDirtyRegion
}

/// Layer-local rasterization contract consumed by MetalBackend (no Metal types).
struct BrushRasterizationPlan: Equatable, Sendable {
    let strokePlan: BrushStrokePlan
    let layerID: String
    let layerFrame: PSDRect
    let layerPixelWidth: Int
    let layerPixelHeight: Int

    var mode: BrushStrokeMode { strokePlan.mode }
    var dabs: [BrushDab] { strokePlan.dabs }
    var dirtyRegion: EditorDirtyRegion { strokePlan.dirtyRegion }
    var dabCount: Int { strokePlan.dabs.count }
    /// Pointer samples that produced this plan (may be fewer than `dabCount`).
    let sampleCount: Int
}

/// Expands `StrokeSession` samples into a deterministic dab plan. Pure Swift; no pixel writes.
enum BrushDabPlanner {
    static let maxDabs = 4096

    static func mode(for tool: EditorTool) -> BrushStrokeMode? {
        switch tool {
        case .brush:
            return .brush
        case .eraser:
            return .eraser
        default:
            return nil
        }
    }

    static func plan(
        from session: StrokeSession,
        tool: EditorTool
    ) -> BrushRasterizationPlan? {
        guard let strokeMode = mode(for: tool) else { return nil }
        guard session.phase == .active || session.phase == .ended else { return nil }
        guard let target = session.target, !session.samples.isEmpty else { return nil }

        let layerWidth = max(target.layerFrame.width, 0)
        let layerHeight = max(target.layerFrame.height, 0)
        guard layerWidth > 0, layerHeight > 0 else { return nil }

        let brush = session.brushSnapshot
        let layerBounds = CGRect(x: 0, y: 0, width: layerWidth, height: layerHeight)
        var dabs: [BrushDab] = []
        var dirtyRegion = EditorDirtyRegion.empty

        let points = layerLocalPoints(from: session.samples, layerBounds: layerBounds)
        guard !points.isEmpty else { return nil }

        expandDabs(
            points: points,
            brush: brush,
            mode: strokeMode,
            layerBounds: layerBounds,
            into: &dabs,
            dirtyRegion: &dirtyRegion
        )

        guard !dabs.isEmpty else { return nil }

        return BrushRasterizationPlan(
            strokePlan: BrushStrokePlan(mode: strokeMode, dabs: dabs, dirtyRegion: dirtyRegion),
            layerID: target.layerID,
            layerFrame: target.layerFrame,
            layerPixelWidth: layerWidth,
            layerPixelHeight: layerHeight,
            sampleCount: session.samples.count
        )
    }

    private struct LayerLocalPoint: Equatable {
        let position: CGPoint
        let pressure: CGFloat
    }

    private static func layerLocalPoints(
        from samples: [PointerSample],
        layerBounds: CGRect
    ) -> [LayerLocalPoint] {
        samples.compactMap { sample in
            guard let local = sample.layerLocalPoint else { return nil }
            guard layerBounds.contains(local) else { return nil }
            return LayerLocalPoint(position: local, pressure: sample.pressure)
        }
    }

    private static func expandDabs(
        points: [LayerLocalPoint],
        brush: BrushSettings,
        mode: BrushStrokeMode,
        layerBounds: CGRect,
        into dabs: inout [BrushDab],
        dirtyRegion: inout EditorDirtyRegion
    ) {
        guard let first = points.first else { return }

        var distAccum: CGFloat = 0
        var through = -1

        if through < 0 {
            appendDab(
                at: first.position,
                pressure: first.pressure,
                brush: brush,
                mode: mode,
                layerBounds: layerBounds,
                into: &dabs,
                dirtyRegion: &dirtyRegion
            )
            through = 0
        }

        guard points.count > 1 else { return }

        for segment in max(through, 0) ..< points.count - 1 {
            let prev = points[segment]
            let curr = points[segment + 1]
            emitDabsAlongSegment(
                from: prev,
                to: curr,
                brush: brush,
                mode: mode,
                layerBounds: layerBounds,
                distAccum: &distAccum,
                into: &dabs,
                dirtyRegion: &dirtyRegion
            )
            if dabs.count >= maxDabs { break }
        }
    }

    private static func emitDabsAlongSegment(
        from prev: LayerLocalPoint,
        to curr: LayerLocalPoint,
        brush: BrushSettings,
        mode: BrushStrokeMode,
        layerBounds: CGRect,
        distAccum: inout CGFloat,
        into dabs: inout [BrushDab],
        dirtyRegion: inout EditorDirtyRegion
    ) {
        let dist = hypot(curr.position.x - prev.position.x, curr.position.y - prev.position.y)
        distAccum += dist

        let prevRadius = brush.radius(for: prev.pressure)
        let currRadius = brush.radius(for: curr.pressure)
        let avgRadius = (prevRadius + currRadius) / 2

        if avgRadius <= 1.5 {
            let mid = CGPoint(
                x: (prev.position.x + curr.position.x) / 2,
                y: (prev.position.y + curr.position.y) / 2
            )
            let midPressure = (prev.pressure + curr.pressure) / 2
            appendDab(
                at: mid,
                pressure: midPressure,
                brush: brush,
                mode: mode,
                layerBounds: layerBounds,
                into: &dabs,
                dirtyRegion: &dirtyRegion
            )
            distAccum = 0
            return
        }

        let spacing = brush.spacingDistance(forRadius: currRadius)
        while distAccum >= spacing, dabs.count < maxDabs {
            distAccum -= spacing
            let t = dist > 0 ? min(max(1 - distAccum / dist, 0), 1) : 1
            let pressure = prev.pressure + (curr.pressure - prev.pressure) * t
            let position = CGPoint(
                x: prev.position.x + (curr.position.x - prev.position.x) * t,
                y: prev.position.y + (curr.position.y - prev.position.y) * t
            )
            appendDab(
                at: position,
                pressure: pressure,
                brush: brush,
                mode: mode,
                layerBounds: layerBounds,
                into: &dabs,
                dirtyRegion: &dirtyRegion
            )
        }
    }

    private static func appendDab(
        at position: CGPoint,
        pressure: CGFloat,
        brush: BrushSettings,
        mode: BrushStrokeMode,
        layerBounds: CGRect,
        into dabs: inout [BrushDab],
        dirtyRegion: inout EditorDirtyRegion
    ) {
        guard dabs.count < maxDabs else { return }

        let radius = brush.radius(for: pressure)
        let dabBounds = CGRect(
            x: position.x - radius,
            y: position.y - radius,
            width: radius * 2,
            height: radius * 2
        )
        guard dabBounds.intersects(layerBounds) else { return }

        let alpha = brush.dabAlpha(for: pressure)
        let color: EditorColor
        switch mode {
        case .brush:
            color = brush.color
        case .eraser:
            color = EditorColor(red: 0, green: 0, blue: 0, alpha: 0)
        }

        dabs.append(BrushDab(center: position, radius: radius, alpha: alpha, color: color))
        dirtyRegion = dirtyRegion.union(with: clippedDirtyRegion(for: dabBounds, in: layerBounds))
    }

    private static func clippedDirtyRegion(for dabBounds: CGRect, in layerBounds: CGRect) -> EditorDirtyRegion {
        let clipped = dabBounds.intersection(layerBounds)
        guard !clipped.isNull, clipped.width > 0, clipped.height > 0 else { return .empty }
        return .unionRect(
            PSDRect(
                left: Int(floor(clipped.minX)),
                top: Int(floor(clipped.minY)),
                right: Int(ceil(clipped.maxX)),
                bottom: Int(ceil(clipped.maxY))
            )
        )
    }
}
