import SwiftUI
import AppKit
import CoreGraphics

/// SwiftUI wrapper around an NSView that captures a single keyboard combo.
/// Clicking the view enters recording mode. Pressing any key combo records it.
/// Escape cancels. Delete/Backspace clears the current hotkey.
public struct KeyRecorderView: NSViewRepresentable {
    @Binding public var hotkey: Hotkey?
    public var conflict: HotkeyConflict
    public var allowChord: Bool

    public init(hotkey: Binding<Hotkey?>, conflict: HotkeyConflict = .noConflict, allowChord: Bool = false) {
        self._hotkey = hotkey
        self.conflict = conflict
        self.allowChord = allowChord
    }

    public func makeNSView(context: Context) -> RecorderNSView {
        let v = RecorderNSView()
        v.onChange = { newHotkey in
            DispatchQueue.main.async {
                self.hotkey = newHotkey
            }
        }
        v.allowChord = allowChord
        v.update(hotkey: hotkey, conflict: conflict)
        return v
    }

    public func updateNSView(_ nsView: RecorderNSView, context: Context) {
        nsView.allowChord = allowChord
        nsView.update(hotkey: hotkey, conflict: conflict)
    }

    public final class RecorderNSView: NSView {
        var onChange: ((Hotkey?) -> Void)?
        var allowChord: Bool = false
        private var isRecording: Bool = false
        private var pendingFirst: (keyCode: UInt16, modifiers: UInt64)?
        private var currentHotkey: Hotkey?
        private var currentConflict: HotkeyConflict = .noConflict
        private var monitor: Any?
        private var usingCaptureHook: Bool = false
        private let label = NSTextField(labelWithString: "")

        public override init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            wantsLayer = true
            layer?.cornerRadius = 6
            layer?.borderWidth = 1
            label.translatesAutoresizingMaskIntoConstraints = false
            label.alignment = .center
            label.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .medium)
            label.textColor = .labelColor
            addSubview(label)
            NSLayoutConstraint.activate([
                label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
                label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
                label.centerYAnchor.constraint(equalTo: centerYAnchor)
            ])
            updateBorder()
            updateLabel()
        }

        public required init?(coder: NSCoder) { fatalError() }

        deinit {
            // Defensive: never leave the global capture hook installed.
            if usingCaptureHook { EventTapManager.shared.captureHook = nil }
            if let m = monitor { NSEvent.removeMonitor(m) }
        }

        public override var intrinsicContentSize: NSSize { NSSize(width: 180, height: 30) }

        public override func mouseDown(with event: NSEvent) {
            if isRecording { stopRecording(commit: false) } else { startRecording() }
        }

        public override var acceptsFirstResponder: Bool { true }

        public override func becomeFirstResponder() -> Bool {
            startRecording()
            return true
        }

        public override func resignFirstResponder() -> Bool {
            // Clicking away / tabbing out must stop recording, or the global hook
            // would keep swallowing keystrokes everywhere.
            if isRecording { stopRecording(commit: false) }
            return super.resignFirstResponder()
        }

        public override func viewWillMove(toWindow newWindow: NSWindow?) {
            super.viewWillMove(toWindow: newWindow)
            if newWindow == nil && isRecording { stopRecording(commit: false) }
        }

        func update(hotkey: Hotkey?, conflict: HotkeyConflict) {
            self.currentHotkey = hotkey
            self.currentConflict = conflict
            updateBorder()
            updateLabel()
        }

        private func startRecording() {
            guard !isRecording else { return }
            isRecording = true
            pendingFirst = nil
            updateBorder()
            updateLabel()
            // When the global tap is live we route through it: that's the only way
            // to see (and swallow) system-defined media keys, which never reach a
            // local NSEvent monitor. Without the tap (Accessibility not yet
            // granted) we fall back to a local monitor for standard keys only.
            let tap = EventTapManager.shared
            if tap.isRunning {
                usingCaptureHook = true
                tap.captureHook = { [weak self] captured in
                    DispatchQueue.main.async {
                        self?.handleCaptured(
                            keyType: captured.keyType,
                            keyCode: captured.keyCode,
                            modifiers: captured.modifiers
                        )
                    }
                }
            } else {
                monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] event in
                    guard let self = self, self.isRecording else { return event }
                    if event.type == .flagsChanged { return nil }
                    let keyCode = UInt16(event.keyCode)
                    let modifiers = UInt64(event.cgEvent?.flags.rawValue ?? 0) & Hotkey.modifierMask
                    self.handleCaptured(keyType: .standard, keyCode: keyCode, modifiers: modifiers)
                    return nil  // swallow event
                }
            }
        }

        private func stopRecording(commit: Bool) {
            isRecording = false
            teardownCapture()
            pendingFirst = nil
            updateBorder()
            updateLabel()
        }

        /// Detach whichever capture mechanism is active. Critical for the capture
        /// hook: while it's installed the global tap swallows *every* keystroke
        /// system-wide, so it must be cleared on every exit path (commit, cancel,
        /// focus loss, teardown).
        private func teardownCapture() {
            if let m = monitor { NSEvent.removeMonitor(m); monitor = nil }
            if usingCaptureHook {
                EventTapManager.shared.captureHook = nil
                usingCaptureHook = false
            }
        }

        private func handleCaptured(keyType: Hotkey.KeyType, keyCode: UInt16, modifiers: UInt64) {
            guard isRecording else { return }
            let mods = modifiers & Hotkey.modifierMask

            // Escape / Delete only make sense for standard keys (their codes
            // collide with NX aux codes, so guard on keyType).
            if keyType == .standard {
                // Escape cancels recording (without modifiers).
                if keyCode == 53 && mods == 0 {
                    stopRecording(commit: false)
                    return
                }
                // Delete/Backspace clears the current hotkey.
                if (keyCode == 51 || keyCode == 117) && mods == 0 {
                    currentHotkey = nil
                    onChange?(nil)
                    stopRecording(commit: true)
                    return
                }
            }

            // Chords are standard-key only; a system key always commits as a single.
            if keyType == .standard, allowChord, let first = pendingFirst {
                let hk = Hotkey(keyCode: first.keyCode, modifiers: first.modifiers, chordKey: keyCode)
                currentHotkey = hk
                onChange?(hk)
                stopRecording(commit: true)
                return
            }

            if keyType == .standard, allowChord, pendingFirst == nil {
                // In chord mode every key sets pendingFirst; the next key completes
                // the chord. For single-key in chord mode, user toggles allowChord off.
                pendingFirst = (keyCode, mods)
                updateLabel()
                return
            }

            let hk = Hotkey(keyCode: keyCode, modifiers: mods, keyType: keyType)
            currentHotkey = hk
            onChange?(hk)
            stopRecording(commit: true)
        }

        private func updateLabel() {
            if isRecording {
                if let first = pendingFirst {
                    let h = Hotkey(keyCode: first.keyCode, modifiers: first.modifiers)
                    label.stringValue = "\(h.displayString) , …"
                } else {
                    label.stringValue = "Press a key combo…"
                }
            } else if let h = currentHotkey {
                label.stringValue = h.displayString
            } else {
                label.stringValue = "Click to record"
            }
            label.textColor = isRecording ? .secondaryLabelColor : .labelColor
        }

        private func updateBorder() {
            switch currentConflict {
            case .noConflict:
                layer?.borderColor = (isRecording ? NSColor.controlAccentColor : NSColor.separatorColor).cgColor
            case .systemConflict, .userConflict:
                layer?.borderColor = NSColor.systemOrange.cgColor
            }
            layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        }
    }
}
