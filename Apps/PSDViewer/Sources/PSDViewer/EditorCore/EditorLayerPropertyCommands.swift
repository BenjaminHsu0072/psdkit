import Foundation
import PSDKit

struct SetLayerOpacityCommand: EditorCommand {
    let layerID: String
    let opacity: UInt8

    func apply(to adapter: any EditorDocumentAdapter) -> EditorCommandResult {
        adapter.setLayerOpacity(id: layerID, opacity: opacity)
    }
}

struct SetLayerBlendModeCommand: EditorCommand {
    let layerID: String
    let blendMode: BlendMode

    func apply(to adapter: any EditorDocumentAdapter) -> EditorCommandResult {
        adapter.setLayerBlendMode(id: layerID, blendMode: blendMode)
    }
}

struct SetLayerFrameCommand: EditorCommand {
    let layerID: String
    let frame: PSDRect

    func apply(to adapter: any EditorDocumentAdapter) -> EditorCommandResult {
        adapter.setLayerFrame(id: layerID, frame: frame)
    }
}
