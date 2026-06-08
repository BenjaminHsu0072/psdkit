import PSDKit
import XCTest
@testable import PSDViewer

final class EditorCommandDispatcherTests: XCTestCase {
    private let dispatcher = EditorCommandDispatcher()

    func testSetLayerOpacityThroughMockAdapter() {
        let adapter = MockEditorDocumentAdapter(
            layers: [
                "0": .init(
                    opacity: 255,
                    blendMode: .normal,
                    frame: PSDRect(left: 0, top: 0, right: 4, bottom: 4)
                ),
            ]
        )

        let result = dispatcher.dispatch(
            SetLayerOpacityCommand(layerID: "0", opacity: 128),
            through: adapter
        )

        XCTAssertEqual(result, .success)
        XCTAssertEqual(adapter.layers["0"]?.opacity, 128)
        XCTAssertEqual(adapter.documentRevision, 1)
        XCTAssertEqual(adapter.contentModifiedCount, 1)
    }

    func testSetLayerBlendModeThroughMockAdapter() {
        let adapter = MockEditorDocumentAdapter(
            layers: [
                "1": .init(
                    opacity: 200,
                    blendMode: .normal,
                    frame: PSDRect(left: 0, top: 0, right: 8, bottom: 8)
                ),
            ]
        )

        let result = dispatcher.dispatch(
            SetLayerBlendModeCommand(layerID: "1", blendMode: .multiply),
            through: adapter
        )

        XCTAssertEqual(result, .success)
        XCTAssertEqual(adapter.layers["1"]?.blendMode, .multiply)
    }

    func testSetLayerFrameThroughMockAdapter() {
        let adapter = MockEditorDocumentAdapter(
            layers: [
                "0": .init(
                    opacity: 255,
                    blendMode: .normal,
                    frame: PSDRect(left: 0, top: 0, right: 4, bottom: 4)
                ),
            ]
        )
        let newFrame = PSDRect(left: 2, top: 3, right: 10, bottom: 11)

        let result = dispatcher.dispatch(
            SetLayerFrameCommand(layerID: "0", frame: newFrame),
            through: adapter
        )

        XCTAssertEqual(result, .success)
        XCTAssertEqual(adapter.layers["0"]?.frame, newFrame)
    }

    func testMissingLayerReturnsLayerNotFound() {
        let adapter = MockEditorDocumentAdapter()

        let result = dispatcher.dispatch(
            SetLayerOpacityCommand(layerID: "missing", opacity: 100),
            through: adapter
        )

        XCTAssertEqual(result, .failure(.layerNotFound))
        XCTAssertEqual(adapter.documentRevision, 0)
    }

    func testUnsupportedBlendMode() {
        let adapter = MockEditorDocumentAdapter(
            layers: [
                "0": .init(
                    opacity: 255,
                    blendMode: .normal,
                    frame: PSDRect(left: 0, top: 0, right: 1, bottom: 1)
                ),
            ]
        )

        let result = dispatcher.dispatch(
            SetLayerBlendModeCommand(layerID: "0", blendMode: .passThrough),
            through: adapter
        )

        XCTAssertEqual(result, .failure(.unsupportedBlendMode))
        XCTAssertEqual(adapter.layers["0"]?.blendMode, .normal)
    }

    func testReplaceLayerPixelsPlaceholderReturnsNotImplemented() {
        let adapter = MockEditorDocumentAdapter(
            layers: [
                "0": .init(
                    opacity: 255,
                    blendMode: .normal,
                    frame: PSDRect(left: 0, top: 0, right: 1, bottom: 1)
                ),
            ]
        )

        XCTAssertEqual(
            dispatcher.dispatch(
                ReplaceLayerPixelsCommand(layerID: "0", rgba: Data(), width: 1, height: 1),
                through: adapter
            ),
            .failure(.notImplemented)
        )
        XCTAssertEqual(adapter.documentRevision, 0)
    }

    func testPSDDocumentEditorAdapterAppliesOpacity() throws {
        let document = try PSDDocument.makeMidtermStandardDocument()
        let adapter = PSDDocumentEditorAdapter(document: document)

        let result = dispatcher.dispatch(
            SetLayerOpacityCommand(layerID: "1/0", opacity: 42),
            through: adapter
        )

        XCTAssertEqual(result, .success)
        let layer = try XCTUnwrap(adapter.resolvePixelLayerForTests(id: "1/0"))
        XCTAssertEqual(layer.opacity, 42)
        XCTAssertTrue(document.hasUnsavedChanges)
        XCTAssertEqual(adapter.documentRevision, 1)
    }
}

private extension PSDDocumentEditorAdapter {
    func resolvePixelLayerForTests(id: String) -> PixelLayer? {
        guard let path = LayerPath(selectionID: id) else { return nil }
        return LayerListFlattener.resolveLayer(in: document.root, path: path) as? PixelLayer
    }
}
