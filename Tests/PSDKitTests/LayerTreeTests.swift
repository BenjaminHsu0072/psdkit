import XCTest
@testable import PSDKit

final class LayerTreeTests: XCTestCase {
    func testChildrenOrderBottomToTop() throws {
        let root = GroupLayer(name: "Root")
        let bottom = try makePixel(name: "Bottom")
        let middle = try makePixel(name: "Middle")
        let top = try makePixel(name: "Top")

        root.append(bottom)
        root.append(middle)
        root.append(top)

        XCTAssertEqual(root.children.map(\.name), ["Bottom", "Middle", "Top"])
        XCTAssertIdentical(root.children.first as AnyObject, bottom)
        XCTAssertIdentical(root.children.last as AnyObject, top)
    }

    func testAppendSetsParent() throws {
        let root = GroupLayer(name: "Root")
        let group = GroupLayer(name: "Group A")
        let layer = try makePixel(name: "A-1")

        root.append(group)
        group.append(layer)

        XCTAssertIdentical(group.parent, root)
        XCTAssertIdentical(layer.parent, group)
        XCTAssertTrue(root.children.contains { $0.id == group.id })
        XCTAssertTrue(group.children.contains { $0.id == layer.id })
    }

    func testInsertPreservesOrderAndParent() throws {
        let group = GroupLayer(name: "Group")
        let a = try makePixel(name: "A")
        let b = try makePixel(name: "B")
        let c = try makePixel(name: "C")

        group.append(a)
        group.append(c)
        group.insert(b, at: 1)

        XCTAssertEqual(group.children.map(\.name), ["A", "B", "C"])
        XCTAssertIdentical(a.parent, group)
        XCTAssertIdentical(b.parent, group)
        XCTAssertIdentical(c.parent, group)
    }

    func testRemoveClearsParent() throws {
        let root = GroupLayer(name: "Root")
        let layer = try makePixel(name: "Layer")
        root.append(layer)

        root.remove(layer)

        XCTAssertTrue(root.children.isEmpty)
        XCTAssertNil(layer.parent)
    }

    func testAppendGroupToSelfIsNoOp() {
        let group = GroupLayer(name: "Solo")
        group.append(group)

        XCTAssertTrue(group.children.isEmpty)
        XCTAssertNil(group.parent)
    }

    func testAppendAncestorGroupToDescendantIsNoOp() {
        let root = GroupLayer(name: "Root")
        let parentGroup = GroupLayer(name: "Parent")
        let childGroup = GroupLayer(name: "Child")
        root.append(parentGroup)
        parentGroup.append(childGroup)

        let rootChildIDs = root.children.map(\.id)
        let parentChildIDs = parentGroup.children.map(\.id)

        childGroup.append(parentGroup)

        XCTAssertEqual(root.children.map(\.id), rootChildIDs)
        XCTAssertEqual(parentGroup.children.map(\.id), parentChildIDs)
        XCTAssertIdentical(parentGroup.parent, root)
        XCTAssertIdentical(childGroup.parent, parentGroup)
        XCTAssertFalse(childGroup.children.contains { $0.id == parentGroup.id })
    }

    func testInsertAncestorGroupToDescendantIsNoOp() throws {
        let root = GroupLayer(name: "Root")
        let parentGroup = GroupLayer(name: "Parent")
        let childGroup = GroupLayer(name: "Child")
        let pixel = try makePixel(name: "Pixel")
        root.append(parentGroup)
        parentGroup.append(childGroup)
        childGroup.append(pixel)

        let childIDs = childGroup.children.map(\.id)
        let pixelParent = pixel.parent

        childGroup.insert(parentGroup, at: 0)

        XCTAssertEqual(childGroup.children.map(\.id), childIDs)
        XCTAssertIdentical(pixel.parent, pixelParent)
        XCTAssertIdentical(parentGroup.parent, root)
        XCTAssertIdentical(childGroup.parent, parentGroup)
    }

    func testDocumentAppendLayerSkipsDirtyOnCycleNoOp() throws {
        let url = try fixtureURL("single-rle-8x8.psd")
        let doc = try PSDDocument.load(url: url)
        XCTAssertFalse(doc.isContentDirty)

        let parentGroup = GroupLayer(name: "Parent")
        let childGroup = GroupLayer(name: "Child")
        doc.root.append(parentGroup)
        doc.root.append(childGroup)
        parentGroup.append(childGroup)
        XCTAssertFalse(doc.isContentDirty)

        doc.appendLayer(parentGroup, to: childGroup)

        XCTAssertFalse(doc.isContentDirty)
        XCTAssertFalse(childGroup.children.contains { $0.id == parentGroup.id })
    }

    func testMoveBetweenGroupsUpdatesParentAndMembership() throws {
        let root = GroupLayer(name: "Root")
        let groupA = GroupLayer(name: "A")
        let groupB = GroupLayer(name: "B")
        let layer = try makePixel(name: "Pixel")

        root.append(groupA)
        root.append(groupB)
        groupA.append(layer)

        groupB.append(layer)

        XCTAssertFalse(groupA.children.contains { $0.id == layer.id })
        XCTAssertTrue(groupB.children.contains { $0.id == layer.id })
        XCTAssertIdentical(layer.parent, groupB)
    }

    func testDirectGroupLayerMutationDoesNotMarkDocumentDirty() throws {
        let doc = try PSDDocument.create(width: 8, height: 8)
        XCTAssertTrue(doc.isContentDirty)

        let group = GroupLayer(name: "Nested")
        let layer = try makePixel(name: "Inside")
        doc.root.append(group)
        group.append(layer)

        XCTAssertTrue(doc.isContentDirty, "create() dirties once; direct tree edits do not toggle dirty")
    }

    func testDocumentAppendLayerMarksDirty() throws {
        let url = try fixtureURL("single-rle-8x8.psd")
        let doc = try PSDDocument.load(url: url)
        XCTAssertFalse(doc.isContentDirty)

        let group = GroupLayer(name: "Folder")
        let layer = try makePixel(name: "Nested")
        doc.appendLayer(group, to: doc.root)
        doc.appendLayer(layer, to: group)

        XCTAssertTrue(doc.isContentDirty)
        XCTAssertIdentical(layer.parent, group)
        XCTAssertEqual(doc.root.children.count, 2)
        XCTAssertEqual(doc.root.children.last?.name, "Folder")
    }

    func testDocumentRemoveLayerMarksDirty() throws {
        let url = try fixtureURL("single-rle-8x8.psd")
        let doc = try PSDDocument.load(url: url)
        XCTAssertFalse(doc.isContentDirty)
        guard let layer = doc.root.children.first else {
            XCTFail("expected layer")
            return
        }

        doc.removeLayer(layer)

        XCTAssertTrue(doc.isContentDirty)
        XCTAssertNil(layer.parent)
        XCTAssertTrue(doc.root.children.isEmpty)
    }

    func testAppendPixelLayerStillSetsParentAndPreservesFlatBehavior() throws {
        let doc = try PSDDocument.create(width: 8, height: 8)
        let layer = try PSDDocument.makeSolidLayer(
            name: "Added",
            canvasSize: doc.canvasSize,
            red: 255,
            green: 0,
            blue: 0
        )
        try doc.appendPixelLayer(layer)

        XCTAssertIdentical(layer.parent, doc.root)
        XCTAssertEqual(doc.root.children.count, 1)

        let data = try doc.data()
        let reloaded = try PSDDocument.load(data: data)
        XCTAssertEqual(reloaded.root.children.compactMap { $0 as? PixelLayer }.count, 1)
        XCTAssertEqual(reloaded.root.children.first?.name, "Added")
        XCTAssertIdentical((reloaded.root.children.first as? PixelLayer)?.parent, reloaded.root)
    }

    func testLoadedDocumentRootChildrenHaveParent() throws {
        let url = try fixtureURL("two-layers.psd")
        let doc = try PSDDocument.load(url: url)
        for child in doc.root.children {
            XCTAssertIdentical(child.parent, doc.root)
        }
    }

    private func makePixel(name: String) throws -> PixelLayer {
        try PixelLayer(
            name: name,
            frame: PSDRect(left: 0, top: 0, right: 2, bottom: 2),
            pixels: PixelBuffer(width: 2, height: 2, rgba: Data(repeating: 0, count: 16))
        )
    }

    private func fixtureURL(_ name: String) throws -> URL {
        let base = name.replacingOccurrences(of: ".psd", with: "")
        guard let url = Bundle.module.url(forResource: base, withExtension: "psd", subdirectory: "Fixtures") else {
            throw XCTSkip("Missing fixture \(name)")
        }
        return url
    }
}
