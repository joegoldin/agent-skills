---
name: rex
description: Operate Rex sessions, tabs, panes, terminals, and connected apps. Use when the user asks to control Rex, to arrange or inspect terminals inside Rex, or when authorized Pi peer collaboration needs a Rex pane.
---

# Rex

Run `rex skill show` for the official guide shipped with the installed version.
Use `rex --help`, command help and `rex api describe` to resolve differences
between the [current docs](https://www.superlogical.com/rex/docs/automate/agent-skill.md)
and the connected server. Use the CLI rather than the server socket or app UI
scripting.

## Choose the target

`REX_BLOCK` identifies the agent's pane, not necessarily the user's focused pane.
Current Rex infers the session from that block and accepts its full ID anywhere
in the CLI a session selector is expected: `-s "$REX_BLOCK"`. Older versions
also set `REX_SESSION`; verify it with `rex whoami --json` if the installed CLI
needs a session ID. Inherited IDs aren't proof a target is still live:

| User's location | Target |
| --- | --- |
| Here, beside you, or no location | The agent's session and block |
| Focused pane or current tab | Inspect the viewed session; match `active_window_id` to a window's `window_id`, then use its `focused_block_id` |
| Named session, tab or pane | The named resource; it takes precedence over agent location and app focus |
| Outside Rex or stale IDs | `rex whoami --json`, then `rex ls --json`; select the matching session, asking only if ambiguous |

Use full IDs. Rex calls a tab a **window** and a pane a **block**. `rex new`
creates a session; it does not switch the app to it.
The presence of Rex context is not a request to alter terminals, rename sessions
or restart a server.

## Run and inspect work

For command recipes, output capture, process checks and remote/client targeting,
read [references/operations.md](references/operations.md).

Put Rex options before `--` and the program's arguments after it. Set an explicit
cwd and use `--focus=false` for background work. Save the new block/window IDs;
a timeout can leave a successful creation behind, so inspect before retrying.
Capture a terminal before sending input: text goes to its current foreground
program, not necessarily a shell. Do not send input to the agent's own pane.

For an app action, discover the client with `rex client ls` and its actions with
`rex -C CLIENT actions`. Remote Control must already be enabled by the user.
For another host, use its full label or `-S ssh://HOST`, not `REX_SERVER`: an
unreachable `REX_SERVER` can silently fall back to the local machine.

## Local integration and Pi peers

Rex's skill and awareness configuration are Nix-managed here. Use
`rex skill status` to inspect installation; do not run `rex skill setup` or
`rex skill remove` over the managed configuration.

For authorized Pi collaboration, follow `pi-peer-sessions`. Split beside the
caller's verified block with explicit cwd and `--focus=false`, running ordinary
`pi` after `--`. Keep the returned block ID. Identify the Pi session through
launch metadata or Intercom rendezvous; a Rex block ID is not its messaging
address. Preserve Pi's normal permissions.

Follow its completion reference for cleanup. `pi --peer-auto-exit` requires
user authorization for a disposable peer. Closing its block is a separate,
consented action after verifying graceful Pi exit and the current occupant;
`idle` or a completion message is not exit.
