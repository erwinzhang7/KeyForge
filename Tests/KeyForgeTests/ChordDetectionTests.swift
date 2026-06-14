import XCTest
import CoreGraphics
@testable import KeyForge

final class ChordDetectionTests: XCTestCase {

    func testChordFiresIfSecondKeyIsWithinTimeout() {
        let detector = ChordDetector(timeoutMS: 500)
        var now = Date(timeIntervalSince1970: 1_000_000)
        detector.nowProvider = { now }

        let mods: UInt64 = CGEventFlags.maskCommand.rawValue
        let macro = Macro(
            name: "GT",
            hotkey: Hotkey(keyCode: 5 /* G */, modifiers: mods, chordKey: 17 /* T */),
            triggerMode: .chord
        )

        // First key: leader G (with ⌘).
        let r1 = detector.process(keyCode: 5, modifiers: mods, chordMacros: [macro])
        XCTAssertTrue(r1.consumed)
        XCTAssertNil(r1.fired)

        // Advance 200ms; press T.
        now = now.addingTimeInterval(0.2)
        let r2 = detector.process(keyCode: 17, modifiers: 0, chordMacros: [macro])
        XCTAssertTrue(r2.consumed)
        XCTAssertEqual(r2.fired, macro.id)
    }

    func testChordDoesNotFireAfterTimeout() {
        let detector = ChordDetector(timeoutMS: 500)
        var now = Date(timeIntervalSince1970: 1_000_000)
        detector.nowProvider = { now }

        let mods: UInt64 = CGEventFlags.maskCommand.rawValue
        let macro = Macro(
            name: "GT",
            hotkey: Hotkey(keyCode: 5, modifiers: mods, chordKey: 17),
            triggerMode: .chord
        )

        _ = detector.process(keyCode: 5, modifiers: mods, chordMacros: [macro])
        // Advance 600ms — past the timeout.
        now = now.addingTimeInterval(0.6)
        let r = detector.process(keyCode: 17, modifiers: 0, chordMacros: [macro])
        XCTAssertFalse(r.consumed)
        XCTAssertNil(r.fired)
    }

    func testNonMatchingSecondKeyResetsDetector() {
        let detector = ChordDetector(timeoutMS: 500)
        let mods: UInt64 = CGEventFlags.maskCommand.rawValue
        let macro = Macro(
            name: "GT",
            hotkey: Hotkey(keyCode: 5, modifiers: mods, chordKey: 17),
            triggerMode: .chord
        )
        _ = detector.process(keyCode: 5, modifiers: mods, chordMacros: [macro])
        XCTAssertTrue(detector.isArmed)
        let r = detector.process(keyCode: 99, modifiers: 0, chordMacros: [macro])
        XCTAssertFalse(r.consumed)
        XCTAssertFalse(detector.isArmed)
    }
}
