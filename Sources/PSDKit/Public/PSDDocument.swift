import Foundation

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

    public func data() throws -> Data {
        try rawFile.write()
    }

    public func save(to url: URL) throws {
        try data().write(to: url, options: .atomic)
    }
}
