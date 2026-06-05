import XCTest
@testable import PSDKit

/// Flat, comparable view of a `PSDDocument` for round-trip persistence tests.
struct DocumentSnapshot: Equatable, Sendable {
    let canvasSize: PSDSize
    let colorMode: ColorMode
    /// Root children in stack order (index 0 = bottom).
    let rootChildren: [SnapshotNode]

    static func capture(
        from document: PSDDocument,
        file: StaticString = #file,
        line: UInt = #line
    ) -> DocumentSnapshot {
        let rootChildren = document.root.children.map {
            capture(node: $0, expectedParent: document.root, file: file, line: line)
        }
        return DocumentSnapshot(
            canvasSize: document.canvasSize,
            colorMode: document.colorMode,
            rootChildren: rootChildren
        )
    }

    func assertEqual(to other: DocumentSnapshot, file: StaticString = #file, line: UInt = #line) {
        XCTAssertEqual(canvasSize, other.canvasSize, "canvasSize", file: file, line: line)
        XCTAssertEqual(colorMode, other.colorMode, "colorMode", file: file, line: line)
        XCTAssertEqual(rootChildren, other.rootChildren, "layer tree", file: file, line: line)
    }

    private static func capture(
        node: any LayerProtocol,
        expectedParent: GroupLayer,
        file: StaticString,
        line: UInt
    ) -> SnapshotNode {
        XCTAssertIdentical(
            node.parent,
            expectedParent,
            "parent invariant for \(node.name)",
            file: file,
            line: line
        )
        let parentName = expectedParent.name.isEmpty ? nil : expectedParent.name

        if let group = node as? GroupLayer {
            let children = group.children.map {
                capture(node: $0, expectedParent: group, file: file, line: line)
            }
            return SnapshotNode(
                kind: .group,
                name: group.name,
                isVisible: group.isVisible,
                opacity: group.opacity,
                blendMode: group.blendMode,
                frame: group.frame,
                pixelRGBA: nil,
                parentName: parentName,
                children: children
            )
        }

        if let pixel = node as? PixelLayer {
            return SnapshotNode(
                kind: .pixel,
                name: pixel.name,
                isVisible: pixel.isVisible,
                opacity: pixel.opacity,
                blendMode: pixel.blendMode,
                frame: pixel.frame,
                pixelRGBA: pixel.pixels.rgba,
                parentName: parentName,
                children: []
            )
        }

        XCTFail("unsupported layer kind", file: file, line: line)
        return SnapshotNode(
            kind: .pixel,
            name: node.name,
            isVisible: node.isVisible,
            opacity: node.opacity,
            blendMode: node.blendMode,
            frame: node.frame,
            pixelRGBA: nil,
            parentName: parentName,
            children: []
        )
    }
}

struct SnapshotNode: Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        case pixel
        case group
    }

    let kind: Kind
    let name: String
    let isVisible: Bool
    let opacity: UInt8
    let blendMode: BlendMode
    let frame: PSDRect
    /// Full RGBA8888 for pixel layers; `nil` for groups.
    let pixelRGBA: Data?
    /// `nil` when the parent is the document root (`GroupLayer` with empty name).
    let parentName: String?
    let children: [SnapshotNode]
}
