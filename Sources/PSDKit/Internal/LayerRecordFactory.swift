import Foundation

enum LayerRecordFactory {
    /// Builds a new layer record for a pixel layer (channel layout matches psd-tools defaults).
    static func makeRecord(from pixel: PixelLayer) throws -> LayerRecord {
        let w = pixel.frame.width
        let h = pixel.frame.height
        guard w > 0, h > 0 else {
            throw PSDError.corruptStructure("cannot encode empty layer bounds")
        }

        let (r, g, b, a) = try PlanarRGBA.deinterleave(pixel.pixels.rgba, width: w, height: h)
        let maskFill = Data(repeating: 255, count: w * h)

        let channelIDs: [Int16] = [
            ChannelID.transparencyMask.rawValue,
            ChannelID.red.rawValue,
            ChannelID.green.rawValue,
            ChannelID.blue.rawValue,
            ChannelID.userLayerMask.rawValue,
        ]
        let planes: [Data] = [a, r, g, b, maskFill]

        var channelInfo: [ChannelInfo] = []
        var channelData: [Int16: Data] = [:]
        var channelCompressions: [Int16: Compression] = [:]
        for (id, plane) in zip(channelIDs, planes) {
            channelInfo.append(ChannelInfo(id: id, length: 0))
            channelData[id] = plane
            channelCompressions[id] = .rle
        }

        var extra = BinaryWriter()
        extra.writeUInt32(0)
        extra.writeUInt32(0)
        let pascal = pixel.name.allSatisfy(\.isASCII) ? pixel.name : "Lyr"
        extra.writePascalString(pascal, padding: 4)
        extra.pad(to: 2)
        var extraData = extra.data
        if !pixel.name.allSatisfy(\.isASCII) {
            extraData = LayerExtra.updateName(in: extraData, name: pixel.name)
        }

        return LayerRecord(
            top: pixel.frame.top,
            left: pixel.frame.left,
            bottom: pixel.frame.bottom,
            right: pixel.frame.right,
            channelInfo: channelInfo,
            blendMode: pixel.blendMode,
            opacity: pixel.opacity,
            clipping: .base,
            flags: LayerFlags(
                transparencyProtected: false,
                visible: pixel.isVisible,
                pixelDataIrrelevant: false
            ),
            name: pixel.name,
            extraData: extraData,
            channelData: channelData,
            channelCompressions: channelCompressions
        )
    }

    /// Builds a section divider boundary record for a group (`bounding` / `openFolder` / `closedFolder`).
    static func makeSectionRecord(
        from group: GroupLayer,
        kind: LayerExtra.SectionDividerKind
    ) -> LayerRecord {
        let type: UInt32
        switch kind {
        case .bounding: type = 3
        case .openFolder: type = 1
        case .closedFolder: type = 2
        }
        let payload = Data([
            UInt8(type >> 24), UInt8(type >> 16), UInt8(type >> 8), UInt8(type),
        ])
        var extra = BinaryWriter()
        extra.writeUInt32(0)
        extra.writeUInt32(0)
        extra.writePascalString(group.name, padding: 4)
        extra.write(encodeSectionTaggedBlock(key: "lsct", payload: payload))
        extra.pad(to: 2)

        let blendMode: BlendMode = group.blendMode == .passThrough ? .passThrough : group.blendMode
        return LayerRecord(
            top: 0,
            left: 0,
            bottom: 0,
            right: 0,
            channelInfo: [],
            blendMode: blendMode,
            opacity: group.opacity,
            clipping: .base,
            flags: LayerFlags(
                transparencyProtected: false,
                visible: group.isVisible,
                pixelDataIrrelevant: false
            ),
            name: group.name,
            extraData: extra.data,
            channelData: [:],
            channelCompressions: [:]
        )
    }

    private static func encodeSectionTaggedBlock(key: String, payload: Data) -> Data {
        var w = BinaryWriter()
        w.writeFixedString("8BIM", length: 4)
        w.writeFixedString(key, length: 4)
        w.writeUInt32(UInt32(payload.count))
        w.write(payload)
        if payload.count % 2 != 0 { w.writeUInt8(0) }
        return w.data
    }
}
