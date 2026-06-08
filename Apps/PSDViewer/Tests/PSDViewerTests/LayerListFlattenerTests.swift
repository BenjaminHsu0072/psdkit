import PSDKit
import XCTest
@testable import PSDViewer

final class LayerListFlattenerTests: XCTestCase {
    func testFlattenEmptyRoot() {
        let root = GroupLayer(name: "")
        XCTAssertEqual(LayerListFlattener.flatten(root: root), [])
    }

    func testFlattenFlatPixelsPreservesOrder() throws {
        let root = GroupLayer(name: "")
        root.append(try makePixel(name: "BG"))
        root.append(try makePixel(name: "FG"))

        let items = LayerListFlattener.flatten(root: root)
        XCTAssertEqual(items.map(\.name), ["BG", "FG"])
        XCTAssertEqual(items.map(\.depth), [0, 0])
        XCTAssertTrue(items.allSatisfy { $0.displayKind == .pixel })
        XCTAssertEqual(items.map(\.path.selectionID), ["0", "1"])
    }

    func testFlattenNestedGroupDepthAndOrder() throws {
        let root = GroupLayer(name: "")
        let group = GroupLayer(name: "Group A")
        group.append(try makePixel(name: "A-1"))
        group.append(try makePixel(name: "A-2"))
        root.append(try makePixel(name: "BG"))
        root.append(group)
        root.append(try makePixel(name: "FG"))

        let items = LayerListFlattener.flatten(root: root)
        XCTAssertEqual(items.map(\.name), ["BG", "Group A", "A-1", "A-2", "FG"])
        XCTAssertEqual(items.map(\.depth), [0, 0, 1, 1, 0])
        XCTAssertEqual(items.map(\.displayKind), [.pixel, .group, .pixel, .pixel, .pixel])
        XCTAssertEqual(items[1].childCount, 2)
    }

    func testResolveLayerByPath() throws {
        let root = GroupLayer(name: "")
        let group = GroupLayer(name: "G")
        let inner = try makePixel(name: "P")
        group.append(inner)
        root.append(group)

        let resolved = LayerListFlattener.resolveLayer(in: root, path: LayerPath(indices: [0, 0]))
        XCTAssertTrue(resolved === inner)
    }

    func testSelectionIDRoundTrip() {
        let path = LayerPath(indices: [2, 0, 1])
        XCTAssertEqual(LayerPath(selectionID: path.selectionID), path)
    }

    func testResolveInvalidPathReturnsNil() throws {
        let root = GroupLayer(name: "")
        root.append(try makePixel(name: "Only"))
        XCTAssertNil(LayerListFlattener.resolveLayer(in: root, path: LayerPath(indices: [2])))
    }

    private func makePixel(name: String) throws -> PixelLayer {
        try PixelLayer(
            name: name,
            frame: PSDRect(left: 0, top: 0, right: 1, bottom: 1),
            pixels: PixelBuffer(width: 1, height: 1, rgba: Data(count: 4))
        )
    }
}
