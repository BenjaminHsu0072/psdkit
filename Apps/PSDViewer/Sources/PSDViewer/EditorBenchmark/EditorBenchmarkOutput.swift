import Foundation

struct EditorTimingStats: Codable, Sendable {
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

struct EditorTextureCacheDiagnosticsReport: Codable, Sendable {
    let textureCount: Int
    let uploadCount: UInt64
    let hitCount: UInt64
    let missCount: UInt64
    let estimatedMemoryBytes: UInt64
}

struct EditorBrushDiagnosticsReport: Codable, Sendable {
    let lastStampedDabCount: Int
    let workingTextureBytes: UInt64
}

struct EditorBenchmarkMetrics: Codable, Sendable {
    let snapshotBuild: EditorTimingStats
    let cpuComposite: EditorTimingStats
    let metalComposite: EditorTimingStats?
    let brushCPURasterize: EditorTimingStats
    let textureCacheAfterMetalComposite: EditorTextureCacheDiagnosticsReport?
    let brushDiagnosticsAfterStamp: EditorBrushDiagnosticsReport?
    let notes: [String]
}

struct EditorBenchmarkEnvironment: Codable, Sendable {
    let osVersion: String
    let hardware: String
    let physicalMemoryBytes: UInt64
    let swiftVersion: String
    let buildConfiguration: String
    let warmupIterations: Int
    let measuredIterations: Int
    let metalAvailable: Bool
    let statistics: String
}

struct EditorBenchmarkReport: Codable, Sendable {
    let fixture: String
    let environment: EditorBenchmarkEnvironment
    let metrics: EditorBenchmarkMetrics
    let generatedAt: String
}

enum EditorBenchmarkOutput {
    static func encodeJSON(_ report: EditorBenchmarkReport) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(ReportEnvelope(report: report))
    }

    private struct ReportEnvelope: Encodable {
        let report: EditorBenchmarkReport
    }
}
