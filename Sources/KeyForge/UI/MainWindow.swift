import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// Three-column main editor: sidebar (groups) → macro list → detail panel.
public struct MainWindow: View {
    @ObservedObject var store: MacroStore
    @ObservedObject var settings = AppSettings.shared
    @ObservedObject var ax = AccessibilityHelper.shared

    @State private var selection: SidebarSelection = .allMacros
    @State private var selectedMacroID: UUID?
    @State private var showingImport = false
    @State private var showingExport = false
    @State private var exportData: Data?
    @State private var showSnippets = false
    @State private var showOnboarding = false

    public init(store: MacroStore) { self.store = store }

    public var body: some View {
        VStack(spacing: 0) {
            permissionsBanner
            NavigationSplitView {
                SidebarView(store: store, selection: $selection)
                    .frame(minWidth: 200, idealWidth: 220)
            } detail: {
                if selection == .allHotkeys {
                    AllHotkeysView(store: store) { macroID in
                        selectedMacroID = macroID
                        selection = .allMacros
                    }
                } else {
                    // Plain HStack (not HSplitView) so the two panes always size to
                    // the available width — HSplitView in a NavigationSplitView
                    // detail uses content/ideal widths and overflows the window.
                    HStack(spacing: 0) {
                        MacroListView(
                            store: store,
                            selectedMacroID: $selectedMacroID,
                            selectedGroupID: groupID,
                            isUngrouped: selection == .ungrouped
                        )
                        .frame(minWidth: 220, idealWidth: 280, maxWidth: 340)
                        Divider()
                        macroDetailPane
                            .frame(maxWidth: .infinity)
                    }
                }
            }
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    Toggle("Hotkeys", isOn: $settings.globalHotkeysEnabled)
                        .toggleStyle(.switch)
                        .help("Global enable/disable")
                    Button {
                        selection = .allHotkeys
                    } label: { Label("All Hotkeys", systemImage: "list.bullet.rectangle") }
                        .help("Browse every hotkey: KeyForge, macOS system, and built-in")
                    Button {
                        showSnippets = true
                    } label: { Label("Snippets", systemImage: "text.cursor") }
                    Button {
                        importMacros()
                    } label: { Label("Import", systemImage: "square.and.arrow.down") }
                    Button {
                        exportMacros()
                    } label: { Label("Export", systemImage: "square.and.arrow.up") }
                }
            }
        }
        .frame(minWidth: 760, minHeight: 500)
        .sheet(isPresented: $showSnippets) {
            VStack(spacing: 0) {
                HStack {
                    Text("Snippets").font(.headline)
                    Spacer()
                    Button("Done") { showSnippets = false }
                        .keyboardShortcut(.defaultAction)
                }
                .padding(12)
                Divider()
                SnippetsView(store: store)
                    .frame(minHeight: 360)
            }
            .frame(width: 640, height: 420)
        }
        .sheet(isPresented: $showOnboarding) {
            OnboardingView(store: store) {
                settings.hasCompletedOnboarding = true
                showOnboarding = false
            }
        }
        .onAppear {
            if !settings.hasCompletedOnboarding { showOnboarding = true }
        }
    }

    @ViewBuilder
    private var macroDetailPane: some View {
        if let id = selectedMacroID {
            MacroDetailView(store: store, macroID: id)
                .frame(minWidth: 300)
        } else {
            EmptyStateView("Select a macro to edit", systemImage: "bolt")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var groupID: UUID? {
        switch selection {
        case .group(let id): return id
        default: return nil
        }
    }

    // MARK: - Import / Export

    private func exportMacros() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "keyforge") ?? .json]
        panel.nameFieldStringValue = "macros.keyforge"
        if panel.runModal() == .OK, let url = panel.url {
            do {
                let data = try store.exportData()
                try data.write(to: url)
            } catch {
                Logger.shared.error("Export failed: \(error)")
            }
        }
    }

    private func importMacros() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [UTType(filenameExtension: "keyforge") ?? .json, .json]
        if panel.runModal() == .OK, let url = panel.url {
            do {
                let data = try Data(contentsOf: url)
                let added = try store.importData(data, replaceExisting: false)
                Logger.shared.info("Imported \(added) macros")
            } catch {
                Logger.shared.error("Import failed: \(error)")
            }
        }
    }

    @ViewBuilder
    private var permissionsBanner: some View {
        if !ax.isTrusted {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text("Accessibility permission is not granted. Hotkeys won't trigger until you enable it.")
                    .font(.callout)
                Spacer()
                Button("Open Settings") { ax.openSystemSettings() }
                Button("Request") { ax.requestTrust() }
            }
            .padding(8)
            .background(Color.orange.opacity(0.12))
        }
    }
}
