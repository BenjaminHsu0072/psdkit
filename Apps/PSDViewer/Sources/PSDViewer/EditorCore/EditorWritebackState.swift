import Foundation
import PSDKit

/// Minimal E5 writeback state machine shared by tests and DocumentModel.
enum EditorWritebackState: Equatable, Sendable {
    case idleClean
    case idleDirty
    case pendingFlush
    case flushing
    case flushFailed(message: String)
}

enum StrokeWritebackStaleReason: Equatable, Sendable {
    case documentSessionMismatch
    case documentRevisionMismatch
    case layerNotFound
    case layerUUIDMismatch
    case layerPixelRevisionMismatch
    case emptyDirtyRegion

    var diagnosticMessage: String {
        switch self {
        case .documentSessionMismatch:
            return "document session changed"
        case .documentRevisionMismatch:
            return "document revision changed"
        case .layerNotFound:
            return "target layer missing"
        case .layerUUIDMismatch:
            return "layer identity changed"
        case .layerPixelRevisionMismatch:
            return "layer pixels changed since stroke"
        case .emptyDirtyRegion:
            return "stroke dirty region empty"
        }
    }
}

struct StrokeWritebackContext: Equatable, Sendable {
    let documentSessionID: UUID
    let documentRevision: UInt64
    let layerID: String
    let layerUUID: UUID?
    let layerPixelRevision: UInt64
}

enum StrokeWritebackResult: Equatable, Sendable {
    case success
    case noPendingCommit
    case stale(StrokeWritebackStaleReason)
    case failure(String)
}

struct StrokeWritebackDiagnostics: Equatable, Sendable {
    var lastResult: String = ""
    var lastStaleReason: StrokeWritebackStaleReason?
    var lastReadbackRect: PSDRect?
    var lastReadbackPixelCount: Int = 0
    var commitCount: Int = 0
    var rejectedCommitCount: Int = 0

    static let empty = StrokeWritebackDiagnostics()
}

enum StrokeWritebackValidator {
    static func validate(
        pending: PendingStrokeCommit,
        against context: StrokeWritebackContext
    ) -> StrokeWritebackStaleReason? {
        if pending.documentSessionID != context.documentSessionID {
            return .documentSessionMismatch
        }
        if pending.documentRevision != context.documentRevision {
            return .documentRevisionMismatch
        }
        if pending.layerID != context.layerID {
            return .layerNotFound
        }
        if let expectedUUID = pending.layerUUID, let actualUUID = context.layerUUID {
            if expectedUUID != actualUUID {
                return .layerUUIDMismatch
            }
        }
        if pending.layerPixelRevision != context.layerPixelRevision {
            return .layerPixelRevisionMismatch
        }
        if pending.dirtyRegion.isEmpty {
            return .emptyDirtyRegion
        }
        return nil
    }
}
