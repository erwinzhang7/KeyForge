import SwiftUI
import AppKit

/// A single unified row in the "All Hotkeys" inventory, regardless of origin.
struct HotkeyRow: Identifiable, Hashable {
    enum Source: String, CaseIterable, Hashable {
        case keyforge = "KeyForge"
        case system   = "macOS"
        case hardware = "Hardware"
        case builtin  = "Built-in"
        case snippet  = "Snippets"

        var symbol: String {
            switch self {
            case .keyforge: return "bolt.fill"
            case .system:   return "apple.logo"
            case .hardware: return "keyboard"
            case .builtin:  return "command"
            case .snippet:  return "text.cursor"
            }
        }

        var tint: Color {
            switch self {
            case .keyforge: return .orange
            case .system:   return .blue
            case .hardware: return .teal
            case .builtin:  return .gray
            case .snippet:  return .purple
            }
        }
    }

    let id: String
    let combo: String
    let title: String
    let source: Source
    let isEnabled: Bool
    /// The originating macro, for KeyForge rows — enables click-to-jump.
    let macroID: UUID?
    /// Precomputed, lowercased search haystack — includes spelled-out modifier
    /// names ("command"/"cmd", "control"/"ctrl", …) so typing words matches the
    /// glyph combos.
    let searchText: String

    init(id: String, combo: String, title: String, source: Source, isEnabled: Bool, macroID: UUID? = nil) {
        self.id = id
        self.combo = combo
        self.title = title
        self.source = source
        self.isEnabled = isEnabled
        self.macroID = macroID
        self.searchText = Self.buildSearchText(combo: combo, title: title, source: source)
    }

    /// Order-independent canonical form of a glyph combo, for cross-source
    /// conflict matching. nil for empty combos. Snippet abbreviations are never
    /// passed here.
    var normalizedComboKey: String? {
        guard !combo.isEmpty else { return nil }
        let glyphs = ["⌃", "⌥", "⇧", "⌘"]
        var key = combo
        for g in glyphs { key = key.replacingOccurrences(of: g, with: "") }
        // Drop the fn "layer" flag entirely — the same physical key may report
        // fn set or not depending on keyboard settings, so it must not affect
        // matching (e.g. "fn Spotlight" and "Spotlight" are the same key).
        key = key.replacingOccurrences(of: "fn ", with: "").replacingOccurrences(of: "fn", with: "")
        key = key.trimmingCharacters(in: .whitespaces).lowercased()
        let mods = glyphs.filter { combo.contains($0) }.joined()
        return "\(mods)\(key)"
    }

    private static func buildSearchText(combo: String, title: String, source: Source) -> String {
        var aliases = ""
        if combo.contains("⌘") { aliases += " command cmd ⌘" }
        if combo.contains("⌃") { aliases += " control ctrl ⌃" }
        if combo.contains("⌥") { aliases += " option alt opt ⌥" }
        if combo.contains("⇧") { aliases += " shift ⇧" }
        if combo.lowercased().contains("fn") { aliases += " fn function" }
        return "\(combo) \(title) \(source.rawValue)\(aliases)".lowercased()
    }

    /// Split a combo display string into individual keycap tokens for chip rendering.
    var keycaps: [String] {
        guard !combo.isEmpty else { return [] }
        var caps: [String] = []
        var rest = Substring(combo)
        if rest.hasPrefix("fn ") { caps.append("fn"); rest = rest.dropFirst(3) }
        let mods: Set<Character> = ["⌃", "⌥", "⇧", "⌘"]
        while let first = rest.first, mods.contains(first) {
            caps.append(String(first))
            rest = rest.dropFirst()
        }
        let key = rest.trimmingCharacters(in: .whitespaces)
        if !key.isEmpty { caps.append(key) }
        return caps
    }
}

/// Browse *every* hotkey the machine knows about: your KeyForge macros, the
/// macOS system shortcuts (read live from com.apple.symbolichotkeys), the
/// always-on built-in editing combos, and your text snippets. Searchable
/// (including by spelled-out modifier names) and filterable by source.
public struct AllHotkeysView: View {
    @ObservedObject var store: MacroStore
    @State private var query: String = ""
    @State private var sourceFilter: HotkeyRow.Source? = nil
    @State private var conflictsOnly: Bool = false
    @State private var systemRecords: [SystemHotkeyRecord] = []
    @State private var hoveredID: String? = nil
    // Press-to-search: capture a real key combo (incl. media keys) and filter to it.
    @State private var isRecordingSearch = false
    @State private var recordedComboKey: String? = nil
    @State private var recordedComboDisplay: String? = nil

    /// Called when the user clicks a KeyForge row — host jumps to that macro.
    var onSelectMacro: (UUID) -> Void

    public init(store: MacroStore, onSelectMacro: @escaping (UUID) -> Void = { _ in }) {
        self.store = store
        self.onSelectMacro = onSelectMacro
    }

    public var body: some View {
        VStack(spacing: 0) {
            searchBar
            filterBar
            Divider()
            content
            Divider()
            footer
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear(perform: reloadSystem)
        .onDisappear { stopSearchRecording() }
    }

    // MARK: - Search

    private var searchBar: some View {
        // The TextField is ALWAYS mounted (never swapped out of an if/else) so it
        // keeps a stable identity and can reliably hold keyboard focus. Recording
        // state and the captured-combo chip render as an overlay on top of it.
        let overlayActive = isRecordingSearch || recordedComboDisplay != nil
        return HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)

            ZStack(alignment: .leading) {
                TextField("Search by action or modifier name (try \"cmd shift\")", text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .opacity(overlayActive ? 0 : 1)
                    .disabled(overlayActive)

                if let disp = recordedComboDisplay {
                    HStack(spacing: 4) {
                        Text(disp)
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                        Button { clearRecordedCombo() } label: {
                            Image(systemName: "xmark.circle.fill")
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 7).padding(.vertical, 2)
                    .background(Capsule().fill(Color.accentColor.opacity(0.18)))
                    .foregroundStyle(Color.accentColor)
                } else if isRecordingSearch {
                    Text("Press a shortcut or media key…  (Esc to cancel)")
                        .font(.system(size: 13))
                        .foregroundStyle(.orange)
                }
            }

            if !overlayActive && !query.isEmpty {
                Button { query = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            // Press-to-search toggle.
            Button {
                if isRecordingSearch { stopSearchRecording() } else { startSearchRecording() }
            } label: {
                Image(systemName: "keyboard")
                    .foregroundStyle(isRecordingSearch ? Color.orange : .secondary)
            }
            .buttonStyle(.plain)
            .help(EventTapManager.shared.isRunning
                  ? "Search by pressing a shortcut (incl. brightness/volume/media keys)"
                  : "Press-to-search needs Accessibility permission")
            .disabled(!EventTapManager.shared.isRunning)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(nsColor: .controlBackgroundColor))
                .overlay(RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(isRecordingSearch ? Color.orange : Color(nsColor: .separatorColor)))
        )
        .padding(.horizontal, 14)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }

    // MARK: - Press-to-search

    private func startSearchRecording() {
        guard EventTapManager.shared.isRunning else { return }
        query = ""
        recordedComboKey = nil
        recordedComboDisplay = nil
        isRecordingSearch = true
        EventTapManager.shared.captureHook = { captured in
            DispatchQueue.main.async { handleSearchCapture(captured) }
        }
    }

    private func stopSearchRecording() {
        if isRecordingSearch {
            EventTapManager.shared.captureHook = nil
            isRecordingSearch = false
        }
    }

    private func handleSearchCapture(_ captured: EventTapManager.CapturedKey) {
        guard isRecordingSearch else { return }
        // Escape cancels without setting a filter.
        if captured.keyType == .standard, captured.keyCode == 53,
           (captured.modifiers & Hotkey.modifierMask) == 0 {
            stopSearchRecording()
            return
        }
        let hk = Hotkey(keyCode: captured.keyCode, modifiers: captured.modifiers, keyType: captured.keyType)
        recordedComboDisplay = hk.displayString
        recordedComboKey = HotkeyRow(id: "q", combo: hk.displayString, title: "",
                                     source: .system, isEnabled: true).normalizedComboKey
        stopSearchRecording()
    }

    private func clearRecordedCombo() {
        recordedComboKey = nil
        recordedComboDisplay = nil
    }

    private var filterBar: some View {
        let conflictCount = conflictMap.count
        return HStack(spacing: 6) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    filterPill(label: "All", source: nil, count: allRows.count)
                    ForEach(HotkeyRow.Source.allCases, id: \.self) { src in
                        filterPill(label: src.rawValue, source: src, count: count(of: src))
                    }
                    if conflictCount > 0 {
                        conflictPill(count: conflictCount)
                    }
                }
            }
            Button {
                reloadSystem()
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .help("Reload macOS system shortcuts")
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 8)
    }

    private func conflictPill(count: Int) -> some View {
        Button {
            conflictsOnly.toggle()
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 10))
                Text("Conflicts").font(.system(size: 12, weight: .medium))
                Text("\(count)")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(conflictsOnly ? Color.white.opacity(0.85) : Color.orange)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(Capsule().fill(conflictsOnly ? Color.orange : Color.orange.opacity(0.12)))
            .overlay(Capsule().strokeBorder(conflictsOnly ? Color.clear : Color.orange.opacity(0.4)))
            .foregroundStyle(conflictsOnly ? Color.white : Color.orange)
        }
        .buttonStyle(.plain)
        .help("Show only hotkeys that collide across KeyForge / macOS / built-in")
    }

    private func filterPill(label: String, source: HotkeyRow.Source?, count: Int) -> some View {
        let isSelected = sourceFilter == source
        return Button {
            sourceFilter = source
        } label: {
            HStack(spacing: 5) {
                if let source { Image(systemName: source.symbol).font(.system(size: 10)) }
                Text(label).font(.system(size: 12, weight: .medium))
                Text("\(count)")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(isSelected ? Color.white.opacity(0.85) : .secondary)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(
                Capsule().fill(isSelected ? Color.accentColor : Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                Capsule().strokeBorder(isSelected ? Color.clear : Color(nsColor: .separatorColor))
            )
            .foregroundStyle(isSelected ? Color.white : Color.primary)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if filteredRows.isEmpty {
            if let disp = recordedComboDisplay {
                // Pressed a key that resolves to nothing bound — still tell the
                // user what the key is, so a press always produces a result.
                unboundKeyResult(disp)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                EmptyStateView("No hotkeys match", systemImage: "magnifyingglass")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        } else {
            let conflicts = conflictMap
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                    ForEach(visibleSources, id: \.self) { source in
                        let rows = filteredRows.filter { $0.source == source }
                        if !rows.isEmpty {
                            Section {
                                ForEach(rows) { row in
                                    rowView(row, conflict: conflicts[row.id])
                                    Divider().padding(.leading, 14)
                                }
                            } header: {
                                sectionHeader(source, count: rows.count)
                            }
                        }
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }

    private func unboundKeyResult(_ disp: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: "keyboard")
                .font(.system(size: 30))
                .foregroundStyle(.secondary)
            Text(disp)
                .font(.system(size: 18, weight: .semibold, design: .rounded))
            Text("This key isn't bound to a KeyForge macro, a macOS shortcut, or a built-in command.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
        }
        .padding()
    }

    private func sectionHeader(_ source: HotkeyRow.Source, count: Int) -> some View {
        HStack(spacing: 6) {
            Image(systemName: source.symbol)
                .font(.system(size: 11))
                .foregroundStyle(source.tint)
            Text(source.rawValue.uppercased())
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.secondary)
            Text("\(count)")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial)
    }

    private func rowView(_ row: HotkeyRow, conflict: String?) -> some View {
        let isClickable = row.macroID != nil
        let isHovered = hoveredID == row.id
        return HStack(spacing: 12) {
            comboView(row)
                .frame(width: 150, alignment: .leading)
            if conflict != nil {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(.orange)
                    .help(conflict ?? "")
            }
            Text(row.title)
                .font(.system(size: 13))
                .lineLimit(1)
                .truncationMode(.tail)
                .foregroundStyle(conflict != nil ? Color.orange : (row.isEnabled ? .primary : .secondary))
            Spacer(minLength: 8)
            if !row.isEnabled {
                Text("OFF")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 5).padding(.vertical, 2)
                    .background(Capsule().fill(Color.secondary.opacity(0.15)))
            }
            if isClickable && isHovered {
                Image(systemName: "arrow.right.circle")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .background(isHovered ? Color.accentColor.opacity(0.08) : Color.clear)
        .contentShape(Rectangle())
        .onHover { inside in
            hoveredID = inside ? row.id : (hoveredID == row.id ? nil : hoveredID)
            if isClickable {
                if inside { NSCursor.pointingHand.push() } else { NSCursor.pop() }
            }
        }
        .onTapGesture {
            if let id = row.macroID { onSelectMacro(id) }
        }
    }

    @ViewBuilder
    private func comboView(_ row: HotkeyRow) -> some View {
        let caps = row.keycaps
        if caps.isEmpty {
            Text("—").foregroundStyle(.tertiary).font(.system(size: 13))
        } else {
            HStack(spacing: 3) {
                ForEach(Array(caps.enumerated()), id: \.offset) { _, cap in
                    Text(cap)
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(row.isEnabled ? .primary : .secondary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color(nsColor: .controlBackgroundColor))
                                .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Color(nsColor: .separatorColor)))
                        )
                }
            }
        }
    }

    private var footer: some View {
        HStack {
            Text(summary).font(.caption).foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    private var summary: String {
        "\(filteredRows.count) of \(allRows.count) shown"
    }

    // MARK: - Data

    private func reloadSystem() {
        systemRecords = SystemHotkeyInventory.load()
    }

    private func count(of source: HotkeyRow.Source) -> Int {
        allRows.lazy.filter { $0.source == source }.count
    }

    private var visibleSources: [HotkeyRow.Source] {
        if let f = sourceFilter { return [f] }
        return HotkeyRow.Source.allCases
    }

    private var allRows: [HotkeyRow] {
        var rows: [HotkeyRow] = []

        // KeyForge macros (those with a hotkey bound).
        let groupEnabled = Dictionary(uniqueKeysWithValues: store.groups.map { ($0.id, $0.isEnabled) })
        for m in store.macros {
            guard let hk = m.hotkey else { continue }
            let groupOn = m.groupID.map { groupEnabled[$0] ?? true } ?? true
            rows.append(HotkeyRow(
                id: "kf-\(m.id.uuidString)",
                combo: hk.displayString,
                title: m.name,
                source: .keyforge,
                isEnabled: m.isEnabled && groupOn,
                macroID: m.id
            ))
        }

        // macOS system shortcuts (live from the OS). Track their normalized
        // combos so the curated built-in list below doesn't duplicate them.
        var systemKeys = Set<String>()
        for r in systemRecords {
            let row = HotkeyRow(
                id: "sys-\(r.id)",
                combo: r.combo,
                title: r.name,
                source: .system,
                isEnabled: r.isEnabled
            )
            if let k = row.normalizedComboKey { systemKeys.insert(k) }
            rows.append(row)
        }

        // Always-on built-in editing/window combos. Skip any the live macOS list
        // already covers (e.g. ⌘⇧3, ⌘Space) so each shortcut appears exactly once;
        // the editing combos (⌘C/⌘V/…) that aren't in symbolichotkeys remain.
        for e in SystemShortcuts.entries {
            let hk = Hotkey(keyCode: e.keyCode, modifiers: e.modifiers)
            let row = HotkeyRow(
                id: "builtin-\(e.keyCode)-\(e.modifiers)",
                combo: hk.displayString,
                title: e.description,
                source: .builtin,
                isEnabled: true
            )
            if let k = row.normalizedComboKey, systemKeys.contains(k) { continue }
            rows.append(row)
        }

        // Hardware / media keys — brightness, volume, media, fn-row specials.
        // Skip ones already represented by a live macOS shortcut to avoid dupes.
        for hk in HardwareKeyCatalog.all {
            let combo = hk.hotkey.displayString
            let id = "hw-\(hk.hotkey.keyType.rawValue)-\(hk.hotkey.keyCode)"
            rows.append(HotkeyRow(
                id: id,
                combo: combo,
                title: hk.action,
                source: .hardware,
                isEnabled: true
            ))
        }

        // Text snippets (abbreviation triggers).
        for s in store.snippets {
            rows.append(HotkeyRow(
                id: "snip-\(s.id.uuidString)",
                combo: s.abbreviation,
                title: s.expansion.replacingOccurrences(of: "\n", with: " "),
                source: .snippet,
                isEnabled: s.isEnabled
            ))
        }

        return rows
    }

    private var filteredRows: [HotkeyRow] {
        // AND across whitespace-separated tokens so "cmd shift" narrows results.
        let tokens = query.lowercased().split(separator: " ").map(String.init)
        let conflicts = conflictMap
        return allRows.filter { row in
            if conflictsOnly && conflicts[row.id] == nil { return false }
            if let f = sourceFilter, row.source != f { return false }
            // Press-to-search: exact combo match (order-independent).
            if let rk = recordedComboKey, row.normalizedComboKey != rk { return false }
            if tokens.isEmpty { return true }
            return tokens.allSatisfy { row.searchText.contains($0) }
        }
    }

    /// row.id -> short reason, for every row whose combo collides across sources
    /// (a KeyForge binding shadowed by — or shadowing — a macOS/built-in
    /// shortcut), plus KeyForge-internal duplicates. Snippets are excluded.
    private var conflictMap: [String: String] {
        var byKey: [String: [HotkeyRow]] = [:]
        for row in allRows where row.source != .snippet {
            guard let k = row.normalizedComboKey else { continue }
            byKey[k, default: []].append(row)
        }
        var reasons: [String: String] = [:]
        for (_, group) in byKey where group.count > 1 {
            let kfCount = group.filter { $0.source == .keyforge }.count
            let hasOther = group.contains { $0.source == .system || $0.source == .builtin }
            // Only surface conflicts that involve a KeyForge macro.
            guard kfCount > 0, hasOther || kfCount > 1 else { continue }
            for row in group {
                if let other = group.first(where: { $0.id != row.id }) {
                    reasons[row.id] = "Also bound: \(other.source.rawValue) — \(other.title)"
                }
            }
        }
        return reasons
    }
}
