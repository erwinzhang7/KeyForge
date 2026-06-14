import Foundation
import AppKit
import CoreGraphics

/// Watches keystrokes for registered abbreviations. When an abbreviation is
/// matched (i.e. typed exactly), it backspaces it out and types the expansion.
///
/// Buffer: rolling window of the last N characters (where N is the length of
/// the longest abbreviation). Reset on any non-printable key, modifier key, or
/// long pause between keystrokes.
public final class SnippetEngine: @unchecked Sendable {
    public var isEnabled: Bool = true

    private let queue = DispatchQueue(label: "com.local.keyforge.snippets")
    private var snippets: [Snippet] = []
    private var buffer: String = ""
    private var maxAbbrLength: Int = 0
    private var lastKeystroke: Date = .distantPast
    private let bufferTimeoutSeconds: TimeInterval = 5.0
    private var typer: TextTyper

    /// Hook for tests: every expansion records its abbreviation here when in mock mode.
    public var mockMode: Bool = false
    public private(set) var expansionsTriggered: [(abbreviation: String, expansion: String)] = []

    public init(mockMode: Bool = false) {
        self.mockMode = mockMode
        self.typer = TextTyper(mockMode: mockMode)
    }

    public func updateSnippets(_ snippets: [Snippet]) {
        queue.sync {
            self.snippets = snippets.filter { $0.isEnabled && !$0.abbreviation.isEmpty }
            self.maxAbbrLength = self.snippets.map { $0.abbreviation.count }.max() ?? 0
            self.buffer = ""
        }
    }

    /// Reset the input buffer. Call this when the user clicks somewhere, switches
    /// app, or otherwise breaks the typing stream.
    public func resetBuffer() {
        queue.sync { buffer = "" }
    }

    /// Process a single keystroke. Returns `true` if a snippet was expanded.
    /// `isPrintable` should be true for visible characters (no Cmd/Ctrl/Esc).
    /// Pass a character of "" for non-printable keys (Backspace, arrow keys, etc.)
    /// — they'll reset the buffer.
    @discardableResult
    public func processCharacter(_ character: String, isPrintable: Bool) -> Bool {
        guard isEnabled else { return false }
        let now = Date()
        var expanded: (abbr: String, replacement: String)?

        queue.sync {
            if now.timeIntervalSince(lastKeystroke) > bufferTimeoutSeconds {
                buffer = ""
            }
            lastKeystroke = now
            guard isPrintable, !character.isEmpty else {
                buffer = ""
                return
            }
            // Handle backspace explicitly via isPrintable=false; here only printable chars.
            buffer.append(character)
            // Trim buffer to longest possible match.
            if buffer.count > maxAbbrLength {
                buffer = String(buffer.suffix(maxAbbrLength))
            }
            // Look for an abbreviation that the buffer ends with.
            for s in snippets where buffer.hasSuffix(s.abbreviation) {
                expanded = (s.abbreviation, s.expansion)
                buffer = ""
                break
            }
        }

        if let (abbr, replacement) = expanded {
            performExpansion(abbreviation: abbr, expansion: replacement)
            return true
        }
        return false
    }

    private func performExpansion(abbreviation: String, expansion: String) {
        Logger.shared.info("Snippet expanded: '\(abbreviation)' → '\(expansion.prefix(40))'")
        if mockMode {
            expansionsTriggered.append((abbreviation, expansion))
            // Still record backspaces + typed events for tests to inspect.
            typer.sendBackspace(count: abbreviation.count)
            typer.type(expansion, useClipboard: false)
            return
        }
        // Tiny delay to let the OS deliver the triggering keystroke to the app.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) { [typer = self.typer] in
            typer.sendBackspace(count: abbreviation.count)
            typer.type(expansion, useClipboard: false)
        }
    }

    // MARK: - Test surface

    public func snapshotEvents() -> [TextTyper.SynthesizedEvent] {
        typer.recordedEvents
    }
}
