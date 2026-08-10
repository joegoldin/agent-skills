---
name: claude-nix-config
description: Use when creating, editing, or managing agent skills, commands, agents, or plugin configuration in this dotfiles repo
---

# Agent Skills Configuration

This dotfiles repo manages Claude Code, Antigravity CLI, and Codex declaratively via Nix. All skills, commands, agents, and plugin settings are defined in Nix and built into plugins for each tool.

## Repository: agent-skills

agent-skills is a standalone repo (canonical clone: `~/Development/agent-skills`; github:joegoldin/agent-skills), consumed by the dotfiles as a git+ssh flake input. It is the single entry point. It re-exports `homeManagerModules` from three upstream repos:

- **claude-nix** — Claude Code plugin system
- **antigravity-cli-nix** — Antigravity CLI plugin system
- **codex-nix** — Codex plugin system

Plugins are built per-target: `claude-plugin`, `antigravity-plugin`, `codex-plugin`.

## Key Files

| File | Purpose |
|------|---------|
| `agent-skills/flake.nix` | Flake definition — inputs (claude-nix, antigravity-cli-nix, codex-nix), builds plugins, exports homeManagerModules |
| `agent-skills/lib/default.nix` | Build system — `discoverSkills`, `buildPlugin`, `buildAntigravityPlugin`, `buildCodexPlugin` |
| `agent-skills/skills/<name>/SKILL.md` | The skill — YAML frontmatter (name, description, allowed-tools, any Claude Code field) + instructions, shipped verbatim |
| `agent-skills/skills/<name>/skill.nix` | Optional sidecar — ONLY `packages`, `mcpServers`, `lspServers` (things markdown can't express) |
| `agent-skills/skills/<name>/agents/*.md` | Optional subagents — frontmatter (description, tools, model) + prompt body, built per-target |
| `agent-skills/hooks/` | Claude hook scripts (e.g., session-start) |
| `agent-skills/ATTRIBUTION.md` | Attribution file bundled into all plugins |

## How to Add a Skill

1. Create `agent-skills/skills/<skill-name>/SKILL.md`. Frontmatter is the
   source of truth and is shipped verbatim — any Claude Code frontmatter
   field works with zero Nix changes:

```markdown
---
name: my-skill
description: Use when [triggering conditions]
allowed-tools: Bash(sometool:*) Read
---

Skill instructions here.
```

Rules (enforced by `checks.skills-lint` at build time):
- `name` must equal the directory name (lowercase, hyphens, max 64 chars)
- `description` is required, single-line, max 1024 chars
- `allowed-tools` is a space-separated string; use commas when an entry
  contains a space (e.g. `Bash(sem diff:*), Bash(sem impact:*)`)
- An `allowed-tools:` key with no value is rejected — an empty line would
  restrict the skill to no tools; omit the key instead
- Reference tools by plain command name, never by Nix store path — put the
  package in the sidecar instead (next step) so it lands on PATH
- YAML `#` comment lines are fine inside the frontmatter block (see
  `skills/gh-stack/SKILL.md` for an example annotating allowed-tools)

2. Only if the skill needs Nix-level things, add a `skill.nix` sidecar.
   Allowed keys: `packages`, `mcpServers`, `lspServers` — nothing else:

```nix
{ pkgs, lib }:
{
  packages = [ pkgs.sometool ];

  mcpServers = {
    my-server = {
      command = "${pkgs.my-mcp}/bin/my-mcp";
    };
  };

  lspServers = {
    my-lang = {
      command = lib.getExe pkgs.my-lsp;
      extensionToLanguage = { ".ext" = "my-lang"; };
    };
  };
}
```

The sidecar may be a plain attrset or a function of (a subset of)
`{ pkgs, lib }`. For a tool built from this repo's `packages/` directory
(not nixpkgs), call it relative to the skill dir — this is how
avoid-ai-writing, figma-readonly, pixeldrain, and vibe-modeling ship
their CLIs:

```nix
{ pkgs }:
{
  packages = [ (pkgs.callPackage ../../packages/my-tool { }) ];
}
```

3. Only if the skill ships subagents, add `agents/<agent-name>.md`:

```markdown
---
name: my-agent
description: What this agent does
tools: Read, Glob, Grep
---

Agent system prompt.
```

4. That's it — `discoverSkills` auto-discovers any directory under
   `skills/` containing a `SKILL.md`.

**Commands are skills.** For a slash-command-style workflow, create a
normal skill with `disable-model-invocation: true` and an `argument-hint`
in its frontmatter (see `skills/format-nix/` for the pattern).

## Permissions

- A `Skill(agent-skills:<name>)` allow is auto-generated for every discovered skill and merged into `~/.claude/settings.json` via `programs.claude-nix.extraPermissions.allow` (additive — concatenates with claude-nix's defaults).
- Per-skill Bash allows go in `allowed-tools` inside that skill's SKILL.md frontmatter.
- Repo-wide additive perms (e.g. a new Bash variant every skill should have) go in `agent-skills/flake.nix` via `programs.claude-nix.extraPermissions.{allow,ask,deny}`, **not** `programs.claude-nix.settings.permissions.*` — the latter is a full-list replacement (via `lib.recursiveUpdate`) and will silently nuke the defaults shipped by claude-nix.
- Default Bash allows themselves live upstream in `claude-nix/modules/home-manager.nix` (`defaultSettings.permissions.allow`).

## How the Build System Works

1. **`discoverSkills ./skills`** — scans for directories with `SKILL.md`, parses/lints the frontmatter (`lib/frontmatter.nix` + `lib/lint.nix`), evaluates the optional sidecar, parses `agents/*.md`, and builds a verbatim-copy skill derivation
2. **`buildPlugin`** — aggregates all skills' agents, mcpServers, lspServers, and sidecar packages into a single Claude plugin via `claudeLib.mkPlugin`
3. **`buildAntigravityPlugin`** — converts skills using `agyLib.mkSkill` and bundles into an Antigravity plugin
4. **`buildCodexPlugin`** — converts skills using `codexLib.mkSkill` and bundles into a Codex plugin

## Dotfiles Integration

In the main dotfiles `flake.nix`, agent-skills is a remote ssh input:

```nix
agent-skills = {
  url = "git+ssh://git@github.com/joegoldin/agent-skills";
  inputs.nixpkgs.follows = "nixpkgs";
};
```

The home-manager modules are wired inside den aspects in the dotfiles —
`modules/ai/{claude,codex,antigravity}.nix` (each imports its
`agent-skills.homeManagerModules.*` and sets `programs.*-nix`), included on
hosts via the `home-baseline` aspect.

## Build & Apply

```sh
# Build plugins standalone (quick check, from this repo)
nix build .#claude-plugin && nix build .#antigravity-plugin && nix build .#codex-plugin

# Release: push this repo, then bump the dotfiles input and switch
git push
cd ~/dotfiles && nix flake update agent-skills

# Apply to system (NixOS)
just switch   # or: sudo nixos-rebuild switch --flake .

# Apply to system (macOS)
darwin-rebuild switch --flake .
```

Skill content edits hot-reload in modern Claude Code (including command-style skills). Adding or removing a skill, or changing sidecars/agents/plugin structure, requires a rebuild for `discoverSkills` to pick it up.
