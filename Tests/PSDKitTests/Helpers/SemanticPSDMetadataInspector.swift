import Foundation
import XCTest
@testable import PSDKit

/// Asserts that a semantic PSDKit write contains only standard PSD metadata (no private extensions).
enum SemanticPSDMetadataInspector {
    /// Tagged block keys PSDKit may emit on pixel layers (Photoshop standard).
    static let pixelLayerTaggedBlockKeys: Set<String> = ["luni"]

    /// Tagged block keys PSDKit may emit on group / section divider records.
    static let sectionLayerTaggedBlockKeys: Set<String> = ["lsct", "lsdk"]

    /// Document-level tagged blocks in `LayerAndMaskInformation.taggedBlocksRaw` (mid-term: none).
    static let documentLevelTaggedBlockKeys: Set<String> = []

    /// Four-character tagged block keys that must never appear in PSDKit semantic output.
    static let privateTaggedBlockKeys: Set<String> = ["mnft", "psdk", "PSDK"]

    private static let blockSignature = "8BIM"
    private static let privateMarkerUTF8: [String] = ["PSDKit", "psdkit"]
    private static let privateMarkerInResourceNames: [String] = ["manifest", "PSDKit", "psdkit"]

    struct Violation: Equatable, CustomStringConvertible {
        let message: String
        var description: String { message }
    }

    static func violations(in file: PSDFile) -> [Violation] {
        var issues: [Violation] = []

        if !file.imageResources.isEmpty {
            let resources = parseImageResources(file.imageResources)
            if resources.isEmpty, !file.imageResources.isEmpty {
                issues.append(Violation(message: "image resources block is non-empty but not parseable as 8BIM resources"))
            }
            for resource in resources {
                issues.append(
                    Violation(
                        message: "unexpected image resource id=0x\(String(format: "%04X", resource.id)) name=\(resource.name)"
                    )
                )
            }
        }

        let documentKeys = Set(parseTaggedBlockKeys(file.layerAndMask.taggedBlocksRaw))
        let unexpectedDocument = documentKeys.subtracting(documentLevelTaggedBlockKeys)
        if !unexpectedDocument.isEmpty {
            issues.append(
                Violation(message: "unexpected document-level tagged block keys: \(sortedKeys(unexpectedDocument))")
            )
        }
        let privateDocument = documentKeys.intersection(privateTaggedBlockKeys)
        if !privateDocument.isEmpty {
            issues.append(
                Violation(message: "private tagged block keys at document level: \(sortedKeys(privateDocument))")
            )
        }

        guard let layerInfo = file.layerAndMask.layerInfo else {
            return issues + privateMarkerViolations(in: file)
        }

        for (index, record) in layerInfo.layers.enumerated() {
            let keys = Set(LayerExtra.taggedBlockKeys(in: record.extraData))
            let allowed: Set<String>
            let role: String
            if record.width > 0, record.height > 0 {
                allowed = pixelLayerTaggedBlockKeys
                role = "pixel"
            } else if LayerExtra.sectionDividerKind(for: record) != nil
                || !keys.isDisjoint(with: LayerExtra.sectionDividerTaggedBlockKeys)
            {
                allowed = sectionLayerTaggedBlockKeys
                role = "section"
            } else {
                allowed = []
                role = "non-pixel"
            }

            let unexpected = keys.subtracting(allowed)
            if !unexpected.isEmpty {
                issues.append(
                    Violation(
                        message: "layer \(index) (\(role) '\(record.name)') unexpected tagged keys: \(sortedKeys(unexpected))"
                    )
                )
            }

            let privateKeys = keys.intersection(privateTaggedBlockKeys)
            if !privateKeys.isEmpty {
                issues.append(
                    Violation(
                        message: "layer \(index) ('\(record.name)') private tagged keys: \(sortedKeys(privateKeys))"
                    )
                )
            }

            for key in keys where key.lowercased().contains("manifest") || key.contains("psdk") {
                issues.append(Violation(message: "layer \(index) ('\(record.name)') suspicious tagged key '\(key)'"))
            }
        }

        return issues + privateMarkerViolations(in: file)
    }

    static func assertNoPrivateMetadata(in psdFile: PSDFile, file: StaticString = #filePath, line: UInt = #line) {
        let issues = violations(in: psdFile)
        if issues.isEmpty { return }
        let detail = issues.map(\.description).joined(separator: "; ")
        XCTFail("semantic PSD must not contain private metadata: \(detail)", file: file, line: line)
    }

    // MARK: - Image resources (8BIM resource list)

    private struct ParsedImageResource {
        var id: UInt16
        var name: String
    }

    private static func parseImageResources(_ data: Data) -> [ParsedImageResource] {
        var resources: [ParsedImageResource] = []
        var offset = 0
        let bytes = [UInt8](data)
        while offset + 6 <= bytes.count {
            guard String(bytes: bytes[offset ..< offset + 4], encoding: .ascii) == blockSignature else { break }
            let id = UInt16(bytes[offset + 4]) << 8 | UInt16(bytes[offset + 5])
            offset += 6
            guard offset < bytes.count else { break }
            let nameLen = Int(bytes[offset])
            offset += 1
            guard offset + nameLen <= bytes.count else { break }
            let name = String(bytes: bytes[offset ..< offset + nameLen], encoding: .ascii) ?? ""
            offset += nameLen
            if (1 + nameLen) % 2 != 0, offset < bytes.count { offset += 1 }
            guard offset + 4 <= bytes.count else { break }
            let size = Int(readUInt32BE(bytes, offset))
            offset += 4
            guard offset + size <= bytes.count else { break }
            offset += size
            if size % 2 != 0, offset < bytes.count { offset += 1 }
            resources.append(ParsedImageResource(id: id, name: name))
        }
        return resources
    }

    // MARK: - Tagged blocks (document-level; mirrors LayerExtra layout)

    private static func parseTaggedBlockKeys(_ data: Data) -> [String] {
        var keys: [String] = []
        var offset = 0
        let bytes = [UInt8](data)
        while offset + 12 <= bytes.count {
            guard String(bytes: bytes[offset ..< offset + 4], encoding: .ascii) == blockSignature else { break }
            let key = String(bytes: bytes[offset + 4 ..< offset + 8], encoding: .ascii) ?? ""
            let length = Int(readUInt32BE(bytes, offset + 8))
            offset += 12
            guard offset + length <= bytes.count else { break }
            offset += length
            if length % 2 != 0, offset < bytes.count { offset += 1 }
            keys.append(key)
        }
        return keys
    }

    // MARK: - Private marker scan (metadata regions only)

    private static func privateMarkerViolations(in file: PSDFile) -> [Violation] {
        var issues: [Violation] = []
        var regions: [(String, Data)] = [
            ("image resources", file.imageResources),
            ("document tagged blocks", file.layerAndMask.taggedBlocksRaw),
        ]
        if let layers = file.layerAndMask.layerInfo?.layers {
            for (index, record) in layers.enumerated() {
                regions.append(("layer \(index) extra", record.extraData))
            }
        }

        for (label, data) in regions where !data.isEmpty {
            for marker in privateMarkerUTF8 {
                if containsUTF8(marker, in: data) {
                    issues.append(Violation(message: "private marker '\(marker)' found in \(label)"))
                }
            }
        }

        if !file.imageResources.isEmpty {
            for resource in parseImageResources(file.imageResources) {
                let lowerName = resource.name.lowercased()
                for marker in privateMarkerInResourceNames where lowerName.contains(marker.lowercased()) {
                    issues.append(
                        Violation(
                            message: "private marker '\(marker)' in image resource name '\(resource.name)'"
                        )
                    )
                }
            }
        }

        let documentKeys = parseTaggedBlockKeys(file.layerAndMask.taggedBlocksRaw)
        for key in documentKeys {
            if key.lowercased().contains("manifest") {
                issues.append(Violation(message: "suspicious document-level tagged key '\(key)'"))
            }
        }

        return issues
    }

    private static func containsUTF8(_ needle: String, in data: Data) -> Bool {
        guard let bytes = needle.data(using: .utf8), !bytes.isEmpty else { return false }
        return data.range(of: bytes) != nil
    }

    private static func sortedKeys(_ keys: Set<String>) -> String {
        keys.sorted().joined(separator: ", ")
    }

    private static func readUInt32BE(_ bytes: [UInt8], _ offset: Int) -> UInt32 {
        UInt32(bytes[offset]) << 24 | UInt32(bytes[offset + 1]) << 16
            | UInt32(bytes[offset + 2]) << 8 | UInt32(bytes[offset + 3])
    }
}
