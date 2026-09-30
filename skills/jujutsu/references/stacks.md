# Stacked PRs from jj with stakk

stakk turns a jj stack into GitHub PRs. Each PR boundary is a bookmark, and each PR targets the bookmark below it. With `STAKK_NATIVE_STACKS=on` (set on workstations), every submit also registers the chain as a GitHub native stack. GitHub then shows the stack and retargets PRs as the bottom ones merge. stakk pushes through jj and never calls git.

On a repo without native stacks, `on` makes submit **fail after** pushing and opening the PRs. The PRs exist, only the stack registration failed. For such repos (GitHub Enterprise, orgs without the preview), pass `--native-stacks auto` to register where available and fall back to a stack comment elsewhere.

`stakk docs agents` is the authoritative agent guide; `stakk docs <topic>` lists the rest.

## Build the stack in jj

One commit per reviewable layer, bottom first:

```bash
jj new 'trunk()' -m "feat(auth): middleware"   # ...edit...
jj new -m "feat(api): routes"                  # ...edit...
jj new -m "feat(ui): screens"                  # ...edit...
jj new                                         # empty @ on top; not submitted
jj log -r 'stack()'
```

A layer can be several commits. Unmarked commits fold into the PR of the nearest mark above them.

## Read the state (offline)

```bash
stakk graph --format=json        # stacks[].segments[].{bookmarks[], commits[]}
stakk graph --format=json-full   # + descriptions, authors, files
```

`remote_state` per bookmark: `unpushed`, `diverged` (the remote sits elsewhere; submit moves it), `synced`. `stacks[]` has no stable order, so select by bookmark or change ID. Pass full `change_id`s to later commands, since short ones can become ambiguous.

## Submit

Marks decide the PR set. They must lie on one trunk-to-tip path, and the topmost mark is the tip.

| Mark | Effect |
|---|---|
| `--keep <bookmark>` | existing bookmark stays a PR boundary |
| `--new <rev>` / `--new <rev>=<name>` | new bookmark `stakk-<change_id>` or `<name>` |
| `--new-auto <rev>` | new bookmark named from the commit content |

```bash
# first submission: name each layer
stakk submit --new 'description(substring:"middleware")'=auth \
             --new 'description(substring:"routes")'=api \
             --new @-=ui --dry-run
# drop --dry-run to push and open the PRs (drafts, via STAKK_PR_MODE)

# later submissions: keep what exists, mark anything new on top
stakk submit --keep auth --keep api --keep ui
```

Always pass marks. Bare `stakk` or `stakk submit` opens a TUI, which fails with `stakk::not_interactive` without a terminal. `--dry-run` reads GitHub but writes nothing.

Titles and bodies come from commit descriptions at creation only. Add `--sync-pr-content all` to overwrite them from the commits on every submit.

## Change the stack

Rewrite with plain jj, then resubmit. Bookmarks follow rewritten commits automatically.

| Change | jj | Then |
|---|---|---|
| Fix a lower layer | `jj edit <rev>` or `jj squash -u --into <rev> <paths>` / `jj absorb` | `stakk submit --keep …` |
| Add a layer on top | `jj top`, work, `jj commit -m …` | `stakk submit --keep … --new @-=<name>` |
| Add commits to the top layer | work on top, `jj b a` | `stakk submit --keep …` |
| Insert a layer mid-stack | `jj new -A <rev> -m …`, work | `stakk submit` with a `--new` mark at that commit, in order |
| Drop a layer | `jj abandon <rev>`, `jj bookmark delete <bookmark>` | `stakk submit --keep …` for the rest; close the orphaned PR (`gh pr close`) |
| Reorder | `jj rebase -r <rev> -A/-B <rev>` | resubmit; check every PR base on GitHub afterwards |
| Sync with trunk | `jj git fetch && jj rebase -o 'trunk()' --skip-emptied` | `stakk submit --keep …` |

Navigate with the dotfiles sugar: `jj top` / `jj bottom` (`-e` to edit instead of stacking a new change), `jj log -r 'stack()'`, `jj log -r 'substack()'`.

GitHub marks a PR merged when its head becomes reachable from its base. Reordering can trigger that and close PRs irreversibly. Run `--dry-run` first and check the planned base for each PR.

## Merge

Merge bottom-up in the GitHub web UI, or with `gh stack merge <pr> --yes`, which uses GitHub's merge API (see the `gh-stack` skill; untested from a jj repo). `gh pr merge` rejects stacked PRs. After a merge:

```bash
jj git fetch                                   # merged bookmarks drop; trunk() advances
jj rebase -o 'trunk()' --skip-emptied          # remaining layers onto trunk; merged copies vanish
stakk submit --keep <remaining bookmarks…>
```

## Errors

stakk exits 1 with a `stakk::…` code on stderr. Common ones:

| Code | Fix |
|---|---|
| `selection::rev_not_on_stack` | empty `@` or trunk selected; use `@-` |
| `selection::not_colinear` | marks span two stacks; mark one stack per run |
| `selection::rev_immutable` | the commit is already in trunk or pinned by a stale remote bookmark (`jj bookmark forget --include-remotes <name>`) |
| `selection::name_exists` | the bookmark exists; use `--keep` |
| `not_interactive` | no marks were passed (often an empty shell substitution) |
