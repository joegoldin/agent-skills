# Design: md-first agent-skills

Date: 2026-08-09
Status: Approved pending review

## Problem

Every skill currently requires a `skill.nix` whose contents mostly duplicate
what belongs in `SKILL.md`: ~25 of 28 skill.nix files contain only `name`
(same as the directory name), `description`, and sometimes `allowed-tools`.
SKILL.md files carry no frontmatter of their own — `buildSkillDrv` synthesizes
it from skill.nix at build time, and the same synthesis is repeated in the
using-agent-skills hook content builder and the per-target `mkSkill` path.

Because Nix owns frontmatter generation, only the three plumbed fields work.
None of the current Claude Code skill features — `context: fork`, `agent`,
`model`, `effort`, `disable-model-invocation`, `user-invocable`,
`argument-hint`, `arguments`, `paths`, `hooks`, `disallowed-tools` — can be
used without adding plumbing per field.

## Goals

- A skill is authored as markdown. `SKILL.md` frontmatter is hand-written,
  spec-proper, and shipped **verbatim** — Nix never generates or rewrites it.
- Every current and future frontmatter field works with zero Nix changes.
- `skill.nix` becomes an optional sidecar carrying only what markdown cannot
  express: Nix package dependencies, MCP servers, LSP servers.
- The repo contract (flake outputs, plugin shapes, consumer interface) is
  unchanged: downstream dotfiles only bumps the flake input.

## The two spec tiers

Skills must be valid against the right tier for where they ship:

1. **Portable tier — the [Agent Skills](https://agentskills.io) open
   standard.** Exactly six frontmatter fields: `name`, `description`,
   `license`, `compatibility`, `metadata`, `allowed-tools`. This is what
   claude.ai web uploads and the Skills API validate against; any other key is
   rejected ("Unexpected key(s) in SKILL.md frontmatter").
   - `name` is **required**, must match the parent directory name, 1–64
     chars, lowercase alphanumerics + hyphens, no leading/trailing/double
     hyphen.
   - `description` is **required**, 1–1024 chars.
   - `allowed-tools` is a space-separated string (e.g.
     `Bash(git:*) Bash(jq:*) Read`).
2. **Claude Code tier — extensions on top of the standard.** Plugin skills
   (which is how this repo ships to Claude Code) may additionally use:
   `when_to_use`, `argument-hint`, `arguments`, `disable-model-invocation`,
   `user-invocable`, `disallowed-tools`, `model`, `effort`, `context` (fork),
   `agent`, `background`, `hooks`, `paths`, `shell`.

Authoring rule: use portable fields wherever possible; Claude Code-only
fields are allowed and encouraged where they add value (they are stripped for
the web bundle and ignored by the Codex/Antigravity converters).

## Design

### 1. Skill contract

A skill is a directory under `skills/` whose `SKILL.md` opens with YAML
frontmatter, authored by hand and shipped verbatim.

- `name`: required, equals the directory name (lint-enforced, per the open
  spec).
- `description`: required, single-line, ≤1024 chars (lint-enforced).
- `allowed-tools`: optional, authored as a space-separated string (the
  portable form). The parser also accepts the YAML-list form defensively.
- Any Claude Code-tier field: optional, passes through untouched.

Discovery keys on `SKILL.md` existing (today it keys on `skill.nix`).

### 2. Pure-Nix frontmatter parser

A small parser in `lib/` extracts the `---`-delimited frontmatter block and
reads only the keys Nix itself consumes:

- `name` (flat string) — validated against the directory name.
- `description` (flat single-line string) — required.
- `allowed-tools` (space-separated string, or simple YAML list) — used only
  by the Codex/Antigravity converters.

All other keys are ignored by Nix and travel in the file unchanged.
Constraint: the three parsed fields must be single-line / simple-list values;
the lint check fails the build with a clear message otherwise. Multi-line
YAML (folded/literal scalars) is out of scope for these three fields — no
IFD, no YAML dependency at eval time.

### 3. Optional skill.nix sidecar

`skill.nix` becomes optional. Allowed keys only:

- `packages`: Nix packages the skill needs on PATH at runtime (e.g. graphviz
  for writing-skills, nixfmt/fd for format-nix). Aggregated into the plugin
  buildEnv automatically, replacing hand-listed flake `extraPackages` where
  the dependency is skill-owned.
- `mcpServers`: skill-scoped MCP server definitions (store-path commands).
- `lspServers`: skill-scoped LSP server definitions.

A sidecar may still be a function of `{ pkgs, lib }`. An eval-time assertion
rejects `name`, `description`, `allowed-tools`, `commands`, `agents`, and
`agentSpecs` in a sidecar so duplication cannot creep back.

Expected end state: ~25 skills have no skill.nix at all; nix-helper keeps one
(mcpServers, lspServers, packages) and writing-skills keeps one (packages).

### 4. Store-path allowed-tools → plain names + PATH

The two skills that interpolate store paths into allowed-tools (nix-helper:
`Bash(${pkgs.statix}/bin/statix)` and `Bash(${pkgs.nixfmt}/bin/nixfmt)` on
the skill plus more in its commands; writing-skills:
`Bash(${pkgs.graphviz}/bin/dot)`) switch to plain command names in
frontmatter (`Bash(statix:*) Bash(nixfmt:*)`, `Bash(dot:*)`), with the
binaries supplied via the sidecar `packages` key so they are on PATH.
nix-helper's sidecar therefore carries `packages = [ statix nixfmt ]` in
addition to its mcpServers/lspServers.

### 5. Agents as markdown

A skill may contain an `agents/` subdirectory with one `<name>.md` per
subagent: frontmatter (`name` defaulting to the file stem, `description`,
`tools`, `model`) and the prompt as the body. The build parses these into
the existing target-neutral agentSpec shape and emits per-target agents for
Claude, Codex, and Antigravity exactly as today. `agents/` is excluded from
the skill's copied assets. nix-helper's single agentSpec migrates here.

### 6. Commands become skills

Claude Code merged commands into skills: every skill is invocable as
`/name`, with `argument-hint`/`arguments` for autocomplete and
`disable-model-invocation: true` for command-only workflows.

- `gh-checks`: the mkCommand wrapper is deleted; `/gh-checks` invokes the
  skill directly. The SKILL.md gains `argument-hint: "[pr-number]"` and
  absorbs the command's step list where not already present.
- nix-helper's `/format-nix` and `/nix-dotfiles` become standalone skill
  directories `skills/format-nix/` and `skills/nix-dotfiles/` with
  `disable-model-invocation: true` and `argument-hint`. format-nix declares
  `packages = [ nixfmt fd ]` in a sidecar; nix-dotfiles is pure markdown.
- The `commands` aggregation path is removed from the skills lib. The
  cross-agent plugins under `plugins/` and claudeLib.mkCommand itself are
  untouched.

Codex/Antigravity note: those targets receive these as ordinary skills (as
they do all skills today); nothing target-specific is lost because the
deleted commands were thin wrappers around skill content.

### 7. Build pipeline changes

- `buildSkillDrv`: copy the skill directory verbatim, excluding `skill.nix`
  and `agents/`. No frontmatter synthesis. Assert frontmatter exists.
- `discoverSkills`: key on `SKILL.md`; parse frontmatter for `name` /
  `description` / `allowed-tools`; eval the optional sidecar; parse
  `agents/*.md` into agentSpecs.
- using-agent-skills session-start hook: read the SKILL.md file verbatim
  instead of re-synthesizing frontmatter.
- `buildSkillForTarget` (Codex/Antigravity): parse description and
  allowed-tools from frontmatter, strip the frontmatter block, and pass the
  body to the target's `mkSkill` — same output as today.
- `buildPlugin` / `buildAntigravityPlugin` / `buildCodexPlugin`: aggregate
  sidecar `packages` into the buildEnv paths.
- Flake outputs keep the same names and shapes (`perSkillPackages`, three
  plugins, web bundles, cross-agent plugins).

### 8. Web bundle

`buildWebBundle` gains one step: filter each SKILL.md's frontmatter down to
the six portable fields (`name`, `description`, `license`, `compatibility`,
`metadata`, `allowed-tools`) so uploads pass the claude.ai validator. The
existing steps stay: XML-tag neutralization, claude→cc rename (with the
`name:` field rewrite), avoid-ai-writing vendoring, one-folder-per-skill and
per-skill zips.

### 9. Lint / flake check

A `checks` output validates every skill at build time:

- Frontmatter present; `name` matches the directory and satisfies the open
  spec's naming rules; `description` present, single-line, ≤1024 chars.
- Frontmatter keys ⊆ (portable tier ∪ Claude Code tier) — typo guard.
- The three Nix-parsed fields are single-line / simple values.
- Sidecar keys ⊆ { packages, mcpServers, lspServers }.
- `agents/*.md` files parse (name/description present).

`skills-ref validate` (the reference validator from
agentskills/agentskills) is noted as a possible future addition if it is
packageable; the checks above cover everything it validates that matters to
this repo.

### 10. writing-skills refresh

`skills/writing-skills/SKILL.md` is rewritten against current guidance:

- The two spec tiers and when each applies (plugin skills vs web uploads),
  including the six portable fields and the Claude Code extension fields.
- Naming and description constraints (64/1024 chars, imperative
  "use when..." descriptions, trigger keywords, the 1536-char listing
  truncation).
- Progressive disclosure: SKILL.md under 500 lines / ~5k tokens; move deep
  reference material to `references/` with explicit "read X when Y"
  triggers.
- Best-practice patterns: gotchas sections, output templates, checklists,
  validation loops, plan-validate-execute, bundling reusable scripts,
  defaults-not-menus, specificity matched to fragility.
- Pointers to description-optimization (trigger evals) and output-quality
  eval loops.
- This repo's contract: md-first authoring, optional sidecar for
  packages/mcpServers/lspServers only, `agents/*.md`, commands-as-skills
  via `disable-model-invocation` + `argument-hint`, plain-command
  allowed-tools with sidecar `packages`.

### 11. Migration

One mechanical pass over `skills/`:

1. For each skill: add frontmatter to SKILL.md (`name`, `description`, and
   `allowed-tools` moved from skill.nix, converted to the space-separated
   string form); delete the skill.nix if it is now empty.
2. nix-helper: move the agentSpec to `agents/`, delete the two commands
   (recreated as the format-nix and nix-dotfiles skills), keep a sidecar
   with mcpServers/lspServers/packages.
3. writing-skills: allowed-tools to `Bash(dot:*)` in frontmatter, sidecar
   with `packages = [ graphviz ]`, plus the content refresh (§10).
4. gh-checks: delete the command, add `argument-hint`, merge the command's
   checklist into the skill body.
5. Update `lib/default.nix` per §7, add the parser and lint, update
   `flake.nix` (drop skill-owned extraPackages that moved to sidecars).

## Error handling

All contract violations fail at Nix eval or build time with messages naming
the offending skill and field: missing/invalid frontmatter, name/dir
mismatch, forbidden sidecar keys, unknown frontmatter keys, unparseable
agents/*.md. There are no runtime failure modes introduced — output
artifacts are static files, same as today.

## Testing and verification

- `nix flake check` runs the new lint over every skill.
- Build all outputs: default (Claude plugin), antigravity + codex plugins,
  `web-skills`, `web-skills-zips`, and per-skill packages.
- Diff generated SKILL.md store contents against pre-migration outputs for a
  sample of skills (expected differences: field ordering, `name:` line,
  allowed-tools string form; no content drift).
- Verify the web bundle contains only portable frontmatter keys
  (`grep -L` over the six-field allowlist).
- Smoke-test in Claude Code: plugin loads, `/gh-checks`, `/format-nix`,
  `/nix-dotfiles` appear as commands, a forked-context field on one skill is
  honored.

## Out of scope

- Changes to `plugins/` (cross-agent plugins), `packages/`, hooks beyond the
  using-agent-skills content read, and the claude-nix / codex-nix /
  antigravity-cli-nix libraries themselves.
- Rewriting skill body content (except gh-checks command absorption and the
  writing-skills refresh).
