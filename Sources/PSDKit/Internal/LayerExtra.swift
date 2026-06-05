import Foundation

/// Parses and updates layer record extra data (mask, blending ranges, Pascal name, tagged blocks).
enum LayerExtra {
    private static let blockSignature = "8BIM"
    private static let unicodeNameKey = "luni"

    /// Tagged block keys for Photoshop layer effects / styles (mid-term unsupported).
    static let layerEffectTaggedBlockKeys: Set<String> = ["lfx2", "lrFX"]

    /// Section divider / group boundary (M3).
    static let sectionDividerTaggedBlockKeys: Set<String> = ["lsct", "lsdk"]

    /// Parsed section divider type from `lsct` / `lsdk` payload (psd-tools `SectionDivider` values).
    enum SectionDividerKind: Equatable, Sendable {
        case bounding
        case openFolder
        case closedFolder
    }

    private static let sectionDividerOpenFolder: UInt32 = 1
    private static let sectionDividerClosedFolder: UInt32 = 2
    private static let sectionDividerBounding: UInt32 = 3

    /// Text layer markers (mid-term dropped).
    static let textLayerTaggedBlockKeys: Set<String> = ["TySh", "Txt "]

    /// Smart Object markers (mid-term dropped).
    static let smartObjectTaggedBlockKeys: Set<String> = ["SoLd", "PlLd"]

    /// Common adjustment-layer markers (mid-term dropped).
    static let adjustmentLayerTaggedBlockKeys: Set<String> = [
        "brit", "levl", "curv", "hue ", "hue2", "blnc", "nvrt", "thrs", "grdm", "selc", "mixr", "phfl",
    ]

    static func unicodeName(from extraData: Data) -> String? {
        guard let (_, _, _, tagged) = splitExtra(extraData) else { return nil }
        for block in parseTaggedBlocks(tagged) where block.key == unicodeNameKey {
            return decodeUnicodeString(block.payload)
        }
        return nil
    }

    /// Whether the record carries a user layer mask beyond the default Photoshop stub.
    static func hasUnsupportedUserMask(in record: LayerRecord) -> Bool {
        if record.channelInfo.contains(where: {
            $0.id == ChannelID.realUserLayerMask.rawValue && $0.length > 2
        }) {
            return true
        }
        guard let (mask, _, _, _) = splitExtra(record.extraData), !mask.isEmpty else {
            return false
        }
        if mask.count > 20 { return true }
        guard mask.count == 20 else { return false }
        let flags = mask[17]
        return flags & 0x08 != 0 || flags & 0x10 != 0
    }

    static func hasUnsupportedLayerEffect(in extraData: Data) -> Bool {
        guard let (_, _, _, tagged) = splitExtra(extraData) else { return false }
        return parseTaggedBlocks(tagged).contains { layerEffectTaggedBlockKeys.contains($0.key) }
    }

    /// Explicit unsupported layer kinds from tagged blocks (checked before silent skip).
    static func explicitUnsupportedLayerKindLabel(for record: LayerRecord) -> String? {
        let keys = Set(taggedBlockKeys(in: record.extraData))
        if !keys.isDisjoint(with: textLayerTaggedBlockKeys) { return "text" }
        if !keys.isDisjoint(with: smartObjectTaggedBlockKeys) { return "smart object" }
        if !keys.isDisjoint(with: adjustmentLayerTaggedBlockKeys) { return "adjustment" }
        return nil
    }

    /// Section divider kind when the record carries a recognized `lsct` / `lsdk` payload.
    static func sectionDividerKind(for record: LayerRecord) -> SectionDividerKind? {
        guard let payload = sectionDividerPayload(from: record.extraData) else { return nil }
        guard payload.count >= 4 else { return nil }
        let bytes = [UInt8](payload.prefix(4))
        let type = readUInt32BE(bytes, 0)
        switch type {
        case sectionDividerOpenFolder: return .openFolder
        case sectionDividerClosedFolder: return .closedFolder
        case sectionDividerBounding: return .bounding
        default: return nil
        }
    }

    /// Records that should be skipped without compatibility issues (unknown zero-size stubs).
    static func shouldSilentlySkipLayerRecord(_ record: LayerRecord) -> Bool {
        if explicitUnsupportedLayerKindLabel(for: record) != nil { return false }
        if sectionDividerKind(for: record) != nil { return false }
        return record.width == 0 && record.height == 0
    }

    private static func sectionDividerPayload(from extraData: Data) -> Data? {
        guard let (_, _, _, tagged) = splitExtra(extraData) else { return nil }
        for block in parseTaggedBlocks(tagged) where sectionDividerTaggedBlockKeys.contains(block.key) {
            return block.payload
        }
        return nil
    }

    static func hasEditableRGBChannels(in record: LayerRecord) -> Bool {
        guard record.width > 0, record.height > 0 else { return false }
        guard let red = record.channelData[ChannelID.red.rawValue],
              let green = record.channelData[ChannelID.green.rawValue],
              let blue = record.channelData[ChannelID.blue.rawValue]
        else {
            return false
        }
        return !red.isEmpty && !green.isEmpty && !blue.isEmpty
    }

    /// Label for dropped-layer reporting from missing RGB; explicit kinds use `explicitUnsupportedLayerKindLabel`.
    static func droppedLayerKindLabel(for record: LayerRecord) -> String? {
        if let explicit = explicitUnsupportedLayerKindLabel(for: record) { return explicit }
        if shouldSilentlySkipLayerRecord(record) { return nil }
        if record.width > 0, record.height > 0, !hasEditableRGBChannels(in: record) {
            return "non-pixel"
        }
        return nil
    }

    static func taggedBlockKeys(in extraData: Data) -> [String] {
        guard let (_, _, _, tagged) = splitExtra(extraData) else { return [] }
        return parseTaggedBlocks(tagged).map(\.key)
    }

    static func updateName(in extraData: Data, name: String) -> Data {
        guard let (mask, blend, pascalName, tagged) = splitExtra(extraData) else {
            return extraData
        }
        var blocks = parseTaggedBlocks(tagged)
        blocks.removeAll { $0.key == unicodeNameKey }
        blocks.append((unicodeNameKey, encodeUnicodeString(name)))
        return assembleExtra(mask: mask, blend: blend, pascalName: pascalName, taggedBlocks: blocks)
    }

    // MARK: - Layout

    private static func splitExtra(_ extraData: Data) -> (mask: Data, blend: Data, pascalName: String, tagged: Data)? {
        var reader = BinaryReader(data: extraData)
        let maskLen = Int((try? reader.readUInt32()) ?? 0)
        let mask = (try? reader.readBytes(maskLen)) ?? Data()
        let blendLen = Int((try? reader.readUInt32()) ?? 0)
        let blend = (try? reader.readBytes(blendLen)) ?? Data()
        let pascalName = (try? reader.readPascalString(padding: 4)) ?? ""
        let tagged = (try? reader.readBytes(reader.remaining)) ?? Data()
        return (mask, blend, pascalName, tagged)
    }

    private static func assembleExtra(
        mask: Data,
        blend: Data,
        pascalName: String,
        taggedBlocks: [(key: String, payload: Data)]
    ) -> Data {
        var w = BinaryWriter()
        w.writeUInt32(UInt32(mask.count))
        if !mask.isEmpty { w.write(mask) }
        w.writeUInt32(UInt32(blend.count))
        if !blend.isEmpty { w.write(blend) }
        w.writePascalString(pascalName, padding: 4)
        for block in taggedBlocks {
            w.write(encodeTaggedBlock(key: block.key, payload: block.payload))
        }
        w.pad(to: 2)
        return w.data
    }

    // MARK: - Tagged blocks

    private static func parseTaggedBlocks(_ data: Data) -> [(key: String, payload: Data)] {
        var blocks: [(String, Data)] = []
        var offset = 0
        let bytes = [UInt8](data)
        while offset + 12 <= bytes.count {
            guard String(bytes: bytes[offset ..< offset + 4], encoding: .ascii) == blockSignature else { break }
            let key = String(bytes: bytes[offset + 4 ..< offset + 8], encoding: .ascii) ?? ""
            let length = Int(readUInt32BE(bytes, offset + 8))
            offset += 12
            guard offset + length <= bytes.count else { break }
            let payload = Data(bytes[offset ..< offset + length])
            offset += length
            if length % 2 != 0, offset < bytes.count { offset += 1 }
            blocks.append((key, payload))
        }
        return blocks
    }

    private static func encodeTaggedBlock(key: String, payload: Data) -> Data {
        var w = BinaryWriter()
        w.writeFixedString(blockSignature, length: 4)
        w.writeFixedString(key, length: 4)
        w.writeUInt32(UInt32(payload.count))
        w.write(payload)
        if payload.count % 2 != 0 { w.writeUInt8(0) }
        return w.data
    }

    private static func encodeUnicodeString(_ value: String) -> Data {
        let utf16 = Array(value.utf16)
        var w = BinaryWriter()
        w.writeUInt32(UInt32(utf16.count))
        for unit in utf16 { w.writeUInt16(unit) }
        if (4 + utf16.count * 2) % 2 != 0 { w.writeUInt8(0) }
        return w.data
    }

    private static func decodeUnicodeString(_ payload: Data) -> String? {
        guard payload.count >= 4 else { return nil }
        var reader = BinaryReader(data: payload)
        let count = Int((try? reader.readUInt32()) ?? 0)
        guard count >= 0, reader.remaining >= count * 2 else { return nil }
        var units = [UInt16]()
        units.reserveCapacity(count)
        for _ in 0 ..< count {
            guard let unit = try? reader.readUInt16() else { return nil }
            units.append(unit)
        }
        return String(utf16CodeUnits: units, count: units.count)
    }

    private static func readUInt32BE(_ bytes: [UInt8], _ offset: Int) -> UInt32 {
        UInt32(bytes[offset]) << 24 | UInt32(bytes[offset + 1]) << 16
            | UInt32(bytes[offset + 2]) << 8 | UInt32(bytes[offset + 3])
    }
}
