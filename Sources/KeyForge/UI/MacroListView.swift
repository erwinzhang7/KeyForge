import SwiftUI
import AppKit

/// Middle column: list of macros in the current group, with quick toggles.
public struct MacroListView: View {
    @ObservedObject var store: MacroStore
    @Binding var selectedMacroID: UUID?
    let selectedGroupID: UUID?  // nil = All Macros; "ungrouped" sentinel handled by host
    let isUngrouped: Bool
    @State var search: String = ""

    public init(store: MacroStore, selectedMacroID: Binding<UUID?>, selectedGroupID: UUID?, isUngrouped: Bool, search: String = "") {
        self.store = store
        self._selectedMacroID = selectedMacroID
        self.selectedGroupID = selectedGroupID
        self.isUngrouped = isUngrouped
        self._search = State(initialValue: search)
    }

    private var visible: [Macro] {
        let base: [Macro]
        if isUngrouped {
            base = store.macros.filter { $0.groupID == nil }
        } else if let g = selectedGroupID {
            base = store.macros.filter { $0.groupID == g }
        } else {
            base = store.macros
        }
        if search.isEmpty { return base }
        return base.filter { $0.name.localizedCaseInsensitiveContains(search) }
    }

    public var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search macros", text: $search)
                    .textFieldStyle(.plain)
            }
            .padding(8)
            Divider()
            List(selection: $selectedMacroID) {
                ForEach(visible) { macro in
                    row(for: macro)
                        .tag(macro.id)
                        .contextMenu {
                            Button("Duplicate") { _ = store.duplicate(macro.id) }
                            Menu("Move to Group") {
                                Button("Ungrouped") { store.move(macroID: macro.id, toGroup: nil) }
                                ForEach(store.groups) { g in
                                    Button(g.name) { store.move(macroID: macro.id, toGroup: g.id) }
                                }
                            }
                            Divider()
                            Button("Test Run") {
                                Task { await EventTapManager.shared.executor.execute(macro) }
                            }
                            Divider()
                            Button("Delete", role: .destructive) {
                                store.delete(macro.id)
                                if selectedMacroID == macro.id { selectedMacroID = nil }
                            }
                        }
                }
            }
            .listStyle(.inset(alternatesRowBackgrounds: true))
            Divider()
            HStack {
                Button {
                    let newMacro = Macro(name: "New Macro", groupID: isUngrouped ? nil : selectedGroupID)
                    store.add(newMacro)
                    selectedMacroID = newMacro.id
                } label: {
                    Label("New Macro", systemImage: "plus")
                }
                .buttonStyle(.borderless)
                Spacer()
                Text("\(visible.count) macro\(visible.count == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(8)
        }
    }

    @ViewBuilder
    private func row(for macro: Macro) -> some View {
        HStack(spacing: 8) {
            Image(systemName: macro.icon)
                .foregroundStyle(macro.isEnabled ? Color.accentColor : Color.secondary)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(macro.name)
                    .lineLimit(1)
                    .foregroundStyle(macro.isEnabled ? .primary : .secondary)
                if let hk = macro.hotkey {
                    Text(hk.displayString)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                } else {
                    Text("No hotkey").font(.caption2).foregroundStyle(.tertiary)
                }
            }
            Spacer()
            Toggle("", isOn: Binding(
                get: { macro.isEnabled },
                set: { newValue in
                    var m = macro
                    m.isEnabled = newValue
                    store.update(m)
                }
            ))
            .labelsHidden()
            .controlSize(.mini)
            Button {
                Task { await EventTapManager.shared.executor.execute(macro) }
            } label: {
                Image(systemName: "play.fill")
            }
            .buttonStyle(.borderless)
            .help("Test run")
        }
        .padding(.vertical, 2)
    }
}
