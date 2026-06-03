import Foundation

struct LayerFlags: Equatable, Sendable {
    var transparencyProtected: Bool
    var visible: Bool
    var pixelDataIrrelevant: Bool

    static func read(from reader: inout BinaryReader) throws -> LayerFlags {
        let flags = try reader.readUInt8()
        return LayerFlags(
            transparencyProtected: flags & 1 != 0,
            visible: flags & 2 == 0,
            pixelDataIrrelevant: flags & 16 != 0
        )
    }

    func write(to writer: inout BinaryWriter) {
        var flags: UInt8 = 0
        if transparencyProtected { flags |= 1 }
        if !visible { flags |= 2 }
        flags |= 8 // photoshop 5+ later
        if pixelDataIrrelevant { flags |= 16 }
        writer.writeUInt8(flags)
    }
}

struct ChannelInfo: Equatable, Sendable {
    var id: Int16
    var length: UInt32
}

struct LayerRecord: Equatable, Sendable {
    var top: Int
    var left: Int
    var bottom: Int
    var right: Int
    var channelInfo: [ChannelInfo]
    var blendMode: BlendMode
    var opacity: UInt8
    var clipping: Clipping
    var flags: LayerFlags
    var name: String
    /// Raw extra: mask + blending ranges + name + tagged blocks (preserved for round-trip).
    var extraData: Data
    /// Decompressed planar channels keyed by channel id.
    var channelData: [Int16: Data]

    var bounds: PSDRect {
        PSDRect(left: left, top: top, right: right, bottom: bottom)
    }

    var width: Int { bounds.width }
    var height: Int { bounds.height }

    static func read(from reader: inout BinaryReader, psdVersion: Int) throws -> LayerRecord {
        let top = Int(try reader.readInt32())
        let left = Int(try reader.readInt32())
        let bottom = Int(try reader.readInt32())
        let right = Int(try reader.readInt32())
        let channelCount = Int(try reader.readUInt16())

        var channelInfo: [ChannelInfo] = []
        for _ in 0 ..< channelCount {
            let id = try reader.readInt16()
            let length: UInt32
            if psdVersion == 1 {
                length = try reader.readUInt32()
            } else {
                length = try reader.readUInt32() // PSB uses 64-bit; v1 only
            }
            channelInfo.append(ChannelInfo(id: id, length: length))
        }

        let signature = try reader.readFixedString(length: 4)
        guard signature == "8BIM" else {
            throw PSDError.corruptStructure("invalid layer blend signature")
        }
        let blendKey = try reader.readFixedString(length: 4)
        let opacity = try reader.readUInt8()
        let clippingRaw = try reader.readUInt8()
        let clipping = Clipping(rawValue: clippingRaw) ?? .base
        let flags = try LayerFlags.read(from: &reader)

        _ = try reader.readUInt8() // pad byte before extra length (psd-tools fmt "xI")
        let extraLength = Int(try reader.readUInt32())
        let extraData = try reader.readBytes(extraLength)
        var extraReader = BinaryReader(data: extraData)

        var name = ""
        if extraLength >= 4 {
            let maskPayloadLen = Int(try extraReader.readUInt32())
            if maskPayloadLen > 0 { try extraReader.skip(maskPayloadLen) }
            let blendPayloadLen = Int(try extraReader.readUInt32())
            if blendPayloadLen > 0 { try extraReader.skip(blendPayloadLen) }
            if !extraReader.isAtEnd {
                name = try extraReader.readPascalString(padding: 4)
            }
        }

        return LayerRecord(
            top: top,
            left: left,
            bottom: bottom,
            right: right,
            channelInfo: channelInfo,
            blendMode: BlendMode(fourCC: blendKey),
            opacity: opacity,
            clipping: clipping,
            flags: flags,
            name: name,
            extraData: extraData,
            channelData: [:]
        )
    }

    mutating func attachChannelPayloads(_ payloads: [Data], depth: Int, psdVersion: Int) throws {
        guard payloads.count == channelInfo.count else {
            throw PSDError.corruptStructure("channel payload count mismatch")
        }
        channelData = [:]
        for (info, payload) in zip(channelInfo, payloads) {
            guard info.length > 2 else { continue }
            var pr = BinaryReader(data: payload)
            let compressionRaw = try pr.readUInt16()
            guard let compression = Compression(rawValue: compressionRaw) else {
                throw PSDError.unsupportedCompression(compressionRaw)
            }
            let compressed = try pr.readBytes(payload.count - 2)
            let w: Int
            let h: Int
            if info.id == ChannelID.userLayerMask.rawValue || info.id == ChannelID.realUserLayerMask.rawValue {
                w = width
                h = height
            } else {
                w = width
                h = height
            }
            let raw = try ChannelDecompressor.decompress(
                data: compressed,
                compression: compression,
                width: w,
                height: h,
                depth: depth,
                psdVersion: psdVersion
            )
            channelData[info.id] = raw
        }
    }
}

struct LayerInfo: Equatable, Sendable {
    var layerCount: Int16
    var layers: [LayerRecord]
}

struct LayerAndMaskInformation: Equatable, Sendable {
    var layerInfo: LayerInfo?
    var globalMaskRaw: Data
    var taggedBlocksRaw: Data

    static func read(from reader: inout BinaryReader, psdVersion: Int, depth: Int) throws -> LayerAndMaskInformation {
        let sectionStart = reader.offset
        let sectionLength = Int(try reader.readUInt32())
        let sectionEnd = sectionStart + 4 + sectionLength
        guard sectionLength > 0 else {
            return LayerAndMaskInformation(layerInfo: nil, globalMaskRaw: Data(), taggedBlocksRaw: Data())
        }

        let layerInfoLength = Int(try reader.readUInt32())
        var layerInfo: LayerInfo?
        if layerInfoLength > 0 {
            let layerInfoEnd = reader.offset + layerInfoLength
            let layerCount = try reader.readInt16()
            let count = abs(Int(layerCount))
            var layers: [LayerRecord] = []
            for _ in 0 ..< count {
                layers.append(try LayerRecord.read(from: &reader, psdVersion: psdVersion))
            }
            for i in 0 ..< layers.count {
                var payloads: [Data] = []
                for info in layers[i].channelInfo {
                    if info.length == 0 {
                        payloads.append(Data())
                    } else if info.length == 1 {
                        _ = try? reader.readBytes(1)
                        payloads.append(Data())
                    } else {
                        payloads.append(try reader.readBytes(Int(info.length)))
                    }
                }
                try layers[i].attachChannelPayloads(payloads, depth: depth, psdVersion: psdVersion)
            }
            layerInfo = LayerInfo(layerCount: layerCount, layers: layers)
            try reader.seek(to: layerInfoEnd)
        }

        var globalMaskRaw = Data()
        if reader.offset + 4 <= sectionEnd {
            let maskLen = try reader.readUInt32()
            if maskLen > 0 {
                globalMaskRaw = try reader.readBytes(Int(maskLen))
            }
        }

        var taggedRaw = Data()
        if reader.offset < sectionEnd {
            taggedRaw = try reader.readBytes(sectionEnd - reader.offset)
        }
        try reader.seek(to: sectionEnd)

        return LayerAndMaskInformation(
            layerInfo: layerInfo,
            globalMaskRaw: globalMaskRaw,
            taggedBlocksRaw: taggedRaw
        )
    }
}

struct ImageDataSection: Equatable, Sendable {
    var compression: Compression
    var data: Data

    static func read(from reader: inout BinaryReader) throws -> ImageDataSection {
        guard !reader.isAtEnd else {
            return ImageDataSection(compression: .raw, data: Data())
        }
        let compressionRaw = try reader.readUInt16()
        guard let compression = Compression(rawValue: compressionRaw) else {
            throw PSDError.unsupportedCompression(compressionRaw)
        }
        let rest = try reader.readBytes(reader.remaining)
        return ImageDataSection(compression: compression, data: rest)
    }
}
