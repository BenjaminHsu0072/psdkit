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

    /// Rebuilds layer channel planes from public `PixelLayer` values (semantic write).
    static func syncRawFile(from document: PSDDocument) throws -> PSDFile {
        var file = document.rawFile
        guard var layerInfo = file.layerAndMask.layerInfo else {
            throw PSDError.corruptStructure("no layer info to sync")
        }

        let pixels = document.root.children.compactMap { $0 as? PixelLayer }
        let templates = layerInfo.layers.filter { $0.width > 0 && $0.height > 0 }
        guard pixels.count == templates.count else {
            throw PSDError.corruptStructure(
                "pixel layer count \(pixels.count) != record count \(templates.count)"
            )
        }

        var updatedLayers: [LayerRecord] = []
        for (pixel, template) in zip(pixels, templates) {
            updatedLayers.append(try merge(pixel: pixel, into: template))
        }

        layerInfo.layers = replacePixelRecords(
            in: layerInfo.layers,
            pixelRecords: updatedLayers
        )
        file.layerAndMask.layerInfo = layerInfo
        return file
    }

    private static func replacePixelRecords(
        in layers: [LayerRecord],
        pixelRecords: [LayerRecord]
    ) -> [LayerRecord] {
        var result: [LayerRecord] = []
        var pixelIndex = 0
        for layer in layers {
            if layer.width > 0, layer.height > 0, pixelIndex < pixelRecords.count {
                result.append(pixelRecords[pixelIndex])
                pixelIndex += 1
            } else {
                result.append(layer)
            }
        }
        return result
    }

    private static func merge(pixel: PixelLayer, into template: LayerRecord) throws -> LayerRecord {
        var record = template
        record.top = pixel.frame.top
        record.left = pixel.frame.left
        record.bottom = pixel.frame.bottom
        record.right = pixel.frame.right
        record.name = pixel.name
        record.opacity = pixel.opacity
        record.flags.visible = pixel.isVisible
        record.blendMode = pixel.blendMode

        let (r, g, b, a) = try PlanarRGBA.deinterleave(
            pixel.pixels.rgba,
            width: pixel.frame.width,
            height: pixel.frame.height
        )
        record.channelData[ChannelID.red.rawValue] = r
        record.channelData[ChannelID.green.rawValue] = g
        record.channelData[ChannelID.blue.rawValue] = b
        record.channelData[ChannelID.transparencyMask.rawValue] = a

        for info in record.channelInfo {
            let id = info.id
            if id == ChannelID.red.rawValue || id == ChannelID.green.rawValue
                || id == ChannelID.blue.rawValue || id == ChannelID.transparencyMask.rawValue
            {
                continue
            }
            if record.channelData[id] == nil, info.length > 2 {
                let fill = pixel.frame.width * pixel.frame.height
                record.channelData[id] = Data(repeating: 255, count: fill)
            }
        }

        return record
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
