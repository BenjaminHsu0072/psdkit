import XCTest
@testable import PSDViewer

/// E6 performance/diagnostics baseline smoke. Record-only; no hard thresholds.
final class EditorBenchmarkSmokeTests: XCTestCase {
    func testEditorBenchmarkSmokeProducesReport() throws {
        let outputURL: URL
        let shouldCleanup: Bool
        if let envPath = ProcessInfo.processInfo.environment["EDITOR_BENCHMARK_OUTPUT"], !envPath.isEmpty {
            outputURL = URL(fileURLWithPath: envPath)
            shouldCleanup = false
            try FileManager.default.createDirectory(
                at: outputURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
        } else {
            outputURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("editor-e6-baseline-\(UUID().uuidString).json")
            shouldCleanup = true
        }
        if shouldCleanup {
            defer { try? FileManager.default.removeItem(at: outputURL) }
        }

        try EditorBenchmarkRunner.run(
            options: EditorBenchmarkOptions(
                warmupIterations: 1,
                measuredIterations: 3,
                outputPath: outputURL.path
            )
        )

        let data = try Data(contentsOf: outputURL)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let report = json?["report"] as? [String: Any]
        XCTAssertNotNil(report)

        let metrics = report?["metrics"] as? [String: Any]
        XCTAssertNotNil(metrics?["snapshotBuild"])
        XCTAssertNotNil(metrics?["cpuComposite"])
        XCTAssertNotNil(metrics?["brushCPURasterize"])

        let environment = report?["environment"] as? [String: Any]
        XCTAssertEqual(environment?["warmupIterations"] as? Int, 1)
        XCTAssertEqual(environment?["measuredIterations"] as? Int, 3)
    }
}
