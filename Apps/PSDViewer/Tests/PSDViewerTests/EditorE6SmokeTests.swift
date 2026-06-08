import CoreGraphics
import Metal
import XCTest
import PSDKit
@testable import PSDViewer

/// E6 umbrella smoke tests: one-file gate coverage across E0–E5 without duplicating deep suites.
final class EditorE6SmokeTests: XCTestCase {
    // MARK: - E0 architecture boundary

    func testE0EditorCoreModuleExistsAndIsTestable() {
        XCTAssertEqual(EditorTool.brush, .brush)
        XCTAssertEqual(EditorWritebackState.idleClean, .idleClean)
    }

    // MARK: - E1 preview routing and CPU composite

    func testE1SupportedSnapshotUsesMetalPath() throws {
        let document = try PSDDocument.makeMidtermStandardDocument()
        let snapshot = EditorRenderSnapshotBuilder.build(from: document, documentRevision: 1)
        XCTAssertNil(
            EditorPreviewRouting.cpuFallbackReason(snapshot: snapshot, userPrefersMetal: true)
        )
    }

    func testE1UnsupportedBlendRequestsCPUFallback() throws {
        let root = GroupLayer(name: "")
        let layer = try PixelLayer(
            name: "Unsupported",
            frame: PSDRect(left: 0, top: 0, right: 1, bottom: 1),
            pixels: PixelBuffer(width: 1, height: 1, rgba: Data([255, 0, 0, 255])),
            blendMode: .unknown
        )
        root.append(layer)
        let document = try PSDDocument.create(canvasSize: PSDSize(width: 1, height: 1), root: root)
        let snapshot = EditorRenderSnapshotBuilder.build(from: document, documentRevision: 0)
        XCTAssertEqual(
            EditorPreviewRouting.cpuFallbackReason(snapshot: snapshot, userPrefersMetal: true),
            .unsupportedBlendMode(.unknown)
        )
    }

    func testE1MidtermStandardCPUCompositeMatchesPreview() throws {
        let document = try PSDDocument.makeMidtermStandardDocument()
        let snapshot = EditorRenderSnapshotBuilder.build(from: document, documentRevision: 1)
        let provider = EditorSnapshotPixelProvider.build(from: document, snapshot: snapshot)
        let composited = try EditorSnapshotCompositor.compositeRGBA(snapshot: snapshot, pixels: provider)
        EditorE6TestSupport.assertRGBAEqual(composited, document.compositePreviewRGBA())
    }

    // MARK: - E2 texture cache

    func testE2TextureCacheHitOnSecondAccess() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw XCTSkip("Metal device unavailable")
        }
        let cache = LayerTextureCache(device: device)
        let document = try PSDDocument.makeMidtermStandardDocument()
        let snapshot = EditorRenderSnapshotBuilder.build(from: document, documentRevision: 1)
        let provider = EditorSnapshotPixelProvider.build(from: document, snapshot: snapshot)
        guard let layer = snapshot.layers.first(where: { $0.kind == .pixel }),
              let payload = provider.rgba(for: layer)
        else {
            XCTFail("missing pixel layer")
            return
        }

        cache.prepareForSnapshot(snapshot)
        _ = try cache.texture(for: layer, payload: payload)
        _ = try cache.texture(for: layer, payload: payload)
        XCTAssertEqual(cache.diagnostics.uploadCount, 1)
        XCTAssertGreaterThanOrEqual(cache.diagnostics.hitCount, 1)
    }

    // MARK: - E3 input state machine

    func testE3NonDrawableToolRejectsStrokeBegin() {
        var session = StrokeSession()
        let viewport = EditorViewport(
            canvasSize: CGSize(width: 16, height: 16),
            viewSize: CGSize(width: 160, height: 160),
            scale: 10,
            translation: .zero
        )
        let context = StrokeInputContext(
            viewport: viewport,
            activeTool: .inspect,
            brushSettings: .defaults,
            drawContext: StrokeDrawContext(
                layerID: "0",
                layerFrame: PSDRect(left: 0, top: 0, right: 16, bottom: 16),
                isEditable: true
            )
        )
        let event = RawPointerEvent(
            viewPoint: CGPoint(x: 80, y: 80),
            phase: .began,
            pressure: 0,
            timestamp: 0
        )
        let result = StrokeInputController.handle(event: event, session: &session, context: context)
        XCTAssertFalse(result.didChange)
        XCTAssertEqual(result.diagnostics.rejectedReason, "non-drawable-tool")
    }

    // MARK: - E4 brush determinism (CPU path, no GPU required)

    func testE4CPURasterizerProducesStableDigest() {
        let plan = EditorE6TestSupport.overlappingBrushPlan()
        var first = Data(repeating: 0, count: plan.layerPixelWidth * plan.layerPixelHeight * 4)
        var second = Data(repeating: 0, count: plan.layerPixelWidth * plan.layerPixelHeight * 4)
        StrokePixelRasterizer.rasterize(
            plan: plan,
            brush: .defaults,
            onto: &first,
            width: plan.layerPixelWidth,
            height: plan.layerPixelHeight
        )
        StrokePixelRasterizer.rasterize(
            plan: plan,
            brush: .defaults,
            onto: &second,
            width: plan.layerPixelWidth,
            height: plan.layerPixelHeight
        )
        XCTAssertEqual(
            EditorPixelRevisionDigest.digest(rgba: first),
            EditorPixelRevisionDigest.digest(rgba: second)
        )
    }

    // MARK: - E5 writeback state machine

    @MainActor
    func testE5WritebackCommitMarksDirtyAndUpdatesComposite() throws {
        let model = EditorE6TestSupport.makeBrushReadyModel()
        guard let document = model.document else {
            XCTFail("missing document")
            return
        }
        let previewBefore = document.compositePreviewRGBA()

        EditorE6TestSupport.drawShortStroke(on: model)
        XCTAssertEqual(model.writebackState, .pendingFlush)

        let result = model.commitPendingStroke()
        XCTAssertEqual(result, .success)
        XCTAssertTrue(model.hasUnsavedChanges)
        XCTAssertEqual(model.writebackDiagnostics.commitCount, 1)
        XCTAssertGreaterThan(model.writebackDiagnostics.lastReadbackPixelCount, 0)

        let previewAfter = document.compositePreviewRGBA()
        XCTAssertNotEqual(
            EditorPixelRevisionDigest.digest(rgba: previewBefore),
            EditorPixelRevisionDigest.digest(rgba: previewAfter)
        )
    }

    // MARK: - Reference: Metal composite vs CPU (GPU optional)

    func testReferenceMetalCompositeMatchesCPUWithinTolerance() throws {
        guard EditorMetalRenderer.canInitialize() else {
            throw XCTSkip("Metal renderer unavailable")
        }
        let document = try PSDDocument.makeMidtermStandardDocument()
        let snapshot = EditorRenderSnapshotBuilder.build(from: document, documentRevision: 1)
        let provider = EditorSnapshotPixelProvider.build(from: document, snapshot: snapshot)
        let cpuRGBA = try EditorSnapshotCompositor.compositeRGBA(snapshot: snapshot, pixels: provider)

        let renderer = try EditorMetalRenderer.makeDefault()
        let gpuRGBA = try renderer.compositeRGBA(snapshot: snapshot, pixels: provider)
        XCTAssertEqual(cpuRGBA.count, gpuRGBA.count)
        XCTAssertTrue(
            EditorE6TestSupport.rgbaApproximatelyEqual(cpuRGBA, gpuRGBA, perChannelTolerance: 1),
            "Metal composite diverged from CPU reference"
        )
    }
}

// MARK: - Shared E6 test helpers

enum EditorE6TestSupport {
    static func assertRGBAEqual(_ lhs: Data, _ rhs: Data, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(lhs.count, rhs.count, file: file, line: line)
        for index in 0 ..< lhs.count {
            XCTAssertEqual(lhs[index], rhs[index], "byte \(index)", file: file, line: line)
        }
    }

    static func rgbaApproximatelyEqual(
        _ lhs: Data,
        _ rhs: Data,
        perChannelTolerance: Int
    ) -> Bool {
        guard lhs.count == rhs.count else { return false }
        for index in lhs.indices {
            if abs(Int(lhs[index]) - Int(rhs[index])) > perChannelTolerance {
                return false
            }
        }
        return true
    }

    static func overlappingBrushPlan() -> BrushRasterizationPlan {
        let dabs = [
            BrushDab(
                center: CGPoint(x: 16, y: 16),
                radius: 10,
                alpha: 0.8,
                color: EditorColor(red: 1, green: 0, blue: 0, alpha: 1)
            ),
            BrushDab(
                center: CGPoint(x: 18, y: 18),
                radius: 10,
                alpha: 0.8,
                color: EditorColor(red: 0, green: 0, blue: 1, alpha: 1)
            ),
        ]
        let dirtyRegion = dabs.reduce(EditorDirtyRegion.empty) { partial, dab in
            partial.union(with: .unionRect(PSDRect(
                left: Int(floor(dab.bounds.minX)),
                top: Int(floor(dab.bounds.minY)),
                right: Int(ceil(dab.bounds.maxX)),
                bottom: Int(ceil(dab.bounds.maxY))
            )))
        }
        return BrushRasterizationPlan(
            strokePlan: BrushStrokePlan(mode: .brush, dabs: dabs, dirtyRegion: dirtyRegion),
            layerID: "0",
            layerFrame: PSDRect(left: 0, top: 0, right: 32, bottom: 32),
            layerPixelWidth: 32,
            layerPixelHeight: 32,
            sampleCount: 2
        )
    }

    @MainActor
    static func makeBrushReadyModel() -> DocumentModel {
        let model = DocumentModel()
        model.generateStandardTestDocument()
        model.setEditorTool(.brush)
        model.editorViewport = EditorViewport(
            canvasSize: CGSize(width: 16, height: 16),
            viewSize: CGSize(width: 160, height: 160),
            scale: 10,
            translation: .zero
        )
        return model
    }

    @MainActor
    static func drawShortStroke(
        on model: DocumentModel,
        from start: CGPoint = CGPoint(x: 50, y: 50),
        to end: CGPoint = CGPoint(x: 100, y: 100)
    ) {
        let mid = CGPoint(x: (start.x + end.x) / 2, y: (start.y + end.y) / 2)
        model.handleRawPointerEvent(RawPointerEvent(viewPoint: start, phase: .began, pressure: 0, timestamp: 0))
        model.handleRawPointerEvent(RawPointerEvent(viewPoint: mid, phase: .moved, pressure: 0, timestamp: 0.1))
        model.handleRawPointerEvent(RawPointerEvent(viewPoint: end, phase: .ended, pressure: 0, timestamp: 0.2))
    }
}
