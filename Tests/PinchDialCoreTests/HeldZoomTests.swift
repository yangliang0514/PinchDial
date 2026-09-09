import XCTest
@testable import PinchDialCore

final class HeldZoomTests: XCTestCase {
    func testQuickDialPressDoesNotRepeat() {
        var hold = HeldZoom()
        hold.begin(key: 79, direction: 1, at: 0)
        XCTAssertNil(hold.advance(to: 0.399))
        XCTAssertFalse(hold.release(key: 79))
        XCTAssertNil(hold.advance(to: 1))
        XCTAssertFalse(hold.isHeld)
    }

    func testDelayCadenceAndReleaseInBothDirections() {
        for direction in [-1, 1] {
            var hold = HeldZoom()
            hold.begin(key: 79, direction: direction, at: 0)
            XCTAssertNil(hold.advance(to: 0.399))
            XCTAssertEqual(hold.advance(to: 0.4), direction)
            XCTAssertNil(hold.advance(to: 0.48))
            XCTAssertEqual(hold.advance(to: 0.484), direction)
            XCTAssertTrue(hold.release(key: 79))
            XCTAssertNil(hold.advance(to: 2))
        }
    }

    func testCancellationAndUnrelatedRelease() {
        var hold = HeldZoom()
        hold.begin(key: 79, direction: 1, at: 0)
        XCTAssertFalse(hold.release(key: 0))
        XCTAssertEqual(hold.advance(to: 0.4), 1)
        hold.cancel()
        XCTAssertNil(hold.advance(to: 1))
        XCTAssertFalse(hold.isHeld)
    }

    func testLatestDirectionWinsAndOldKeyNeverResumes() {
        var hold = HeldZoom()
        hold.begin(key: 79, direction: 1, at: 0)
        hold.begin(key: 80, direction: -1, at: 0.2)
        XCTAssertFalse(hold.release(key: 79))
        XCTAssertNil(hold.advance(to: 0.59))
        XCTAssertEqual(hold.advance(to: 0.61), -1)
        XCTAssertTrue(hold.release(key: 80))
        XCTAssertNil(hold.advance(to: 2))
    }

    func testStalledLoopDoesNotProduceCatchUpBurst() {
        var hold = HeldZoom()
        hold.begin(key: 79, direction: 1, at: 0)
        XCTAssertEqual(hold.advance(to: 10), 1)
        XCTAssertNil(hold.advance(to: 10))
        XCTAssertNil(hold.advance(to: 10.01))
    }
}
