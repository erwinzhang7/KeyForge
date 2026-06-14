import Foundation
import AppKit
@preconcurrency import UserNotifications
import CoreWLAN

/// Executes macros serially on a background actor. Each action runs with a
/// per-action timeout (default 10s) — if exceeded, an error is logged and the
/// next action runs.
///
/// Thread model: every `execute(_:)` enqueues work onto the actor's serial
/// executor, so two macros can never run in parallel and clobber each other's
/// state. Within a macro, actions also run serially.
public actor MacroExecutor {
    public var actionTimeoutSeconds: TimeInterval

    public init(actionTimeoutSeconds: TimeInterval = 10.0) {
        self.actionTimeoutSeconds = actionTimeoutSeconds
    }

    public func setTimeout(_ seconds: TimeInterval) {
        self.actionTimeoutSeconds = seconds
    }

    /// Execute a macro's actions in order. Errors are logged; the macro is not
    /// aborted on individual action failure unless explicitly indicated.
    public func execute(_ macro: Macro) async {
        guard macro.isEnabled else { return }
        Logger.shared.info("Executing macro: \(macro.name) (\(macro.actions.count) actions)")
        await executeActions(macro.actions, macroName: macro.name)
    }

    public func executeActions(_ actions: [MacroAction], macroName: String) async {
        for action in actions {
            await executeAction(action, macroName: macroName)
        }
    }

    private func executeAction(_ action: MacroAction, macroName: String) async {
        let timeout = actionTimeoutSeconds
        let actionName = action.displayName

        // Race the action against a timeout.
        let timeoutTask = Task<Bool, Never> {
            try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
            return true
        }
        let actionTask = Task<Void, Never> {
            await self.dispatch(action)
        }

        await withTaskGroup(of: ActionGroupResult.self) { group in
            group.addTask { _ = await actionTask.value; return .completed }
            group.addTask {
                _ = await timeoutTask.value
                return .timedOut
            }
            if let first = await group.next() {
                switch first {
                case .completed:
                    timeoutTask.cancel()
                case .timedOut:
                    actionTask.cancel()
                    Logger.shared.error("Action '\(actionName)' in macro '\(macroName)' timed out after \(timeout)s")
                }
                group.cancelAll()
            }
        }
    }

    private enum ActionGroupResult { case completed, timedOut }

    private func dispatch(_ action: MacroAction) async {
        switch action {
        case .launchApp(_, let bundleID):
            await launchApp(bundleID: bundleID)
        case .openURL(_, let urlString):
            await openURL(urlString)
        case .typeText(_, let text, let useClipboard):
            await typeText(text, useClipboard: useClipboard)
        case .shellCommand(_, let command, let wait):
            await runShell(command: command, wait: wait)
        case .appleScript(_, let source):
            await runAppleScript(source: source)
        case .delay(_, let ms):
            try? await Task.sleep(nanoseconds: UInt64(ms) * 1_000_000)
        case .keyPress(_, let keyCode, let modifiers):
            await postKey(keyCode: keyCode, modifiers: modifiers)
        case .mediaControl(_, let act):
            await MainActor.run { MediaController.perform(act) }
        case .focusApp(_, let bundleID):
            await focusApp(bundleID: bundleID)
        case .openFile(_, let path):
            await openFile(path: path)
        case .notification(_, let title, let body):
            await postNotification(title: title, body: body)
        case .ifCondition(_, let condition, let thenActions, let elseActions):
            let branch = await Self.evaluate(condition)
            await executeActions(branch ? thenActions : elseActions, macroName: "if")
        }
    }

    // MARK: - Action implementations (all hop to MainActor where the OS API requires it)

    private func launchApp(bundleID: String) async {
        await MainActor.run {
            let config = NSWorkspace.OpenConfiguration()
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
                NSWorkspace.shared.openApplication(at: url, configuration: config) { _, err in
                    if let err = err { Logger.shared.error("launchApp \(bundleID) failed: \(err)") }
                }
            } else {
                Logger.shared.error("Couldn't find app for bundleID \(bundleID)")
            }
        }
    }

    private func openURL(_ s: String) async {
        await MainActor.run {
            guard let url = URL(string: s) else {
                Logger.shared.error("Invalid URL: \(s)")
                return
            }
            NSWorkspace.shared.open(url)
        }
    }

    private func typeText(_ text: String, useClipboard: Bool) async {
        await MainActor.run {
            let typer = TextTyper()
            typer.type(text, useClipboard: useClipboard)
        }
    }

    private func runShell(command: String, wait: Bool) async {
        let timeout = actionTimeoutSeconds
        let result: ShellResult = await withCheckedContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                let r = ShellRunner.run(command: command, waitForExit: wait, timeout: timeout)
                cont.resume(returning: r)
            }
        }
        if result.didTimeout {
            Logger.shared.error("Shell '\(command)' timed out")
        }
        if wait && result.exitCode != 0 {
            Logger.shared.error("Shell '\(command)' exit=\(result.exitCode): \(result.stderr)")
        }
    }

    private func runAppleScript(source: String) async {
        let result: AppleScriptResult = await withCheckedContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                cont.resume(returning: AppleScriptRunner.run(source: source))
            }
        }
        if !result.success {
            Logger.shared.error("AppleScript failed: \(result.errorMessage ?? "")")
        }
    }

    private func postKey(keyCode: UInt16, modifiers: UInt64) async {
        await MainActor.run {
            let typer = TextTyper()
            typer.postKey(keyCode: keyCode, modifiers: modifiers)
        }
    }

    private func focusApp(bundleID: String) async {
        await MainActor.run {
            let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            if let app = running.first {
                app.activate(options: [.activateIgnoringOtherApps])
            } else {
                // Fall back to launch.
                if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
                    let config = NSWorkspace.OpenConfiguration()
                    config.activates = true
                    NSWorkspace.shared.openApplication(at: url, configuration: config, completionHandler: nil)
                }
            }
        }
    }

    private func openFile(path: String) async {
        await MainActor.run {
            let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
            NSWorkspace.shared.open(url)
        }
    }

    private func postNotification(title: String, body: String) async {
        await MainActor.run {
            let center = UNUserNotificationCenter.current()
            center.getNotificationSettings { settings in
                let send = {
                    let content = UNMutableNotificationContent()
                    content.title = title
                    content.body = body
                    content.sound = .default
                    let req = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
                    center.add(req) { err in
                        if let err = err { Logger.shared.error("Notification failed: \(err)") }
                    }
                }
                switch settings.authorizationStatus {
                case .notDetermined:
                    center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
                        if granted { send() }
                    }
                case .authorized, .provisional, .ephemeral:
                    send()
                case .denied:
                    Logger.shared.error("Notifications denied")
                @unknown default:
                    Logger.shared.error("Notifications not authorized")
                }
            }
        }
    }

    // MARK: - Condition evaluation

    public static func evaluate(_ condition: ConditionCheck) async -> Bool {
        switch condition {
        case .alwaysTrue:
            return true
        case .alwaysFalse:
            return false
        case .frontmostApp(let bundleID):
            return await MainActor.run {
                NSWorkspace.shared.frontmostApplication?.bundleIdentifier == bundleID
            }
        case .timeOfDay(let start, let end):
            let hour = Calendar.current.component(.hour, from: Date())
            if start <= end { return hour >= start && hour <= end }
            return hour >= start || hour <= end
        case .wifiConnected(let ssid):
            #if canImport(CoreWLAN)
            return CWWiFiClient.shared().interface()?.ssid() == ssid
            #else
            return false
            #endif
        case .fileExists(let path):
            let expanded = (path as NSString).expandingTildeInPath
            return FileManager.default.fileExists(atPath: expanded)
        }
    }
}
