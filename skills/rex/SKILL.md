---
name: rex
description: Operate Rex sessions, tabs, panes, terminals, and connected apps. Use when the user asks to control Rex, or to arrange or inspect terminals while running inside Rex.
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
