import Foundation

struct FileHeader: Equatable, Sendable {
    static let signature = "8BPS"
    static let fixedSize = 26

    var version: UInt16
    var channels: UInt16
    var height: Int
    var width: Int
    var depth: UInt16
    var colorMode: ColorMode

    var canvasSize: PSDSize {
        PSDSize(width: width, height: height)
    }

    static func read(from reader: inout BinaryReader) throws -> FileHeader {
        let sig = try reader.readFixedString(length: 4)
        guard sig == signature else {
            throw PSDError.invalidSignature
        }
        let version = try reader.readUInt16()
        guard version == 1 else {
            throw PSDError.unsupportedVersion(Int(version))
        }
        try reader.skip(6)
        let channels = try reader.readUInt16()
        let height = Int(try reader.readUInt32())
        let width = Int(try reader.readUInt32())
        let depth = try reader.readUInt16()
        guard depth == 8 else {
            throw PSDError.unsupportedBitDepth(Int(depth))
        }
        let colorModeRaw = try reader.readUInt16()
        guard let colorMode = ColorMode(rawValue: colorModeRaw) else {
            throw PSDError.unsupportedColorMode(colorModeRaw)
        }
        guard colorMode == .rgb else {
            throw PSDError.unsupportedColorMode(colorModeRaw)
        }
        return FileHeader(
            version: version,
            channels: channels,
            height: height,
            width: width,
            depth: depth,
            colorMode: colorMode
        )
    }

    func write(to writer: inout BinaryWriter) {
        writer.writeFixedString(Self.signature, length: 4)
        writer.writeUInt16(version)
        writer.write(Data(repeating: 0, count: 6))
        writer.writeUInt16(channels)
        writer.writeUInt32(UInt32(height))
        writer.writeUInt32(UInt32(width))
        writer.writeUInt16(depth)
        writer.writeUInt16(colorMode.rawValue)
    }

    static func newRGB(width: Int, height: Int, channels: UInt16 = 4) -> FileHeader {
        FileHeader(
            version: 1,
            channels: channels,
            height: height,
            width: width,
            depth: 8,
            colorMode: .rgb
        )
    }
}

public struct PSDSize: Sendable, Equatable {
    public var width: Int
    public var height: Int

    public init(width: Int, height: Int) {
        self.width = width
        self.height = height
    }
}

public struct PSDRect: Sendable, Equatable {
    public var left: Int
    public var top: Int
    public var right: Int
    public var bottom: Int

    public var width: Int { max(right - left, 0) }
    public var height: Int { max(bottom - top, 0) }

    public init(left: Int, top: Int, right: Int, bottom: Int) {
        self.left = left
        self.top = top
        self.right = right
        self.bottom = bottom
    }
}
