import Foundation
import CoreGraphics
import AppKit

// MARK: - Hotkey

public struct Hotkey: Codable, Hashable, Sendable {
    /// Which event stream this hotkey lives on.
    ///
    /// `.standard` keys arrive as `CGEvent` keyDowns and `keyCode` is a virtual
    /// (Carbon) key code. `.systemDefined` keys (brightness/volume/mute/media and
    /// the special top-row function keys) arrive as `NSSystemDefined` (CGEventType
    /// 14, subtype 8) events; there `keyCode` is an `NX_KEYTYPE_*` aux code, which
    /// lives in a *separate* numbering space from virtual key codes. The two must
    /// never be matched against each other — hence the discriminator.
    public enum KeyType: String, Codable, Hashable, Sendable {
        case standard
        case systemDefined
    }

    public var keyCode: UInt16          // CGKeyCode (standard) or NX_KEYTYPE_* (systemDefined)
    public var modifiers: UInt64        // CGEventFlags.rawValue is UInt64
    public var chordKey: UInt16?        // For two-key sequences
    public var keyType: KeyType         // Defaults to .standard for back-compat

    public init(keyCode: UInt16, modifiers: UInt64, chordKey: UInt16? = nil, keyType: KeyType = .standard) {
        self.keyCode = keyCode
        // Mask out non-essential flags (device-dependent, numpad, etc).
        self.modifiers = modifiers & Hotkey.modifierMask
        self.chordKey = chordKey
        self.keyType = keyType
    }

    // Custom Codable so `.keyforge` files written before keyType existed still
    // decode (absent key -> .standard). New files always write the field.
    private enum CodingKeys: String, CodingKey { case keyCode, modifiers, chordKey, keyType }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.keyCode = try c.decode(UInt16.self, forKey: .keyCode)
        self.modifiers = (try c.decode(UInt64.self, forKey: .modifiers)) & Hotkey.modifierMask
        self.chordKey = try c.decodeIfPresent(UInt16.self, forKey: .chordKey)
        self.keyType = (try? c.decode(KeyType.self, forKey: .keyType)) ?? .standard
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(keyCode, forKey: .keyCode)
        try c.encode(modifiers, forKey: .modifiers)
        try c.encodeIfPresent(chordKey, forKey: .chordKey)
        try c.encode(keyType, forKey: .keyType)
    }

    /// True for brightness/volume/media/special-function keys.
    public var isSystemDefined: Bool { keyType == .systemDefined }

    /// Mask covering the modifier flags we care about for matching.
    ///
    /// `maskSecondaryFn` is deliberately excluded: `fn` is a keyboard *layer*,
    /// not a semantic modifier, and the same physical key (e.g. F4/Spotlight =
    /// keycode 177) reports fn set or unset depending on keyboard settings. If
    /// it were part of the mask, a macro bound to such a key would only match in
    /// one of those states. Ignoring it makes hardware-key overrides reliable.
    public static let modifierMask: UInt64 =
        CGEventFlags.maskCommand.rawValue |
        CGEventFlags.maskAlternate.rawValue |
        CGEventFlags.maskControl.rawValue |
        CGEventFlags.maskShift.rawValue

    public var cgEventFlags: CGEventFlags {
        CGEventFlags(rawValue: modifiers)
    }

    public var hasCommand: Bool { (modifiers & CGEventFlags.maskCommand.rawValue) != 0 }
    public var hasOption:  Bool { (modifiers & CGEventFlags.maskAlternate.rawValue) != 0 }
    public var hasControl: Bool { (modifiers & CGEventFlags.maskControl.rawValue) != 0 }
    public var hasShift:   Bool { (modifiers & CGEventFlags.maskShift.rawValue) != 0 }
    public var hasFn:      Bool { (modifiers & CGEventFlags.maskSecondaryFn.rawValue) != 0 }

    public var displayString: String {
        var s = ""
        if hasControl { s += "⌃" }
        if hasOption  { s += "⌥" }
        if hasShift   { s += "⇧" }
        if hasCommand { s += "⌘" }
        if hasFn      { s += "fn " }
        s += isSystemDefined ? SystemKeyMap.name(for: keyCode) : KeyCodeMap.name(for: keyCode)
        if let chord = chordKey {
            s += " , " + KeyCodeMap.name(for: chord)
        }
        return s
    }
}

// MARK: - Trigger Mode

public enum TriggerMode: String, Codable, CaseIterable, Sendable {
    case hotkey   // Single hotkey press
    case chord    // Two-key sequence
    case manual   // Only triggered manually
}

// MARK: - Media Action

public enum MediaAction: String, Codable, CaseIterable, Sendable {
    case playPause
    case next
    case previous
    case volumeUp
    case volumeDown
    case mute
}

// MARK: - Condition Check

public enum ConditionCheck: Codable, Hashable, Sendable {
    case frontmostApp(bundleID: String)
    case timeOfDay(startHour: Int, endHour: Int)
    case wifiConnected(ssid: String)
    case fileExists(path: String)
    case alwaysTrue
    case alwaysFalse

    private enum CodingKeys: String, CodingKey { case type, value }
    private enum Kind: String, Codable { case frontmostApp, timeOfDay, wifiConnected, fileExists, alwaysTrue, alwaysFalse }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try c.decode(Kind.self, forKey: .type)
        switch kind {
        case .frontmostApp:
            let v = try c.decode([String: String].self, forKey: .value)
            self = .frontmostApp(bundleID: v["bundleID"] ?? "")
        case .timeOfDay:
            let v = try c.decode([String: Int].self, forKey: .value)
            self = .timeOfDay(startHour: v["startHour"] ?? 0, endHour: v["endHour"] ?? 23)
        case .wifiConnected:
            let v = try c.decode([String: String].self, forKey: .value)
            self = .wifiConnected(ssid: v["ssid"] ?? "")
        case .fileExists:
            let v = try c.decode([String: String].self, forKey: .value)
            self = .fileExists(path: v["path"] ?? "")
        case .alwaysTrue:  self = .alwaysTrue
        case .alwaysFalse: self = .alwaysFalse
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .frontmostApp(let bundleID):
            try c.encode(Kind.frontmostApp, forKey: .type)
            try c.encode(["bundleID": bundleID], forKey: .value)
        case .timeOfDay(let s, let e):
            try c.encode(Kind.timeOfDay, forKey: .type)
            try c.encode(["startHour": s, "endHour": e], forKey: .value)
        case .wifiConnected(let ssid):
            try c.encode(Kind.wifiConnected, forKey: .type)
            try c.encode(["ssid": ssid], forKey: .value)
        case .fileExists(let path):
            try c.encode(Kind.fileExists, forKey: .type)
            try c.encode(["path": path], forKey: .value)
        case .alwaysTrue:
            try c.encode(Kind.alwaysTrue, forKey: .type)
            try c.encode([String: String](), forKey: .value)
        case .alwaysFalse:
            try c.encode(Kind.alwaysFalse, forKey: .type)
            try c.encode([String: String](), forKey: .value)
        }
    }
}

// MARK: - Macro Action

public indirect enum MacroAction: Codable, Hashable, Sendable, Identifiable {
    case launchApp(id: UUID, bundleID: String)
    case openURL(id: UUID, url: String)
    case typeText(id: UUID, text: String, useClipboard: Bool)
    case shellCommand(id: UUID, command: String, waitForExit: Bool)
    case appleScript(id: UUID, source: String)
    case delay(id: UUID, milliseconds: Int)
    case keyPress(id: UUID, keyCode: UInt16, modifiers: UInt64)
    case mediaControl(id: UUID, action: MediaAction)
    case focusApp(id: UUID, bundleID: String)
    case openFile(id: UUID, path: String)
    case notification(id: UUID, title: String, body: String)
    case ifCondition(id: UUID, condition: ConditionCheck, thenActions: [MacroAction], elseActions: [MacroAction])

    public var id: UUID {
        switch self {
        case .launchApp(let id, _),
             .openURL(let id, _),
             .typeText(let id, _, _),
             .shellCommand(let id, _, _),
             .appleScript(let id, _),
             .delay(let id, _),
             .keyPress(let id, _, _),
             .mediaControl(let id, _),
             .focusApp(let id, _),
             .openFile(let id, _),
             .notification(let id, _, _),
             .ifCondition(let id, _, _, _):
            return id
        }
    }

    public var displayName: String {
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

    public var sfSymbol: String {
        switch self {
        case .launchApp: return "app.badge"
        case .openURL: return "link"
        case .typeText: return "text.cursor"
        case .shellCommand: return "terminal"
        case .appleScript: return "applescript"
        case .delay: return "clock"
        case .keyPress: return "keyboard"
        case .mediaControl: return "playpause"
        case .focusApp: return "rectangle.stack"
        case .openFile: return "doc"
        case .notification: return "bell"
        case .ifCondition: return "questionmark.diamond"
        }
    }

    // Codable conformance via discriminator + payload.
    private enum CodingKeys: String, CodingKey { case type, payload }
    private enum Kind: String, Codable {
        case launchApp, openURL, typeText, shellCommand, appleScript, delay,
             keyPress, mediaControl, focusApp, openFile, notification, ifCondition
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try c.decode(Kind.self, forKey: .type)
        let payload = try c.nestedContainer(keyedBy: PayloadKeys.self, forKey: .payload)
        let id = (try? payload.decode(UUID.self, forKey: .id)) ?? UUID()
        switch kind {
        case .launchApp:
            self = .launchApp(id: id, bundleID: try payload.decode(String.self, forKey: .bundleID))
        case .openURL:
            self = .openURL(id: id, url: try payload.decode(String.self, forKey: .url))
        case .typeText:
            self = .typeText(
                id: id,
                text: try payload.decode(String.self, forKey: .text),
                useClipboard: try payload.decode(Bool.self, forKey: .useClipboard)
            )
        case .shellCommand:
            self = .shellCommand(
                id: id,
                command: try payload.decode(String.self, forKey: .command),
                waitForExit: try payload.decode(Bool.self, forKey: .waitForExit)
            )
        case .appleScript:
            self = .appleScript(id: id, source: try payload.decode(String.self, forKey: .source))
        case .delay:
            self = .delay(id: id, milliseconds: try payload.decode(Int.self, forKey: .milliseconds))
        case .keyPress:
            self = .keyPress(
                id: id,
                keyCode: try payload.decode(UInt16.self, forKey: .keyCode),
                modifiers: try payload.decode(UInt64.self, forKey: .modifiers)
            )
        case .mediaControl:
            self = .mediaControl(id: id, action: try payload.decode(MediaAction.self, forKey: .mediaAction))
        case .focusApp:
            self = .focusApp(id: id, bundleID: try payload.decode(String.self, forKey: .bundleID))
        case .openFile:
            self = .openFile(id: id, path: try payload.decode(String.self, forKey: .path))
        case .notification:
            self = .notification(
                id: id,
                title: try payload.decode(String.self, forKey: .title),
                body: try payload.decode(String.self, forKey: .body)
            )
        case .ifCondition:
            self = .ifCondition(
                id: id,
                condition: try payload.decode(ConditionCheck.self, forKey: .condition),
                thenActions: try payload.decode([MacroAction].self, forKey: .thenActions),
                elseActions: try payload.decode([MacroAction].self, forKey: .elseActions)
            )
        }
    }

    private enum PayloadKeys: String, CodingKey {
        case id, bundleID, url, text, useClipboard, command, waitForExit, source,
             milliseconds, keyCode, modifiers, mediaAction, path, title, body,
             condition, thenActions, elseActions
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        var p = c.nestedContainer(keyedBy: PayloadKeys.self, forKey: .payload)
        try p.encode(self.id, forKey: .id)
        switch self {
        case .launchApp(_, let bundleID):
            try c.encode(Kind.launchApp, forKey: .type)
            try p.encode(bundleID, forKey: .bundleID)
        case .openURL(_, let url):
            try c.encode(Kind.openURL, forKey: .type)
            try p.encode(url, forKey: .url)
        case .typeText(_, let text, let useClipboard):
            try c.encode(Kind.typeText, forKey: .type)
            try p.encode(text, forKey: .text)
            try p.encode(useClipboard, forKey: .useClipboard)
        case .shellCommand(_, let command, let waitForExit):
            try c.encode(Kind.shellCommand, forKey: .type)
            try p.encode(command, forKey: .command)
            try p.encode(waitForExit, forKey: .waitForExit)
        case .appleScript(_, let source):
            try c.encode(Kind.appleScript, forKey: .type)
            try p.encode(source, forKey: .source)
        case .delay(_, let ms):
            try c.encode(Kind.delay, forKey: .type)
            try p.encode(ms, forKey: .milliseconds)
        case .keyPress(_, let keyCode, let modifiers):
            try c.encode(Kind.keyPress, forKey: .type)
            try p.encode(keyCode, forKey: .keyCode)
            try p.encode(modifiers, forKey: .modifiers)
        case .mediaControl(_, let action):
            try c.encode(Kind.mediaControl, forKey: .type)
            try p.encode(action, forKey: .mediaAction)
        case .focusApp(_, let bundleID):
            try c.encode(Kind.focusApp, forKey: .type)
            try p.encode(bundleID, forKey: .bundleID)
        case .openFile(_, let path):
            try c.encode(Kind.openFile, forKey: .type)
            try p.encode(path, forKey: .path)
        case .notification(_, let title, let body):
            try c.encode(Kind.notification, forKey: .type)
            try p.encode(title, forKey: .title)
            try p.encode(body, forKey: .body)
        case .ifCondition(_, let condition, let thenActions, let elseActions):
            try c.encode(Kind.ifCondition, forKey: .type)
            try p.encode(condition, forKey: .condition)
            try p.encode(thenActions, forKey: .thenActions)
            try p.encode(elseActions, forKey: .elseActions)
        }
    }
}

// MARK: - Macro

public struct Macro: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var name: String
    public var icon: String
    public var hotkey: Hotkey?
    public var actions: [MacroAction]
    public var groupID: UUID?
    public var isEnabled: Bool
    public var triggerMode: TriggerMode

    public init(
        id: UUID = UUID(),
        name: String,
        icon: String = "bolt.fill",
        hotkey: Hotkey? = nil,
        actions: [MacroAction] = [],
        groupID: UUID? = nil,
        isEnabled: Bool = true,
        triggerMode: TriggerMode = .hotkey
    ) {
        self.id = id
        self.name = name
        self.icon = icon
        self.hotkey = hotkey
        self.actions = actions
        self.groupID = groupID
        self.isEnabled = isEnabled
        self.triggerMode = triggerMode
    }
}

// MARK: - Macro Group

public struct MacroGroup: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var name: String
    public var icon: String
    public var isEnabled: Bool
    public var sortOrder: Int

    public init(
        id: UUID = UUID(),
        name: String,
        icon: String = "folder",
        isEnabled: Bool = true,
        sortOrder: Int = 0
    ) {
        self.id = id
        self.name = name
        self.icon = icon
        self.isEnabled = isEnabled
        self.sortOrder = sortOrder
    }
}

// MARK: - Snippet

public struct Snippet: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var abbreviation: String
    public var expansion: String
    public var isEnabled: Bool

    public init(
        id: UUID = UUID(),
        abbreviation: String,
        expansion: String,
        isEnabled: Bool = true
    ) {
        self.id = id
        self.abbreviation = abbreviation
        self.expansion = expansion
        self.isEnabled = isEnabled
    }
}

// MARK: - Library Wrapper

public struct MacroLibrary: Codable, Sendable {
    public var macros: [Macro]
    public var groups: [MacroGroup]
    public var snippets: [Snippet]
    public var version: Int

    public init(
        macros: [Macro] = [],
        groups: [MacroGroup] = [],
        snippets: [Snippet] = [],
        version: Int = 1
    ) {
        self.macros = macros
        self.groups = groups
        self.snippets = snippets
        self.version = version
    }
}

// MARK: - Key Code Map (for display)

public enum KeyCodeMap {
    /// Reverse map of macOS virtual key codes to human-readable strings.
    public static func name(for keyCode: UInt16) -> String {
        switch keyCode {
        case 0:   return "A"
        case 1:   return "S"
        case 2:   return "D"
        case 3:   return "F"
        case 4:   return "H"
        case 5:   return "G"
        case 6:   return "Z"
        case 7:   return "X"
        case 8:   return "C"
        case 9:   return "V"
        case 11:  return "B"
        case 12:  return "Q"
        case 13:  return "W"
        case 14:  return "E"
        case 15:  return "R"
        case 16:  return "Y"
        case 17:  return "T"
        case 18:  return "1"
        case 19:  return "2"
        case 20:  return "3"
        case 21:  return "4"
        case 22:  return "6"
        case 23:  return "5"
        case 24:  return "="
        case 25:  return "9"
        case 26:  return "7"
        case 27:  return "-"
        case 28:  return "8"
        case 29:  return "0"
        case 30:  return "]"
        case 31:  return "O"
        case 32:  return "U"
        case 33:  return "["
        case 34:  return "I"
        case 35:  return "P"
        case 36:  return "↩︎"
        case 37:  return "L"
        case 38:  return "J"
        case 39:  return "'"
        case 40:  return "K"
        case 41:  return ";"
        case 42:  return "\\"
        case 43:  return ","
        case 44:  return "/"
        case 45:  return "N"
        case 46:  return "M"
        case 47:  return "."
        case 48:  return "⇥"
        case 49:  return "Space"
        case 50:  return "`"
        case 51:  return "⌫"
        case 53:  return "⎋"
        case 117: return "⌦"
        case 122: return "F1"
        case 120: return "F2"
        case 99:  return "F3"
        case 118: return "F4"
        case 96:  return "F5"
        case 97:  return "F6"
        case 98:  return "F7"
        case 100: return "F8"
        case 101: return "F9"
        case 109: return "F10"
        case 103: return "F11"
        case 111: return "F12"
        case 105: return "F13"
        case 107: return "F14"
        case 113: return "F15"
        case 106: return "F16"
        case 64:  return "F17"
        case 79:  return "F18"
        case 80:  return "F19"
        case 90:  return "F20"
        case 123: return "←"
        case 124: return "→"
        case 125: return "↓"
        case 126: return "↑"
        case 115: return "Home"
        case 119: return "End"
        case 116: return "PgUp"
        case 121: return "PgDn"
        // Apple fn-row "special" keys that arrive as standard keyDowns with
        // high virtual key codes (vary by keyboard; these are the common ones).
        case 176: return "Dictation"
        case 177: return "Spotlight"
        case 178: return "Focus"
        case 179: return "Emoji"
        default:  return "Key(\(keyCode))"
        }
    }

    /// Map a single ASCII character to a (keyCode, requiresShift) tuple, for use in
    /// synthesizing keyboard events. Used by TextTyper for non-clipboard mode.
    public static func keyCode(for character: Character) -> (keyCode: UInt16, shift: Bool)? {
        switch character {
        case "a": return (0, false);  case "A": return (0, true)
        case "s": return (1, false);  case "S": return (1, true)
        case "d": return (2, false);  case "D": return (2, true)
        case "f": return (3, false);  case "F": return (3, true)
        case "h": return (4, false);  case "H": return (4, true)
        case "g": return (5, false);  case "G": return (5, true)
        case "z": return (6, false);  case "Z": return (6, true)
        case "x": return (7, false);  case "X": return (7, true)
        case "c": return (8, false);  case "C": return (8, true)
        case "v": return (9, false);  case "V": return (9, true)
        case "b": return (11, false); case "B": return (11, true)
        case "q": return (12, false); case "Q": return (12, true)
        case "w": return (13, false); case "W": return (13, true)
        case "e": return (14, false); case "E": return (14, true)
        case "r": return (15, false); case "R": return (15, true)
        case "y": return (16, false); case "Y": return (16, true)
        case "t": return (17, false); case "T": return (17, true)
        case "o": return (31, false); case "O": return (31, true)
        case "u": return (32, false); case "U": return (32, true)
        case "i": return (34, false); case "I": return (34, true)
        case "p": return (35, false); case "P": return (35, true)
        case "l": return (37, false); case "L": return (37, true)
        case "j": return (38, false); case "J": return (38, true)
        case "k": return (40, false); case "K": return (40, true)
        case "n": return (45, false); case "N": return (45, true)
        case "m": return (46, false); case "M": return (46, true)
        case "1": return (18, false); case "!": return (18, true)
        case "2": return (19, false); case "@": return (19, true)
        case "3": return (20, false); case "#": return (20, true)
        case "4": return (21, false); case "$": return (21, true)
        case "5": return (23, false); case "%": return (23, true)
        case "6": return (22, false); case "^": return (22, true)
        case "7": return (26, false); case "&": return (26, true)
        case "8": return (28, false); case "*": return (28, true)
        case "9": return (25, false); case "(": return (25, true)
        case "0": return (29, false); case ")": return (29, true)
        case "-": return (27, false); case "_": return (27, true)
        case "=": return (24, false); case "+": return (24, true)
        case "[": return (33, false); case "{": return (33, true)
        case "]": return (30, false); case "}": return (30, true)
        case "\\": return (42, false); case "|": return (42, true)
        case ";": return (41, false); case ":": return (41, true)
        case "'": return (39, false); case "\"": return (39, true)
        case ",": return (43, false); case "<": return (43, true)
        case ".": return (47, false); case ">": return (47, true)
        case "/": return (44, false); case "?": return (44, true)
        case "`": return (50, false); case "~": return (50, true)
        case " ": return (49, false)
        case "\n": return (36, false)
        case "\t": return (48, false)
        default:  return nil
        }
    }
}

// MARK: - System Key Map (NX_KEYTYPE_* aux codes)

/// Human-readable names + identity for the hardware "special" keys that arrive
/// as `NSSystemDefined` (CGEventType 14) subtype-8 events: brightness, volume,
/// mute, media transport, and the keyboard-illumination keys. The numeric codes
/// are the `NX_KEYTYPE_*` constants from IOKit's `ev_keymap.h` — a separate
/// numbering space from virtual key codes, so `keyCode` here must only ever be
/// interpreted via this map (never `KeyCodeMap`).
public enum SystemKeyMap {
    // NX_KEYTYPE_* values from <IOKit/hidsystem/ev_keymap.h>.
    public static let soundUp: UInt16        = 0
    public static let soundDown: UInt16      = 1
    public static let brightnessUp: UInt16   = 2
    public static let brightnessDown: UInt16 = 3
    public static let mute: UInt16           = 7
    public static let play: UInt16           = 16   // play/pause
    public static let next: UInt16           = 17   // fast-forward / next track
    public static let previous: UInt16       = 18   // rewind / previous track
    public static let fast: UInt16           = 19
    public static let rewind: UInt16         = 20
    public static let illuminationUp: UInt16 = 21
    public static let illuminationDown: UInt16 = 22

    /// The keys we know how to recognize, in display order. Drives the picker
    /// and the "All Hotkeys" inventory.
    public static let known: [UInt16] = [
        brightnessDown, brightnessUp,
        illuminationDown, illuminationUp,
        previous, play, next,
        rewind, fast,
        mute, soundDown, soundUp,
    ]

    public static func name(for keyCode: UInt16) -> String {
        switch keyCode {
        case soundUp:         return "Volume Up"
        case soundDown:       return "Volume Down"
        case brightnessUp:    return "Brightness Up"
        case brightnessDown:  return "Brightness Down"
        case mute:            return "Mute"
        case play:            return "Play/Pause"
        case next:            return "Next Track"
        case previous:        return "Previous Track"
        case fast:            return "Fast-Forward"
        case rewind:          return "Rewind"
        case illuminationUp:  return "Keyboard Bright Up"
        case illuminationDown: return "Keyboard Bright Down"
        default:              return "SystemKey(\(keyCode))"
        }
    }

    /// SF Symbol suggestion for a system key (used in the inventory UI).
    public static func sfSymbol(for keyCode: UInt16) -> String {
        switch keyCode {
        case soundUp, soundDown:           return "speaker.wave.2"
        case mute:                         return "speaker.slash"
        case brightnessUp, brightnessDown: return "sun.max"
        case play:                         return "playpause"
        case next, fast:                   return "forward"
        case previous, rewind:             return "backward"
        case illuminationUp, illuminationDown: return "keyboard"
        default:                           return "key"
        }
    }
}

// MARK: - Hardware Key Catalog

/// Every physical "special" key on a Mac keyboard, with what macOS does with it
/// by default. Indexed into the All Hotkeys inventory so pressing brightness,
/// volume, media, or an fn-row key (Spotlight/Dictation/…) resolves to a result
/// even when no macro is bound. A key can arrive as a `.systemDefined` aux event
/// (brightness/volume/media) OR as a `.standard` keyDown with a high keycode
/// (the newer fn-row keys) — both forms are listed so a press always matches.
public struct HardwareKey: Hashable, Sendable {
    public let hotkey: Hotkey
    public let action: String   // what macOS does by default
    public let symbol: String
}

public enum HardwareKeyCatalog {
    private static func sys(_ code: UInt16, _ action: String, _ sym: String) -> HardwareKey {
        HardwareKey(hotkey: Hotkey(keyCode: code, modifiers: 0, keyType: .systemDefined), action: action, symbol: sym)
    }
    private static func std(_ code: UInt16, _ action: String, _ sym: String) -> HardwareKey {
        HardwareKey(hotkey: Hotkey(keyCode: code, modifiers: 0, keyType: .standard), action: action, symbol: sym)
    }

    public static let all: [HardwareKey] = {
        var keys: [HardwareKey] = [
            // System-defined (aux) keys — brightness / backlight / media / volume.
            sys(SystemKeyMap.brightnessDown, "Decrease display brightness", "sun.min"),
            sys(SystemKeyMap.brightnessUp,   "Increase display brightness", "sun.max"),
            sys(SystemKeyMap.illuminationDown, "Decrease keyboard backlight", "light.min"),
            sys(SystemKeyMap.illuminationUp,   "Increase keyboard backlight", "light.max"),
            sys(SystemKeyMap.previous, "Previous track / rewind", "backward.fill"),
            sys(SystemKeyMap.play,     "Play / pause media", "playpause.fill"),
            sys(SystemKeyMap.next,     "Next track / fast-forward", "forward.fill"),
            sys(SystemKeyMap.mute,     "Mute audio", "speaker.slash.fill"),
            sys(SystemKeyMap.soundDown, "Decrease volume", "speaker.wave.1.fill"),
            sys(SystemKeyMap.soundUp,   "Increase volume", "speaker.wave.3.fill"),
            // fn-row special keys that arrive as standard high keycodes.
            std(177, "Spotlight Search", "magnifyingglass"),
            std(176, "Dictation", "mic.fill"),
            std(178, "Focus / Do Not Disturb", "moon.fill"),
            std(179, "Emoji & Symbols", "face.smiling"),
        ]
        // Plain function keys F1-F12 (when "Use F-keys as standard" is on).
        let fkeys: [(UInt16, String)] = [
            (122, "F1"), (120, "F2"), (99, "F3"), (118, "F4"), (96, "F5"), (97, "F6"),
            (98, "F7"), (100, "F8"), (101, "F9"), (109, "F10"), (103, "F11"), (111, "F12"),
        ]
        for (code, label) in fkeys {
            keys.append(std(code, "\(label) function key", "f.square"))
        }
        return keys
    }()
}
