import XCTest
@testable import KeyForge

final class AppleScriptRunnerTests: XCTestCase {
    func testSimpleStringReturn() {
        let result = AppleScriptRunner.run(source: "return \"ok\"")
        XCTAssertTrue(result.success)
        XCTAssertEqual(result.value, "ok")
    }

    func testInvalidScriptReturnsError() {
        let result = AppleScriptRunner.run(source: "this is not valid applescript")
        XCTAssertFalse(result.success)
        XCTAssertNotNil(result.errorMessage)
    }
}
