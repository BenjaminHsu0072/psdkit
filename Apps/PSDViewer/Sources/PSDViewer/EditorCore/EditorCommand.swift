import Foundation

enum EditorCommandResult: Equatable, Sendable {
    case success
    case failure(EditorCommandError)
}

enum EditorCommandError: Equatable, Sendable {
    case layerNotFound
    case invalidParameter(String)
    case unsupportedBlendMode
    case notImplemented
    case staleWriteback(StrokeWritebackStaleReason)
    case patchApplyFailed(String)
}

/// All document mutations flow through commands. No UI alerts or save side effects.
protocol EditorCommand: Sendable {
    func apply(to adapter: any EditorDocumentAdapter) -> EditorCommandResult
}

struct EditorCommandDispatcher: Sendable {
    func dispatch(_ command: any EditorCommand, through adapter: any EditorDocumentAdapter) -> EditorCommandResult {
        command.apply(to: adapter)
    }
}
