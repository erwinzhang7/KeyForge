import XCTest
@testable import KeyForge

final class ShellRunnerTests: XCTestCase {
    func testEchoReturnsExpectedStdout() {
        let result = ShellRunner.run(command: "echo 'keyforge_test'", waitForExit: true, timeout: 5)
        XCTAssertEqual(result.exitCode, 0)
        XCTAssertTrue(result.stdout.contains("keyforge_test"))
        XCTAssertFalse(result.didTimeout)
    }

    func testNonZeroExitCodeIsReported() {
        let result = ShellRunner.run(command: "exit 7", waitForExit: true, timeout: 5)
        XCTAssertEqual(result.exitCode, 7)
    }

    func testFireAndForgetDoesNotBlock() {
        let start = Date()
        let result = ShellRunner.run(command: "sleep 5", waitForExit: false, timeout: 5)
        XCTAssertLessThan(Date().timeIntervalSince(start), 1.0)
        XCTAssertEqual(result.exitCode, -1)  // no exit info when not awaited
    }
}
