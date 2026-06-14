import Foundation
import Combine

/// Manages persistence of all macros, groups, and snippets to disk.
///
/// Mutations call `scheduleSave()` which debounces writes by 500ms so rapid
/// keystrokes in the editor don't thrash the disk. All public APIs are
/// MainActor-bound for thread safety with SwiftUI.
@MainActor
public final class MacroStore: ObservableObject {
    @Published public private(set) var macros: [Macro] = []
    @Published public private(set) var groups: [MacroGroup] = []
    @Published public private(set) var snippets: [Snippet] = []

    public let storageURL: URL
    private let fileManager: FileManager
    private var saveTask: Task<Void, Never>?
    private let debounceNanos: UInt64 = 500_000_000  // 500ms

    public init(storageURL: URL? = nil, fileManager: FileManager = .default) {
        self.fileManager = fileManager
        if let url = storageURL {
            self.storageURL = url
        } else {
            let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            let dir = appSupport.appendingPathComponent("KeyForge", isDirectory: true)
            try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
            self.storageURL = dir.appendingPathComponent("macros.json")
        }
        load()
    }

    // MARK: - Persistence

    /// Returns true if the on-disk macros.json existed at init time.
    public var hasExistingLibrary: Bool {
        fileManager.fileExists(atPath: storageURL.path)
    }

    public func load() {
        guard fileManager.fileExists(atPath: storageURL.path) else { return }
        do {
            let data = try Data(contentsOf: storageURL)
            let library = try JSONDecoder().decode(MacroLibrary.self, from: data)
            self.macros = library.macros
            self.groups = library.groups
            self.snippets = library.snippets
        } catch {
            Logger.shared.error("Failed to load macros from \(storageURL.path): \(error)")
        }
    }

    /// Saves immediately, bypassing the debounce. Useful for tests.
    public func saveImmediately() {
        saveTask?.cancel()
        saveTask = nil
        writeToDisk()
    }

    /// Schedules a save in 500ms; coalesces consecutive calls.
    public func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: self?.debounceNanos ?? 500_000_000)
                guard !Task.isCancelled else { return }
                await MainActor.run { self?.writeToDisk() }
            } catch {
                // Sleep cancelled.
            }
        }
    }

    private func writeToDisk() {
        let library = MacroLibrary(macros: macros, groups: groups, snippets: snippets)
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(library)
            // Atomic write: write to temp, then rename, so a crash mid-write doesn't corrupt the library.
            let tmp = storageURL.appendingPathExtension("tmp")
            try data.write(to: tmp, options: .atomic)
            if fileManager.fileExists(atPath: storageURL.path) {
                _ = try? fileManager.replaceItemAt(storageURL, withItemAt: tmp)
            } else {
                try fileManager.moveItem(at: tmp, to: storageURL)
            }
        } catch {
            Logger.shared.error("Failed to save macros: \(error)")
        }
    }

    // MARK: - Macro CRUD

    public func add(_ macro: Macro) {
        macros.append(macro)
        scheduleSave()
    }

    public func update(_ macro: Macro) {
        if let idx = macros.firstIndex(where: { $0.id == macro.id }) {
            macros[idx] = macro
            scheduleSave()
        }
    }

    public func delete(_ macroID: UUID) {
        macros.removeAll { $0.id == macroID }
        scheduleSave()
    }

    public func duplicate(_ macroID: UUID) -> Macro? {
        guard let source = macros.first(where: { $0.id == macroID }) else { return nil }
        var copy = source
        copy.id = UUID()
        copy.name += " Copy"
        copy.hotkey = nil  // Don't conflict with original.
        copy.actions = source.actions.map(MacroAction.cloneWithNewIDs)
        macros.append(copy)
        scheduleSave()
        return copy
    }

    public func move(macroID: UUID, toGroup groupID: UUID?) {
        if let idx = macros.firstIndex(where: { $0.id == macroID }) {
            macros[idx].groupID = groupID
            scheduleSave()
        }
    }

    public func reorder(_ newOrder: [Macro]) {
        macros = newOrder
        scheduleSave()
    }

    public func macro(withID id: UUID) -> Macro? {
        macros.first { $0.id == id }
    }

    // MARK: - Group CRUD

    public func addGroup(_ group: MacroGroup) {
        var g = group
        g.sortOrder = (groups.map { $0.sortOrder }.max() ?? 0) + 1
        groups.append(g)
        scheduleSave()
    }

    public func updateGroup(_ group: MacroGroup) {
        if let idx = groups.firstIndex(where: { $0.id == group.id }) {
            groups[idx] = group
            scheduleSave()
        }
    }

    public func deleteGroup(_ groupID: UUID) {
        groups.removeAll { $0.id == groupID }
        for i in 0..<macros.count where macros[i].groupID == groupID {
            macros[i].groupID = nil
        }
        scheduleSave()
    }

    public func macros(inGroup groupID: UUID?) -> [Macro] {
        macros.filter { $0.groupID == groupID }
    }

    public func group(withID id: UUID) -> MacroGroup? {
        groups.first { $0.id == id }
    }

    // MARK: - Snippet CRUD

    public func addSnippet(_ snippet: Snippet) {
        snippets.append(snippet)
        scheduleSave()
    }

    public func updateSnippet(_ snippet: Snippet) {
        if let idx = snippets.firstIndex(where: { $0.id == snippet.id }) {
            snippets[idx] = snippet
            scheduleSave()
        }
    }

    public func deleteSnippet(_ id: UUID) {
        snippets.removeAll { $0.id == id }
        scheduleSave()
    }

    // MARK: - Import / Export

    public func exportData(macroIDs: [UUID]? = nil) throws -> Data {
        let selected: [Macro]
        if let ids = macroIDs {
            selected = macros.filter { ids.contains($0.id) }
        } else {
            selected = macros
        }
        let usedGroupIDs = Set(selected.compactMap { $0.groupID })
        let bundled = MacroLibrary(
            macros: selected,
            groups: groups.filter { usedGroupIDs.contains($0.id) },
            snippets: macroIDs == nil ? snippets : []
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(bundled)
    }

    public func importData(_ data: Data, replaceExisting: Bool = false) throws -> Int {
        let library = try JSONDecoder().decode(MacroLibrary.self, from: data)
        var added = 0
        for group in library.groups where !groups.contains(where: { $0.id == group.id }) {
            groups.append(group)
        }
        for var macro in library.macros {
            if let existingIdx = macros.firstIndex(where: { $0.id == macro.id }) {
                if replaceExisting {
                    macros[existingIdx] = macro
                    added += 1
                }
            } else {
                // Strip hotkey if it conflicts to avoid breaking the user's existing layout.
                if let hk = macro.hotkey, macros.contains(where: { $0.hotkey == hk }) {
                    macro.hotkey = nil
                }
                macros.append(macro)
                added += 1
            }
        }
        for snippet in library.snippets where !snippets.contains(where: { $0.id == snippet.id }) {
            snippets.append(snippet)
        }
        scheduleSave()
        return added
    }
}

extension MacroAction {
    /// Returns a deep copy of this action with fresh IDs (used by duplicate()).
    static func cloneWithNewIDs(_ action: MacroAction) -> MacroAction {
        switch action {
        case .launchApp(_, let b):                       return .launchApp(id: UUID(), bundleID: b)
        case .openURL(_, let u):                         return .openURL(id: UUID(), url: u)
        case .typeText(_, let t, let c):                 return .typeText(id: UUID(), text: t, useClipboard: c)
        case .shellCommand(_, let cmd, let w):           return .shellCommand(id: UUID(), command: cmd, waitForExit: w)
        case .appleScript(_, let s):                     return .appleScript(id: UUID(), source: s)
        case .delay(_, let ms):                          return .delay(id: UUID(), milliseconds: ms)
        case .keyPress(_, let k, let m):                 return .keyPress(id: UUID(), keyCode: k, modifiers: m)
        case .mediaControl(_, let a):                    return .mediaControl(id: UUID(), action: a)
        case .focusApp(_, let b):                        return .focusApp(id: UUID(), bundleID: b)
        case .openFile(_, let p):                        return .openFile(id: UUID(), path: p)
        case .notification(_, let t, let b):             return .notification(id: UUID(), title: t, body: b)
        case .ifCondition(_, let cond, let th, let el):
            return .ifCondition(
                id: UUID(),
                condition: cond,
                thenActions: th.map(MacroAction.cloneWithNewIDs),
                elseActions: el.map(MacroAction.cloneWithNewIDs)
            )
        }
    }
}
