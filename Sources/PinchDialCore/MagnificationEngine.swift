import Foundation

public enum GesturePhase: Equatable {
    case began, changed, ended, cancelled
}

public struct GestureSample: Equatable {
    public let phase: GesturePhase
    public let magnification: Double

    public init(_ phase: GesturePhase, _ magnification: Double = 0) {
        self.phase = phase
        self.magnification = magnification
    }
}

/// Deterministic, clock-independent gesture state. All calls must be serialized.
/// Input and pending movement are in log-scale units; output is a relative scale delta.
public struct MagnificationEngine {
    public struct Configuration {
        public var sensitivity: Double = 0.035
        public var timeConstant: Double = 0.045
        public var idleTimeout: Double = 0.16
        public init() {}
    }

    public var configuration: Configuration
    public private(set) var isActive = false
    public private(set) var pending = 0.0
    private var lastInput = 0.0
    private var lastFrame = 0.0
    private var lastDirection = 0
    private let epsilon = 0.00001

    public init(configuration: Configuration = .init()) {
        self.configuration = configuration
    }

    public mutating func push(direction: Int, at time: Double) -> [GestureSample] {
        guard direction != 0, time.isFinite else { return [] }
        let sign = direction > 0 ? 1 : -1
        var samples: [GestureSample] = []
        if !isActive {
            isActive = true
            lastFrame = time
            // The zero changed sample is part of the historical synthesis recipe.
            samples = [GestureSample(.began), GestureSample(.changed)]
        } else if sign != lastDirection {
            // A reversal takes control immediately instead of fighting an old tail.
            pending = 0
        }
        lastDirection = sign
        lastInput = time
        let sensitivity = configuration.sensitivity.isFinite
            ? min(max(configuration.sensitivity, 0.001), 0.15) : 0.035
        pending = min(max(pending + Double(sign) * sensitivity, -0.5), 0.5)
        return samples
    }

    public mutating func advance(to time: Double) -> [GestureSample] {
        guard isActive, time.isFinite, time > lastFrame else { return [] }
        // Don't replay a long backlog after a stalled run loop or system sleep.
        if time - lastFrame > 0.5 { return finish(cancelled: true) }
        let elapsed = time - lastFrame
        lastFrame = time
        let tau = configuration.timeConstant.isFinite
            ? min(max(configuration.timeConstant, 0.01), 0.15) : 0.045
        var amount = pending * (1 - exp(-elapsed / tau))
        amount = min(max(amount, -0.04), 0.04)
        if abs(pending - amount) < epsilon { amount = pending }
        pending -= amount
        var samples: [GestureSample] = []
        if amount != 0 { samples.append(GestureSample(.changed, expm1(amount))) }
        let timeout = configuration.idleTimeout.isFinite
            ? min(max(configuration.idleTimeout, 0.05), 0.4) : 0.16
        if time - lastInput >= timeout && pending == 0 {
            samples += finish(cancelled: false)
        }
        return samples
    }

    public mutating func finish(cancelled: Bool) -> [GestureSample] {
        guard isActive else { return [] }
        isActive = false
        pending = 0
        lastDirection = 0
        return [GestureSample(cancelled ? .cancelled : .ended)]
    }
}
