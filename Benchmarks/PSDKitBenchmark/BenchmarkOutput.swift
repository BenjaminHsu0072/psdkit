import Foundation
import PSDKitPerformanceFixtures

struct TimingStats: Codable, Sendable {
    let minSeconds: Double
    let maxSeconds: Double
    let p50Seconds: Double
    let p95Seconds: Double

    init(samples: [Double]) {
        let sorted = samples.sorted()
        minSeconds = sorted.first ?? 0
        maxSeconds = sorted.last ?? 0
        p50Seconds = Self.percentile(sorted, 0.50)
        p95Seconds = Self.percentile(sorted, 0.95)
    }

    private static func percentile(_ sorted: [Double], _ p: Double) -> Double {
        guard !sorted.isEmpty else { return 0 }
        if sorted.count == 1 { return sorted[0] }
        let rank = p * Double(sorted.count - 1)
        let lower = Int(floor(rank))
        let upper = Int(ceil(rank))
        if lower == upper { return sorted[lower] }
        let weight = rank - Double(lower)
        return sorted[lower] * (1 - weight) + sorted[upper] * weight
    }
}

struct BenchmarkMetrics: Codable, Sendable {
    let load: TimingStats
    let semanticSave: TimingStats
    let composite: TimingStats
    let fileSizeBytes: Int
    let peakMemoryBytes: Int
}

struct BenchmarkReport: Codable, Sendable {
    let preset: String
    let fixture: PerformanceFixtureConfig
    let environment: BenchmarkEnvironment
    let metrics: BenchmarkMetrics
    let generatedAt: String
}

enum BenchmarkOutput {
    static func encodeJSON(_ report: BenchmarkReport) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(ReportEnvelope(report: report))
    }

    static func renderMarkdown(_ report: BenchmarkReport) -> String {
        let m = report.metrics
        return """
        # PSDKit Benchmark

        - Preset: `\(report.preset)`
        - Canvas: \(report.fixture.canvasWidth)×\(report.fixture.canvasHeight)
        - Pixel layers: \(report.fixture.pixelLayerCount)
        - Generated at: \(report.generatedAt)

        ## Environment

        | Field | Value |
        |---|---|
        | OS | \(report.environment.osVersion) |
        | Hardware | \(report.environment.hardware) |
        | Physical RAM | \(formatBytes(Int(report.environment.physicalMemoryBytes))) |
        | Swift | \(report.environment.swiftVersion) |
        | Build | \(report.environment.buildConfiguration) |
        | Warmup iterations | \(report.environment.warmupIterations) |
        | Measured iterations | \(report.environment.measuredIterations) |
        | Statistics | \(report.environment.statistics) |
        | Peak memory | \(report.environment.peakMemoryNote) |

        ## Metrics (seconds)

        | Operation | Min | P50 | P95 | Max |
        |---|---:|---:|---:|---:|
        | Load | \(format(m.load.minSeconds)) | \(format(m.load.p50Seconds)) | \(format(m.load.p95Seconds)) | \(format(m.load.maxSeconds)) |
        | Semantic save | \(format(m.semanticSave.minSeconds)) | \(format(m.semanticSave.p50Seconds)) | \(format(m.semanticSave.p95Seconds)) | \(format(m.semanticSave.maxSeconds)) |
        | Composite | \(format(m.composite.minSeconds)) | \(format(m.composite.p50Seconds)) | \(format(m.composite.p95Seconds)) | \(format(m.composite.maxSeconds)) |

        ## File size

        - Semantic PSD size: **\(m.fileSizeBytes)** bytes (\(formatBytes(m.fileSizeBytes)))

        ## Peak memory (resident)

        - Sampled peak: **\(formatBytes(m.peakMemoryBytes))** (\(m.peakMemoryBytes) bytes)
        - Note: \(report.environment.peakMemoryNote)
        """
    }

    private static func format(_ value: Double) -> String {
        String(format: "%.4f", value)
    }

    private static func formatBytes(_ bytes: Int) -> String {
        let kb = Double(bytes) / 1024
        if kb < 1024 { return String(format: "%.1f KB", kb) }
        return String(format: "%.2f MB", kb / 1024)
    }

    private struct ReportEnvelope: Codable {
        let report: BenchmarkReport
    }
}
