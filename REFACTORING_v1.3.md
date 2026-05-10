# Refactoring Audit: approval v1.3.0

Fresh assessment after the v1.3.0 release (font-scale in detail window, direct-confirmation mode, X-as-cancel, swapped button colors). The original `REFACTORING.md` is the historical roadmap up to v1.0 — most of its items are done. This document focuses on what's worth fixing **now**, in the post-v1.0 state.

---

## Executive summary

The codebase has good DI fundamentals (`AppContainer`), solid storage patterns (debounced async writes for `LogStore`, in-memory `L10n`), and reasonable error handling. Three categories merit near-term attention:

1. **Concurrency isolation** in the server accept loop and `WindowManager` re-entrancy.
2. **IPC robustness** around partial writes, timeouts, and silent failures in the socket layer.
3. **Test coverage** for the integration paths (server↔hook, WindowManager double-resolve, timeout races).

No architectural rewrites are needed. All improvements are contained and low-risk.

---

## Priority issues

### 1. WindowManager double-resolve race window — **P0**

**Where:** `WindowManager.swift:36–95`, especially `wrappedResolve` (`51–56`) and `windowWillClose` (`84–96`).

**Symptom / risk:**
The `didResolve` flag guards against firing `onResolve` twice when `coordinator.resolve()` triggers `closeWindow(id:)` after explicit Approve/Cancel. However, the check happens inside an async `Task { @MainActor in ... }` block:

```swift
Task { @MainActor in
    for (id, entry) in self.entries where entry.window === window {
        if !entry.didResolve {
            entry.onResolve(false)   // race window
        }
        ...
    }
}
```

Between the `windowWillClose` invocation (still running on AppKit's main thread) and the Task body actually executing, another resolve path could see the entry in an inconsistent state. In practice `PendingStore.resolve` is idempotent, so the worst case is silently absorbed — but it's brittle.

**Fix sketch:**
Have `wrappedResolve` *immediately* remove the entry from `entries` before calling the original callback. Then `windowWillClose` only fires the cancel-callback when the entry is still present. This collapses the flag and the dictionary into a single source of truth.

```swift
let wrappedResolve: (Bool) -> Void = { [weak self, id = cmd.id] approved in
    guard let entry = self?.entries.removeValue(forKey: id) else { return }
    entry.onResolve(approved)
}
```

Then `windowWillClose` does the same `removeValue` and treats a hit as an X-close.

**Effort/Risk:** S / Low.

---

### 2. ApprovalServer.sendResponse silently swallows write failures — **P1**

**Where:** `ApprovalServer.swift:196–202`, calling `UnixSocket.writeLine` from `UnixSocket.swift:50–65`.

**Symptom / risk:**
```swift
nonisolated private static func sendResponse(fd: Int32, ...) {
    if let data = try? JSONSerialization.data(...) {
        _ = UnixSocket.writeLine(fd: fd, data: data)   // return value discarded
    }
    close(fd)
}
```

If the hook's read end has already closed (timeout, kill -9, broken pipe), the write fails. The failure is dropped, the fd is closed, the hook reads EOF and exits with the fail-open path. That last bit is usually fine, but you lose all observability — there's no way to tell from the GUI side whether responses are getting through.

**Fix sketch:**
Capture the boolean return; on `false`, write a one-line message via `Logger(subsystem: "alexmasyukov.approval", category: "ipc")` (already a known pattern from the `.timeSensitive` debugging session). Don't surface to UI — that's noisy. Just `log.warning("response write failed for request \(id)")`.

**Effort/Risk:** S / Low.

---

### 3. ApprovalServer accept loop holds strong refs through the closure — **P1**

**Where:** `ApprovalServer.swift:88–91, 105–117, 120–134`.

**Symptom / risk:**
`start()` spawns a `Thread` whose closure captures `self` strongly:

```swift
Thread { [server = self] in
    Self.acceptLoop(server: server)
}.start()
```

Inside `acceptLoop`, every `accept()` triggers `DispatchQueue.global(qos: .userInitiated).async { handleClient(server: server, fd: clientFd) }` — another strong capture. `handleClient` then does `Task { @MainActor in server.processCheck(...) }` — yet another strong capture.

`stop()` closes the listening fd, which makes `accept()` return `EBADF` and the loop breaks, but any *in-flight* client connections still hold references to `server` until their tasks complete. In practice this means `ApprovalServer` can outlive `AppContainer.shutdown()` for up to 600 seconds (the hook timeout) if a request was mid-flight at quit time. Under normal use the lifetime mismatch is invisible, but with multiple stop/start cycles in tests this would manifest as leaked state.

**Fix sketch:**
1. Promote the "should stop" signal from the fd state to an explicit `_Atomic<Bool> shouldStop` (or `OSAllocatedUnfairLock<Bool>` on macOS 13+).
2. In `acceptLoop`, check the flag *before* `accept()`.
3. Switch the per-client capture to `[weak server]` and bail out cleanly if `server` is nil.

Better yet: re-architect the loop as `Task.detached { ... }` with cancellation, but that's a bigger change and depends on having integration tests in place first. Defer until #11 is done.

**Effort/Risk:** M / Med.

---

### 4. PendingStore timeout vs explicit resolve — **P2**

**Where:** `ApprovalServer.swift:175–189`, `PendingStore.swift:20–30`.

**Symptom / risk:**
`processCheck` schedules a timeout via `DispatchQueue.main.asyncAfter(deadline: .now() + serverTimeout, execute: timeoutWork)`, and inside the resolve callback calls `timeoutWork.cancel()`. Cancellation is best-effort — if the timer has already fired and the work item is queued but not yet running, `cancel()` may be a no-op, and both paths can call `pending.resolve(id, approved: false)` and `Self.sendResponse(fd:, ...)`.

The first `sendResponse` closes `fd`. The second writes to a closed fd, which fails — and per issue #2 the failure is silently swallowed. Net result: idempotent, but messy.

**Fix sketch:**
Move the "have we resolved?" check inside `PendingStore.resolve` itself, returning a `Bool` that says "I actually resolved this one." Skip the response send if the call was a no-op:

```swift
@discardableResult
func resolve(id: String, approved: Bool) -> Bool {
    guard let entry = entries.removeValue(forKey: id) else { return false }
    pending.removeAll { $0.id == id }
    entry.onResolve(approved)
    return true
}
```

Then `processCheck`'s callback can short-circuit if the resolve was a duplicate.

**Effort/Risk:** S / Low.

---

### 5. NotificationClient: `.timeSensitive` requested without entitlement — **P1**

**Where:** `NotificationClient.swift:36, 90`.

**Symptom / risk:**
The code requests `.timeSensitive` in `requestAuthorization` and sets `content.interruptionLevel = .timeSensitive`. macOS only honours that interruption level if the app has the `com.apple.developer.usernotifications.time-sensitive` entitlement. The current build has no Entitlements.plist (verified during the v1.0 release prep — `find /Users/alex/my-pro/approval/approval -name "*.entitlements"` returns nothing). macOS silently downgrades to `.active`, which means notifications can be muffled by Focus / Do Not Disturb — exactly what `.timeSensitive` is meant to bypass.

**Fix sketch:**
Add `approval/approval.entitlements` with:
```xml
<dict>
    <key>com.apple.developer.usernotifications.time-sensitive</key>
    <true/>
</dict>
```

Wire it into `project.pbxproj` via `CODE_SIGN_ENTITLEMENTS = approval/approval.entitlements`. Note: this entitlement is granted by Apple via the Developer Portal — it's allowed in development but for distribution you need to enable the Time Sensitive Notifications capability for the App ID.

If you don't want to deal with that yet, drop the request and use `.active`. Don't leave the false advertisement of `.timeSensitive`.

**Effort/Risk:** S / Low.

---

### 6. RulesStore.save() blocks the main thread — **P2**

**Where:** `RulesStore.swift:47–49`, called from every mutation (`addRule`, `removeRule`, `toggleRule`, `updateRule`, `setMode`).

**Symptom / risk:**
Every UI edit synchronously encodes JSON and writes to disk via `data.write(to: url, options: .atomic)`. For ~5 KB rules.json on local SSD this is sub-millisecond, but the pattern is inconsistent with `LogStore`, which already does debounced async writes. If a user toggles a bunch of rules in quick succession, each toggle hits disk — a small but real waste.

**Fix sketch:**
Mirror `LogStore`'s approach: a `DispatchQueue` with a `DispatchWorkItem` that gets cancelled and rescheduled on each `save()` (debounce 200–500 ms). Add `flushSync()` and call it from `applicationWillTerminate` and `clear`-style operations.

**Effort/Risk:** M / Med (regression risk if shutdown ordering is wrong).

---

### 7. ApprovalCoordinator reads UserDefaults directly — **P2**

**Where:** `ApprovalCoordinator.swift:60`.

**Symptom / risk:**
```swift
let direct = UserDefaults.standard.bool(forKey: DefaultsKeys.directConfirmation)
```

This couples the coordinator to global mutable state. It can't be tested without polluting real UserDefaults, and the value isn't observable — if the user toggles the setting while a request is mid-flight, the coordinator picks up the new value immediately, which may not be what we want.

**Fix sketch:**
Introduce a small `SettingsStore: ObservableObject` with `@Published` properties for each user-facing setting (`directConfirmation`, `verboseNotifications`, `showInMenuBar`, `hideDockIcon`, `detailFontScale`). Persist via `UserDefaults` inside `didSet`. Inject into `AppContainer`. UI views switch from `@AppStorage` to `@EnvironmentObject var settings: SettingsStore`. Tests can pass a stub.

**Effort/Risk:** M / Low.

---

### 8. Models.Rule: legacy `builtin` field silently dropped — **P3**

**Where:** `Models.swift:32–46`.

**Symptom / risk:**
The `builtin: Bool` field was removed in commit `edcde9b`. `JSONDecoder` ignores unknown keys, so existing `rules.json` files with `"builtin": true` decode fine, but the field is lost on next save. This is a one-way migration — downgrading to v1.0.0 would lose the distinction between built-in and user rules.

The current behaviour is correct and intentional. The risk is just that it's an *implicit* contract.

**Fix sketch:**
Add a one-line comment in `Models.swift` near the `Rule` struct: `// v1.1.0 dropped the builtin distinction; existing JSON with that field decodes cleanly and re-saves without it.` That's the whole fix.

**Effort/Risk:** S / Low.

---

### 9. Test coverage gaps — **P1**

**Where:** `Tests/ApprovalCoreTests/`.

**Currently covered:** RulesStore (16 tests), LogStore (8 tests), MarkdownParser (10 tests), Models (8 tests). Total 42 unit tests, ~17 ms.

**Not covered, in order of value:**

| Path | Why it matters |
|---|---|
| `ApprovalServer` ↔ `HookHandler` round-trip | Full IPC contract. Easy to write: connect to a server bound to a temp socket path, send JSON, assert response. Catches regressions on protocol changes. |
| `WindowManager` double-resolve | The exact race fixed in issue #1. After fix, write a test that creates a window, calls `wrappedResolve(true)`, then triggers `windowWillClose` — assert `onResolve` fired exactly once with `true`. |
| `PendingStore.resolve` idempotence | Two-line test: call `resolve` twice, assert second call returns `false` and doesn't fire callback again. |
| `ApprovalCoordinator.resolve` flow | Mock `pending`, `notifications`, `windows`, `log`; assert the right sequence of calls. |
| `UnixSocket.writeLine` partial writes | Inject a mock fd that accepts only N bytes per call; verify retry loop. |

**Fix sketch:**
Add an `IPCIntegrationTests.swift` file with the round-trip test. Add `WindowManagerTests.swift` after issue #1 is fixed. The other three are trivially small.

**Effort/Risk:** M / Med (mainly the IPC test setup).

---

### 10. Test-trigger buttons live in release — **P2**

**Where:** `StatusView.swift:54–66`.

**Symptom / risk:**
Commit `5d1b9de` deliberately exposed the DROP / rm -rf / SELECT test buttons in the Release build. That's good for verifying installs end-to-end, but it's also a foot-gun — anyone tapping "DROP" thinking it's a benign label fires a real notification with an actual destructive command displayed (the command itself doesn't run, but the user might not realise).

**Fix sketch:**
Move the section under a "Developer" / "Diagnostics" disclosure (collapsed by default). Or: leave visible but rename the section to something explicit like "Test commands (won't actually run — just to verify the popup pipeline)". Keep the buttons; just frame them.

**Effort/Risk:** S / Low.

---

### 11. L10n in-memory dictionary — **P2**

**Where:** `L10n.swift:65–316` (~250 lines of static string tables).

**Symptom / risk:**
Translations live in code. SwiftUI's `Text("key")` with `LocalizedStringKey` doesn't help — the custom `tr()` method bypasses Apple's resolution chain. Adding a third language means extending the dictionary and recompiling. The Xcode tooling for localization (`Localizable.xcstrings`, automated screenshot translation, etc.) doesn't apply.

**Fix sketch:**
Migrate to `Localizable.xcstrings` (Xcode 15+). Each `tr("key")` becomes `String(localized: "key")` or just `Text("key")`. The catalog is a JSON file checked into the repo; Xcode UI handles editing. Two-step migration: first move the strings, then drop the `L10n` class entirely.

**Effort/Risk:** M / Low (mechanical; tests still pass because the strings are the same).

---

### 12. Concurrency mix is inconsistent — **P3**

**Where:** Throughout, but most visible in `ApprovalServer.swift`, `NotificationClient.swift`, `LogStore.swift`.

**Symptom / risk:**
The codebase mixes:
- `@MainActor` types (`ApprovalServer`, `ApprovalCoordinator`, `NotificationClient`, `WindowManager`, `RulesStore`, `LogStore`, `PendingStore`).
- `nonisolated static` for background work (`acceptLoop`, `handleClient`).
- `Task { @MainActor in ... }` hops back.
- `DispatchQueue.main.async { ... }` (older callbacks in `NotificationClient.send`'s completion).
- `DispatchQueue.global(qos:)` for client dispatch.
- `Thread { ... }.start()` for the accept loop.

It works, but the mental cost of reading the code is real. A canonical Swift Concurrency rewrite (background actor for the server, async stream for client connections, MainActor everything else) would be cleaner — but it's high risk without integration tests, and "works" is currently true.

**Fix sketch:**
Defer until issue #9 lands. Then re-architect in one pass: replace the Thread with `Task.detached`, the DispatchQueue with structured concurrency, the manual flag with `Task.cancel()`. Keep `@MainActor` annotations on the types that touch UI state.

**Effort/Risk:** L / High.

---

### 13. Build & release: no signing, no notarization, no DMG — **P3**

**Where:** `project.pbxproj` (no `CODE_SIGN_IDENTITY` or notarization config), no Entitlements.plist, no GitHub Actions for release builds, manual `xcodebuild + cp -R` flow.

**Symptom / risk:**
Currently you build locally, copy to `/Applications`, strip quarantine with `xattr -dr`. Fine for the developer's own machine; doesn't scale to anyone else without "I trust you" Gatekeeper waivers.

**Fix sketch:**
Out of scope for code refactoring, but worth noting. The path forward:
1. Apple Developer ID + entitlements (covers issue #5 too).
2. `xcodebuild archive` + `notarytool submit` in a release script.
3. `create-dmg` for distribution.
4. GitHub Release with the signed DMG attached (`gh release create vX.Y.Z signed.dmg`).
5. (later) Sparkle for in-app updates.

**Effort/Risk:** L / Med.

---

## What's already done from the old REFACTORING.md

For context, items the old document listed that are now resolved:
- DI container instead of singletons → done (`AppContainer` in `approvalApp.swift`).
- `ContentView` decomposition → done (`StatusView`, `RulesView`, `LogView`, `InstallView`, `SettingsView`, `AppSection`).
- Coordinator split → done (`ApprovalCoordinator` + `NotificationClient` + `WindowManager`).
- L10n RU/EN → done (still in-memory; see issue #11).
- Test coverage for stores → done (42 tests).
- Single-instance guard → done (commit `ec82d4c`).
- `.timeSensitive` request in auth options → done (commit `1ee92b4`); but see issue #5 for missing entitlement.
- Tests hidden in DEBUG → reverted by design (commit `5d1b9de`); see issue #10 for framing.

---

## Recommended next 3 actions

### 1. Fix `WindowManager` double-resolve race + add a test (1–2 h)
Convert the `didResolve` flag into a `removeValue`-based check inside `wrappedResolve`. Write a unit test in a new `WindowManagerTests.swift` that opens a window, calls Cancel, then synchronously fires `windowWillClose` — assert `onResolve` was called exactly once with `false`.

**Unblocks:** Issues #1 and partially #4 (cleaner resolve idempotence).

### 2. Add IPC round-trip test + fix silent write failures (2–3 h)
Create `IPCIntegrationTests.swift` that binds an `ApprovalServer` to a temp socket path, runs `HookHandler` logic in-process against it, and asserts the response. While there, change `sendResponse` to log write failures via `os.Logger`. This single PR closes issues #2 and #9-first-row.

**Unblocks:** All future server-side refactors (issue #3, #12) because you'll have a test net.

### 3. Add the `.timeSensitive` entitlement (or remove the request) (30 min)
Pick one. If keeping: create `approval/approval.entitlements` with the key, wire `CODE_SIGN_ENTITLEMENTS` in `project.pbxproj`. If dropping: change `.timeSensitive` to `.active` in both spots in `NotificationClient.swift` and document the reason. The current state — requesting a level that's silently downgraded — is the worst of both worlds.

**Unblocks:** Issue #5; closes the gap between the README's promise and the actual behaviour under Focus mode.

---

## Closing notes

The codebase is in good shape for v1.x. The DI pattern, storage layer, and IPC foundation are all reasonable. The three "do soon" items above are all small, well-scoped, and low-risk. The medium-term items (debounced `RulesStore`, `SettingsStore`, xcstrings migration) are nice-to-haves that improve testability and maintainability but don't gate any new features. The long-term items (concurrency overhaul, signing/notarization/DMG) are real work but predictable.

Avoid the temptation to do a sweeping concurrency rewrite before the integration tests land — that's the order in which to do this.
