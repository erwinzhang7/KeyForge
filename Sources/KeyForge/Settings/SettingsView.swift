import SwiftUI
import ServiceManagement

public struct SettingsView: View {
    @ObservedObject var settings = AppSettings.shared
    @ObservedObject var ax = AccessibilityHelper.shared
    let store: MacroStore

    public init(store: MacroStore) { self.store = store }

    public var body: some View {
        TabView {
            generalTab
                .tabItem { Label("General", systemImage: "gear") }
            snippetsTab
                .tabItem { Label("Snippets", systemImage: "text.cursor") }
            advancedTab
                .tabItem { Label("Advanced", systemImage: "wrench.and.screwdriver") }
            permissionsTab
                .tabItem { Label("Permissions", systemImage: "lock.shield") }
        }
        .frame(width: 460, height: 320)
    }

    private var generalTab: some View {
        Form {
            Toggle("Launch at login", isOn: $settings.launchAtLogin)
                .onChange(of: settings.launchAtLogin) { newValue in
                    do {
                        if newValue {
                            try SMAppService.mainApp.register()
                        } else {
                            try SMAppService.mainApp.unregister()
                        }
                    } catch {
                        Logger.shared.error("SMAppService toggle failed: \(error)")
                    }
                }
            Toggle("Global hotkeys enabled", isOn: $settings.globalHotkeysEnabled)
            Toggle("Strict conflict detection (warn on system shortcuts)", isOn: $settings.conflictDetectionStrict)
            HStack {
                Text("Chord timeout: \(settings.chordTimeoutMS) ms")
                Slider(value: Binding(
                    get: { Double(settings.chordTimeoutMS) },
                    set: { settings.chordTimeoutMS = Int($0) }
                ), in: 200...1000, step: 50)
            }
        }
        .padding(16)
    }

    private var snippetsTab: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle("Enable text expansion snippets", isOn: $settings.snippetsEnabled)
            Text("Open the main window's Snippets sheet to add/edit individual snippets.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(16)
    }

    private var advancedTab: some View {
        Form {
            HStack {
                Text("Action timeout: \(settings.actionTimeoutMS) ms")
                Slider(value: Binding(
                    get: { Double(settings.actionTimeoutMS) },
                    set: { settings.actionTimeoutMS = Int($0) }
                ), in: 1000...60_000, step: 500)
            }
            Picker("Log level", selection: Binding(
                get: { settings.logLevel },
                set: { settings.logLevel = $0 }
            )) {
                ForEach(LogLevel.allCases, id: \.self) { lvl in
                    Text(lvl.rawValue.capitalized).tag(lvl)
                }
            }
            HStack {
                Button("Export debug log…") { exportLog() }
                Spacer()
            }
        }
        .padding(16)
    }

    private var permissionsTab: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Image(systemName: ax.isTrusted ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundStyle(ax.isTrusted ? .green : .red)
                Text("Accessibility: \(ax.isTrusted ? "Granted" : "Not granted")")
                Spacer()
                Button("Open Settings") { ax.openSystemSettings() }
                Button("Request") { ax.requestTrust() }
            }
            Text("Required for global hotkey interception. Re-checks every 2 seconds.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Divider()
            HStack {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                Text("Automation: requested lazily when an AppleScript action is run.")
            }
            HStack {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                Text("Notifications: requested when the first notification action runs.")
            }
            Spacer()
        }
        .padding(16)
    }

    private func exportLog() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "keyforge-debug.log"
        if panel.runModal() == .OK, let url = panel.url {
            try? Logger.shared.exportBuffer().write(to: url, atomically: true, encoding: .utf8)
        }
    }
}
