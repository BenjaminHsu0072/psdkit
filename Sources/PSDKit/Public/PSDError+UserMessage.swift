import Foundation

extension PSDError {
    /// Short message suitable for UI or logs.
    public var userMessage: String {
        switch self {
        case .invalidSignature:
            return "Not a valid PSD file (missing 8BPS signature)."
        case .unexpectedEOF:
            return "Unexpected end of file while reading PSD data."
        case .unsupportedVersion(let v):
            return "Unsupported PSD version \(v). Only version 1 is supported."
        case .unsupportedBitDepth(let d):
            return "Unsupported bit depth \(d). Only 8-bit is supported."
        case .unsupportedColorMode(let mode):
            return "Unsupported color mode (\(mode)). Only RGB is supported in v1."
        case .unsupportedCompression(let c):
            return "Unsupported channel compression (\(c)). Zip is not supported yet."
        case .unsupportedLayerKind(let kind):
            return "Unsupported layer kind: \(kind)."
        case .corruptStructure(let detail):
            return "Invalid PSD structure: \(detail)"
        case .io(let detail):
            return "File I/O error: \(detail)"
        }
    }
}
