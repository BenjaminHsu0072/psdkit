import Foundation

enum PSDWriter {
    static func serialize(_ file: PSDFile) throws -> Data {
        var writer = BinaryWriter()
        file.header.write(to: &writer)
        writer.writeLengthBlockUInt32(file.colorModeData)
        writer.writeLengthBlockUInt32(file.imageResources)
        try writeLayerAndMask(
            file.layerAndMask,
            psdVersion: Int(file.header.version),
            depth: Int(file.header.depth),
            to: &writer
        )
        try writeImageData(file.imageData, to: &writer)
        return writer.data
    }

    private static func writeImageData(_ section: ImageDataSection, to writer: inout BinaryWriter) throws {
        writer.writeUInt16(section.compression.rawValue)
        writer.write(section.data)
    }

    private static func writeLayerAndMask(
        _ section: LayerAndMaskInformation,
        psdVersion: Int,
        depth: Int,
        to writer: inout BinaryWriter
    ) throws {
        var sectionWriter = BinaryWriter()
        if let layerInfo = section.layerInfo {
            let prepared = try layerInfo.layers.map {
                try prepareChannelPayloads(for: $0, depth: depth, psdVersion: psdVersion)
            }
            var layerInfoWriter = BinaryWriter()
            layerInfoWriter.writeInt16(layerInfo.layerCount)
            for prep in prepared {
                writeLayerRecord(prep.record, psdVersion: psdVersion, to: &layerInfoWriter)
            }
            for prep in prepared {
                for payload in prep.payloads {
                    if payload.isEmpty { continue }
                    layerInfoWriter.write(payload)
                }
            }
            sectionWriter.writeLengthBlockUInt32(layerInfoWriter.data)
        } else {
            sectionWriter.writeUInt32(0)
        }

        if section.globalMaskRaw.isEmpty {
            sectionWriter.writeUInt32(0)
        } else {
            sectionWriter.writeUInt32(UInt32(section.globalMaskRaw.count))
            sectionWriter.write(section.globalMaskRaw)
        }
        sectionWriter.write(section.taggedBlocksRaw)

        writer.writeLengthBlockUInt32(sectionWriter.data)
    }

    private struct PreparedLayer {
        var record: LayerRecord
        var payloads: [Data]
    }

    private static func prepareChannelPayloads(
        for record: LayerRecord,
        depth: Int,
        psdVersion: Int
    ) throws -> PreparedLayer {
        var updated = record
        var payloads: [Data] = []
        var infos = record.channelInfo

        for (index, info) in infos.enumerated() {
            if info.length == 0, record.channelData[info.id] == nil {
                payloads.append(Data())
                continue
            }
            if info.length == 1, record.channelData[info.id] == nil {
                payloads.append(Data([0]))
                infos[index].length = 1
                continue
            }

            let raw: Data
            if let existing = record.channelData[info.id] {
                raw = existing
            } else if info.id == ChannelID.userLayerMask.rawValue || info.id == ChannelID.realUserLayerMask.rawValue {
                let fill = record.width * record.height
                raw = Data(repeating: 255, count: fill)
            } else {
                throw PSDError.corruptStructure("missing channel data for id \(info.id)")
            }

            let compression = record.channelCompressions[info.id] ?? .rle
            let compressed = try ChannelDecompressor.compress(
                raw: raw,
                compression: compression,
                width: record.width,
                height: record.height,
                depth: depth,
                psdVersion: psdVersion
            )
            var payloadWriter = BinaryWriter()
            payloadWriter.writeUInt16(compression.rawValue)
            payloadWriter.write(compressed)
            let payload = payloadWriter.data
            payloads.append(payload)
            infos[index].length = UInt32(payload.count)
        }

        updated.channelInfo = infos
        return PreparedLayer(record: updated, payloads: payloads)
    }

    private static func writeLayerRecord(
        _ record: LayerRecord,
        psdVersion: Int,
        to writer: inout BinaryWriter
    ) {
        writer.writeInt32(Int32(record.top))
        writer.writeInt32(Int32(record.left))
        writer.writeInt32(Int32(record.bottom))
        writer.writeInt32(Int32(record.right))
        writer.writeUInt16(UInt16(record.channelInfo.count))
        for info in record.channelInfo {
            writer.writeInt16(info.id)
            if psdVersion == 1 {
                writer.writeUInt32(info.length)
            } else {
                writer.writeUInt32(info.length)
            }
        }
        writer.writeFixedString("8BIM", length: 4)
        writer.writeFixedString(record.blendMode.fourCC, length: 4)
        writer.writeUInt8(record.opacity)
        writer.writeUInt8(record.clipping.rawValue)
        record.flags.write(to: &writer)
        writer.writeUInt8(0)
        writer.writeUInt32(UInt32(record.extraData.count))
        writer.write(record.extraData)
    }
}
