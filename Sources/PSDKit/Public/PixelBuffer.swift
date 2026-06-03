import Foundation

public struct PixelBuffer: Sendable, Equatable {
    public let width: Int
    public let height: Int
    /// RGBA8888, row-major.
    public var rgba: Data

    public init(width: Int, height: Int, rgba: Data) throws {
        guard width > 0, height > 0 else {
            throw PSDError.corruptStructure("invalid dimensions")
        }
        let expected = width * height * 4
        guard rgba.count >= expected else {
            throw PSDError.corruptStructure("rgba too short: \(rgba.count) < \(expected)")
        }
        self.width = width
        self.height = height
        self.rgba = rgba.prefix(expected)
    }
}
