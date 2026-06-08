import CoreGraphics
import Metal
import XCTest
import PSDKit
@testable import PSDViewer

@MainActor
final class EditorWritebackTests: XCTestCase {
    func testCommitPendingStrokeModifiesTargetLayerDirtyRegionOnly() throws {
        let model = makeBrushReadyModel()
        guard let targetLayer = model.selectedPixelLayer,
              let targetID = model.selectedLayerID
        else {
            XCTFail("missing editable target layer")
            return
        }

        let otherLayers = model.layerItems.compactMap { item -> (String, UInt64)? in
            guard item.id != targetID,
                  let path = LayerPath(selectionID: item.id),
                  let layer = LayerListFlattener.resolveLayer(in: model.document!.root, path: path) as? PixelLayer
            else { return nil }
            return (item.id, EditorPixelRevisionDigest.digest(rgba: layer.pixels.rgba))
        }
        XCTAssertFalse(otherLayers.isEmpty)

        let digestBefore = EditorPixelRevisionDigest.digest(rgba: targetLayer.pixels.rgba)
        drawShortStroke(on: model)

        XCTAssertNotNil(model.pendingStrokeCommit)
        XCTAssertEqual(model.writebackState, .pendingFlush)

        let commitResult = model.commitPendingStroke()
        XCTAssertEqual(commitResult, .success)
        XCTAssertNil(model.pendingStrokeCommit)
        XCTAssertTrue(model.hasUnsavedChanges)
        XCTAssertEqual(model.writebackDiagnostics.commitCount, 1)
        XCTAssertGreaterThan(model.writebackDiagnostics.lastReadbackPixelCount, 0)

        let digestAfter = EditorPixelRevisionDigest.digest(rgba: targetLayer.pixels.rgba)
        XCTAssertNotEqual(digestBefore, digestAfter)

        for (layerID, digest) in otherLayers {
            guard let path = LayerPath(selectionID: layerID),
                  let layer = LayerListFlattener.resolveLayer(in: model.document!.root, path: path) as? PixelLayer
            else { continue }
            XCTAssertEqual(EditorPixelRevisionDigest.digest(rgba: layer.pixels.rgba), digest)
        }
    }

    func testStaleDocumentRevisionRejectsWriteback() {
        let model = makeBrushReadyModel()
        drawShortStroke(on: model)
        guard let path = model.selectedLayerPath else {
            XCTFail("missing selected layer path")
            return
        }
        model.renameLayer(at: path, to: "Revision Bump")

        let result = model.commitPendingStroke()
        XCTAssertEqual(result, .stale(.documentRevisionMismatch))
        XCTAssertNotNil(model.pendingStrokeCommit)
        XCTAssertEqual(model.writebackDiagnostics.rejectedCommitCount, 1)
        XCTAssertEqual(model.writebackDiagnostics.lastStaleReason, .documentRevisionMismatch)
        XCTAssertNotNil(model.pendingStrokeCommit)
    }

    func testStaleLayerPixelRevisionRejectsWriteback() throws {
        let model = makeBrushReadyModel()
        drawShortStroke(on: model)
        guard let layer = model.selectedPixelLayer else {
            XCTFail("missing layer")
            return
        }
        var rgba = layer.pixels.rgba
        if !rgba.isEmpty {
            rgba[0] = rgba[0] == 255 ? 254 : 255
            layer.pixels = try PixelBuffer(width: layer.pixels.width, height: layer.pixels.height, rgba: rgba)
        }

        let result = model.commitPendingStroke()
        XCTAssertEqual(result, .stale(.layerPixelRevisionMismatch))
        XCTAssertEqual(model.writebackDiagnostics.lastStaleReason, .layerPixelRevisionMismatch)
        XCTAssertNotNil(model.pendingStrokeCommit)
    }

    func testMissingLayerRejectsWriteback() {
        let model = makeBrushReadyModel()
        drawShortStroke(on: model)
        model.removeSelectedLayer()

        let result = model.commitPendingStroke()
        XCTAssertEqual(result, .stale(.layerNotFound))
        XCTAssertEqual(model.writebackDiagnostics.lastStaleReason, .layerNotFound)
    }

    func testWritebackSuccessMarksDirtyAndSaveClearsDirty() throws {
        let model = makeBrushReadyModel()
        let temp = FileManager.default.temporaryDirectory
            .appendingPathComponent("writeback-save-\(UUID().uuidString).psd")
        defer { try? FileManager.default.removeItem(at: temp) }

        drawShortStroke(on: model)
        XCTAssertEqual(model.commitPendingStroke(), .success)
        XCTAssertTrue(model.hasUnsavedChanges)

        model.saveDocumentAs(urlOverrideForTests: temp)
        XCTAssertFalse(model.hasUnsavedChanges)
        XCTAssertEqual(model.writebackState, .idleClean)
    }

    func testUndoRedoRestoresPixelsWithoutTouchingOtherLayers() throws {
        let model = makeBrushReadyModel()
        guard let targetLayer = model.selectedPixelLayer,
              let targetID = model.selectedLayerID
        else {
            XCTFail("missing layer")
            return
        }
        let otherDigests = model.layerItems.compactMap { item -> (String, UInt64)? in
            guard item.id != targetID,
                  let path = LayerPath(selectionID: item.id),
                  let layer = LayerListFlattener.resolveLayer(in: model.document!.root, path: path) as? PixelLayer
            else { return nil }
            return (item.id, EditorPixelRevisionDigest.digest(rgba: layer.pixels.rgba))
        }

        let digestBefore = EditorPixelRevisionDigest.digest(rgba: targetLayer.pixels.rgba)
        drawShortStroke(on: model)
        XCTAssertEqual(model.commitPendingStroke(), .success)
        let digestAfterStroke = EditorPixelRevisionDigest.digest(rgba: targetLayer.pixels.rgba)
        XCTAssertNotEqual(digestBefore, digestAfterStroke)

        model.undoStrokeEdit()
        XCTAssertEqual(EditorPixelRevisionDigest.digest(rgba: targetLayer.pixels.rgba), digestBefore)

        model.redoStrokeEdit()
        XCTAssertEqual(EditorPixelRevisionDigest.digest(rgba: targetLayer.pixels.rgba), digestAfterStroke)

        for (layerID, digest) in otherDigests {
            guard let path = LayerPath(selectionID: layerID),
                  let layer = LayerListFlattener.resolveLayer(in: model.document!.root, path: path) as? PixelLayer
            else { continue }
            XCTAssertEqual(EditorPixelRevisionDigest.digest(rgba: layer.pixels.rgba), digest)
        }
    }

    func testWritebackUpdatesRenderSnapshotPixelRevisionAndCacheInvalidates() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw XCTSkip("Metal unavailable")
        }

        let model = makeBrushReadyModel()
        guard let pendingTargetID = model.selectedLayerID,
              let snapshotBefore = model.renderSnapshot,
              let layerBefore = snapshotBefore.layers.first(where: { $0.id == pendingTargetID })
        else {
            XCTFail("missing snapshot layer")
            return
        }

        let cache = LayerTextureCache(device: device)
        cache.prepareForSnapshot(snapshotBefore)
        guard let payload = model.snapshotPixels.rgba(for: layerBefore) else {
            XCTFail("missing pixel payload")
            return
        }
        _ = try cache.texture(for: layerBefore, payload: payload)
        XCTAssertEqual(cache.diagnostics.uploadCount, 1)

        drawShortStroke(on: model)
        XCTAssertEqual(model.commitPendingStroke(), .success)

        guard let snapshotAfter = model.renderSnapshot,
              let layerAfter = snapshotAfter.layers.first(where: { $0.id == pendingTargetID })
        else {
            XCTFail("missing post-commit snapshot")
            return
        }
        XCTAssertNotEqual(layerBefore.pixelRevision, layerAfter.pixelRevision)

        cache.prepareForSnapshot(snapshotAfter)
        guard let payloadAfter = model.snapshotPixels.rgba(for: layerAfter) else {
            XCTFail("missing post-commit payload")
            return
        }
        _ = try cache.texture(for: layerAfter, payload: payloadAfter)
        XCTAssertEqual(cache.diagnostics.uploadCount, 2)
        XCTAssertTrue(cache.diagnostics.lastInvalidationReasons.contains(.layerPixelRevisionChanged))
    }

    func testSaveFlushesPendingStrokeBeforeWriting() throws {
        let model = makeBrushReadyModel()
        let temp = FileManager.default.temporaryDirectory
            .appendingPathComponent("writeback-flush-\(UUID().uuidString).psd")
        defer { try? FileManager.default.removeItem(at: temp) }

        drawShortStroke(on: model)
        XCTAssertNotNil(model.pendingStrokeCommit)
        model.saveDocumentAs(urlOverrideForTests: temp)
        XCTAssertNil(model.pendingStrokeCommit)
        XCTAssertFalse(model.hasUnsavedChanges)

        let reopened = try PSDDocument.load(url: temp)
        let flattened = LayerListFlattener.flatten(root: reopened.root)
        guard let reopenedLayer = flattened.first(where: { $0.id == model.selectedLayerID }),
              let path = LayerPath(selectionID: reopenedLayer.id),
              let pixel = LayerListFlattener.resolveLayer(in: reopened.root, path: path) as? PixelLayer
        else {
            XCTFail("missing reopened layer")
            return
        }
        let digest = EditorPixelRevisionDigest.digest(rgba: pixel.pixels.rgba)
        XCTAssertNotEqual(digest, 0)
    }

    func testFlushFailureBlocksSave() {
        let model = makeBrushReadyModel()
        drawShortStroke(on: model)
        guard let path = model.selectedLayerPath else {
            XCTFail("missing selected layer path")
            return
        }
        model.renameLayer(at: path, to: "Blocked Save")

        model.saveDocumentAs(urlOverrideForTests: FileManager.default.temporaryDirectory.appendingPathComponent("blocked-\(UUID().uuidString).psd"))
        XCTAssertTrue(model.hasUnsavedChanges)
        XCTAssertNotNil(model.pendingStrokeCommit)
        XCTAssertEqual(model.writebackState, .flushFailed(message: StrokeWritebackStaleReason.documentRevisionMismatch.diagnosticMessage))
    }

    func testPixelPatchExtractApplyRoundtripWithNonZeroLeftPreservesSurroundingPixels() throws {
        let width = 16
        let height = 16
        var rgba = Data(count: width * height * 4)
        for y in 0 ..< height {
            for x in 0 ..< width {
                let offset = (y * width + x) * 4
                rgba[offset] = UInt8(x)
                rgba[offset + 1] = UInt8(y)
                rgba[offset + 2] = UInt8((x + y) % 256)
                rgba[offset + 3] = 255
            }
        }
        let layer = try PixelLayer(
            name: "Patch",
            frame: PSDRect(left: 0, top: 0, right: width, bottom: height),
            pixels: PixelBuffer(width: width, height: height, rgba: rgba)
        )
        let originalRGBA = rgba

        let rect = PSDRect(left: 4, top: 2, right: 12, bottom: 6)
        let extracted = try PixelPatchApplier.extractPatch(
            from: layer,
            layerID: "0",
            rect: rect,
            revision: 0
        )
        XCTAssertEqual(extracted.rgba[0], 4)
        XCTAssertEqual(extracted.rgba[1], 2)
        XCTAssertEqual(extracted.rgba[2], UInt8((4 + 2) % 256))

        var modifiedRGBA = extracted.rgba
        for index in stride(from: 0, to: modifiedRGBA.count, by: 4) {
            modifiedRGBA[index] = 200
            modifiedRGBA[index + 1] = 50
            modifiedRGBA[index + 2] = 75
            modifiedRGBA[index + 3] = 255
        }
        let forwardPatch = LayerPixelPatch(
            layerID: extracted.layerID,
            rect: extracted.rect,
            rgba: modifiedRGBA,
            rowBytes: extracted.rowBytes,
            pixelFormat: extracted.pixelFormat,
            sourceRevision: extracted.sourceRevision,
            resultRevision: extracted.resultRevision
        )

        let inverse = try PixelPatchApplier.apply(patch: forwardPatch, to: layer)

        for y in 0 ..< height {
            for x in 0 ..< width {
                let offset = (y * width + x) * 4
                let inside = x >= rect.left && x < rect.right && y >= rect.top && y < rect.bottom
                if inside {
                    XCTAssertEqual(layer.pixels.rgba[offset], 200)
                    XCTAssertEqual(layer.pixels.rgba[offset + 1], 50)
                    XCTAssertEqual(layer.pixels.rgba[offset + 2], 75)
                } else {
                    XCTAssertEqual(layer.pixels.rgba[offset], originalRGBA[offset])
                    XCTAssertEqual(layer.pixels.rgba[offset + 1], originalRGBA[offset + 1])
                    XCTAssertEqual(layer.pixels.rgba[offset + 2], originalRGBA[offset + 2])
                    XCTAssertEqual(layer.pixels.rgba[offset + 3], originalRGBA[offset + 3])
                }
            }
        }

        _ = try PixelPatchApplier.apply(patch: inverse, to: layer)
        XCTAssertEqual(layer.pixels.rgba, originalRGBA)
    }

    func testSecondStrokeFlushesPriorPendingWithoutOverwrite() throws {
        let model = makeBrushReadyModel()
        guard let targetLayer = model.selectedPixelLayer else {
            XCTFail("missing target layer")
            return
        }
        let digestBefore = EditorPixelRevisionDigest.digest(rgba: targetLayer.pixels.rgba)

        drawShortStroke(on: model)
        guard let firstPending = model.pendingStrokeCommit else {
            XCTFail("missing first pending commit")
            return
        }
        XCTAssertEqual(
            EditorPixelRevisionDigest.digest(rgba: targetLayer.pixels.rgba),
            digestBefore,
            "first stroke must stay preview-only until flushed"
        )

        drawShortStroke(on: model, from: CGPoint(x: 60, y: 60), to: CGPoint(x: 110, y: 110))

        let digestAfterFirstFlush = EditorPixelRevisionDigest.digest(rgba: targetLayer.pixels.rgba)
        XCTAssertNotEqual(digestAfterFirstFlush, digestBefore, "first stroke pixels must land in document")
        XCTAssertEqual(model.writebackDiagnostics.commitCount, 1)
        XCTAssertNotNil(model.pendingStrokeCommit)
        XCTAssertTrue(model.hasUnsavedChanges)
        XCTAssertGreaterThan(
            model.pendingStrokeCommit?.documentRevision ?? 0,
            firstPending.documentRevision
        )
        XCTAssertNotEqual(
            model.pendingStrokeCommit?.layerPixelRevision,
            firstPending.layerPixelRevision
        )
    }

    func testSecondStrokeRetainsPriorPendingWhenFlushFails() {
        let model = makeBrushReadyModel()
        drawShortStroke(on: model)
        guard let firstPending = model.pendingStrokeCommit else {
            XCTFail("missing first pending commit")
            return
        }
        guard let path = model.selectedLayerPath else {
            XCTFail("missing selected layer path")
            return
        }
        model.renameLayer(at: path, to: "Stale Revision")

        drawShortStroke(on: model, from: CGPoint(x: 60, y: 60), to: CGPoint(x: 110, y: 110))

        XCTAssertEqual(model.writebackDiagnostics.commitCount, 0)
        XCTAssertEqual(model.pendingStrokeCommit?.layerID, firstPending.layerID)
        XCTAssertEqual(model.pendingStrokeCommit?.documentRevision, firstPending.documentRevision)
        XCTAssertEqual(model.strokePreviewDiagnostics.rejectionReason, "prior-pending-flush-stale")
        XCTAssertEqual(model.writebackState, .flushFailed(message: StrokeWritebackStaleReason.documentRevisionMismatch.diagnosticMessage))
    }

    func testRequestCloseBlockedWhenCleanButPendingStroke() throws {
        let model = makeBrushReadyModel()
        model.shouldRequireLossySaveConfirmation = { _ in false }
        let temp = FileManager.default.temporaryDirectory
            .appendingPathComponent("close-pending-\(UUID().uuidString).psd")
        defer { try? FileManager.default.removeItem(at: temp) }
        model.saveDocumentAs(urlOverrideForTests: temp)
        XCTAssertFalse(model.hasUnsavedChanges)

        drawShortStroke(on: model)
        XCTAssertNotNil(model.pendingStrokeCommit)

        var closed = false
        model.requestCloseDocument { closed = true }
        XCTAssertFalse(closed)
        XCTAssertTrue(model.isShowingUnsavedCloseConfirmation)
    }

    func testSaveAndCloseFlushesPendingStrokeBeforeClosing() throws {
        let model = makeBrushReadyModel()
        model.shouldRequireLossySaveConfirmation = { _ in false }
        let temp = FileManager.default.temporaryDirectory
            .appendingPathComponent("save-close-pending-\(UUID().uuidString).psd")
        defer { try? FileManager.default.removeItem(at: temp) }
        model.saveDocumentAs(urlOverrideForTests: temp)
        XCTAssertFalse(model.hasUnsavedChanges)

        drawShortStroke(on: model)
        XCTAssertNotNil(model.pendingStrokeCommit)

        var closed = false
        model.requestCloseDocument { closed = true }
        XCTAssertTrue(model.isShowingUnsavedCloseConfirmation)

        model.saveAndCloseDocument()
        XCTAssertTrue(closed)
        XCTAssertNil(model.pendingStrokeCommit)
        XCTAssertFalse(model.hasUnsavedChanges)
    }

    func testFlushFailedBlocksClose() {
        let model = makeBrushReadyModel()
        drawShortStroke(on: model)
        guard let path = model.selectedLayerPath else {
            XCTFail("missing selected layer path")
            return
        }
        model.renameLayer(at: path, to: "Flush Failed")

        _ = model.commitPendingStroke()
        XCTAssertTrue(model.isWritebackFlushFailed)

        var closed = false
        model.requestCloseDocument { closed = true }
        XCTAssertFalse(closed)
        XCTAssertFalse(model.isShowingUnsavedCloseConfirmation)
        XCTAssertTrue(model.statusMessage.contains("Close blocked"))

        model.requestCloseDocument { closed = true }
        model.saveAndCloseDocument()
        XCTAssertFalse(closed)
        XCTAssertTrue(model.statusMessage.contains("Close blocked"))
    }

    func testActiveStrokeBlocksSave() throws {
        let model = makeBrushReadyModel()
        model.shouldRequireLossySaveConfirmation = { _ in false }
        let temp = FileManager.default.temporaryDirectory
            .appendingPathComponent("active-stroke-save-\(UUID().uuidString).psd")
        defer { try? FileManager.default.removeItem(at: temp) }

        model.saveDocumentAs(urlOverrideForTests: temp)
        XCTAssertFalse(model.hasUnsavedChanges)
        let savedDigest = try digestOfSelectedLayer(in: temp, layerID: model.selectedLayerID)

        seedActiveStroke(on: model)
        XCTAssertTrue(model.hasActiveStrokeRecording)
        XCTAssertNil(model.pendingStrokeCommit)

        model.saveDocument()
        XCTAssertTrue(model.hasActiveStrokeRecording)
        XCTAssertNil(model.pendingStrokeCommit)
        XCTAssertFalse(model.hasUnsavedChanges)
        XCTAssertEqual(model.writebackDiagnostics.commitCount, 0)
        XCTAssertTrue(model.statusMessage.contains("blocked"))
        XCTAssertTrue(model.statusMessage.contains("finish or cancel"))

        let afterBlockedSaveDigest = try digestOfSelectedLayer(in: temp, layerID: model.selectedLayerID)
        XCTAssertEqual(savedDigest, afterBlockedSaveDigest)
    }

    func testActiveStrokeBlocksSaveAndClose() throws {
        let model = makeBrushReadyModel()
        model.shouldRequireLossySaveConfirmation = { _ in false }
        let temp = FileManager.default.temporaryDirectory
            .appendingPathComponent("active-stroke-save-close-\(UUID().uuidString).psd")
        defer { try? FileManager.default.removeItem(at: temp) }

        model.saveDocumentAs(urlOverrideForTests: temp)
        XCTAssertFalse(model.hasUnsavedChanges)

        seedActiveStroke(on: model)
        XCTAssertTrue(model.hasActiveStrokeRecording)

        var closed = false
        model.requestCloseDocument { closed = true }
        XCTAssertTrue(model.isShowingUnsavedCloseConfirmation)

        model.saveAndCloseDocument()
        XCTAssertFalse(closed)
        XCTAssertTrue(model.hasActiveStrokeRecording)
        XCTAssertNil(model.pendingStrokeCommit)
        XCTAssertTrue(model.isShowingUnsavedCloseConfirmation)
        XCTAssertTrue(model.statusMessage.contains("blocked"))
    }

    func testActiveStrokeRequestCloseShowsGuard() throws {
        let model = makeBrushReadyModel()
        model.shouldRequireLossySaveConfirmation = { _ in false }
        let temp = FileManager.default.temporaryDirectory
            .appendingPathComponent("active-stroke-close-guard-\(UUID().uuidString).psd")
        defer { try? FileManager.default.removeItem(at: temp) }
        model.saveDocumentAs(urlOverrideForTests: temp)

        seedActiveStroke(on: model)
        XCTAssertTrue(model.hasActiveStrokeRecording)
        XCTAssertFalse(model.hasUnsavedChanges)

        var closed = false
        model.requestCloseDocument { closed = true }

        XCTAssertFalse(closed)
        XCTAssertTrue(model.isShowingUnsavedCloseConfirmation)
        XCTAssertTrue(model.statusMessage.contains("Finish or cancel"))
    }

    func testUndoWithPendingFlushCommitsThenRestoresPixels() throws {
        let model = makeBrushReadyModel()
        guard let targetLayer = model.selectedPixelLayer else {
            XCTFail("missing target layer")
            return
        }
        let digestBefore = EditorPixelRevisionDigest.digest(rgba: targetLayer.pixels.rgba)

        drawShortStroke(on: model)
        XCTAssertNotNil(model.pendingStrokeCommit)
        XCTAssertEqual(model.writebackState, .pendingFlush)

        model.undoStrokeEdit()

        XCTAssertNil(model.pendingStrokeCommit)
        XCTAssertEqual(model.writebackDiagnostics.commitCount, 1)
        XCTAssertEqual(EditorPixelRevisionDigest.digest(rgba: targetLayer.pixels.rgba), digestBefore)
        XCTAssertTrue(model.statusMessage.contains("Undid"))
    }

    func testUndoBlockedWhenFlushFailedDoesNotMutatePixels() throws {
        let model = makeBrushReadyModel()
        guard let targetLayer = model.selectedPixelLayer else {
            XCTFail("missing target layer")
            return
        }
        let digestBefore = EditorPixelRevisionDigest.digest(rgba: targetLayer.pixels.rgba)

        drawShortStroke(on: model)
        guard let path = model.selectedLayerPath else {
            XCTFail("missing selected layer path")
            return
        }
        model.renameLayer(at: path, to: "Stale For Undo")

        let commitResult = model.commitPendingStroke()
        XCTAssertEqual(commitResult, .stale(.documentRevisionMismatch))
        XCTAssertTrue(model.isWritebackFlushFailed)
        XCTAssertNotNil(model.pendingStrokeCommit)

        model.undoStrokeEdit()

        XCTAssertNotNil(model.pendingStrokeCommit)
        XCTAssertTrue(model.isWritebackFlushFailed)
        XCTAssertEqual(EditorPixelRevisionDigest.digest(rgba: targetLayer.pixels.rgba), digestBefore)
        XCTAssertTrue(model.statusMessage.contains("Complete or cancel pending stroke"))
    }

    func testPixelPatchApplierRejectsOutOfBoundsRect() throws {
        let layer = try PSDDocument.makePixelLayer(
            name: "Patch",
            frame: PSDRect(left: 0, top: 0, right: 8, bottom: 8),
            rgba: Data(repeating: 0, count: 8 * 8 * 4)
        )
        let document = try PSDDocument.create(width: 8, height: 8, layers: [layer])
        let pixelLayer = try XCTUnwrap(document.layers.children.first as? PixelLayer)
        XCTAssertThrowsError(
            try PixelPatchApplier.extractPatch(
                from: pixelLayer,
                layerID: "0",
                rect: PSDRect(left: 0, top: 0, right: 9, bottom: 8),
                revision: 0
            )
        )
    }

    private func makeBrushReadyModel() -> DocumentModel {
        let model = DocumentModel()
        model.generateStandardTestDocument()
        configureBrushViewport(on: model)
        return model
    }

    private func configureBrushViewport(on model: DocumentModel) {
        model.setEditorTool(.brush)
        model.editorViewport = EditorViewport(
            canvasSize: CGSize(width: 16, height: 16),
            viewSize: CGSize(width: 160, height: 160),
            scale: 10,
            translation: .zero
        )
    }

    private func drawShortStroke(
        on model: DocumentModel,
        from start: CGPoint = CGPoint(x: 50, y: 50),
        to end: CGPoint = CGPoint(x: 100, y: 100)
    ) {
        let mid = CGPoint(x: (start.x + end.x) / 2, y: (start.y + end.y) / 2)
        model.handleRawPointerEvent(RawPointerEvent(viewPoint: start, phase: .began, pressure: 0, timestamp: 0))
        model.handleRawPointerEvent(RawPointerEvent(viewPoint: mid, phase: .moved, pressure: 0, timestamp: 0.1))
        model.handleRawPointerEvent(RawPointerEvent(viewPoint: end, phase: .ended, pressure: 0, timestamp: 0.2))
    }

    private func seedActiveStroke(on model: DocumentModel) {
        model.handleRawPointerEvent(
            RawPointerEvent(viewPoint: CGPoint(x: 50, y: 50), phase: .began, pressure: 0, timestamp: 0)
        )
        XCTAssertTrue(model.hasActiveStrokeRecording)
    }

    private func digestOfSelectedLayer(in url: URL, layerID: String?) throws -> UInt64 {
        let reopened = try PSDDocument.load(url: url)
        let flattened = LayerListFlattener.flatten(root: reopened.root)
        guard let layerID,
              let reopenedLayer = flattened.first(where: { $0.id == layerID }),
              let path = LayerPath(selectionID: reopenedLayer.id),
              let pixel = LayerListFlattener.resolveLayer(in: reopened.root, path: path) as? PixelLayer
        else {
            throw NSError(domain: "EditorWritebackTests", code: 1)
        }
        return EditorPixelRevisionDigest.digest(rgba: pixel.pixels.rgba)
    }
}
