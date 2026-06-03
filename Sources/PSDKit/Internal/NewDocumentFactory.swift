import Foundation

enum NewDocumentFactory {
    static func makeFile(
        canvasSize: PSDSize,
        layers: [PixelLayer],
        colorMode: ColorMode = .rgb
    ) throws -> PSDFile {
        guard canvasSize.width > 0, canvasSize.height > 0 else {
            throw PSDError.corruptStructure("canvas size must be positive")
        }
        guard colorMode == .rgb else {
            throw PSDError.unsupportedColorMode(colorMode.rawValue)
        }

        var records: [LayerRecord] = []
        for layer in layers {
            records.append(try LayerRecordFactory.makeRecord(from: layer))
        }

        let layerInfo: LayerInfo? = records.isEmpty
            ? nil
            : LayerInfo(layerCount: Int16(records.count), layers: records)

        let imageData = try CompositeBuilder.buildImageData(
            canvasSize: canvasSize,
            layers: layers,
            compression: .raw,
            depth: 8,
            psdVersion: 1
        )

        return PSDFile(
            header: FileHeader.newRGB(width: canvasSize.width, height: canvasSize.height, channels: 3),
            colorModeData: Data(),
            imageResources: Data(),
            layerAndMask: LayerAndMaskInformation(
                layerInfo: layerInfo,
                globalMaskRaw: Data(),
                taggedBlocksRaw: Data()
            ),
            imageData: imageData,
            sourceData: Data()
        )
    }
}
