import os
from datetime import datetime
from pathlib import Path
from zoneinfo import ZoneInfo

os.environ["DAY_SYNC_CONFIG"] = "/nonexistent"  # config-independent tests

import day_sync as ds  # noqa: E402

TZ = ZoneInfo("America/Los_Angeles")


def dt(h, m=0):
    return datetime(2026, 7, 8, h, m, tzinfo=TZ)


def test_fmt_time():
    assert ds.fmt_time(dt(14, 30)) == "2:30p"
    assert ds.fmt_time(dt(9)) == "9a"
    assert ds.fmt_time(dt(0, 5)) == "12:05a"
    assert ds.fmt_time(dt(12)) == "12p"


def test_normalize():
    assert ds.normalize("  Dentist Appt!! ") == "dentist appt"
    assert ds.normalize("Alex / Sam 1:1") == "alex sam 1 1"


def test_bare_id():
    assert ds.bare_id("38b1452d-b6a5-81d1-8a14-cd9a53cdb92e") == "38b1452db6a581d18a14cd9a53cdb92e"


def test_scan_journal(tmp_path):
    (tmp_path / "2026-07-07.md").write_text(
        "- [x] Fix bug 🅽 38b1452db6a581d18a14cd9a53cdb92e ✅ 2026-07-07\n"
        "- [ ] Titled 🅽 [Some Notion Task](aa41452db6a58052afadf943e56f6874)\n"
        "- [ ] no marker\n"
    )
    marks = ds.scan_journal(tmp_path)
    assert sorted(marks) == ["38b1452db6a581d18a14cd9a53cdb92e", "aa41452db6a58052afadf943e56f6874"]
    assert marks["38b1452db6a581d18a14cd9a53cdb92e"][0]["state"] == "x"
    assert marks["aa41452db6a58052afadf943e56f6874"][0]["state"] == " "


NOTE = """---
created: x
---
# Wednesday

---
## Today

- [ ]
- [ ] 5m break #task/routine
- [ ] 7:15p hard stop work #task/routine
- [ ] Dinner at 8:30p #task/routine

## Thoughts

-
"""


def test_insert_into_note():
    out = ds.insert_into_note(NOTE, ["- [ ] 2:30p Appt"], ["- [ ] Fix seats 🅽 abc 📅 2026-07-10"])
    lines = out.splitlines()
    i_blank = next(i for i, l in enumerate(lines) if l.rstrip() == "- [ ]")
    assert lines[i_blank + 1] == "- [ ] Fix seats 🅽 abc 📅 2026-07-10"
    assert lines.index("- [ ] 2:30p Appt") == lines.index("- [ ] 7:15p hard stop work #task/routine") - 1


def test_insert_without_hard_stop_appends_to_section_end():
    note = NOTE.replace("- [ ] 7:15p hard stop work #task/routine\n", "")
    out = ds.insert_into_note(note, ["- [ ] 2:30p Appt"], [])
    lines = out.splitlines()
    assert "- [ ] 2:30p Appt" in lines
    assert lines.index("- [ ] 2:30p Appt") < lines.index("## Thoughts")


def test_open_tasks_in():
    assert ds.open_tasks_in("- [ ] a\n- [x] b\n- [/] c\n- [-] d\n") == ["a", "c"]


def test_sync_back():
    marks = {
        "aa": [{"path": "1.md", "state": "x", "line_no": 0, "text": "t"}],
        "bb": [{"path": "1.md", "state": "/", "line_no": 0, "text": "t"}],
        "cc": [{"path": "1.md", "state": "x", "line_no": 0, "text": "t"}],
        "dd": [{"path": "1.md", "state": " ", "line_no": 0, "text": "t"}],
    }
    notion = {
        "aa": {"title": "A", "url": "u", "status": "In progress"},
        "bb": {"title": "B", "url": "u", "status": "Not started"},
        "cc": {"title": "C", "url": "u", "status": "Released"},
        "dd": {"title": "D", "url": "u", "status": "In progress"},
    }
    items = ds.sync_back(marks, notion)
    assert {i["title"] for i in items} == {"A", "B"}


GCAL_ITEMS = [
    {"summary": "Alex / Sam 1:1", "status": "confirmed",
     "start": {"dateTime": "2026-07-10T09:30:00-07:00"},
     "end": {"dateTime": "2026-07-10T10:00:00-07:00"}},
    {"summary": "Errand day", "status": "confirmed",
     "start": {"date": "2026-07-10"}, "end": {"date": "2026-07-11"}},
    {"summary": "Ghost meeting", "status": "cancelled",
     "start": {"dateTime": "2026-07-10T11:00:00-07:00"},
     "end": {"dateTime": "2026-07-10T12:00:00-07:00"}},
]


def test_parse_gcal_events():
    events = ds.parse_gcal_events(GCAL_ITEMS)
    titles = {e["title"] for e in events}
    assert titles == {"Alex / Sam 1:1", "Errand day"}
    timed = next(e for e in events if not e["all_day"])
    assert ds.fmt_time(timed["start"]) == "9:30a"
    assert next(e for e in events if e["all_day"])["all_day"] is True


def _page(title, status, due=None):
    props = {
        "Task Name": {"type": "title", "title": [{"plain_text": title}]},
        "Status": {"type": "status", "status": {"name": status}},
    }
    if due:
        props["Due date"] = {"type": "date", "date": {"start": due}}
    return {"id": "38b1452d-b6a5-81d1-8a14-cd9a53cdb92e",
            "url": "https://www.notion.so/x", "properties": props}


def test_parse_notion_page():
    t = ds.parse_notion_page(_page("Fix seats", "In progress", "2026-07-10T09:00:00.000-07:00"))
    assert t["title"] == "Fix seats"
    assert t["status"] == "In progress"
    assert t["due"] == "2026-07-10"
    assert t["bare"] == "38b1452db6a581d18a14cd9a53cdb92e"


def test_notion_sort_key():
    tasks = [
        ds.parse_notion_page(_page("z-later", "Not started")),
        ds.parse_notion_page(_page("due-soon", "In progress", "2026-07-09")),
        ds.parse_notion_page(_page("no-due", "In progress")),
    ]
    tasks.sort(key=ds.notion_sort_key)
    assert [t["title"] for t in tasks] == ["due-soon", "no-due", "z-later"]


def test_notion_sort_key_sprint_first():
    blocked_in_sprint = ds.parse_notion_page(_page("sprint-blocked", "Blocked"))
    blocked_in_sprint["in_sprint"] = True
    in_progress_off = ds.parse_notion_page(_page("off-sprint-active", "In progress"))
    tasks = [in_progress_off, blocked_in_sprint]
    tasks.sort(key=ds.notion_sort_key)
    assert [t["title"] for t in tasks] == ["sprint-blocked", "off-sprint-active"]


def test_parse_notion_page_sprint_relation():
    page = _page("Fix seats", "In progress")
    page["properties"]["Sprint"] = {
        "type": "relation",
        "relation": [{"id": "3971452d-b6a5-80b1-8ca6-e1bc7cb30947"}],
    }
    t = ds.parse_notion_page(page)
    assert t["sprints"] == ["3971452db6a580b18ca6e1bc7cb30947"]
    assert t["in_sprint"] is False


def _sprint_page(title, start, end):
    return {"id": "3971452d-b6a5-80b1-8ca6-e1bc7cb30947", "url": "x",
            "properties": {
                "Name": {"type": "title", "title": [{"plain_text": title}]},
                "Dates": {"type": "date", "date": {"start": start, "end": end}},
                "Status": {"type": "status", "status": {"name": "Not started"}},
            }}


def test_parse_sprint_page():
    s = ds.parse_sprint_page(_sprint_page("H2 Kick Off", "2026-07-09", "2026-07-22"))
    assert s["title"] == "H2 Kick Off"
    assert s["start"] == "2026-07-09"
    assert s["end"] == "2026-07-22"
    assert s["bare"] == "3971452db6a580b18ca6e1bc7cb30947"


def test_parse_sprint_page_single_day():
    # a Dates value with no end falls back to the start date
    s = ds.parse_sprint_page({"id": "abc", "properties": {
        "Dates": {"type": "date", "date": {"start": "2026-07-09"}}}})
    assert s["start"] == "2026-07-09"
    assert s["end"] == "2026-07-09"


def test_pick_current_sprint():
    from datetime import date as _date
    sprints = [
        {"title": "Feature Delivery 2x", "start": "2026-06-24", "end": "2026-07-01", "bare": "c"},
        {"title": "PC Mag Focus", "start": "2026-07-01", "end": "2026-07-08", "bare": "a"},
        {"title": "H2 Kick Off", "start": "2026-07-09", "end": "2026-07-22", "bare": "b"},
    ]
    assert ds.pick_current_sprint(sprints, _date(2026, 7, 9))["title"] == "H2 Kick Off"
    assert ds.pick_current_sprint(sprints, _date(2026, 7, 8))["title"] == "PC Mag Focus"
    # overlapping boundary (7/1 ends Feature Delivery, starts PC Mag) → latest start wins
    assert ds.pick_current_sprint(sprints, _date(2026, 7, 1))["title"] == "PC Mag Focus"
    assert ds.pick_current_sprint(sprints, _date(2026, 8, 1)) is None


def test_build_candidates_sprint_preselected():
    data = {
        "date": "2026-07-08", "events": [], "tracked_ids": [], "prs": [],
        "notion": [
            {"title": "Sprint task", "bare": "s1", "due": None, "status": "Scoping",
             "url": "u", "in_sprint": True},
            {"title": "Off-sprint task", "bare": "o1", "due": None, "status": "Scoping",
             "url": "u", "in_sprint": False},
        ],
    }
    note = "## Today\n\n\n## Thoughts\n"
    cands = ds.build_candidates(data, note)
    by_label = {c["label"]: c for c in cands}
    assert by_label["Sprint task (Scoping)"]["preselected"] is True
    assert by_label["Off-sprint task (Scoping)"]["preselected"] is False


def test_conflicts_and_gaps():
    events = [
        {"title": "one", "start": dt(9), "end": dt(10), "all_day": False},
        {"title": "two", "start": dt(9, 30), "end": dt(10, 30), "all_day": False},
        {"title": "three", "start": dt(13), "end": dt(14), "all_day": False},
    ]
    conflicts, gaps = ds.conflicts_and_gaps(events)
    assert conflicts == [("one", "two")]
    assert gaps == [("10:30a", "1p", 150)]


def test_event_and_task_lines():
    e = {"title": "Dentist Appt", "start": dt(15, 45), "end": dt(16, 50), "all_day": False}
    assert ds.event_line(e) == "- [ ] 3:45p Dentist Appt"
    t = {"title": "Fix seats", "bare": "abc123", "due": "2026-07-10"}
    assert ds.task_line(t) == "- [ ] Fix seats #work 🅽 abc123 📅 2026-07-10"
    t2 = {"title": "Fix seats", "bare": "abc123", "due": None}
    assert ds.task_line(t2) == "- [ ] Fix seats #work 🅽 abc123"


def test_build_candidates_dedup():
    data = {
        "date": "2026-07-08",
        "events": [
            {"title": "Dentist Appt", "start": dt(15, 45), "end": dt(16, 50), "all_day": False},
            {"title": "Standup Meeting", "start": dt(9), "end": dt(9, 30), "all_day": False},
        ],
        "notion": [
            {"title": "Fix seats", "bare": "abc", "due": None, "status": "In progress", "url": "u"},
            {"title": "Old thing", "bare": "ddd", "due": None, "status": "Not started", "url": "u"},
            {"title": "Tracked", "bare": "eee", "due": None, "status": "In progress", "url": "u"},
        ],
        "tracked_ids": ["eee"],
    }
    note = "## Today\n\n- [ ] 9a Standup meeting #task/routine\n\n## Thoughts\n"
    cands = ds.build_candidates(data, note)
    by_label = {c["label"]: c for c in cands}
    assert "3:45p Dentist Appt" in by_label
    assert not any("Standup" in l for l in by_label)
    assert not any("Tracked" in l for l in by_label)
    assert by_label["3:45p Dentist Appt"]["preselected"] is True
    assert by_label["Fix seats (In progress)"]["preselected"] is True
    assert by_label["Old thing (Not started)"]["preselected"] is False


def test_fallback_correlate_and_pr_in_note():
    prs = [
        {"repo": "acme-api", "number": 12, "title": "Fix seats model admin bugs",
         "url": "u", "kind": "merged", "draft": False, "decision": ""},
        {"repo": "tools", "number": 17, "title": "notion assignment watcher",
         "url": "u", "kind": "review", "draft": False, "decision": ""},
    ]
    notion = [{"title": "Seats model admin bugs", "bare": "abc", "status": "In progress", "url": "u", "due": None}]
    todos = ["fix seats admin bugs today"]
    out = ds.fallback_correlate(prs, notion, todos)
    m = out["matches"][0]
    assert (m["repo"], m["number"], m["notion_bare_id"]) == ("acme-api", 12, "abc")
    assert m["todo"] == "fix seats admin bugs today"
    assert any(a["number"] == 17 for a in out["actionable"])
    assert ds.pr_in_note(prs[1], "- [ ] Review PR: notion assignment watcher (tools#17)") is True
    assert ds.pr_in_note(prs[0], "- [ ] unrelated") is False


def test_pr_candidates():
    data = {
        "date": "2026-07-08", "events": [], "tracked_ids": [],
        "notion": [],
        "prs": [
            {"repo": "tools", "number": 17, "title": "notion watcher", "url": "u",
             "kind": "review", "draft": False, "decision": ""},
            {"repo": "tools", "number": 18, "title": "already there", "url": "u",
             "kind": "review", "draft": False, "decision": ""},
        ],
    }
    note = "## Today\n\n- [ ] Review PR: already there (tools#18)\n\n## Thoughts\n"
    cands = ds.build_candidates(data, note)
    labels = [c["label"] for c in cands]
    assert any("tools#17" in l for l in labels)
    assert not any("tools#18" in l for l in labels)
    c17 = next(c for c in cands if "tools#17" in c["label"])
    assert c17["preselected"] is True
    assert c17["line"] == "- [ ] Review PR: notion watcher (tools#17) #work"
