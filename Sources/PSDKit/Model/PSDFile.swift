import Foundation

/// Low-level PSD container (aligned with psd-tools `psd_tools.psd` + Adobe sections).
struct PSDFile: Sendable {
    var header: FileHeader
    var colorModeData: Data
    var imageResources: Data
    var layerAndMask: LayerAndMaskInformation
    var imageData: ImageDataSection
    var sourceData: Data

    static func read(data: Data) throws -> PSDFile {
        var reader = BinaryReader(data: data)
        let header = try FileHeader.read(from: &reader)
        let (_, colorModeData) = try reader.readLengthBlockUInt32()
        let (_, imageResources) = try reader.readLengthBlockUInt32()
        let layerAndMask = try LayerAndMaskInformation.read(
            from: &reader,
            psdVersion: Int(header.version),
            depth: Int(header.depth)
        )
        let imageData = try ImageDataSection.read(from: &reader)
        return PSDFile(
            header: header,
            colorModeData: colorModeData,
            imageResources: imageResources,
            layerAndMask: layerAndMask,
            imageData: imageData,
            sourceData: data
        )
    }

    func write(passthrough: Bool = true) throws -> Data {
        if passthrough, !sourceData.isEmpty {
            return sourceData
        }
        return try PSDWriter.serialize(self)
    }
}
