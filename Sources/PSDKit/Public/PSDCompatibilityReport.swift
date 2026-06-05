import Foundation

/// Compatibility findings from opening a PSD (session-only; not written to the file).
public struct PSDCompatibilityReport: Sendable, Equatable {
    public var issues: [PSDCompatibilityIssue]
    public var hasLossyChanges: Bool

    public init(issues: [PSDCompatibilityIssue] = [], hasLossyChanges: Bool = false) {
        self.issues = issues
        self.hasLossyChanges = hasLossyChanges
    }

    public static let empty = PSDCompatibilityReport()
}

public struct PSDCompatibilityIssue: Sendable, Equatable {
    public enum Severity: Sendable, Equatable {
        case info
        case warning
        case error
    }

    public enum Kind: Sendable, Equatable {
        case unsupportedLayerKind
        case unsupportedBlendMode
        case unsupportedMask
        case unsupportedLayerEffect
        case unsupportedCompression
        case droppedLayer
        case rasterizedOrFlattenedContent
    }

    public var severity: Severity
    public var kind: Kind
    public var layerName: String?
    public var message: String

    public init(
        severity: Severity,
        kind: Kind,
        layerName: String? = nil,
        message: String
    ) {
        self.severity = severity
        self.kind = kind
        self.layerName = layerName
        self.message = message
    }
}
