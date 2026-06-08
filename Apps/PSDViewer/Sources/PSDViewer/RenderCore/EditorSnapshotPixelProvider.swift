import Foundation
import PSDKit

struct EditorSnapshotPixelProviderDiagnostics: Equatable, Sendable {
    let missingDocumentLayerUUIDs: [UUID]

    var missingDocumentLayerUUIDCount: Int { missingDocumentLayerUUIDs.count }

    static let none = EditorSnapshotPixelProviderDiagnostics(missingDocumentLayerUUIDs: [])

    var summaryLine: String {
        "missingDocumentLayerUUIDs=\(missingDocumentLayerUUIDCount)"
    }
}

/// Resolves layer pixel data for render/composite without exposing PSDDocument to MetalBackend.
struct EditorSnapshotPixelProvider: Sendable {
    private let pixelsByLayerUUID: [UUID: PixelPayload]
    let diagnostics: EditorSnapshotPixelProviderDiagnostics

    struct PixelPayload: Equatable, Sendable {
        let data: Data
        let width: Int
        let height: Int
    }

    init(
        pixelsByLayerUUID: [UUID: PixelPayload] = [:],
        diagnostics: EditorSnapshotPixelProviderDiagnostics = .none
    ) {
        self.pixelsByLayerUUID = pixelsByLayerUUID
        self.diagnostics = diagnostics
    }

    func rgba(for layer: EditorLayerSnapshot) -> PixelPayload? {
        switch layer.pixelSource {
        case .none:
            return nil
        case .documentLayerUUID(let layerUUID):
            return pixelsByLayerUUID[layerUUID]
        case .rgbaData(let data, let width, let height):
            return PixelPayload(data: data, width: width, height: height)
        }
    }

    /// Snapshot-time resolution: maps `.documentLayerUUID` to RGBA payloads.
    static func build(from document: PSDDocument, snapshot: EditorRenderSnapshot) -> EditorSnapshotPixelProvider {
        var map: [UUID: PixelPayload] = [:]
        var missingDocumentLayerUUIDs: [UUID] = []
        for layer in snapshot.layers where layer.kind == .pixel {
            guard case .documentLayerUUID(let layerUUID) = layer.pixelSource else { continue }
            guard let pixel = resolvePixelLayer(id: layerUUID, in: document.root) else {
                missingDocumentLayerUUIDs.append(layerUUID)
                continue
            }
            map[layerUUID] = PixelPayload(
                data: pixel.pixels.rgba,
                width: pixel.pixels.width,
                height: pixel.pixels.height
            )
        }
        let diagnostics = EditorSnapshotPixelProviderDiagnostics(
            missingDocumentLayerUUIDs: missingDocumentLayerUUIDs
        )
        #if DEBUG
        logMissingDocumentLayerUUIDsIfNeeded(diagnostics)
        #endif
        return EditorSnapshotPixelProvider(pixelsByLayerUUID: map, diagnostics: diagnostics)
    }

    #if DEBUG
    private static var lastLoggedMissingDocumentLayerUUIDFingerprint: String?

    /// Logs only when the missing UUID set changes, so refresh loops do not spam.
    private static func logMissingDocumentLayerUUIDsIfNeeded(
        _ diagnostics: EditorSnapshotPixelProviderDiagnostics
    ) {
        guard !diagnostics.missingDocumentLayerUUIDs.isEmpty else {
            lastLoggedMissingDocumentLayerUUIDFingerprint = nil
            return
        }
        let fingerprint = diagnostics.missingDocumentLayerUUIDs
            .map(\.uuidString)
            .sorted()
            .joined(separator: ",")
        guard fingerprint != lastLoggedMissingDocumentLayerUUIDFingerprint else { return }
        lastLoggedMissingDocumentLayerUUIDFingerprint = fingerprint
        print(
            "[EditorSnapshotPixelProvider] unresolved documentLayerUUID count="
                + "\(diagnostics.missingDocumentLayerUUIDCount): \(fingerprint)"
        )
    }
    #endif

    private static func resolvePixelLayer(id: UUID, in group: GroupLayer) -> PixelLayer? {
        for child in group.children {
            if child.id == id, let pixel = child as? PixelLayer {
                return pixel
            }
            if let nested = child as? GroupLayer, let pixel = resolvePixelLayer(id: id, in: nested) {
                return pixel
            }
        }
        return nil
    }
}
