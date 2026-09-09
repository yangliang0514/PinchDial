import SwiftUI

/// UI draft: edits remain local to this window until settings are connected.
struct SetupView: View {
    @State private var zoomIn = "F18"
    @State private var zoomOut = "F19"
    @State private var sensitivity: Double
    @State private var showInMenuBar = true
    @State private var launchAtLogin: Bool
    let accessibilityGranted: Bool
    let monitoringGranted: Bool

    init(initialSensitivity: Double, initialLaunchAtLogin: Bool,
         accessibilityGranted: Bool, monitoringGranted: Bool) {
        _sensitivity = State(initialValue: initialSensitivity)
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
                shortcutRow("Zoom in", symbol: "plus.magnifyingglass", key: $zoomIn)
                shortcutRow("Zoom out", symbol: "minus.magnifyingglass", key: $zoomOut)
            }
            .padding(.top, 10)

            Divider().padding(.vertical, 16)

            sectionTitle("Sensitivity")
            Slider(value: $sensitivity, in: 0.018...0.065)
                .accessibilityLabel("Zoom sensitivity")
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
        .frame(width: 340, height: 438, alignment: .topLeading)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title).font(.system(size: 12, weight: .semibold))
    }

    private func shortcutRow(_ title: String, symbol: String, key: Binding<String>) -> some View {
        HStack(spacing: 9) {
            Image(systemName: symbol)
                .foregroundStyle(.secondary)
                .frame(width: 18)
            Text(title)
            Spacer()
            TextField("Set shortcut", text: key)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .multilineTextAlignment(.center)
                .textFieldStyle(.roundedBorder)
                .frame(width: 94)
                .accessibilityLabel("\(title) shortcut")
                .help("Shortcut preview. Key recording will be added later.")
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
