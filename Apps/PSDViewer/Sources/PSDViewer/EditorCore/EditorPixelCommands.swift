import Foundation
import PSDKit

/// Applies a stroke rasterization result to PSDKit pixels through the document adapter.
struct CommitStrokeCommand: EditorCommand {
    let pending: PendingStrokeCommit
    let context: StrokeWritebackContext

    func apply(to adapter: any EditorDocumentAdapter) -> EditorCommandResult {
        if let stale = StrokeWritebackValidator.validate(pending: pending, against: context) {
            return .failure(.staleWriteback(stale))
        }
        guard let rect = pending.dirtyRegion.layerLocalRect(
            pixelWidth: pending.rasterizationPlan.layerPixelWidth,
            pixelHeight: pending.rasterizationPlan.layerPixelHeight
        ) else {
            return .failure(.staleWriteback(.emptyDirtyRegion))
        }

        do {
            let beforePatch = try adapter.extractPixelPatch(
                layerID: pending.layerID,
                rect: rect,
                revision: context.layerPixelRevision
            )

            var rgba = try adapter.layerRGBA(layerID: pending.layerID)
            let width = pending.rasterizationPlan.layerPixelWidth
            let height = pending.rasterizationPlan.layerPixelHeight
            StrokePixelRasterizer.rasterize(
                plan: pending.rasterizationPlan,
                brush: pending.brushSnapshot,
                onto: &rgba,
                width: width,
                height: height
            )

            guard try adapter.replaceLayerRGBA(
                layerID: pending.layerID,
                rgba: rgba,
                width: width,
                height: height
            ) else {
                return .failure(.layerNotFound)
            }

            let afterRevision = EditorPixelRevisionDigest.digest(rgba: rgba)
            let afterPatch = try PixelPatchApplier.extractPatch(
                from: rgba,
                width: width,
                height: height,
                layerID: pending.layerID,
                rect: rect,
                revision: afterRevision
            )

            adapter.notifyContentModified()
            adapter.recordUndoEntry(
                EditorUndoEntry(
                    label: "Stroke",
                    forwardPatch: afterPatch,
                    inversePatch: beforePatch,
                    affectedLayerIDs: [pending.layerID]
                )
            )
            return .success
        } catch let error as PixelPatchError {
            return .failure(.patchApplyFailed(String(describing: error)))
        } catch {
            return .failure(.patchApplyFailed(error.localizedDescription))
        }
    }
}

/// Restores a saved pixel patch (undo inverse or redo forward).
struct ApplyPixelPatchCommand: EditorCommand {
    let patch: LayerPixelPatch

    func apply(to adapter: any EditorDocumentAdapter) -> EditorCommandResult {
        do {
            _ = try adapter.applyPixelPatch(patch)
            adapter.notifyContentModified()
            return .success
        } catch let error as PixelPatchError {
            return .failure(.patchApplyFailed(String(describing: error)))
        } catch {
            return .failure(.patchApplyFailed(error.localizedDescription))
        }
    }
}

/// E0 placeholder: pixel replacement contract only. No texture readback or PNG import.
struct ReplaceLayerPixelsCommand: EditorCommand {
    let layerID: String
    let rgba: Data
    let width: Int
    let height: Int

    func apply(to adapter: any EditorDocumentAdapter) -> EditorCommandResult {
        _ = adapter
        _ = layerID
        _ = rgba
        _ = width
        _ = height
        return .failure(.notImplemented)
    }
}
