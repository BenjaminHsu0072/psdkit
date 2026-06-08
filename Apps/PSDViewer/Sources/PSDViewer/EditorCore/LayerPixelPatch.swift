import Foundation
import PSDKit

/// RGBA8888 patch for a layer-local dirty rectangle.
struct LayerPixelPatch: Equatable, Sendable {
    let layerID: String
    let rect: PSDRect
    let rgba: Data
    let rowBytes: Int
    let pixelFormat: PixelPatchFormat
    let sourceRevision: UInt64
    let resultRevision: UInt64

    var width: Int { rect.width }
    var height: Int { rect.height }

    var expectedByteCount: Int {
        width * height * pixelFormat.bytesPerPixel
    }
}

enum PixelPatchFormat: Equatable, Sendable {
    case rgba8888

    var bytesPerPixel: Int { 4 }
}

enum PixelPatchError: Equatable, Error, Sendable {
    case layerNotFound
    case rectOutOfBounds
    case rgbaSizeMismatch
    case corruptStructure(String)
}

/// Applies layer-local RGBA patches and extracts undo inverse data.
enum PixelPatchApplier {
    static func extractPatch(
        from layer: PixelLayer,
        layerID: String,
        rect: PSDRect,
        revision: UInt64
    ) throws -> LayerPixelPatch {
        try extractPatch(
            from: layer.pixels.rgba,
            width: layer.pixels.width,
            height: layer.pixels.height,
            layerID: layerID,
            rect: rect,
            revision: revision
        )
    }

    static func extractPatch(
        from rgba: Data,
        width: Int,
        height: Int,
        layerID: String,
        rect: PSDRect,
        revision: UInt64
    ) throws -> LayerPixelPatch {
        try validate(rect: rect, width: width, height: height)
        let patchData = try copyRect(from: rgba, width: width, height: height, rect: rect)
        return LayerPixelPatch(
            layerID: layerID,
            rect: rect,
            rgba: patchData,
            rowBytes: rect.width * PixelPatchFormat.rgba8888.bytesPerPixel,
            pixelFormat: .rgba8888,
            sourceRevision: revision,
            resultRevision: revision
        )
    }

    @discardableResult
    static func apply(
        patch: LayerPixelPatch,
        to layer: PixelLayer
    ) throws -> LayerPixelPatch {
        let beforeRevision = EditorPixelRevisionDigest.digest(rgba: layer.pixels.rgba)
        let inverse = try extractPatch(
            from: layer,
            layerID: patch.layerID,
            rect: patch.rect,
            revision: beforeRevision
        )
        try validate(patch: patch, width: layer.pixels.width, height: layer.pixels.height)
        var rgba = layer.pixels.rgba
        try writeRect(patch.rgba, into: &rgba, width: layer.pixels.width, height: layer.pixels.height, rect: patch.rect)
        layer.pixels = try PixelBuffer(width: layer.pixels.width, height: layer.pixels.height, rgba: rgba)
        let afterRevision = EditorPixelRevisionDigest.digest(rgba: layer.pixels.rgba)
        return LayerPixelPatch(
            layerID: inverse.layerID,
            rect: inverse.rect,
            rgba: inverse.rgba,
            rowBytes: inverse.rowBytes,
            pixelFormat: inverse.pixelFormat,
            sourceRevision: beforeRevision,
            resultRevision: afterRevision
        )
    }

    private static func validate(rect: PSDRect, width: Int, height: Int) throws {
        guard rect.left >= 0, rect.top >= 0,
              rect.right <= width, rect.bottom <= height,
              rect.width > 0, rect.height > 0
        else {
            throw PixelPatchError.rectOutOfBounds
        }
    }

    private static func validate(patch: LayerPixelPatch, width: Int, height: Int) throws {
        try validate(rect: patch.rect, width: width, height: height)
        guard patch.rgba.count == patch.expectedByteCount else {
            throw PixelPatchError.rgbaSizeMismatch
        }
    }

    private static func copyRect(
        from rgba: Data,
        width: Int,
        height: Int,
        rect: PSDRect
    ) throws -> Data {
        var patch = Data(count: rect.width * rect.height * 4)
        for row in 0 ..< rect.height {
            let srcRow = ((rect.top + row) * width + rect.left) * 4
            let dstRow = row * rect.width * 4
            let byteCount = rect.width * 4
            patch.replaceSubrange(dstRow ..< dstRow + byteCount, with: rgba[srcRow ..< srcRow + byteCount])
        }
        return patch
    }

    private static func writeRect(
        _ patchRGBA: Data,
        into rgba: inout Data,
        width: Int,
        height: Int,
        rect: PSDRect
    ) throws {
        guard patchRGBA.count == rect.width * rect.height * 4 else {
            throw PixelPatchError.rgbaSizeMismatch
        }
        try validate(rect: rect, width: width, height: height)
        for row in 0 ..< rect.height {
            let srcRow = row * rect.width * 4
            let dstRow = ((rect.top + row) * width + rect.left) * 4
            let byteCount = rect.width * 4
            rgba.replaceSubrange(dstRow ..< dstRow + byteCount, with: patchRGBA[srcRow ..< srcRow + byteCount])
        }
    }
}

extension EditorDirtyRegion {
    func layerLocalRect(pixelWidth: Int, pixelHeight: Int) -> PSDRect? {
        switch self {
        case .empty:
            return nil
        case .fullLayer:
            guard pixelWidth > 0, pixelHeight > 0 else { return nil }
            return PSDRect(left: 0, top: 0, right: pixelWidth, bottom: pixelHeight)
        case .unionRect(let rect):
            let clamped = PSDRect(
                left: max(0, min(rect.left, pixelWidth)),
                top: max(0, min(rect.top, pixelHeight)),
                right: max(0, min(rect.right, pixelWidth)),
                bottom: max(0, min(rect.bottom, pixelHeight))
            )
            guard clamped.width > 0, clamped.height > 0 else { return nil }
            return clamped
        }
    }
}
