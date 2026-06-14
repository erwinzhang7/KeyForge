import SwiftUI

public struct SnippetsView: View {
    @ObservedObject var store: MacroStore
    @ObservedObject var settings = AppSettings.shared
    @State private var selectedID: UUID?

    public init(store: MacroStore) { self.store = store }

    public var body: some View {
        HSplitView {
            VStack(spacing: 0) {
                HStack {
                    Toggle("Snippets enabled", isOn: $settings.snippetsEnabled)
                        .controlSize(.small)
                    Spacer()
                    Button {
                        let s = Snippet(abbreviation: ";new", expansion: "")
                        store.addSnippet(s)
                        selectedID = s.id
                    } label: {
                        Label("Add", systemImage: "plus")
                    }
                    .buttonStyle(.borderless)
                }
                .padding(8)
                Divider()
                List(selection: $selectedID) {
                    ForEach(store.snippets) { snippet in
                        HStack {
                            Toggle("", isOn: Binding(
                                get: { snippet.isEnabled },
                                set: { v in
                                    var s = snippet; s.isEnabled = v; store.updateSnippet(s)
                                }
                            ))
                            .labelsHidden()
                            .controlSize(.mini)
                            Text(snippet.abbreviation)
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundStyle(.primary)
                            Spacer()
                            Text(snippet.expansion.prefix(30) + (snippet.expansion.count > 30 ? "…" : ""))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        .tag(snippet.id)
                    }
                }
                .listStyle(.inset(alternatesRowBackgrounds: true))
            }
            .frame(minWidth: 280)
            detail
                .frame(minWidth: 280)
        }
        .navigationTitle("Snippets")
    }

    @ViewBuilder
    private var detail: some View {
        if let id = selectedID,
           let idx = store.snippets.firstIndex(where: { $0.id == id }) {
            let binding = Binding<Snippet>(
                get: { store.snippets[idx] },
                set: { store.updateSnippet($0) }
            )
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Snippet").font(.headline)
                    Spacer()
                    Button("Delete", role: .destructive) {
                        store.deleteSnippet(id)
                        selectedID = nil
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.red)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("Abbreviation").font(.caption).foregroundStyle(.secondary)
                    TextField(";em", text: binding.abbreviation)
                        .font(.system(size: 13, design: .monospaced))
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("Expansion").font(.caption).foregroundStyle(.secondary)
                    TextEditor(text: binding.expansion)
                        .frame(minHeight: 100)
                        .font(.system(size: 13))
                        .padding(4)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color(NSColor.textBackgroundColor))
                        )
                }
                Spacer()
            }
            .padding(16)
        } else {
            EmptyStateView("Select a snippet", systemImage: "text.cursor")
        }
    }
}
