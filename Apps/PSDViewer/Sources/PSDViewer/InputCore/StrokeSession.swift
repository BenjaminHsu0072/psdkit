import CoreGraphics
import Foundation
import PSDKit

enum StrokeSessionPhase: Equatable, Sendable {
    case idle
    case active
    case ended
    case cancelled
}

struct StrokeTarget: Equatable, Sendable {
    let layerID: String
    let layerFrame: PSDRect
}

enum StrokeSessionEndResult: Equatable, Sendable {
    case ended(StrokeSession)
    case cancelled(StrokeSession)
    case ignored
}

/// Records stroke samples and metadata only. Does not write pixels or dispatch editor commands.
struct StrokeSession: Equatable, Sendable {
    private(set) var phase: StrokeSessionPhase = .idle
    private(set) var target: StrokeTarget?
    private(set) var brushSnapshot: BrushSettings = .defaults
    private(set) var samples: [PointerSample] = []
    private(set) var estimatedDirtyBounds: CGRect?

    var isRecording: Bool { phase == .active }

    /// E4/E5 may consult this; E3 never commits pixels from this flag alone.
    var isCommitEligible: Bool {
        phase == .ended && !samples.isEmpty
    }

    mutating func reset() {
        phase = .idle
        target = nil
        brushSnapshot = .defaults
        samples = []
        estimatedDirtyBounds = nil
    }

    @discardableResult
    mutating func begin(
        target: StrokeTarget,
        brush: BrushSettings,
        initialSample: PointerSample
    ) -> Bool {
        guard phase == .idle else { return false }
        guard initialSample.phase == .began else { return false }

        self.target = target
        brushSnapshot = brush
        samples = [initialSample]
        estimatedDirtyBounds = dirtyRect(for: initialSample, brush: brush)
        phase = .active
        return true
    }

    @discardableResult
    mutating func append(_ sample: PointerSample) -> Bool {
        guard phase == .active else { return false }
        guard sample.phase == .moved || sample.phase == .began else { return false }

        samples.append(sample)
        expandDirtyBounds(with: sample)
        return true
    }

    mutating func end(finalSample: PointerSample?) -> StrokeSessionEndResult {
        guard phase == .active else { return .ignored }

        if let finalSample {
            if finalSample.phase == .ended {
                samples.append(finalSample)
                expandDirtyBounds(with: finalSample)
            }
        }
        phase = .ended
        return .ended(self)
    }

    mutating func cancel(reasonSample: PointerSample?) -> StrokeSessionEndResult {
        guard phase == .active || phase == .idle else {
            if phase == .cancelled {
                return .cancelled(self)
            }
            return .ignored
        }

        if phase == .active, let reasonSample {
            samples.append(reasonSample)
        }
        phase = .cancelled
        estimatedDirtyBounds = nil
        return .cancelled(self)
    }

    private mutating func expandDirtyBounds(with sample: PointerSample) {
        let rect = dirtyRect(for: sample, brush: brushSnapshot)
        if let existing = estimatedDirtyBounds {
            estimatedDirtyBounds = existing.union(rect)
        } else {
            estimatedDirtyBounds = rect
        }
    }

    private func dirtyRect(for sample: PointerSample, brush: BrushSettings) -> CGRect {
        let radius = brush.radius(for: sample.pressure)
        return CGRect(
            x: sample.canvasPoint.x - radius,
            y: sample.canvasPoint.y - radius,
            width: radius * 2,
            height: radius * 2
        )
    }
}
