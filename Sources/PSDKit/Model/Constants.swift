import Foundation

public enum ColorMode: UInt16, Sendable {
    case bitmap = 0
    case grayscale = 1
    case indexed = 2
    case rgb = 3
    case cmyk = 4
    case multichannel = 7
    case duotone = 8
    case lab = 9
}

public enum Compression: UInt16, Sendable {
    case raw = 0
    case rle = 1
    case zip = 2
    case zipWithPrediction = 3
}

/// Channel id in layer record (`ChannelInfo.id`).
public enum ChannelID: Int16, Sendable {
    case red = 0
    case green = 1
    case blue = 2
    case transparencyMask = -1
    case userLayerMask = -2
    case realUserLayerMask = -3
}

public enum BlendMode: String, Sendable {
    case normal = "norm"
    case passThrough = "pass"
    case unknown

    public init(fourCC: String) {
        switch fourCC {
        case "norm": self = .normal
        case "pass": self = .passThrough
        default: self = .unknown
        }
    }

    public var fourCC: String {
        switch self {
        case .normal: return "norm"
        case .passThrough: return "pass"
        case .unknown: return "norm"
        }
    }
}

public enum Clipping: UInt8, Sendable {
    case base = 0
    case nonBase = 1
}
