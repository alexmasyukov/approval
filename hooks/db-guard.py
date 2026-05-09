#!/usr/bin/env python3
"""
PreToolUse-хук для Claude Code: перехватывает Bash-команды и шлёт их
на локальный approval-сервер (http://localhost:47823/check). Сервер
проверяет команду по правилам и либо сразу пропускает, либо ждёт
решения пользователя через системное оповещение и окно с деталями.

exit 0 — пропустить команду
exit 2 — заблокировать (Claude Code увидит сообщение из stderr)
"""

import json
import sys
import urllib.error
import urllib.request

APPROVAL_URL = "http://localhost:47823/check"
TIMEOUT_SECONDS = 600  # 10 минут — должно совпадать с timeout в settings.json


def main() -> None:
    try:
        data = json.load(sys.stdin)
    except Exception:
        sys.exit(0)

    if data.get("tool_name") != "Bash":
        sys.exit(0)

    cmd = (data.get("tool_input") or {}).get("command", "")
    cwd = data.get("cwd", "")

    if not cmd:
        sys.exit(0)

    payload = json.dumps(
        {"command": cmd, "cwd": cwd, "source": "Claude Code"}
    ).encode("utf-8")

    req = urllib.request.Request(
        APPROVAL_URL,
        data=payload,
        headers={"Content-Type": "application/json"},
        method="POST",
    )

    try:
        with urllib.request.urlopen(req, timeout=TIMEOUT_SECONDS) as resp:
            body = json.loads(resp.read())
    except (urllib.error.URLError, ConnectionError, TimeoutError) as exc:
        # Approval-сервер не запущен — fail open с предупреждением.
        # Claude Code увидит этот warning в stderr.
        print(
            f"approval hook: сервер недоступен ({exc}); пропускаю без проверки",
            file=sys.stderr,
        )
        sys.exit(0)
    except Exception as exc:  # noqa: BLE001
        print(f"approval hook: ошибка ({exc}); пропускаю", file=sys.stderr)
        sys.exit(0)

    if body.get("approved"):
        sys.exit(0)
    else:
        reason = body.get("reason", "denied")
        print(f"Команда отклонена через approval app: {reason}", file=sys.stderr)
        sys.exit(2)


if __name__ == "__main__":
    main()
