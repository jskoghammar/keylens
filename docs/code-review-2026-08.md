# Keylens — Code Review Findings (2026-08-31)

Scope: static review of `keylens/*.swift` and `keylens.xcodeproj/project.pbxproj` at commit `9043b03`.

> **Not build-verified.** `xcodebuild` was unavailable in the review environment (Command Line
> Tools only, no Xcode), so nothing below was confirmed by compiling or running the app. Line
> references are from the reviewed commit.

This document covers the five High findings and the three Medium findings selected for
follow-up (M1–M3). The remaining Medium and Low items from the full review are not repeated here.

---

## Fix order

`H1` and `H2` are a single change and must land together — see
[the interaction note](#the-h1--h2-interaction) for why fixing `H1` alone makes the app
noticeably worse. After that, `H3` → `H4` → `H5`. `M1`–`M3` are small, independent, and each
removes a class of silent wrong state.

| ID | Title | Area |
|----|-------|------|
| [H1](#h1--hotkey-matching-compares-state-flags-the-user-never-chose) | Hotkey matching compares state flags the user never chose | `HotkeyMonitor`, `AppConfiguration`, `SettingsView` |
| [H2](#h2--auto-assignment-binds-unmodified-keys) | Auto-assignment binds unmodified keys | `AppConfiguration` |
| [H3](#h3--sync-deletes-local-svgs-before-downloading-replacements) | Sync deletes local SVGs before downloading replacements | `SVGRepositorySyncService` |
| [H4](#h4--untrusted-svgs-rendered-as-html-in-a-js-enabled-wkwebview) | Untrusted SVGs rendered as HTML in a JS-enabled WKWebView | `OverlayWindowController` |
| [H5](#h5--modal-nsalert-run-from-inside-the-cgevent-tap-callback) | Modal `NSAlert` run from inside the CGEvent tap callback | `HotkeyMonitor`, `AppDelegate` |
| [M1](#m1--any-decode-failure-silently-wipes-all-settings) | Any decode failure silently wipes all settings | `AppConfiguration` |
| [M2](#m2--persist-ignores-the-injected-defaults) | `persist` ignores the injected `defaults` | `AppConfiguration` |
| [M3](#m3--the-menu-bar-status-actively-lies) | The menu bar status actively lies | `AppDelegate`, `HotkeyMonitor` |

---

# HIGH

## H1 — Hotkey matching compares state flags the user never chose

**Files:** `keylens/HotkeyMonitor.swift:114`, `keylens/AppConfiguration.swift:7-14`,
`keylens/AppConfiguration.swift:137-140`, `keylens/SettingsView.swift:360-384`

### What happens

`HotkeyShortcut.supportedModifiers` includes `.maskSecondaryFn` and `.maskAlphaShift`:

```swift
// AppConfiguration.swift:7
static let supportedModifiers: CGEventFlags = [
    .maskCommand, .maskAlternate, .maskControl,
    .maskShift, .maskSecondaryFn, .maskAlphaShift
]
```

`handle(event:type:)` builds a shortcut from the *full* intersected flag set and looks it up by
dictionary-key equality, so every bit in that set must match exactly:

```swift
// HotkeyMonitor.swift:113-117
let relevantFlags = event.flags.intersection(HotkeyShortcut.supportedModifiers)
let shortcut = HotkeyShortcut(keyCode: eventKeyCode, modifiers: relevantFlags)
guard let assetID = bindings[shortcut] else { return }
```

`.maskSecondaryFn` and `.maskAlphaShift` are *state* bits set by the system, not modifiers the
user deliberately holds. Including them in the comparison key makes matching depend on ambient
keyboard state.

### Why it's a defect, provable without hardware

Two shortcuts are constructed by **different rules**, so they cannot both match the same event:

1. **Recorder path** derives flags from the live event —
   `HotkeyShortcut(keyCode:, modifiers: Self.cgFlags(from: event.modifierFlags))`
   (`SettingsView.swift:320-323`), where `cgFlags` maps `.function → .maskSecondaryFn` and
   `.capsLock → .maskAlphaShift` (`SettingsView.swift:376-381`).
2. **Auto-assign path** hardcodes an empty set —
   `HotkeyShortcut(keyCode: $0.keyCode, modifiers: [])` (`AppConfiguration.swift:139`).

One of these is wrong by construction. This holds regardless of how any particular keyboard
reports flags.

### Mechanism

`NSEventModifierFlagFunction` and `kCGEventFlagMaskSecondaryFn` are the same bit, and it is set
for the entire *function key group* — arrow keys, F1–F20, Home/End/PageUp/PageDown — not only
when the physical <kbd>fn</kbd> key is held. Consequences:

- Recording <kbd>←</kbd> stores `Fn + LeftArrow` and `hotkeyDescription`
  (`AppConfiguration.swift:217-234`) renders it to the user as **"Fn + Left Arrow"**, which is
  confusing on its own.
- Auto-assign stores bare `LeftArrow`, a combination no real key event produces.

Separately, `.maskAlphaShift` is set on every event while Caps Lock is on. So **turning Caps Lock
on kills every hotkey**, including ones recorded correctly through the recorder path.

### Impact

- Auto-assigned hotkeys never fire (see [H2](#h2--auto-assignment-binds-unmodified-keys) — in
  practice this means *no* hotkey fires after a sync).
- Caps Lock silently disables all hotkeys, with no feedback anywhere in the UI.
- The recorder displays a modifier the user never pressed.

### Fix

Remove `.maskSecondaryFn` and `.maskAlphaShift` from `supportedModifiers` so they are stripped
identically on both the record and the match path:

```swift
static let supportedModifiers: CGEventFlags = [
    .maskCommand, .maskAlternate, .maskControl, .maskShift
]
```

Then route auto-assignment through the same normalization the recorder uses, so the two paths
cannot drift again. Drop `kVK_Function` / `kVK_CapsLock` from `modifierFlag(for:)` in both
`HotkeyMonitor.swift:131-148` and `SettingsView.swift:386-403`, and drop the corresponding "Fn" /
"Caps" cases from `hotkeyDescription`.

---

## H2 — Auto-assignment binds unmodified keys

**Files:** `keylens/AppConfiguration.swift:137-140`, `keylens/AppConfiguration.swift:262-270`

### What happens

After a successful sync, every asset without an existing assignment is given the next free
shortcut from `defaultAssignmentOrder`:

```swift
// AppConfiguration.swift:262-270
var usedShortcuts = Set(assignments.values)
for asset in assets {
    guard assignments[asset.id] == nil else { continue }
    if let auto = KeyChoice.defaultAssignmentOrder.first(where: { !usedShortcuts.contains($0) }) {
        assignments[asset.id] = auto
        usedShortcuts.insert(auto)
    }
}
```

`defaultAssignmentOrder` is `arrowKeys + functionKeys + letterKeys`, **all with `modifiers: []`**
(`AppConfiguration.swift:137-140`). The event tap is created with `options: .listenOnly`
(`HotkeyMonitor.swift:76`), so it observes but does not consume events.

### Impact

Binding bare keys to a fullscreen `.screenSaver`-level overlay means: pressing <kbd>←</kbd> in any
application shows the overlay **and** still moves the cursor. Once the letter slots are reached,
ordinary typing triggers overlays.

### The H1 + H2 interaction

This is currently invisible, and that is the important part.

`defaultAssignmentOrder` puts the 4 arrow keys and 20 function keys **first** — 24 slots before
the first letter. Every realistic `keymap-drawer` repo has ≤24 SVGs, so in practice auto-assignment
only ever hands out arrows and F-keys: exactly the keys [H1](#h1--hotkey-matching-compares-state-flags-the-user-never-chose)
prevents from matching.

**Today, after a sync, zero hotkeys fire.** H1 is suppressing H2.

Fixing H1 in isolation would immediately activate ~24 bare-key bindings across arrows and function
keys. The user-visible result of a "bug fix" would be an overlay flashing on every arrow keypress
system-wide. **The two must be fixed in the same change.**

### Fix

Either stop auto-assigning entirely and leave assets unbound until the user records a shortcut, or
change `defaultAssignmentOrder` to require a modifier the user is unlikely to hit by accident:

```swift
static let defaultAssignmentOrder: [HotkeyShortcut] = {
    let preferred = arrowKeys + functionKeys + letterKeys
    return preferred.map {
        HotkeyShortcut(keyCode: $0.keyCode, modifiers: [.maskControl, .maskAlternate])
    }
}()
```

Note also that `defaultAssignmentOrder` has 50 slots; repos with more SVGs leave the remainder
silently unassigned (`guard let auto` falls through with no message).

---

## H3 — Sync deletes local SVGs before downloading replacements

**Files:** `keylens/SVGRepositorySyncService.swift:100-118`,
`keylens/SVGRepositorySyncService.swift:320-323`

### What happens

`makeDestinationDirectory` wipes the cache as a side effect, before any download runs:

```swift
// SVGRepositorySyncService.swift:320-323
let existing = (try? fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
for file in existing where file.pathExtension.lowercased() == "svg" {
    try? fileManager.removeItem(at: file)
}
```

It is called at `:100`, and only then does the download loop at `:103-118` run. Any failure inside
that loop — `downloadFile` throwing on a non-2xx, a dropped connection, a disk write failure —
propagates out of `sync()` and is caught by the caller at `AppConfiguration.swift:280`, which sets
an error message. `configuration.svgAssets` is never assigned.

### Impact

A single network blip produces a fully inconsistent state:

1. Local SVG files are gone.
2. `configuration.svgAssets` still holds the previous entries, whose `localFilePath` values now
   point at deleted files.
3. Triggering a hotkey calls `showAsset(at:for:)`, whose `loadSVG` silently early-returns on the
   read failure (`OverlayWindowController.swift:101-104`).
4. `show(for:)` runs anyway (`OverlayWindowController.swift:66`) and displays the window with
   whatever the webView rendered last, or the `tst.jpg` placeholder.

Net: data loss plus silently wrong output, with the only signal being a settings-screen error
string the user may never look at.

### Fix

Download to a temporary directory and swap atomically on success:

```swift
let staging = try makeStagingDirectory()
defer { try? fileManager.removeItem(at: staging) }

// ... download every entry into `staging`, letting failures throw ...

let destination = try makeDestinationDirectory(owner:repository:branch:)  // no longer deletes
_ = try fileManager.replaceItemAt(destination, withItemAt: staging)
```

Remove the deletion side effect from `makeDestinationDirectory` — a function named "make a
directory" should not destroy its contents. Related: `loadAsset` should return `Bool` and gate the
`show()` call, so a missing or unreadable asset never displays stale content (this is finding M5
in the full review).

---

## H4 — Untrusted SVGs rendered as HTML in a JS-enabled WKWebView

**File:** `keylens/OverlayWindowController.swift:100-139`

### What happens

SVG bytes fetched from a user-supplied GitHub repository are string-interpolated into an HTML
document and loaded with a `file://` base URL:

```swift
// OverlayWindowController.swift:131-139
    \(svgBody)
  ...
let baseURL = URL(fileURLWithPath: localPath).deletingLastPathComponent()
webView.loadHTMLString(html, baseURL: baseURL)
```

The `WKWebView` is created with the default configuration (`OverlayWindowController.swift:6`), so
JavaScript is enabled and remote subresource loading is permitted.

### Why it matters

SVG is not an inert image format when parsed as HTML. `<script>` elements execute. `<foreignObject>`
embeds arbitrary HTML. `<image href="https://…">`, `<use href>`, and CSS `url()` all trigger network
requests — meaning **silent outbound egress on every overlay show**, which also functions as a
tracking beacon for whoever controls the repo.

The download path applies no validation: `SVGRepositorySyncService.swift:93` filters on filename
suffix only (`$0.name.lowercased().hasSuffix(".svg")`), never on content.

`ENABLE_APP_SANDBOX = NO` (`project.pbxproj:254`) is a defensible setting on its own — event taps
and Input Monitoring are a legitimate reason — but it removes the containment that would otherwise
limit the blast radius of code executing in this webview.

### Fix

Disable script execution and drop the base URL unless relative asset resolution is genuinely
needed:

```swift
private let webView: WKWebView = {
    let configuration = WKWebViewConfiguration()
    configuration.defaultWebpagePreferences.allowsContentJavaScript = false
    return WKWebView(frame: .zero, configuration: configuration)
}()

// ...
webView.loadHTMLString(html, baseURL: nil)
```

For defence in depth, add a `WKContentRuleList` blocking all non-`file` loads.

If the SVGs are known to be static output from `keymap-drawer`, consider rasterizing them outside a
webview entirely — that removes this attack surface rather than narrowing it, and avoids a full page
navigation per overlay. Verify feature coverage against your actual `keymap-drawer` output before
committing to that route; SVG support outside WebKit is narrower.

---

## H5 — Modal `NSAlert` run from inside the CGEvent tap callback

**Files:** `keylens/HotkeyMonitor.swift:167-183`, `keylens/AppDelegate.swift:173-181`

### What happens

The tap callback handles `tapDisabledByUserInput` by invoking `onRuntimeWarning` **synchronously**,
before re-arming the tap:

```swift
// HotkeyMonitor.swift:167-177
if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
    if type == .tapDisabledByUserInput, !source.hasWarnedAboutUserInputDisable {
        source.hasWarnedAboutUserInputDisable = true
        source.onRuntimeWarning?("Hotkey monitoring was disabled by macOS user input security. …")
    }
    if let tap = source.eventTap {
        CGEvent.tapEnable(tap: tap, enable: true)   // <- not reached until the modal returns
    }
    return Unmanaged.passUnretained(event)
}
```

`onRuntimeWarning` is wired to `showRuntimeHotkeyWarning` (`AppDelegate.swift:131`), which calls
`alert.runModal()` (`AppDelegate.swift:180`).

### Two problems

**Reentrant modal on the tap's own run loop.** The run loop source is added to
`CFRunLoopGetMain()` (`HotkeyMonitor.swift:88`), so this callback executes on the main run loop.
`runModal()` spins a nested modal run loop from inside a run-loop source callback and blocks until
the user dismisses it. The `tapEnable` re-arm on line 174 does not execute during that time. This
is a classic hang path.

**The one-shot guard is defeated.** `hasWarnedAboutUserInputDisable` is reset to `false` on
*every* subsequent keyDown or flagsChanged event:

```swift
// HotkeyMonitor.swift:183
source.hasWarnedAboutUserInputDisable = false
source.handle(event: event, type: type)
```

So the flag only suppresses a repeat warning if no key is pressed in between — which never holds in
practice. Under sustained secure input the alert can reappear on each disable.

### Impact

Only reachable when something enables secure input (Terminal's Secure Keyboard Entry, a password
field), but the failure mode is a blocked main run loop and a repeating modal the user has to
dismiss over and over.

### Fix

Re-arm first, then hop off the callback before presenting anything:

```swift
if let tap = source.eventTap {
    CGEvent.tapEnable(tap: tap, enable: true)
}
if type == .tapDisabledByUserInput, !source.hasWarnedAboutUserInputDisable {
    source.hasWarnedAboutUserInputDisable = true
    let warn = source.onRuntimeWarning
    DispatchQueue.main.async { warn?("…") }
}
return Unmanaged.passUnretained(event)
```

Reset `hasWarnedAboutUserInputDisable` on a cooldown timer or when the tap re-arms cleanly — not on
every keystroke. Prefer a menu-bar status change or a `UNUserNotification` over a modal alert for a
background accessory app.

---

# MEDIUM

## M1 — Any decode failure silently wipes all settings

**File:** `keylens/AppConfiguration.swift:325-329`

### What happens

```swift
if let data = defaults.data(forKey: DefaultsKey.configurationV2),
   let decoded = try? JSONDecoder().decode(AppConfiguration.self, from: data) {
    return decoded
}
// falls through to AppConfiguration.default
```

`try?` discards the decoding error. On any failure, `loadConfiguration` returns
`AppConfiguration.default` — empty repo URL, no assets, no hotkey assignments. The very next
mutation triggers the `didSet` at `AppConfiguration.swift:147-152`, which persists that empty
config over the user's stored data.

### Impact

Two ways to lose every hotkey assignment and the repository URL with no signal to the user:

1. Corrupted or truncated `UserDefaults` data.
2. **Adding any future non-optional field to `AppConfiguration`.** A routine schema change is
   indistinguishable from corruption here, and the failure is silent and destructive — the user
   opens Settings, sees a blank form, and their assignments are gone.

The `DefaultsKey.configurationV2` name shows versioning was anticipated, but no path bumps the
version or handles a v2 decode failure.

### Fix

Distinguish "absent" from "unreadable", and never overwrite data that failed to decode:

```swift
private static func loadConfiguration(defaults: UserDefaults) -> AppConfiguration {
    guard let data = defaults.data(forKey: DefaultsKey.configurationV2) else {
        return migrateLegacyConfiguration(defaults: defaults)
    }
    do {
        return try JSONDecoder().decode(AppConfiguration.self, from: data)
    } catch {
        // Preserve the first unreadable payload for recovery; don't clobber it on later launches.
        let quarantine = DefaultsKey.configurationV2 + ".corrupt"
        if defaults.data(forKey: quarantine) == nil {
            defaults.set(data, forKey: quarantine)
        }
        Logger(...).error("Configuration decode failed: \(error)")
        return .default
    }
}
```

Give every new field a default value (or make it `Optional`) so additive schema changes decode
against old payloads. Surface the failure in the settings UI rather than presenting a blank form.

---

## M2 — `persist` ignores the injected `defaults`

**File:** `keylens/AppConfiguration.swift:172-175`, `keylens/AppConfiguration.swift:359-365`

### What happens

`init` accepts a `UserDefaults` and uses it for loading:

```swift
private init(defaults: UserDefaults, syncService: SVGRepositorySyncService) {
    self.syncService = syncService
    configuration = Self.loadConfiguration(defaults: defaults)   // uses the injected instance
}
```

but the instance is never stored, and `persist` hardcodes the standard suite:

```swift
private func persist(_ config: AppConfiguration) {
    guard let data = try? JSONEncoder().encode(config) else { return }
    UserDefaults.standard.set(data, forKey: DefaultsKey.configurationV2)   // not `defaults`
}
```

### Impact

Read/write asymmetry. Injecting a test suite (`UserDefaults(suiteName:)`) reads from the suite but
writes to the real user defaults — a test would silently mutate the developer's actual settings and
would not observe its own writes. The injection point is currently vestigial: the only call site is
`AppSettings.shared`, which passes `.standard`, so the two happen to coincide today.

The `try?` on line 360 also discards encode failures, so a persist can silently no-op.

### Fix

Store the injected instance and use it for both directions:

```swift
private let defaults: UserDefaults

private init(defaults: UserDefaults, syncService: SVGRepositorySyncService) {
    self.defaults = defaults
    self.syncService = syncService
    configuration = Self.loadConfiguration(defaults: defaults)
}

private func persist(_ config: AppConfiguration) {
    do {
        defaults.set(try JSONEncoder().encode(config), forKey: DefaultsKey.configurationV2)
    } catch {
        Logger(...).error("Configuration persist failed: \(error)")
    }
}
```

No ordering hazard here: Swift property observers do not fire for assignments made inside an
initializer, so `configuration = Self.loadConfiguration(...)` does not call `persist`. `self.defaults`
can be assigned wherever is convenient.

---

## M3 — The menu bar status actively lies

**Files:** `keylens/AppDelegate.swift:48-51`, `keylens/AppDelegate.swift:183-190`,
`keylens/HotkeyMonitor.swift:67-93`

### What happens

`setHotkeyActive` is the only feedback channel this accessory app has — there is no window unless
the user opens Settings. It is driven from two conflicting sources.

`onStartError` and `onRuntimeWarning` correctly set it to `false`
(`AppDelegate.swift:127`, `:131`). But `apply(configuration:)` recomputes it from permission state
alone:

```swift
// AppDelegate.swift:48-51
private func apply(configuration: AppConfiguration) {
    triggerController?.update(configuration: configuration)
    setHotkeyActive(InputMonitoringPermission.hasAccess())
}
```

and `apply` runs on **every** configuration change, via
`settings.onConfigurationChanged` (`AppDelegate.swift:33-35`).

### Impact

`CGPreflightListenEventAccess()` returning `true` does not imply `CGEvent.tapCreate` succeeded.
When tap creation fails (`HotkeyMonitor.swift:80-85`) the alert fires and the menu correctly reads
"Hotkey: Inactive" — until the next config change, at which point `apply` overwrites it with
"Hotkey: Active (N mappings)". Since `syncSVGRepository` alone triggers three separate config
mutations (see finding M8 in the full review), this happens readily.

The user is then told hotkeys are active while no tap exists. Combined with
[H1](#h1--hotkey-matching-compares-state-flags-the-user-never-chose)/[H2](#h2--auto-assignment-binds-unmodified-keys),
this is the difference between a diagnosable problem and an inexplicable one.

The count is also misleading in the other direction: `activeMappingCount`
(`AppDelegate.swift:192-195`) reports assignments whose asset ID is known, which is *not* the same
as assignments that can actually fire.

### Fix

Track real tap state on the source and read that, rather than inferring it:

```swift
// HotkeyMonitor.swift
final class HotkeyTriggerSource: ConfigurableTriggerSource {
    private(set) var isRunning = false      // set true after tapEnable, false in stop()/on disable
}

// TriggerController
var isRunning: Bool { (source as? HotkeyTriggerSource)?.isRunning ?? false }

// AppDelegate
private func apply(configuration: AppConfiguration) {
    triggerController?.update(configuration: configuration)
    setHotkeyActive(triggerController?.isRunning == true)
}
```

Set `isRunning = false` in the `tapDisabledByUserInput` branch as well, and consider distinguishing
"no permission", "tap failed", and "active but 0 mappings" in the menu title — they need different
user actions.

---

## Not covered here

The remaining findings from the full review — M4–M15 and the Low list — are out of scope for this
document. The ones most worth revisiting next: `loadAsset` not gating `show()` (M5), missing
auto-repeat filtering (M4), the private `setValue(false, forKey: "drawsBackground")` KVC call (M7),
and the redundant triple-persist in `syncSVGRepository` (M8).
