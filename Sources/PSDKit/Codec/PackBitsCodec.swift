import Foundation

/// Apple PackBits RLE (Photoshop 8-bit channel compression).
/// Ported from psd-tools `compression/rle.py`.
enum PackBitsCodec {
    static func decode(_ data: Data, size: Int) -> Data {
        var i = 0
        var j = 0
        let length = data.count
        let bytes = [UInt8](data)
        var result = [UInt8](repeating: 0, count: size)

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
                    result[j] = value
                    j += 1
                }
            } else if bit < 128 {
                let copyCount = 1 + bit
                let available = length - i
                let actual = min(copyCount, available, size - j)
                for k in 0 ..< actual {
                    result[j + k] = bytes[i + k]
                }
                j += actual
                i += min(copyCount, available)
            }
        }
        return Data(result)
    }

    static func encode(_ data: Data) -> Data {
        let bytes = [UInt8](data)
        let length = bytes.count
        if length == 0 { return Data() }
        if length == 1 { return Data([0, bytes[0]]) }

        let maxLen = 0x7F
        var i = 0
        var j = 0
        var result = [UInt8]()

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
                result.append(contentsOf: bytes[i ..< j])
                i = j
            }
        }
        return Data(result)
    }
}
