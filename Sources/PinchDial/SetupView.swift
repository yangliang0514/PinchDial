import SwiftUI
import PinchDialCore
import ServiceManagement

final class SensitivityState: ObservableObject {
    @Published var value = ZoomSensitivity.standard
}

final class LoginState: ObservableObject {
    @Published var status: SMAppService.Status = .notRegistered

    var isRequested: Bool { status == .enabled || status == .requiresApproval }
}

final class PermissionState: ObservableObject {
    @Published var accessibilityGranted = false
    @Published var monitoringGranted = false
    @Published var accessibilityRequested = false
    @Published var monitoringRequested = false

    var hasMissingPermission: Bool { !accessibilityGranted || !monitoringGranted }
    var showsRestartHint: Bool {
        (accessibilityRequested && !accessibilityGranted)
            || (monitoringRequested && !monitoringGranted)
    }
}

struct SetupView: View {
    @State private var shortcuts: ZoomShortcuts
    @State private var editingZoomIn = false
    @State private var editingZoomOut = false
    let onShortcutsChange: (ZoomShortcuts) -> Void
    @ObservedObject var sensitivityState: SensitivityState
    let onSensitivityChange: (Double) -> Void
    @State private var showInMenuBar: Bool
    let onShowInMenuBarChange: (Bool) -> Void
    @ObservedObject var loginState: LoginState
    let onLaunchAtLoginChange: (Bool) -> Void
    @ObservedObject var permissionState: PermissionState
    let onGrantAccessibility: () -> Void
    let onGrantMonitoring: () -> Void

    init(initialShortcuts: ZoomShortcuts, onShortcutsChange: @escaping (ZoomShortcuts) -> Void,
         sensitivityState: SensitivityState, onSensitivityChange: @escaping (Double) -> Void,
         initialShowInMenuBar: Bool, onShowInMenuBarChange: @escaping (Bool) -> Void,
         loginState: LoginState, onLaunchAtLoginChange: @escaping (Bool) -> Void,
         permissionState: PermissionState,
         onGrantAccessibility: @escaping () -> Void, onGrantMonitoring: @escaping () -> Void) {
        _shortcuts = State(initialValue: initialShortcuts)
        self.onShortcutsChange = onShortcutsChange
        self.sensitivityState = sensitivityState
        self.onSensitivityChange = onSensitivityChange
        _showInMenuBar = State(initialValue: initialShowInMenuBar)
        self.onShowInMenuBarChange = onShowInMenuBarChange
        self.loginState = loginState
        self.onLaunchAtLoginChange = onLaunchAtLoginChange
        self.permissionState = permissionState
        self.onGrantAccessibility = onGrantAccessibility
        self.onGrantMonitoring = onGrantMonitoring
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
                    .onChange(of: showInMenuBar, perform: onShowInMenuBarChange)
                    .help("Show the PinchDial icon on the right side of the menu bar. Setup remains available from the Dock.")
                HStack {
                    Toggle("Launch at Login", isOn: Binding(
                        get: { loginState.isRequested }, set: onLaunchAtLoginChange))
                        .help("Start PinchDial automatically when you log in to your Mac.")
                    if loginState.status == .requiresApproval {
                        Spacer()
                        Button("Approval Needed…") {
                            SMAppService.openSystemSettingsLoginItems()
                        }
                        .font(.system(size: 10))
                        .help("Allow PinchDial in System Settings to finish enabling launch at login.")
                    }
                }
            }
            .toggleStyle(.checkbox)

            Divider().padding(.vertical, 16)

            HStack(spacing: 4) {
                sectionTitle("Permissions")
                if permissionState.hasMissingPermission {
                    Text("(click to request permission)")
                        .font(.system(size: 10)).foregroundStyle(.secondary)
                }
            }
            HStack(spacing: 10) {
                permission("Accessibility", granted: permissionState.accessibilityGranted, action: onGrantAccessibility)
                permission("Input Monitoring", granted: permissionState.monitoringGranted, action: onGrantMonitoring)
            }
            .padding(.top, 10)
            if permissionState.showsRestartHint {
                Text("If you enabled access, restart to apply it.")
                    .font(.system(size: 10)).foregroundStyle(.secondary)
                    .padding(.top, 10)
            }
        }
        .font(.system(size: 12))
        .padding(22)
        .frame(width: 340, height: permissionState.showsRestartHint ? 510 : 478, alignment: .topLeading)
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

    private func permission(_ title: String, granted: Bool, action: @escaping () -> Void) -> some View {
        Group {
            if granted {
                HStack(spacing: 5) {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                    Text(title)
                }
                .accessibilityLabel("\(title) granted")
            } else {
                Button(action: action) {
                    Text(title).frame(maxWidth: .infinity)
                }
                .controlSize(.regular)
                .help("Allow PinchDial in System Settings → Privacy & Security → \(title).")
            }
        }
        .frame(maxWidth: .infinity, minHeight: 24)
    }
}
