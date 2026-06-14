import XCTest
@testable import KeyForge

/// Top-level smoke test: ensures every public type used by the tests can at
/// least be instantiated. Catches build-time regressions in the public surface
/// that the other tests might miss.
final class SmokeTests: XCTestCase {
    func testFundamentalTypesInstantiate() {
        _ = Macro(name: "smoke")
        _ = MacroGroup(name: "smoke")
        _ = Snippet(abbreviation: "x", expansion: "y")
        _ = Hotkey(keyCode: 0, modifiers: 0)
        _ = ConditionCheck.alwaysTrue
    }
}
