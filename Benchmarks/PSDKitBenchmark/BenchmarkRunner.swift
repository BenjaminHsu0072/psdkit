import Foundation
import PSDKit
import PSDKitPerformanceFixtures

struct BenchmarkOptions {
    var preset: PerformanceFixturePreset = .smoke
    var format: OutputFormat = .json
    var warmupIterations: Int = 1
    var measuredIterations: Int = 5
    var outputPath: String?
    var generateOnlyDirectory: String?
}

enum OutputFormat: String {
    case json
    case markdown
}

enum BenchmarkRunner {
    static func run(options: BenchmarkOptions) throws {
        let config = PerformanceFixtureConfig.config(for: options.preset)

        if let directory = options.generateOnlyDirectory {
            try generateFixtures(into: directory, presets: PerformanceFixturePreset.allCases)
            return
        }

        let fixtureData = try buildFixtureData(config: config)
        let metrics = try measure(
            fixtureData: fixtureData,
            warmupIterations: options.warmupIterations,
            measuredIterations: options.measuredIterations
        )

        let report = BenchmarkReport(
            preset: options.preset.rawValue,
            fixture: config,
            environment: EnvironmentInfo.capture(
                warmupIterations: options.warmupIterations,
                measuredIterations: options.measuredIterations
            ),
            metrics: metrics,
            generatedAt: ISO8601DateFormatter().string(from: Date())
        )

        let outputData: Data
        let textOutput: String
        switch options.format {
        case .json:
            outputData = try BenchmarkOutput.encodeJSON(report)
            textOutput = String(decoding: outputData, as: UTF8.self)
        case .markdown:
            textOutput = BenchmarkOutput.renderMarkdown(report)
            outputData = Data(textOutput.utf8)
        }

        if let outputPath = options.outputPath {
            let url = URL(fileURLWithPath: outputPath)
            try outputData.write(to: url, options: .atomic)
            fputs("Wrote benchmark report to \(url.path)\n", stderr)
        } else {
            print(textOutput)
        }
    }

    private static func buildFixtureData(config: PerformanceFixtureConfig) throws -> Data {
        let doc = try PerformanceFixtureFactory.makeDocument(config: config)
        return try doc.data(writeMode: .semantic)
    }

    private static func generateFixtures(into directory: String, presets: [PerformanceFixturePreset]) throws {
        let root = URL(fileURLWithPath: directory, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        for preset in presets {
            let config = PerformanceFixtureConfig.config(for: preset)
            let doc = try PerformanceFixtureFactory.makeDocument(config: config)
            let url = root.appendingPathComponent("\(preset.rawValue).psd")
            try doc.save(to: url, writeMode: .semantic)
            fputs("Generated \(url.path)\n", stderr)
        }
    }

    private static func measure(
        fixtureData: Data,
        warmupIterations: Int,
        measuredIterations: Int
    ) throws -> BenchmarkMetrics {
        for _ in 0 ..< warmupIterations {
            _ = try runOnce(fixtureData: fixtureData)
        }

        var loadSamples: [Double] = []
        var saveSamples: [Double] = []
        var compositeSamples: [Double] = []
        var fileSize = fixtureData.count
        var peakMemoryBytes = 0

        for _ in 0 ..< measuredIterations {
            let sample = try runOnce(fixtureData: fixtureData)
            loadSamples.append(sample.loadSeconds)
            saveSamples.append(sample.saveSeconds)
            compositeSamples.append(sample.compositeSeconds)
            fileSize = sample.fileSizeBytes
            peakMemoryBytes = max(peakMemoryBytes, sample.peakMemoryBytes)
        }

        return BenchmarkMetrics(
            load: TimingStats(samples: loadSamples),
            semanticSave: TimingStats(samples: saveSamples),
            composite: TimingStats(samples: compositeSamples),
            fileSizeBytes: fileSize,
            peakMemoryBytes: peakMemoryBytes
        )
    }

    private struct Sample {
        let loadSeconds: Double
        let saveSeconds: Double
        let compositeSeconds: Double
        let fileSizeBytes: Int
        let peakMemoryBytes: Int
    }

    private static func runOnce(fixtureData: Data) throws -> Sample {
        var peakMemoryBytes = TaskMemorySampler.residentMemoryBytes()

        let loadStart = CFAbsoluteTimeGetCurrent()
        let doc = try PSDDocument.load(data: fixtureData)
        peakMemoryBytes = max(peakMemoryBytes, TaskMemorySampler.residentMemoryBytes())
        let loadSeconds = CFAbsoluteTimeGetCurrent() - loadStart

        let saveStart = CFAbsoluteTimeGetCurrent()
        let saved = try doc.data(writeMode: .semantic)
        peakMemoryBytes = max(peakMemoryBytes, TaskMemorySampler.residentMemoryBytes())
        let saveSeconds = CFAbsoluteTimeGetCurrent() - saveStart

        let compositeStart = CFAbsoluteTimeGetCurrent()
        _ = doc.compositePreviewRGBA()
        peakMemoryBytes = max(peakMemoryBytes, TaskMemorySampler.residentMemoryBytes())
        let compositeSeconds = CFAbsoluteTimeGetCurrent() - compositeStart

        return Sample(
            loadSeconds: loadSeconds,
            saveSeconds: saveSeconds,
            compositeSeconds: compositeSeconds,
            fileSizeBytes: saved.count,
            peakMemoryBytes: peakMemoryBytes
        )
    }
}
