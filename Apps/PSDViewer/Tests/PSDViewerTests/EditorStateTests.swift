import XCTest
@testable import PSDViewer

final class EditorStateTests: XCTestCase {
    func testDefaultState() {
        let state = EditorState()

        XCTAssertEqual(state.selection, .none)
        XCTAssertEqual(state.activeTool, .inspect)
        XCTAssertEqual(state.brushSettings, .defaults)
        XCTAssertNil(state.selectedLayerID)
    }

    func testToolSwitching() {
        var state = EditorState()
        state.setTool(.brush)
        XCTAssertEqual(state.activeTool, .brush)

        state.setTool(.eraser)
        XCTAssertEqual(state.activeTool, .eraser)

        for tool in EditorTool.allCases {
            state.setTool(tool)
            XCTAssertEqual(state.activeTool, tool)
        }
    }

    func testSelection() {
        var state = EditorState()
        state.selectLayer(id: "1/0")
        XCTAssertEqual(state.selection, .layer(id: "1/0"))
        XCTAssertEqual(state.selectedLayerID, "1/0")

        state.selectLayer(id: nil)
        XCTAssertEqual(state.selection, .none)
        XCTAssertNil(state.selectedLayerID)
    }

    func testBrushDefaultsAreStable() {
        let first = BrushSettings.defaults
        let second = BrushSettings()

        XCTAssertEqual(first, second)
        XCTAssertEqual(first.size, 32)
        XCTAssertEqual(first.hardness, 50)
        XCTAssertEqual(first.spacing, 0.09, accuracy: 0.0001)
        XCTAssertEqual(first.flow, 0.6, accuracy: 0.0001)
        XCTAssertEqual(first.opacity, 1.0, accuracy: 0.0001)
    }

    func testBrushPressureMath() {
        let brush = BrushSettings.defaults
        XCTAssertGreaterThan(brush.radius(for: 0), 0)
        XCTAssertGreaterThanOrEqual(brush.radius(for: 1), brush.radius(for: 0))
        XCTAssertGreaterThan(brush.dabAlpha(for: 0.5), 0)
        XCTAssertGreaterThan(brush.spacingDistance(forRadius: 8), 0)
    }
}
