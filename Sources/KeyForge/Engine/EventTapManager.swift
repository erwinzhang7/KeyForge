import Foundation
import CoreGraphics
import AppKit

/// Owns the CGEventTap that intercepts all keyboard events system-wide.
///
/// Lifecycle:
///   1. start() — install the tap (requires Accessibility permission)
///   2. updateMacros(_:) — refresh the lookup table whenever the store changes
///   3. stop() — uninstall on shutdown or when globally disabled
///
/// The tap callback runs on the event-tap's own thread. We do the bare minimum
/// inside it: hash lookup + chord state update. Macro execution is dispatched
/// onto the MacroExecutor actor.
public final class EventTapManager: @unchecked Sendable {
    public static let shared = EventTapManager()

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    /// `NSSystemDefined`. `CGEventType` has no public case for raw value 14, so
    /// we mint it once. This is the event that carries brightness/volume/mute,
    /// media transport, and the special top-row function keys (subtype 8).
    public static let systemDefinedType = CGEventType(rawValue: 14)!

    // Lookup tables, replaced atomically on update.
    // We use NSLock around access since the callback runs off-main.
    private let lock = NSLock()
    private var hotkeyMacros: [HotkeyKey: Macro] = [:]
    private var chordMacros: [Macro] = []
    /// Macros bound to a system-defined key (NX_KEYTYPE_*), keyed the same way as
    /// `hotkeyMacros` but in the aux-code numbering space.
    private var systemKeyMacros: [HotkeyKey: Macro] = [:]

    /// When set, every key event (standard keyDown *and* system-defined media key)
    /// is diverted to this hook instead of normal macro processing, and swallowed.
    /// The key recorder installs this so it can capture media keys the OS would
    /// otherwise consume before any app sees them. Runs on the tap thread — the
    /// hook is responsible for hopping to the main actor.
    public var captureHook: ((CapturedKey) -> Void)?

    public let chordDetector = ChordDetector()
    public let executor: MacroExecutor
    public let snippetEngine = SnippetEngine()

    /// When false, the tap stays installed but all events pass through untouched.
    public var globallyEnabled: Bool = true

    /// Called on every fired macro for UI feedback (e.g. status bar flash).
    public var onMacroFired: ((Macro) -> Void)?

    /// Called when the tap is disabled by the OS (timeout / user input) and we
    /// need to re-arm it. Internal — not for the host.
    private var enabledMacros: [Macro] = []

    public init(executor: MacroExecutor = MacroExecutor()) {
        self.executor = executor
    }

    // MARK: - Public API

    @discardableResult
    public func start() -> Bool {
        guard eventTap == nil else { return true }

        let mask: CGEventMask =
            (1 << CGEventType.keyDown.rawValue) |
            (1 << CGEventType.flagsChanged.rawValue) |
            (1 << EventTapManager.systemDefinedType.rawValue) |
            (1 << CGEventType.tapDisabledByTimeout.rawValue) |
            (1 << CGEventType.tapDisabledByUserInput.rawValue)

        let opaqueSelf = Unmanaged.passUnretained(self).toOpaque()

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { proxy, type, event, refcon in
                guard let refcon = refcon else { return Unmanaged.passUnretained(event) }
                let manager = Unmanaged<EventTapManager>.fromOpaque(refcon).takeUnretainedValue()
                return manager.handleEvent(proxy: proxy, type: type, event: event)
            },
            userInfo: opaqueSelf
        ) else {
            Logger.shared.error("CGEvent.tapCreate failed — Accessibility permission missing?")
            return false
        }

        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        if let src = runLoopSource {
            CFRunLoopAddSource(CFRunLoopGetCurrent(), src, .commonModes)
        }
        CGEvent.tapEnable(tap: tap, enable: true)
        Logger.shared.info("CGEventTap started")
        return true
    }

    public func stop() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let src = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), src, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil
        Logger.shared.info("CGEventTap stopped")
    }

    public var isRunning: Bool { eventTap != nil }

    /// Rebuilds the lookup tables from the given macros + groups.
    /// Only macros that are enabled and inside enabled groups participate.
    public func updateMacros(macros: [Macro], groups: [MacroGroup]) {
        let groupEnabled: [UUID: Bool] = Dictionary(uniqueKeysWithValues: groups.map { ($0.id, $0.isEnabled) })
        let live = macros.filter { macro in
            guard macro.isEnabled else { return false }
            if let g = macro.groupID, groupEnabled[g] == false { return false }
            return true
        }

        var hot: [HotkeyKey: Macro] = [:]
        var sys: [HotkeyKey: Macro] = [:]
        var chord: [Macro] = []
        for m in live {
            guard let hk = m.hotkey else { continue }
            if m.triggerMode == .chord, hk.chordKey != nil {
                chord.append(m)
            } else if m.triggerMode == .hotkey {
                let key = HotkeyKey(keyCode: hk.keyCode, modifiers: hk.modifiers & Hotkey.modifierMask)
                // System-defined keys live in their own numbering space and are
                // matched off the type-14 event stream, never keyDown.
                if hk.isSystemDefined { sys[key] = m } else { hot[key] = m }
            }
        }

        lock.lock()
        hotkeyMacros = hot
        systemKeyMacros = sys
        chordMacros = chord
        enabledMacros = live
        lock.unlock()
        Logger.shared.debug("EventTap registered \(hot.count) hotkeys, \(sys.count) system keys, \(chord.count) chords")
    }

    public func setChordTimeout(_ ms: Int) {
        chordDetector.timeoutMS = ms
    }

    // MARK: - Lookup helpers (also exposed for testing)

    public struct HotkeyKey: Hashable, Sendable {
        public let keyCode: UInt16
        public let modifiers: UInt64
        public init(keyCode: UInt16, modifiers: UInt64) {
            self.keyCode = keyCode
            self.modifiers = modifiers & Hotkey.modifierMask
        }
    }

    public func lookup(keyCode: UInt16, modifiers: UInt64) -> Macro? {
        lock.lock(); defer { lock.unlock() }
        return hotkeyMacros[HotkeyKey(keyCode: keyCode, modifiers: modifiers)]
    }

    /// Lookup in the system-defined (NX_KEYTYPE_*) table.
    public func lookupSystemKey(keyCode: UInt16, modifiers: UInt64) -> Macro? {
        lock.lock(); defer { lock.unlock() }
        return systemKeyMacros[HotkeyKey(keyCode: keyCode, modifiers: modifiers)]
    }

    /// A key captured by the recorder via `captureHook`.
    public struct CapturedKey: Sendable {
        public let keyType: Hotkey.KeyType
        public let keyCode: UInt16
        public let modifiers: UInt64
    }

    public func chordSnapshot() -> [Macro] {
        lock.lock(); defer { lock.unlock() }
        return chordMacros
    }

    // MARK: - Event handling

    private func handleEvent(
        proxy: CGEventTapProxy,
        type: CGEventType,
        event: CGEvent
    ) -> Unmanaged<CGEvent>? {
        // Re-enable the tap if the OS suspended it.
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = eventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
                Logger.shared.error("Event tap was disabled — re-enabled")
            }
            return Unmanaged.passUnretained(event)
        }

        // Suppress synthetic events we ourselves posted. CGEvent doesn't expose a
        // direct "is synthetic" flag, but events posted via CGEventSourceStateID
        // get a non-zero source UID we can sniff. In practice we tag our own
        // source IDs so handlers can ignore them — but easier: bail out if the
        // event's source-user-data is our magic value.
        let userData = event.getIntegerValueField(.eventSourceUserData)
        if userData == EventTapManager.syntheticUserData {
            return Unmanaged.passUnretained(event)
        }

        // Capture mode: the key recorder is open. Divert every real key — standard
        // and system-defined — to the hook and swallow it, so the user can record
        // a media key without the OS acting on it. Modifier-only (flagsChanged)
        // events pass through so modifiers can be held while choosing the key.
        if let hook = captureHook {
            if type == .keyDown {
                let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
                let modifiers = event.flags.rawValue & Hotkey.modifierMask
                hook(CapturedKey(keyType: .standard, keyCode: keyCode, modifiers: modifiers))
                return nil
            }
            if type == EventTapManager.systemDefinedType {
                if let parsed = Self.parseSystemKey(event), parsed.isDown {
                    hook(CapturedKey(keyType: .systemDefined, keyCode: parsed.keyCode, modifiers: parsed.modifiers))
                }
                return nil  // swallow both down and up while recording
            }
            return Unmanaged.passUnretained(event)
        }

        guard globallyEnabled else { return Unmanaged.passUnretained(event) }

        // System-defined keys (brightness/volume/media/special function keys).
        // If a macro is bound to this key we fire it and swallow BOTH the down and
        // up events — that's what "override the F4 / brightness key" means. Unbound
        // system keys pass straight through so the OS handles them normally.
        if type == EventTapManager.systemDefinedType {
            guard let parsed = Self.parseSystemKey(event) else {
                return Unmanaged.passUnretained(event)
            }
            guard let macro = lookupSystemKey(keyCode: parsed.keyCode, modifiers: parsed.modifiers) else {
                return Unmanaged.passUnretained(event)
            }
            if parsed.isDown && !parsed.isRepeat { fire(macro) }
            return nil
        }

        guard type == .keyDown else { return Unmanaged.passUnretained(event) }

        let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
        let modifiers = event.flags.rawValue & Hotkey.modifierMask

        // 1) Chord detection. If a chord macro starts/completes with this stroke,
        //    swallow the event and possibly fire.
        let chords = chordSnapshot()
        if !chords.isEmpty {
            let outcome = chordDetector.process(keyCode: keyCode, modifiers: modifiers, chordMacros: chords)
            if let firedID = outcome.fired,
               let macro = chords.first(where: { $0.id == firedID }) {
                fire(macro)
                return nil  // suppress
            }
            if outcome.consumed {
                return nil  // suppress (we're armed)
            }
        }

        // 2) Direct hotkey match.
        if let macro = lookup(keyCode: keyCode, modifiers: modifiers) {
            fire(macro)
            return nil  // suppress
        }

        // 3) Snippet engine — observe the keystroke without consuming.
        let hasModifier = (modifiers & (
            CGEventFlags.maskCommand.rawValue |
            CGEventFlags.maskControl.rawValue |
            CGEventFlags.maskAlternate.rawValue
        )) != 0
        if !hasModifier {
            let nsEvent = NSEvent(cgEvent: event)
            let chars = nsEvent?.characters ?? ""
            let isPrintable = !chars.isEmpty && chars.allSatisfy { c in
                !c.isNewline && (c.asciiValue.map { $0 >= 0x20 && $0 != 0x7F } ?? true)
            }
            snippetEngine.processCharacter(chars, isPrintable: isPrintable)
        } else {
            snippetEngine.resetBuffer()
        }

        return Unmanaged.passUnretained(event)
    }

    private func fire(_ macro: Macro) {
        onMacroFired?(macro)
        Task { [executor] in
            await executor.execute(macro)
        }
    }

    /// User-data value tagged onto every CGEvent we post ourselves; lets the tap
    /// avoid feedback loops.
    public static let syntheticUserData: Int64 = 0x4B45_5946_4F52_4745  // "KEYFORGE"

    // MARK: - System-defined event parsing

    struct ParsedSystemKey {
        let keyCode: UInt16   // NX_KEYTYPE_*
        let modifiers: UInt64
        let isDown: Bool
        let isRepeat: Bool
    }

    /// Decode an `NSSystemDefined` (type 14) event into its aux key code + state.
    /// Returns nil for non-aux (subtype != 8) events — e.g. some screen/power
    /// events also ride this stream and must be passed through untouched.
    ///
    /// Layout of `data1` for subtype 8 (from IOKit's NX aux-key convention):
    ///   bits 31..16  key code (NX_KEYTYPE_*)
    ///   bits 15..8   key state nibble: 0xA = down, 0xB = up
    ///   bit  0       repeat flag
    static func parseSystemKey(_ event: CGEvent) -> ParsedSystemKey? {
        guard let ns = NSEvent(cgEvent: event), ns.subtype.rawValue == 8 else { return nil }
        let data1 = ns.data1
        let keyCode = UInt16((data1 >> 16) & 0xFFFF)
        let keyFlags = data1 & 0xFFFF
        let stateNibble = (keyFlags & 0xFF00) >> 8
        let modifiers = event.flags.rawValue & Hotkey.modifierMask
        return ParsedSystemKey(
            keyCode: keyCode,
            modifiers: modifiers,
            isDown: stateNibble == 0xA,
            isRepeat: (keyFlags & 0x1) != 0
        )
    }
}
