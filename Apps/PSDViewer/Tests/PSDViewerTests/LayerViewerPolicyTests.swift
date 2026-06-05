import PSDKit
import XCTest
@testable import PSDViewer

final class LayerViewerPolicyTests: XCTestCase {
    func testRootPixelIsEditable() throws {
        let root = GroupLayer(name: "")
        root.append(try makePixel(name: "FG"))

        let item = LayerListFlattener.flatten(root: root)[0]
        XCTAssertEqual(LayerViewerPolicy.editPolicy(for: item), .editableRootPixel)
        XCTAssertTrue(LayerViewerPolicy.canToggleVisibility(for: item))
    }

    func testNestedPixelIsReadOnly() throws {
        let root = GroupLayer(name: "")
        let group = GroupLayer(name: "Group A")
        group.append(try makePixel(name: "A-1"))
        root.append(group)

        let nested = LayerListFlattener.flatten(root: root).first { $0.name == "A-1" }!
        XCTAssertEqual(LayerViewerPolicy.editPolicy(for: nested), .readOnly(.nestedPixel))
        XCTAssertFalse(LayerViewerPolicy.canToggleVisibility(for: nested))
    }

    func testGroupIsReadOnly() throws {
        let root = GroupLayer(name: "")
        let group = GroupLayer(name: "Group A")
        group.append(try makePixel(name: "A-1"))
        root.append(group)

        let groupItem = LayerListFlattener.flatten(root: root).first { $0.displayKind == .group }!
        XCTAssertEqual(LayerViewerPolicy.editPolicy(for: groupItem), .readOnly(.group))
        XCTAssertFalse(LayerViewerPolicy.canToggleVisibility(for: groupItem))
    }

    func testEditPolicyFromLayerProtocol() throws {
        let root = GroupLayer(name: "")
        let pixel = try makePixel(name: "P")
        root.append(pixel)

        let rootPath = LayerPath(indices: [0])
        XCTAssertEqual(
            LayerViewerPolicy.editPolicy(path: rootPath, layer: pixel),
            .editableRootPixel
        )

        let group = GroupLayer(name: "G")
        group.append(try makePixel(name: "Inner"))
        root.append(group)
        let nestedPath = LayerPath(indices: [1, 0])
        let inner = group.children[0]
        XCTAssertEqual(
            LayerViewerPolicy.editPolicy(path: nestedPath, layer: inner),
            .readOnly(.nestedPixel)
        )
        XCTAssertEqual(
            LayerViewerPolicy.editPolicy(path: LayerPath(indices: [1]), layer: group),
            .readOnly(.group)
        )
    }

    private func makePixel(name: String) throws -> PixelLayer {
        try PixelLayer(
            name: name,
            frame: PSDRect(left: 0, top: 0, right: 1, bottom: 1),
            pixels: PixelBuffer(width: 1, height: 1, rgba: Data(count: 4))
        )
    }
}
