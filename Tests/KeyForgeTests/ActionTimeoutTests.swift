import XCTest
@testable import KeyForge

final class ActionTimeoutTests: XCTestCase {
    func testLongRunningShellTimesOutWithinTwoSeconds() async {
        let executor = MacroExecutor(actionTimeoutSeconds: 1.0)
        let macro = Macro(
            name: "LongShell",
            actions: [.shellCommand(id: UUID(), command: "sleep 30", waitForExit: true)]
        )
        let start = Date()
        await executor.execute(macro)
        let elapsed = Date().timeIntervalSince(start)
        XCTAssertLessThan(elapsed, 2.0, "Macro execution should be interrupted by timeout")
    }

    func testDelayShorterThanTimeoutCompletesNormally() async {
        let executor = MacroExecutor(actionTimeoutSeconds: 5.0)
        let macro = Macro(
            name: "Short",
            actions: [.delay(id: UUID(), milliseconds: 200)]
        )
        let start = Date()
        await executor.execute(macro)
        let elapsed = Date().timeIntervalSince(start)
        XCTAssertGreaterThanOrEqual(elapsed, 0.18)
        XCTAssertLessThan(elapsed, 1.0)
    }
}
