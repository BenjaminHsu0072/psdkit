import Foundation

/// Stable, deterministic digest for RGBA pixel buffers.
/// Used as E0 `pixelRevision` until PSDKit exposes a native revision field.
enum EditorPixelRevisionDigest {
    private static let fnvOffsetBasis: UInt64 = 0xcbf29ce484222325
    private static let fnvPrime: UInt64 = 0x100000001b3

    static func digest(rgba: Data) -> UInt64 {
        var hash = fnvOffsetBasis
        for byte in rgba {
            hash ^= UInt64(byte)
            hash &*= fnvPrime
        }
        return hash
    }
}
