import Foundation

#if canImport(Darwin)
import Darwin
#endif

/// Runtime metadata for benchmark reports (`docs/midterm-plan/06-performance.md`).
public enum PerformanceBenchmarkMetadata {
    public static func swiftToolchainVersion() -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/swift")
        process.arguments = ["--version"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let text = String(decoding: data, as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty {
                return text.replacingOccurrences(of: "\n", with: " ")
            }
        } catch {
            // Fall through to compile-time hint.
        }
        return compileTimeSwiftHint()
    }

    public static func hardwareSummary() -> String {
        let model = machineModelIdentifier()
        let memoryGB = String(format: "%.1f", Double(physicalMemoryBytes()) / 1_073_741_824)
        let cores = ProcessInfo.processInfo.processorCount
        if model.isEmpty {
            return "\(cores) logical CPUs, \(memoryGB) GB RAM"
        }
        return "\(model), \(cores) logical CPUs, \(memoryGB) GB RAM"
    }

    public static func physicalMemoryBytes() -> UInt64 {
        UInt64(ProcessInfo.processInfo.physicalMemory)
    }

    private static func machineModelIdentifier() -> String {
        #if canImport(Darwin)
        var size: Int = 0
        guard sysctlbyname("hw.model", nil, &size, nil, 0) == 0, size > 0 else {
            return ""
        }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname("hw.model", &buffer, &size, nil, 0) == 0 else {
            return ""
        }
        return String(cString: buffer)
        #else
        return ""
        #endif
    }

    private static func compileTimeSwiftHint() -> String {
        #if swift(>=6.0)
        return "Swift 6.x (compile-time; swift --version unavailable)"
        #elseif swift(>=5.9)
        return "Swift 5.9+ (compile-time; swift --version unavailable)"
        #else
        return "Swift (compile-time; swift --version unavailable)"
        #endif
    }
}
