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
            return try decodeRLE(data: data, width: width, height: height, depth: depth, version: psdVersion)

        case .zip, .zipWithPrediction:
            throw PSDError.unsupportedCompression(compression.rawValue)
        }
    }

    private static func decodeRLE(data: Data, width: Int, height: Int, depth: Int, version: Int) throws -> Data {
        let rowSize = max(width * depth / 8, 1)
        var reader = BinaryReader(data: data)
        var rowCounts: [UInt16] = []
        if version == 1 {
            rowCounts.reserveCapacity(height)
            do {
                for _ in 0 ..< height {
                    rowCounts.append(try reader.readUInt16())
                }
            } catch PSDError.unexpectedEOF {
                throw PSDError.corruptStructure("RLE row count table truncated")
            }
            guard rowCounts.count == height else {
                throw PSDError.corruptStructure("RLE row count table incomplete")
            }
        }
        let totalSize = rowSize * height
        var output = Data(count: totalSize)
        var writeOffset = 0
        do {
            for count in rowCounts {
                let rowData = try reader.readBytes(Int(count))
                let written = PackBitsCodec.decode(rowData, into: &output, writeOffset: writeOffset, size: rowSize)
                guard written == rowSize else {
                    throw PSDError.corruptStructure("RLE row PackBits decode short: \(written) < \(rowSize)")
                }
                writeOffset += rowSize
            }
        } catch let error as PSDError {
            if case .unexpectedEOF = error {
                throw PSDError.corruptStructure("RLE row payload truncated")
            }
            throw error
        }
        guard writeOffset == totalSize else {
            throw PSDError.corruptStructure("RLE decoded size mismatch: \(writeOffset) < \(totalSize)")
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
        var rowPayloads: [Data] = []
        rowPayloads.reserveCapacity(height)
        raw.withUnsafeBytes { rawBytes in
            let bytes = rawBytes.bindMemory(to: UInt8.self)
            for row in 0 ..< height {
                let start = row * rowSize
                let end = min(start + rowSize, bytes.count)
                let rowBuffer = UnsafeBufferPointer(rebasing: bytes[start ..< end])
                let encoded = PackBitsCodec.encode(bytes: rowBuffer)
                rowPayloads.append(encoded)
                writer.writeUInt16(UInt16(encoded.count))
            }
        }
        for payload in rowPayloads {
            writer.write(payload)
        }
        return writer.data
    }
}
