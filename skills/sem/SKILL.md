---
name: sem
description: Use when reviewing or understanding code changes at the entity level — functions, classes, methods — instead of line-by-line. Covers entity-aware diffs (working tree, staged, commit ranges), impact/blast-radius analysis ('what breaks if I change X', which tests to run), entity blame ('who last touched this function'), tracking how a single entity evolved through history, listing entities in a file/dir, and generating token-budgeted dependency-aware context for an LLM. Trigger when the user mentions `sem`, asks what entities changed, what depends on a symbol, who changed a function, or wants compact context for one symbol before editing it.
allowed-tools: Bash(sem diff:*), Bash(sem impact:*), Bash(sem context:*), Bash(sem blame:*), Bash(sem log:*), Bash(sem entities:*)
---

# sem: Semantic (Entity-Level) Version Control

## Overview

`sem` is a Git-aware tool that diffs and analyzes code at the **entity** level —
functions, methods, and classes — instead of by lines. It parses each file with
tree-sitter, extracts every entity, hashes it structurally, and matches entities
across versions (with rename/move detection). The result: "what *changed*"
expressed as `modified authenticateUser`, not `+12 −7 in auth.ts`.

It supports ~28 languages plus structured formats (JSON/YAML/TOML/CSV/Markdown),
falling back to chunk-based diffing for anything it can't parse.

**Core syntax:** `sem <command> [target] [flags]`. Most commands take `--json`
for machine-readable output — prefer it when you (the agent) are consuming the
result rather than showing it to a human.

## When to use

- **Before editing a symbol** — `sem context <entity>` to pull the entity plus
  its dependencies/dependents, fitted to a token budget, instead of reading
  whole files.
- **Assessing a change** — `sem impact <entity>` to see what depends on it and
  which tests to run before you touch it.
- **Reviewing / summarizing a diff** — `sem diff` for an entity-level changelog
  (great for PR bodies and self-review: "renamed X, modified Y, deleted Z").
- **Attributing a change** — `sem blame <file>` for per-entity authorship, or
  `sem log <entity>` to trace how one function evolved.
- The user says "sem", "what entities changed", "what breaks if I change…",
  "who last touched this function", or asks for compact context for a symbol.

## When NOT to use

- You need exact line-level/whitespace changes → use `git diff`.
- The file type isn't code (plain prose, binaries) → sem falls back to coarse
  chunk diffs; `git diff` is usually clearer.
- You're outside a Git repo and have no two files to compare → most commands
  expect a repo (use `sem diff fileA fileB` or `--stdin` for the repo-less case).

## Commands

### `sem diff` — entity-level diff

```bash
sem diff                          # working-tree changes vs HEAD
sem diff --staged                 # staged changes only
sem diff --commit <hash>          # changes introduced by one commit
sem diff --from <ref> --to <ref>  # changes across a commit range
sem diff fileA.ts fileB.ts        # compare two arbitrary files (no repo needed)
sem diff -v                       # add word-level inline diffs per entity
sem diff --format json            # plain | json | markdown
sem diff --file-exts .py .rs      # restrict to certain extensions
sem diff --stdin                  # read changes from stdin, no Git required
```

Summary counts cover added / modified / deleted / moved / renamed / reordered
entities. Use `--format markdown` to drop straight into a PR description.

### `sem impact` — blast radius

```bash
sem impact authenticateUser            # full analysis: deps, dependents, tests
sem impact authenticateUser --deps     # only what this entity depends on
sem impact authenticateUser --dependents  # only what depends on this entity
sem impact authenticateUser --tests    # only the affected tests
sem impact authenticateUser --file src/auth.ts   # disambiguate same-named entities
sem impact authenticateUser --json
```

Run `--tests` after a change to know exactly which tests to execute.

### `sem context` — token-budgeted LLM context

```bash
sem context authenticateUser              # entity + deps/dependents, default budget
sem context authenticateUser --budget 4000
sem context authenticateUser --json       # for agent/pipeline consumption
```

Purpose-built for agents: returns the target entity plus its dependency
neighborhood trimmed to fit a token budget. In JSON, if the target signature
itself doesn't fit, the output sets `target_omitted: true` — check that flag
before trusting the payload, and raise `--budget` if so.

### `sem blame` — per-entity authorship

```bash
sem blame src/auth.ts          # who/which commit last modified each entity
sem blame src/auth.ts --json
```

### `sem log` — history of one entity

```bash
sem log authenticateUser           # every commit that changed this entity
sem log authenticateUser -v        # with content diffs between versions
sem log authenticateUser --limit 20
sem log authenticateUser --json
```

### `sem entities` — list entities

```bash
sem entities                 # entities in the current directory
sem entities src/auth.ts     # entities in one file
sem entities --json
sem entities --no-default-excludes   # include generated/build dirs
```

## Agent workflows

- **Plan a refactor:** `sem impact <entity> --json` → read `dependents` to know
  call sites to update and `tests` to know what to re-run.
- **Gather context cheaply:** `sem context <entity> --json --budget <N>` instead
  of reading several files; respect `target_omitted`.
- **Summarize your own work:** `sem diff --staged --format markdown` to draft an
  entity-level commit message or PR body.
- **Locate a same-named symbol:** disambiguate with `--file <path>` on `impact`
  / `context` when an entity name is not unique.

## Output formats & config

- Formats: `plain` (git-status-like), `json` (for agents/CI), `markdown` (PRs).
  Pass `--format` on `diff`; other commands expose `--json`.
- `.semrc` in the repo root maps custom file extensions to languages; sem also
  respects `.gitattributes` patterns.
- `SEM_CACHE_DIR` overrides the cache location.
- `--no-default-excludes` (on `entities` / `impact` / `context`) includes
  generated and build directories that are skipped by default.
