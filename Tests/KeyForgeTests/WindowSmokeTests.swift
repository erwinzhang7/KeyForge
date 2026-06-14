import XCTest
import AppKit
import SwiftUI
@testable import KeyForge

final class WindowSmokeTests: XCTestCase {
    @MainActor
    func testInstantiatingMainWindowDoesNotCrashAndHasNonZeroFrame() {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("smoke-\(UUID().uuidString).json")
        let store = MacroStore(storageURL: url)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 480),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: true
        )
        let content = MainWindow(store: store)
        let hosting = NSHostingView(rootView: content)
        window.contentView = hosting
        // Sanity: frame is non-zero and view layout produces an actual view tree.
        XCTAssertGreaterThan(window.frame.width, 0)
        XCTAssertGreaterThan(window.frame.height, 0)
        XCTAssertNotNil(window.contentView)
    }
}
