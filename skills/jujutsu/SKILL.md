---
name: jujutsu
description: Work with jj changes, bookmarks, revsets, and stacked PRs. Use when a .jj directory is present, the user mentions jj, or a task needs an isolated Git worktree, jj workspace, or hunk-level commit.
allowed-tools: Bash(jj status:*), Bash(jj st:*), Bash(jj log:*), Bash(jj diff:*), Bash(jj show:*), Bash(jj evolog:*), Bash(jj op log:*), Bash(jj op show:*), Bash(jj bookmark list:*), Bash(jj b l:*), Bash(jj file show:*), Bash(jj file list:*), Bash(jj config list:*), Bash(jj config get:*), Bash(jj git remote list:*), Bash(jj resolve --list:*), Bash(stakk graph:*)
---

# Jujutsu

In a jj checkout, use jj for writes, not git staging or stash. `@` is the working-copy commit and `@-` is its parent. Bookmarks do not automatically advance. Inspect with `jj st`, `jj diff --git`, or `jj log --no-pager`; quote revsets in the shell. Avoid interactive commands in scripts.

- To isolate a change or share a repo with concurrent writers, read `references/workspaces.md`. It covers both jj workspaces and plain Git worktrees.
- To split a mixed change, or for history edits, conflicts, recovery, bookmarks, or Git interop, read `references/operations.md`.
- For stacked PRs with stakk, including which operations read GitHub, read `references/stacks.md`.

A read-only question does not authorize rewriting or publishing.
