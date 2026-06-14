import XCTest
@testable import KeyForge

final class SnippetEngineTests: XCTestCase {
    func testEmExpandsAndProducesBackspaces() {
        let engine = SnippetEngine(mockMode: true)
        engine.updateSnippets([Snippet(abbreviation: ";em", expansion: "erwin@example.com")])

        // Feed ; e m one at a time.
        XCTAssertFalse(engine.processCharacter(";", isPrintable: true))
        XCTAssertFalse(engine.processCharacter("e", isPrintable: true))
        XCTAssertTrue(engine.processCharacter("m", isPrintable: true))

        XCTAssertEqual(engine.expansionsTriggered.count, 1)
        XCTAssertEqual(engine.expansionsTriggered.first?.abbreviation, ";em")
        XCTAssertEqual(engine.expansionsTriggered.first?.expansion, "erwin@example.com")

        // Backspace events: 3 (one per char of ";em") × (down+up) = 6
        let bs = engine.snapshotEvents().filter { $0.keyCode == 51 }
        XCTAssertEqual(bs.count, 6)
    }

    func testNonPrintableResetsBuffer() {
        let engine = SnippetEngine(mockMode: true)
        engine.updateSnippets([Snippet(abbreviation: ";em", expansion: "x")])
        _ = engine.processCharacter(";", isPrintable: true)
        _ = engine.processCharacter("", isPrintable: false)  // arrow key, e.g.
        _ = engine.processCharacter("e", isPrintable: true)
        _ = engine.processCharacter("m", isPrintable: true)
        // Buffer reset by non-printable means we did NOT see the full ";em" sequence.
        XCTAssertEqual(engine.expansionsTriggered.count, 0)
    }

    func testDisabledSnippetEngineNoOps() {
        let engine = SnippetEngine(mockMode: true)
        engine.isEnabled = false
        engine.updateSnippets([Snippet(abbreviation: "x", expansion: "y")])
        _ = engine.processCharacter("x", isPrintable: true)
        XCTAssertEqual(engine.expansionsTriggered.count, 0)
    }
}
