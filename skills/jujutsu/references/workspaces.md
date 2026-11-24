# Isolated checkouts

Use a separate checkout when the user asks for isolation or when concurrent
writers need to change the same repository. Start it from the intended base:
`@` may contain another writer's work, and `trunk()` may be older than the
latest remote commit. Check both before choosing.

1. Check whether you are already isolated. In jj, `.jj/repo` is a file in a
   secondary workspace and a directory in the default workspace. In plain
   Git, a linked worktree has different `git rev-parse --git-dir` and
   `git rev-parse --git-common-dir` paths. Reuse an existing suitable checkout
   rather than nesting another one.
2. Prefer the harness's worktree tool if it owns workspace lifecycle. Otherwise
   use the user's chosen path, an existing ignored project worktree, or
   `~/.worktrees/<project>/<task>`. Reuse the legacy
   `~/.config/agent-skills/worktrees/` location if the project already uses it.
3. Create the workspace from the checked base, substituting the name, path, and
   revision. Use jj when `.jj/` exists; use Git only in a plain Git checkout.

   ```fish
   jj workspace add --name task --revision 'trunk()' ~/.worktrees/project/task
   # Plain Git instead:
   git worktree add -b task ~/.worktrees/project/task origin/main
   ```

4. Report the path and base. Verify the new checkout's status before editing.
   Use its project environment for the needed checks; don't carry failed
   baseline checks over as regressions. For integration and cleanup after the
   work is done, use `finishing-a-development-branch`.

A colocated jj repository's secondary workspace may not expose a `.git`
folder. Run jj there rather than `git checkout` or `git worktree`.
