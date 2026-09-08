import AppKit
import CoreGraphics
import PinchDialCore

/// The ONLY place containing the undocumented magnification wire format.
/// Historical reference (not an Apple API contract):
/// https://github.com/noah-nuebling/mac-mouse-fix/discussions/366
/// The field recipe is implemented independently; no external source is vendored.
final class GestureBackend {
    static let marker: Int64 = 0x50494E4348444941
    private let source = CGEventSource(stateID: .privateState)

    /// Posting succeeds only in the sense that we constructed and submitted an event.
    /// CGEventPost does not acknowledge delivery or application handling.
    @discardableResult
    func post(_ sample: GestureSample, location: CGPoint, terminalTarget: pid_t? = nil) -> Bool {
        guard let event = makeEvent(sample, location: location) else { return false }
        if let pid = terminalTarget {
            // Best-effort cleanup of the old recipient after an app switch.
            // Never route a pending magnification delta into the new application.
            event.postToPid(pid)
        } else {
            event.post(tap: .cghidEventTap)
        }
        return true
    }

    /// Kept separate so the wire format can be checked without injecting input.
    func makeEvent(_ sample: GestureSample, location: CGPoint) -> CGEvent? {
        guard sample.magnification.isFinite,
              let event = CGEvent(source: source),
              let type = CGEventType(rawValue: 29),
              let subtype = CGEventField(rawValue: 110),
              let phase = CGEventField(rawValue: 132),
              let magnitude = CGEventField(rawValue: 113) else { return nil }
        let phaseBits: Int64
        switch sample.phase {
        case .began: phaseBits = 1
        case .changed: phaseBits = 2
        case .ended: phaseBits = 4
        case .cancelled: phaseBits = 8
        }
        event.type = type
        event.location = location
        event.flags = []
        event.setIntegerValueField(subtype, value: 8)
        event.setIntegerValueField(phase, value: phaseBits)
        event.setDoubleValueField(magnitude, value: sample.magnification)
        event.setIntegerValueField(.eventSourceUserData, value: Self.marker)
        return event
    }
}
