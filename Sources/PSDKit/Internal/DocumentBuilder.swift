import Foundation

enum DocumentBuilder {
    static func makeDocument(from file: PSDFile) throws -> PSDDocument {
        var collector = CompatibilityIssueCollector()
        let root = GroupLayer(name: "")
        guard let layerInfo = file.layerAndMask.layerInfo else {
            return PSDDocument(
                canvasSize: file.header.canvasSize,
                colorMode: file.header.colorMode,
                root: root,
                rawFile: file,
                compatibilityReport: collector.report
            )
        }

        // psd-tools iteration order: index 0 = bottom of stack.
        try LayerTreeBuilder.build(
            records: layerInfo.layers,
            into: root,
            collector: &collector,
            makePixelLayer: makePixelLayer
        )

        return PSDDocument(
            canvasSize: file.header.canvasSize,
            colorMode: file.header.colorMode,
            root: root,
            rawFile: file,
            compatibilityReport: collector.report
        )
    }

    /// Rebuilds layer channel planes from public `PixelLayer` values (semantic write).
    static func syncRawFile(from document: PSDDocument) throws -> PSDFile {
        var file = document.rawFile
        let treePixels = LayerTreeFlattener.collectPixels(in: document.root)
        let treeHasGroups = LayerTreeFlattener.containsGroupLayers(in: document.root)

        if file.layerAndMask.layerInfo == nil {
            if treePixels.isEmpty, !treeHasGroups {
                file.imageData = try CompositeBuilder.buildImageData(
                    canvasSize: document.canvasSize,
                    layers: [],
                    compression: file.imageData.compression,
                    depth: Int(file.header.depth),
                    psdVersion: Int(file.header.version)
                )
                return file
            }
            let records = try flattenLayerRecords(from: document, templatePixels: [])
            file.layerAndMask.layerInfo = LayerInfo(layerCount: Int16(records.count), layers: records)
        } else {
            guard var layerInfo = file.layerAndMask.layerInfo else {
                throw PSDError.corruptStructure("no layer info to sync")
            }

            let templatePixels = layerInfo.layers.filter { $0.width > 0 && $0.height > 0 }
            if !treeHasGroups, treePixels.count != templatePixels.count {
                throw PSDError.corruptStructure(
                    "pixel layer count \(treePixels.count) != record count \(templatePixels.count)"
                )
            }

            let mergeTemplates = canMergeTemplates(
                treePixels: treePixels,
                templatePixels: templatePixels
            )
            let records = try flattenLayerRecords(
                from: document,
                templatePixels: mergeTemplates ? templatePixels : []
            )
            layerInfo.layers = records
            layerInfo.layerCount = Int16(records.count)
            file.layerAndMask.layerInfo = layerInfo
        }

        file.imageData = try CompositeBuilder.buildImageData(
            canvasSize: document.canvasSize,
            layers: treePixels,
            compression: file.imageData.compression,
            depth: Int(file.header.depth),
            psdVersion: Int(file.header.version)
        )
        return file
    }

    /// True when flattened pixel order matches on-disk templates (name and bounds per index).
    private static func canMergeTemplates(
        treePixels: [PixelLayer],
        templatePixels: [LayerRecord]
    ) -> Bool {
        guard treePixels.count == templatePixels.count else { return false }
        for (pixel, template) in zip(treePixels, templatePixels) {
            let templateName = template.name.isEmpty ? "Layer" : template.name
            guard template.width == pixel.frame.width,
                  template.height == pixel.frame.height,
                  templateName == pixel.name
            else {
                return false
            }
        }
        return true
    }

    private static func flattenLayerRecords(
        from document: PSDDocument,
        templatePixels: [LayerRecord]
    ) throws -> [LayerRecord] {
        var pixelTemplateIndex = 0

        return try LayerTreeFlattener.flatten(
            group: document.root,
            makePixelRecord: { pixel in
                if pixelTemplateIndex < templatePixels.count {
                    let merged = try merge(pixel: pixel, into: templatePixels[pixelTemplateIndex])
                    pixelTemplateIndex += 1
                    return merged
                }
                return try LayerRecordFactory.makeRecord(from: pixel)
            },
            makeSectionRecord: { group, kind in
                LayerRecordFactory.makeSectionRecord(from: group, kind: kind)
            }
        )
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
        record.extraData = LayerExtra.updateName(in: template.extraData, name: pixel.name)

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

    private static func makePixelLayer(
        from record: LayerRecord,
        collector: inout CompatibilityIssueCollector
    ) throws -> PixelLayer? {
        guard record.width > 0, record.height > 0 else { return nil }
        guard LayerExtra.hasEditableRGBChannels(in: record) else { return nil }
        let red = record.channelData[ChannelID.red.rawValue]!
        let green = record.channelData[ChannelID.green.rawValue]!
        let blue = record.channelData[ChannelID.blue.rawValue]!
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
        let layerName = record.name.isEmpty ? "Layer" : record.name
        if LayerExtra.hasUnsupportedUserMask(in: record) {
            collector.recordUnsupportedMask(layerName: layerName)
        }
        if LayerExtra.hasUnsupportedLayerEffect(in: record.extraData) {
            collector.recordUnsupportedLayerEffect(layerName: layerName)
        }
        var blendMode = record.blendMode
        if !blendMode.isSupportedForPixelLayer {
            collector.recordUnsupportedBlendMode(layerName: layerName)
            blendMode = .normal
        }
        return PixelLayer(
            name: layerName,
            frame: record.bounds,
            pixels: buffer,
            isVisible: record.flags.visible,
            opacity: record.opacity,
            blendMode: blendMode
        )
    }
}
