import Foundation

public enum LayerKind: Sendable, Equatable {
    case pixel
    case group
    case unknown(String)
}

/// In-memory layer tree container. `children[0]` is the bottom of the stack; `children.last` is the top.
public final class GroupLayer: LayerProtocol, @unchecked Sendable {
    public let id = UUID()
    public var name: String
    public var isVisible: Bool
    public var opacity: UInt8
    public var blendMode: BlendMode
    /// Document bounds for the group; defaults to empty until group bounds are modeled explicitly.
    public var frame: PSDRect
    public private(set) var children: [any LayerProtocol] = []
    public weak var parent: GroupLayer?

    public var kind: LayerKind { .group }

    public init(
        name: String = "Root",
        isVisible: Bool = true,
        opacity: UInt8 = 255,
        blendMode: BlendMode = .passThrough,
        frame: PSDRect = PSDRect(left: 0, top: 0, right: 0, bottom: 0)
    ) {
        self.name = name
        self.isVisible = isVisible
        self.opacity = opacity
        self.blendMode = blendMode
        self.frame = frame
    }

    public func append(_ layer: any LayerProtocol) {
        if wouldCreateGroupCycle(adopting: layer) {
            return
        }
        if layer.parent === self, children.contains(where: { $0.id == layer.id }) {
            return
        }
        detachFromCurrentParent(layer)
        children.append(layer)
        layer.parent = self
    }

    public func remove(_ layer: any LayerProtocol) {
        children.removeAll { $0.id == layer.id }
        if layer.parent === self {
            layer.parent = nil
        }
    }

    public func insert(_ layer: any LayerProtocol, at index: Int) {
        if wouldCreateGroupCycle(adopting: layer) {
            return
        }
        if layer.parent === self {
            children.removeAll { $0.id == layer.id }
        } else {
            detachFromCurrentParent(layer)
        }
        let clamped = min(max(0, index), children.count)
        children.insert(layer, at: clamped)
        layer.parent = self
    }

    /// Returns true when adopting `layer` as a direct child would create a group cycle.
    private func wouldCreateGroupCycle(adopting layer: any LayerProtocol) -> Bool {
        guard let group = layer as? GroupLayer else { return false }
        if group === self { return true }
        var ancestor = parent
        while let current = ancestor {
            if current === group { return true }
            ancestor = current.parent
        }
        return false
    }

    private func detachFromCurrentParent(_ layer: any LayerProtocol) {
        guard let oldParent = layer.parent, oldParent !== self else { return }
        oldParent.remove(layer)
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
