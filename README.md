# KeyForge

A macOS macro and hotkey manager. Runs as a background menu-bar agent (no dock icon) and turns any keyboard combination into a chain of actions: launch apps, run scripts, type text, control media, open URLs, fire AppleScripts, and more.

- **Bundle ID:** `com.local.keyforge`
- **Minimum macOS:** 13.0 (Ventura)
- **Architecture:** Universal (Apple Silicon + Intel)
- **Dependencies:** none — pure Swift + AppKit + SwiftUI
- **License:** Apache 2.0

## Features

- **Global hotkeys → action chains.** Bind any combo to a sequence of actions: launch apps, run shell, type text, control media, open URLs/files, run AppleScript, post notifications, and conditional (`if`) branches.
- **Override hardware & media keys.** Bind macros to brightness, volume, mute, play/next/previous, keyboard backlight, and the fn-row special keys (F4/Spotlight, F5/Dictation, …) — KeyForge intercepts them at the event tap and replaces the macOS default. (e.g. remap F4 from Spotlight to launch your own app.)
- **All Hotkeys browser.** One searchable view of *every* shortcut on the machine: your KeyForge macros, the live macOS system shortcuts (read from `com.apple.symbolichotkeys`), built-in editing combos, hardware keys, and text snippets — with cross-source **conflict highlighting**.
- **Press-to-search.** Hit any key or combo (including media keys) and the browser resolves it — telling you what it's bound to. Text search also understands modifier *names* (`cmd shift` matches ⇧⌘ combos).
- **Chords.** Two-key sequences (vim-style, e.g. `g` then `t`) with a tunable timeout.
- **Text snippets.** Abbreviation expansion (e.g. `;em` → your email).
- **Import/export** of macro libraries as portable `.keyforge` JSON.

## Build

```sh
# Run the test suite (59 tests)
swift test

# Build the executable
swift build

# Assemble a complete .app bundle (Info.plist + entitlements + ad-hoc sign)
./Scripts/make-app.sh           # debug
./Scripts/make-app.sh --release # optimized

# Launch it
open build/KeyForge.app
```

First launch will prompt for **Accessibility** permission, which is required for the global hotkey engine. The onboarding sheet has a button that opens the System Settings pane directly.

## Smoke test

After granting Accessibility:

1. The onboarding sheet seeds a sample macro bound to **⌘⌥⇧K** with a single Notification action.
2. Press **⌘⌥⇧K** anywhere — a Notification Center banner saying "KeyForge is working" appears.
3. Add another macro of type **Shell Command** (e.g. `say "hello"`) bound to **⌘⌥⇧H** and verify it runs.

## Architecture

```
Sources/KeyForge/
├── App/                  KeyForgeApp.swift, AppDelegate.swift
├── Engine/               EventTapManager, ChordDetector, MacroExecutor,
│                         ConflictDetector, SnippetEngine
├── Actions/              TextTyper, ShellRunner, AppleScriptRunner, MediaController
├── Storage/              Models, MacroStore
├── UI/                   MainWindow, SidebarView, MacroListView, MacroDetailView,
│                         ActionCardView, KeyRecorderView, IconPickerView,
│                         SnippetsView, OnboardingView, AllHotkeysView, CompatViews
├── Settings/             SettingsView, AppSettings
└── Helpers/              AccessibilityHelper, SystemShortcuts, SystemHotkeyInventory,
                          PrivateAPIs, Logger
```

**Lifecycle.** `KeyForgeApp` (the `@main` SwiftUI App) registers `AppDelegate` via `@NSApplicationDelegateAdaptor`. `AppDelegate.applicationDidFinishLaunching` installs the status item, creates the `MacroStore` (which reads `~/Library/Application Support/KeyForge/macros.json`), wires Combine observers from store → engine, and asks `EventTapManager` to install its `CGEventTap`.

**Event flow.**

```
hardware keypress
     ↓
CGEventTap (kCGSessionEventTap)
     ↓
EventTapManager.handleEvent
     ↓
[1] ChordDetector.process — if in chord state or this starts a chord, consume
[2] hotkey lookup table — if matched, dispatch macro to MacroExecutor and consume
[3] SnippetEngine.processCharacter — observe character, expand if abbreviation matched
     ↓
event passes through to focused app (unless consumed above)
```

`MacroExecutor` is an `actor`: macro executions serialize so two concurrently-triggered macros can't interleave actions. Each individual action also has a configurable timeout (default 10s); if exceeded the action is cancelled and the next one runs.

## Action reference

| Action            | Fields                                       | Notes |
| ----------------- | -------------------------------------------- | ----- |
| `launchApp`       | `bundleID`                                   | Uses `NSWorkspace.openApplication(at:)`. |
| `openURL`         | `url`                                        | Any URL scheme the system can handle. |
| `typeText`        | `text`, `useClipboard`                       | Clipboard mode posts ⌘V; keystroke mode synthesizes per-char events. Unmappable chars fall back to Unicode input. |
| `shellCommand`    | `command`, `waitForExit`                     | Spawned via `/bin/zsh -c`. Captures stdout/stderr. |
| `appleScript`     | `source`                                     | `NSAppleScript.executeAndReturnError`. Requires Automation permission. |
| `delay`           | `milliseconds`                               | Non-blocking `Task.sleep`. |
| `keyPress`        | `keyCode`, `modifiers`                       | Synthesizes a single keystroke. |
| `mediaControl`    | `action` ∈ {playPause, next, prev, vol±, mute} | Uses private MediaRemote when available, falls back to `NX_SYSDEFINED` events. |
| `focusApp`        | `bundleID`                                   | `NSRunningApplication.activate`; falls back to launch. |
| `openFile`        | `path`                                       | `NSWorkspace.open(URL(fileURLWithPath:))`. |
| `notification`    | `title`, `body`                              | `UNUserNotificationCenter`. Lazily requests permission. |
| `ifCondition`     | `condition`, `thenActions`, `elseActions`    | Conditions: `frontmostApp`, `timeOfDay`, `wifiConnected`, `fileExists`, `alwaysTrue`, `alwaysFalse`. |

## Hotkey syntax

A hotkey is the pair `(virtualKeyCode, modifierMask)` plus an optional `chordKey`:

- **Modifiers** are bitmasks over `CGEventFlags`. The recorder ignores device-specific bits like numpad/help, keeping only `⌘ ⌥ ⌃ ⇧ fn`.
- **Single hotkey** mode: pressing the combo fires the macro and the event is suppressed.
- **Chord** mode: pressing the leader combo arms a 500 ms timer (tunable in Settings, 200–1000 ms). Press the chord key within the window to fire. Otherwise the detector resets silently.
- **Manual** mode: hotkey can be set but isn't bound globally — fire it via the Test Run button or programmatically.

Examples:

- `⌘⌥T` → keyCode 17, modifiers `cmd|opt`
- `G then T` (vim-style chord) → keyCode 5 (G), modifiers 0, chordKey 17 (T)

## Import / Export format

A `.keyforge` file is JSON with the following top-level shape:

```json
{
  "version": 1,
  "macros":   [ { "id": "UUID", "name": "…", "icon": "bolt.fill", "hotkey": {…}, "actions": [{ "type": "shellCommand", "payload": { "id": "UUID", "command": "ls", "waitForExit": true } }], "groupID": null, "isEnabled": true, "triggerMode": "hotkey" } ],
  "groups":   [ { "id": "UUID", "name": "Dev", "icon": "folder", "isEnabled": true, "sortOrder": 0 } ],
  "snippets": [ { "id": "UUID", "abbreviation": ";em", "expansion": "erwin@example.com", "isEnabled": true } ]
}
```

Actions use a discriminated union: each action object is `{"type": "<kind>", "payload": {...}}`. See `MacroAction.encode(to:)` in `Sources/KeyForge/Storage/Models.swift` for the exact schema.

**Import behavior.** Importing checks IDs; new macros are appended, existing IDs are either skipped or replaced based on the `replaceExisting` flag. If an imported macro carries a hotkey that already exists locally, the hotkey is stripped from the import to avoid clobbering the user's layout.

## Permissions

| Permission   | When | How |
| ------------ | ---- | --- |
| Accessibility | Required at startup before the CGEventTap can intercept events. | Onboarding prompts; `AccessibilityHelper` polls every 2s and the main window shows a banner until granted. |
| Automation   | When an AppleScript action targets a specific app. | macOS prompts at first execution. |
| Notifications | First time a `notification` action runs. | `UNUserNotificationCenter.requestAuthorization`. |
| Network / Location / Camera | Never. | — |

## Settings

A `Settings { }` scene exposes four tabs:

- **General** — launch at login (`SMAppService`), global enable/disable, hide menu bar icon (run headless in the background; relaunch the app to reopen the editor), conflict detection strictness, chord timeout (200–1000ms).
- **Snippets** — global on/off; per-snippet editing lives in the main window's Snippets sheet.
- **Advanced** — action timeout (1s–60s), log verbosity, export debug log button.
- **Permissions** — live AX permission status with a direct "Open System Settings" link.

## Conflict detection

`ConflictDetector` reports three outcomes when the user records a new hotkey:

- `noConflict` — safe to bind.
- `userConflict(macroName, macroID)` — another macro already uses the combo.
- `systemConflict(description)` — overlaps a well-known macOS shortcut (Spotlight, Mission Control, screenshots, app switching, text editing, …). Listed in `SystemShortcuts.entries`. Strict detection is on by default and can be disabled in Settings.

## Known limitations

- **MediaRemote private framework** is no longer ABI-stable across macOS releases. KeyForge dynamically `dlopen`s the framework; if the symbol is unresolved (newer macOS), it falls back to posting `NX_SYSDEFINED` system events, which works for volume / mute and usually for play/pause.
- **AppleScript actions** require user approval for each app they target. The first run of a script that drives another app will prompt the user.
- **App Sandbox** is intentionally disabled (see `Resources/KeyForge.entitlements`). KeyForge needs CGEventTap, AppleScript, NSWorkspace activation, and process spawning — all incompatible with the sandbox. Distribution would require Developer ID signing + notarization.
- **Snippet expansion in secure input** is blocked by the OS (password fields, etc.). This is by design and is consistent with every other text-expansion app on the platform.
- **Inline editing of nested actions inside `ifCondition`** is currently surfaced only at the top level; nested then/else action arrays are visible in the editor but full nested editing is best done via the JSON import/export pipeline.
- The provided `.app` is **ad-hoc signed**. macOS Gatekeeper will warn on first launch; right-click → Open works, or `xattr -dr com.apple.quarantine build/KeyForge.app`.

## Test suite

59 tests cover the engine, storage, codable round-trips, and the hotkey
inventory / hardware-key override paths:

```
ActionTimeoutTests           — shellCommand timeout enforcement
AppleScriptRunnerTests       — success + error paths
ChordDetectionTests          — in-window fire, timeout reset, mismatch reset
ConditionCheckTests          — alwaysTrue/False, fileExists (with real temp file), timeOfDay
ConflictDetectorTests        — system shortcut, exotic combo, user conflict, self-exclude
HotkeyMatchingTests          — 3-entry table, false-positive checks, disabled-macro skip, group-disable
ImportExportTests            — 5-macro .keyforge roundtrip, dedup behavior
MacroActionCodableTests      — all 12 variants, ID preservation
MacroStoreTests              — save/reload, debounced autosave, duplicate
ShellRunnerTests             — echo stdout, non-zero exit, fire-and-forget
SmokeTests                   — fundamental type instantiation
SnippetEngineTests           — abbreviation expansion + backspace count, buffer reset, disabled engine
TextTyperTests               — keystroke mode event count, clipboard mode, backspace count
WindowSmokeTests             — MainWindow instantiates with non-zero frame
SystemKeyTests               — system-defined key codable, naming, engine routing, symbolichotkeys parsing
HotkeyInventoryViewTests     — search aliasing, keycap tokenizing, conflict matching, hardware catalog
```

Run with `swift test`.

## Development

Design rationale, conventions, gotchas, and "how to add an action/condition type"
guides live in [`docs/DEVELOPMENT.md`](docs/DEVELOPMENT.md).

## License

Licensed under the **Apache License, Version 2.0**. See [`LICENSE`](LICENSE).

```
Copyright 2026 Erwin Zhang

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0
```
