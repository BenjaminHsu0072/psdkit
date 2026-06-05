import Foundation
import PSDKit

/// Child indices from `document.root` (e.g. `[1, 0]` = second root child, then its first child).
struct LayerPath: Hashable, Equatable, Sendable {
    let indices: [Int]

    var selectionID: String {
        indices.map(String.init).joined(separator: "/")
    }

    init(indices: [Int]) {
        self.indices = indices
    }

    init?(selectionID: String) {
        guard !selectionID.isEmpty else { return nil }
        let parts = selectionID.split(separator: "/")
        var parsed: [Int] = []
        parsed.reserveCapacity(parts.count)
        for part in parts {
            guard let value = Int(part) else { return nil }
            parsed.append(value)
        }
        self.indices = parsed
    }
}

enum LayerDisplayKind: Equatable, Sendable {
    case group
    case pixel
}

struct LayerListItem: Identifiable, Equatable, Sendable {
    let path: LayerPath
    let depth: Int
    let displayKind: LayerDisplayKind
    let name: String
    let isVisible: Bool
    let opacity: UInt8
    let childCount: Int?

    var id: String { path.selectionID }
}

enum LayerListFlattener {
    /// Depth-first list: each group row appears immediately before its descendants.
    /// Order within a parent matches `children` (`0` = stack bottom).
    static func flatten(root: GroupLayer) -> [LayerListItem] {
        var items: [LayerListItem] = []
        visit(parent: root, pathPrefix: [], into: &items)
        return items
    }

    static func resolveLayer(in root: GroupLayer, path: LayerPath) -> (any LayerProtocol)? {
        guard !path.indices.isEmpty else { return nil }
        var current: GroupLayer = root
        var layer: (any LayerProtocol)?
        for (step, index) in path.indices.enumerated() {
            guard index >= 0, index < current.children.count else { return nil }
            layer = current.children[index]
            if step < path.indices.count - 1 {
                guard let group = layer as? GroupLayer else { return nil }
                current = group
            }
        }
        return layer
    }

    private static func visit(
        parent: GroupLayer,
        pathPrefix: [Int],
        into items: inout [LayerListItem]
    ) {
        for (index, layer) in parent.children.enumerated() {
            let path = LayerPath(indices: pathPrefix + [index])
            let depth = pathPrefix.count
            if let group = layer as? GroupLayer {
                items.append(
                    LayerListItem(
                        path: path,
                        depth: depth,
                        displayKind: .group,
                        name: layer.name,
                        isVisible: layer.isVisible,
                        opacity: layer.opacity,
                        childCount: group.children.count
                    )
                )
                visit(parent: group, pathPrefix: path.indices, into: &items)
            } else {
                items.append(
                    LayerListItem(
                        path: path,
                        depth: depth,
                        displayKind: .pixel,
                        name: layer.name,
                        isVisible: layer.isVisible,
                        opacity: layer.opacity,
                        childCount: nil
                    )
                )
            }
        }
    }
}
