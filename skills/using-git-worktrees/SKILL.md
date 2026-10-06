---
name: using-git-worktrees
description: Set up an isolated workspace (git worktree or jj workspace) for feature work, with a clean test baseline. Use when starting work that should not touch the current checkout, or before executing a plan.
---

# Using Git Worktrees

Put the work in its own workspace so the user's checkout, and any uncommitted
changes in it, stay untouched. Done means you are in an isolated workspace,
dependencies are installed, and you have reported the baseline test result.

## 1. Check for existing isolation

Don't nest one workspace inside another. In a jj repository (`.jj/` exists),
a secondary workspace stores `.jj/repo` as a file pointing at the main repo,
where the default workspace has a directory:

```bash
[ -f "$(jj workspace root)/.jj/repo" ] && echo "already in a secondary jj workspace"
```

In plain git, compare the git dir with the common dir:

```bash
GIT_DIR=$(cd "$(git rev-parse --git-dir)" 2>/dev/null && pwd -P)
GIT_COMMON=$(cd "$(git rev-parse --git-common-dir)" 2>/dev/null && pwd -P)
git rev-parse --show-superproject-working-tree 2>/dev/null   # prints a path inside a submodule
```

`GIT_DIR != GIT_COMMON` means a linked worktree, unless the last command
printed a path, in which case it is a submodule and counts as a normal
checkout. If you are already isolated, say where and on which branch (or that
HEAD is detached and the harness manages it), then skip to setup.

In a normal checkout, follow the user's stated preference if there is one;
otherwise offer a workspace before creating it. If they decline, work in place
and go on to setup.

## 2. Create the workspace

Use the harness's own worktree tool if it has one (`EnterWorktree`, a
`/worktree` command, a `--worktree` flag). It handles placement and cleanup,
and a worktree made behind its back is state it cannot see.

Otherwise choose the location in this order:

1. A directory the user's instructions name.
2. An existing worktree for this branch under a project-local `.worktrees/` or
   `worktrees/`: reuse it in place. A bare `.worktrees/` directory with no
   worktree for the branch is not a reason to put new ones there.
3. The legacy global directory, if it exists for this project:
   `~/.config/agent-skills/worktrees/$project/`.
4. The default, `~/.worktrees/$project/$BRANCH_NAME`. It sits outside the
   repo, so editors and fuzzy finders don't index it.

When reusing a project-local directory, confirm it is ignored first, or the
worktree's contents end up tracked:

```bash
git check-ignore -q .worktrees 2>/dev/null || git check-ignore -q worktrees 2>/dev/null
```

If it isn't, add it to `.gitignore` and commit that before going on.

```bash
project=$(basename "$(git rev-parse --show-toplevel 2>/dev/null || jj workspace root)")
path="$HOME/.worktrees/$project/$BRANCH_NAME"
mkdir -p "$(dirname "$path")"

# jj repository: a workspace, with a bookmark created when the work is pushed
jj workspace add --name "$BRANCH_NAME" "$path"

# plain git
git worktree add "$path" -b "$BRANCH_NAME"

cd "$path"
```

In a colocated jj repo, the new workspace has no `.git`, so run jj there
rather than git. The jujutsu skill covers workspaces, bookmarks and pushing.

If creation fails with a permission error, the sandbox blocked it. Say so and
work in the current directory instead.

## 3. Set up and check the baseline

Install dependencies the way the project does (a dev shell or `nix develop`
where there is a flake; otherwise `npm install`, `cargo build`, `uv sync`,
`go mod download`), then run the test suite.

Report the location and the result, for example "Workspace ready at
`<path>`; 214 tests pass." If tests already fail, report which ones and ask
whether to proceed or investigate first; otherwise new failures can't be told
apart from old ones.
