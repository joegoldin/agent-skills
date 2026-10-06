---
name: jujutsu
description: Work in jj (Jujutsu) repositories: changes, bookmarks, revsets, the operation log, git interop and stacked PRs. Use when a .jj/ directory is present or the user mentions jj.
allowed-tools: Bash(jj status:*), Bash(jj st:*), Bash(jj log:*), Bash(jj diff:*), Bash(jj show:*), Bash(jj evolog:*), Bash(jj op log:*), Bash(jj op show:*), Bash(jj bookmark list:*), Bash(jj b l:*), Bash(jj file show:*), Bash(jj file list:*), Bash(jj config list:*), Bash(jj config get:*), Bash(jj git remote list:*), Bash(jj resolve --list:*), Bash(stakk graph:*)
---

# Jujutsu (jj)

jj is a git-compatible VCS. Repos are **colocated**: `.jj/` and `.git/` sit side by side, the remote is ordinary git, and teammates never see jj. Installed on workstations by the dotfiles `jujutsu` aspect, together with jjui (TUI), stakk (stacked PRs), and the stack aliases below.

Check which tool owns the repo before acting: if `.jj/` exists, use jj for every write. Otherwise use git, unless the user asks to start using jj there (`jj git init` in an existing clone; `jj git clone <url>` for a new one).

## Mental model (what differs from git)

- **The working copy is a commit (`@`).** Every jj command snapshots the files into `@` first. There is no staging area and no stash. New files are tracked automatically, so check `jj st` before pushing and keep secrets in `.gitignore`.
- **Change IDs are stable** (`kxqpvmto`, letters k–z), while commit IDs (hex) change on every rewrite. Refer to work by change ID.
- **Descendants rebase automatically** when you rewrite a commit. Editing the middle of a stack is normal.
- **Conflicts are committed, not blocking.** A rebase always succeeds; conflicted commits show `(conflict)` and are resolved later.
- **Bookmarks = git branches, but they don't follow you.** A new commit doesn't advance a bookmark; move it explicitly (`jj b a` / `jj b m`).
- **`trunk()` and everything reachable from it or from tags is immutable.** Rewriting an immutable commit fails unless you pass `--ignore-immutable`. Don't pass it without being asked.
- **Everything is undoable.** `jj undo` reverts the last operation; `jj op log` + `jj op restore <id>` go further back.

Revsets used everywhere: `@` (working copy), `@-` (parent), `trunk()`, `x::y` (ancestry range), `trunk()..@` (my unmerged work), `mine()`, `conflicts()`, `description(substring:"foo")`, `bookmarks()`.

## Non-interactive use (agents)

Anything that opens an editor or diff UI hangs or fails without a TTY. Always:

| Do | Never bare |
|---|---|
| `jj describe -m "msg"` / `jj commit -m "msg"` | `jj describe`, `jj commit` (editor) |
| `jj split -m "msg" <paths>` | `jj split`, `jj split -i` (diff editor) |
| `jj squash -u` or `jj squash -m "msg"` | `jj squash` when both commits have descriptions (editor) |
| `jj squash -u --into <rev> <paths>` | `jj squash -i` |
| Edit the conflict markers in the file | `jj resolve` (merge tool), `jj arrange`, `jj diffedit` |
| `jj diff --git`, `jj log --no-pager` | parsing the delta-paged output |

For structured output, use templates: `jj log --no-graph -r 'trunk()..@' -T 'change_id.short() ++ " " ++ description.first_line() ++ "\n"'`.

## Everyday loop

```bash
jj git fetch                       # update remote bookmarks; trunk() moves
jj new 'trunk()' -m "feat: thing"  # start a change on latest trunk (quote revsets with parens)
# ...edit files; they're already in @...
jj st                              # what's in @
jj diff --git                      # review it
jj commit -m "feat: thing"         # finalize @ (sets message) and start a fresh empty @
```

Two equivalent styles. Use whichever the user is in:

- **Describe-first:** `jj new -m "msg"`, edit, then `jj new` when done.
- **Squash:** keep a described commit at `@-` and an unnamed scratch commit at `@`; `jj squash` moves work down into it.

## Shaping history

```bash
jj split -m "refactor: extract" src/a.rs src/b.rs  # selected paths → first commit; rest stays in @
jj commit -m "part one" src/a.rs                   # same idea, from @
jj squash -u --into <rev> path/to/file             # move a file's changes into an earlier commit
jj absorb                                          # auto-distribute @'s hunks into the commits that last touched those lines
jj edit <rev>                                      # make an earlier commit @; descendants follow your edits
jj new <rev>                                       # new change on top of <rev> (sibling of existing children)
jj new -A <rev> -m "msg"                           # insert a new change after <rev> in a stack
jj rebase -r <rev> -o <dest>                       # move one commit (its children stay put)
jj rebase -s <rev> -o <dest>                       # move a commit and its descendants
jj rebase -o 'trunk()'                             # move the whole branch containing @ onto trunk
jj abandon <rev>                                   # drop a commit; children reparent
jj restore --from <rev> <paths>                    # discard/revert file content (git checkout -- equivalent)
```

`-o/--onto` is the destination flag (`-d` is a deprecated alias). Prefer `jj edit` or `jj squash --into` over a `git rebase -i` style flow.

## Conflicts

```bash
jj log -r 'conflicts()'            # which commits are conflicted
jj new <conflicted-rev>            # work on top of it
# edit the files: between <<<<<<< and >>>>>>>, %%%%%%% is a diff to apply and +++++++ a side's content;
# replace the whole block with the merged text
jj squash -u                       # move the resolution into the conflicted commit
```

Descendants of a resolved commit rebase and often resolve too; recheck `conflicts()`.

## Git interop

- **Push a single change as a PR branch:** `jj b c my-feature -r @-` then `jj git push -b my-feature`. New bookmarks are tracked automatically on first push. Then run `gh pr create --head my-feature` as usual.
- **Update after review:** edit the commits (any of the above), `jj b a` or `jj b m my-feature --to @-`, then `jj git push -b my-feature`. The push is a force-with-lease, so it refuses if the remote moved since your last fetch.
- **Colleague's branch:** `jj git fetch`, `jj bookmark track their-branch@origin`, `jj new their-branch`.
- **After a squash-merge upstream:** `jj git fetch && jj rebase -o 'trunk()' --skip-emptied`. Your now-empty local copies are abandoned.
- **Refused pushes:** jj rejects commits without descriptions, with conflicts, or matching `git.private-commits`. Fix the commit rather than passing `--allow-*`.
- **git in a colocated repo:** read-only git (`git log`, `git blame`, `gh pr view`, `gh pr checks`) is fine. Mutating git commands (`commit`, `checkout`, `rebase`, `stash`) get imported but fight jj. Use the jj equivalent. git sees a detached HEAD; that's expected.
- **git-hunk and `git add -p` don't apply.** There's no index; use `jj split <paths>` or `jj commit <paths>`.

## Stacks (stacked PRs)

A stack is the chain of mutable commits containing `@`. Config from the dotfiles (`~/.config/jj/conf.d/stacks.toml`) gives:

| Sugar | Meaning |
|---|---|
| `stack()` / `substack()` | whole stack containing `@` / its bottom through `@` |
| `stack_top()` / `stack_bottom()` / `tree()` | revsets for the ends, and all stacks sharing `@`'s base |
| `jj top` / `jj bottom` | `jj new` on top of that end; `--edit`/`-e` to edit it instead |
| `jj b a` | advance the nearest bookmark to the newest described, non-empty commit (skips the empty `@`) |

Use **stakk** for the GitHub side. It turns bookmarks in a stack into one PR each, chained by base branch, and registers the stack with GitHub's native stacked PRs (`STAKK_NATIVE_STACKS=on`, drafts by default via `STAKK_PR_MODE`):

```bash
stakk graph --format=json                            # offline: stacks, segments, bookmark remote_state
stakk submit --new-auto <rev> --new-auto <rev> --dry-run   # plan: PR boundaries = marked commits
stakk submit --keep a --keep b --new <rev>=c         # push + create/update PRs; rerun after every rewrite
```

Bare `stakk`/`stakk submit` opens a TUI; always pass `--keep`/`--new*` marks. See `references/stacks.md` for the full flow, how marks work, and error codes. Don't use `gh stack` commands in jj repos; `gh stack` tracks git branches in `.git/gh-stack` and fights jj's rewrites. The `gh-stack` skill still covers merging a stack and the stacks API.

## Recovery

```bash
jj undo                            # undo the last operation (repeatable)
jj op log                          # every operation, with ids
jj op restore <op-id>              # whole repo back to that point
jj evolog -r <rev>                 # every past version of one change
```

A bookmark marked `??` (conflicted) or `*` (ahead of remote) needs `jj b m <name> --to <rev>` or a push. A divergent change (same change ID, two commits) happens after concurrent rewrites: `jj abandon` the unwanted commit ID.
