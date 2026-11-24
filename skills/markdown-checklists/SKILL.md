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

Write `checklist.md` in the printed directory and share its absolute path in the conversation or handoff. Keep scratch checklists out of commits unless the user asks to include one. Use a heading, a line naming the checkout or worktree, and one checkbox per verifiable outcome:

```markdown
# Upgrade staging

Checkout: /absolute/path/to/worktree

- [x] Verify the repair — staging smoke test passed.
- [ ] Verify the upgrade — blocked on the approved deploy window.
```

Read the current file before updating it. A checklist you created here is task scratch, not a permission record or audit log; leave those records untouched. Check off an item only with evidence; leave blockers and next actions beside unchecked items. On resume, reopen the same file and reconcile it with current results. A checked box records progress; it does not execute anything or waive a gate.

For shared work, give agents the same absolute path and distinct items. Keep one writer (the coordinator by default); peers send evidence for their items rather than racing to rewrite the file. If agents cannot access the same filesystem, exchange updates and let the coordinator edit. A checklist does not authorize delegation or network sync.

## Show the live checklist in Rex

When the user wants a side pane, use the `rex` skill to verify the target session and block. Reuse a live preview of the same file; otherwise open a non-focused split, substituting the verified IDs and absolute paths:

```fish
rex split -s SESSION -b BLOCK --split=right --ratio 40 --focus=false -c /absolute/worktree --label Checklist --json -- watch -t -c -n 2 -x glow -s dark /absolute/path/to/checklist.md
```

Save the returned viewer block ID and capture it once to check rendering. The pane is read-only and refreshes on save; edit the Markdown with any editor and stop the preview with Ctrl+C. For a long checklist, `glow -p /absolute/path/to/checklist.md` gives a scrollable snapshot. Without Rex, share the file path; without Glow, open the plain Markdown.
