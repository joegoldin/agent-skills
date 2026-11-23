# Rex operations

These recipes follow the [official agent documentation](https://www.superlogical.com/rex/docs/automate/agent-skill.md)
and `rex skill show`. Check the installed guide for version-specific options.
The examples use fish; replace uppercase IDs with full IDs from inspected state.
For your own session, current Rex accepts `-s "$REX_BLOCK"`. Pass `-s` to scope
`rex events` or `rex client ls`, which otherwise cover every session, or to give
`rex api call` a session context.

## Create and verify

Open a background tab, or a pane below a known block:

```fish
rex window new -s SESSION Tests -c /absolute/project --keep-open --focus=false --json -- npm test
rex split -s SESSION -b BLOCK --split=below --ratio 25 --focus=false -c /absolute/project --json -- tail -n 100 -f app.log
```

`run` normally creates a tab; `split` defaults to the right. `--ratio 25` gives
the new pane 25 percent. Placement directions are `right`, `left`, `above`,
`below`; focus directions use `up` and `down` instead of `above` and `below`.

Save `.block_ids[0]` from `run`, `split` or `window new --json`; it is the new
pane. A split also returns the original pane's ID. A new window includes
`.window_id`. `rex new --json` instead returns `.session_id` and
`.initial_windows[0].block_ids`.

Use `--wait` when a finite command's exit status is needed, not for an editor
or server. `--keep-open` keeps output available after exit, but the pane can no longer
accept input. For a dev server someone will restart, open a shell and start the
server at its prompt instead. Verify readiness or completion rather than
inferring it from a pane's existence:

```fish
rex capture -s SESSION -b BLOCK --trim --unwrap
rex block call -s SESSION -b BLOCK process
rex session inspect SESSION --json
```

`process` reports running state and `last_exit`. `capture` reads the screen and
scrollback, fetching long output in parts. `--trim --unwrap` removes trailing
blank lines and joins soft-wrapped lines. For large logs, capture only the tail
or redirect the program's output to a file: scrollback is bounded and drops old
lines. A full-screen app has no alternate-screen scrollback; inspect `modes`
and its `screen` field when a capture does not look like shell output.

After confirming that a different pane is at the intended interactive prompt,
send exact text and then press Return:

```fish
rex send -s SESSION -b BLOCK 'npm test'; and rex send-key -s SESSION -b BLOCK enter
```

Key names are case-insensitive: `send-key G` sends lowercase `g`. Use `shift+g`
or `send` for uppercase text. Capture after an interrupt and check process state;
a pane kept open after exit is not evidence that its program is still running.

## Remote hosts and app clients

A **host** runs programs. A **client** displays sessions. Start discovery with:

```fish
rex hosts check --json
rex -S devbox ls --json
rex -S devbox client ls
rex -S devbox -C CLIENT actions --json
```

`-S` takes a full host label or an endpoint and ignores local caller IDs; select
remote IDs explicitly. Paths, installed programs and `localhost` belong to that
host. A missing or inaccessible `-c` directory can silently fall back to the
home directory, so for remote work check the directory inside the command:

```fish
rex -S devbox run -s REMOTE_SESSION --focus=false --keep-open --json --wait -- sh -c 'cd -- "$HOME/code/app" && exec npm test'
```

A machine that is only a client cannot run the job. Report an unavailable host
rather than running locally instead.

With no saved host, use `rex -S ssh://USER@HOST:PORT ls --json` with the user's
SSH config and credentials. Use brackets for IPv6 and percent-encode spaces in
socket paths. If SSH requires an interactive login or host-key confirmation,
have the user establish it in their own terminal. Read `rex hosts check` or
`rex server status` for the actual connection or startup error before retrying.

For an unmanaged Linux host with no Rex, `rex server install --label LABEL ssh://HOST`
can install Rex for that user, configure the personal server, and save the host.
Run it only when the user asks to install there. On a Nix-managed host, use
its declared service and package instead.

For app-only changes, select the named device's client and inspect its available
actions before calling them:

```fish
rex client ls
rex -C CLIENT actions --json
rex -C CLIENT do session.select session_id=SESSION
```

Global `-C` and `-S` options precede the command. Action arguments are `KEY=VALUE`
or JSON via `--args`; `.args` in the action listing gives the schema. Client
IDs can change on reconnect. For `session.select`, use the actual session ID
from `rex whoami --json` or session inspection, not a block ID: the CLI passes
client action arguments through unchanged. An attachment to a session does not
establish which session the user is viewing. Listing actions does not grant Remote Control;
if the app refuses, report its message rather than changing its settings.

## Discover unsupported or advanced operations

Check `rex block types --json`, `rex api list` and `rex api describe METHOD --json`
for built-in blocks, layouts and resizing. Some versions list CLI commands that
are not implemented; use the documented API, not tmux flags. Inspect a block's
methods with `rex block inspect BLOCK --json` before `rex block call`.

For configuration and protocol questions, fetch Markdown pages by appending
`.md` to the URL. The [documentation index](https://www.superlogical.com/rex/docs.md)
links the pages; `/rex/docs/search.json?q=YOUR+QUERY` returns matching sections.
