import XCTest
@testable import KeyForge

final class ImportExportTests: XCTestCase {

    @MainActor
    func testRoundtripFiveMacrosThroughTempKeyforgeFile() throws {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("rt-\(UUID().uuidString).keyforge")
        defer { try? FileManager.default.removeItem(at: url) }

        let source = MacroStore(storageURL: URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("src-\(UUID().uuidString).json"))

        let group = MacroGroup(name: "RoundtripGroup")
        source.addGroup(group)

        let macros: [Macro] = (1...5).map { i in
            Macro(
                name: "Macro \(i)",
                icon: "bolt",
                hotkey: Hotkey(keyCode: UInt16(i), modifiers: 0),
                actions: [
                    .typeText(id: UUID(), text: "M\(i)", useClipboard: false),
                    .delay(id: UUID(), milliseconds: i * 100),
                    .ifCondition(
                        id: UUID(),
                        condition: .alwaysTrue,
                        thenActions: [.openURL(id: UUID(), url: "https://m\(i)")],
                        elseActions: []
                    )
                ],
                groupID: group.id
            )
        }
        macros.forEach { source.add($0) }

        let data = try source.exportData()
        try data.write(to: url)

        let dest = MacroStore(storageURL: URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("dst-\(UUID().uuidString).json"))
        let read = try Data(contentsOf: url)
        let added = try dest.importData(read, replaceExisting: false)
        XCTAssertEqual(added, 5)
        XCTAssertEqual(dest.macros.count, 5)
        XCTAssertEqual(dest.groups.count, 1)
        XCTAssertEqual(dest.groups.first?.name, "RoundtripGroup")

        for (orig, imported) in zip(source.macros, dest.macros.sorted(by: { $0.name < $1.name })) {
            XCTAssertEqual(orig.name, imported.name)
            XCTAssertEqual(orig.actions.count, imported.actions.count)
        }
    }

    @MainActor
    func testImportingAvoidsDuplicateIDs() throws {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("dup-\(UUID().uuidString).json")
        let store = MacroStore(storageURL: url)
        let m = Macro(name: "Dup")
        store.add(m)
        let exported = try store.exportData()
        // Import the same data again — should not double-up since IDs match.
        let added = try store.importData(exported, replaceExisting: false)
        XCTAssertEqual(added, 0)
        XCTAssertEqual(store.macros.count, 1)
    }
}
