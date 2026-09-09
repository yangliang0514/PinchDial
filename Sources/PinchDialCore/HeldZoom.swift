/// App-controlled repetition, independent of macOS keyboard repeat settings.
public struct HeldZoom {
    public static let delay = 0.4
    public static let interval = 1.0 / 12.0
    private var key: UInt16?
    private var direction = 0
    private var nextRepeat = 0.0
    public private(set) var hasRepeated = false
    public var isHeld: Bool { key != nil }
    public init() {}

    /// The most recently pressed zoom key wins; releasing it never resumes an older key.
    public mutating func begin(key: UInt16, direction: Int, at time: Double) {
        self.key = key
        self.direction = direction
        nextRepeat = time + Self.delay
        hasRepeated = false
    }

    public mutating func advance(to time: Double) -> Int? {
        guard isHeld, time >= nextRepeat else { return nil }
        // Never catch up missed repeats after a stalled run loop.
        nextRepeat = time + Self.interval
        hasRepeated = true
        return direction
    }

    /// True when a repeating hold ended, so its remaining smoothing can be stopped.
    public mutating func release(key: UInt16) -> Bool {
        guard self.key == key else { return false }
        let wasRepeating = hasRepeated
        cancel()
        return wasRepeating
    }

    public mutating func cancel() { key = nil; hasRepeated = false }
}
