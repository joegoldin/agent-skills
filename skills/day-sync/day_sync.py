#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11"
# dependencies = ["requests"]
# ///
"""day-sync: brief the user on their day/week from Notion + Google Calendar
+ GitHub PRs, optionally inserting missing items into today's daily note in
an Obsidian vault.

Read-only against Notion, the calendar, and GitHub; writes only the daily
note. Configuration lives in ~/.config/day-sync/config.json (override the
path via DAY_SYNC_CONFIG) — see SKILL.md for the keys.
"""
from __future__ import annotations

import argparse
import difflib
import json
import os
import re
import sys
from datetime import date, datetime, time, timedelta
from pathlib import Path
from zoneinfo import ZoneInfo

CONFIG_FILE = Path(os.environ.get("DAY_SYNC_CONFIG", "~/.config/day-sync/config.json")).expanduser()
try:
    CONFIG = json.loads(CONFIG_FILE.read_text())
except (OSError, ValueError):
    CONFIG = {}


def _cfg(key: str, default=None, env: str | None = None):
    if env and os.environ.get(env):
        return os.environ[env]
    return CONFIG.get(key, default)


NOTION_BASE = "https://api.notion.com/v1"
NOTION_VERSION = "2025-09-03"
NOTION_USER_ID = _cfg("notion_user_id")
NOTION_DATA_SOURCE_ID = _cfg("notion_data_source_id")
NOTION_TOKEN_FILE = Path(_cfg("notion_token_file", "~/.config/day-sync/notion-token",
                              env="NOTION_TOKEN_FILE")).expanduser()
TZ = ZoneInfo(_cfg("timezone", "America/Los_Angeles"))
VAULT = Path(_cfg("vault", ".", env="DAY_SYNC_VAULT")).expanduser()
JOURNAL = VAULT / _cfg("journal", "Notes/Journal")
GWS_BIN = _cfg("gws_bin", "gws", env="GWS_BIN")
GH_BIN = _cfg("gh_bin", "gh", env="GH_BIN")
GH_ORG = _cfg("gh_org")  # PR section is skipped entirely when unset
WORK_TAG = _cfg("work_tag", "#work")
# Optional sprint awareness: tasks that belong to the sprint whose date range
# contains today get flagged, sorted first, and preselected for insertion.
# Leave notion_sprint_data_source_id unset to skip sprint handling entirely.
NOTION_SPRINT_DATA_SOURCE_ID = _cfg("notion_sprint_data_source_id")
SPRINT_RELATION_PROP = _cfg("notion_sprint_relation_prop", "Sprint")
SPRINT_DATES_PROP = _cfg("notion_sprint_dates_prop", "Dates")

# Statuses treated as "done" client-side (plate + sync-back baseline)…
PLATE_EXCLUDE = {s.lower() for s in _cfg("done_statuses", ["done", "complete", "released", "archived"])}
# …plus ones where the human already did the work even if not shipped.
SYNC_DONEISH = PLATE_EXCLUDE | {s.lower() for s in _cfg("almost_done_statuses", ["ready for release"])}
# Optional server-side status excludes. Notion rejects filters naming
# nonexistent options, so this MUST match your DB's real option names;
# empty default = filter client-side only.
QUERY_EXCLUDE_STATUSES = _cfg("query_exclude_statuses", [])
# Statuses that mean "not yet started" for the [/]-in-vault sync-back hint.
UNSTARTED_STATUSES = {s.lower() for s in _cfg("unstarted_statuses", ["not started", "to-do", "todo", "backlog", "scoping"])}

TASK_LINE = re.compile(r"^\s*- \[(.)\] (.*\S)")
# Matches bare `🅽 <id>` and titled `🅽 [Title](<id>)`
NOTION_MARK = re.compile(r"🅽 ?(?:\[[^\]]*\]\()?([0-9a-fA-F]{32}|[0-9a-fA-F-]{36})\)?")
HARD_STOP = re.compile(r"^- \[.\] .*hard stop", re.IGNORECASE)
BLANK_SLOT = re.compile(r"^- \[ \]\s*$")


def fmt_time(dt: datetime) -> str:
    h = dt.hour % 12 or 12
    ap = "a" if dt.hour < 12 else "p"
    return f"{h}:{dt.minute:02d}{ap}" if dt.minute else f"{h}{ap}"


def normalize(s: str) -> str:
    return re.sub(r"\s+", " ", re.sub(r"[^a-z0-9 ]", " ", s.lower())).strip()


def bare_id(nid: str) -> str:
    return nid.replace("-", "").lower()


def scan_journal(journal: Path) -> dict[str, list[dict]]:
    """All 🅽 markers on task lines across the journal, keyed by bare id."""
    marks: dict[str, list[dict]] = {}
    for f in sorted(journal.glob("*.md")):
        for i, line in enumerate(f.read_text().splitlines()):
            t = TASK_LINE.match(line)
            if not t:
                continue
            for m in NOTION_MARK.finditer(line):
                marks.setdefault(bare_id(m.group(1)), []).append(
                    {"path": str(f), "line_no": i, "state": t.group(1), "text": t.group(2)}
                )
    return marks


def today_section(lines: list[str]) -> tuple[int, int]:
    """(start, end) line indices of the '## Today' section body; end exclusive."""
    start = next(i for i, l in enumerate(lines) if l.strip() == "## Today") + 1
    end = len(lines)
    for j in range(start, len(lines)):
        if lines[j].startswith("## ") or lines[j].strip() == "---":
            end = j
            break
    return start, end


def open_tasks_in(text: str) -> list[str]:
    out = []
    for line in text.splitlines():
        m = TASK_LINE.match(line)
        if m and m.group(1) in " /":
            out.append(m.group(2))
    return out


def insert_into_note(text: str, event_lines: list[str], task_lines: list[str]) -> str:
    """Events go before the 'hard stop' line (else end of Today section);
    tasks go after the first blank '- [ ]' slot (else top of section)."""
    lines = text.splitlines()
    start, end = today_section(lines)
    if task_lines:
        at = next((i + 1 for i in range(start, end) if BLANK_SLOT.match(lines[i])), start + 1)
        lines[at:at] = task_lines
        end += len(task_lines)
    if event_lines:
        at = next((i for i in range(start, end) if HARD_STOP.match(lines[i])), end - 1)
        lines[at:at] = event_lines
    return "\n".join(lines) + ("\n" if text.endswith("\n") else "")


def sync_back(marks: dict[str, list[dict]], notion_by_id: dict[str, dict]) -> list[dict]:
    """Vault state ahead of Notion → advisory items."""
    out = []
    for bid, occs in marks.items():
        task = notion_by_id.get(bid)
        if not task:
            continue
        state = max(occs, key=lambda o: o["path"])["state"]  # newest note wins
        s = task["status"].lower()
        if state == "x" and s not in SYNC_DONEISH:
            what = f"you finished this — move it out of “{task['status']}”"
        elif state == "-" and s not in SYNC_DONEISH:
            what = f"you cancelled this locally — close or archive it (currently “{task['status']}”)"
        elif state == "/" and s in UNSTARTED_STATUSES:
            what = "you started this — move it to In progress"
        else:
            continue
        out.append({"title": task["title"], "url": task["url"], "status": task["status"],
                    "vault_state": state, "suggestion": what})
    return out


def conflicts_and_gaps(events: list[dict]) -> tuple[list, list]:
    timed = sorted([e for e in events if not e["all_day"]], key=lambda e: e["start"])
    conflicts, gaps = [], []
    for a, b in zip(timed, timed[1:]):
        if b["start"] < a["end"]:
            conflicts.append((a["title"], b["title"]))
        else:
            gap = (b["start"] - a["end"]).total_seconds() / 60
            if gap >= 45 and a["end"].hour >= 9 and b["start"].hour < 18:
                gaps.append((fmt_time(a["end"]), fmt_time(b["start"]), int(gap)))
    return conflicts, gaps


STATUS_ORDER = {"in progress": 0, "to-do": 1, "not started": 2}


def parse_notion_page(page: dict) -> dict:
    props = page.get("properties", {})

    def plain(rich):
        return "".join(t.get("plain_text", "") for t in (rich or []))

    title = ""
    due = None
    sprints: list[str] = []
    for name, val in props.items():
        if (val or {}).get("type") == "title":
            title = plain(val.get("title"))
        if "due" in name.lower() and (val or {}).get("type") == "date":
            start = (val.get("date") or {}).get("start")
            due = start[:10] if start else None
        if name == SPRINT_RELATION_PROP and (val or {}).get("type") == "relation":
            sprints = [bare_id(r.get("id", "")) for r in (val.get("relation") or [])]
    status = (((props.get("Status") or {}).get("status")) or {}).get("name", "")
    pid = page.get("id", "")
    return {"id": pid, "bare": bare_id(pid), "url": page.get("url", ""),
            "title": title, "status": status, "due": due,
            "sprints": sprints, "in_sprint": False}


def notion_sort_key(t: dict):
    s = t["status"].lower()
    return (0 if t.get("in_sprint") else 1,
            STATUS_ORDER.get(s, 3), s, t["due"] or "9999-99-99", t["title"].lower())


def _notion_headers() -> dict:
    token = NOTION_TOKEN_FILE.read_text().strip()
    return {"Authorization": f"Bearer {token}", "Notion-Version": NOTION_VERSION,
            "Content-Type": "application/json"}


def _notion_query(data_source_id: str, body: dict) -> list[dict]:
    import requests

    headers = _notion_headers()
    results, cursor = [], None
    while True:
        if cursor:
            body["start_cursor"] = cursor
        r = requests.post(f"{NOTION_BASE}/data_sources/{data_source_id}/query",
                          headers=headers, json=body, timeout=30)
        r.raise_for_status()
        data = r.json()
        results.extend(data.get("results", []))
        if not data.get("has_more"):
            break
        cursor = data.get("next_cursor")
    return results


def fetch_notion_tasks() -> list[dict]:
    if not NOTION_USER_ID or not NOTION_DATA_SOURCE_ID:
        raise RuntimeError(f"set notion_user_id + notion_data_source_id in {CONFIG_FILE}")
    conds = [{"property": "Assignee", "people": {"contains": NOTION_USER_ID}}]
    for s in QUERY_EXCLUDE_STATUSES:
        conds.append({"property": "Status", "status": {"does_not_equal": s}})
    body = {"filter": {"and": conds} if len(conds) > 1 else conds[0], "page_size": 100}
    results = _notion_query(NOTION_DATA_SOURCE_ID, body)
    tasks = [parse_notion_page(p) for p in results]
    tasks = [t for t in tasks if t["status"].lower() not in PLATE_EXCLUDE]
    tasks.sort(key=notion_sort_key)
    return tasks


def parse_sprint_page(page: dict) -> dict:
    props = page.get("properties", {})
    title = ""
    start = end = None
    for name, val in props.items():
        if (val or {}).get("type") == "title":
            title = "".join(t.get("plain_text", "") for t in (val.get("title") or []))
        elif name == SPRINT_DATES_PROP and (val or {}).get("type") == "date" \
                and (val.get("date") or {}).get("start"):
            d = val["date"]
            start = d["start"][:10]
            end = (d.get("end") or d["start"])[:10]
    pid = page.get("id", "")
    return {"id": pid, "bare": bare_id(pid), "title": title, "start": start, "end": end}


def pick_current_sprint(sprints: list[dict], today: date) -> dict | None:
    """The sprint whose date range contains `today`. Dates are authoritative
    (the Status field lags). On overlap the latest-starting sprint wins."""
    td = today.isoformat()
    active = sorted((s for s in sprints if s["start"] and s["end"] and s["start"] <= td <= s["end"]),
                    key=lambda s: s["start"])
    return active[-1] if active else None


def fetch_current_sprint(today: date) -> dict | None:
    if not NOTION_SPRINT_DATA_SOURCE_ID:
        return None
    sprints = [parse_sprint_page(p)
               for p in _notion_query(NOTION_SPRINT_DATA_SOURCE_ID, {"page_size": 100})]
    return pick_current_sprint(sprints, today)


def parse_gcal_events(items: list[dict]) -> list[dict]:
    """Google Calendar API event resources → our event dicts."""
    out = []
    for it in items:
        if it.get("status") == "cancelled":
            continue
        s, e = it.get("start", {}), it.get("end", {})
        all_day = "date" in s
        if all_day:
            st = date.fromisoformat(s["date"])
            en = date.fromisoformat(e.get("date", s["date"]))
        else:
            st = datetime.fromisoformat(s["dateTime"]).astimezone(TZ)
            en = datetime.fromisoformat(e.get("dateTime", s["dateTime"])).astimezone(TZ)
        out.append({"title": it.get("summary", ""), "start": st, "end": en, "all_day": all_day})
    out.sort(key=lambda ev: (str(ev["start"]), ev["title"]))
    return out


def fetch_events(start_d: date, end_d: date) -> list[dict]:
    import subprocess

    params = {
        "calendarId": "primary",
        "timeMin": datetime.combine(start_d, time.min, tzinfo=TZ).isoformat(),
        "timeMax": datetime.combine(end_d + timedelta(days=1), time.min, tzinfo=TZ).isoformat(),
        "singleEvents": True,
        "orderBy": "startTime",
        "maxResults": 2500,
        "eventTypes": ["default", "outOfOffice"],  # drop workingLocation/birthday noise
    }
    try:
        r = subprocess.run([GWS_BIN, "calendar", "events", "list", "--params", json.dumps(params)],
                           capture_output=True, text=True, timeout=60)
    except FileNotFoundError:
        raise RuntimeError("gws CLI not found — install googleworkspace/cli and run `gws auth login`") from None
    if r.returncode != 0:
        raise RuntimeError(f"gws failed (try `gws auth login`): {r.stderr.strip()[:200]}")
    return parse_gcal_events(json.loads(r.stdout).get("items", []))


def _gh_search(extra: list[str]) -> list[dict]:
    import subprocess

    fields = "title,url,repository,number,state,isDraft,updatedAt"
    r = subprocess.run([GH_BIN, "search", "prs", "--owner", GH_ORG, "--json", fields,
                        "--limit", "50", *extra], capture_output=True, text=True, timeout=60)
    if r.returncode != 0:
        raise RuntimeError(f"gh search failed: {r.stderr.strip()[:200]}")
    return json.loads(r.stdout)


def fetch_prs() -> list[dict]:
    import subprocess

    week_ago = (datetime.now(TZ) - timedelta(days=7)).date().isoformat()
    raw = (
        [(p, "authored") for p in _gh_search(["--author", "@me", "--state", "open"])]
        + [(p, "review") for p in _gh_search(["--review-requested", "@me", "--state", "open"])]
        + [(p, "merged") for p in _gh_search(["--author", "@me", "--merged", "--merged-at", f">={week_ago}"])]
    )
    seen, prs = set(), []
    for p, kind in raw:
        repo = p["repository"]["name"] if isinstance(p.get("repository"), dict) else str(p.get("repository", ""))
        key = (repo, p["number"])
        if key in seen:
            continue
        seen.add(key)
        prs.append({"repo": repo, "number": p["number"], "title": p["title"], "url": p["url"],
                    "kind": kind, "draft": bool(p.get("isDraft")), "decision": ""})
    for pr in prs:  # enrich open authored PRs with review state
        if pr["kind"] != "authored":
            continue
        r = subprocess.run([GH_BIN, "pr", "view", pr["url"], "--json", "reviewDecision"],
                           capture_output=True, text=True, timeout=30)
        if r.returncode == 0:
            pr["decision"] = json.loads(r.stdout).get("reviewDecision") or ""
    return prs


def _tokens(s: str) -> set[str]:
    return {t for t in normalize(s).split() if len(t) > 3}


def fallback_correlate(prs: list[dict], notion: list[dict], todos: list[str]) -> dict:
    matches, actionable = [], []
    for pr in prs:
        pt = _tokens(pr["title"])
        n = next((t for t in notion if len(pt & _tokens(t["title"])) >= 2), None)
        td = next((t for t in todos if len(pt & _tokens(t)) >= 2), None)
        if n or td:
            sugg = ("merged — check off the todo / mark the Notion task done"
                    if pr["kind"] == "merged" else "open PR lines up with this work")
            matches.append({"repo": pr["repo"], "number": pr["number"],
                            "notion_bare_id": n["bare"] if n else None,
                            "todo": td, "relation": pr["kind"], "suggestion": sugg})
        if pr["kind"] == "review":
            actionable.append({"repo": pr["repo"], "number": pr["number"],
                               "action": "review requested — needs your review"})
    return {"matches": matches, "actionable": actionable}


def pr_in_note(pr: dict, note_text: str) -> bool:
    if f"#{pr['number']}" in note_text and pr["repo"] in note_text:
        return True
    n = normalize(pr["title"])
    return any(n and n in normalize(l) for l in note_text.splitlines() if TASK_LINE.match(l))


def correlate(prs: list[dict], notion: list[dict], todos: list[str]) -> dict:
    import subprocess

    if not prs:
        return {"matches": [], "actionable": []}
    payload = {
        "prs": [{k: p[k] for k in ("repo", "number", "title", "kind", "draft", "decision")} for p in prs],
        "notion_tasks": [{"bare_id": t["bare"], "title": t["title"], "status": t["status"]} for t in notion],
        "todos": todos,
    }
    prompt = (
        "You correlate GitHub PRs with Notion tasks and today's todo lines. "
        "Input JSON follows. Reply with ONLY minified JSON, no prose/fences, shaped: "
        '{"matches":[{"repo":str,"number":int,"notion_bare_id":str|null,"todo":str|null,'
        '"relation":"authored|review|merged","suggestion":str}],'
        '"actionable":[{"repo":str,"number":int,"action":str}]}. '
        "Match only when clearly the same work. Suggestions: merged→'check off / mark the Notion task done'; "
        "changes_requested→flag for today; review kind→needs review. Input: "
        + json.dumps(payload)
    )
    try:
        r = subprocess.run(["claude", "-p", prompt, "--output-format", "json"],
                           capture_output=True, text=True, timeout=120)
        if r.returncode != 0:
            raise RuntimeError(r.stderr.strip()[:200])
        result = json.loads(r.stdout).get("result", "")
        result = re.sub(r"^```(json)?|```$", "", result.strip(), flags=re.M).strip()
        out = json.loads(result)
        assert isinstance(out.get("matches"), list) and isinstance(out.get("actionable"), list)
        return out
    except Exception:  # noqa: BLE001 — matcher down ≠ brief down
        return fallback_correlate(prs, notion, todos)


def gather(week: bool = False) -> dict:
    today = datetime.now(TZ).date()
    data = {"date": today.isoformat(), "events": [], "notion": [], "note": {},
            "sync_back": [], "warnings": [], "sprint": None}
    try:
        data["notion"] = fetch_notion_tasks()
    except Exception as e:  # noqa: BLE001 — degrade, don't die
        data["warnings"].append(f"notion: {e}")
    try:
        sprint = fetch_current_sprint(today)
        data["sprint"] = sprint
        if sprint and data["notion"]:
            for t in data["notion"]:
                t["in_sprint"] = sprint["bare"] in t.get("sprints", [])
            data["notion"].sort(key=notion_sort_key)
    except Exception as e:  # noqa: BLE001 — sprint down ≠ brief down
        data["warnings"].append(f"sprint: {e}")
    end = today + timedelta(days=6) if week else today
    try:
        data["events"] = fetch_events(today, end)
    except Exception as e:  # noqa: BLE001
        data["warnings"].append(f"calendar: {e}")
    if GH_ORG:
        try:
            data["prs"] = fetch_prs()
        except Exception as e:  # noqa: BLE001
            data["prs"] = []
            data["warnings"].append(f"github: {e}")
    else:
        data["prs"] = []
    note_file = JOURNAL / f"{today.isoformat()}.md"
    if note_file.exists():
        text = note_file.read_text()
        data["note"] = {"path": str(note_file), "open_tasks": open_tasks_in(text)}
    else:
        data["warnings"].append(f"no daily note at {note_file}")
    marks = scan_journal(JOURNAL)
    data["sync_back"] = sync_back(marks, {t["bare"]: t for t in data["notion"]})
    data["tracked_ids"] = sorted(marks)
    data["pr_correlation"] = correlate(data["prs"], data["notion"],
                                       data.get("note", {}).get("open_tasks", []))
    return data


def render_text(data: dict, week: bool = False) -> str:
    today = datetime.now(TZ).date()
    out = [f"# day-sync brief — {data['date']}", ""]
    for w in data["warnings"]:
        out.append(f"⚠️  {w}")
    if data["events"]:
        out.append("## Schedule")
        last_day = None
        for e in data["events"]:
            day = e["start"].strftime("%a %m-%d") if week else None
            if week and day != last_day:
                out.append(f"### {day}")
                last_day = day
            when = "all day" if e["all_day"] else f"{fmt_time(e['start'])}–{fmt_time(e['end'])}"
            out.append(f"- {when}  {e['title']}")
        conflicts, gaps = conflicts_and_gaps(
            [e for e in data["events"] if not e["all_day"] and e["start"].date() == today])
        for a, b in conflicts:
            out.append(f"  ⚠️ conflict: {a} ↔ {b}")
        for s, e_, mins in gaps:
            out.append(f"  ◦ gap {s}–{e_} ({mins}m)")
        out.append("")
    if data["notion"]:
        tracked = set(data.get("tracked_ids", []))

        def due_flag(t: dict) -> str:
            if not t["due"]:
                return ""
            return " ‼️ OVERDUE" if t["due"] < data["date"] else (
                " ⏰ due today" if t["due"] == data["date"] else f" (due {t['due']})")

        def tracked_mark(t: dict) -> str:
            return " ✓tracked" if t["bare"] in tracked else ""

        sprint = data.get("sprint")
        in_sprint = [t for t in data["notion"] if t.get("in_sprint")]
        if sprint and in_sprint:
            out.append(f"## Current sprint — {sprint['title']} ({sprint['start']} → {sprint['end']})")
            for t in in_sprint:
                out.append(f"- {t['title']} [{t['status'] or 'No status'}]"
                           f"{due_flag(t)}{tracked_mark(t)}\n  {t['url']}")
            out.append("")
        rest = [t for t in data["notion"] if not t.get("in_sprint")]
        if rest:
            out.append("## Notion plate (assigned, not done)")
            cur = None
            for t in rest:
                if t["status"] != cur:
                    out.append(f"### {t['status'] or 'No status'}")
                    cur = t["status"]
                out.append(f"- {t['title']}{due_flag(t)}{tracked_mark(t)}\n  {t['url']}")
            out.append("")
    if data.get("prs"):
        out.append("## Pull requests")
        corr = data.get("pr_correlation", {})
        by_pr = {(m["repo"], m["number"]): m for m in corr.get("matches", [])}
        for pr in data["prs"]:
            state = pr["kind"] + (" DRAFT" if pr["draft"] else "") + (f" [{pr['decision']}]" if pr["decision"] else "")
            out.append(f"- ({state}) {pr['repo']}#{pr['number']} {pr['title']}\n  {pr['url']}")
            m = by_pr.get((pr["repo"], pr["number"]))
            if m:
                tie = (m.get("notion_bare_id") and f"🅽 {m['notion_bare_id']}") or m.get("todo") or ""
                out.append(f"  ↳ {m['suggestion']}" + (f" ({tie})" if tie else ""))
        for a in corr.get("actionable", []):
            out.append(f"  ⚠️ {a['repo']}#{a['number']}: {a['action']}")
        out.append("")
    if data["note"]:
        out.append(f"## Today's note — {len(data['note']['open_tasks'])} open tasks")
        for t in data["note"]["open_tasks"]:
            out.append(f"- {t}")
        out.append("")
    if data["sync_back"]:
        out.append("## Sync back to Notion")
        for i in data["sync_back"]:
            out.append(f"- {i['title']}: {i['suggestion']}\n  {i['url']}")
    return "\n".join(out)


def event_line(e: dict) -> str:
    if e["all_day"]:
        return f"- [ ] {e['title']} (all day)"
    return f"- [ ] {fmt_time(e['start'])} {e['title']}"


def task_line(t: dict) -> str:
    line = f"- [ ] {t['title']} {WORK_TAG} 🅽 {t['bare']}"
    return f"{line} 📅 {t['due']}" if t["due"] else line


def build_candidates(data: dict, note_text: str) -> list[dict]:
    note_norm = [normalize(l) for l in note_text.splitlines() if TASK_LINE.match(l)]

    def in_note(title: str) -> bool:
        n = normalize(title)
        return any(n and n in l for l in note_norm)

    cands = []
    today = data["date"]
    for e in data["events"]:
        e_day = e["start"].date().isoformat() if hasattr(e["start"], "hour") else e["start"].isoformat()[:10]
        if e_day != today or in_note(e["title"]):
            continue
        cands.append({"kind": "event", "label": event_line(e)[6:], "line": event_line(e),
                      "preselected": True})
    tracked = set(data.get("tracked_ids", []))
    for t in data["notion"]:
        if t["bare"] in tracked:
            continue
        preselected = bool(t.get("in_sprint")) or t["status"].lower() == "in progress"
        cands.append({"kind": "notion", "label": f"{t['title']} ({t['status']})",
                      "line": task_line(t), "preselected": preselected})
    for pr in data.get("prs", []):
        if pr["kind"] != "review" or pr["draft"] or pr_in_note(pr, note_text):
            continue
        line = f"- [ ] Review PR: {pr['title']} ({pr['repo']}#{pr['number']}) {WORK_TAG}"
        cands.append({"kind": "pr", "label": f"Review {pr['repo']}#{pr['number']}: {pr['title']}",
                      "preselected": True, "line": line})
    return cands


def pick(cands: list[dict]) -> list[dict] | None:
    selected = {i for i, c in enumerate(cands) if c["preselected"]}
    while True:
        print("\nCandidates for today's note:")
        for i, c in enumerate(cands):
            mark = "x" if i in selected else " "
            print(f"  [{mark}] {i + 1}. {c['label']}")
        try:
            raw = input("Toggle numbers (space-separated), Enter to accept, q to abort: ").strip()
        except EOFError:
            return [c for i, c in enumerate(cands) if i in selected]
        if raw.lower() == "q":
            return None
        if not raw:
            return [c for i, c in enumerate(cands) if i in selected]
        for tok in raw.split():
            if tok.isdigit() and 1 <= int(tok) <= len(cands):
                selected.symmetric_difference_update({int(tok) - 1})


def run_add(dry_run: bool = False, yes: bool = False) -> int:
    data = gather(week=False)
    note_file = JOURNAL / f"{data['date']}.md"
    if not note_file.exists():
        print(f"no daily note at {note_file}", file=sys.stderr)
        return 1
    text = note_file.read_text()
    cands = build_candidates(data, text)
    if not cands:
        print("nothing to add — note already covers today 🎉")
        return 0
    chosen = ([c for c in cands if c["preselected"]] if yes else pick(cands))
    if chosen is None:
        print("aborted")
        return 1
    if not chosen:
        print("nothing selected")
        return 0
    new = insert_into_note(text,
                           [c["line"] for c in chosen if c["kind"] == "event"],
                           [c["line"] for c in chosen if c["kind"] in ("notion", "pr")])
    if dry_run:
        sys.stdout.writelines(difflib.unified_diff(
            text.splitlines(keepends=True), new.splitlines(keepends=True),
            fromfile="today", tofile="today+adds"))
        return 0
    note_file.write_text(new)
    print(f"added {len(chosen)} item(s) to {note_file.name}")
    return 0


def main() -> int:
    ap = argparse.ArgumentParser(prog="day_sync")
    sub = ap.add_subparsers(dest="cmd", required=True)
    b = sub.add_parser("brief", help="print the day/week brief")
    b.add_argument("--week", action="store_true")
    b.add_argument("--json", action="store_true")
    a = sub.add_parser("add", help="insert missing items into today's note")
    a.add_argument("--dry-run", action="store_true")
    a.add_argument("--yes", action="store_true", help="accept defaults, no prompt")
    args = ap.parse_args()
    if args.cmd == "brief":
        data = gather(week=args.week)
        if args.json:
            print(json.dumps(data, default=str, indent=2))
        else:
            print(render_text(data, week=args.week))
        return 0
    if args.cmd == "add":
        return run_add(dry_run=args.dry_run, yes=args.yes)
    return 1


if __name__ == "__main__":
    sys.exit(main())
