---
name: jujutsu
description: Work in Jujutsu repositories with jj (changes, bookmarks, revsets, the operation log, git interop and stacked PRs). Use when a .jj/ directory is present or the user mentions jj.
allowed-tools: Bash(jj status:*), Bash(jj st:*), Bash(jj log:*), Bash(jj diff:*), Bash(jj show:*), Bash(jj evolog:*), Bash(jj op log:*), Bash(jj op show:*), Bash(jj bookmark list:*), Bash(jj b l:*), Bash(jj file show:*), Bash(jj file list:*), Bash(jj config list:*), Bash(jj config get:*), Bash(jj git remote list:*), Bash(jj resolve --list:*), Bash(stakk graph:*)
---

# Jujutsu

In a jj checkout, use jj for writes, not git staging or stash. `@` is the working-copy commit and `@-` is its parent. Bookmarks do not automatically advance. Inspect with `jj st`, `jj diff --git`, or `jj log --no-pager`; quote revsets in the shell. Avoid interactive commands in scripts.

For stacked PRs with stakk, including which operations read GitHub, use `references/stacks.md`. For amending history, conflicts, recovery, bookmark changes, or git interop, read `references/operations.md`. A read-only question does not authorize rewriting or publishing.
