import Foundation
import CoreGraphics

/// Tracks two-key sequence (chord) input. When the user presses the "leader" key
/// of a chord macro, the detector enters armed state. If the second key arrives
/// within `timeoutMS`, the chord fires. Otherwise the detector resets silently.
///
/// Thread-safety: all calls go through an internal serial dispatch queue, so
/// it's safe to call `process` from the CGEventTap callback thread.
public final class ChordDetector {
    public struct Outcome: Equatable, Sendable {
        public let fired: UUID?           // Macro ID if a chord completed
        public let consumed: Bool         // Should the source event be suppressed?
    }

    private struct Pending {
        let firstHotkey: Hotkey
        let deadline: Date
    }

    public var timeoutMS: Int = 500
    private var pending: Pending?
    /// Now-injection for deterministic tests.
    public var nowProvider: () -> Date = { Date() }
    private let queue = DispatchQueue(label: "com.local.keyforge.chord")

    public init(timeoutMS: Int = 500) {
        self.timeoutMS = timeoutMS
    }

    /// Process a single keystroke against the registered chord macros.
    /// - Parameters:
    ///   - keyCode: virtual key code of pressed key
    ///   - modifiers: masked modifier flags
    ///   - chordMacros: macros where `triggerMode == .chord` and have a chordKey
    /// - Returns: outcome describing whether to consume the event and what fired.
    public func process(
        keyCode: UInt16,
        modifiers: UInt64,
        chordMacros: [Macro]
    ) -> Outcome {
        queue.sync {
            let now = nowProvider()

            // If we have a pending first stroke, see if this matches the second.
            if let pending = pending {
                if now > pending.deadline {
                    // Timed out — discard, fall through to fresh-match logic.
                    self.pending = nil
                } else {
                    // Look for a macro whose leader matches `pending.firstHotkey` and
                    // whose chordKey matches the current keystroke.
                    for macro in chordMacros {
                        guard let hk = macro.hotkey,
                              let chord = hk.chordKey else { continue }
                        if hk.keyCode == pending.firstHotkey.keyCode,
                           hk.modifiers == pending.firstHotkey.modifiers,
                           chord == keyCode {
                            self.pending = nil
                            return Outcome(fired: macro.id, consumed: true)
                        }
                    }
                    // Pending but didn't match — reset and let the keystroke flow.
                    self.pending = nil
                    return Outcome(fired: nil, consumed: false)
                }
            }

            // Fresh keystroke — does any chord macro start with this combo?
            for macro in chordMacros {
                guard let hk = macro.hotkey, hk.chordKey != nil else { continue }
                if hk.keyCode == keyCode && hk.modifiers == (modifiers & Hotkey.modifierMask) {
                    pending = Pending(
                        firstHotkey: Hotkey(keyCode: keyCode, modifiers: modifiers),
                        deadline: now.addingTimeInterval(Double(timeoutMS) / 1000.0)
                    )
                    return Outcome(fired: nil, consumed: true)
                }
            }
            return Outcome(fired: nil, consumed: false)
        }
    }

    public func reset() {
        queue.sync { pending = nil }
    }

    public var isArmed: Bool {
        queue.sync { pending != nil }
    }
}
