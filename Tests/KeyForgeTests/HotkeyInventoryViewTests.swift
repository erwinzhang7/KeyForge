import XCTest
import CoreGraphics
@testable import KeyForge

/// Covers the "All Hotkeys" row model: the search haystack (so spelled-out
/// modifier names match glyph combos) and the keycap tokenizer.
final class HotkeyInventoryViewTests: XCTestCase {

    private func row(_ combo: String, _ title: String = "Some action") -> HotkeyRow {
        HotkeyRow(id: "t", combo: combo, title: title, source: .system, isEnabled: true)
    }

    func testSearchTextExpandsModifierGlyphsToWords() {
        let r = row("⇧⌘3", "Screenshot: save picture of screen as a file")
        let hay = r.searchText
        // Glyphs are aliased to both long and short spellings.
        XCTAssertTrue(hay.contains("command"))
        XCTAssertTrue(hay.contains("cmd"))
        XCTAssertTrue(hay.contains("shift"))
        // Title is searchable too.
        XCTAssertTrue(hay.contains("screenshot"))
        // Modifiers NOT present should not be aliased in.
        XCTAssertFalse(hay.contains("control"))
        XCTAssertFalse(hay.contains("option"))
    }

    func testMultiTokenSearchMatchesGlyphCombo() {
        // Simulates the view's AND-across-tokens filter for query "cmd shift".
        let r = row("⇧⌘3")
        let tokens = "cmd shift".split(separator: " ").map(String.init)
        XCTAssertTrue(tokens.allSatisfy { r.searchText.contains($0) })

        // "ctrl space" must NOT match a ⇧⌘3 row.
        let miss = "ctrl space".split(separator: " ").map(String.init)
        XCTAssertFalse(miss.allSatisfy { r.searchText.contains($0) })
    }

    func testOptionAliasesCoverAltAndOpt() {
        let hay = row("⌥Space").searchText
        XCTAssertTrue(hay.contains("option"))
        XCTAssertTrue(hay.contains("alt"))
        XCTAssertTrue(hay.contains("opt"))
    }

    func testKeycapsSplitModifiersFromKey() {
        XCTAssertEqual(row("⇧⌘3").keycaps, ["⇧", "⌘", "3"])
        XCTAssertEqual(row("⌃⌥Space").keycaps, ["⌃", "⌥", "Space"])
        XCTAssertEqual(row("K").keycaps, ["K"])
    }

    func testKeycapsHandleFnPrefixAndEmpty() {
        XCTAssertEqual(row("fn F4").keycaps, ["fn", "F4"])
        XCTAssertTrue(row("").keycaps.isEmpty)
    }

    func testNormalizedComboKeyIsOrderIndependent() {
        // Same modifiers + key collapse to the same key regardless of glyph order.
        XCTAssertEqual(row("⇧⌘3").normalizedComboKey, row("⌘⇧3").normalizedComboKey)
        // Different key -> different normalized form.
        XCTAssertNotEqual(row("⇧⌘3").normalizedComboKey, row("⇧⌘4").normalizedComboKey)
        // Different modifier set -> different form.
        XCTAssertNotEqual(row("⇧⌘3").normalizedComboKey, row("⌘3").normalizedComboKey)
    }

    func testNormalizedComboKeyHandlesFnAndEmpty() {
        XCTAssertNil(row("").normalizedComboKey)
        // The fn "layer" flag must NOT affect matching — the same physical key
        // reports fn set or not depending on keyboard settings.
        XCTAssertEqual(row("fn F4").normalizedComboKey, row("F4").normalizedComboKey)
        XCTAssertEqual(row("fn Spotlight").normalizedComboKey, row("Spotlight").normalizedComboKey)
    }

    func testKeyForgeRowCarriesMacroIDForJump() {
        let id = UUID()
        let r = HotkeyRow(id: "kf-\(id)", combo: "⌘K", title: "M", source: .keyforge, isEnabled: true, macroID: id)
        XCTAssertEqual(r.macroID, id)
        // System rows have no macro to jump to.
        XCTAssertNil(row("⌘Space").macroID)
    }

    func testConflictingCombosShareNormalizedKey() {
        // A KeyForge macro on ⇧⌘3 collides with the macOS screenshot shortcut.
        let kf = HotkeyRow(id: "kf-1", combo: Hotkey(keyCode: 20, modifiers:
            CGEventFlags.maskShift.rawValue | CGEventFlags.maskCommand.rawValue).displayString,
            title: "My macro", source: .keyforge, isEnabled: true, macroID: UUID())
        let sys = row("⇧⌘3", "Screenshot")
        XCTAssertEqual(kf.normalizedComboKey, sys.normalizedComboKey)
    }

    func testHardwareCatalogCoversMediaAndFnRowKeys() {
        let names = HardwareKeyCatalog.all.map { $0.hotkey.displayString }
        XCTAssertTrue(names.contains("Brightness Up"))
        XCTAssertTrue(names.contains("Volume Down"))
        XCTAssertTrue(names.contains("Spotlight"))   // keycode 177
        XCTAssertTrue(names.contains("Dictation"))   // keycode 176
    }

    func testPressingBrightnessResolvesToCatalogEntry() {
        // A captured brightness-up press must match the catalog row for it.
        let pressed = Hotkey(keyCode: SystemKeyMap.brightnessUp, modifiers: 0, keyType: .systemDefined)
        let pressedKey = row(pressed.displayString).normalizedComboKey

        let catalogKeys = HardwareKeyCatalog.all.map {
            row($0.hotkey.displayString).normalizedComboKey
        }
        XCTAssertTrue(catalogKeys.contains(pressedKey))
    }

    func testFnSpotlightPressResolvesToCatalogSpotlight() {
        // F4/Spotlight arrives as keycode 177 with the fn flag; it must match the
        // catalog Spotlight entry (keycode 177, no fn) despite the fn difference.
        let fn = CGEventFlags.maskSecondaryFn.rawValue
        let pressed = Hotkey(keyCode: 177, modifiers: fn, keyType: .standard)
        let catalog = Hotkey(keyCode: 177, modifiers: 0, keyType: .standard)
        XCTAssertEqual(row(pressed.displayString).normalizedComboKey,
                       row(catalog.displayString).normalizedComboKey)
    }

    func testSystemDefinedComboFlowsThroughRow() {
        // A bound brightness key renders as a single labeled keycap.
        let hk = Hotkey(keyCode: SystemKeyMap.brightnessUp, modifiers: 0, keyType: .systemDefined)
        let r = row(hk.displayString, "Dim screen")
        XCTAssertEqual(r.keycaps, ["Brightness Up"])
        XCTAssertTrue(r.searchText.contains("brightness up"))
    }
}
