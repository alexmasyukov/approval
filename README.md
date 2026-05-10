# approval

<img width="614" height="500" alt="image" src="https://github.com/user-attachments/assets/aa09d0fa-0f6f-4433-8cf3-89a6ee47e294" />

---

A native macOS app that intercepts dangerous shell commands from [Claude Code](https://claude.com/claude-code) (and similar coding assistants) and asks you for explicit confirmation before they run.

If your AI assistant ever tries to drop a database, truncate a table, or `rm -rf` something it shouldn't — `approval` catches it, sends you a system notification, and waits for you to approve or deny.

> **Status:** v1.0 — first public release. Hand-tested on macOS 26+. Not signed/notarized yet — build from source for now.

---

## Why

Coding assistants are useful, but giving them shell access is a tradeoff. Most of the time they run boring stuff — `git status`, `npm test`, `ls`. But occasionally they decide to:

- `DROP TABLE users` while debugging migrations
- `rm -rf node_modules` and pick the wrong directory
- `TRUNCATE TABLE logs` to "clean up"
- `psql -c "DELETE FROM orders"` to "fix" data

A single misfire on a real database is a very bad day. `approval` adds a tiny human-in-the-loop step for the dangerous things, while staying out of your way for everything else.

---


<img width="906" height="620" alt="image" src="https://github.com/user-attachments/assets/0bf58237-cb40-4d2f-a1db-8ea1b702ac8b" />


## How it feels to use

1. You install the app and add a one-line entry to your Claude Code settings.
2. You work normally. 99% of commands flow straight through — no popups, no clicks, no slowdown. The hook adds ~20 ms.
3. When the assistant tries to run something that matches a danger rule (drops, truncates, destructive deletes, `rm -rf`, etc.), you get a **macOS system notification**:
   > ⚠️ Dangerous command requires confirmation
4. Tap the notification → a window opens with the full details:
   - The exact command
   - Where it came from (working directory)
   - Which rule matched
   - The reason given by the assistant (when available)
5. You click **Approve** or **Cancel**.
   - **Approve** → the command runs as if nothing happened.
   - **Cancel** → the command is blocked, the assistant sees an error message and moves on.

You can also dismiss the notification from **Notification Center** (swipe it away there, or hit *Clear*) — that counts as **Cancel**. Note: just swiping the corner banner only hides it, the request stays open until you act on it from Notification Center, the detail window, or the request times out (10 min).

If `approval` isn't running, the hook fails open with a warning to stderr — your assistant still works, you just don't get the safety net until you launch the app.

---

## Features

- **Built-in danger rules** — `DROP TABLE/DATABASE`, `TRUNCATE`, `DELETE FROM ... ;`, `rm -rf`, `psql/mysql -c "..."`, `ALTER TABLE ... DROP COLUMN`, MongoDB `.drop()/.dropDatabase()`, Redis `FLUSHALL/FLUSHDB`.
- **Custom rules** — add your own regex patterns through a native form. Each rule has a name, a pattern, an on/off switch, and lives in a JSON file you can edit by hand.
- **Two modes** — *Validate & notify* (default) and *Pass-through* (for when you don't want to be interrupted; a bright red banner reminds you it's on).
- **Per-request detail window** — every notification opens its own native window. You can have multiple pending approvals, decide them in any order, and they don't block your other work.
- **Verbose / minimal notifications** — a toggle in *Settings*. Verbose shows full title and body; minimal is one short line.
- **Direct-confirmation mode** — toggle in *Settings → Notifications*. Skips the system notification entirely and opens the request window immediately, activating the app to the foreground. Handy when you're at the keyboard and want one click instead of *click banner → click button*.
- **Activity log** — last 100 filtered requests with timestamp, matched rule, decision (approved / denied / pending). Click "Open folder" to find the JSON file.
- **🇷🇺 Russian + 🇬🇧 English UI** — switchable from *Settings → Interface language*. Applies instantly without restart, including the install instructions.
- **Menu bar icon (optional)** — a `staroflife.fill` lives in the menu bar with a count of pending requests; switches to a red `exclamationmark.triangle.fill` when something needs your attention. Toggleable.
- **Hide Dock icon (optional)** — runs as `.accessory`, freeing the Dock and Cmd+Tab. Switches on the fly without restart. Locked behind the menu-bar toggle so you can't lose access to the UI.
- **macOS Settings.app look** — `Form { Section { ... } }.formStyle(.grouped)`, `LabeledContent`, `NavigationSplitView` with sidebar. Native, not a web view.

---

## Installation

> Until v1.0 ships with a signed DMG, build from source.

```bash
git clone https://github.com/alexmasyukov/approval.git
cd approval
cp Local.xcconfig.example Local.xcconfig
# edit Local.xcconfig and set your DEVELOPMENT_TEAM
open approval.xcodeproj
```

In Xcode → ⌘R.

Then open the **Install hook** tab inside the app — it shows the exact JSON to paste into `~/.claude/settings.json`, with the absolute path to the binary already filled in. Restart Claude Code, and you're done.

---

## How it works (technical, brief)

```
┌──────────────────┐  posix_spawn   ┌─────────────────────┐
│  Claude Code     │ ─────────────▶ │ approval --hook     │
│  (your IDE)      │  stdin pipe    │ short-lived process │
└──────────────────┘                └──────────┬──────────┘
        ▲                                       │
        │ exit code 0 / 2                       │ Unix domain socket
        │                                       ▼
┌──────────────────┐                ┌─────────────────────┐
│  Bash tool       │ ◀───block──── │  approval.app       │
│  blocked / runs  │                │  (long-lived GUI)   │
└──────────────────┘                │  ┌──────────────┐   │
                                    │  │ RulesStore   │   │
                                    │  │ Notification │   │
                                    │  │ Window       │   │
                                    │  └──────────────┘   │
                                    └─────────────────────┘
                                              ▲
                                              │ user clicks
                                              │ Approve / Cancel
                                              │
                                       👤 You (in the UI)
```

Three processes:

- **Claude Code** spawns a `PreToolUse` hook for each `Bash` tool call.
- **`approval --hook`** is the same `.app` binary launched with a flag. It reads the JSON command from stdin, opens a Unix domain socket to the GUI, sends `{"command": ..., "cwd": ...}`, blocks waiting for a JSON response, then exits with `0` (allow) or `2` (block, with a stderr message).
- **`approval.app`** is the long-lived GUI. It evaluates the command against the rules, posts a `UNUserNotification`, opens an `NSWindow` per request when you tap the notification, and writes the user's decision back into the still-open socket connection — closing it triggers the hook to exit.

Stack:

- **Swift 5.10**, **SwiftUI** for everything UI, **AppKit** where needed (windows, pasteboard, file viewer reveal).
- **Network framework was tried but abandoned** in favor of raw POSIX sockets for simpler IPC — TCP was overkill, port management noisy, Unix sockets give file-system-level access control for free.
- **`UserDefaults`** for the verbose-notifications toggle, **`~/Library/Application Support/approval/`** for `rules.json` and `log.json`.
- **App Sandbox is off** for the prototype — needed for incoming socket and direct `~/Library` access. A future signed/sandboxed version will use entitlements and the container path.

See `REFACTORING.md` for what's planned to be cleaned up before v1.0.

---

## Roadmap

- [ ] In-app "Install Hook" button (write to `~/.claude/settings.json` automatically)
- [ ] Code signing + notarization
- [ ] Signed DMG release on GitHub Releases
- [ ] Sparkle-based auto-update
- [x] Menu bar mode (no Dock icon)
- [x] English UI localization
- [x] Tests (49 unit tests via `swift test`)
- [ ] Re-enable App Sandbox with proper entitlements

---

## License

MIT — see [LICENSE](LICENSE) (TBD).

## Contributing

Issues and PRs welcome. The codebase is small (~1.5k LOC of Swift) and easy to read top-to-bottom.

### Running tests

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swift test
```

49 unit tests covering `MarkdownParser`, `RulesStore` (rule matching, persistence, corruption recovery), `LogStore` (ring buffer, sync flush, codable round-trips), `PendingStore` (add/resolve/idempotence), and the data models. Run in <20 ms.
