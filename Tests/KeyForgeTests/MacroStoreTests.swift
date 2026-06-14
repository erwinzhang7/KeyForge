import XCTest
@testable import KeyForge

final class MacroStoreTests: XCTestCase {

    func makeTempURL() -> URL {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("KeyForgeTests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("macros.json")
    }

    @MainActor
    func testSaveAndReloadThreeMacros() async throws {
        let url = makeTempURL()
        let store = MacroStore(storageURL: url)

        let m1 = Macro(name: "First",
                       hotkey: Hotkey(keyCode: 5, modifiers: 0),
                       actions: [.delay(id: UUID(), milliseconds: 100)])
        let m2 = Macro(name: "Second",
                       actions: [.openURL(id: UUID(), url: "https://example.com")])
        let m3 = Macro(name: "Third",
                       actions: [.shellCommand(id: UUID(), command: "ls", waitForExit: true)])
        store.add(m1)
        store.add(m2)
        store.add(m3)
        store.saveImmediately()

        let reloaded = MacroStore(storageURL: url)
        XCTAssertEqual(reloaded.macros.count, 3)
        XCTAssertEqual(reloaded.macros[0].name, "First")
        XCTAssertEqual(reloaded.macros[1].name, "Second")
        XCTAssertEqual(reloaded.macros[2].name, "Third")
        XCTAssertEqual(reloaded.macros[0].hotkey?.keyCode, 5)
        XCTAssertEqual(reloaded.macros[0].actions.count, 1)
        if case .delay(_, let ms) = reloaded.macros[0].actions[0] {
            XCTAssertEqual(ms, 100)
        } else { XCTFail("Expected delay action") }
    }

    @MainActor
    func testDebouncedSaveEventuallyWrites() async throws {
        let url = makeTempURL()
        let store = MacroStore(storageURL: url)
        store.add(Macro(name: "Debounced"))
        // Wait a bit longer than debounce window.
        try await Task.sleep(nanoseconds: 800_000_000)
        let reloaded = MacroStore(storageURL: url)
        XCTAssertEqual(reloaded.macros.count, 1)
        XCTAssertEqual(reloaded.macros.first?.name, "Debounced")
    }

    @MainActor
    func testDuplicatePreservesActionsWithFreshIDs() {
        let store = MacroStore(storageURL: makeTempURL())
        let orig = Macro(name: "Orig", actions: [.delay(id: UUID(), milliseconds: 50)])
        store.add(orig)
        let copy = store.duplicate(orig.id)
        XCTAssertNotNil(copy)
        XCTAssertNotEqual(copy?.id, orig.id)
        XCTAssertEqual(copy?.actions.count, 1)
        XCTAssertNotEqual(copy?.actions[0].id, orig.actions[0].id)
    }
}
