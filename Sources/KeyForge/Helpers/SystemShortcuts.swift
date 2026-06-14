import Foundation
import CoreGraphics

/// Known macOS system-reserved shortcuts. Used by ConflictDetector to warn the user
/// when they bind a hotkey that the OS will likely intercept first.
public enum SystemShortcuts {
    public struct Entry: Hashable {
        public let keyCode: UInt16
        public let modifiers: UInt64
        public let description: String

        public init(_ keyCode: UInt16, _ modifiers: UInt64, _ description: String) {
            self.keyCode = keyCode
            self.modifiers = modifiers
            self.description = description
        }
    }

    public static let entries: [Entry] = {
        let cmd  = CGEventFlags.maskCommand.rawValue
        let opt  = CGEventFlags.maskAlternate.rawValue
        let ctrl = CGEventFlags.maskControl.rawValue
        let shft = CGEventFlags.maskShift.rawValue

        return [
            // Spotlight, command-tab, etc.
            Entry(49, cmd, "Spotlight (⌘Space)"),
            Entry(49, opt | cmd, "Siri / Spotlight alt"),
            Entry(48, cmd, "App switcher (⌘⇥)"),
            Entry(48, cmd | shft, "Reverse app switcher"),
            Entry(50, cmd, "Window switcher within app (⌘`)"),

            // Screenshots
            Entry(20, cmd | shft, "Screenshot full screen (⌘⇧3)"),
            Entry(21, cmd | shft, "Screenshot selection (⌘⇧4)"),
            Entry(23, cmd | shft, "Screenshot UI (⌘⇧5)"),
            Entry(22, cmd | shft, "Quick note (⌘⇧6)"),

            // Lock & sleep
            Entry(12, cmd | ctrl, "Lock screen (⌃⌘Q)"),
            Entry(14, cmd | opt, "Eject menu"),

            // Mission Control - usually F3 / Ctrl+Up
            Entry(126, ctrl, "Mission Control (⌃↑)"),
            Entry(125, ctrl, "App Exposé (⌃↓)"),
            Entry(123, ctrl, "Previous space (⌃←)"),
            Entry(124, ctrl, "Next space (⌃→)"),

            // System
            Entry(53, cmd | opt, "Force Quit"),
            Entry(12, cmd | opt | shft, "Quit & keep windows alt"),

            // Window mgmt
            Entry(46, cmd, "Minimize window (⌘M)"),
            Entry(4, cmd | shft, "Hide others (⌘⇧H)"),
            Entry(12, cmd, "Quit app (⌘Q)"),
            Entry(13, cmd, "Close window (⌘W)"),

            // Text editing system-wide
            Entry(0, cmd, "Select all (⌘A)"),
            Entry(8, cmd, "Copy (⌘C)"),
            Entry(9, cmd, "Paste (⌘V)"),
            Entry(7, cmd, "Cut (⌘X)"),
            Entry(6, cmd, "Undo (⌘Z)"),
            Entry(6, cmd | shft, "Redo (⌘⇧Z)"),
        ]
    }()

    /// Returns the description if `keyCode + modifiers` matches a known system shortcut.
    public static func conflict(keyCode: UInt16, modifiers: UInt64) -> String? {
        let masked = modifiers & Hotkey.modifierMask
        return entries.first { $0.keyCode == keyCode && $0.modifiers == masked }?.description
    }
}
