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
    private(set) var isContentDirty = false

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
        let effective: PSDWriteMode = isContentDirty ? .semantic : writeMode
        switch effective {
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

    // MARK: - Layer editing (phase 4)

    public func appendPixelLayer(_ layer: PixelLayer) throws {
        root.append(layer)
        var file = rawFile
        if file.layerAndMask.layerInfo == nil {
            file.layerAndMask.layerInfo = LayerInfo(layerCount: 0, layers: [])
        }
        guard var layerInfo = file.layerAndMask.layerInfo else {
            throw PSDError.corruptStructure("missing layer info")
        }
        let record = try LayerRecordFactory.makeRecord(from: layer)
        layerInfo.layers.append(record)
        layerInfo.layerCount = Int16(layerInfo.layers.count)
        file.layerAndMask.layerInfo = layerInfo
        rawFile = file
        isContentDirty = true
    }

    public func removePixelLayer(_ layer: PixelLayer) throws {
        guard let childIndex = root.children.firstIndex(where: { ($0 as? PixelLayer)?.id == layer.id }) else {
            return
        }
        root.remove(layer)
        guard var layerInfo = rawFile.layerAndMask.layerInfo else { return }

        var pixelRecordIndex = 0
        var removeAt: Int?
        for (i, record) in layerInfo.layers.enumerated() {
            guard record.width > 0, record.height > 0 else { continue }
            if pixelRecordIndex == childIndex {
                removeAt = i
                break
            }
            pixelRecordIndex += 1
        }
        if let removeAt {
            layerInfo.layers.remove(at: removeAt)
            layerInfo.layerCount = Int16(layerInfo.layers.count)
            rawFile.layerAndMask.layerInfo = layerInfo
            isContentDirty = true
        }
    }
}
