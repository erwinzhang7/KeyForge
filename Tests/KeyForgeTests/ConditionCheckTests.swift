import XCTest
@testable import KeyForge

final class ConditionCheckTests: XCTestCase {
    func testAlwaysTrueAndAlwaysFalse() async {
        let t = await MacroExecutor.evaluate(.alwaysTrue)
        let f = await MacroExecutor.evaluate(.alwaysFalse)
        XCTAssertTrue(t)
        XCTAssertFalse(f)
    }

    func testFileExistsWithRealTempFileReturnsTrue() async throws {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("keyforge-condition-\(UUID().uuidString).txt")
        try "x".write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }
        let result = await MacroExecutor.evaluate(.fileExists(path: url.path))
        XCTAssertTrue(result)
    }

    func testFileExistsWithBogusPathReturnsFalse() async {
        let result = await MacroExecutor.evaluate(.fileExists(path: "/nonexistent/path/abcd"))
        XCTAssertFalse(result)
    }

    func testTimeOfDayHonorsCurrentHour() async {
        let hour = Calendar.current.component(.hour, from: Date())
        let within = await MacroExecutor.evaluate(.timeOfDay(startHour: hour, endHour: hour))
        XCTAssertTrue(within)
        let other = (hour + 12) % 24
        let outside = await MacroExecutor.evaluate(.timeOfDay(startHour: other, endHour: other))
        XCTAssertFalse(outside)
    }
}
