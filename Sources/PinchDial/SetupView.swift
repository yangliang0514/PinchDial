import SwiftUI
import PinchDialCore

final class SensitivityState: ObservableObject {
    @Published var value = ZoomSensitivity.standard
}

/// Shortcut and sensitivity edits are live; other setup controls remain a UI preview.
struct SetupView: View {
    @State private var shortcuts: ZoomShortcuts
    @State private var editingZoomIn = false
    @State private var editingZoomOut = false
    let onShortcutsChange: (ZoomShortcuts) -> Void
    @ObservedObject var sensitivityState: SensitivityState
    let onSensitivityChange: (Double) -> Void
    @State private var showInMenuBar = true
    @State private var launchAtLogin: Bool
    let accessibilityGranted: Bool
    let monitoringGranted: Bool

    init(initialShortcuts: ZoomShortcuts, onShortcutsChange: @escaping (ZoomShortcuts) -> Void,
         sensitivityState: SensitivityState, onSensitivityChange: @escaping (Double) -> Void,
         initialLaunchAtLogin: Bool,
         accessibilityGranted: Bool, monitoringGranted: Bool) {
        _shortcuts = State(initialValue: initialShortcuts)
        self.onShortcutsChange = onShortcutsChange
        self.sensitivityState = sensitivityState
        self.onSensitivityChange = onSensitivityChange
        _launchAtLogin = State(initialValue: initialLaunchAtLogin)
        self.accessibilityGranted = accessibilityGranted
        self.monitoringGranted = monitoringGranted
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                Image(nsImage: NSApplication.shared.applicationIconImage)
                    .resizable()
                    .frame(width: 44, height: 44)
                VStack(alignment: .leading, spacing: 3) {
                    Text("PinchDial").font(.system(size: 19, weight: .semibold))
                    Text("Pinch to zoom. With a twist.")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }
            .padding(.bottom, 19)

            sectionTitle("Zoom shortcuts")
            VStack(spacing: 10) {
                shortcutRow("Zoom in", symbol: "plus.magnifyingglass", zoomIn: true, presented: $editingZoomIn)
                shortcutRow("Zoom out", symbol: "minus.magnifyingglass", zoomIn: false, presented: $editingZoomOut)
            }
            .padding(.top, 10)

            Text("While enabled, assigned keys are captured in other apps from every device. F18/F19 are recommended.")
                .font(.system(size: 10)).foregroundStyle(.secondary)
                .padding(.top, 8)

            Divider().padding(.vertical, 16)

            sectionTitle("Sensitivity")
            Slider(value: Binding(get: { sensitivityState.value }, set: onSensitivityChange),
                   in: ZoomSensitivity.range)
                .accessibilityLabel("Zoom sensitivity")
                .accessibilityValue(String(format: "%.2f times Standard", sensitivityState.value / ZoomSensitivity.standard))
                .help("Adjust how far each dial step zooms. Changes are saved automatically.")
                .padding(.top, 8)
            HStack {
                Text("Slower")
                Spacer()
                Text("Faster")
            }
            .font(.system(size: 10)).foregroundStyle(.secondary)

            Divider().padding(.vertical, 16)

            VStack(alignment: .leading, spacing: 10) {
                Toggle("Show in menu bar", isOn: $showInMenuBar)
                Toggle("Launch at Login", isOn: $launchAtLogin)
            }
            .toggleStyle(.checkbox)

            Divider().padding(.vertical, 16)

            sectionTitle("Permissions")
            HStack(spacing: 10) {
                permission("Accessibility", granted: accessibilityGranted)
                permission("Input Monitoring", granted: monitoringGranted)
            }
            .padding(.top, 10)
        }
        .font(.system(size: 12))
        .padding(22)
        .frame(width: 340, height: 478, alignment: .topLeading)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title).font(.system(size: 12, weight: .semibold))
    }

    private func shortcutRow(_ title: String, symbol: String, zoomIn: Bool, presented: Binding<Bool>) -> some View {
        HStack(spacing: 9) {
            Image(systemName: symbol)
                .foregroundStyle(.secondary)
                .frame(width: 18)
            Text(title)
            Spacer()
            Button { presented.wrappedValue = true } label: {
                Text((zoomIn ? shortcuts.zoomIn : shortcuts.zoomOut).label)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .frame(minWidth: 80)
            }
            .accessibilityLabel("\(title) shortcut")
            .accessibilityValue((zoomIn ? shortcuts.zoomIn : shortcuts.zoomOut).label)
            .help("Choose or record a key")
            // Prefer the field’s bottom edge; AppKit adjusts placement to fit the screen.
            .popover(isPresented: presented, attachmentAnchor: .rect(.bounds), arrowEdge: .bottom) {
                ShortcutPicker(title: title,
                               current: zoomIn ? shortcuts.zoomIn : shortcuts.zoomOut,
                               other: zoomIn ? shortcuts.zoomOut : shortcuts.zoomIn,
                               defaultKeyCode: zoomIn ? 79 : 80) { shortcut in
                    var next = shortcuts
                    if zoomIn { next.zoomIn = shortcut } else { next.zoomOut = shortcut }
                    guard next.isValid else { return }
                    shortcuts = next
                    onShortcutsChange(next)
                }
            }
        }
    }

    private func permission(_ title: String, granted: Bool) -> some View {
        Group {
            if granted {
                HStack(spacing: 5) {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                    Text(title)
                }
                .accessibilityLabel("\(title) granted")
            } else {
                // Intentionally unconnected: this UI pass must not request access.
                Button(action: {}) {
                    Text(title).frame(maxWidth: .infinity)
                }
                .controlSize(.regular)
                .help("Permission requests will be connected later.")
            }
        }
        .frame(maxWidth: .infinity, minHeight: 24)
    }
}
