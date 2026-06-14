import SwiftUI
import AppKit

public struct OnboardingView: View {
    @ObservedObject var ax = AccessibilityHelper.shared
    @ObservedObject var store: MacroStore
    @State private var step: Int = 0
    let onComplete: () -> Void

    public init(store: MacroStore, onComplete: @escaping () -> Void) {
        self.store = store
        self.onComplete = onComplete
    }

    public var body: some View {
        VStack(spacing: 20) {
            ProgressView(value: Double(step), total: 3)
                .padding(.top, 8)
            content
                .padding(.horizontal, 24)
            Spacer()
            HStack {
                if step > 0 {
                    Button("Back") { step -= 1 }
                }
                Spacer()
                primaryButton
            }
            .padding([.horizontal, .bottom], 24)
        }
        .frame(width: 480, height: 360)
        .onAppear { ax.refresh() }
    }

    @ViewBuilder
    private var content: some View {
        switch step {
        case 0:
            VStack(alignment: .leading, spacing: 14) {
                Image(systemName: "bolt.fill").font(.system(size: 36)).foregroundStyle(Color.accentColor)
                Text("Welcome to KeyForge").font(.title2.bold())
                Text("KeyForge lets you bind global keyboard shortcuts to powerful actions: launch apps, type text snippets, run shell commands, control media, and chain everything into sequences.")
                    .foregroundStyle(.secondary)
                Text("Let's get you set up in three quick steps.").foregroundStyle(.secondary)
            }
        case 1:
            VStack(alignment: .leading, spacing: 14) {
                Image(systemName: "lock.shield").font(.system(size: 36)).foregroundStyle(Color.accentColor)
                Text("Accessibility Permission").font(.title2.bold())
                Text("KeyForge needs Accessibility permission to intercept keyboard shortcuts system-wide. This is required for the global hotkey engine to work.")
                    .foregroundStyle(.secondary)
                HStack {
                    Image(systemName: ax.isTrusted ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(ax.isTrusted ? .green : .secondary)
                    Text(ax.isTrusted ? "Granted" : "Not granted")
                }
                if !ax.isTrusted {
                    Text("Click 'Request' to prompt the system, or open System Settings → Privacy & Security → Accessibility and toggle KeyForge on.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
        case 2:
            VStack(alignment: .leading, spacing: 14) {
                Image(systemName: "command").font(.system(size: 36)).foregroundStyle(Color.accentColor)
                Text("Create Your First Macro").font(.title2.bold())
                Text("We'll seed a sample macro for you: pressing ⌘⌥⇧K will post a notification saying 'KeyForge is working'. Press the hotkey after onboarding to test.")
                    .foregroundStyle(.secondary)
                if let m = store.macros.first(where: { $0.name == "KeyForge Is Working" }) {
                    Label("Sample macro created: \(m.hotkey?.displayString ?? "")", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                } else {
                    Text("(will be seeded when you click 'Create')").font(.caption).foregroundStyle(.tertiary)
                }
            }
        default:
            VStack(alignment: .leading, spacing: 14) {
                Image(systemName: "sparkles").font(.system(size: 36)).foregroundStyle(Color.accentColor)
                Text("You're all set").font(.title2.bold())
                Text("KeyForge lives in your menu bar. Click the bolt icon to open the editor any time.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var primaryButton: some View {
        switch step {
        case 0:
            Button("Continue") { step = 1 }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
        case 1:
            if ax.isTrusted {
                Button("Continue") { step = 2 }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
            } else {
                HStack {
                    Button("Open Settings") {
                        ax.openSystemSettings()
                    }
                    Button("Request") {
                        ax.requestTrust()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        case 2:
            Button("Create & Finish") {
                seedSampleMacro()
                onComplete()
            }
            .keyboardShortcut(.defaultAction)
            .buttonStyle(.borderedProminent)
        default:
            Button("Done") { onComplete() }
                .buttonStyle(.borderedProminent)
        }
    }

    private func seedSampleMacro() {
        // ⌘⌥⇧K — keyCode 40 with cmd+opt+shift modifiers.
        let mods = CGEventFlags.maskCommand.rawValue |
                   CGEventFlags.maskAlternate.rawValue |
                   CGEventFlags.maskShift.rawValue
        let hk = Hotkey(keyCode: 40, modifiers: mods)
        let macro = Macro(
            name: "KeyForge Is Working",
            icon: "checkmark.circle.fill",
            hotkey: hk,
            actions: [.notification(id: UUID(), title: "KeyForge", body: "KeyForge is working ✨")],
            isEnabled: true,
            triggerMode: .hotkey
        )
        if !store.macros.contains(where: { $0.name == macro.name }) {
            store.add(macro)
        }
    }
}
