import Foundation
import ApplicationServices
import AppKit

/// Wraps the macOS Accessibility ("AX") permission API.
/// The engine cannot install its CGEventTap without this permission, so we re-check
/// every 2s while the app is running and surface state to the UI.
public final class AccessibilityHelper: ObservableObject, @unchecked Sendable {
    public static let shared = AccessibilityHelper()

    @Published public private(set) var isTrusted: Bool = false

    private var pollTimer: Timer?

    private init() {
        refresh()
    }

    /// Returns true if the process has Accessibility permission.
    /// Does NOT prompt — use `requestTrust()` to prompt the user.
    @discardableResult
    public func refresh() -> Bool {
        let trusted = AXIsProcessTrusted()
        DispatchQueue.main.async { [weak self] in
            self?.isTrusted = trusted
        }
        return trusted
    }

    /// Prompts the user (via the system dialog) for accessibility permission.
    /// The dialog only appears the first time; subsequent calls just return current state.
    @discardableResult
    public func requestTrust() -> Bool {
        let key = "AXTrustedCheckOptionPrompt" as CFString
        let options: CFDictionary = [key: true] as CFDictionary
        let result = AXIsProcessTrustedWithOptions(options)
        DispatchQueue.main.async { [weak self] in
            self?.isTrusted = result
        }
        return result
    }

    /// Open the Privacy & Security → Accessibility settings panel directly.
    public func openSystemSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }

    /// Begin polling AX permission status every 2 seconds. UI binds to `isTrusted`.
    public func startPolling() {
        stopPolling()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.refresh()
        }
        RunLoop.main.add(pollTimer!, forMode: .common)
    }

    public func stopPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
    }
}
