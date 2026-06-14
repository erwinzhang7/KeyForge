import Foundation
import SwiftUI
import Combine

/// Centralized @AppStorage-backed user preferences. Observed across the app.
public final class AppSettings: ObservableObject {
    public static let shared = AppSettings()

    @AppStorage("globalHotkeysEnabled") public var globalHotkeysEnabled: Bool = true
    @AppStorage("snippetsEnabled") public var snippetsEnabled: Bool = true
    @AppStorage("launchAtLogin") public var launchAtLogin: Bool = false
    @AppStorage("chordTimeoutMS") public var chordTimeoutMS: Int = 500
    @AppStorage("actionTimeoutMS") public var actionTimeoutMS: Int = 10_000
    @AppStorage("conflictDetectionStrict") public var conflictDetectionStrict: Bool = true
    @AppStorage("logLevelRaw") public var logLevelRaw: String = LogLevel.errors.rawValue
    @AppStorage("hasCompletedOnboarding") public var hasCompletedOnboarding: Bool = false

    public var logLevel: LogLevel {
        get { LogLevel(rawValue: logLevelRaw) ?? .errors }
        set {
            logLevelRaw = newValue.rawValue
            Logger.shared.level = newValue
        }
    }

    private init() {
        Logger.shared.level = logLevel
    }
}
