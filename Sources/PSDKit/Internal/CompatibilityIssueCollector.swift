import Foundation

/// Collects compatibility findings while building a document from a PSD read.
struct CompatibilityIssueCollector {
    private(set) var issues: [PSDCompatibilityIssue] = []

    mutating func recordUnsupportedBlendMode(layerName: String) {
        issues.append(
            PSDCompatibilityIssue(
                severity: .warning,
                kind: .unsupportedBlendMode,
                layerName: layerName,
                message: Self.unsupportedBlendModeMessage
            )
        )
    }

    mutating func recordUnsupportedMask(layerName: String) {
        issues.append(
            PSDCompatibilityIssue(
                severity: .warning,
                kind: .unsupportedMask,
                layerName: layerName,
                message: Self.unsupportedMaskMessage
            )
        )
    }

    mutating func recordUnsupportedLayerEffect(layerName: String) {
        issues.append(
            PSDCompatibilityIssue(
                severity: .warning,
                kind: .unsupportedLayerEffect,
                layerName: layerName,
                message: Self.unsupportedLayerEffectMessage
            )
        )
    }

    mutating func recordDroppedUnsupportedLayer(layerName: String, kindLabel: String) {
        issues.append(
            PSDCompatibilityIssue(
                severity: .warning,
                kind: .unsupportedLayerKind,
                layerName: layerName,
                message: Self.unsupportedLayerKindMessage(for: kindLabel)
            )
        )
        issues.append(
            PSDCompatibilityIssue(
                severity: .warning,
                kind: .droppedLayer,
                layerName: layerName,
                message: Self.droppedLayerMessage
            )
        )
    }

    var report: PSDCompatibilityReport {
        PSDCompatibilityReport(issues: issues, hasLossyChanges: !issues.isEmpty)
    }

    private static let unsupportedBlendModeMessage =
        "Unsupported blend mode; layer was imported as Normal."
    private static let unsupportedMaskMessage =
        "Layer mask is not supported; mask was ignored."
    private static let unsupportedLayerEffectMessage =
        "Layer effects are not supported; effects were ignored."
    private static let droppedLayerMessage =
        "Layer was omitted from the editable document."

    private static func unsupportedLayerKindMessage(for kindLabel: String) -> String {
        switch kindLabel {
        case "text":
            return "Text layers are not supported; layer was dropped."
        case "smart object":
            return "Smart Objects are not supported; layer was dropped."
        case "adjustment":
            return "Adjustment layers are not supported; layer was dropped."
        default:
            return "This layer type is not supported; layer was dropped."
        }
    }
}
