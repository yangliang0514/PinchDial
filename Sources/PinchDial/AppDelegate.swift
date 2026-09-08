import AppKit
import ApplicationServices
import Carbon
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, NSWindowDelegate {
    private let input = InputService()
    private let defaults = UserDefaults.standard
    private var configuration = InputConfiguration()
    private var snapshot = InputSnapshot()
    private var statusItem: NSStatusItem!
    private let statusRow = NSMenuItem(title: "Starting…", action: nil, keyEquivalent: "")
    private var enabledItem: NSMenuItem!
    private var observeItem: NSMenuItem!
    private var inverseItem: NSMenuItem!
    private var loginItem: NSMenuItem!
    private var testItem: NSMenuItem!
    private var testButton: NSButton?
    private var sensitivityItems: [NSMenuItem] = []
    private var diagnostics: NSWindow?
    private var diagnosticsText: NSTextView?
    private var observeButton: NSButton?
    private var enabledButton: NSButton?
    private var diagnosticsTimer: Timer?
    private var testWork: DispatchWorkItem?
    private var observers: [NSObjectProtocol] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        defaults.register(defaults: ["enabled": true, "sensitivity": 0.035, "inverted": false])
        configuration.enabled = defaults.bool(forKey: "enabled")
        configuration.sensitivity = defaults.double(forKey: "sensitivity")
        configuration.inverted = defaults.bool(forKey: "inverted")
        buildMenu()
        input.onSnapshot = { [weak self] value in
            guard let self else { return }
            snapshot = value
            statusRow.title = value.status
            statusItem.button?.toolTip = "PinchDial: \(value.status)"
            updateMenu()
            renderDiagnostics()
        }
        input.start()
        input.configure(configuration)
        observeWorkspace()
        if !defaults.bool(forKey: "hasShownIntroduction") || !AXIsProcessTrusted() {
            defaults.set(true, forKey: "hasShownIntroduction")
            DispatchQueue.main.async { [weak self] in self?.showDiagnostics() }
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showDiagnostics()
        input.configure(configuration, reconnect: true)
        return true
    }

    private func buildMenu() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "plus.magnifyingglass", accessibilityDescription: "PinchDial")
        let menu = NSMenu()
        menu.delegate = self
        menu.autoenablesItems = false
        statusRow.isEnabled = false
        menu.addItem(statusRow)
        menu.addItem(.separator())
        enabledItem = item("Enable PinchDial", #selector(toggleEnabled), in: menu)
        observeItem = item("Observe Only (Pass Keys Through)", #selector(toggleObserve), in: menu)
        inverseItem = item("Reverse Zoom Direction", #selector(toggleInversion), in: menu)
        let sensitivity = NSMenuItem(title: "Sensitivity", action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        submenu.autoenablesItems = false
        for (name, value) in [("Gentle", 0.018), ("Standard", 0.035), ("Fast", 0.065)] {
            let row = item(name, #selector(setSensitivity(_:)), in: submenu)
            row.representedObject = value
            sensitivityItems.append(row)
        }
        sensitivity.submenu = submenu
        menu.addItem(sensitivity)
        menu.addItem(.separator())
        item("Grant Accessibility…", #selector(grantAccessibility), in: menu)
        item("Grant Input Monitoring…", #selector(grantMonitoring), in: menu)
        item("Retry Input Connection", #selector(retry), in: menu)
        menu.addItem(.separator())
        testItem = item("Test Zoom In After 3 Seconds", #selector(scheduleTest), in: menu)
        item("Show Setup & Diagnostics…", #selector(showDiagnostics), in: menu)
        loginItem = item("Launch at Login", #selector(toggleLogin), in: menu)
        menu.addItem(.separator())
        item("Quit PinchDial", #selector(quit), in: menu)
        statusItem.menu = menu
        updateMenu()
    }

    @discardableResult
    private func item(_ title: String, _ action: Selector, in menu: NSMenu) -> NSMenuItem {
        let row = NSMenuItem(title: title, action: action, keyEquivalent: "")
        row.target = self
        menu.addItem(row)
        return row
    }

    func menuWillOpen(_ menu: NSMenu) {
        updateMenu()
        input.refresh()
    }

    private func updateMenu() {
        enabledItem.state = configuration.enabled ? .on : .off
        observeItem.state = configuration.observeOnly ? .on : .off
        observeButton?.state = observeItem.state
        enabledButton?.state = enabledItem.state
        inverseItem.state = configuration.inverted ? .on : .off
        sensitivityItems.forEach {
            $0.state = ($0.representedObject as? Double) == configuration.sensitivity ? .on : .off
        }
        let status = SMAppService.mainApp.status
        loginItem.state = status == .enabled ? .on : (status == .requiresApproval ? .mixed : .off)
        loginItem.title = status == .requiresApproval ? "Launch at Login — Approval Needed…" : "Launch at Login"
        testItem.isEnabled = configuration.enabled && !configuration.observeOnly
            && AXIsProcessTrusted() && CGPreflightPostEventAccess() && snapshot.tapConnected
        testButton?.isEnabled = testItem.isEnabled
        testButton?.title = testItem.title
    }

    private func apply(reconnect: Bool = false) {
        testWork?.cancel()
        testItem.title = "Test Zoom In After 3 Seconds"
        defaults.set(configuration.enabled, forKey: "enabled")
        defaults.set(configuration.sensitivity, forKey: "sensitivity")
        defaults.set(configuration.inverted, forKey: "inverted")
        input.configure(configuration, reconnect: reconnect)
        updateMenu()
    }

    @objc private func toggleEnabled() { configuration.enabled.toggle(); apply() }
    @objc private func toggleObserve() { configuration.observeOnly.toggle(); apply(reconnect: true) }
    @objc private func toggleInversion() { configuration.inverted.toggle(); apply() }
    @objc private func setSensitivity(_ sender: NSMenuItem) {
        if let value = sender.representedObject as? Double { configuration.sensitivity = value; apply() }
    }
    @objc private func retry() { apply(reconnect: true) }

    @objc private func grantAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        openPrivacy("Privacy_Accessibility")
    }

    @objc private func grantMonitoring() {
        _ = CGRequestListenEventAccess()
        openPrivacy("Privacy_ListenEvent")
    }

    private func openPrivacy(_ pane: String) {
        // Settings anchors are a convenience, not part of input synthesis.
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func toggleLogin() {
        do {
            switch SMAppService.mainApp.status {
            case .enabled: try SMAppService.mainApp.unregister()
            case .requiresApproval: SMAppService.openSystemSettingsLoginItems()
            default: try SMAppService.mainApp.register()
            }
        } catch {
            let alert = NSAlert()
            alert.messageText = "Could not change Launch at Login"
            alert.informativeText = "Run the bundled PinchDial.app from a stable location, then try again.\n\n\(error.localizedDescription)"
            alert.runModal()
        }
        updateMenu()
    }

    @objc private func scheduleTest() {
        testWork?.cancel()
        testItem.title = "Test Scheduled — Switch to Your App"
        updateMenu()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            testItem.title = "Test Zoom In After 3 Seconds"
            updateMenu()
            input.testGesture()
        }
        testWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 3, execute: work)
    }

    @objc private func showDiagnostics() {
        if diagnostics == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 670, height: 600),
                                  styleMask: [.titled, .closable, .resizable, .miniaturizable],
                                  backing: .buffered, defer: false)
            window.title = "PinchDial — Setup & Diagnostics"
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.minSize = NSSize(width: 540, height: 420)
            let content = window.contentView!
            let scroll = NSScrollView(frame: NSRect(x: 0, y: 90, width: 670, height: 510))
            scroll.translatesAutoresizingMaskIntoConstraints = false
            scroll.hasVerticalScroller = true
            let text = NSTextView(frame: scroll.bounds)
            text.isEditable = false
            text.isSelectable = true
            text.isRichText = false
            text.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
            text.textContainerInset = NSSize(width: 18, height: 18)
            text.isVerticallyResizable = true
            text.isHorizontallyResizable = false
            text.autoresizingMask = [.width]
            text.textContainer?.widthTracksTextView = true
            scroll.documentView = text
            content.addSubview(scroll)
            let access = NSButton(title: "Accessibility…", target: self, action: #selector(grantAccessibility))
            let monitoring = NSButton(title: "Input Monitoring…", target: self, action: #selector(grantMonitoring))
            let retryButton = NSButton(title: "Retry", target: self, action: #selector(retry))
            let observe = NSButton(checkboxWithTitle: "Observe only", target: self, action: #selector(toggleObserve))
            let enabled = NSButton(checkboxWithTitle: "Enable", target: self, action: #selector(toggleEnabled))
            observeButton = observe
            enabledButton = enabled
            [access, monitoring, retryButton].forEach { $0.bezelStyle = .rounded }
            let controls = NSStackView(views: [access, monitoring, retryButton, observe, enabled])
            controls.orientation = .horizontal
            controls.spacing = 10
            controls.translatesAutoresizingMaskIntoConstraints = false
            content.addSubview(controls)
            let test = NSButton(title: "Test Zoom In After 3 Seconds", target: self, action: #selector(scheduleTest))
            test.bezelStyle = .rounded
            test.translatesAutoresizingMaskIntoConstraints = false
            testButton = test
            content.addSubview(test)
            NSLayoutConstraint.activate([
                scroll.leadingAnchor.constraint(equalTo: content.leadingAnchor),
                scroll.trailingAnchor.constraint(equalTo: content.trailingAnchor),
                scroll.topAnchor.constraint(equalTo: content.topAnchor),
                scroll.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -90),
                controls.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 18),
                controls.trailingAnchor.constraint(lessThanOrEqualTo: content.trailingAnchor, constant: -18),
                controls.centerYAnchor.constraint(equalTo: content.bottomAnchor, constant: -64),
                test.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 18),
                test.centerYAnchor.constraint(equalTo: content.bottomAnchor, constant: -26)
            ])
            window.center()
            diagnostics = window
            diagnosticsText = text
        }
        updateMenu()
        renderDiagnostics()
        NSApp.activate(ignoringOtherApps: true)
        diagnostics?.makeKeyAndOrderFront(nil)
        diagnosticsTimer?.invalidate()
        let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in self?.input.refresh() }
        RunLoop.main.add(timer, forMode: .common)
        diagnosticsTimer = timer
    }

    private func renderDiagnostics() {
        guard let text = diagnosticsText else { return }
        let selected = text.selectedRanges
        text.string = """
        PINCHDIAL 0.1 — EXPERIMENTAL NATIVE MAGNIFICATION

        SETUP
        1. In Keychron Launcher, map clockwise to F18 and
           counterclockwise to F19 (one key press per detent).
        2. Use the menu-bar icon to grant Accessibility access.
           Grant Input Monitoring too if input is unavailable.
        3. Choose Retry Input Connection. If macOS requests it,
           quit and reopen PinchDial after granting access.
        4. Turn on Observe Only to check the counter below.
           This passes F18/F19 through and does not zoom.
        5. Turn Observe Only off; enable PinchDial. Close this
           window, focus Safari/Preview/Maps, place the pointer
           over content, and rotate the dial.

        STATUS
        \(snapshot.status)
        macOS: \(ProcessInfo.processInfo.operatingSystemVersionString)
        Accessibility: \(AXIsProcessTrusted() ? "granted" : "not granted")
        Listen access: \(CGPreflightListenEventAccess() ? "granted" : "not granted")
        Post access: \(CGPreflightPostEventAccess() ? "granted" : "not granted")
        Secure Input: \(IsSecureEventInputEnabled() ? "active" : "inactive")
        Event tap: \(snapshot.tapConnected ? "connected" : "not connected")
        Matched key presses: \(snapshot.matchedPresses)
        Last matched input: \(snapshot.lastInput)
        Submitted gesture samples: \(snapshot.postedSamples)
        Gesture active: \(snapshot.gestureActive ? "yes" : "no")
        Sensitivity (log units/detent): \(configuration.sensitivity)
        App: \(Bundle.main.bundlePath)

        TEST WITHOUT THE DIAL
        Choose Test Zoom In After 3 Seconds, then switch to a
        target app and put the pointer over its content.
        This sends one bounded detent using current settings.

        IMPORTANT LIMITS
        The gesture backend uses undocumented CGEvent fields.
        Submitted samples do not prove an app received them.
        This app does not emulate raw trackpad finger contacts.
        F18/F19 from any device are reserved while enabled.
        Observe Only is temporary and resets at the next launch.
        No unrelated keystrokes are recorded or logged.

        Close this window to stop diagnostic refreshes.
        Disable or Quit from the menu bar to stop translation.
        """
        text.selectedRanges = selected.filter { $0.rangeValue.upperBound <= (text.string as NSString).length }
    }

    func windowWillClose(_ notification: Notification) {
        diagnosticsTimer?.invalidate()
        diagnosticsTimer = nil
    }

    private func observeWorkspace() {
        let center = NSWorkspace.shared.notificationCenter
        observers.append(center.addObserver(forName: NSWorkspace.didActivateApplicationNotification,
                                            object: nil, queue: .main) { [weak self] _ in self?.input.interrupt() })
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.sessionDidResignActiveNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.testWork?.cancel()
                self?.input.suspend(true)
            })
        }
        for name in [NSWorkspace.didWakeNotification, NSWorkspace.sessionDidBecomeActiveNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.input.suspend(false)
            })
        }
    }

    @objc private func quit() { NSApp.terminate(nil) }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        testWork?.cancel()
        diagnosticsTimer?.invalidate()
        input.shutdown { sender.reply(toApplicationShouldTerminate: true) }
        return .terminateLater
    }
}
