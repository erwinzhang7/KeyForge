import Foundation
import CoreGraphics

public enum HotkeyConflict: Equatable, Sendable {
    case noConflict
    case systemConflict(description: String)
    case userConflict(macroName: String, macroID: UUID)
}

/// Determines whether a candidate hotkey clashes with another user macro or a
/// known system shortcut.
public enum ConflictDetector {
    /// `excludeMacroID` lets the editor skip the current macro when re-checking.
    public static func check(
        candidate: Hotkey,
        against macros: [Macro],
        excludeMacroID: UUID? = nil,
        strict: Bool = true
    ) -> HotkeyConflict {
        for macro in macros {
            guard macro.id != excludeMacroID, let hk = macro.hotkey else { continue }
            if hk == candidate {
                return .userConflict(macroName: macro.name, macroID: macro.id)
            }
            // For chord macros, also check whether the *first* keystroke matches.
            if hk.chordKey != nil,
               candidate.chordKey == nil,
               hk.keyCode == candidate.keyCode,
               hk.modifiers == candidate.modifiers {
                return .userConflict(macroName: macro.name, macroID: macro.id)
            }
        }
        if strict {
            if let desc = SystemShortcuts.conflict(keyCode: candidate.keyCode, modifiers: candidate.modifiers) {
                return .systemConflict(description: desc)
            }
        }
        return .noConflict
    }
}
