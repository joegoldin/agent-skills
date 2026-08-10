---
name: zmx
description: Use when running long-lived or persistent terminal processes — dev servers, builds, remote SSH/container shells that must survive disconnects or outlive the task — or when the user mentions zmx, session persistence, attach/detach, or asks to run or inspect something in a named session.
allowed-tools: Bash(zmx) Bash(zmx:*)
---

# zmx — persistent terminal sessions (attach/detach, no window management)

zmx (https://github.com/neurosnap/zmx) keeps a shell + its processes alive independent of any terminal. A session is one PTY running `$SHELL` (or a given command), reachable by name. Humans `zmx attach` to it; agents drive it non-interactively with `run`/`send`/`history`. Sessions survive SSH drops, closed terminals, and the end of your task.

## When to use

- A process must **outlive your task**: dev server, watcher, training run, download — start it in a session and hand it to the user.
- The user says "in my zmx session `foo`", asks what a session is doing, or wants a server/process left running.
- You need a **persistent environment** (SSH box, container shell) that keeps state across your commands — and gives the user an auditable log of everything you ran (`zmx attach <name>` shows them live).

**Not for** one-shot commands (plain Bash is simpler) and not a tmux replacement for window management — one session = one PTY, no tabs/splits.

## Iron rules for agents

1. **Never `zmx attach` from your shell** — it's interactive and will hang your tool call. Same for bare `zmx tail` (it follows forever; only use with `timeout`).
2. **Do not quote the command**: args are passed as-is. `zmx run dev git -c core.pager=cat diff`, NOT `zmx run dev 'git diff'` (the quotes end up in the session and break the shell).
3. **One command at a time per session.** `run` blocks until the command finishes (it appends `; echo ZMX_TASK_COMPLETED:$?` and waits for the marker). Never fire a second `run` while one is busy — it types into the foreground process's stdin.
4. **Avoid interactive programs** (pagers, editors, prompts): they hang. Use `-c core.pager=cat`, `--no-pager`, `-y` flags.
5. **Always verify the first command in a brand-new session** (see gotchas — shell startup can eat keystrokes).

## Quick reference

| Command | Purpose |
|---|---|
| `zmx run <name> <cmd...>` | Create session if needed, run cmd, block, return cmd's exit code |
| `zmx run <name> -d <cmd...>` | Same but detached (for servers / long tasks) |
| `zmx wait <name>...` | Block until a detached `run` finishes |
| `zmx history <name> \| tail -100` | Read session scrollback (add `--html` for rendered) |
| `zmx list` | Active sessions (`--short` for names only) |
| `zmx send <name> <text...>` | Raw PTY input, fire-and-forget — answer prompts, drive TUIs |
| `zmx print <name> <text...>` | Inject text into the display only (leave a note for the human) |
| `... \| zmx write <name> <path>` | Write stdin to a file *inside* the session env (works over SSH) |
| `zmx kill <name>... [--force]` | Kill session + processes |
| `zmx attach <name>` | Humans only — interactive |

Exit codes propagate through `run`: `zmx run dev false` → 1, mangled/missing command → 127. `zmx help` covers the rest.

## Core workflow: leave a server running

```bash
zmx run dev.web -d python3 -m http.server 8199
sleep 1
zmx history dev.web | tail -20        # verify it actually started (see gotchas)
curl -s http://localhost:8199/        # interact from OUTSIDE the session
```

While a foreground process owns the session, do not `run` anything else there — read `history`, hit its port, or use a second session. Tell the user the session name so they can `zmx attach dev.web` (or pick it with `zmx-select`).

## Recovering a stuck session

`run` hung, or a server needs stopping without killing the session:

```bash
zmx run <name> $(printf '\x03')       # sends Ctrl-C; returns the interrupted
                                      # command's exit status (130, or 0 if it
                                      # catches SIGINT and exits cleanly)
zmx history <name> | tail -20         # confirm the prompt is back
```

Note: `zmx send <name> $(printf '\x03')` does **not** interrupt — the `run` form is the one that works. `zmx kill <name>` is the last resort (kills the whole session).

## Shell syntax inside the session

Pipes/redirects written normally are interpreted by *your* shell, not the session's. Escape them so they survive as args:

```bash
zmx run dev grep -r TODO src          # plain args: just works
zmx run dev du -sh \* \| sort -h      # \| and \* reach the session shell intact
```

## Session naming

Group by project, dot-separated: `myproj.1`, `myproj.2` (auto-increment) or role-based `myproj.server`, `myproj.editor`. Inside a session `$ZMX_SESSION` holds the name (the starship prompt shows it); `ZMX_SESSION_PREFIX` auto-prefixes every name.

## Gotchas

- **Fresh-session race:** the session's login shell may still be initializing when your first command arrives, and startup wizards/slow rc files can eat leading characters (`python3 ...` became `ython3: command not found`). A blocking `run` surfaces this as exit 127; for `-d` check `history`. If mangled: interrupt (Ctrl-C form above) and re-run.
- **`zmx kill` race:** `zmx list` right after a kill may show the session as `unreachable` for ~1s before it disappears.
- **History is raw scrollback** — includes ANSI escapes and the `ZMX_TASK_COMPLETED` markers; `| tail -N` is usually readable enough.
- **Sockets live in** `$ZMX_DIR` → `$XDG_RUNTIME_DIR/zmx` → `$TMPDIR` — sessions are per-user, per-machine.
