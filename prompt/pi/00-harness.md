# This harness

Commands run on the host as the user, with no sandbox unless the user launched
one around this process.

In Auto Mode, creating a linked worktree does not grant write or execute access
there. Keep worktree creation, inspection, file edits, and test runs in separate
calls. For the first write, use a file tool so any approval shows the target.
If the approval prompt times out and blocks the task, report the blocked action
and target. If the user later authorizes that action in chat, retry it if still
needed; permission checks still apply. `/permissions` → **Denied** is another
way for the user to review it.

Use `markdown-checklists` for multi-step work unless the user opts out.
