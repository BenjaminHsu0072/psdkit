import Foundation
@testable import PSDKit

/// Standard midterm round-trip fixture built entirely in PSDKit (no external PSD).
enum MidtermStandardDocument {
    static let canvasSize = PSDSize(width: 16, height: 16)

    /// ```
    /// Canvas 16×16
    /// ├── BG normal, opaque
    /// ├── Group A
    /// │   ├── Red multiply, opacity 200
    /// │   └── Group B
    /// │       └── Glow add, alpha gradient
    /// └── Top normal, hidden
    /// ```
    static func make() throws -> PSDDocument {
        let size = canvasSize
        let fullFrame = PSDRect(left: 0, top: 0, right: size.width, bottom: size.height)

        let bg = try PSDDocument.makeSolidLayer(
            name: "BG",
            canvasSize: size,
            red: 240,
            green: 240,
            blue: 240,
            alpha: 255
        )

        let red = try PSDDocument.makeSolidLayer(
            name: "Red",
            canvasSize: size,
            red: 255,
            green: 0,
            blue: 0,
            alpha: 255
        )
        red.blendMode = .multiply
        red.opacity = 200

        let glow = try PSDDocument.makePixelLayer(
            name: "Glow",
            frame: fullFrame,
            rgba: glowAlphaGradientRGBA(width: size.width, height: size.height),
            blendMode: .add
        )

        let top = try PSDDocument.makeSolidLayer(
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

        let file = PSDFile(
            header: FileHeader.newRGB(width: size.width, height: size.height, channels: 3),
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
            canvasSize: size,
            colorMode: file.header.colorMode,
            root: root,
            rawFile: file
        )
        doc.markContentModified()
        return doc
    }

    /// Warm glow color with horizontal alpha ramp (not fully opaque).
    private static func glowAlphaGradientRGBA(width: Int, height: Int) -> Data {
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
