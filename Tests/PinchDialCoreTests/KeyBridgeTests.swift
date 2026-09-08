import XCTest
@testable import PinchDialCore

final class KeyBridgeTests: XCTestCase {
    func testOneStepPerPressAndBothEdgesConsumed() {
        var keys = KeyBridge()
        XCTAssertEqual(keys.handle(key: 79, down: true, repeated: false, enabled: true, observeOnly: false),
                       .init(consume: true, direction: 1))
        XCTAssertEqual(keys.handle(key: 79, down: true, repeated: true, enabled: true, observeOnly: false),
                       .init(consume: true))
        XCTAssertEqual(keys.handle(key: 79, down: false, repeated: false, enabled: true, observeOnly: false),
                       .init(consume: true))
        XCTAssertEqual(keys.handle(key: 80, down: true, repeated: false, enabled: true, observeOnly: false),
                       .init(consume: true, direction: -1))
    }

    func testDisabledObservationAndUnrelatedKeysPassThrough() {
        var keys = KeyBridge()
        for (key, enabled, observe) in [(UInt16(79), false, false), (80, true, true), (0, true, false)] {
            XCTAssertEqual(keys.handle(key: key, down: true, repeated: false, enabled: enabled, observeOnly: observe),
                           .init(consume: false))
            XCTAssertEqual(keys.handle(key: key, down: false, repeated: false, enabled: enabled, observeOnly: observe),
                           .init(consume: false))
        }
    }

    func testDisableDuringHeldPressStillConsumesItsRelease() {
        var keys = KeyBridge()
        _ = keys.handle(key: 79, down: true, repeated: false, enabled: true, observeOnly: false)
        XCTAssertEqual(keys.handle(key: 79, down: false, repeated: false, enabled: false, observeOnly: false),
                       .init(consume: true))
        XCTAssertEqual(keys.handle(key: 80, down: false, repeated: false, enabled: true, observeOnly: false),
                       .init(consume: false))
    }
}
