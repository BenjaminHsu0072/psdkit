import Foundation

struct BinaryWriter {
    private(set) var data = Data()

    mutating func write(_ bytes: Data) {
        data.append(bytes)
    }

    mutating func writeUInt8(_ value: UInt8) {
        data.append(value)
    }

    mutating func writeUInt16(_ value: UInt16) {
        data.append(UInt8((value >> 8) & 0xFF))
        data.append(UInt8(value & 0xFF))
    }

    mutating func writeInt16(_ value: Int16) {
        writeUInt16(UInt16(bitPattern: value))
    }

    mutating func writeUInt32(_ value: UInt32) {
        data.append(UInt8((value >> 24) & 0xFF))
        data.append(UInt8((value >> 16) & 0xFF))
        data.append(UInt8((value >> 8) & 0xFF))
        data.append(UInt8(value & 0xFF))
    }

    mutating func writeInt32(_ value: Int32) {
        writeUInt32(UInt32(bitPattern: value))
    }

    mutating func writeFixedString(_ string: String, length: Int) {
        var raw = Array(string.utf8.prefix(length))
        if raw.count < length {
            raw.append(contentsOf: repeatElement(0, count: length - raw.count))
        }
        data.append(contentsOf: raw.prefix(length))
    }

    mutating func writePascalString(_ string: String, padding align: Int) {
        let chars = Array(string.utf8)
        let length = min(chars.count, 255)
        writeUInt8(UInt8(length))
        if length > 0 {
            data.append(contentsOf: chars.prefix(length))
        }
        let readSoFar = 1 + length
        let pad = (align - (readSoFar % align)) % align
        if pad > 0 {
            data.append(Data(repeating: 0, count: pad))
        }
    }

    mutating func writeLengthBlockUInt32(_ payload: Data) {
        writeUInt32(UInt32(payload.count))
        write(payload)
    }

    mutating func pad(to alignment: Int) {
        let pad = (alignment - (data.count % alignment)) % alignment
        if pad > 0 {
            data.append(Data(repeating: 0, count: pad))
        }
    }
}
