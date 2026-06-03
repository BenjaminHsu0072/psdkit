import Foundation

enum DocumentBuilder {
    static func makeDocument(from file: PSDFile) throws -> PSDDocument {
        let root = GroupLayer(name: "")
        guard let layerInfo = file.layerAndMask.layerInfo else {
            return PSDDocument(
                canvasSize: file.header.canvasSize,
                colorMode: file.header.colorMode,
                root: root,
                rawFile: file
            )
        }

        // psd-tools iteration order: index 0 = bottom of stack.
        for record in layerInfo.layers {
            guard let pixel = try makePixelLayer(from: record) else { continue }
            root.append(pixel)
        }

        return PSDDocument(
            canvasSize: file.header.canvasSize,
            colorMode: file.header.colorMode,
            root: root,
            rawFile: file
        )
    }

    private static func makePixelLayer(from record: LayerRecord) throws -> PixelLayer? {
        guard record.width > 0, record.height > 0 else { return nil }
        guard let red = record.channelData[0],
              let green = record.channelData[1],
              let blue = record.channelData[2]
        else {
            return nil
        }
        let alpha = record.channelData[ChannelID.transparencyMask.rawValue]
        let rgba = try PlanarRGBA.interleave(
            red: red,
            green: green,
            blue: blue,
            alpha: alpha,
            width: record.width,
            height: record.height
        )
        let buffer = try PixelBuffer(width: record.width, height: record.height, rgba: rgba)
        return PixelLayer(
            name: record.name.isEmpty ? "Layer" : record.name,
            frame: record.bounds,
            pixels: buffer,
            isVisible: record.flags.visible,
            opacity: record.opacity,
            blendMode: record.blendMode
        )
    }
}
