import Foundation

enum ChannelDecompressor {
    static func decompress(
        data: Data,
        compression: Compression,
        width: Int,
        height: Int,
        depth: Int = 8,
        psdVersion: Int = 1
    ) throws -> Data {
        switch compression {
        case .raw:
            let expected = width * height * depth / 8
            guard data.count >= expected else {
                throw PSDError.corruptStructure("raw channel too short: \(data.count) < \(expected)")
            }
            return data.prefix(expected)

        case .rle:
            return decodeRLE(data: data, width: width, height: height, depth: depth, version: psdVersion)

        case .zip, .zipWithPrediction:
            throw PSDError.unsupportedCompression(compression.rawValue)
        }
    }

    private static func decodeRLE(data: Data, width: Int, height: Int, depth: Int, version: Int) -> Data {
        let rowSize = max(width * depth / 8, 1)
        var reader = BinaryReader(data: data)
        var rowCounts: [UInt16] = []
        if version == 1 {
            for _ in 0 ..< height {
                if let count = try? reader.readUInt16() {
                    rowCounts.append(count)
                }
            }
        }
        var output = Data()
        output.reserveCapacity(rowSize * height)
        for count in rowCounts {
            if let rowData = try? reader.readBytes(Int(count)) {
                let decoded = PackBitsCodec.decode(rowData, size: rowSize)
                output.append(decoded)
            }
        }
        return output
    }

    static func compress(
        raw: Data,
        compression: Compression,
        width: Int,
        height: Int,
        depth: Int = 8,
        psdVersion: Int = 1
    ) throws -> Data {
        switch compression {
        case .raw:
            return raw

        case .rle:
            return encodeRLE(raw: raw, width: width, height: height, depth: depth, version: psdVersion)

        case .zip, .zipWithPrediction:
            throw PSDError.unsupportedCompression(compression.rawValue)
        }
    }

    private static func encodeRLE(raw: Data, width: Int, height: Int, depth: Int, version: Int) -> Data {
        let rowSize = max(width * depth / 8, 1)
        var writer = BinaryWriter()
        var offset = 0
        var rowPayloads: [Data] = []
        for _ in 0 ..< height {
            let row = raw.subdata(in: offset ..< min(offset + rowSize, raw.count))
            offset += rowSize
            let encoded = PackBitsCodec.encode(row)
            rowPayloads.append(encoded)
            writer.writeUInt16(UInt16(encoded.count))
        }
        for payload in rowPayloads {
            writer.write(payload)
        }
        return writer.data
    }
}
