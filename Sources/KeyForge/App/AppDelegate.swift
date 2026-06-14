import Foundation
import AppKit
import SwiftUI
import Combine
import UniformTypeIdentifiers

/// AppDelegate owns the long-lived singletons: the macro store, the engine,
/// and the UI windows. It also installs the menu bar status item.
@MainActor
public final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    public let store: MacroStore
    public let settings = AppSettings.shared

    public private(set) var statusItem: NSStatusItem?
    public private(set) var mainWindow: NSWindow?
    public private(set) var windowController: NSWindowController?

    private var cancellables: Set<AnyCancellable> = []
    private var hotkeyEnabledObserver: NSKeyValueObservation?

    public override init() {
        self.store = MacroStore()
        super.init()
    }

    // MARK: - NSApplicationDelegate

    public func applicationWillFinishLaunching(_ notification: Notification) {
        // No dock icon; the status item is our face.
        NSApp.setActivationPolicy(.accessory)
    }

    public func applicationDidFinishLaunching(_ notification: Notification) {
        Logger.shared.info("KeyForge starting up")
        installStatusItem()
        // Start engine
        EventTapManager.shared.setChordTimeout(settings.chordTimeoutMS)
        EventTapManager.shared.updateMacros(macros: store.macros, groups: store.groups)
        EventTapManager.shared.snippetEngine.updateSnippets(store.snippets)
        EventTapManager.shared.globallyEnabled = settings.globalHotkeysEnabled

        // Refresh AX status, start polling.
        AccessibilityHelper.shared.refresh()
        AccessibilityHelper.shared.startPolling()
        // Try to start tap; if AX missing it'll fail and we'll retry on poll.
        if AccessibilityHelper.shared.isTrusted {
            EventTapManager.shared.start()
        }

        // Update engine action timeout.
        Task { @MainActor in
            await EventTapManager.shared.executor.setTimeout(Double(settings.actionTimeoutMS) / 1000.0)
        }

        // Observe store changes and push them to the engine.
        store.$macros
            .combineLatest(store.$groups)
            .receive(on: DispatchQueue.main)
            .sink { macros, groups in
                EventTapManager.shared.updateMacros(macros: macros, groups: groups)
            }
            .store(in: &cancellables)

        store.$snippets
            .receive(on: DispatchQueue.main)
            .sink { snippets in
                EventTapManager.shared.snippetEngine.updateSnippets(snippets)
            }
            .store(in: &cancellables)

        // Re-start tap when AX permission flips on.
        AccessibilityHelper.shared.$isTrusted
            .removeDuplicates()
            .sink { trusted in
                if trusted && !EventTapManager.shared.isRunning {
                    EventTapManager.shared.start()
                    EventTapManager.shared.updateMacros(
                        macros: AppDelegate.shared?.store.macros ?? [],
                        groups: AppDelegate.shared?.store.groups ?? []
                    )
                }
            }
            .store(in: &cancellables)

        // Track settings changes for the engine.
        settings.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in
                guard let self = self else { return }
                EventTapManager.shared.globallyEnabled = self.settings.globalHotkeysEnabled
                EventTapManager.shared.setChordTimeout(self.settings.chordTimeoutMS)
                EventTapManager.shared.snippetEngine.isEnabled = self.settings.snippetsEnabled
                Task { @MainActor in
                    await EventTapManager.shared.executor.setTimeout(Double(self.settings.actionTimeoutMS) / 1000.0)
                }
            }
            .store(in: &cancellables)

        // Note: AppleEvent file-open handler for .keyforge files is installed in
        // application(_:openFile:) and application(_:open:).
        AppDelegate.shared = self

        // First-time launch — open the editor so the user sees onboarding.
        if !settings.hasCompletedOnboarding {
            DispatchQueue.main.async { self.openMainWindow() }
        }
    }

    public func applicationWillTerminate(_ notification: Notification) {
        store.saveImmediately()
        EventTapManager.shared.stop()
        AccessibilityHelper.shared.stopPolling()
    }

    public func application(_ sender: NSApplication, openFile filename: String) -> Bool {
        let url = URL(fileURLWithPath: filename)
        return importFromFile(url: url)
    }

    public func application(_ application: NSApplication, open urls: [URL]) {
        for u in urls { _ = importFromFile(url: u) }
    }

    private func importFromFile(url: URL) -> Bool {
        do {
            let data = try Data(contentsOf: url)
            let added = try store.importData(data, replaceExisting: false)
            Logger.shared.info("Imported \(added) macros from \(url.lastPathComponent)")
            openMainWindow()
            return true
        } catch {
            Logger.shared.error("Failed to import \(url.lastPathComponent): \(error)")
            return false
        }
    }

    // MARK: - Status item

    private func installStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            let image = NSImage(systemSymbolName: "bolt.fill", accessibilityDescription: "KeyForge")
            image?.isTemplate = true
            button.image = image
            button.target = self
            button.action = #selector(statusItemClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        statusItem = item
    }

    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp {
            showStatusMenu()
        } else {
            openMainWindow()
        }
    }

    private func showStatusMenu() {
        let menu = NSMenu()
        menu.addItem(withTitle: "Open KeyForge", action: #selector(openMainWindow), keyEquivalent: "o")
            .target = self
        menu.addItem(.separator())
        let toggleItem = NSMenuItem(
            title: settings.globalHotkeysEnabled ? "Disable Hotkeys" : "Enable Hotkeys",
            action: #selector(toggleGlobalHotkeys),
            keyEquivalent: ""
        )
        toggleItem.target = self
        menu.addItem(toggleItem)
        menu.addItem(.separator())
        menu.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
            .target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit KeyForge", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        statusItem?.menu = menu
        statusItem?.button?.performClick(nil)
        // Restore action-on-click for next time.
        DispatchQueue.main.async { [weak self] in self?.statusItem?.menu = nil }
    }

    @objc public func openMainWindow() {
        // Become a regular foreground app while the editor is open. As an
        // `.accessory` (LSUIElement) app our windows can't reliably take
        // keyboard focus for text fields (search, macro names) — switching to
        // `.regular` fixes typing. We revert to `.accessory` on window close so
        // the dock icon only shows while the editor is up.
        NSApp.setActivationPolicy(.regular)

        if let win = mainWindow {
            win.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 960, height: 600),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        win.title = "KeyForge"
        win.center()
        win.setFrameAutosaveName("KeyForgeMainWindow")
        win.minSize = NSSize(width: 760, height: 500)
        win.delegate = self
        let content = MainWindow(store: store)
        win.contentView = NSHostingView(rootView: content)
        win.isReleasedWhenClosed = false
        mainWindow = win
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // When the editor window closes, drop back to a menu-bar-only agent
    // (no dock icon). Only the main window has us as its delegate.
    public func windowWillClose(_ notification: Notification) {
        guard (notification.object as? NSWindow) === mainWindow else { return }
        NSApp.setActivationPolicy(.accessory)
    }

    @objc private func toggleGlobalHotkeys() {
        settings.globalHotkeysEnabled.toggle()
    }

    @objc private func openSettings() {
        if #available(macOS 14, *) {
            NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        } else {
            NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    // Shared instance for cross-module access.
    public static var shared: AppDelegate?
}
