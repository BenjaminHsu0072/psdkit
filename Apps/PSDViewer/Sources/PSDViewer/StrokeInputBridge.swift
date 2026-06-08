import AppKit
import Foundation

/// AppKit event adapter for InputCore. Lives in App Shell; InputCore models stay platform-neutral.
enum StrokeInputBridge {
    static func rawEvent(
        from event: NSEvent,
        phase: PointerSamplePhase,
        viewPoint: CGPoint
    ) -> RawPointerEvent {
        RawPointerEvent(
            viewPoint: viewPoint,
            phase: phase,
            pressure: pressure(from: event),
            timestamp: event.timestamp,
            device: deviceKind(from: event),
            modifiers: modifiers(from: event),
            tilt: tilt(from: event)
        )
    }

    static func pressure(from event: NSEvent) -> CGFloat {
        if event.type == .tabletPoint {
            return CGFloat(event.pressure)
        }
        if event.subtype == .tabletPoint {
            return CGFloat(event.pressure)
        }
        return 0
    }

    static func deviceKind(from event: NSEvent) -> PointerDeviceKind {
        switch event.type {
        case .tabletPoint, .tabletProximity:
            return .tablet
        default:
            if event.subtype == .tabletPoint {
                return .tablet
            }
            if event.subtype == .mouseEvent {
                return .mouse
            }
            return .unknown
        }
    }

    static func modifiers(from event: NSEvent) -> PointerModifiers {
        var flags = PointerModifiers()
        if event.modifierFlags.contains(.shift) { flags.insert(.shift) }
        if event.modifierFlags.contains(.option) { flags.insert(.option) }
        if event.modifierFlags.contains(.command) { flags.insert(.command) }
        if event.modifierFlags.contains(.control) { flags.insert(.control) }
        return flags
    }

    static func tilt(from event: NSEvent) -> PointerTilt {
        guard deviceKind(from: event) == .tablet else { return .none }
        let azimuth = CGFloat(event.tilt.x)
        let altitude = CGFloat(event.tilt.y)
        return PointerTilt(azimuth: azimuth, altitude: altitude)
    }
}
