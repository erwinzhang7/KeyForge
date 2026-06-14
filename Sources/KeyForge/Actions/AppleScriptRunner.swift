import Foundation
import AppKit

public struct AppleScriptResult: Sendable {
    public let success: Bool
    public let value: String
    public let errorMessage: String?
}

public enum AppleScriptRunner {
    /// Executes the given AppleScript source. Returns the script's return value
    /// (string-coerced) or an error.
    public static func run(source: String) -> AppleScriptResult {
        // NSAppleScript is fine off-main as long as we don't share script instances.
        guard let script = NSAppleScript(source: source) else {
            return AppleScriptResult(success: false, value: "", errorMessage: "Failed to compile script")
        }
        var error: NSDictionary?
        let descriptor = script.executeAndReturnError(&error)
        if let error = error {
            let msg = error[NSAppleScript.errorMessage] as? String ?? "Unknown AppleScript error"
            return AppleScriptResult(success: false, value: "", errorMessage: msg)
        }
        let value = descriptor.stringValue ?? ""
        return AppleScriptResult(success: true, value: value, errorMessage: nil)
    }
}
