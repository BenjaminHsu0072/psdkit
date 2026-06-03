import Foundation

public enum PSDWriteMode: Sendable {
    /// Return original bytes when loaded from disk (default).
    case passthrough
    /// Re-encode layer/mask and image sections from the in-memory model.
    case semantic
}

public final class PSDDocument: @unchecked Sendable {
    public let canvasSize: PSDSize
    public let colorMode: ColorMode
    public let root: GroupLayer

    var rawFile: PSDFile

    public var layers: GroupLayer { root }

    init(canvasSize: PSDSize, colorMode: ColorMode, root: GroupLayer, rawFile: PSDFile) {
        self.canvasSize = canvasSize
        self.colorMode = colorMode
        self.root = root
        self.rawFile = rawFile
    }

    public static func load(data: Data) throws -> PSDDocument {
        let file = try PSDFile.read(data: data)
        return try DocumentBuilder.makeDocument(from: file)
    }

    public static func load(url: URL) throws -> PSDDocument {
        let data = try Data(contentsOf: url)
        return try load(data: data)
    }

    public func data(writeMode: PSDWriteMode = .passthrough) throws -> Data {
        switch writeMode {
        case .passthrough:
            return try rawFile.write(passthrough: true)
        case .semantic:
            let synced = try DocumentBuilder.syncRawFile(from: self)
            return try synced.write(passthrough: false)
        }
    }

    public func save(to url: URL, writeMode: PSDWriteMode = .passthrough) throws {
        try data(writeMode: writeMode).write(to: url, options: .atomic)
    }
}
