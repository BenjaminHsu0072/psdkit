import Foundation
import PSDKit

/// CPU RGBA8888 resampling for layer frame resize (nearest-neighbor).
enum PixelBufferResampler {
    static func resampleRGBA(
        source: Data,
        sourceWidth: Int,
        sourceHeight: Int,
        targetWidth: Int,
        targetHeight: Int
    ) throws -> Data {
        guard targetWidth > 0, targetHeight > 0 else {
            throw PSDError.corruptStructure("target size must be positive")
        }
        guard source.count == sourceWidth * sourceHeight * 4 else {
            throw PSDError.corruptStructure("invalid source RGBA byte count")
        }
        guard sourceWidth > 0, sourceHeight > 0 else {
            return Data(repeating: 0, count: targetWidth * targetHeight * 4)
        }

        var result = Data(repeating: 0, count: targetWidth * targetHeight * 4)
        for ty in 0 ..< targetHeight {
            let sy = min(ty * sourceHeight / targetHeight, sourceHeight - 1)
            for tx in 0 ..< targetWidth {
                let sx = min(tx * sourceWidth / targetWidth, sourceWidth - 1)
                let sourceOffset = (sy * sourceWidth + sx) * 4
                let targetOffset = (ty * targetWidth + tx) * 4
                result[targetOffset] = source[sourceOffset]
                result[targetOffset + 1] = source[sourceOffset + 1]
                result[targetOffset + 2] = source[sourceOffset + 2]
                result[targetOffset + 3] = source[sourceOffset + 3]
            }
        }
        return result
    }
}
