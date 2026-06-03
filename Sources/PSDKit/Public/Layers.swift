import Foundation

public enum LayerKind: Sendable, Equatable {
    case pixel
    case group
    case unknown(String)
}

public final class GroupLayer: @unchecked Sendable {
    public let id = UUID()
    public var name: String
    public private(set) var children: [any LayerProtocol] = []

    public init(name: String = "Root") {
        self.name = name
    }

    public func append(_ layer: any LayerProtocol) {
        children.append(layer)
    }

    public func remove(_ layer: any LayerProtocol) {
        children.removeAll { $0.id == layer.id }
    }

    public func insert(_ layer: any LayerProtocol, at index: Int) {
        children.insert(layer, at: index)
    }
}

public protocol LayerProtocol: AnyObject {
    var id: UUID { get }
    var name: String { get set }
    var isVisible: Bool { get set }
    var opacity: UInt8 { get set }
    var blendMode: BlendMode { get set }
    var frame: PSDRect { get set }
    var kind: LayerKind { get }
    var parent: GroupLayer? { get set }
}

public final class PixelLayer: LayerProtocol, @unchecked Sendable {
    public let id = UUID()
    public var name: String
    public var isVisible: Bool
    public var opacity: UInt8
    public var blendMode: BlendMode
    public var frame: PSDRect
    public var pixels: PixelBuffer
    public weak var parent: GroupLayer?

    public var kind: LayerKind { .pixel }

    public init(
        name: String,
        frame: PSDRect,
        pixels: PixelBuffer,
        isVisible: Bool = true,
        opacity: UInt8 = 255,
        blendMode: BlendMode = .normal
    ) {
        self.name = name
        self.frame = frame
        self.pixels = pixels
        self.isVisible = isVisible
        self.opacity = opacity
        self.blendMode = blendMode
    }
}
