#!/usr/bin/env python3
"""
Time-awareness hook for Claude Code / Codex / Antigravity CLIs.

Ports https://gist.github.com/asakin/e4225721bb8f16dd6bc34f4eec5499f9
(v2 repo: github.com/asakin/claude-context-hook).

Wired by agent-skills-temporal for UserPromptSubmit + SessionStart on all
three CLIs. State directory is per-CLI via $TEMPORAL_STATE_DIR.

Env:
  TEMPORAL_STATE_DIR  Override the state directory (set by the plugin).
                      Defaults to ~/.claude/.temporal for backward compat.
  TEMPORAL_INTERVAL   Min seconds between UserPromptSubmit injects (default 300, 0=always).
  TEMPORAL_TTL_DAYS   Days before a stale session JSON is swept (default 7).
"""

import json, os, sys, time
from datetime import datetime, timezone
from pathlib import Path

INTERVAL_S = int(os.environ.get("TEMPORAL_INTERVAL", 300))
TTL_S      = int(os.environ.get("TEMPORAL_TTL_DAYS", 7)) * 86400
DIR        = Path(os.environ.get("TEMPORAL_STATE_DIR", str(Path.home() / ".claude" / ".temporal")))


def fmt(s):
    if s < 60:   return f"{s}s"
    if s < 3600: return f"{s // 60}m{s % 60:02d}s"
    return f"{s // 3600}h{(s % 3600) // 60:02d}m"


def emit(event, context):
    print(json.dumps({"hookSpecificOutput":
        {"hookEventName": event, "additionalContext": context}}))


def main():
    raw = sys.stdin.read().strip()
    data = json.loads(raw) if raw else {}
    event = data.get("hook_event_name", "")

    DIR.mkdir(parents=True, exist_ok=True)

    for old in DIR.glob("*.json"):
        try:
            if time.time() - old.stat().st_mtime > TTL_S:
                old.unlink(missing_ok=True)
        except OSError:
            pass

    f = DIR / f"{data.get('session_id', 'nosession')}.json"
    try:
        s = json.loads(f.read_text()) if f.exists() else {}
    except (OSError, json.JSONDecodeError):
        s = {}

    now_ms = int(time.time() * 1000)
    utc, local = datetime.now(timezone.utc), datetime.now().astimezone()

    session_s = (now_ms - s.setdefault("start_ms", now_ms)) // 1000
    stamp = (f"now={local:%H:%M} {local:%Z} | utc={utc:%Y-%m-%dT%H:%M:%SZ} | "
             f"unix_ms={now_ms} | session={fmt(session_s)}")

    if event == "UserPromptSubmit":
        if INTERVAL_S == 0 or (now_ms - s.get("last_inject_ms", 0)) // 1000 >= INTERVAL_S:
            s["last_inject_ms"] = now_ms
            emit(event, f"[⏱ {stamp}]")
    elif event == "SessionStart":
        # Fire on compact (post-compaction context refresh), and best-effort on
        # startup/resume so users see a timestamp at the top of fresh sessions.
        source = data.get("source", "")
        if source == "compact":
            emit(event, f"[⏱ post-compaction time check — {stamp}]")
        elif source in ("startup", "resume", ""):
            emit(event, f"[⏱ {stamp}]")

    try:
        f.write_text(json.dumps(s))
    except OSError:
        pass


if __name__ == "__main__":
    main()
