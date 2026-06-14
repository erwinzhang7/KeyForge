# Development notes

Design rationale, conventions, and gotchas for working on KeyForge. The
user-facing overview lives in the top-level [`README.md`](../README.md); this
document is for contributors.

## Project shape

KeyForge is a **SwiftPM executable**, not an Xcode project — intentional, so
`swift build` and `swift test` work directly without Xcode. The `.app` bundle is
assembled by `Scripts/make-app.sh` from the SwiftPM binary plus
`Resources/Info.plist` and `Resources/KeyForge.entitlements`.

```
Sources/KeyForge/
├── App/          Entry point + AppDelegate
├── Engine/       EventTapManager, ChordDetector, MacroExecutor, SnippetEngine, ConflictDetector
├── Actions/      Per-action executors (TextTyper, ShellRunner, AppleScriptRunner, MediaController)
├── Storage/      Models (Macro, Hotkey, MacroAction enum, etc.) + MacroStore (persistence)
├── UI/           SwiftUI views (MainWindow, Sidebar, MacroList, Detail, ActionCard, KeyRecorder,
│                 AllHotkeysView, …)
├── Settings/     SettingsView + AppSettings (@AppStorage)
└── Helpers/      AccessibilityHelper, SystemShortcuts, SystemHotkeyInventory,
                  PrivateAPIs (MediaRemote dlopen), Logger

Tests/KeyForgeTests/   59 tests
Resources/             Info.plist, KeyForge.entitlements
Scripts/make-app.sh    Assemble .app + sign
```

## Build / test commands

```sh
swift build                                    # compile
swift build -Xswiftc -warnings-as-errors       # strict check; should be clean
swift test                                     # 59 tests, ~2.4s
./Scripts/make-app.sh                          # builds build/KeyForge.app (debug)
./Scripts/make-app.sh --release                # release variant
open build/KeyForge.app                        # launch
```

`make-app.sh` is bash-sensitive to Unicode in `echo` strings — use ASCII only
(no `…` ellipsis, etc.).

### Code signing & the Accessibility grant

`make-app.sh` signs with a **stable** code-signing identity when one is available
(resolution order: `$KEYFORGE_SIGN_ID` → a `KeyForge Dev` identity → any local
self-signed identity → ad-hoc). This matters: macOS pins the Accessibility (TCC)
grant to the binary's signature. **Ad-hoc signing changes the signature on every
build**, which silently invalidates the grant and forces a re-authorize. A stable
self-signed identity (Keychain Access → Certificate Assistant → Create a
Certificate → Code Signing, Self Signed Root) makes the grant survive rebuilds.

## Key design decisions

**MacroExecutor is an actor.** Macros serialize per-process; two concurrent
triggers can't interleave action steps. Per-action timeout is enforced via a
`TaskGroup` racing the action vs `Task.sleep(timeout)`. When the timeout wins the
action task is cancelled and execution continues to the next action — it does
*not* abort the whole macro.

**MacroAction is a discriminated-union Codable enum** with hand-written
`encode(to:)` / `init(from:)`. The wire format is `{"type": "<kind>", "payload":
{...}}`. Every variant carries a UUID `id` as the first payload field so deduping
at import time can be id-based. **Don't switch to `automatic` Codable** — it would
break `.keyforge` file-format compatibility.

**EventTapManager owns one CGEventTap at `kCGSessionEventTap`.** The callback runs
on its own thread; an `NSLock` guards the lookup tables, and macro execution is
dispatched onto the executor actor. The callback must be **fast** — no
allocation-heavy work — and it re-enables itself on `.tapDisabledByTimeout` /
`.tapDisabledByUserInput`, which the OS fires if the callback ever takes too long.

**The tap also listens for `NSSystemDefined` (CGEventType raw 14).** That's the
event carrying brightness/volume/mute, media transport, and the special top-row
function keys — they do **not** arrive as `keyDown`. `parseSystemKey` decodes
subtype-8 events: `data1` high word = `NX_KEYTYPE_*` aux code, bits 15..8 = state
nibble (0xA down / 0xB up), bit 0 = repeat. A macro bound to a system key fires on
down and the tap returns `nil` for **both** down and up — that's how "override the
F4 / brightness key" works. Aux codes live in a *separate numbering space* from
virtual key codes, so they get their own lookup table (`systemKeyMacros`) and
`Hotkey.keyType == .systemDefined` keeps the two from ever cross-matching.

**The `fn` flag is excluded from `Hotkey.modifierMask`.** `fn` is a keyboard
*layer*, not a semantic modifier, and the same physical key (e.g. F4/Spotlight =
keycode 177) reports `fn` set or unset depending on keyboard settings. Excluding
it from the match mask makes hardware-key overrides reliable.

**`captureHook` on EventTapManager is the recording path for system keys.** When
the KeyRecorder (or the inventory's press-to-search) is active it installs this
hook; the tap then diverts every key (standard + system-defined) to it and
swallows it, because media keys never reach a local `NSEvent` monitor. While the
hook is set the tap swallows keystrokes **system-wide**, so it must be cleared on
every exit path (commit / cancel / `resignFirstResponder` / window change /
`deinit` / `onDisappear`). The recorder falls back to a local monitor (standard
keys only) when the tap isn't running (no Accessibility yet).

**"All Hotkeys" viewer** (`UI/AllHotkeysView.swift`) is an inline sidebar
destination (`SidebarSelection.allHotkeys`, under "Reference"). The inventory
merges five sources: KeyForge macros, live macOS system shortcuts read from
`com.apple.symbolichotkeys` (`Helpers/SystemHotkeyInventory.swift`), the curated
always-on `SystemShortcuts.entries`, the `HardwareKeyCatalog` (brightness /
volume / media / fn-row keys), and snippets. The symbolichotkeys `parameters`
array is `[ascii, virtualKeyCode, cocoaModifierMask]` where the mask is **Cocoa
`NSEvent.ModifierFlags` raw bits** (not Carbon, not CGEventFlags).

- **Search** matches a precomputed `HotkeyRow.searchText` that aliases glyphs to
  words (⌘→"command"/"cmd", ⌥→"option"/"alt"/"opt", …), AND-ed across whitespace
  tokens, so "cmd shift" matches `⇧⌘3`.
- **Press-to-search** captures a real key press via `captureHook` and filters by
  `HotkeyRow.normalizedComboKey` (order-independent, `fn` stripped). Unmatched
  presses still resolve to a "what this key is" result so a press is never a dead
  end.
- **Conflict detection** keys off `normalizedComboKey`. The view flags rows whose
  combo collides across sources when a KeyForge macro is involved (plus
  KeyForge-internal dupes); a "Conflicts" filter pill + orange row treatment
  surface them. The curated built-in list is de-duplicated against the live
  symbolichotkeys read so each system shortcut appears once.
- **Click-to-jump**: KeyForge rows carry `macroID`; tapping calls `onSelectMacro`,
  which `MainWindow` uses to select that macro in the editor.

**Activation policy.** The app is `LSUIElement` (menu-bar agent, no dock icon),
but `.accessory` apps can't reliably give their windows keyboard focus for text
fields. So `AppDelegate.openMainWindow` switches to `.regular` while the editor
window is open and reverts to `.accessory` on close (`windowWillClose`). The dock
icon therefore appears only while the editor is up.

**Synthetic events tagged with `EventTapManager.syntheticUserData`**
(`0x4B45_5946_4F52_4745` = "KEYFORGE" ASCII) so when TextTyper posts a keystroke,
the tap sees the tag and passes it through without re-processing — prevents
feedback loops.

**TextTyper has a `mockMode`** that records events instead of posting them. Used
by tests and by SnippetEngine in test mode.

**ChordDetector takes a `nowProvider`** closure for deterministic time-based
testing. Production passes `{ Date() }`; tests pass a mutable `var now`.

**MediaRemote is `dlopen`-ed at runtime**, not link-time. If the symbol isn't
found on newer macOS releases, `MediaController` falls back to posting
`NX_SYSDEFINED` system-defined NSEvents (the same events the keyboard's media keys
generate). See `Helpers/PrivateAPIs.swift`.

**MacroStore is `@MainActor`.** This propagates: AppDelegate is `@MainActor`,
SwiftUI views are naturally main-actor. For off-main store mutation use
`Task { @MainActor in … }`. Persistence uses a 500 ms debounced autosave
(`scheduleSave()`); tests call `saveImmediately()` to skip the debounce.

**ConflictDetector** returns `.noConflict`, `.systemConflict(description)`, or
`.userConflict(macroName, macroID)`. The `excludeMacroID` parameter is critical
when re-checking a hotkey in the editor — without it the macro would self-conflict.

**Onboarding seeds a sample macro** bound to ⌘⌥⇧K → Notification "KeyForge is
working ✨" (the canonical smoke test). Don't remove it without updating tests and
the README.

## Permissions

- **Accessibility** — required before the CGEventTap can intercept events.
  `AccessibilityHelper` polls every 2 s; the main window shows a banner until
  granted.
- **Automation** — requested lazily the first time an AppleScript action targets
  another app.
- **Notifications** — `UNUserNotificationCenter.requestAuthorization` on the first
  notification action.
- No network, location, or camera permissions, ever.

## Sandbox status

KeyForge is **intentionally unsandboxed** (`com.apple.security.app-sandbox =
false`). It needs CGEventTap, AppleScript driving other apps, NSWorkspace
activation, and `/bin/zsh` spawning — all incompatible with the App Sandbox.
Hardened runtime is on for codesigning. Don't enable the sandbox without rewriting
the engine.

## Testing conventions

- All tests live in `Tests/KeyForgeTests/`.
- Tests that touch `@MainActor` types (MacroStore, EventTapManager) are themselves
  `@MainActor`.
- `ActionTimeoutTests` (shell-command timeout) is the slowest at ~1 s; the rest are
  sub-100 ms.
- `WindowSmokeTests` instantiates `MainWindow` inside an `NSHostingView` to catch
  SwiftUI compile/runtime regressions — keep it green.
- Prefer deterministic inputs (`Date(timeIntervalSince1970:)`, temp file URLs with
  a `UUID()` suffix) over relying on system state.

## .keyforge file format

JSON, top-level `MacroLibrary`:

```json
{
  "version": 1,
  "macros":   [ { "id": "UUID", "name": "...", "icon": "bolt.fill", "hotkey": {...}, "actions": [...], "groupID": null, "isEnabled": true, "triggerMode": "hotkey" } ],
  "groups":   [ { "id": "UUID", "name": "Dev", "icon": "folder", "isEnabled": true, "sortOrder": 0 } ],
  "snippets": [ { "id": "UUID", "abbreviation": ";em", "expansion": "...", "isEnabled": true } ]
}
```

Each action: `{"type": "<kind>", "payload": {"id": "UUID", ...kind-specific
fields}}`. See `MacroAction.encode(to:)` in `Storage/Models.swift` for the
authoritative schema.

`hotkey`: `{"keyCode": N, "modifiers": N, "chordKey": N?, "keyType":
"standard"|"systemDefined"}`. `keyType` was added for system/media keys; `Hotkey`
has hand-written Codable so files written before it (no `keyType`) still decode as
`.standard`. For `.systemDefined`, `keyCode` is an `NX_KEYTYPE_*` aux code, not a
virtual key code.

Import behavior: new IDs are appended; conflicting hotkeys on imported macros are
stripped (not the local macro's hotkey) to avoid clobbering the user's layout.

Persistence lives at `~/Library/Application Support/KeyForge/macros.json` (atomic
write via `replaceItemAt`). On first launch (file absent) the onboarding sheet
runs.

## Gotchas (macOS 13 / Swift 6)

- `ContentUnavailableView` is macOS 14+. Use `EmptyStateView` from
  `UI/CompatViews.swift` instead — drop-in replacement.
- `.foregroundStyle(.accent)` doesn't exist on macOS 13. Use
  `.foregroundStyle(Color.accentColor)`.
- Swift 6 strict concurrency requires `@MainActor` on AppDelegate (it constructs
  `MacroStore` synchronously in `init`).
- `@unknown default` must come **after** all `case` clauses in a switch.
- `import UserNotifications` needs `@preconcurrency` because
  `UNUserNotificationCenter` isn't `Sendable`.
- Bash on macOS treats `$VAR…` (with Unicode ellipsis) as the variable name
  `VAR…`. Use `${VAR}...` in shell scripts.
- A SwiftUI `TextField` swapped in/out of an `if/else` chain loses focus
  (unstable identity). Keep it always-mounted and overlay alternate states.

## How to add a new action type

1. Add the case to `MacroAction` in `Storage/Models.swift` — payload + UUID id.
2. Add to the `Codable` switch in `init(from:)` and `encode(to:)`.
3. Add to `displayName`, `sfSymbol`, and `cloneWithNewIDs` switches.
4. Add to the `ActionType` enum in `UI/ActionCardView.swift` (label +
   `defaultAction`).
5. Add a fields branch to `ActionCardView.fields`.
6. Add the execution case to `MacroExecutor.dispatch`.
7. Add a round-trip test to `MacroActionCodableTests`.

## How to add a new condition type

Same pattern: `ConditionCheck` enum → `Codable` switch → `MacroExecutor.evaluate`
→ `IfConditionFields` in `ActionCardView` → add a test to `ConditionCheckTests`.
