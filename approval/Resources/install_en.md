# Install hook

To make Claude Code ask for confirmation before dangerous commands, register `approval` as a `PreToolUse` hook.

## 1. Move the app to `/Applications`

Drag `approval.app` from the DMG into your `Applications` folder. This gives the binary a stable path that won't break when you update.

The app is currently running from:

```
{{APP_PATH}}
```

## 2. Launch the app

Open `approval` from Launchpad. On first launch macOS will ask for permission to send notifications — click "Allow". On the **Status** page, make sure the indicator is green and the server is listening.

## 3. Add the hook to `~/.claude/settings.json`

Open (or create) `~/.claude/settings.json` and add a `hooks` block:

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "{{APP_BIN}} --hook",
            "timeout": 600
          }
        ]
      }
    ]
  }
}
```

If the file already exists with other settings, only add the `hooks` section to the root object — don't overwrite the rest.

Alternatively, for a single project: put the same file at `<project>/.claude/settings.json`.

## 4. Restart Claude Code

Close all Claude Code terminals and reopen them — settings are picked up on session start.

## Verify

In Claude Code, ask it to run a dangerous command, e.g.:

```
run: docker exec ... psql -c "DROP TABLE test"
```

You should get a system notification from `approval`. Tap it — a window opens with details. Click **Approve** or **Cancel** — Claude Code receives the corresponding response.

## Uninstall

1. Remove the `hooks.PreToolUse` block from `~/.claude/settings.json`.
2. Move `approval.app` to the Trash.
3. (optional) remove app data: `rm -rf ~/Library/Application\ Support/approval`.
