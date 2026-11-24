---
name: markdown-checklists
description: Track multi-step work in a local Markdown checklist and optionally preview it live in Rex. Use when work has several independently verifiable milestones, or when asked to create, resume, share, or show a todo checklist.
---

# Markdown checklists

The Markdown file is the tracker. No Pi session state or Rex pane is required to read or edit it.

## Keep one file per work batch

For read-only work, track milestones in the conversation unless the user asks for a file. Otherwise, reuse the task's local checklist or create `.pi/todo/<topic>.<unique-suffix>/checklist.md` under the active checkout or working directory. Use the worktree you're actually working in, not another checkout or your home directory. If there's no suitable writable directory or `.pi` or `.pi/todo` is a symlink, track progress in the conversation instead.

From the active checkout or working directory, in fish:

```fish
set -l root "$PWD/.pi/todo"
test ! -L "$PWD/.pi"; and test ! -L "$root"; and mkdir -p -- "$root"; and mktemp -d "$root/topic.XXXXXXXX"
```

Write `checklist.md` in the printed directory and share its absolute path in the conversation or handoff. Keep scratch checklists out of commits unless the user asks to include one.

## Keep the list scannable

Use the same compact format in chat and in files: a short title and one line per independently verifiable milestone. Use a verb and an outcome; leave routine substeps, commands, logs, and rationale in supporting docs. When a row needs more context, link a short label to existing documentation or a sibling note. In a Markdown file, make local links relative to `checklist.md`; in chat, use a workspace-relative path when the client supports it.

```markdown
# Upgrade staging

- [x] Smoke-test the repair
- [/] Deploy the upgrade ([runbook](../../../docs/staging-upgrade.md))
- [ ] Verify the upgrade
```

Read the current file before updating it. A checklist is task scratch, not a permission record or audit log. Use `[ ]` for pending work, `[/]` for work in progress, and `[x]` only when evidence confirms completion. Keep the `[/]` marker even in renderers that display it as plain text. For a blocked item, give the blocker or next action in a short phrase and link details if needed. On resume, reconcile the same file with current results. A checked box records progress; it does not execute anything or waive a gate.

For shared work, give agents the same absolute path and distinct items. Keep one writer (the coordinator by default); peers send evidence for their items rather than racing to rewrite the file. If agents cannot access the same filesystem, exchange updates and let the coordinator edit. A checklist does not authorize delegation or network sync.

## Show the live checklist in Rex

When the user wants a side pane, use the `rex` skill to verify the target session and block. Reuse a live preview of the same file; otherwise open a non-focused split, substituting the verified IDs and absolute paths:

```fish
rex split -s SESSION -b BLOCK --split=right --ratio 40 --focus=false -c /absolute/worktree --label Checklist --json -- checklist-view /absolute/path/to/checklist.md
```

Save the returned viewer block ID and capture it once to check rendering. The bottom bar shows how to cycle a task with Space, follow a link with Enter, edit with `e`, save with Ctrl+S, or quit with `q`. The pane reloads external saves when there are no unsaved edits. When sharing the file, save pane edits before someone else writes it. Without Rex, share the path or run `checklist-view` in a terminal; if it isn't installed, open the plain Markdown.
