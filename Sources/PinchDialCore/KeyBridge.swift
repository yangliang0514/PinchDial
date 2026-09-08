/// Uses macOS virtual key codes, not USB HID usage IDs or printable characters.
public struct KeyBridge {
    public static let clockwise: UInt16 = 79  // kVK_F18
    public static let counterclockwise: UInt16 = 80  // kVK_F19

    public struct Decision: Equatable {
        public let consume: Bool
        public let direction: Int?
        public init(consume: Bool, direction: Int? = nil) {
            self.consume = consume
            self.direction = direction
        }
    }

    private var consumedKeys: Set<UInt16> = []
    public init() {}

    public mutating func handle(key: UInt16, down: Bool, repeated: Bool,
                                enabled: Bool) -> Decision {
        guard key == Self.clockwise || key == Self.counterclockwise else {
            return Decision(consume: false)
        }
        if !down {
            return Decision(consume: consumedKeys.remove(key) != nil)
        }
        // Preserve ownership of a press even if settings change while it is held.
        if repeated { return Decision(consume: consumedKeys.contains(key)) }
        guard enabled else { return Decision(consume: false) }
        consumedKeys.insert(key)
        return Decision(consume: true, direction: key == Self.clockwise ? 1 : -1)
    }

    public mutating func reset() { consumedKeys.removeAll() }
}
