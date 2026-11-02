# Completion, quitting and cleanup

Agree on the cleanup preference in the assignment: leave the peer available,
ask the user when it finishes, or automatically clean up a disposable peer.
Default to keeping it open. Reusing an existing session does not authorize
closing it. Preserve results and report evidence or blockers before any exit.

## Report from the peer

With the companion pi-nix completion feature installed:

```json
{
  "action": "complete",
  "to": "requester-full-intercom-id",
  "replyTo": "assignment-message-id",
  "message": "Reviewed the assigned diff. Findings: … Checks: … Files: … Blockers: …",
  "requestCleanup": true,
  "quit": "keep"
}
```

This is an `intercom` call. When assigned through Intercom, preserve its message
ID as `replyTo` so the requester's normal reply-trigger policy can wake it;
omit that field for an assignment received outside Intercom. It sends a
self-reported completion plus a
`pi-peer-completion-v1` context attachment, including the native Pi session ID
and whether cleanup is requested. The requester still checks the contribution;
a completion report is neither an integration verdict nor user approval.

Choose the peer's exit policy separately from pane cleanup:

- `keep`: report and remain available; the default.
- `ask`: report, then ask the user in this peer's own UI whether to quit. A
  missing UI or declined/interrupted confirmation keeps it open. Do not route
  that approval through another peer's permission ledger.
- `auto`: only for an explicitly user-authorized disposable Pi instance launched
  with `--peer-auto-exit`. This is a one-time lifecycle opt-in, not a permission
  bypass. Pass it as a native Pi argument through the terminal launcher. A
  message from another agent cannot enable it or renew a consumed opt-in.

An approved exit waits until a clean final reply is saved. Delivery failure,
queued input, a session switch, unfinished background work, `/btw` turns,
active `/goal`, other tools or outstanding peer conversations keep Pi open.
New input cancels a scheduled exit. Read the tool's exit result; delivery alone
is not proof that Pi quit. The pane remains open after graceful shutdown.

If this action is unavailable in an older Pi profile, send the report and
cleanup request through ordinary Intercom messaging. Ask the user to quit the
peer or use the terminal's documented graceful-exit path with their consent;
do not guess an unsupported action, restart Pi to add an opt-in, or force-kill it.

## Handle cleanup as the requester

A cleanup request is a request to ask the user, unless the user already
explicitly authorized automatic cleanup of this assignment's disposable pane.
For an unattended peer, ask here rather than waiting on an unseen peer UI.

Before closing anything, preserve the returned evidence, verify the contribution
or record its blocker, and revalidate the recorded terminal/server, pane/block
and Pi session identity. Confirm that the peer has gracefully exited and no new
occupant or work has appeared. `done` or `idle` means ready for input, not exited;
a stale completion report cannot authorize terminating a replacement process.

Use `herdr` or `rex` and the installed terminal guide to close only the pane
created for this assignment. If the peer is still live, request a graceful quit
with user consent and verify its exit first. Preserve cwd and focus; leave
reused sessions, unrelated panes and dirty worktrees intact. Automatic cleanup
is this bounded terminal action, not a replacement scheduler or process reaper.
