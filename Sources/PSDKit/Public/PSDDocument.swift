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


    // MARK: - Create new document

    /// Creates a new 8-bit RGB PSD (version 1). Layers are ordered bottom-to-top in the array.
    /// Save/export always uses semantic encoding (`sourceData` is empty).
    public static func create(
        canvasSize: PSDSize,
        layers: [PixelLayer] = [],
        colorMode: ColorMode = .rgb
    ) throws -> PSDDocument {
        let file = try NewDocumentFactory.makeFile(
            canvasSize: canvasSize,
            layers: layers,
            colorMode: colorMode
        )
        let root = GroupLayer(name: "")
        for layer in layers {
            root.append(layer)
        }
        let doc = PSDDocument(
            canvasSize: canvasSize,
            colorMode: colorMode,
            root: root,
            rawFile: file
        )
        doc.isContentDirty = true
        return doc
    }

    public static func create(width: Int, height: Int, layers: [PixelLayer] = []) throws -> PSDDocument {
        try create(canvasSize: PSDSize(width: width, height: height), layers: layers)
    }

    /// Full-canvas solid layer for export workflows.
    public static func makeSolidLayer(
        name: String,
        canvasSize: PSDSize,
        red: UInt8,
        green: UInt8,
        blue: UInt8,
        alpha: UInt8 = 255
    ) throws -> PixelLayer {
        let count = canvasSize.width * canvasSize.height
        var rgba = Data(count: count * 4)
        rgba.withUnsafeMutableBytes { raw in
            let bytes = raw.bindMemory(to: UInt8.self)
            for i in 0 ..< count {
                bytes[i * 4] = red
                bytes[i * 4 + 1] = green
                bytes[i * 4 + 2] = blue
                bytes[i * 4 + 3] = alpha
            }
        }
        return try PixelLayer(
            name: name,
            frame: PSDRect(left: 0, top: 0, right: canvasSize.width, bottom: canvasSize.height),
            pixels: PixelBuffer(width: canvasSize.width, height: canvasSize.height, rgba: rgba)
        )
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
        let effective: PSDWriteMode = (isContentDirty || rawFile.sourceData.isEmpty) ? .semantic : writeMode
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

    /// Call after mutating layer properties in place.
    /// Merged canvas preview (RGBA8888) using normal blend, bottom-to-top.
    public func compositePreviewRGBA() -> Data {
        let layers = root.children.compactMap { $0 as? PixelLayer }
        return CompositeBuilder.compositeRGBA(canvasSize: canvasSize, layers: layers)
    }

    public func markContentModified() {
        isContentDirty = true
    }

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
