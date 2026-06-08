import Foundation
import PSDKit

/// Builds renderer input from PSDDocument. Does not import SwiftUI or reference DocumentModel.
enum EditorRenderSnapshotBuilder {
    static func build(
        from document: PSDDocument,
        documentSessionID: UUID = UUID(),
        documentRevision: UInt64,
        selectedLayerID: String? = nil,
        viewport: EditorViewport? = nil
    ) -> EditorRenderSnapshot {
        var layers: [EditorLayerSnapshot] = []
        var stackOrder = 0
        collectLayers(
            from: document.root,
            pathPrefix: [],
            inheritedVisible: true,
            inheritedOpacity: 255,
            stackOrder: &stackOrder,
            into: &layers
        )
        return EditorRenderSnapshot(
            canvasSize: document.canvasSize,
            layers: layers,
            documentSessionID: documentSessionID,
            documentRevision: documentRevision,
            selectedLayerID: selectedLayerID,
            viewport: viewport ?? .default(canvasPixelSize: document.canvasSize)
        )
    }

    private static func collectLayers(
        from group: GroupLayer,
        pathPrefix: [Int],
        inheritedVisible: Bool,
        inheritedOpacity: UInt8,
        stackOrder: inout Int,
        into layers: inout [EditorLayerSnapshot]
    ) {
        let effectiveParentVisible = inheritedVisible && group.isVisible
        let parentOpacity = combineOpacity(inheritedOpacity, group.opacity)

        for (index, child) in group.children.enumerated() {
            let path = LayerPath(indices: pathPrefix + [index])
            let depth = pathPrefix.count
            if let pixel = child as? PixelLayer {
                let effectiveOpacity = combineOpacity(parentOpacity, pixel.opacity)
                layers.append(
                    EditorLayerSnapshot(
                        id: path.selectionID,
                        layerUUID: pixel.id,
                        name: pixel.name,
                        kind: .pixel,
                        depth: depth,
                        stackOrder: stackOrder,
                        frame: pixel.frame,
                        isVisible: effectiveParentVisible && pixel.isVisible,
                        opacity: effectiveOpacity,
                        blendMode: pixel.blendMode,
                        pixelRevision: pixelRevisionDigest(for: pixel),
                        pixelSource: .documentLayerUUID(pixel.id)
                    )
                )
                stackOrder += 1
            } else if let nested = child as? GroupLayer {
                layers.append(
                    EditorLayerSnapshot(
                        id: path.selectionID,
                        layerUUID: nested.id,
                        name: nested.name,
                        kind: .group,
                        depth: depth,
                        stackOrder: stackOrder,
                        frame: nested.frame,
                        isVisible: nested.isVisible,
                        opacity: nested.opacity,
                        blendMode: nested.blendMode,
                        pixelRevision: 0,
                        pixelSource: .none
                    )
                )
                stackOrder += 1
                collectLayers(
                    from: nested,
                    pathPrefix: path.indices,
                    inheritedVisible: effectiveParentVisible,
                    inheritedOpacity: parentOpacity,
                    stackOrder: &stackOrder,
                    into: &layers
                )
            }
        }
    }

    private static func combineOpacity(_ lhs: UInt8, _ rhs: UInt8) -> UInt8 {
        UInt8((Int(lhs) * Int(rhs) + 127) / 255)
    }

    private static func pixelRevisionDigest(for pixel: PixelLayer) -> UInt64 {
        EditorPixelRevisionDigest.digest(rgba: pixel.pixels.rgba)
    }
}
