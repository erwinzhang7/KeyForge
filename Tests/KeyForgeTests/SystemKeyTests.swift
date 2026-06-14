import XCTest
import CoreGraphics
import AppKit
@testable import KeyForge

/// Covers the system-defined (brightness/volume/media/special-function) key path:
/// model back-compat, naming, engine routing, raw NSSystemDefined parsing, and
/// the symbolichotkeys inventory parser.
final class SystemKeyTests: XCTestCase {

    private let cmd = CGEventFlags.maskCommand.rawValue

    // MARK: - Model back-compat

    func testLegacyHotkeyJSONWithoutKeyTypeDecodesAsStandard() throws {
        // A hotkey written before keyType existed — the field is simply absent.
        let json = #"{"keyCode": 3, "modifiers": 0}"#.data(using: .utf8)!
        let hk = try JSONDecoder().decode(Hotkey.self, from: json)
        XCTAssertEqual(hk.keyCode, 3)
        XCTAssertEqual(hk.keyType, .standard)
        XCTAssertFalse(hk.isSystemDefined)
    }

    func testSystemKeyHotkeyRoundtrips() throws {
        let hk = Hotkey(keyCode: SystemKeyMap.brightnessUp, modifiers: cmd, keyType: .systemDefined)
        let data = try JSONEncoder().encode(hk)
        let back = try JSONDecoder().decode(Hotkey.self, from: data)
        XCTAssertEqual(back, hk)
        XCTAssertEqual(back.keyType, .systemDefined)
        XCTAssertTrue(back.isSystemDefined)
    }

    func testSystemKeyDisplayStringUsesSystemNames() {
        let hk = Hotkey(keyCode: SystemKeyMap.brightnessUp, modifiers: 0, keyType: .systemDefined)
        XCTAssertEqual(hk.displayString, "Brightness Up")
        // Same numeric code as a standard key would render very differently.
        let standard = Hotkey(keyCode: SystemKeyMap.brightnessUp, modifiers: 0, keyType: .standard)
        XCTAssertEqual(standard.displayString, "D")  // virtual key 2 == 'D'
    }

    func testSystemKeyNamesCoverKnownSet() {
        XCTAssertEqual(SystemKeyMap.name(for: SystemKeyMap.mute), "Mute")
        XCTAssertEqual(SystemKeyMap.name(for: SystemKeyMap.play), "Play/Pause")
        XCTAssertEqual(SystemKeyMap.name(for: SystemKeyMap.soundDown), "Volume Down")
        XCTAssertFalse(SystemKeyMap.known.isEmpty)
    }

    // MARK: - Engine routing

    @MainActor
    func testSystemKeyMacroRoutesToSeparateTableNotStandardTable() {
        let tap = EventTapManager(executor: MacroExecutor())
        let media = Macro(name: "Bright",
                          hotkey: Hotkey(keyCode: SystemKeyMap.brightnessUp, modifiers: 0, keyType: .systemDefined))
        let normal = Macro(name: "PlainD",
                           hotkey: Hotkey(keyCode: 2, modifiers: cmd))  // ⌘D, standard
        tap.updateMacros(macros: [media, normal], groups: [])

        // System key only resolves via the system table.
        XCTAssertEqual(tap.lookupSystemKey(keyCode: SystemKeyMap.brightnessUp, modifiers: 0)?.id, media.id)
        XCTAssertNil(tap.lookup(keyCode: SystemKeyMap.brightnessUp, modifiers: 0))

        // Standard key only resolves via the standard table.
        XCTAssertEqual(tap.lookup(keyCode: 2, modifiers: cmd)?.id, normal.id)
        XCTAssertNil(tap.lookupSystemKey(keyCode: 2, modifiers: cmd))
    }

    // MARK: - Raw NSSystemDefined parsing

    func testParseSystemKeyDecodesAuxKeyDown() throws {
        // Encode an aux brightness-up key-down: keyCode in the high word,
        // state nibble 0xA (down) in bits 15..8.
        let keyCode = Int(SystemKeyMap.brightnessUp)
        let data1 = (keyCode << 16) | (0xA << 8)
        guard let ns = NSEvent.otherEvent(
            with: .systemDefined,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            subtype: 8,
            data1: data1,
            data2: -1
        ), let cg = ns.cgEvent else {
            throw XCTSkip("Cannot synthesize a systemDefined CGEvent in this environment")
        }

        let parsed = try XCTUnwrap(EventTapManager.parseSystemKey(cg))
        XCTAssertEqual(parsed.keyCode, SystemKeyMap.brightnessUp)
        XCTAssertTrue(parsed.isDown)
        XCTAssertFalse(parsed.isRepeat)
    }

    // MARK: - symbolichotkeys inventory

    func testInventoryParsesEnabledStateComboAndName() {
        // Mirrors the real plist shape: parameters = [ascii, keyCode, cocoaModifiers].
        let fixture: [String: Any] = [
            "64": ["enabled": true,
                   "value": ["type": "standard",
                             "parameters": [32, 49, 1048576]]],   // ⌘ + Space
            "32": ["enabled": false,
                   "value": ["type": "standard",
                             "parameters": [65535, 65535, 0]]],    // no real combo
        ]
        let records = SystemHotkeyInventory.parse(fixture)
        XCTAssertEqual(records.count, 2)

        let spotlight = try? XCTUnwrap(records.first { $0.id == 64 })
        XCTAssertEqual(spotlight?.name, "Spotlight: show search")
        XCTAssertEqual(spotlight?.combo, "⌘Space")
        XCTAssertEqual(spotlight?.isEnabled, true)

        let mission = records.first { $0.id == 32 }
        XCTAssertEqual(mission?.isEnabled, false)
        XCTAssertEqual(mission?.combo, "")  // 0xFFFF sentinels -> empty
    }

    func testInventoryComboFormatsModifierOrder() {
        // ⌃⌥⇧⌘ glyph order, screenshot ⌘⇧3 style.
        XCTAssertEqual(
            SystemHotkeyInventory.comboString(ascii: 51, keyCode: 20, cocoaModifiers: 1179648),
            "⇧⌘3"
        )
    }
}
