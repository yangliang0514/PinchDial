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

    /// Deliver evenly spaced detents independently of the output frame cadence.
    private func rotate(_ engine: inout MagnificationEngine, rate: Int,
                        direction: Int = 1, from start: Double = 0,
                        seconds: Int = 3, fps: Int = 60) -> [[GestureSample]] {
        var frames: [[GestureSample]] = []
        var step = 0
        for frame in 1...(seconds * fps) {
            let now = start + Double(frame) / Double(fps)
            var samples: [GestureSample] = []
            while step < rate * seconds {
                let inputTime = start + (Double(step) + 0.5) / Double(rate)
                guard inputTime <= now + 1e-12 else { break }
                samples += engine.push(direction: direction, at: inputTime)
                step += 1
            }
            samples += engine.advance(to: now)
            frames.append(samples)
        }
        return frames
    }

    func testOneDetentProducesOneCompleteGestureAndPreservesAmount() {
        var engine = MagnificationEngine()
        let beginning = engine.push(direction: 1, at: 10)
        XCTAssertEqual(beginning.map(\.phase), [.began, .changed])
        let samples = beginning + drain(&engine, from: 10)
        XCTAssertEqual(samples.filter { $0.phase == .began }.count, 1)
        XCTAssertEqual(samples.filter { $0.phase == .ended }.count, 1)
        XCTAssertEqual(samples.last?.phase, .ended)
        XCTAssertEqual(logAmount(samples), 0.0525, accuracy: 1e-10)
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
        XCTAssertEqual(logAmount(samples), 0.1575, accuracy: 1e-10)
    }

    func testFrameRateDoesNotChangeTotalZoom() {
        for frame in [1.0 / 30, 1.0 / 60, 1.0 / 120] {
            var engine = MagnificationEngine()
            _ = engine.push(direction: -1, at: 0)
            XCTAssertEqual(logAmount(drain(&engine, from: 0, frame: frame)), -0.0525, accuracy: 1e-10)
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

    func testSustainedRotationPreservesRateAndTotalAcrossSensitivitiesAndFrameRates() {
        for sensitivity in [0.01, ZoomSensitivity.standard, 0.15] {
            for fps in [30, 60, 120] {
                for rate in [10, 20, 40, 60, 120, 240] {
                    for direction in [-1, 1] {
                        var configuration = MagnificationEngine.Configuration()
                        configuration.sensitivity = sensitivity
                        var engine = MagnificationEngine(configuration: configuration)
                        let frames = rotate(&engine, rate: rate, direction: direction, fps: fps)
                        let expectedRate = Double(direction * rate) * sensitivity
                        let context = "sensitivity=\(sensitivity), fps=\(fps), rate=\(rate), direction=\(direction)"
                        XCTAssertEqual(logAmount(frames.suffix(fps).flatMap { $0 }),
                                       expectedRate, accuracy: 1e-8, context)
                        let samples = frames.flatMap { $0 } + drain(&engine, from: 3, frame: 1 / Double(fps))
                        XCTAssertEqual(logAmount(samples), expectedRate * 3, accuracy: 1e-8, context)
                        XCTAssertTrue(samples.allSatisfy { $0.magnification.isFinite && $0.magnification > -1 }, context)
                    }
                }
            }
        }
    }

    func testSlowFastSlowRotationTracksEachRateWithoutLosingMovement() {
        var engine = MagnificationEngine()
        var samples: [GestureSample] = []
        for (index, rate) in [20, 120, 20].enumerated() {
            let frames = rotate(&engine, rate: rate, from: Double(index * 3))
            samples += frames.flatMap { $0 }
            XCTAssertEqual(logAmount(frames.suffix(60).flatMap { $0 }),
                           Double(rate) * ZoomSensitivity.standard, accuracy: 1e-8)
            // The new speed should settle promptly, including after slowing down.
            let settledWindow = frames.dropFirst(12).prefix(12).flatMap { $0 }
            XCTAssertEqual(logAmount(settledWindow) / 0.2,
                           Double(rate) * ZoomSensitivity.standard, accuracy: 0.03)
        }
        samples += drain(&engine, from: 9)
        XCTAssertEqual(logAmount(samples), Double((20 + 120 + 20) * 3) * ZoomSensitivity.standard,
                       accuracy: 1e-8)
    }

    func testFastRotationTailSettlesPromptlyAndReversalTakesControl() {
        for direction in [-1, 1] {
            var configuration = MagnificationEngine.Configuration()
            configuration.sensitivity = 0.15
            var engine = MagnificationEngine(configuration: configuration)
            _ = rotate(&engine, rate: 240, direction: direction)
            let pendingAtStop = abs(engine.pending)
            _ = engine.advance(to: 3.135)
            XCTAssertLessThan(abs(engine.pending), pendingAtStop * 0.051,
                              "At least 95% of the tail should settle within 135 ms")
            _ = engine.push(direction: -direction, at: 3.14)
            let reversed = engine.advance(to: 3.15)
            XCTAssertGreaterThan(logAmount(reversed) * Double(-direction), 0)
        }
    }

    func testBriefFrameDelayPreservesFastRotationMovement() {
        var configuration = MagnificationEngine.Configuration()
        configuration.sensitivity = 0.15
        var engine = MagnificationEngine(configuration: configuration)
        var samples = rotate(&engine, rate: 120).flatMap { $0 }
        // Input continues while output misses six frames, then the timer resumes.
        for step in 0..<12 {
            samples += engine.push(direction: 1, at: 3 + Double(step) / 120)
        }
        samples += engine.advance(to: 3.1)
        samples += drain(&engine, from: 3.1)
        XCTAssertEqual(logAmount(samples), Double(360 + 12) * 0.15, accuracy: 1e-8)
    }

    func testPathologicalBurstCancelsInsteadOfClippingAndReplayingBacklog() {
        var configuration = MagnificationEngine.Configuration()
        configuration.sensitivity = 0.15
        for direction in [-1, 1] {
            var engine = MagnificationEngine(configuration: configuration)
            for _ in 0..<106 { _ = engine.push(direction: direction, at: 0) }
            XCTAssertTrue(engine.isActive)
            XCTAssertEqual(engine.push(direction: direction, at: 0), [GestureSample(.cancelled)])
            XCTAssertEqual(engine.pending, 0)
            XCTAssertTrue(engine.advance(to: 0.1).isEmpty)
            XCTAssertEqual(engine.push(direction: direction, at: 1).first?.phase, .began)
        }
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

    func testSensitivityRangePreservesZoomAmountInBothDirections() {
        for sensitivity in [ZoomSensitivity.range.lowerBound, ZoomSensitivity.standard, ZoomSensitivity.range.upperBound] {
            for direction in [-1, 1] {
                var configuration = MagnificationEngine.Configuration()
                configuration.sensitivity = sensitivity
                var engine = MagnificationEngine(configuration: configuration)
                _ = engine.push(direction: direction, at: 0)
                let samples = drain(&engine, from: 0)
                XCTAssertEqual(logAmount(samples), Double(direction) * sensitivity, accuracy: 1e-10)
                XCTAssertTrue(samples.allSatisfy { $0.magnification.isFinite && $0.magnification > -1 })
            }
        }
    }

    func testSensitivityRestoration() {
        XCTAssertEqual(ZoomSensitivity.restored(nil), ZoomSensitivity.standard)
        XCTAssertEqual(ZoomSensitivity.restored(0.035), 0.035)
        XCTAssertEqual(ZoomSensitivity.restored(0.083), 0.083)
        XCTAssertEqual(ZoomSensitivity.restored(.nan), ZoomSensitivity.standard)
        XCTAssertEqual(ZoomSensitivity.restored(.infinity), ZoomSensitivity.standard)
        XCTAssertEqual(ZoomSensitivity.restored(-1), ZoomSensitivity.range.lowerBound)
        XCTAssertEqual(ZoomSensitivity.restored(1), ZoomSensitivity.range.upperBound)
    }

    func testInvalidTime() {
        var engine = MagnificationEngine()
        XCTAssertTrue(engine.push(direction: 1, at: .nan).isEmpty)
        _ = engine.push(direction: 1, at: 0)
        XCTAssertTrue(engine.advance(to: -.infinity).isEmpty)
        XCTAssertEqual(logAmount(drain(&engine, from: 0)), 0.0525, accuracy: 1e-10)
    }
}
