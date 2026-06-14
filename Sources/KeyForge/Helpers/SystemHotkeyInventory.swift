import Foundation
import CoreGraphics

/// One macOS system keyboard shortcut as recorded in the OS's own
/// `com.apple.symbolichotkeys` preference domain — the authoritative source
/// behind System Settings → Keyboard → Keyboard Shortcuts. Covers Mission
/// Control, Spotlight, screenshots, input sources, space switching, etc.,
/// including each one's enabled/disabled state.
public struct SystemHotkeyRecord: Identifiable, Hashable, Sendable {
    public let id: Int          // symbolic hotkey id
    public let name: String     // human label (curated; falls back to id)
    public let combo: String    // display combo, "" if the OS stores no override
    public let isEnabled: Bool

    public init(id: Int, name: String, combo: String, isEnabled: Bool) {
        self.id = id
        self.name = name
        self.combo = combo
        self.isEnabled = isEnabled
    }
}

/// Reads and decodes the OS symbolic-hotkeys plist. Pure parsing lives in
/// `parse(_:)` so it can be unit-tested against a fixture dictionary without
/// touching the live preference domain.
public enum SystemHotkeyInventory {
    /// Read the live `com.apple.symbolichotkeys` domain. Returns [] if the key
    /// is absent (fresh account) or unreadable.
    public static func load() -> [SystemHotkeyRecord] {
        guard let raw = CFPreferencesCopyAppValue(
            "AppleSymbolicHotKeys" as CFString,
            "com.apple.symbolichotkeys" as CFString
        ) as? [String: Any] else {
            return []
        }
        return parse(raw)
    }

    /// Decode the `AppleSymbolicHotKeys` dictionary into records.
    public static func parse(_ dict: [String: Any]) -> [SystemHotkeyRecord] {
        var out: [SystemHotkeyRecord] = []
        for (key, value) in dict {
            guard let id = Int(key), let entry = value as? [String: Any] else { continue }
            let enabled = (entry["enabled"] as? NSNumber)?.boolValue ?? false

            var combo = ""
            if let v = entry["value"] as? [String: Any],
               let params = (v["parameters"] as? [NSNumber])?.map(\.intValue),
               params.count >= 3 {
                combo = comboString(ascii: params[0], keyCode: params[1], cocoaModifiers: params[2])
            }

            out.append(SystemHotkeyRecord(id: id, name: name(forID: id), combo: combo, isEnabled: enabled))
        }
        // Stable, human-friendly order: by name then id.
        return out.sorted { ($0.name.lowercased(), $0.id) < ($1.name.lowercased(), $1.id) }
    }

    // MARK: - Combo formatting

    /// macOS stores the modifier mask using the Cocoa device-independent
    /// `NSEvent.ModifierFlags` raw bits (NOT Carbon and NOT CGEventFlags).
    static func comboString(ascii: Int, keyCode: Int, cocoaModifiers: Int) -> String {
        let control  = 0x40000
        let option   = 0x80000
        let shift    = 0x20000
        let command  = 0x100000
        let function = 0x800000

        var s = ""
        if cocoaModifiers & function != 0 { s += "fn " }
        if cocoaModifiers & control  != 0 { s += "⌃" }
        if cocoaModifiers & option   != 0 { s += "⌥" }
        if cocoaModifiers & shift    != 0 { s += "⇧" }
        if cocoaModifiers & command  != 0 { s += "⌘" }

        if keyCode >= 0 && keyCode != 0xFFFF {
            s += KeyCodeMap.name(for: UInt16(truncatingIfNeeded: keyCode))
        } else if ascii != 0xFFFF, ascii > 0, let scalar = Unicode.Scalar(UInt32(ascii)) {
            s += String(Character(scalar)).uppercased()
        }
        return s
    }

    // MARK: - ID -> name

    /// Curated labels for the well-known symbolic-hotkey ids. Apple does not
    /// publish a stable list, so unknown ids fall back to a generic label — the
    /// row is still shown (with its combo + enabled state) so the inventory is
    /// genuinely exhaustive.
    static func name(forID id: Int) -> String {
        if let n = table[id] { return n }
        return "System shortcut #\(id)"
    }

    private static let table: [Int: String] = [
        7:   "Keyboard: move focus to menu bar",
        8:   "Keyboard: move focus to Dock",
        9:   "Keyboard: move focus to active/next window",
        10:  "Keyboard: move focus to window toolbar",
        11:  "Keyboard: move focus to floating window",
        12:  "Keyboard: toggle full keyboard access",
        13:  "Keyboard: move focus to next window",
        15:  "Zoom: toggle",
        17:  "Display: invert colors",
        18:  "Zoom: increase contrast",
        19:  "Zoom: decrease contrast",
        25:  "Dock: hide/show",
        27:  "Keyboard: move focus to status menus",
        28:  "Screenshot: copy picture of screen to clipboard",
        29:  "Screenshot: save picture of screen as a file",
        30:  "Screenshot: copy picture of selected area to clipboard",
        31:  "Screenshot: save picture of selected area as a file",
        32:  "Mission Control",
        33:  "Show Dashboard",
        34:  "Mission Control: show desktop",
        35:  "Spaces: switch (legacy)",
        36:  "Mission Control: application windows",
        51:  "Look up in Dictionary",
        52:  "Spaces: switch (legacy)",
        57:  "Keyboard: change the way Tab moves focus",
        59:  "Spaces: switch (legacy)",
        60:  "Input: select the previous input source",
        61:  "Input: select next source in input menu",
        62:  "Spotlight: show (legacy)",
        64:  "Spotlight: show search",
        65:  "Spotlight: show Finder search window",
        70:  "Front Row (legacy)",
        73:  "Spaces: switch (legacy)",
        79:  "Spaces: move left a space",
        80:  "Spaces: move right a space",
        81:  "Spaces: switch to desktop up",
        82:  "Spaces: switch to desktop down",
        98:  "Help: show",
        118: "Spaces: switch to Desktop 1",
        119: "Spaces: switch to Desktop 2",
        120: "Spaces: switch to Desktop 3",
        121: "Spaces: switch to Desktop 4",
        122: "Spaces: switch to Desktop 5",
        123: "Spaces: switch to Desktop 6",
        159: "Spotlight: show in Finder",
        160: "Launchpad: show",
        162: "Notification Center: show",
        163: "Do Not Disturb: toggle",
        175: "Notification Center: toggle",
        179: "Dictation: start",
        181: "Screenshot: copy Touch Bar to clipboard",
        182: "Screenshot: save Touch Bar as a file",
        184: "Screenshot and recording options",
        190: "Stage Manager: toggle",
        222: "Quick Note",
    ]
}
