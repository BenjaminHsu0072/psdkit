import PSDKit
import XCTest
@testable import PSDViewer

final class EditorDirtyRegionTests: XCTestCase {
    func testEmptyUnionPreservesOtherRegion() {
        let rect = PSDRect(left: 1, top: 2, right: 5, bottom: 7)
        XCTAssertEqual(EditorDirtyRegion.empty.union(with: .unionRect(rect)), .unionRect(rect))
        XCTAssertEqual(EditorDirtyRegion.unionRect(rect).union(with: .empty), .unionRect(rect))
    }

    func testFullLayerDominatesUnion() {
        let rect = PSDRect(left: 0, top: 0, right: 4, bottom: 4)
        XCTAssertEqual(EditorDirtyRegion.fullLayer.union(with: .unionRect(rect)), .fullLayer)
        XCTAssertEqual(EditorDirtyRegion.unionRect(rect).union(with: .fullLayer), .fullLayer)
    }

    func testUnionRectMergesExtents() {
        let lhs = PSDRect(left: 0, top: 0, right: 4, bottom: 4)
        let rhs = PSDRect(left: 2, top: 3, right: 8, bottom: 9)
        let merged = EditorDirtyRegion.unionRect(lhs).union(with: .unionRect(rhs))
        XCTAssertEqual(merged, .unionRect(PSDRect(left: 0, top: 0, right: 8, bottom: 9)))
    }
}
