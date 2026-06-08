import PSDKit
import XCTest
@testable import PSDViewer

final class EditorSnapshotCompositorTests: XCTestCase {
    private let canvasSize = PSDSize(width: 1, height: 1)

    func testNormalMatchesDocumentPreviewRGBA() throws {
        let rgba = try compositeSnapshot(topBlendMode: .normal)
        let reference = try previewReference(topBlendMode: .normal)
        assertRGBAEqual(rgba, reference)
    }

    func testMultiplyMatchesDocumentPreviewRGBA() throws {
        let rgba = try compositeSnapshot(topBlendMode: .multiply)
        let reference = try previewReference(topBlendMode: .multiply)
        assertRGBAEqual(rgba, reference)
        XCTAssertEqual(rgba[0], 100)
        XCTAssertEqual(rgba[1], 25)
        XCTAssertEqual(rgba[2], 6)
    }

    func testAddMatchesDocumentPreviewRGBA() throws {
        let rgba = try compositeSnapshot(topBlendMode: .add)
        let reference = try previewReference(topBlendMode: .add)
        assertRGBAEqual(rgba, reference)
        XCTAssertEqual(rgba[0], 255)
        XCTAssertEqual(rgba[1], 164)
        XCTAssertEqual(rgba[2], 82)
    }

    func testMultiplyDiffersFromNormal() throws {
        let multiply = try compositeSnapshot(topBlendMode: .multiply)
        let normal = try compositeSnapshot(topBlendMode: .normal)
        XCTAssertNotEqual(Array(multiply.prefix(3)), Array(normal.prefix(3)))
    }

    func testAddDiffersFromNormal() throws {
        let add = try compositeSnapshot(topBlendMode: .add)
        let normal = try compositeSnapshot(topBlendMode: .normal)
        XCTAssertNotEqual(Array(add.prefix(3)), Array(normal.prefix(3)))
    }

    func testBlendChannelKernelMatchesPreviewSemantics() throws {
        XCTAssertEqual(EditorSnapshotCompositor.blendChannel(source: 200, destination: 128, mode: .multiply), 100)
        XCTAssertEqual(EditorSnapshotCompositor.blendChannel(source: 100, destination: 200, mode: .add), 255)
        XCTAssertEqual(EditorSnapshotCompositor.blendChannel(source: 90, destination: 10, mode: .normal), 90)
    }

    func testMidtermStandardDocumentMatchesPreviewRGBA() throws {
        let document = try PSDDocument.makeMidtermStandardDocument()
        let snapshot = EditorRenderSnapshotBuilder.build(from: document, documentRevision: 1)
        let provider = EditorSnapshotPixelProvider.build(from: document, snapshot: snapshot)
        let composited = try EditorSnapshotCompositor.compositeRGBA(snapshot: snapshot, pixels: provider)
        let preview = document.compositePreviewRGBA()
        assertRGBAEqual(composited, preview)
    }

    func testNestedGroupHiddenMatchesPreviewRGBA() throws {
        try assertMatchesPreviewReference { root in
            let visibleGroup = GroupLayer(name: "Visible")
            visibleGroup.append(try solidPixelLayer(r: 255, g: 0, b: 0, blendMode: .normal))
            root.append(visibleGroup)

            let hiddenGroup = GroupLayer(name: "Hidden")
            hiddenGroup.isVisible = false
            hiddenGroup.append(try solidPixelLayer(r: 0, g: 255, b: 0, blendMode: .normal))
            root.append(hiddenGroup)
        }
    }

    func testNestedGroupOpacityMatchesPreviewRGBA() throws {
        try assertMatchesPreviewReference { root in
            let group = GroupLayer(name: "Half")
            group.opacity = 128
            group.append(try solidPixelLayer(r: 200, g: 100, b: 50, blendMode: .normal))
            root.append(group)
        }
    }

    func testNestedGroupAndChildOpacityStackMatchesPreviewRGBA() throws {
        try assertMatchesPreviewReference { root in
            let group = GroupLayer(name: "Group")
            group.opacity = 128
            let pixel = try solidPixelLayer(r: 200, g: 100, b: 50, blendMode: .normal)
            pixel.opacity = 128
            group.append(pixel)
            root.append(group)
        }
    }

    func testNestedGroupBlendModesMatchPreviewRGBA() throws {
        for blendMode in [BlendMode.normal, .multiply, .add] {
            try assertMatchesPreviewReference { root in
                let group = GroupLayer(name: "Group")
                group.append(try solidPixelLayer(r: 128, g: 64, b: 32, blendMode: .normal))
                root.append(group)
                root.append(try solidPixelLayer(r: 200, g: 100, b: 50, blendMode: blendMode))
            }
        }
    }

    func testUnsupportedBlendModeFailsCompositorInsteadOfNormalFallback() throws {
        let document = try makeUnsupportedBlendDocument()
        let snapshot = EditorRenderSnapshotBuilder.build(from: document, documentRevision: 1)
        let provider = EditorSnapshotPixelProvider.build(from: document, snapshot: snapshot)

        XCTAssertThrowsError(try EditorSnapshotCompositor.compositeRGBA(snapshot: snapshot, pixels: provider)) { error in
            XCTAssertEqual(error as? EditorSnapshotCompositeError, .unsupportedBlendMode(.unknown))
        }
        XCTAssertEqual(
            EditorPreviewBlendSupport.firstUnsupportedBlend(in: snapshot),
            .unknown
        )
    }

    private func assertMatchesPreviewReference(
        _ configure: (GroupLayer) throws -> Void,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let root = GroupLayer(name: "")
        try configure(root)
        let document = try PSDDocument.create(canvasSize: canvasSize, root: root)
        let snapshot = EditorRenderSnapshotBuilder.build(from: document, documentRevision: 1)
        let provider = EditorSnapshotPixelProvider.build(from: document, snapshot: snapshot)
        let composited = try EditorSnapshotCompositor.compositeRGBA(snapshot: snapshot, pixels: provider)
        let preview = document.compositePreviewRGBA()
        assertRGBAEqual(composited, preview, file: file, line: line)
    }

    private func makeUnsupportedBlendDocument() throws -> PSDDocument {
        let root = GroupLayer(name: "")
        root.append(try solidPixelLayer(r: 128, g: 64, b: 32, blendMode: .normal))
        let unsupported = try solidPixelLayer(r: 200, g: 100, b: 50, blendMode: .normal)
        unsupported.blendMode = .unknown
        root.append(unsupported)
        return try PSDDocument.create(canvasSize: canvasSize, root: root)
    }

    private func compositeSnapshot(topBlendMode: BlendMode) throws -> Data {
        let document = try makeTwoLayerDocument(topBlendMode: topBlendMode)
        let snapshot = EditorRenderSnapshotBuilder.build(from: document, documentRevision: 1)
        let provider = EditorSnapshotPixelProvider.build(from: document, snapshot: snapshot)
        return try EditorSnapshotCompositor.compositeRGBA(snapshot: snapshot, pixels: provider)
    }

    private func previewReference(topBlendMode: BlendMode) throws -> Data {
        let document = try makeTwoLayerDocument(topBlendMode: topBlendMode)
        return document.compositePreviewRGBA()
    }

    private func makeTwoLayerDocument(topBlendMode: BlendMode) throws -> PSDDocument {
        let root = GroupLayer(name: "")
        root.append(try solidPixelLayer(r: 128, g: 64, b: 32, blendMode: .normal))
        root.append(try solidPixelLayer(r: 200, g: 100, b: 50, blendMode: topBlendMode))
        return try PSDDocument.create(canvasSize: canvasSize, root: root)
    }

    private func solidPixelLayer(
        r: UInt8,
        g: UInt8,
        b: UInt8,
        alpha: UInt8 = 255,
        blendMode: BlendMode
    ) throws -> PixelLayer {
        try PixelLayer(
            name: "Layer",
            frame: PSDRect(left: 0, top: 0, right: canvasSize.width, bottom: canvasSize.height),
            pixels: PixelBuffer(
                width: canvasSize.width,
                height: canvasSize.height,
                rgba: Data([r, g, b, alpha])
            ),
            opacity: 255,
            blendMode: blendMode
        )
    }

    private func assertRGBAEqual(_ lhs: Data, _ rhs: Data, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(lhs.count, rhs.count, file: file, line: line)
        for index in 0 ..< lhs.count {
            XCTAssertEqual(lhs[index], rhs[index], "byte \(index)", file: file, line: line)
        }
    }
}
