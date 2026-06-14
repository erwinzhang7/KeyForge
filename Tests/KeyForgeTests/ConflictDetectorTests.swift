import XCTest
import CoreGraphics
@testable import KeyForge

final class ConflictDetectorTests: XCTestCase {
    private let cmd = CGEventFlags.maskCommand.rawValue
    private let opt = CGEventFlags.maskAlternate.rawValue
    private let ctrl = CGEventFlags.maskControl.rawValue
    private let shift = CGEventFlags.maskShift.rawValue

    func testSpotlightShortcutIsSystemConflict() {
        let candidate = Hotkey(keyCode: 49, modifiers: cmd)  // ⌘Space
        let result = ConflictDetector.check(candidate: candidate, against: [], strict: true)
        if case .systemConflict(let desc) = result {
            XCTAssertFalse(desc.isEmpty)
        } else {
            XCTFail("Expected systemConflict, got \(result)")
        }
    }

    func testUnusedExoticComboHasNoConflict() {
        let candidate = Hotkey(keyCode: 111, modifiers: cmd | opt | ctrl | shift)  // ⌘⌥⌃⇧F12
        let result = ConflictDetector.check(candidate: candidate, against: [], strict: true)
        XCTAssertEqual(result, .noConflict)
    }

    func testUserConflictFlaggedWhenAnotherMacroUsesSameCombo() {
        let combo = Hotkey(keyCode: 17, modifiers: cmd | opt)  // ⌘⌥T
        let existing = Macro(name: "Existing", hotkey: combo)
        let result = ConflictDetector.check(candidate: combo, against: [existing], strict: false)
        if case .userConflict(let name, let mid) = result {
            XCTAssertEqual(name, "Existing")
            XCTAssertEqual(mid, existing.id)
        } else {
            XCTFail("Expected userConflict, got \(result)")
        }
    }

    func testExcludingCurrentMacroAvoidsSelfConflict() {
        let combo = Hotkey(keyCode: 17, modifiers: cmd | opt)
        let existing = Macro(name: "Self", hotkey: combo)
        let result = ConflictDetector.check(
            candidate: combo,
            against: [existing],
            excludeMacroID: existing.id,
            strict: false
        )
        XCTAssertEqual(result, .noConflict)
    }
}
