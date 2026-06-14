import XCTest
@testable import KeyForge

final class TextTyperTests: XCTestCase {
    func testTypingHelloGenerates10Events() {
        let typer = TextTyper(mockMode: true)
        typer.type("hello", useClipboard: false)
        // 5 chars × (down + up) = 10 events.
        XCTAssertEqual(typer.recordedEvents.count, 10)
        // Alternating down/up.
        let kinds = typer.recordedEvents.map(\.kind)
        XCTAssertEqual(kinds.filter { $0 == .down }.count, 5)
        XCTAssertEqual(kinds.filter { $0 == .up }.count, 5)
        // The first down should be 'h' = keyCode 4.
        XCTAssertEqual(typer.recordedEvents[0].keyCode, 4)
    }

    func testClipboardModePostsSingleCmdV() {
        let typer = TextTyper(mockMode: true)
        typer.type("hello world this is a long string", useClipboard: true)
        XCTAssertEqual(typer.recordedEvents.count, 2)
        XCTAssertEqual(typer.recordedEvents[0].keyCode, 9)  // V
        XCTAssertEqual(typer.recordedEvents[0].modifiers, 1 << 20)  // ⌘
    }

    func testBackspaceCount() {
        let typer = TextTyper(mockMode: true)
        typer.sendBackspace(count: 3)
        XCTAssertEqual(typer.recordedEvents.count, 6)
        for e in typer.recordedEvents {
            XCTAssertEqual(e.keyCode, 51)  // backspace
        }
    }
}
