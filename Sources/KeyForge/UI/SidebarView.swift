import SwiftUI

public enum SidebarSelection: Hashable {
    case allMacros
    case ungrouped
    case group(UUID)
    case allHotkeys
}

public struct SidebarView: View {
    @ObservedObject var store: MacroStore
    @Binding var selection: SidebarSelection
    @State private var newGroupName: String = ""
    @State private var showNewGroup: Bool = false

    public init(store: MacroStore, selection: Binding<SidebarSelection>) {
        self.store = store
        self._selection = selection
    }

    public var body: some View {
        VStack(spacing: 0) {
            List(selection: $selection) {
                Section("Library") {
                    HStack {
                        Image(systemName: "tray.full")
                        Text("All Macros")
                        Spacer()
                        Text("\(store.macros.count)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .tag(SidebarSelection.allMacros)
                    HStack {
                        Image(systemName: "tray")
                        Text("Ungrouped")
                        Spacer()
                        Text("\(store.macros.filter { $0.groupID == nil }.count)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .tag(SidebarSelection.ungrouped)
                }
                Section("Groups") {
                    ForEach(store.groups.sorted(by: { $0.sortOrder < $1.sortOrder })) { group in
                        groupRow(group)
                            .tag(SidebarSelection.group(group.id))
                            .contextMenu {
                                Button("Rename") {}
                                Button("Delete", role: .destructive) {
                                    store.deleteGroup(group.id)
                                }
                            }
                    }
                }
                Section("Reference") {
                    HStack {
                        Image(systemName: "list.bullet.rectangle")
                        Text("All Hotkeys")
                        Spacer()
                    }
                    .tag(SidebarSelection.allHotkeys)
                }
            }
            .listStyle(.sidebar)
            Divider()
            HStack {
                Button {
                    showNewGroup = true
                } label: {
                    Label("New Group", systemImage: "folder.badge.plus")
                }
                .buttonStyle(.borderless)
                Spacer()
            }
            .padding(8)
        }
        .sheet(isPresented: $showNewGroup) {
            newGroupSheet
        }
    }

    @ViewBuilder
    private func groupRow(_ group: MacroGroup) -> some View {
        HStack(spacing: 4) {
            Image(systemName: group.icon)
                .foregroundStyle(group.isEnabled ? Color.accentColor : Color.secondary)
            Text(group.name)
                .foregroundStyle(group.isEnabled ? .primary : .secondary)
            Spacer()
            Toggle("", isOn: Binding(
                get: { group.isEnabled },
                set: { newValue in
                    var g = group
                    g.isEnabled = newValue
                    store.updateGroup(g)
                }
            ))
            .labelsHidden()
            .controlSize(.mini)
        }
    }

    @ViewBuilder
    private var newGroupSheet: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("New Group").font(.headline)
            TextField("Group name", text: $newGroupName)
                .textFieldStyle(.roundedBorder)
                .frame(width: 240)
            HStack {
                Spacer()
                Button("Cancel") {
                    newGroupName = ""
                    showNewGroup = false
                }
                Button("Create") {
                    let trimmed = newGroupName.trimmingCharacters(in: .whitespaces)
                    if !trimmed.isEmpty {
                        store.addGroup(MacroGroup(name: trimmed))
                    }
                    newGroupName = ""
                    showNewGroup = false
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
    }
}
