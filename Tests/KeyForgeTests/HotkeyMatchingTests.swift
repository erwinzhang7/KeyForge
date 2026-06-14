import XCTest
import CoreGraphics
@testable import KeyForge

final class HotkeyMatchingTests: XCTestCase {

    private let cmd = CGEventFlags.maskCommand.rawValue
    private let opt = CGEventFlags.maskAlternate.rawValue
    private let shift = CGEventFlags.maskShift.rawValue

    @MainActor
    func testThreeRegisteredHotkeysReturnCorrectMacros() async throws {
        let tap = EventTapManager(executor: MacroExecutor())
        let m1 = Macro(name: "M1", hotkey: Hotkey(keyCode: 9, modifiers: cmd))  // ⌘V
        let m2 = Macro(name: "M2", hotkey: Hotkey(keyCode: 12, modifiers: cmd | opt))  // ⌘⌥Q
        let m3 = Macro(name: "M3", hotkey: Hotkey(keyCode: 40, modifiers: cmd | opt | shift))  // ⌘⌥⇧K

        tap.updateMacros(macros: [m1, m2, m3], groups: [])

        XCTAssertEqual(tap.lookup(keyCode: 9, modifiers: cmd)?.id, m1.id)
        XCTAssertEqual(tap.lookup(keyCode: 12, modifiers: cmd | opt)?.id, m2.id)
        XCTAssertEqual(tap.lookup(keyCode: 40, modifiers: cmd | opt | shift)?.id, m3.id)
    }

    @MainActor
    func testNoFalsePositivesForUnregisteredCombos() async throws {
        let tap = EventTapManager(executor: MacroExecutor())
        let m = Macro(name: "M", hotkey: Hotkey(keyCode: 9, modifiers: cmd))
        tap.updateMacros(macros: [m], groups: [])
        XCTAssertNil(tap.lookup(keyCode: 9, modifiers: 0))                  // plain V
        XCTAssertNil(tap.lookup(keyCode: 9, modifiers: cmd | shift))        // ⌘⇧V
        XCTAssertNil(tap.lookup(keyCode: 10, modifiers: cmd))               // ⌘ on a different key
    }

    @MainActor
    func testFnRowKeyOverrideMatchesRegardlessOfFnFlag() async throws {
        // A macro bound to F4/Spotlight (keycode 177). The real key press carries
        // the fn flag; the binding stores none. They must still match, because fn
        // is excluded from the matching mask.
        let fn = CGEventFlags.maskSecondaryFn.rawValue
        let tap = EventTapManager(executor: MacroExecutor())
        let m = Macro(name: "Mosaic", hotkey: Hotkey(keyCode: 177, modifiers: 0, keyType: .standard))
        tap.updateMacros(macros: [m], groups: [])

        // Pressing F4 (fn + 177) resolves to the macro via the standard table.
        XCTAssertEqual(tap.lookup(keyCode: 177, modifiers: fn)?.id, m.id)
        XCTAssertEqual(tap.lookup(keyCode: 177, modifiers: 0)?.id, m.id)
        // It does NOT leak into the system-defined table.
        XCTAssertNil(tap.lookupSystemKey(keyCode: 177, modifiers: 0))
    }

    @MainActor
    func testDisabledMacroIsNotRegistered() async throws {
        let tap = EventTapManager(executor: MacroExecutor())
        var m = Macro(name: "Off", hotkey: Hotkey(keyCode: 9, modifiers: cmd))
        m.isEnabled = false
        tap.updateMacros(macros: [m], groups: [])
        XCTAssertNil(tap.lookup(keyCode: 9, modifiers: cmd))
    }

    @MainActor
    func testGroupDisableRemovesAllItsHotkeys() async throws {
        let tap = EventTapManager(executor: MacroExecutor())
        let g = MacroGroup(name: "G", isEnabled: false)
        let m = Macro(name: "M", hotkey: Hotkey(keyCode: 9, modifiers: cmd), groupID: g.id)
        tap.updateMacros(macros: [m], groups: [g])
        XCTAssertNil(tap.lookup(keyCode: 9, modifiers: cmd))
    }
}
