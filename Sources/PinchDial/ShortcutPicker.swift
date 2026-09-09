import AppKit
import SwiftUI
import PinchDialCore

/// A local monitor needs no additional permissions and never records in other apps.
final class KeyRecorder: ObservableObject {
    @Published private(set) var isRecording = false
    @Published private(set) var message: String?
    var onKey: ((UInt16) -> Void)?
    private var monitor: Any?
    private var deactivation: NSObjectProtocol?
    private var heldKeys: Set<UInt16> = []

    func install() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp, .flagsChanged]) { [weak self] event in
            guard let self else { return event }
            if event.type == .keyUp {
                return heldKeys.remove(event.keyCode) != nil ? nil : event
            }
            if event.type == .keyDown, heldKeys.contains(event.keyCode) { return nil }
            guard isRecording else { return event }
            if event.type == .flagsChanged {
                message = "Press one key without Command, Option, Control or Shift."
                return event
            }
            guard !event.isARepeat else { return nil }
            heldKeys.insert(event.keyCode)
            guard ShortcutModifiers.fromEventFlags(UInt64(event.modifierFlags.rawValue)).isEmpty else {
                message = "Key combinations aren’t supported yet. Release the modifiers and try again."
                return nil
            }
            guard KeyCatalog.key(event.keyCode) != nil else {
                message = "That key isn’t supported. Choose a key from the list."
                return nil
            }
            isRecording = false
            message = nil
            onKey?(event.keyCode)
            return nil
        }
        deactivation = NotificationCenter.default.addObserver(forName: NSApplication.didResignActiveNotification,
                                                               object: nil, queue: .main) { [weak self] _ in
            self?.stop()
            self?.heldKeys.removeAll()
        }
    }

    func start() {
        message = nil
        isRecording = true
    }
    func stop() { isRecording = false; message = nil }
    func uninstall() {
        stop()
        if let monitor { NSEvent.removeMonitor(monitor) }
        if let deactivation { NotificationCenter.default.removeObserver(deactivation) }
        monitor = nil
        deactivation = nil
        heldKeys.removeAll()
        onKey = nil
    }
    deinit {
        if let monitor { NSEvent.removeMonitor(monitor) }
        if let deactivation { NotificationCenter.default.removeObserver(deactivation) }
    }
}

struct ShortcutPicker: View {
    let title: String
    let current: Shortcut
    let other: Shortcut
    let defaultKeyCode: UInt16
    let onSelect: (Shortcut) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var selection: UInt16?
    @State private var conflict = false
    @StateObject private var recorder = KeyRecorder()

    private var matches: [KeyDefinition] { KeyCatalog.all.filter { $0.matches(query) } }
    private func select(_ code: UInt16) {
        selection = code
        guard code != other.keyCode else {
            conflict = true
            return
        }
        conflict = false
        onSelect(Shortcut(keyCode: code))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("\(title) shortcut").font(.headline)
            TextField("Search keys, e.g. F19 or Space", text: $query)
                .textFieldStyle(.roundedBorder)
                .accessibilityLabel("Search supported keys")
                .disabled(recorder.isRecording)
            if matches.isEmpty {
                Text("No matching keys").foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 215)
            } else {
                List(selection: Binding<UInt16?>(
                    get: { selection },
                    set: { if let code = $0 { select(code) } }
                )) {
                    ForEach(KeyCatalog.groups, id: \.self) { group in
                        let entries = matches.filter { $0.group == group }
                        if !entries.isEmpty {
                            Section(group) {
                                ForEach(entries) { key in
                                    Button { select(key.id) } label: {
                                        HStack {
                                            Text(key.name)
                                            Spacer()
                                            if key.id == other.keyCode {
                                                Text("Used by other direction").font(.caption).foregroundStyle(.secondary)
                                            }
                                        }
                                        .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                    .contentShape(Rectangle())
                                    .simultaneousGesture(TapGesture(count: 2).onEnded {
                                        select(key.id)
                                        if !conflict { dismiss() }
                                    })
                                    .tag(key.id)
                                }
                            }
                        }
                    }
                }
                .frame(height: 215)
                .disabled(recorder.isRecording)
            }
            if let message = recorder.message {
                Text(message).font(.caption).foregroundStyle(.orange)
            }
            if conflict {
                Text("Zoom in and zoom out must use different keys.")
                    .font(.caption).foregroundStyle(.red)
            }
            HStack {
                Button(recorder.isRecording ? "Stop recording" : "Record a key") {
                    if recorder.isRecording { recorder.stop() } else { recorder.start() }
                }
                Spacer()
                Button("Use Default \(Shortcut(keyCode: defaultKeyCode).label)") {
                    recorder.stop()
                    select(defaultKeyCode)
                }
                .disabled(defaultKeyCode == other.keyCode)
                .help(defaultKeyCode == other.keyCode ? "The default key is used by the other direction." : "Restore the default shortcut")
            }
            if recorder.isRecording {
                Text("Press a key or turn your dial…").font(.caption)
            }

        }
        .padding(16)
        .frame(width: 360)
        .onAppear {
            selection = current.keyCode
            recorder.onKey = { code in
                query = ""
                select(code)
            }
            recorder.install()
        }
        .onDisappear { recorder.uninstall() }
    }
}
