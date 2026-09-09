import Foundation

/// Shared scale for the setup slider and gesture engine.
public enum ZoomSensitivity {
    public static let range = 0.01...0.15
    public static let standard = 0.0525

    public static func clamped(_ value: Double) -> Double {
        value.isFinite ? min(max(value, range.lowerBound), range.upperBound) : standard
    }

    /// Restore a saved value, falling back to Standard when unset.
    public static func restored(_ value: Double?) -> Double {
        guard let value else { return standard }
        return clamped(value)
    }
}
