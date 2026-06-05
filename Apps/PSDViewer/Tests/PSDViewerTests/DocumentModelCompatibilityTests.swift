import PSDKit
import XCTest
@testable import PSDViewer

@MainActor
final class DocumentModelCompatibilityTests: XCTestCase {
    func testCompatibilitySummaryNilWhenFullySupported() {
        XCTAssertNil(DocumentModel.compatibilitySummary(from: .empty))
    }

    func testCompatibilitySummaryIncludesSingleIssueMessage() {
        let report = PSDCompatibilityReport(
            issues: [
                PSDCompatibilityIssue(
                    severity: .warning,
                    kind: .unsupportedMask,
                    layerName: "Layer 1",
                    message: "Layer mask is not supported; mask was ignored."
                ),
            ],
            hasLossyChanges: true
        )
        let summary = DocumentModel.compatibilitySummary(from: report)
        XCTAssertEqual(
            summary,
            "部分 PSD 特性不受支持，已降级、忽略或丢弃。 Layer mask is not supported; mask was ignored."
        )
    }

    func testCompatibilitySummaryCountsMultipleIssues() {
        let report = PSDCompatibilityReport(
            issues: [
                PSDCompatibilityIssue(
                    severity: .warning,
                    kind: .unsupportedBlendMode,
                    layerName: "A",
                    message: "Unsupported blend mode; layer was imported as Normal."
                ),
                PSDCompatibilityIssue(
                    severity: .warning,
                    kind: .droppedLayer,
                    layerName: "B",
                    message: "Layer was omitted from the editable document."
                ),
            ],
            hasLossyChanges: true
        )
        let summary = DocumentModel.compatibilitySummary(from: report)
        XCTAssertEqual(
            summary,
            "部分 PSD 特性不受支持，已降级、忽略或丢弃。（2 项警告）"
        )
    }
}
