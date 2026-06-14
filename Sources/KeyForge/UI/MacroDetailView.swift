import SwiftUI

/// Trailing-panel editor for a single macro. Bindings are split across name, icon,
/// hotkey, trigger mode, group, and the action list.
public struct MacroDetailView: View {
    @ObservedObject var store: MacroStore
    let macroID: UUID
    @State private var showIconPicker = false
    @State private var conflict: HotkeyConflict = .noConflict

    public init(store: MacroStore, macroID: UUID) {
        self.store = store
        self.macroID = macroID
    }

    private var macroBinding: Binding<Macro>? {
        guard let idx = store.macros.firstIndex(where: { $0.id == macroID }) else { return nil }
        return Binding(
            get: { store.macros[idx] },
            set: { newValue in store.update(newValue) }
        )
    }

    public var body: some View {
        Group {
            if let macro = macroBinding {
                content(macro: macro)
            } else {
                EmptyStateView("Select a macro", systemImage: "bolt")
            }
        }
    }

    @ViewBuilder
    private func content(macro: Binding<Macro>) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header(macro: macro)
                Divider()
                hotkeySection(macro: macro)
                Divider()
                triggerSection(macro: macro)
                Divider()
                actionsSection(macro: macro)
            }
            .padding(20)
            // Pin the content to the scroll view's width so no child can push
            // the detail pane wider than the window.
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onAppear { recomputeConflict(for: macro.wrappedValue) }
        .onChange(of: macro.wrappedValue.hotkey) { _ in
            recomputeConflict(for: macro.wrappedValue)
        }
    }

    // MARK: - Sections

    @ViewBuilder
    private func header(macro: Binding<Macro>) -> some View {
        HStack(spacing: 12) {
            Button {
                showIconPicker = true
            } label: {
                Image(systemName: macro.wrappedValue.icon)
                    .font(.system(size: 26))
                    .frame(width: 50, height: 50)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color.accentColor.opacity(0.15))
                    )
                    .foregroundStyle(Color.accentColor)
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showIconPicker) {
                IconPickerView(selection: macro.icon)
            }
            VStack(alignment: .leading, spacing: 4) {
                TextField("Name", text: macro.name)
                    .textFieldStyle(.plain)
                    .font(.title2.bold())
                Toggle("Enabled", isOn: macro.isEnabled)
                    .toggleStyle(.switch)
                    .controlSize(.small)
            }
            Spacer()
            Button {
                Task { await EventTapManager.shared.executor.execute(macro.wrappedValue) }
            } label: {
                Label("Test Run", systemImage: "play.fill")
            }
            .buttonStyle(.borderedProminent)
        }
    }

    @ViewBuilder
    private func hotkeySection(macro: Binding<Macro>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Hotkey").font(.headline)
            HStack(spacing: 8) {
                KeyRecorderView(
                    hotkey: macro.hotkey,
                    conflict: conflict,
                    allowChord: macro.wrappedValue.triggerMode == .chord
                )
                .frame(width: 220, height: 30)
                if macro.wrappedValue.hotkey != nil {
                    Button {
                        var m = macro.wrappedValue
                        m.hotkey = nil
                        store.update(m)
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }
            }

            // Prominent media / hardware-key binder — these never arrive as a
            // normal keystroke, so the recorder above can capture them by press,
            // but this menu makes every option visible and pickable directly.
            HStack(spacing: 6) {
                Text("or").font(.caption).foregroundStyle(.secondary)
                Menu {
                    systemKeyMenuItems(macro: macro)
                } label: {
                    Label("Bind a media / hardware key", systemImage: "slider.horizontal.below.sun.max")
                }
                .fixedSize()
                .help("Override brightness, volume, mute, or media keys")
            }

            if macro.wrappedValue.hotkey?.isSystemDefined == true {
                Label("Overrides the macOS default for this key while KeyForge is running.",
                      systemImage: "bolt.shield")
                    .foregroundStyle(.orange)
                    .font(.caption)
            } else {
                Text("Tip: click the field and press any combo — including brightness, volume, or media keys.")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }
            switch conflict {
            case .noConflict:
                EmptyView()
            case .systemConflict(let desc):
                Label("Conflicts with system shortcut: \(desc)", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
                    .font(.caption)
            case .userConflict(let name, _):
                Label("Already used by '\(name)'", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
                    .font(.caption)
            }
        }
    }

    @ViewBuilder
    private func systemKeyMenuItems(macro: Binding<Macro>) -> some View {
        // System-defined (aux) keys.
        let sysGroups: [(String, [UInt16])] = [
            ("Brightness", [SystemKeyMap.brightnessDown, SystemKeyMap.brightnessUp]),
            ("Volume", [SystemKeyMap.soundDown, SystemKeyMap.soundUp, SystemKeyMap.mute]),
            ("Media", [SystemKeyMap.previous, SystemKeyMap.play, SystemKeyMap.next,
                       SystemKeyMap.rewind, SystemKeyMap.fast]),
            ("Keyboard Backlight", [SystemKeyMap.illuminationDown, SystemKeyMap.illuminationUp]),
        ]
        ForEach(sysGroups, id: \.0) { title, codes in
            Section(title) {
                ForEach(codes, id: \.self) { code in
                    Button {
                        bindHotkey(Hotkey(keyCode: code, modifiers: 0, keyType: .systemDefined), macro: macro)
                    } label: {
                        Label(SystemKeyMap.name(for: code), systemImage: SystemKeyMap.sfSymbol(for: code))
                    }
                }
            }
        }
        // fn-row special keys (Spotlight/F4, Dictation/F5, Focus, Emoji) — these
        // arrive as standard keycodes, so override the OS default by binding here.
        Section("Function & Search Keys") {
            ForEach([UInt16(177), 176, 178, 179], id: \.self) { code in
                Button {
                    bindHotkey(Hotkey(keyCode: code, modifiers: 0, keyType: .standard), macro: macro)
                } label: {
                    Label(KeyCodeMap.name(for: code), systemImage: "keyboard")
                }
            }
        }
    }

    private func bindHotkey(_ hotkey: Hotkey, macro: Binding<Macro>) {
        var m = macro.wrappedValue
        m.hotkey = hotkey
        m.triggerMode = .hotkey
        store.update(m)
    }

    @ViewBuilder
    private func triggerSection(macro: Binding<Macro>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Trigger").font(.headline)
            // Short labels so the segmented control never forces the detail pane
            // wider than the window (segmented controls don't truncate).
            Picker("Trigger mode", selection: macro.triggerMode) {
                Text("Hotkey").tag(TriggerMode.hotkey)
                Text("Chord").tag(TriggerMode.chord)
                Text("Manual").tag(TriggerMode.manual)
            }
            .pickerStyle(.segmented)
            .help("Hotkey: single press · Chord: two-key sequence · Manual: only triggered manually")
        }
    }

    @ViewBuilder
    private func actionsSection(macro: Binding<Macro>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Actions").font(.headline)
                Spacer()
                Menu {
                    ForEach(ActionType.allCases, id: \.self) { t in
                        Button(t.label) {
                            var m = macro.wrappedValue
                            m.actions.append(t.defaultAction(id: UUID()))
                            store.update(m)
                        }
                    }
                } label: {
                    Label("Add Action", systemImage: "plus")
                }
            }
            if macro.wrappedValue.actions.isEmpty {
                Text("No actions yet. Add one to make this macro do something.")
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 12)
            }
            VStack(spacing: 8) {
                ForEach(macro.wrappedValue.actions.indices, id: \.self) { idx in
                    actionCard(macro: macro, index: idx)
                }
            }
        }
    }

    @ViewBuilder
    private func actionCard(macro: Binding<Macro>, index: Int) -> some View {
        let binding = Binding<MacroAction>(
            get: { macro.wrappedValue.actions[index] },
            set: { newValue in
                var m = macro.wrappedValue
                m.actions[index] = newValue
                store.update(m)
            }
        )
        ActionCardView(
            action: binding,
            onDelete: {
                var m = macro.wrappedValue
                m.actions.remove(at: index)
                store.update(m)
            },
            onMoveUp: {
                guard index > 0 else { return }
                var m = macro.wrappedValue
                m.actions.swapAt(index, index - 1)
                store.update(m)
            },
            onMoveDown: {
                guard index < macro.wrappedValue.actions.count - 1 else { return }
                var m = macro.wrappedValue
                m.actions.swapAt(index, index + 1)
                store.update(m)
            }
        )
    }

    private func recomputeConflict(for macro: Macro) {
        guard let hk = macro.hotkey else {
            conflict = .noConflict
            return
        }
        conflict = ConflictDetector.check(
            candidate: hk,
            against: store.macros,
            excludeMacroID: macro.id,
            strict: AppSettings.shared.conflictDetectionStrict
        )
    }
}
