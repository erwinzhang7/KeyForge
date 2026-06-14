import XCTest
@testable import KeyForge

final class MacroActionCodableTests: XCTestCase {

    func roundtrip(_ action: MacroAction, file: StaticString = #file, line: UInt = #line) {
        do {
            let encoder = JSONEncoder()
            let data = try encoder.encode(action)
            let decoded = try JSONDecoder().decode(MacroAction.self, from: data)
            XCTAssertEqual(action, decoded, "Failed roundtrip for \(action.displayName)", file: file, line: line)
        } catch {
            XCTFail("Codable error for \(action.displayName): \(error)", file: file, line: line)
        }
    }

    func testAllTwelveActionTypesRoundtrip() {
        let id = UUID()
        roundtrip(.launchApp(id: id, bundleID: "com.apple.Safari"))
        roundtrip(.openURL(id: id, url: "https://example.com"))
        roundtrip(.typeText(id: id, text: "hello world", useClipboard: true))
        roundtrip(.shellCommand(id: id, command: "echo hi", waitForExit: true))
        roundtrip(.appleScript(id: id, source: "return 1"))
        roundtrip(.delay(id: id, milliseconds: 250))
        roundtrip(.keyPress(id: id, keyCode: 9, modifiers: 0x100000))
        roundtrip(.mediaControl(id: id, action: .playPause))
        roundtrip(.focusApp(id: id, bundleID: "com.apple.Terminal"))
        roundtrip(.openFile(id: id, path: "/tmp/x"))
        roundtrip(.notification(id: id, title: "T", body: "B"))
        roundtrip(.ifCondition(
            id: id,
            condition: .alwaysTrue,
            thenActions: [.delay(id: UUID(), milliseconds: 100)],
            elseActions: [.openURL(id: UUID(), url: "https://no.example")]
        ))
    }

    func testIDsArePreservedAcrossRoundtrip() throws {
        let id = UUID()
        let action: MacroAction = .typeText(id: id, text: "preserve", useClipboard: false)
        let data = try JSONEncoder().encode(action)
        let decoded = try JSONDecoder().decode(MacroAction.self, from: data)
        XCTAssertEqual(decoded.id, id)
    }
}
