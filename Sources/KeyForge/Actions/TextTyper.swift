import Foundation
import AppKit
import CoreGraphics

/// Synthesizes keyboard events to "type" text into the focused application.
/// Supports two modes:
///   - clipboard: write text to NSPasteboard, then post ⌘V. Fast and reliable for long text.
///   - keystroke: synthesize one keydown+keyup per character. Slower but works in
///                contexts where paste is blocked (password fields, secure inputs).
public final class TextTyper {
    public struct SynthesizedEvent: Equatable, Sendable {
        public enum Kind: Equatable, Sendable { case down, up }
        public let kind: Kind
        public let keyCode: UInt16
        public let modifiers: UInt64
    }

    /// When true, events are recorded instead of posted. Used by tests.
    public var mockMode: Bool = false
    public private(set) var recordedEvents: [SynthesizedEvent] = []

    public init(mockMode: Bool = false) {
        self.mockMode = mockMode
    }

    public func reset() { recordedEvents.removeAll() }

    /// Types `text`. If `useClipboard` is true, uses pasteboard + ⌘V; else synthesizes
    /// individual key events.
    public func type(_ text: String, useClipboard: Bool) {
        if useClipboard {
            typeViaClipboard(text)
        } else {
            typeViaKeystrokes(text)
        }
    }

    /// Sends a single backspace key event. Used by SnippetEngine.
    public func sendBackspace(count: Int = 1) {
        for _ in 0..<count {
            postKey(keyCode: 51, modifiers: 0)
        }
    }

    /// Posts a single key-down / key-up pair with the given modifier flags.
    public func postKey(keyCode: UInt16, modifiers: UInt64) {
        record(.down, keyCode: keyCode, modifiers: modifiers)
        record(.up,   keyCode: keyCode, modifiers: modifiers)
        guard !mockMode else { return }
        guard let src = CGEventSource(stateID: .hidSystemState) else { return }
        if let down = CGEvent(keyboardEventSource: src, virtualKey: CGKeyCode(keyCode), keyDown: true) {
            down.flags = CGEventFlags(rawValue: modifiers)
            down.post(tap: .cghidEventTap)
        }
        if let up = CGEvent(keyboardEventSource: src, virtualKey: CGKeyCode(keyCode), keyDown: false) {
            up.flags = CGEventFlags(rawValue: modifiers)
            up.post(tap: .cghidEventTap)
        }
    }

    // MARK: - Clipboard mode

    private func typeViaClipboard(_ text: String) {
        if !mockMode {
            let pb = NSPasteboard.general
            pb.clearContents()
            pb.setString(text, forType: .string)
        }
        // ⌘V — keyCode 9 with command modifier.
        let cmd = CGEventFlags.maskCommand.rawValue
        record(.down, keyCode: 9, modifiers: cmd)
        record(.up,   keyCode: 9, modifiers: cmd)
        guard !mockMode else { return }
        guard let src = CGEventSource(stateID: .hidSystemState) else { return }
        if let down = CGEvent(keyboardEventSource: src, virtualKey: 9, keyDown: true) {
            down.flags = .maskCommand
            down.post(tap: .cghidEventTap)
        }
        if let up = CGEvent(keyboardEventSource: src, virtualKey: 9, keyDown: false) {
            up.flags = .maskCommand
            up.post(tap: .cghidEventTap)
        }
    }

    // MARK: - Keystroke mode

    private func typeViaKeystrokes(_ text: String) {
        for ch in text {
            guard let (kc, shift) = KeyCodeMap.keyCode(for: ch) else {
                // Characters we can't map (Unicode, emoji) fall back to inserting
                // via CGEventKeyboardSetUnicodeString — single down+up tagged as no key.
                postUnicode(String(ch))
                continue
            }
            let mods: UInt64 = shift ? CGEventFlags.maskShift.rawValue : 0
            postKey(keyCode: kc, modifiers: mods)
        }
    }

    private func postUnicode(_ s: String) {
        // Record one down/up pair tagged with keyCode 0 to keep test counts predictable.
        record(.down, keyCode: 0, modifiers: 0)
        record(.up,   keyCode: 0, modifiers: 0)
        guard !mockMode else { return }
        guard let src = CGEventSource(stateID: .hidSystemState) else { return }
        let utf16 = Array(s.utf16)
        if let down = CGEvent(keyboardEventSource: src, virtualKey: 0, keyDown: true) {
            down.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: utf16)
            down.post(tap: .cghidEventTap)
        }
        if let up = CGEvent(keyboardEventSource: src, virtualKey: 0, keyDown: false) {
            up.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: utf16)
            up.post(tap: .cghidEventTap)
        }
    }

    private func record(_ kind: SynthesizedEvent.Kind, keyCode: UInt16, modifiers: UInt64) {
        recordedEvents.append(SynthesizedEvent(kind: kind, keyCode: keyCode, modifiers: modifiers))
    }
}
