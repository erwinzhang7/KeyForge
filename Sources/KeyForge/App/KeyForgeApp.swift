import SwiftUI
import AppKit

@main
struct KeyForgeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        Settings {
            SettingsView(store: delegate.store)
        }
    }
}
