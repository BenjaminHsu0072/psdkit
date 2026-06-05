import Foundation
import PSDKitPerformanceFixtures

struct BenchmarkEnvironment: Codable, Sendable {
    let osVersion: String
    let hardware: String
    let physicalMemoryBytes: UInt64
    let swiftVersion: String
    let buildConfiguration: String
    let warmupIterations: Int
    let measuredIterations: Int
    let statistics: String
    let peakMemoryNote: String
}

enum EnvironmentInfo {
    static func capture(warmupIterations: Int, measuredIterations: Int) -> BenchmarkEnvironment {
        BenchmarkEnvironment(
            osVersion: ProcessInfo.processInfo.operatingSystemVersionString,
            hardware: PerformanceBenchmarkMetadata.hardwareSummary(),
            physicalMemoryBytes: PerformanceBenchmarkMetadata.physicalMemoryBytes(),
            swiftVersion: PerformanceBenchmarkMetadata.swiftToolchainVersion(),
            buildConfiguration: buildConfiguration(),
            warmupIterations: warmupIterations,
            measuredIterations: measuredIterations,
            statistics: "P50, P95, min, max over measured iterations (linear interpolation)",
            peakMemoryNote: "mach_task_basic_info.resident_size max sampled around each measured iteration"
        )
    }

    private static func buildConfiguration() -> String {
        #if DEBUG
        return "debug"
        #else
        return "release"
        #endif
    }
}
