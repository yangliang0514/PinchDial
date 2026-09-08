import XCTest
@testable import PinchDialCore

final class KeyBridgeTests: XCTestCase {
    func testOneStepPerPressAndBothEdgesConsumed() {
        var keys = KeyBridge()
        XCTAssertEqual(keys.handle(key: 79, down: true, repeated: false, enabled: true),
                       .init(consume: true, direction: 1))
        XCTAssertEqual(keys.handle(key: 79, down: true, repeated: true, enabled: true),
                       .init(consume: true))
        XCTAssertEqual(keys.handle(key: 79, down: false, repeated: false, enabled: true),
                       .init(consume: true))
        XCTAssertEqual(keys.handle(key: 80, down: true, repeated: false, enabled: true),
                       .init(consume: true, direction: -1))
    }

    func testDisabledAndUnrelatedKeysPassThrough() {
        var keys = KeyBridge()
        for (key, enabled) in [(UInt16(79), false), (80, false), (0, true)] {
            XCTAssertEqual(keys.handle(key: key, down: true, repeated: false, enabled: enabled),
                           .init(consume: false))
            XCTAssertEqual(keys.handle(key: key, down: false, repeated: false, enabled: enabled),
                           .init(consume: false))
        }
    }

    func testDisableDuringHeldPressStillConsumesItsRelease() {
        var keys = KeyBridge()
        _ = keys.handle(key: 79, down: true, repeated: false, enabled: true)
        XCTAssertEqual(keys.handle(key: 79, down: false, repeated: false, enabled: false),
                       .init(consume: true))
        XCTAssertEqual(keys.handle(key: 80, down: false, repeated: false, enabled: true),
                       .init(consume: false))
    }
}
