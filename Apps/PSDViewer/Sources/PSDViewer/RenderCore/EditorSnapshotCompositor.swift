import Foundation
import PSDKit

enum EditorSnapshotCompositeError: Error, Equatable {
    case unsupportedBlendMode(BlendMode)
}

/// Integer-accurate snapshot compositor matching PSDKit `CompositeBuilder` semantics.
/// Serves as Metal shader reference and automated regression tests for normal/multiply/add.
enum EditorSnapshotCompositor {
    private static let alphaScale = 65_025
    private static let alphaRoundBias = alphaScale / 2

    static func compositeRGBA(
        snapshot: EditorRenderSnapshot,
        pixels: EditorSnapshotPixelProvider,
        background: (r: UInt8, g: UInt8, b: UInt8, a: UInt8) = (255, 255, 255, 255)
    ) throws -> Data {
        if let unsupported = EditorPreviewBlendSupport.firstUnsupportedBlend(in: snapshot) {
            throw EditorSnapshotCompositeError.unsupportedBlendMode(unsupported)
        }
        let width = snapshot.canvasSize.width
        let height = snapshot.canvasSize.height
        let count = width * height
        var canvas = [UInt8](repeating: 0, count: count * 4)
        for index in 0 ..< count {
            let base = index * 4
            canvas[base] = background.r
            canvas[base + 1] = background.g
            canvas[base + 2] = background.b
            canvas[base + 3] = background.a
        }

        let orderedLayers = snapshot.layers
            .filter { $0.kind == .pixel && $0.isVisible }
            .sorted { $0.stackOrder < $1.stackOrder }

        for layer in orderedLayers {
            guard let payload = pixels.rgba(for: layer) else { continue }
            compositeLayer(
                layer: layer,
                rgba: payload.data,
                pixelWidth: payload.width,
                pixelHeight: payload.height,
                into: &canvas,
                canvasWidth: width,
                canvasHeight: height
            )
        }
        return Data(canvas)
    }

    private static func compositeLayer(
        layer: EditorLayerSnapshot,
        rgba: Data,
        pixelWidth: Int,
        pixelHeight: Int,
        into canvas: inout [UInt8],
        canvasWidth: Int,
        canvasHeight: Int
    ) {
        let layerW = layer.frame.width
        let layerH = layer.frame.height
        guard layerW > 0, layerH > 0, pixelWidth == layerW, pixelHeight == layerH else { return }

        let layerOpacity = layer.opacity
        let blendMode = layer.blendMode
        let frameLeft = layer.frame.left
        let frameTop = layer.frame.top

        let clipLeft = max(0, frameLeft)
        let clipRight = min(canvasWidth, frameLeft + layerW)
        let clipTop = max(0, frameTop)
        let clipBottom = min(canvasHeight, frameTop + layerH)
        guard clipLeft < clipRight, clipTop < clipBottom else { return }

        let pixelBytes = layerW * layerH * 4
        rgba.withUnsafeBytes { raw in
            guard raw.count >= pixelBytes else { return }
            let pixels = raw.bindMemory(to: UInt8.self)

            for cy in clipTop ..< clipBottom {
                let y = cy - frameTop
                let srcRow = y * layerW * 4
                let dstRow = cy * canvasWidth * 4
                for cx in clipLeft ..< clipRight {
                    let x = cx - frameLeft
                    let sourceIndex = srcRow + x * 4
                    let destinationIndex = dstRow + cx * 4

                    let pixelAlpha = pixels[sourceIndex + 3]
                    let effective = Int(pixelAlpha) * Int(layerOpacity)
                    let inverseEffective = alphaScale - effective

                    for channel in 0 ..< 3 {
                        let source = pixels[sourceIndex + channel]
                        let destination = canvas[destinationIndex + channel]
                        let blended = blendChannel(source: source, destination: destination, mode: blendMode)
                        let value = Int(blended) * effective + Int(destination) * inverseEffective + alphaRoundBias
                        canvas[destinationIndex + channel] = UInt8(clamping: value / alphaScale)
                    }
                    let alphaValue = Int(pixelAlpha) * Int(layerOpacity) * 255
                        + Int(canvas[destinationIndex + 3]) * inverseEffective + alphaRoundBias
                    canvas[destinationIndex + 3] = UInt8(clamping: alphaValue / alphaScale)
                }
            }
        }
    }

    static func blendChannel(source: UInt8, destination: UInt8, mode: BlendMode) -> UInt8 {
        switch mode {
        case .normal:
            return source
        case .multiply:
            return UInt8((Int(source) * Int(destination) + 127) / 255)
        case .add:
            return UInt8(min(255, Int(source) + Int(destination)))
        case .passThrough, .unknown:
            return source
        }
    }
}
