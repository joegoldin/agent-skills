# `gh stack` command behavior and recovery

`gh stack <command> --help` is authoritative for flags and arguments. (`gh stack help <command>` only prints the top-level help.) This file covers what `--help` does not: preconditions, side effects, atomicity, failure modes, and recovery.

## Contents

- [Command behavior](#command-behavior)
  - [init](#init) · [add](#add) · [push](#push) · [submit](#submit) · [link](#link) · [sync](#sync) · [rebase](#rebase) · [view](#view) · [checkout](#checkout) · [unstack](#unstack) · [merge](#merge) · [Navigation](#navigation) · [modify](#modify)
- [Designing a stack](#designing-a-stack)
  - [Plan the layers before writing code](#plan-the-layers-before-writing-code) · [Branch naming](#branch-naming) · [Staging changes deliberately](#staging-changes-deliberately) · [When to add a layer](#when-to-add-a-layer) · [One stack, one story](#one-stack-one-story)
- [Troubleshooting and recovery](#troubleshooting-and-recovery)

## Command behavior

### init

Creates the stack and checks out the **last** branch listed, so one `init` can lay down the whole chain: `gh stack init auth api frontend`.

Arguments are processed bottom to top. Existing branches are adopted; there is no separate adopt mode, existence decides. If the first branch does not exist it is created from the trunk, and each later new branch is created from the one before it. `--base` selects a non-default trunk.

`init` also enables `git rerere`. Under a TTY the first run in a repo asks for confirmation — set `git config rerere.enabled true` beforehand to skip the prompt.

### add

- **Must run from the top branch** of the stack (or the trunk when the stack is still empty). Anywhere else it exits **5** with `can only add branches on top of the stack`. Run `gh stack top` first.
- **Uncommitted changes carry over.** Without `-Am`, `add` does not touch the working tree, so staged and unstaged changes follow onto the new branch. Commit or stash first for a clean layer.
- **`add -Am` commits in place when the current branch has no commits yet** — for example right after `init` — instead of creating a branch. This is deliberate: the first layer needs content before a second exists.
- `-A` (all, including untracked) and `-u` (tracked only) are mutually exclusive, and both require `-m`.
- With `-m` and no branch name, the name is auto-generated in date+slug format (e.g. `03-24-add_login`).

### push

Pushes every active (non-merged, non-queued) branch in one multi-ref push with per-branch `--force-with-lease`.

**Not atomic.** Some branches may update while another is rejected. A rejection means that branch moved on the remote; fix it and rerun — rerunning is safe and skips what already landed.

`push` never creates or updates pull requests. That is `submit`.

### submit

Pushes each active branch, creates a PR for every branch lacking one (based on the first non-merged ancestor), then links them into a Stack on GitHub.

- **Not atomic.** Branches are pushed sequentially with per-branch `--force-with-lease`. If a later push is rejected, earlier pushes and PR updates stand. Fix and rerun the same command.
- **A fully merged stack cannot be extended.** When every PR is already merged, `submit` forks the remaining unmerged branches into a **new** stack rooted at the trunk, leaving the merged stack untouched.
- **Title generation with `--auto`:** a single-commit branch uses that commit's subject as the title and its body as the PR body. A multi-commit branch humanizes the branch name (hyphens and underscores become spaces). There is no flag for a custom title or body — use `gh pr edit` afterwards.
- `--open` marks new *and existing* PRs ready for review; without it new PRs are drafts.
- Requires stacked PRs enabled on the repo. If not, `submit` exits **9** when non-interactive (under a TTY it offers to create ordinary unstacked PRs instead).

### link

Creates or updates a stack on GitHub **with no local tracking state**. This is the path for branches managed by another tool or living in another worktree.

- Arguments are bottom to top; each is a branch name or PR number. A numeric argument is tried as a PR number first, then as a branch name.
- **A numeric first argument is treated as a stack number only when a stack with that number exists.** Then the remaining arguments are appended to that stack and you do not re-list its current PRs: `gh stack link 7 feature-c`. Arguments already in the stack are skipped; arguments belonging to a different stack are rejected.
- Branch arguments are pushed automatically (non-force, atomic). Missing PRs are created with auto-generated titles and correctly chained bases; existing PRs with a wrong base are corrected.
- Stack membership is **additive only** — `link` never removes a PR from a stack.
- Because it writes no local state, local navigation (`up`, `down`, `top`, `bottom`) will not work on the result. Use `gh stack checkout <stack-number>` to gain local tracking later.

### sync

The routine command. Steps, in order:

1. **Fetch** from the remote.
2. **Reconcile with the GitHub stack.** PRs added to the stack on github.com are pulled down and appended locally. A clean remote-ahead update needs no prompt, so `sync` is safe in automation. On genuine divergence it aborts when non-interactive.
3. **Fast-forward the trunk.** Skipped when current; warns when diverged.
4. **Cascade rebase when needed** — if the trunk moved, a branch was fast-forwarded from its remote, or a branch no longer contains its expected parent. Merged PRs are handled automatically. On conflict **all branches are restored** and it exits **3**.
5. **Push** all active branches, atomically.
6. **Refresh PR state** from GitHub.
7. **Sync the stack object** — link open PRs into a stack, additively, only when two or more PRs exist. `sync` never opens PRs; that is `submit`.
8. **Prune** local branches for merged PRs, only with `--prune` when non-interactive.

### rebase

Pulls from the remote and cascade-rebases. Use it when `sync` reported a conflict or to rebase part of the stack.

- `--upstack` rebases from the current branch to the top. This is what you run after editing a lower layer.
- `--downstack` rebases from the trunk to the current branch.
- `--no-trunk` skips fetching and the trunk rebase, aligning stack branches with each other only.
- `--continue` after staging resolutions; `--abort` restores **every** branch in the stack, not just the current one.
- A merged PR is detected automatically and replayed with `--onto` against the correct target, so a squash-merged parent does not produce spurious conflicts.
- `--committer-date-is-author-date` (alias `--preserve-dates`) keeps dates stable.
- Starting a rebase while one is in progress exits **7**.

### view

- `--json` writes the machine-readable payload to stdout. Schema is in `SKILL.md`.
- Bare `view` opens a full-screen TUI when stdout is a TTY, and prints static text when piped.
- `--short` never opens the TUI but is formatted for humans — parse `--json` instead.
- `view` refreshes PR state from GitHub as a side effect, best-effort; it does not fail when the API is unreachable.
- Output is piped through a pager (`GIT_PAGER`, `PAGER`, else `less -R`).

### checkout

Accepts a stack number, PR number, PR URL, or branch name.

- A bare number resolves as a **stack number first**, then a PR number, then a branch name.
- Stack numbers, PR numbers, and PR URLs fetch from GitHub, pull the branches down, and set up local tracking.
- A **branch name resolves against locally tracked stacks only** and never contacts GitHub. Use a stack or PR number to pull down a stack that is not tracked locally.
- If a local stack already covers those branches with a different composition, `checkout` **cannot be forced past it**. Run `gh stack unstack --local` first (this keeps the stack on GitHub), then retry.
- `checkout` has no flags. It relies on `remote.pushDefault` when several remotes exist.

### unstack

Removes the stack **grouping** only. It never deletes pull requests or branches. Also available as `gh stack delete`.

- With no argument it targets the active stack — the one containing the current branch — removing it on GitHub and locally.
- With a stack number it works from anywhere in the repo, tracked locally or not, via the API. Local tracking is also removed when present.
- `--local` removes local tracking only and never contacts GitHub. Combining `--local` with a stack number that is not tracked locally is an error.
- GitHub decides what can be unstacked: PRs queued for merge or with auto-merge enabled are left stacked, and the stack is kept.
- An unknown stack number exits **2**.

### merge

- Scope with an argument: a **PR number** merges that PR and every unmerged PR below it; a **stack number** merges every unmerged PR in that stack. No argument uses the current active local stack.
- **All-or-nothing.** If any PR in the merge set cannot be merged, none are, and the reason is reported.
- Method comes from `--squash`, `--rebase`, `--merge`, or `--merge-method <method>`. Without one, the last-used method is reused.
- Only basic PR state is checked before merging (open, not a draft). Branch protection and rules are evaluated when the merge runs. **Bypassing merge requirements is not supported for stacks.**
- **A merge queue on the base branch overrides everything.** The stack is queued rather than merged, the queue chooses the method, and any method flag is ignored with a warning. Queued PRs are submitted together but land as the queue processes them, so they may merge in separate groups.
- `gh pr merge` cannot merge a stack. Always use `gh stack merge`.

### Navigation

`up`, `down`, `top`, `bottom`, and `trunk` are always non-interactive. `up` and `down` accept a count (`gh stack up 3`). Movement clamps at the stack bounds, and merged branches are skipped when navigating from an active branch, so `bottom` lands on the lowest *unmerged* branch. From the trunk, `up` moves to the first stack branch.

`gh stack switch` is a selection menu with no non-interactive path. Use the commands above instead.

### modify

TUI-only, with no non-interactive path — **an agent should never invoke it**. It stages drops, folds, inserts, renames, and reorders in a preview and applies them at once. Preconditions: an active stack checked out, a clean working tree, no rebase in progress, no PR queued for merge, and linear history. Errors from other commands sometimes suggest `modify`; restructure with `unstack` + `init` instead (see below).

## Designing a stack

### Plan the layers before writing code

A stack is a dependency chain. If code in one layer depends on code in another, the dependency must live in the same branch or a lower one. That is far cheaper to satisfy by planning than by restructuring, because there is no non-interactive reorder — fixing the order means `unstack` and `init` again.

Stacks are strictly linear: one parent, at most one child. Parallel work needs separate stacks.

Decide the layers first, then write code into them:

```
(main) <- todo-app/models <- todo-app/api <- todo-app/frontend <- todo-app/integration
```

- `todo-app/models` — shared types and schema
- `todo-app/api` — routes that use the models
- `todo-app/frontend` — components that call the routes
- `todo-app/integration` — tests exercising the whole feature

This is illustrative. Infer the stack topic and layer names from the actual task; do not reuse `todo-app` or these layer names literally.

The failure mode to avoid is writing everything on one branch and trying to split it afterwards. If a task is large enough to warrant a stack, create the stack at the start.

### Branch naming

Prefer a shared topic prefix plus the layer's concern — `<topic>/<concern>`, for example `billing/schema`, `billing/api`, `billing/ui`. This keeps related branches recognizable without generic names that could belong to any stack. **User and repository branch naming conventions take precedence; follow them instead.**

Names are used exactly as given — nothing is prepended or transformed, and slashes are kept, so `gh stack add refactor/foo` creates a branch literally named `refactor/foo`. If you pass `-m` without a branch name, the name is generated from the commit message in date-and-slug form (e.g. `03-24-add_api_routes`). Prefer naming the branch yourself.

### Staging changes deliberately

Use `git add` and `git commit` directly rather than the `add -Am` shortcut. The point is control over which changes land in which branch. With several modified files in the working tree, stage the subset that belongs to the current layer, commit it, then create the next branch and stage the rest there:

```bash
git add internal/models/user.go internal/models/session.go
git commit -m "Add user and session models"

gh stack add api-routes
git add internal/api/routes.go internal/api/handlers.go
git commit -m "Add user API routes"
```

Multiple commits per branch are fine. What matters is that every commit in a branch serves the same concern, and that a change belonging to a different concern goes in a different branch.

### When to add a layer

Add a branch when you start a different concern that depends on what you have built so far. Signals: moving backend → frontend, or core logic → tests or docs; the next changes have a different reviewer audience; the current diff is already large enough to review alone. A layer that cannot be described in one sentence is usually two layers.

### One stack, one story

A stack should read as a coherent progression: a reviewer walks the PRs bottom to top and sees the feature being built.

Use a single stack when every branch serves the same feature or project, even across concerns. Start a separate stack for unrelated work — a different feature, an unrelated bug fix, an independent refactor. Do not mix efforts into one stack just because you happened to work on both; use `gh stack init` for the new effort, or `gh stack checkout <target>` to move between existing stacks. A trivial incidental fix can ride along; once it grows into its own project it deserves its own stack.

## Troubleshooting and recovery

### Rebase conflicts (exit 3)

`rebase` and `sync` both exit 3 on conflict. `sync` restores every branch to its pre-rebase state first, so a failed `sync` leaves nothing half-applied; a failed `rebase` stops mid-flight and waits.

```bash
gh stack rebase
# exit 3 — conflicted paths are listed on stderr
git add <resolved paths>
gh stack rebase --continue     # repeat if the next branch also conflicts
```

`gh stack rebase --abort` restores every branch in the stack.

Because `init` enables `git rerere`, a conflict resolved once is replayed automatically the next time it appears — common, since a change low in the stack is rebased through every branch above it. Without `rerere`, repeated conflicts need manual resolution on each affected layer.

### After a squash merge

A squash merge replaces a branch's commits with one new commit, so the originals no longer exist in the trunk's history and an ordinary rebase would replay them again.

`gh stack sync` detects this and rebases with `--onto` against the correct target, skipping the merged branch. No manual action is needed.

```bash
gh stack sync
gh stack view --json    # merged branch reports "isMerged": true, "state": "MERGED"
```

If the replay conflicts, `sync` restores all branches and exits 3. Run `gh stack rebase` to recreate the conflict, then resolve and `--continue`. Use `gh stack sync --prune` to also delete local branches for merged PRs.

### Local and remote stacks have diverged

Divergence means neither stack is a clean prefix of the other — for example a branch was added locally while a different PR was added to the stack on github.com.

Non-interactively, `sync` prints both chains, changes nothing, and **exits 0** with `Sync aborted`. A zero exit here does not mean the sync happened: check for that message, or re-read `gh stack view --json`.

Two resolution paths, neither of which deletes PRs or branches:

```bash
# Keep the remote version — drop local tracking and pull the stack back down
gh stack unstack --local          # keeps the stack on GitHub
gh stack checkout <stack-number>  # or a PR number

# Keep the local version — remove the grouping on GitHub, recreate from local state
gh stack unstack                  # PRs and branches survive
gh stack submit --auto
```

Prefer `submit` over `sync` for the second path: unlike `sync`, it also creates PRs for branches you have not submitted yet. Remote unstacking leaves PRs that are queued or have auto-merge enabled still stacked — clear that state before retrying.

### Restructuring a stack

There is no non-interactive reorder, rename, or removal. Tear the stack down and rebuild:

```bash
gh stack unstack                       # removes local tracking and the GitHub grouping
# rename or drop branches, and rewrite ancestry as needed
gh stack init --base main branch-1 branch-2 branch-3
gh stack submit --auto                 # re-link on GitHub
```

`init` adopts existing branches, so the rebuild reuses them. Existing PRs survive; once Git ancestry is correct, `submit` updates their base branches and re-links the stack.

Changing metadata does **not** change Git ancestry — reorder commits first, then rebuild. To turn `main <- models <- migration <- ui` into `main <- migration <- models <- ui`:

```bash
old_models=$(git rev-parse models)
old_migration=$(git rev-parse migration)
git rebase --onto main "$old_models" migration
git rebase --onto migration main models
git rebase --onto models "$old_migration" ui
gh stack unstack
gh stack init --base main migration models ui
```

Preserve the old boundary SHAs before moving any branch. For a different reorder, identify each layer's range with `git log <old-parent>..<branch>`, then replay bottom to top.

### Branch belongs to several stacks (exit 6)

Exit 6 means the current branch cannot identify a single stack — typically because it is the trunk of more than one. There is no flag to disambiguate.

```bash
gh stack checkout <a-branch-unique-to-the-intended-stack>
```

Commands that take an explicit stack number (`merge 7`, `unstack 7`) sidestep this entirely, since they do not infer the stack from the current branch.

### Driving stacks from another tool or worktree

`gh stack link` creates and updates stacks purely through the API, with no local tracking. Use it when branches are managed by jj, Sapling, git-town, a separate worktree, or any workflow where `.git/gh-stack` would be wrong or absent.

```bash
gh stack link branch-a branch-b branch-c        # bottom to top
gh stack link --base develop --open a b c       # non-default trunk, ready for review
gh stack link 10 20 30                          # by PR number
gh stack link 7 feature-d                       # append to existing stack #7
```

### Stack file is locked (exit 8)

Another `gh stack` process holds the exclusive lock on `.git/gh-stack.lock`. It times out after about five seconds — wait and retry. A persistent exit 8 means another process still holds it; identify and stop that process.

### An interrupted modify session (exit 10)

```bash
gh stack modify --abort
```

`submit` also detects a pending modify state, and under a TTY asks before overwriting the stack on GitHub with local state.

## Local state

Stack metadata lives in `.git/gh-stack` (JSON, not committed). Rebase state during interrupted rebases is stored separately in `.git/gh-stack-rebase-state`, and the lock in `.git/gh-stack.lock`.
