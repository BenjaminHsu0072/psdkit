import XCTest
@testable import PSDViewer

final class EditorDependencyBoundaryTests: XCTestCase {
    func testEditorCoreDoesNotImportForbiddenFrameworks() throws {
        let editorCoreDir = moduleDirectory(named: "EditorCore")
        let forbidden = ["import SwiftUI", "import AppKit", "import Metal", "import MetalKit"]
        try assertNoForbiddenPatterns(in: editorCoreDir, forbidden: forbidden)
    }

    func testRenderCoreDoesNotReferenceDocumentModel() throws {
        let renderCoreDir = moduleDirectory(named: "RenderCore")
        try assertNoForbiddenPatterns(in: renderCoreDir, forbidden: ["DocumentModel"])
    }

    func testRenderCoreDoesNotImportSwiftUI() throws {
        let renderCoreDir = moduleDirectory(named: "RenderCore")
        try assertNoForbiddenPatterns(in: renderCoreDir, forbidden: ["import SwiftUI"])
    }

    func testMetalBackendDoesNotReferenceDocumentModel() throws {
        let metalBackendDir = moduleDirectory(named: "MetalBackend")
        try assertNoForbiddenPatterns(in: metalBackendDir, forbidden: ["DocumentModel"])
    }

    func testMetalBackendDoesNotImportSwiftUI() throws {
        let metalBackendDir = moduleDirectory(named: "MetalBackend")
        try assertNoForbiddenPatterns(in: metalBackendDir, forbidden: ["import SwiftUI"])
    }

    func testInputCoreDoesNotImportForbiddenFrameworks() throws {
        let inputCoreDir = moduleDirectory(named: "InputCore")
        let forbidden = ["import SwiftUI", "import AppKit", "import Metal", "import MetalKit"]
        try assertNoForbiddenPatterns(in: inputCoreDir, forbidden: forbidden)
    }

    private func moduleDirectory(named name: String) -> URL {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0 ..< 3 {
            url.deleteLastPathComponent()
        }
        return url.appendingPathComponent("Sources/PSDViewer/\(name)", isDirectory: true)
    }

    private func assertNoForbiddenPatterns(in directory: URL, forbidden: [String]) throws {
        let files = try swiftFiles(in: directory)
        XCTAssertFalse(files.isEmpty, "Expected Swift sources in \(directory.path)")
        for file in files {
            let content = try String(contentsOf: file, encoding: .utf8)
            let lines = content.split(whereSeparator: \.isNewline)
            for line in lines {
                let trimmed = String(line).trimmingCharacters(in: .whitespaces)
                guard !trimmed.isEmpty, !trimmed.hasPrefix("//") else { continue }
                for pattern in forbidden {
                    XCTAssertFalse(
                        lineViolatesForbidden(trimmed, pattern: pattern),
                        "\(file.lastPathComponent) must not contain \"\(pattern)\""
                    )
                }
            }
        }
    }

    private func lineViolatesForbidden(_ line: String, pattern: String) -> Bool {
        if pattern.hasPrefix("import ") {
            return line == pattern || line.hasPrefix(pattern + " ")
        }
        return line.contains(pattern)
    }

    private func swiftFiles(in directory: URL) throws -> [URL] {
        let contents = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        )
        return contents.filter { $0.pathExtension == "swift" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
    }
}
