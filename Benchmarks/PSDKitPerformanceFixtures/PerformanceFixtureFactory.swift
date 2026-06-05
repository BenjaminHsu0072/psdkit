import Foundation
import PSDKit

/// Repeatable performance fixture presets aligned with `docs/midterm-plan/06-performance.md`.
public enum PerformanceFixturePreset: String, Sendable, CaseIterable, Codable {
    /// Fast local/CI smoke: 64×64, 6 pixel layers + nested groups.
    case smoke
    /// Target small tier: 1024×1024, 20 pixel layers.
    case small
    /// Target medium tier: 2048×2048, 50 pixel layers.
    case medium
    /// Target stress tier: 4096×4096, 100 pixel layers.
    case stress
}

public struct PerformanceFixtureConfig: Sendable, Equatable, Codable {
    public let preset: PerformanceFixturePreset
    public let canvasWidth: Int
    public let canvasHeight: Int
    /// Leaf pixel layer count (groups are additional).
    public let pixelLayerCount: Int

    public var canvasSize: PSDSize { PSDSize(width: canvasWidth, height: canvasHeight) }

    public static func config(for preset: PerformanceFixturePreset) -> PerformanceFixtureConfig {
        switch preset {
        case .smoke:
            return PerformanceFixtureConfig(preset: preset, canvasWidth: 64, canvasHeight: 64, pixelLayerCount: 6)
        case .small:
            return PerformanceFixtureConfig(preset: preset, canvasWidth: 1024, canvasHeight: 1024, pixelLayerCount: 20)
        case .medium:
            return PerformanceFixtureConfig(preset: preset, canvasWidth: 2048, canvasHeight: 2048, pixelLayerCount: 50)
        case .stress:
            return PerformanceFixtureConfig(preset: preset, canvasWidth: 4096, canvasHeight: 4096, pixelLayerCount: 100)
        }
    }
}

public enum PerformanceFixtureFactory {
    public static func makeDocument(preset: PerformanceFixturePreset) throws -> PSDDocument {
        try makeDocument(config: .config(for: preset))
    }

    public static func makeDocument(config: PerformanceFixtureConfig) throws -> PSDDocument {
        let size = config.canvasSize
        let offsetSize = max(16, min(256, max(size.width, size.height) / 16))

        let bg = try PSDDocument.makeSolidLayer(
            name: "BG",
            canvasSize: size,
            red: 32,
            green: 32,
            blue: 40,
            alpha: 255
        )

        var rootLayers: [any LayerProtocol] = [bg]
        var groupedLayers: [PixelLayer] = []

        for index in 1 ..< config.pixelLayerCount {
            let layer = try makeVarietyLayer(
                index: index,
                canvasSize: size,
                offsetSize: offsetSize
            )
            if index.isMultiple(of: 3) {
                groupedLayers.append(layer)
            } else {
                rootLayers.append(layer)
            }
        }

        let innerGroup = GroupLayer(name: "Perf Inner Group")
        for layer in groupedLayers.prefix(groupedLayers.count / 2) {
            innerGroup.append(layer)
        }

        let outerGroup = GroupLayer(name: "Perf Outer Group")
        for layer in groupedLayers.dropFirst(groupedLayers.count / 2) {
            outerGroup.append(layer)
        }
        outerGroup.append(innerGroup)

        if !groupedLayers.isEmpty {
            rootLayers.append(outerGroup)
        }

        let root = GroupLayer(name: "")
        for layer in rootLayers {
            root.append(layer)
        }

        return try PSDDocument.create(canvasSize: size, root: root)
    }

    private static func makeVarietyLayer(
        index: Int,
        canvasSize: PSDSize,
        offsetSize: Int
    ) throws -> PixelLayer {
        let blendMode = blendMode(for: index)
        let name = "Layer-\(index)"
        let opacity = UInt8(160 + (index * 7) % 96)

        switch index % 5 {
        case 0 where (index / 5) < fullCanvasSlotCount(canvasSize: canvasSize):
            let layer = try PSDDocument.makeSolidLayer(
                name: name,
                canvasSize: canvasSize,
                red: UInt8((index * 53) % 256),
                green: UInt8((index * 97) % 256),
                blue: UInt8((index * 149) % 256),
                alpha: 255
            )
            layer.blendMode = blendMode
            layer.opacity = opacity
            return layer

        case 1, 4:
            let left = (index * 37) % max(1, canvasSize.width - offsetSize)
            let top = (index * 59) % max(1, canvasSize.height - offsetSize)
            let frame = PSDRect(
                left: left,
                top: top,
                right: left + offsetSize,
                bottom: top + offsetSize
            )
            let rgba = solidRGBA(
                width: frame.width,
                height: frame.height,
                red: UInt8((index * 41) % 256),
                green: UInt8((index * 67) % 256),
                blue: UInt8((index * 83) % 256),
                alpha: 220
            )
            return try PSDDocument.makePixelLayer(
                name: name,
                frame: frame,
                rgba: rgba,
                opacity: opacity,
                blendMode: blendMode
            )

        default:
            let gradWidth = min(canvasSize.width, max(offsetSize * 2, canvasSize.width / 4))
            let gradHeight = min(canvasSize.height, max(offsetSize, canvasSize.height / 8))
            let left = (index * 19) % max(1, canvasSize.width - gradWidth)
            let top = (index * 23) % max(1, canvasSize.height - gradHeight)
            let frame = PSDRect(
                left: left,
                top: top,
                right: left + gradWidth,
                bottom: top + gradHeight
            )
            return try PSDDocument.makePixelLayer(
                name: name,
                frame: frame,
                rgba: alphaGradientRGBA(width: frame.width, height: frame.height, seed: index),
                opacity: opacity,
                blendMode: blendMode
            )
        }
    }

    private static func fullCanvasSlotCount(canvasSize: PSDSize) -> Int {
        let pixels = canvasSize.width * canvasSize.height
        if pixels <= 64 * 64 { return 3 }
        if pixels <= 1024 * 1024 { return 4 }
        if pixels <= 2048 * 2048 { return 3 }
        return 2
    }

    private static func blendMode(for index: Int) -> BlendMode {
        switch index % 3 {
        case 0: return .normal
        case 1: return .multiply
        default: return .add
        }
    }

    private static func solidRGBA(width: Int, height: Int, red: UInt8, green: UInt8, blue: UInt8, alpha: UInt8) -> Data {
        var rgba = Data(count: width * height * 4)
        rgba.withUnsafeMutableBytes { raw in
            let bytes = raw.bindMemory(to: UInt8.self)
            for i in 0 ..< width * height {
                bytes[i * 4] = red
                bytes[i * 4 + 1] = green
                bytes[i * 4 + 2] = blue
                bytes[i * 4 + 3] = alpha
            }
        }
        return rgba
    }

    private static func alphaGradientRGBA(width: Int, height: Int, seed: Int) -> Data {
        var rgba = Data(count: width * height * 4)
        let span = max(1, width - 1)
        let baseRed = UInt8(80 + (seed * 17) % 160)
        let baseGreen = UInt8(120 + (seed * 23) % 100)
        let baseBlue = UInt8(40 + (seed * 31) % 180)
        for y in 0 ..< height {
            for x in 0 ..< width {
                let offset = (y * width + x) * 4
                rgba[offset] = baseRed
                rgba[offset + 1] = baseGreen
                rgba[offset + 2] = baseBlue
                let alpha = UInt8(32 + (223 * x) / span)
                rgba[offset + 3] = alpha
            }
        }
        return rgba
    }
}
