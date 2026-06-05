import Foundation
import PSDKitPerformanceFixtures

enum BenchmarkCLI {
    static func main() {
        do {
            let options = try parse(Array(CommandLine.arguments.dropFirst()))
            try BenchmarkRunner.run(options: options)
        } catch {
            fputs("error: \(error)\n\n", stderr)
            printUsage()
            exit(1)
        }
    }

    private static func parse(_ args: [String]) throws -> BenchmarkOptions {
        var options = BenchmarkOptions()
        var index = 0
        while index < args.count {
            let arg = args[index]
            switch arg {
            case "--help", "-h":
                printUsage()
                exit(0)
            case "--preset":
                index += 1
                guard index < args.count, let preset = PerformanceFixturePreset(rawValue: args[index]) else {
                    throw CLIError.invalidValue("--preset", args[safe: index])
                }
                options.preset = preset
            case "--format":
                index += 1
                guard index < args.count, let format = OutputFormat(rawValue: args[index]) else {
                    throw CLIError.invalidValue("--format", args[safe: index])
                }
                options.format = format
            case "--warmup":
                index += 1
                guard index < args.count, let value = Int(args[index]), value >= 0 else {
                    throw CLIError.invalidValue("--warmup", args[safe: index])
                }
                options.warmupIterations = value
            case "--iterations":
                index += 1
                guard index < args.count, let value = Int(args[index]), value >= 1 else {
                    throw CLIError.invalidValue("--iterations", args[safe: index])
                }
                options.measuredIterations = value
            case "--output":
                index += 1
                guard index < args.count else { throw CLIError.missingValue("--output") }
                options.outputPath = args[index]
            case "--generate-only":
                index += 1
                guard index < args.count else { throw CLIError.missingValue("--generate-only") }
                options.generateOnlyDirectory = args[index]
            default:
                throw CLIError.unknownArgument(arg)
            }
            index += 1
        }
        return options
    }

    private static func printUsage() {
        print(
            """
            PSDKitBenchmark — performance smoke/baseline runner

            Usage:
              swift run PSDKitBenchmark [--preset smoke|small|medium|stress] [--format json|markdown] \\
                [--warmup 1] [--iterations 5] [--output path]

            Generate fixture files without measuring:
              swift run PSDKitBenchmark --generate-only /tmp/psdkit-fixtures

            Defaults: --preset smoke --format json --warmup 1 --iterations 5
            """
        )
    }
}

private enum CLIError: LocalizedError {
    case unknownArgument(String)
    case missingValue(String)
    case invalidValue(String, String?)

    var errorDescription: String? {
        switch self {
        case .unknownArgument(let arg):
            return "unknown argument: \(arg)"
        case .missingValue(let flag):
            return "missing value for \(flag)"
        case .invalidValue(let flag, let value):
            return "invalid value for \(flag): \(value ?? "<missing>")"
        }
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

BenchmarkCLI.main()
