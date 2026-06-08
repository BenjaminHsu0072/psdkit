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
    public let compatibilityReport: PSDCompatibilityReport

    var rawFile: PSDFile
    private(set) var isContentDirty = false
    public var hasUnsavedChanges: Bool { isContentDirty }

    public var layers: GroupLayer { root }

    init(
        canvasSize: PSDSize,
        colorMode: ColorMode,
        root: GroupLayer,
        rawFile: PSDFile,
        compatibilityReport: PSDCompatibilityReport = .empty
    ) {
        self.canvasSize = canvasSize
        self.colorMode = colorMode
        self.root = root
        self.rawFile = rawFile
        self.compatibilityReport = compatibilityReport
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

    /// Creates a new document from an in-memory layer tree. Requires semantic save before sharing.
    public static func create(
        canvasSize: PSDSize,
        root: GroupLayer,
        colorMode: ColorMode = .rgb
    ) throws -> PSDDocument {
        guard canvasSize.width > 0, canvasSize.height > 0 else {
            throw PSDError.corruptStructure("canvas size must be positive")
        }
        guard colorMode == .rgb else {
            throw PSDError.unsupportedColorMode(colorMode.rawValue)
        }
        let file = PSDFile(
            header: FileHeader.newRGB(width: canvasSize.width, height: canvasSize.height, channels: 3),
            colorModeData: Data(),
            imageResources: Data(),
            layerAndMask: LayerAndMaskInformation(
                layerInfo: LayerInfo(layerCount: 0, layers: []),
                globalMaskRaw: Data(),
                taggedBlocksRaw: Data()
            ),
            imageData: ImageDataSection(compression: .raw, data: Data()),
            sourceData: Data()
        )
        let doc = PSDDocument(
            canvasSize: canvasSize,
            colorMode: colorMode,
            root: root,
            rawFile: file
        )
        doc.markContentModified()
        return doc
    }

    /// Builds a PSD from pre-rendered layer RGBA buffers (e.g. pipeline output files).
    public static func create(
        canvasSize: PSDSize,
        exportedLayers: [LayerRGBAInput],
        colorMode: ColorMode = .rgb
    ) throws -> PSDDocument {
        let layers = try exportedLayers.map { try makePixelLayer(from: $0) }
        return try create(canvasSize: canvasSize, layers: layers, colorMode: colorMode)
    }

    public static func create(
        width: Int,
        height: Int,
        exportedLayers: [LayerRGBAInput]
    ) throws -> PSDDocument {
        try create(canvasSize: PSDSize(width: width, height: height), exportedLayers: exportedLayers)
    }

    /// Public standard document for manual validation and midterm round-trip checks.
    ///
    /// Tree shape:
    /// BG -> Group A(Red, Group B(Glow)) -> Top(hidden)
    public static func makeMidtermStandardDocument(
        canvasSize: PSDSize = PSDSize(width: 16, height: 16)
    ) throws -> PSDDocument {
        let size = canvasSize
        let fullFrame = PSDRect(left: 0, top: 0, right: size.width, bottom: size.height)

        let bg = try makeSolidLayer(
            name: "BG",
            canvasSize: size,
            red: 240,
            green: 240,
            blue: 240,
            alpha: 255
        )

        let red = try makeSolidLayer(
            name: "Red",
            canvasSize: size,
            red: 255,
            green: 0,
            blue: 0,
            alpha: 255
        )
        red.blendMode = .multiply
        red.opacity = 200

        let glow = try makePixelLayer(
            name: "Glow",
            frame: fullFrame,
            rgba: makeGlowAlphaGradientRGBA(width: size.width, height: size.height),
            blendMode: .add
        )

        let top = try makeSolidLayer(
            name: "Top",
            canvasSize: size,
            red: 0,
            green: 0,
            blue: 255,
            alpha: 255
        )
        top.isVisible = false

        let groupB = GroupLayer(name: "Group B")
        groupB.append(glow)

        let groupA = GroupLayer(name: "Group A")
        groupA.append(red)
        groupA.append(groupB)

        let root = GroupLayer(name: "")
        root.append(bg)
        root.append(groupA)
        root.append(top)

        return try create(canvasSize: size, root: root)
    }

    /// Pixel layer from in-memory RGBA (dimensions must match `frame`).
    public static func makePixelLayer(
        name: String,
        frame: PSDRect,
        rgba: Data,
        isVisible: Bool = true,
        opacity: UInt8 = 255,
        blendMode: BlendMode = .normal
    ) throws -> PixelLayer {
        let pixels = try PixelBuffer(width: frame.width, height: frame.height, rgba: rgba)
        return PixelLayer(
            name: name,
            frame: frame,
            pixels: pixels,
            isVisible: isVisible,
            opacity: opacity,
            blendMode: blendMode
        )
    }

    public static func makePixelLayer(from input: LayerRGBAInput) throws -> PixelLayer {
        try makePixelLayer(
            name: input.name,
            frame: input.frame,
            rgba: input.rgba,
            isVisible: input.isVisible,
            opacity: input.opacity,
            blendMode: input.blendMode
        )
    }

    /// Reads a raw RGBA8888 file and places it at `frame` (common export pipeline output).
    public static func makePixelLayer(
        name: String,
        frame: PSDRect,
        rgbaFileURL: URL,
        isVisible: Bool = true,
        opacity: UInt8 = 255,
        blendMode: BlendMode = .normal
    ) throws -> PixelLayer {
        let rgba = try Data(contentsOf: rgbaFileURL)
        return try makePixelLayer(
            name: name,
            frame: frame,
            rgba: rgba,
            isVisible: isVisible,
            opacity: opacity,
            blendMode: blendMode
        )
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
        let frame = PSDRect(left: 0, top: 0, right: canvasSize.width, bottom: canvasSize.height)
        return try makePixelLayer(name: name, frame: frame, rgba: rgba, opacity: alpha)
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
        try serializedData(writeMode: writeMode).data
    }

    public func save(to url: URL, writeMode: PSDWriteMode = .passthrough) throws {
        let payload = try serializedData(writeMode: writeMode)
        try payload.data.write(to: url, options: .atomic)
        switch payload.effectiveMode {
        case .passthrough:
            rawFile.sourceData = payload.data
        case .semantic:
            if let synced = payload.syncedFile {
                rawFile = synced
                rawFile.sourceData = payload.data
            }
        }
        isContentDirty = false
    }

    // MARK: - Layer editing (phase 4)

    /// Call after mutating layer properties in place.
    /// Merged canvas preview (RGBA8888), recursively compositing visible pixel layers in tree order.
    public func compositePreviewRGBA() -> Data {
        let layers = Self.collectPreviewPixels(from: root, inheritedVisible: true, inheritedOpacity: 255)
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

    // MARK: - Layer tree editing (memory model; nested PSD persistence is separate)

    /// Appends `layer` under `parent` in the in-memory tree and marks the document modified.
    /// Does not update on-disk layer records for non-root parents.
    public func appendLayer(_ layer: any LayerProtocol, to parent: GroupLayer) {
        let childIDsBefore = parent.children.map(\.id)
        let parentBefore = layer.parent
        parent.append(layer)
        if parent.children.map(\.id) != childIDsBefore || layer.parent === parent && parentBefore !== parent {
            markContentModified()
        }
    }

    /// Inserts `layer` under `parent` at `index` (`0` = bottom) and marks the document modified.
    public func insertLayer(_ layer: any LayerProtocol, to parent: GroupLayer, at index: Int) {
        let childIDsBefore = parent.children.map(\.id)
        let parentBefore = layer.parent
        parent.insert(layer, at: index)
        if parent.children.map(\.id) != childIDsBefore || layer.parent === parent && parentBefore !== parent {
            markContentModified()
        }
    }

    /// Removes `layer` from its current parent in the in-memory tree and marks the document modified.
    public func removeLayer(_ layer: any LayerProtocol) {
        guard let parent = layer.parent else { return }
        parent.remove(layer)
        markContentModified()
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

    private struct SerializationPayload {
        let data: Data
        let effectiveMode: PSDWriteMode
        let syncedFile: PSDFile?
    }

    private func serializedData(writeMode: PSDWriteMode) throws -> SerializationPayload {
        let effective: PSDWriteMode = (isContentDirty || rawFile.sourceData.isEmpty) ? .semantic : writeMode
        switch effective {
        case .passthrough:
            return SerializationPayload(
                data: try rawFile.write(passthrough: true),
                effectiveMode: .passthrough,
                syncedFile: nil
            )
        case .semantic:
            let synced = try DocumentBuilder.syncRawFile(from: self)
            return SerializationPayload(
                data: try synced.write(passthrough: false),
                effectiveMode: .semantic,
                syncedFile: synced
            )
        }
    }

    private static func collectPreviewPixels(
        from group: GroupLayer,
        inheritedVisible: Bool,
        inheritedOpacity: UInt8
    ) -> [PixelLayer] {
        guard inheritedVisible, group.isVisible else { return [] }
        let groupOpacity = combineOpacity(inheritedOpacity, group.opacity)
        var result: [PixelLayer] = []
        for child in group.children {
            if let pixel = child as? PixelLayer {
                guard pixel.isVisible else { continue }
                let effectiveOpacity = combineOpacity(groupOpacity, pixel.opacity)
                let layerForPreview: PixelLayer
                if effectiveOpacity == pixel.opacity {
                    layerForPreview = pixel
                } else {
                    layerForPreview = PixelLayer(
                        name: pixel.name,
                        frame: pixel.frame,
                        pixels: pixel.pixels,
                        isVisible: true,
                        opacity: effectiveOpacity,
                        blendMode: pixel.blendMode
                    )
                }
                result.append(layerForPreview)
            } else if let nested = child as? GroupLayer {
                result.append(
                    contentsOf: collectPreviewPixels(
                        from: nested,
                        inheritedVisible: true,
                        inheritedOpacity: groupOpacity
                    )
                )
            }
        }
        return result
    }

    private static func combineOpacity(_ lhs: UInt8, _ rhs: UInt8) -> UInt8 {
        UInt8((Int(lhs) * Int(rhs) + 127) / 255)
    }

    private static func makeGlowAlphaGradientRGBA(width: Int, height: Int) -> Data {
        var rgba = Data(count: width * height * 4)
        let span = max(1, width - 1)
        for y in 0 ..< height {
            for x in 0 ..< width {
                let offset = (y * width + x) * 4
                rgba[offset] = 255
                rgba[offset + 1] = 220
                rgba[offset + 2] = 80
                let alpha = UInt8(64 + (191 * x) / span)
                rgba[offset + 3] = alpha
            }
        }
        return rgba
    }
}
