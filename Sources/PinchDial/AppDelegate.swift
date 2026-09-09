import AppKit
import PinchDialCore
import SwiftUI
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
    private var loginItem: NSMenuItem!
    private let sensitivityState = SensitivityState()
    private var diagnostics: NSWindow?
    private var observers: [NSObjectProtocol] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        defaults.register(defaults: ["enabled": true])
        configuration.enabled = defaults.bool(forKey: "enabled")
        configuration.sensitivity = ZoomSensitivity.restored(
            (defaults.object(forKey: "sensitivity") as? NSNumber)?.doubleValue
        )
        sensitivityState.value = configuration.sensitivity
        configuration.shortcuts = ZoomShortcuts.restored(from: defaults.data(forKey: "zoomShortcuts"))
        buildMenu()
        input.onSnapshot = { [weak self] value in
            guard let self else { return }
            snapshot = value
            statusRow.title = value.status
            statusItem.button?.toolTip = "PinchDial: \(value.status)"
            updateMenu()
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
        let icon = NSImage(named: "MenuBarIcon")
        icon?.size = NSSize(width: 18, height: 18)
        icon?.isTemplate = true
        statusItem.button?.image = icon
        statusItem.button?.setAccessibilityLabel("PinchDial")
        let menu = NSMenu()
        menu.delegate = self
        menu.autoenablesItems = false
        statusRow.isEnabled = false
        menu.addItem(statusRow)
        menu.addItem(.separator())
        enabledItem = item("Enable PinchDial", #selector(toggleEnabled), in: menu)
        menu.addItem(.separator())
        item("Grant Accessibility…", #selector(grantAccessibility), in: menu)
        item("Grant Input Monitoring…", #selector(grantMonitoring), in: menu)
        menu.addItem(.separator())
        item("Show Setup…", #selector(showDiagnostics), in: menu)
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
        let status = SMAppService.mainApp.status
        loginItem.state = status == .enabled ? .on : (status == .requiresApproval ? .mixed : .off)
        loginItem.title = status == .requiresApproval ? "Launch at Login — Approval Needed…" : "Launch at Login"
    }

    private func apply() {
        configuration.sensitivity = ZoomSensitivity.clamped(configuration.sensitivity)
        sensitivityState.value = configuration.sensitivity
        defaults.set(configuration.enabled, forKey: "enabled")
        defaults.set(configuration.sensitivity, forKey: "sensitivity")
        if let data = try? JSONEncoder().encode(configuration.shortcuts) {
            defaults.set(data, forKey: "zoomShortcuts")
        }
        input.configure(configuration)
        updateMenu()
    }

    @objc private func toggleEnabled() { configuration.enabled.toggle(); apply() }

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

    @objc private func showDiagnostics() {
        NSApp.setActivationPolicy(.regular)
        if diagnostics == nil {
            let view = SetupView(
                initialShortcuts: configuration.shortcuts,
                onShortcutsChange: { [weak self] value in
                    guard let self, value.isValid else { return }
                    self.configuration.shortcuts = value
                    self.apply()
                },
                sensitivityState: sensitivityState,
                onSensitivityChange: { [weak self] value in
                    guard let self else { return }
                    self.configuration.sensitivity = value
                    self.apply()
                },
                initialLaunchAtLogin: SMAppService.mainApp.status == .enabled,
                accessibilityGranted: AXIsProcessTrusted(),
                monitoringGranted: CGPreflightListenEventAccess()
            )
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 340, height: 478),
                                  styleMask: [.titled, .closable, .miniaturizable],
                                  backing: .buffered, defer: false)
            window.title = "PinchDial"
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.contentView = NSHostingView(rootView: view)
            window.center()
            diagnostics = window
        }
        NSApp.activate(ignoringOtherApps: true)
        diagnostics?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow, window === diagnostics else { return }
        NSApp.setActivationPolicy(.accessory)
    }

    private func observeWorkspace() {
        let center = NSWorkspace.shared.notificationCenter
        observers.append(center.addObserver(forName: NSWorkspace.didActivateApplicationNotification,
                                            object: nil, queue: .main) { [weak self] _ in self?.input.interrupt() })
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.sessionDidResignActiveNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
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
        input.shutdown { sender.reply(toApplicationShouldTerminate: true) }
        return .terminateLater
    }
}
