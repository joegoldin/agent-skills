# gh-stack

Stacked pull requests: an ordered chain of branches rooted on a trunk, where each branch has one PR based on the branch below it. A reviewer of any PR sees only that layer's diff.

Two surfaces, both covered here:

- **`gh stack`** — the GitHub CLI extension that manages the chain locally and on GitHub.
- **The stacks API** — REST endpoints, the async merge API, read-only GraphQL fields, and webhook payloads.

## Orientation

`gh stack` prints a stack trunk-first, left to right:

```
(main) <- auth <- api <- frontend
```

Left is the **bottom** (closest to trunk, merges first), right is the **top**. `up` moves away from trunk, `down` moves toward it. `position` in the API is 1-based from the bottom.

A PR's own `base.ref` is the branch directly below it in the stack. `stack.base.ref` is the branch the whole stack ultimately targets. These differ for every PR except the bottom one — a distinction that trips up most stack tooling.

## Setup

Installed declaratively in this environment via `programs.gh.extensions` (dotfiles `modules/home/gh.nix`), pinned to 0.1.0. Verify with `gh stack --version`.

Elsewhere: `gh extension install github/gh-stack`.

Per-repo config worth setting:

```bash
git config rerere.enabled true         # replay conflict resolutions across cascading rebases
git config remote.pushDefault origin   # required when the repo has more than one remote
```

Stacked PRs must be enabled on the repository. When they are not, `submit` exits **9** and the REST `/stacks` endpoints return `404`.

## Non-interactive use — read this before running anything

`gh stack` branches on whether **stdout is a TTY**. Piped, most commands error cleanly or print static text; under a PTY the same commands open a prompt or a full-screen TUI and **block forever**. Agent harnesses differ in whether they allocate a PTY, so always pass the explicit flag rather than relying on detection.

| Always run | Never run bare | Why |
|---|---|---|
| `gh stack view --json` | `gh stack view` | opens a TUI under a PTY |
| `gh stack submit --auto` | `gh stack submit` | prompts for a title per new PR |
| `gh stack merge <target> --yes` | `gh stack merge` | prompts for scope, method, confirmation |
| `gh stack init <branch>...` | `gh stack init` | prompts for branch names |
| `gh stack add <branch>` | `gh stack add` | prompts for a name, and fails even when piped |
| `gh stack checkout <target>` | `gh stack checkout` | opens a selection menu |
| `gh stack up` / `down` / `top` / `bottom` | `gh stack switch` | `switch` is menu-only |
| — | `gh stack modify` | TUI-only, no non-interactive path |

- `view --short` is safe in both modes, but it is formatted for humans. Use `--json` to parse.
- **`checkout <target>` when a different local stack already covers those branches** cannot be forced. Run `gh stack unstack --local` first (this keeps the stack on GitHub), then retry.

**Multiple remotes:** never run `push`, `submit`, `sync`, `rebase`, or `link` without `--remote <name>` unless `remote.pushDefault` is configured. `checkout` and `trunk` have no `--remote` flag and require the config.

## Core loop

```bash
gh stack init auth                 # create the stack, check out its first branch
git add ... && git commit -m "Add auth middleware"
gh stack add api                   # next layer, branched from the current one
git add ... && git commit -m "Add API routes"
gh stack submit --auto             # push every branch, open a PR per branch, link them
gh stack view --json               # confirm
```

`submit --auto` creates drafts; add `--open` for ready-for-review. Branch names are taken verbatim. Titles are auto-generated — use `gh pr edit` to change them.

Plan the layers **before** writing code. A stack is a dependency chain: if code in one layer depends on another, the dependency must live in the same branch or a lower one. There is no non-interactive reorder, so fixing the order later means tearing the stack down and rebuilding it.

## Editing a lower layer

Check out the layer that owns the change before editing. Never commit a lower layer's concern onto the top branch.

```bash
gh stack down                      # or: gh stack checkout api
git add ... && git commit -m "Add get-user endpoint"
gh stack rebase --upstack          # replay every branch above onto the change
gh stack top
gh stack push
```

If ownership is unclear, run `gh stack view --json` and inspect `git log --all -- <path>`.

## Staying in sync

```bash
gh stack sync                      # fetch, reconcile with GitHub, rebase, push, refresh PR state
gh stack sync --prune              # also delete local branches for merged PRs
```

Non-interactively, pruning only happens with `--prune`. On divergence between the local and remote stack, `sync` prints both chains, changes nothing, and **exits 0** with `Sync aborted` — a zero exit does not mean the sync happened. Check for that message or re-read `gh stack view --json`.

## Merging

**`gh pr merge` cannot merge a stack.** Stacks merge through the async merge API, which `gh stack merge` drives.

```bash
gh stack merge 42 --yes            # PR #42 plus every unmerged PR below it
gh stack merge 7 --yes             # every unmerged PR in stack #7
gh stack merge 42 --yes --squash   # or --merge, --rebase, --merge-method <method>
```

All-or-nothing: if any PR in the set cannot merge, none do. Without a method flag the last-used method is reused. Merge requirements cannot be bypassed, and auto-merge is unsupported for stacked PRs. If the base branch uses a merge queue, the stack is queued instead and the queue picks the method, ignoring any method flag with a warning; queued PRs may land in separate groups.

## Reading state

`gh stack view --json` writes JSON to **stdout**; status messages go to **stderr**. Never parse stderr — branch on exit codes.

```
trunk           string
currentBranch   string
branches[]      name, head, base, isCurrent, isMerged, isQueued, needsRebase
branches[].pr   number, url, state ("OPEN" | "MERGED" | "QUEUED"); omitted when no PR exists
```

`base` is the saved SHA of the parent branch that this branch was last known to contain; it may lag the parent's current tip. `needsRebase` is true when the parent's tip is no longer an ancestor.

## Constraints

- Stacks are strictly **linear**: one parent, at most one child. Use separate stacks for parallel work.
- There is no non-interactive reorder, rename, or removal. Errors may suggest `gh stack modify`, but it is TUI-only — restructure with `unstack` then `init` instead.
- PR titles and bodies are auto-generated. Use `gh pr edit` afterwards to change them.
- `checkout <branch-name>` resolves against local stacks only. Use a stack or PR number to pull a stack down from GitHub.

## API quick reference

```bash
gh api repos/OWNER/REPO/stacks                      # list stacks
gh api "repos/OWNER/REPO/stacks?pull_request=102"   # the stack containing a PR
gh api repos/OWNER/REPO/stacks/42                   # get stack #42
gh api /repos/OWNER/REPO/pulls/42 --jq '.stack'     # a PR's stack membership (null if none)

echo '{"pull_requests":[101,102,103]}' | gh api --method POST repos/OWNER/REPO/stacks --input -
echo '{"pull_requests":[104]}' | gh api --method POST repos/OWNER/REPO/stacks/42/add --input -
gh api --method POST repos/OWNER/REPO/stacks/42/unstack
```

Merging is a two-step submit-then-poll flow against `pulls/{n}/merge-async`. Full schemas, status semantics, GraphQL fields, and webhook payloads: `references/api.md`.

## Exit codes

| Code | Meaning | Recovery |
|---|---|---|
| 0 | Success | — |
| 1 | Generic error | Read stderr |
| 2 | Branch or stack not found | `gh stack init`, or `gh stack checkout <target>` |
| 3 | Rebase conflict | Resolve, `git add`, `gh stack rebase --continue` |
| 4 | GitHub API failure | Check `gh auth status`, retry |
| 5 | Invalid arguments or flags | See `gh stack <command> --help` |
| 6 | Ambiguous stack or remote | Check out a branch unique to the intended stack |
| 7 | Rebase already in progress | `gh stack rebase --continue` or `--abort` |
| 8 | Stack file locked | Another process holds it; retry after ~5s |
| 9 | Stacked PRs unavailable on the repo | Tell the user; not fixable client-side |
| 10 | Interrupted modify session | `gh stack modify --abort` |

**Exit 3 recovery:**

- After `gh stack rebase`: resolve the files, run `git add`, then `gh stack rebase --continue`; use `gh stack rebase --abort` to restore the stack.
- After `gh stack sync`: the stack has already been restored. Run `gh stack rebase` to recreate the conflict, then resolve and continue as above.

## Common mistakes

| Mistake | Correction |
|---|---|
| `gh pr merge` on a stacked PR | Use `gh stack merge`; the legacy merge endpoints reject stacks |
| Parsing `gh stack view` text output | Use `--json`; bare `view` is a TUI under a PTY |
| Treating `sync` exit 0 as success | Divergence aborts with exit 0 — check for `Sync aborted` |
| Building everything on one branch, splitting later | Create the stack before writing code |
| Reading `base.ref` as the stack's target | That is the PR below it; use `stack.base.ref` |
| `gh stack add` from a middle layer | Must run from the top; `gh stack top` first (else exit 5) |
| Expecting `opened` webhooks to carry a stack | PRs are created before joining a stack; listen for the `stacked` action |
| Running `gh stack modify` from an agent | TUI-only with no non-interactive path; rebuild with `unstack` + `init` |

## References

Open the one whose trigger matches; no need to preload both.

- `references/cli.md` — per-command preconditions, atomicity, side effects, and recovery procedures. Read when a command fails unexpectedly, on a rebase conflict, after a squash merge, on local/remote divergence, when restructuring a stack, or when driving stacks from jj/Sapling/git-town or a worktree.
- `references/api.md` — REST stacks endpoints, the async merge API, GraphQL fields, and webhook payloads with full field tables. Read when calling the API directly, building CI logic on stack metadata, or polling a merge.

`gh stack <command> --help` is authoritative for flags. Note that `gh stack help <command>` does **not** work — it prints the top-level help.
