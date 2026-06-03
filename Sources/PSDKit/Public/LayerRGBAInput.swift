import Foundation

/// One pixel layer to assemble when exporting a new PSD from generated RGBA assets.
public struct LayerRGBAInput: Sendable {
    public var name: String
    public var frame: PSDRect
    /// RGBA8888, row-major; length must be `frame.width * frame.height * 4`.
    public var rgba: Data
    public var isVisible: Bool
    public var opacity: UInt8
    public var blendMode: BlendMode

    public init(
        name: String,
        frame: PSDRect,
        rgba: Data,
        isVisible: Bool = true,
        opacity: UInt8 = 255,
        blendMode: BlendMode = .normal
    ) {
        self.name = name
        self.frame = frame
        self.rgba = rgba
        self.isVisible = isVisible
        self.opacity = opacity
        self.blendMode = blendMode
    }

    public init(
        name: String,
        left: Int,
        top: Int,
        width: Int,
        height: Int,
        rgba: Data,
        isVisible: Bool = true,
        opacity: UInt8 = 255,
        blendMode: BlendMode = .normal
    ) {
        self.init(
            name: name,
            frame: PSDRect(left: left, top: top, right: left + width, bottom: top + height),
            rgba: rgba,
            isVisible: isVisible,
            opacity: opacity,
            blendMode: blendMode
        )
    }
}
