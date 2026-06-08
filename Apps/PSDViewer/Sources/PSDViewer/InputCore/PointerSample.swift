import CoreGraphics
import Foundation

enum PointerSamplePhase: Equatable, Sendable {
    case began
    case moved
    case ended
    case cancelled
}

enum PointerDeviceKind: Equatable, Sendable {
    case mouse
    case tablet
    case trackpad
    case unknown
}

struct PointerModifiers: Equatable, Sendable, OptionSet {
    let rawValue: UInt

    static let shift = PointerModifiers(rawValue: 1 << 0)
    static let option = PointerModifiers(rawValue: 1 << 1)
    static let command = PointerModifiers(rawValue: 1 << 2)
    static let control = PointerModifiers(rawValue: 1 << 3)
}

struct PointerTilt: Equatable, Sendable {
    var azimuth: CGFloat?
    var altitude: CGFloat?

    static let none = PointerTilt(azimuth: nil, altitude: nil)
}

/// Platform-neutral pointer sample. Coordinates are produced via `InputCoordinateMapper` + `EditorViewport`.
struct PointerSample: Equatable, Sendable {
    let timestamp: TimeInterval
    let phase: PointerSamplePhase
    let viewPoint: CGPoint
    let canvasPoint: CGPoint
    let layerLocalPoint: CGPoint?
    let pressure: CGFloat
    let tilt: PointerTilt
    let device: PointerDeviceKind
    let modifiers: PointerModifiers
    /// `nil` when no target layer context was supplied.
    let isInsideTargetLayer: Bool?
}

/// App-shell neutral event payload before coordinate mapping.
struct RawPointerEvent: Equatable, Sendable {
    let viewPoint: CGPoint
    let phase: PointerSamplePhase
    let pressure: CGFloat
    let timestamp: TimeInterval
    let device: PointerDeviceKind
    let modifiers: PointerModifiers
    let tilt: PointerTilt

    init(
        viewPoint: CGPoint,
        phase: PointerSamplePhase,
        pressure: CGFloat,
        timestamp: TimeInterval,
        device: PointerDeviceKind = .mouse,
        modifiers: PointerModifiers = [],
        tilt: PointerTilt = .none
    ) {
        self.viewPoint = viewPoint
        self.phase = phase
        self.pressure = pressure
        self.timestamp = timestamp
        self.device = device
        self.modifiers = modifiers
        self.tilt = tilt
    }
}
