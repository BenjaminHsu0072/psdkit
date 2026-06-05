import Foundation

/// Apple PackBits RLE (Photoshop 8-bit channel compression).
/// Ported from psd-tools `compression/rle.py`.
enum PackBitsCodec {
    static func decode(_ data: Data, size: Int) -> Data {
        var result = Data(count: size)
        _ = decode(data, into: &result, writeOffset: 0, size: size)
        return result
    }

    /// Decodes PackBits into a pre-allocated buffer slice. Returns bytes written (0 if the slice is invalid).
    @discardableResult
    static func decode(_ data: Data, into output: inout Data, writeOffset: Int, size: Int) -> Int {
        guard size > 0 else { return 0 }
        guard writeOffset >= 0, writeOffset + size <= output.count else { return 0 }
        return output.withUnsafeMutableBytes { dest -> Int in
            guard let base = dest.baseAddress?.advanced(by: writeOffset).assumingMemoryBound(to: UInt8.self) else {
                return 0
            }
            return decode(data, into: base, size: size)
        }
    }

    @discardableResult
    static func decode(_ data: Data, into destination: UnsafeMutablePointer<UInt8>, size: Int) -> Int {
        guard size > 0 else { return 0 }
        var i = 0
        var j = 0
        data.withUnsafeBytes { raw in
            guard raw.count > 0 else { return }
            let bytes = raw.bindMemory(to: UInt8.self)
            let length = bytes.count

            while i < length, j < size {
                let bit = Int(bytes[i])
                i += 1
                if bit > 128 {
                    let run = 256 - bit
                    if i >= length { break }
                    let value = bytes[i]
                    i += 1
                    let actual = min(1 + run, size - j)
                    for _ in 0 ..< actual {
                        destination[j] = value
                        j += 1
                    }
                } else if bit < 128 {
                    let copyCount = 1 + bit
                    let available = length - i
                    let actual = min(copyCount, available, size - j)
                    for k in 0 ..< actual {
                        destination[j + k] = bytes[i + k]
                    }
                    j += actual
                    i += min(copyCount, available)
                }
            }
        }
        return j
    }

    static func encode(_ data: Data) -> Data {
        data.withUnsafeBytes { raw in
            encode(bytes: raw.bindMemory(to: UInt8.self))
        }
    }

    static func encode(bytes: UnsafeBufferPointer<UInt8>) -> Data {
        let length = bytes.count
        if length == 0 { return Data() }
        if length == 1 { return Data([0, bytes[0]]) }

        let maxLen = 0x7F
        var i = 0
        var j = 0
        var result = [UInt8]()
        result.reserveCapacity(min(length * 2, length + length / 128 + 2))

        while i < length {
            if j + 1 < length, bytes[j] == bytes[j + 1] {
                while j < length {
                    if j - i >= maxLen { break }
                    if j + 1 >= length || bytes[j] != bytes[j + 1] { break }
                    j += 1
                }
                result.append(UInt8(256 - (j - i)))
                result.append(bytes[i])
                i = j + 1
                j = i
            } else {
                while j < length {
                    if j - i >= maxLen { break }
                    if j + 2 < length, bytes[j] == bytes[j + 1], bytes[j] == bytes[j + 2] { break }
                    if j + 1 < length, bytes[j] == bytes[j + 1] {
                        if j + 2 == length || maxLen - (j - i) <= 2 { break }
                    }
                    j += 1
                }
                result.append(UInt8(j - i - 1))
                result.append(contentsOf: UnsafeBufferPointer(rebasing: bytes[i ..< j]))
                i = j
            }
        }
        return Data(result)
    }
}
