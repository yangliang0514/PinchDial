import XCTest
@testable import PinchDialCore

final class MagnificationEngineTests: XCTestCase {
    private func drain(_ engine: inout MagnificationEngine, from start: Double,
                       frame: Double = 1.0 / 60) -> [GestureSample] {
        var samples: [GestureSample] = []
        var now = start
        for _ in 0..<300 {
            now += frame
            samples += engine.advance(to: now)
            if !engine.isActive { break }
        }
        XCTAssertFalse(engine.isActive, "Gesture must finish within a bounded interval")
        return samples
    }

    private func logAmount(_ samples: [GestureSample]) -> Double {
        samples.reduce(0) { $0 + log1p($1.magnification) }
    }

    func testOneDetentProducesOneCompleteGestureAndPreservesAmount() {
        var engine = MagnificationEngine()
        let beginning = engine.push(direction: 1, at: 10)
        XCTAssertEqual(beginning.map(\.phase), [.began, .changed])
        let samples = beginning + drain(&engine, from: 10)
        XCTAssertEqual(samples.filter { $0.phase == .began }.count, 1)
        XCTAssertEqual(samples.filter { $0.phase == .ended }.count, 1)
        XCTAssertEqual(samples.last?.phase, .ended)
        XCTAssertEqual(logAmount(samples), 0.035, accuracy: 1e-10)
        XCTAssertTrue(engine.advance(to: 20).isEmpty)
    }

    func testBurstSharesLifecycleAndAddsAllSteps() {
        var engine = MagnificationEngine()
        var samples = engine.push(direction: 1, at: 0)
        samples += engine.advance(to: 0.02)
        samples += engine.push(direction: 1, at: 0.02)
        samples += engine.advance(to: 0.04)
        samples += engine.push(direction: 1, at: 0.04)
        samples += drain(&engine, from: 0.04)
        XCTAssertEqual(samples.filter { $0.phase == .began }.count, 1)
        XCTAssertEqual(logAmount(samples), 0.105, accuracy: 1e-10)
    }

    func testFrameRateDoesNotChangeTotalZoom() {
        for frame in [1.0 / 30, 1.0 / 60, 1.0 / 120] {
            var engine = MagnificationEngine()
            _ = engine.push(direction: -1, at: 0)
            XCTAssertEqual(logAmount(drain(&engine, from: 0, frame: frame)), -0.035, accuracy: 1e-10)
        }
    }

    func testReverseTakesEffectOnNextFrameWithoutOldTail() {
        var engine = MagnificationEngine()
        _ = engine.push(direction: 1, at: 0)
        _ = engine.advance(to: 0.01)
        XCTAssertGreaterThan(engine.pending, 0)
        XCTAssertTrue(engine.push(direction: -1, at: 0.012).isEmpty)
        XCTAssertLessThan(engine.advance(to: 0.02).first!.magnification, 0)
    }

    func testCancellationIsIdempotentAndNextGestureBeginsFresh() {
        var engine = MagnificationEngine()
        _ = engine.push(direction: 1, at: 0)
        XCTAssertEqual(engine.finish(cancelled: true), [GestureSample(.cancelled)])
        XCTAssertEqual(engine.pending, 0)
        XCTAssertTrue(engine.finish(cancelled: true).isEmpty)
        XCTAssertTrue(engine.advance(to: 1).isEmpty)
        XCTAssertEqual(engine.push(direction: -1, at: 2).first?.phase, .began)
    }

    func testLongStallCancelsWithoutCatchUpZoom() {
        var engine = MagnificationEngine()
        _ = engine.push(direction: 1, at: 0)
        XCTAssertEqual(engine.advance(to: 1), [GestureSample(.cancelled)])
    }

    func testBacklogAndFrameDeltaAreBounded() {
        var engine = MagnificationEngine()
        for _ in 0..<10000 { _ = engine.push(direction: 1, at: 0) }
        XCTAssertLessThanOrEqual(engine.pending, 0.5)
        let samples = drain(&engine, from: 0)
        XCTAssertTrue(samples.allSatisfy { abs(log1p($0.magnification)) <= 0.040000001 })
    }

    func testSeparateOppositeGesturesAreReciprocal() {
        var engine = MagnificationEngine()
        _ = engine.push(direction: 1, at: 0)
        let first = drain(&engine, from: 0)
        _ = engine.push(direction: -1, at: 3)
        let second = drain(&engine, from: 3)
        let scale = (first + second).reduce(1.0) { $0 * (1 + $1.magnification) }
        XCTAssertEqual(scale, 1, accuracy: 1e-10)
    }

    func testInversionAndInvalidTime() {
        var configuration = MagnificationEngine.Configuration()
        configuration.inverted = true
        var engine = MagnificationEngine(configuration: configuration)
        XCTAssertTrue(engine.push(direction: 1, at: .nan).isEmpty)
        _ = engine.push(direction: 1, at: 0)
        XCTAssertTrue(engine.advance(to: -.infinity).isEmpty)
        XCTAssertEqual(logAmount(drain(&engine, from: 0)), -0.035, accuracy: 1e-10)
    }
}
