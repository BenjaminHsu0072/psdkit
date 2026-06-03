import Foundation

public enum PSDError: Error, Sendable, Equatable {
    case invalidSignature
    case unexpectedEOF
    case unsupportedVersion(Int)
    case unsupportedBitDepth(Int)
    case unsupportedColorMode(UInt16)
    case unsupportedCompression(UInt16)
    case unsupportedLayerKind(String)
    case corruptStructure(String)
    case io(String)
}
