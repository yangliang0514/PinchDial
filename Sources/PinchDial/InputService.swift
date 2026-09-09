import AppKit
import Carbon
import CoreGraphics
import PinchDialCore

struct InputConfiguration {
    var enabled = true
    var sensitivity = ZoomSensitivity.standard
    var shortcuts = ZoomShortcuts()
}

struct InputSnapshot {
    var status = "Starting input service…"
    var tapConnected = false
    var matchedPresses = 0
    var postedSamples = 0
    var lastInput = "None"
    var gestureActive = false
}

/// Public methods and callbacks belong to the main thread. Mutable input state
/// below belongs exclusively to the worker run loop, including the CGEvent tap.
final class InputService {
    var onSnapshot: ((InputSnapshot) -> Void)?
    private var workerLoop: CFRunLoop?
    private var pendingCommands: [() -> Void] = []
    private var worker: Thread?

    // Worker-owned state.
    private var tap: CFMachPort?
    private var tapSource: CFRunLoopSource?
    private var frameTimer: Timer?
    private var configuration = InputConfiguration()
    private var engine = MagnificationEngine()
    private var keys = KeyBridge()
    private var heldZoom = HeldZoom()
    private let backend = GestureBackend()
    private var snapshot = InputSnapshot()
    private var targetPID: pid_t?
    private var anchor = CGPoint.zero
    private var sessionSuspended = false

    func start() {
        let thread = Thread { [self] in
            autoreleasepool {
                let keepAlive = Port()
                RunLoop.current.add(keepAlive, forMode: .default)
                let loop = CFRunLoopGetCurrent()!
                DispatchQueue.main.async { [self] in
                    workerLoop = loop
                    let commands = pendingCommands
                    pendingCommands.removeAll()
                    commands.forEach { enqueue($0) }
                }
                CFRunLoopRun()
                keepAlive.invalidate()
            }
        }
        thread.name = "PinchDial.Input"
        thread.qualityOfService = .userInteractive
        worker = thread
        thread.start()
    }

    func configure(_ value: InputConfiguration, reconnect: Bool = false) {
        enqueue { [self] in
            cancelGesture()
            configuration = value
            engine.configuration.sensitivity = value.sensitivity
            if reconnect || tap == nil { connectTap() }
            refreshStatus()
        }
    }

    func refresh() {
        enqueue { [self] in
            snapshot.gestureActive = engine.isActive
            refreshStatus()
        }
    }

    func interrupt() { enqueue { [self] in cancelGesture(); publish() } }

    func suspend(_ suspended: Bool) {
        enqueue { [self] in
            sessionSuspended = suspended
            cancelGesture()
            keys.reset()
            if !suspended && tap == nil { connectTap() }
            refreshStatus()
        }
    }

    func shutdown(completion: @escaping () -> Void) {
        enqueue { [self] in
            cancelGesture()
            disconnectTap()
            CFRunLoopStop(CFRunLoopGetCurrent())
            DispatchQueue.main.async(execute: completion)
        }
    }

    private func enqueue(_ command: @escaping () -> Void) {
        dispatchPrecondition(condition: .onQueue(.main))
        guard let loop = workerLoop else { pendingCommands.append(command); return }
        CFRunLoopPerformBlock(loop, CFRunLoopMode.commonModes.rawValue) {
            autoreleasepool(invoking: command)
        }
        CFRunLoopWakeUp(loop)
    }

    private var canGenerate: Bool {
        configuration.enabled && !sessionSuspended
            && tap != nil && AXIsProcessTrusted() && CGPreflightPostEventAccess()
            && !IsSecureEventInputEnabled()
    }

    private func connectTap() {
        disconnectTap()
        let mask = (CGEventMask(1) << CGEventType.keyDown.rawValue)
            | (CGEventMask(1) << CGEventType.keyUp.rawValue)
            | (CGEventMask(1) << CGEventType.flagsChanged.rawValue)
        let callback: CGEventTapCallBack = { _, type, event, context in
            guard let context else { return Unmanaged.passUnretained(event) }
            let service = Unmanaged<InputService>.fromOpaque(context).takeUnretainedValue()
            return autoreleasepool { service.receive(type: type, event: event) }
        }
        guard let created = CGEvent.tapCreate(
            tap: .cgSessionEventTap, place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask, callback: callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            snapshot.status = "Input unavailable — check permissions, then quit and reopen"
            snapshot.tapConnected = false
            publish()
            return
        }
        tap = created
        tapSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, created, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), tapSource, .commonModes)
        CGEvent.tapEnable(tap: created, enable: true)
        snapshot.tapConnected = true
    }

    private func disconnectTap() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: false); CFMachPortInvalidate(tap) }
        if let tapSource { CFRunLoopRemoveSource(CFRunLoopGetCurrent(), tapSource, .commonModes) }
        tap = nil
        tapSource = nil
        keys.reset()
        snapshot.tapConnected = false
    }

    private func receive(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            cancelGesture()
            keys.reset()
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            snapshot.status = "Input tap restarted after interruption"
            publish()
            return Unmanaged.passUnretained(event)
        }
        if type == .flagsChanged {
            if !ShortcutModifiers.fromEventFlags(event.flags.rawValue).isEmpty { cancelGesture() }
            return Unmanaged.passUnretained(event)
        }
        guard type == .keyDown || type == .keyUp,
              event.getIntegerValueField(.eventSourceUserData) != GestureBackend.marker else {
            return Unmanaged.passUnretained(event)
        }
        let rawKey = event.getIntegerValueField(.keyboardEventKeycode)
        guard let keyCode = UInt16(exactly: rawKey) else { return Unmanaged.passUnretained(event) }
        let down = type == .keyDown
        let repeated = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
        // Let our own controls receive assigned keys, including search and recording.
        let isOwnApp = NSWorkspace.shared.frontmostApplication?.processIdentifier == ProcessInfo.processInfo.processIdentifier
        let decision = keys.handle(key: keyCode, down: down, repeated: repeated,
                                   enabled: canGenerate && !isOwnApp,
                                   shortcuts: configuration.shortcuts,
                                   modifiers: .fromEventFlags(event.flags.rawValue))
        if decision.direction != nil {
            snapshot.matchedPresses += 1
            snapshot.lastInput = "\(KeyCatalog.key(keyCode)?.name ?? String(keyCode)) at \(Date().formatted(date: .omitted, time: .standard))"
        }
        if !down, heldZoom.release(key: keyCode) { cancelGesture() }
        if let direction = decision.direction {
            push(direction)
            if targetPID != nil {
                heldZoom.begin(key: keyCode, direction: direction, at: ProcessInfo.processInfo.systemUptime)
            }
        }
        // Counters are read on demand; no per-detent main-thread work or disk logs.
        return decision.consume ? nil : Unmanaged.passUnretained(event)
    }

    private func push(_ direction: Int) {
        let frontmost = NSWorkspace.shared.frontmostApplication?.processIdentifier
        guard let frontmost, frontmost != ProcessInfo.processInfo.processIdentifier else { return }
        if engine.isActive && frontmost != targetPID { cancelGesture() }
        if !engine.isActive {
            targetPID = frontmost
            anchor = CGEvent(source: nil)?.location ?? .zero
        }
        emit(engine.push(direction: direction, at: ProcessInfo.processInfo.systemUptime))
        if frameTimer == nil {
            let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
                autoreleasepool { self?.tick() }
            }
            timer.tolerance = 0.001
            RunLoop.current.add(timer, forMode: .common)
            frameTimer = timer
        }
    }

    private func tick() {
        guard canGenerate, NSWorkspace.shared.frontmostApplication?.processIdentifier == targetPID else {
            cancelGesture()
            return
        }
        let now = ProcessInfo.processInfo.systemUptime
        if let direction = heldZoom.advance(to: now) { push(direction) }
        emit(engine.advance(to: now))
        if !engine.isActive && !heldZoom.isHeld { stopTimer(); targetPID = nil }
    }

    private func emit(_ samples: [GestureSample], terminalTarget: pid_t? = nil) {
        for sample in samples {
            if backend.post(sample, location: anchor, terminalTarget: terminalTarget) {
                snapshot.postedSamples += 1
            }
        }
        snapshot.gestureActive = engine.isActive
    }

    private func cancelGesture() {
        heldZoom.cancel()
        let terminal = engine.finish(cancelled: true)
        if CGPreflightPostEventAccess(), let targetPID {
            emit(terminal, terminalTarget: targetPID)
        }
        stopTimer()
        targetPID = nil
        snapshot.gestureActive = false
    }

    private func stopTimer() { frameTimer?.invalidate(); frameTimer = nil }

    private func refreshStatus() {
        snapshot.tapConnected = tap.map { CGEvent.tapIsEnabled(tap: $0) } ?? false
        if tap == nil { snapshot.status = "Input unavailable — check permissions, then quit and reopen" }
        else if !snapshot.tapConnected { snapshot.status = "Input tap disabled — quit and reopen PinchDial" }
        else if sessionSuspended { snapshot.status = "Paused while session is inactive" }
        else if !configuration.enabled { snapshot.status = "Disabled — keys pass through" }
        else if !AXIsProcessTrusted() || !CGPreflightPostEventAccess() {
            snapshot.status = "Accessibility / posting access required"
        } else if IsSecureEventInputEnabled() { snapshot.status = "Paused during Secure Input" }
        else { snapshot.status = "Ready — \(configuration.shortcuts.zoomIn.label) zooms in, \(configuration.shortcuts.zoomOut.label) zooms out" }
        publish()
    }

    private func publish() {
        let value = snapshot
        DispatchQueue.main.async { [weak self] in self?.onSnapshot?(value) }
    }
}
