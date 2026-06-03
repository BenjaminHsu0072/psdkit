import Foundation

struct BinaryReader {
    private let data: Data
    private(set) var offset: Int = 0

    init(data: Data) {
        self.data = data
    }

    var remaining: Int { data.count - offset }
    var isAtEnd: Bool { offset >= data.count }

    mutating func seek(to position: Int) throws {
        guard position >= 0, position <= data.count else {
            throw PSDError.corruptStructure("seek out of range: \(position)")
        }
        offset = position
    }

    mutating func skip(_ count: Int) throws {
        guard count >= 0, offset + count <= data.count else {
            throw PSDError.unexpectedEOF
        }
        offset += count
    }

    mutating func readBytes(_ count: Int) throws -> Data {
        guard count >= 0, offset + count <= data.count else {
            throw PSDError.unexpectedEOF
        }
        let slice = data.subdata(in: offset ..< offset + count)
        offset += count
        return slice
    }

    mutating func readUInt8() throws -> UInt8 {
        let bytes = try readBytes(1)
        return bytes[bytes.startIndex]
    }

    mutating func readUInt16() throws -> UInt16 {
        let bytes = try readBytes(2)
        return UInt16(bytes[bytes.startIndex]) << 8 | UInt16(bytes[bytes.startIndex + 1])
    }

    mutating func readInt16() throws -> Int16 {
        Int16(bitPattern: try readUInt16())
    }

    mutating func readUInt32() throws -> UInt32 {
        let bytes = try readBytes(4)
        var value: UInt32 = 0
        for byte in bytes {
            value = (value << 8) | UInt32(byte)
        }
        return value
    }

    mutating func readInt32() throws -> Int32 {
        Int32(bitPattern: try readUInt32())
    }

    mutating func readFixedString(length: Int) throws -> String {
        let raw = try readBytes(length)
        return String(decoding: raw, as: UTF8.self)
    }

    mutating func readLengthBlockUInt32() throws -> (length: UInt32, payload: Data) {
        let length = try readUInt32()
        let payload = try readBytes(Int(length))
        return (length, payload)
    }

    mutating func readPascalString(padding align: Int) throws -> String {
        let length = Int(try readUInt8())
        let chars = length > 0 ? try readBytes(length) : Data()
        let readSoFar = 1 + length
        let pad = (align - (readSoFar % align)) % align
        if pad > 0 { try skip(pad) }
        return String(chars.map { Character(UnicodeScalar($0)) })
    }
}
