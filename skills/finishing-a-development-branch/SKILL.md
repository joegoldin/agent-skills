---
name: finishing-a-development-branch
description: Wrap up a finished branch or jj change stack by merging locally, opening a PR, keeping it, or discarding it, then clean up the workspace. Use when implementation is done and the work needs integrating.
---

# Finishing a Development Branch

Done means the tests pass on what you integrate, the user's chosen outcome is
carried out, and only a workspace this workflow created is removed.

## 1. Check the tests

Run the project's suite. If it fails, show the failures and stop; don't merge
or open a PR on a red build.

## 2. Work out where you are

- **jj repository** (`.jj/` exists): find the change stack (`jj log -r
  'trunk()..@'`) and whether you are in a secondary workspace (`.jj/repo` is a
  file there, a directory in the default one).
- **git**: compare `git rev-parse --git-dir` with `--git-common-dir` (both
  resolved with `pwd -P`). If they differ you are in a linked worktree. Check
  whether HEAD is on a branch or detached; a detached worktree is managed by
  the harness.

Find the base: usually `trunk()` in jj, or `git merge-base HEAD main` (or
`master`) in git. If it is unclear, ask.

## 3. Choose the outcome

The outcomes are merging into the base locally, pushing and opening a pull
request, keeping the work as it is, and discarding it. When the user has
already said which they want, do that. Otherwise ask, briefly. A detached
worktree can't be merged locally; it can be pushed as a new branch, kept or
discarded.

Pushing, opening a PR and deleting a branch reach outside the session or
destroy work, so they need the user's go-ahead.

## 4. Carry it out

**Merge locally.** Merge first and check the result before removing anything.

```bash
# jj: rebase the stack onto the base and move the base bookmark to its tip
# (@- assumes @ is the empty change left by `jj commit`; check with `jj log`)
jj rebase -b @ -d main
jj bookmark set main -r @-

# git: from the main checkout
MAIN_ROOT=$(git -C "$(git rev-parse --git-common-dir)/.." rev-parse --show-toplevel)
cd "$MAIN_ROOT"
git checkout main && git pull && git merge <feature-branch>
```

Run the tests on the merged result, then clean up the workspace (step 5) and,
in git, delete the branch with `git branch -d <feature-branch>`. Delete it
after removing the worktree, because git won't delete a branch a worktree
still has checked out.

**Push and open a PR.**

```bash
jj bookmark create <feature> -r @-  &&  jj git push -b <feature>   # jj
git push -u origin <feature-branch>                                 # git
```

Then open the PR (gh-stack for stacked PRs). Keep the workspace; the user
will need it for review feedback.

**Keep.** Report the branch or bookmark and the workspace path, and leave
both alone.

**Discard.** List what will be lost (the branch or bookmark, its commits, the
workspace path) and wait for the user to confirm. Then abandon the changes
(`jj abandon 'trunk()..<feature>'`) or, in git, clean up the worktree and
force-delete the branch with `git branch -D <feature-branch>`.

## 5. Clean up the workspace

This applies only after a merge or discard. Remove a workspace only if this
workflow made it, meaning it lives under `~/.worktrees/`, a project-local
`.worktrees/` or `worktrees/`, or `~/.config/agent-skills/worktrees/`.
Anything else belongs to the harness: use its exit tool if it has one, or
leave the workspace in place.

Run removal from the main checkout, not from inside the workspace, where it
fails. In git, `MAIN_ROOT` is as in step 4; in jj, it is the default
workspace's directory (`jj workspace list` names the workspaces).

```bash
# jj
cd "$MAIN_ROOT" && jj workspace forget <name> && rm -rf "$WORKSPACE_PATH"

# git
cd "$MAIN_ROOT" && git worktree remove "$WORKTREE_PATH" && git worktree prune
```

Force-push only when the user asks for it.
