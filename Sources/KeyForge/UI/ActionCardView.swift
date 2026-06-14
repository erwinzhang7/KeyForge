import SwiftUI
import AppKit

/// Editor card for a single MacroAction. Type picker + type-specific fields.
public struct ActionCardView: View {
    @Binding var action: MacroAction
    let onDelete: () -> Void
    let onMoveUp: () -> Void
    let onMoveDown: () -> Void

    public init(action: Binding<MacroAction>,
                onDelete: @escaping () -> Void,
                onMoveUp: @escaping () -> Void,
                onMoveDown: @escaping () -> Void) {
        self._action = action
        self.onDelete = onDelete
        self.onMoveUp = onMoveUp
        self.onMoveDown = onMoveDown
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: action.sfSymbol)
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 18)
                Picker("", selection: typeBinding) {
                    ForEach(ActionType.allCases, id: \.self) { t in
                        Text(t.label).tag(t)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                Spacer()
                Button(action: onMoveUp) { Image(systemName: "arrow.up") }
                    .buttonStyle(.borderless)
                    .help("Move up")
                Button(action: onMoveDown) { Image(systemName: "arrow.down") }
                    .buttonStyle(.borderless)
                    .help("Move down")
                Button(action: onDelete) { Image(systemName: "trash") }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.red)
                    .help("Delete")
            }
            Divider()
            fields
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(NSColor.controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color(NSColor.separatorColor), lineWidth: 1)
        )
    }

    // MARK: - Type picker binding (rewrites action on change preserving id)

    private var typeBinding: Binding<ActionType> {
        Binding(
            get: { ActionType(of: action) },
            set: { newType in
                let id = action.id
                action = newType.defaultAction(id: id)
            }
        )
    }

    // MARK: - Per-type fields

    @ViewBuilder
    private var fields: some View {
        switch action {
        case .launchApp(let id, let bundleID):
            BundleIDField(label: "Bundle ID", value: bundleID) { newValue in
                action = .launchApp(id: id, bundleID: newValue)
            }
        case .focusApp(let id, let bundleID):
            BundleIDField(label: "Bundle ID", value: bundleID) { newValue in
                action = .focusApp(id: id, bundleID: newValue)
            }
        case .openURL(let id, let url):
            LabeledField(label: "URL", placeholder: "https://example.com", value: url) { v in
                action = .openURL(id: id, url: v)
            }
        case .typeText(let id, let text, let useClipboard):
            VStack(alignment: .leading, spacing: 6) {
                Text("Text").font(.caption).foregroundStyle(.secondary)
                TextEditor(text: Binding(
                    get: { text },
                    set: { action = .typeText(id: id, text: $0, useClipboard: useClipboard) }
                ))
                .frame(minHeight: 50, maxHeight: 120)
                .font(.system(size: 12, design: .monospaced))
                .padding(4)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color(NSColor.textBackgroundColor))
                )
                Toggle("Paste via clipboard (faster, recommended)", isOn: Binding(
                    get: { useClipboard },
                    set: { action = .typeText(id: id, text: text, useClipboard: $0) }
                ))
            }
        case .shellCommand(let id, let cmd, let wait):
            VStack(alignment: .leading, spacing: 6) {
                Text("Command (run with /bin/zsh -c)").font(.caption).foregroundStyle(.secondary)
                TextEditor(text: Binding(
                    get: { cmd },
                    set: { action = .shellCommand(id: id, command: $0, waitForExit: wait) }
                ))
                .frame(minHeight: 40, maxHeight: 100)
                .font(.system(size: 12, design: .monospaced))
                .padding(4)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color(NSColor.textBackgroundColor))
                )
                Toggle("Wait for exit", isOn: Binding(
                    get: { wait },
                    set: { action = .shellCommand(id: id, command: cmd, waitForExit: $0) }
                ))
            }
        case .appleScript(let id, let source):
            VStack(alignment: .leading, spacing: 6) {
                Text("AppleScript source").font(.caption).foregroundStyle(.secondary)
                TextEditor(text: Binding(
                    get: { source },
                    set: { action = .appleScript(id: id, source: $0) }
                ))
                .frame(minHeight: 60, maxHeight: 160)
                .font(.system(size: 12, design: .monospaced))
                .padding(4)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color(NSColor.textBackgroundColor))
                )
            }
        case .delay(let id, let ms):
            HStack {
                Text("Delay")
                TextField("ms", value: Binding(
                    get: { ms },
                    set: { action = .delay(id: id, milliseconds: max(0, $0)) }
                ), format: .number)
                .frame(width: 80)
                Text("ms")
            }
        case .keyPress(let id, let keyCode, let modifiers):
            VStack(alignment: .leading, spacing: 6) {
                Text("Synthesize keystroke").font(.caption).foregroundStyle(.secondary)
                KeyRecorderView(hotkey: Binding(
                    get: { Hotkey(keyCode: keyCode, modifiers: modifiers) },
                    set: { hk in
                        if let hk = hk {
                            action = .keyPress(id: id, keyCode: hk.keyCode, modifiers: hk.modifiers)
                        }
                    }
                ))
                .frame(width: 200, height: 30)
            }
        case .mediaControl(let id, let act):
            Picker("Media", selection: Binding(
                get: { act },
                set: { action = .mediaControl(id: id, action: $0) }
            )) {
                ForEach(MediaAction.allCases, id: \.self) { a in
                    Text(a.label).tag(a)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .frame(maxWidth: 200, alignment: .leading)
        case .openFile(let id, let path):
            HStack {
                TextField("Path", text: Binding(
                    get: { path },
                    set: { action = .openFile(id: id, path: $0) }
                ))
                Button("Browse…") {
                    let panel = NSOpenPanel()
                    panel.canChooseFiles = true
                    panel.canChooseDirectories = true
                    if panel.runModal() == .OK, let url = panel.url {
                        action = .openFile(id: id, path: url.path)
                    }
                }
            }
        case .notification(let id, let title, let body):
            VStack(alignment: .leading, spacing: 6) {
                TextField("Title", text: Binding(
                    get: { title },
                    set: { action = .notification(id: id, title: $0, body: body) }
                ))
                TextField("Body", text: Binding(
                    get: { body },
                    set: { action = .notification(id: id, title: title, body: $0) }
                ))
            }
        case .ifCondition(let id, let condition, let thenActions, let elseActions):
            IfConditionFields(id: id, condition: condition, thenActions: thenActions, elseActions: elseActions) { new in
                action = new
            }
        }
    }
}

private struct LabeledField: View {
    let label: String
    let placeholder: String
    let value: String
    let onChange: (String) -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            TextField(placeholder, text: Binding(get: { value }, set: { onChange($0) }))
        }
    }
}

private struct BundleIDField: View {
    let label: String
    let value: String
    let onChange: (String) -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label).font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Pick app…") {
                    let panel = NSOpenPanel()
                    panel.allowedContentTypes = [.application]
                    panel.directoryURL = URL(fileURLWithPath: "/Applications")
                    if panel.runModal() == .OK, let url = panel.url,
                       let bundle = Bundle(url: url),
                       let bid = bundle.bundleIdentifier {
                        onChange(bid)
                    }
                }
                .controlSize(.small)
            }
            TextField("com.example.app", text: Binding(get: { value }, set: { onChange($0) }))
                .font(.system(size: 12, design: .monospaced))
        }
    }
}

private struct IfConditionFields: View {
    let id: UUID
    var condition: ConditionCheck
    var thenActions: [MacroAction]
    var elseActions: [MacroAction]
    let onUpdate: (MacroAction) -> Void

    enum ConditionType: String, CaseIterable, Identifiable {
        case alwaysTrue, alwaysFalse, frontmostApp, timeOfDay, wifiConnected, fileExists
        var id: String { rawValue }
        var label: String {
            switch self {
            case .alwaysTrue: return "Always true"
            case .alwaysFalse: return "Always false"
            case .frontmostApp: return "Frontmost app"
            case .timeOfDay: return "Time of day"
            case .wifiConnected: return "WiFi SSID"
            case .fileExists: return "File exists"
            }
        }
    }

    private var conditionType: ConditionType {
        switch condition {
        case .alwaysTrue: return .alwaysTrue
        case .alwaysFalse: return .alwaysFalse
        case .frontmostApp: return .frontmostApp
        case .timeOfDay: return .timeOfDay
        case .wifiConnected: return .wifiConnected
        case .fileExists: return .fileExists
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("Condition", selection: Binding(
                get: { conditionType },
                set: { type in
                    let newCondition: ConditionCheck = {
                        switch type {
                        case .alwaysTrue: return .alwaysTrue
                        case .alwaysFalse: return .alwaysFalse
                        case .frontmostApp: return .frontmostApp(bundleID: "")
                        case .timeOfDay: return .timeOfDay(startHour: 9, endHour: 17)
                        case .wifiConnected: return .wifiConnected(ssid: "")
                        case .fileExists: return .fileExists(path: "")
                        }
                    }()
                    onUpdate(.ifCondition(id: id, condition: newCondition, thenActions: thenActions, elseActions: elseActions))
                }
            )) {
                ForEach(ConditionType.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.menu)
            switch condition {
            case .frontmostApp(let b):
                TextField("Bundle ID", text: Binding(
                    get: { b },
                    set: { onUpdate(.ifCondition(id: id, condition: .frontmostApp(bundleID: $0), thenActions: thenActions, elseActions: elseActions)) }
                ))
            case .timeOfDay(let s, let e):
                HStack {
                    Text("Start hour:")
                    TextField("", value: Binding(
                        get: { s },
                        set: { onUpdate(.ifCondition(id: id, condition: .timeOfDay(startHour: $0, endHour: e), thenActions: thenActions, elseActions: elseActions)) }
                    ), format: .number).frame(width: 50)
                    Text("End hour:")
                    TextField("", value: Binding(
                        get: { e },
                        set: { onUpdate(.ifCondition(id: id, condition: .timeOfDay(startHour: s, endHour: $0), thenActions: thenActions, elseActions: elseActions)) }
                    ), format: .number).frame(width: 50)
                }
            case .wifiConnected(let s):
                TextField("SSID", text: Binding(
                    get: { s },
                    set: { onUpdate(.ifCondition(id: id, condition: .wifiConnected(ssid: $0), thenActions: thenActions, elseActions: elseActions)) }
                ))
            case .fileExists(let p):
                TextField("Path", text: Binding(
                    get: { p },
                    set: { onUpdate(.ifCondition(id: id, condition: .fileExists(path: $0), thenActions: thenActions, elseActions: elseActions)) }
                ))
            case .alwaysTrue, .alwaysFalse:
                EmptyView()
            }
            Text("Then: \(thenActions.count) action(s). Else: \(elseActions.count) action(s).")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text("Note: nested action editing is supported via inline cards in a future revision; for now use the API or import a .keyforge file.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }
}

// MARK: - Action type enumeration

enum ActionType: String, CaseIterable, Hashable {
    case launchApp, openURL, typeText, shellCommand, appleScript, delay, keyPress,
         mediaControl, focusApp, openFile, notification, ifCondition

    var label: String {
        switch self {
        case .launchApp: return "Launch App"
        case .openURL: return "Open URL"
        case .typeText: return "Type Text"
        case .shellCommand: return "Shell Command"
        case .appleScript: return "AppleScript"
        case .delay: return "Delay"
        case .keyPress: return "Key Press"
        case .mediaControl: return "Media Control"
        case .focusApp: return "Focus App"
        case .openFile: return "Open File"
        case .notification: return "Notification"
        case .ifCondition: return "If Condition"
        }
    }

    init(of action: MacroAction) {
        switch action {
        case .launchApp: self = .launchApp
        case .openURL: self = .openURL
        case .typeText: self = .typeText
        case .shellCommand: self = .shellCommand
        case .appleScript: self = .appleScript
        case .delay: self = .delay
        case .keyPress: self = .keyPress
        case .mediaControl: self = .mediaControl
        case .focusApp: self = .focusApp
        case .openFile: self = .openFile
        case .notification: self = .notification
        case .ifCondition: self = .ifCondition
        }
    }

    func defaultAction(id: UUID) -> MacroAction {
        switch self {
        case .launchApp:    return .launchApp(id: id, bundleID: "")
        case .openURL:      return .openURL(id: id, url: "")
        case .typeText:     return .typeText(id: id, text: "", useClipboard: true)
        case .shellCommand: return .shellCommand(id: id, command: "", waitForExit: true)
        case .appleScript:  return .appleScript(id: id, source: "")
        case .delay:        return .delay(id: id, milliseconds: 200)
        case .keyPress:     return .keyPress(id: id, keyCode: 0, modifiers: 0)
        case .mediaControl: return .mediaControl(id: id, action: .playPause)
        case .focusApp:     return .focusApp(id: id, bundleID: "")
        case .openFile:     return .openFile(id: id, path: "")
        case .notification: return .notification(id: id, title: "", body: "")
        case .ifCondition:  return .ifCondition(id: id, condition: .alwaysTrue, thenActions: [], elseActions: [])
        }
    }
}

extension MediaAction {
    var label: String {
        switch self {
        case .playPause: return "Play / Pause"
        case .next: return "Next Track"
        case .previous: return "Previous Track"
        case .volumeUp: return "Volume Up"
        case .volumeDown: return "Volume Down"
        case .mute: return "Mute"
        }
    }
}
