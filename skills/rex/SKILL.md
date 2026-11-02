---
name: rex
description: Operate Rex sessions, tabs, panes, terminals, and connected apps. Use when the user asks to control Rex, to arrange or inspect terminals inside Rex, or when authorized Pi peer collaboration needs a Rex pane.
---

# Rex

Run `rex skill show` for the official guide from the installed Rex version.
Use `rex --help` and `rex <command> --help` if that version has no guide.

`REX_SESSION` and `REX_BLOCK` identify this agent's session and pane, not
necessarily the user's focused pane. An explicit target in the request wins.
Confirm stale or ambiguous targets with `rex whoami --json` and the CLI's
resource listings before acting.

The presence of Rex context does not request terminal changes. Keep existing
sessions running; restart a server or rename a session only when asked.

Rex's skill and awareness hooks are managed by Nix here. Do not run
`rex skill setup` to overwrite the managed agent configuration.

For authorized Pi peer collaboration, follow `pi-peer-sessions`. Use the installed
guide's `split` command with the caller's session/block, explicit cwd and
`--focus=false`, running ordinary `pi` after `--`. Keep the returned block ID.
Use launch metadata or Intercom rendezvous to identify the Pi session; a block
ID alone is not its messaging address. Preserve the normal Pi permission setup.
For completion and cleanup, read `pi-peer-sessions`' completion reference.
`pi --peer-auto-exit` is only for a user-authorized disposable peer. Closing its
block is a separate, consented terminal action after verifying graceful Pi exit
and the block's current occupant; `idle` or a completion message is not exit.
