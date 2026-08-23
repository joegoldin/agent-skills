---
name: agent-skills-nix-config
description: Use when authoring or changing shared skills, skill frontmatter, sidecars, subagents, or cross-runtime skill packaging in this Nix repository
---

# Agent Skills Nix Configuration

This repository is the source of truth for skills shared by Claude Code,
Codex, Antigravity CLI, and Pi. Use `writing-skills` for authoring method and
this skill for the repository's build contract.

## Source Layout

| Path | Responsibility |
|---|---|
| `skills/<name>/SKILL.md` | Shared instructions and frontmatter |
| `skills/<name>/skill.nix` | Optional packages, MCP servers, and language servers |
| `skills/<name>/agents/*.md` | Optional shared subagent definitions |
| `lib/default.nix` | Discovery and target-specific builders |
| `lib/frontmatter.nix` | Frontmatter parsing |
| `lib/lint.nix` | Skill and agent validation |
| `flake.nix` | Packages, checks, and Home Manager module fanout |

`discoverSkills ./skills` finds every directory containing `SKILL.md`; no
central registry entry is needed.

## Shared Skill Contract

`SKILL.md` frontmatter is the source of truth. The build requires:

- `name` equal to the directory name, using lowercase letters, numbers, and
  single hyphens, with a maximum of 64 characters
- A single-line `description`, maximum 1024 characters
- `allowed-tools` as a space-separated string; use commas when an entry itself
  contains a space
- No empty `allowed-tools` value
- Plain command names rather than Nix store paths

Claude Code and Pi receive the shared skill derivation. Codex and Antigravity
receive the fields their builders model. Put behavior required by every target
in the body rather than a runtime-specific frontmatter field.

Command-style skills use `disable-model-invocation: true` and an
`argument-hint`.

## Nix Sidecars

Add `skill.nix` only when Markdown cannot express a runtime dependency. Its
allowed keys are:

- `packages`
- `mcpServers`
- `lspServers`

The sidecar may be an attribute set or a function accepting a subset of
`{ pkgs, lib }`. Reference nixpkgs packages directly. For a package under this
repository's `packages/`, use:

```nix
{ pkgs }:
{
  packages = [ (pkgs.callPackage ../../packages/my-tool { }) ];
}
```

## Shared Subagents

Subagents live in `agents/<name>.md`. Their frontmatter requires a description;
the name defaults to the filename. The parser accepts the modeled agent fields
and rejects unknown keys. Shared subagents currently fan out to Claude, Codex,
and Antigravity, with only fields supported by each agent format. Pi packages
skills, prompt templates, and extensions, but does not convert shared subagents.

## Permissions

Every discovered skill receives a generated Claude permission entry. Put
skill-specific command allowances in that skill's `allowed-tools`. Put
repository-wide additive Claude permissions in
`programs.claude-nix.extraPermissions`; replacing
`settings.permissions` discards upstream defaults.

## Verification

Run the repository checks after changing shared authoring or packaging:

```sh
nix build .#checks.$(nix eval --impure --raw --expr builtins.currentSystem).skills-lint
nix flake check
```

Build individual target plugins when changing target conversion or layout:

```sh
nix build .#claude-plugin
nix build .#codex-plugin
nix build .#antigravity-plugin
nix build .#pi-plugin
```

## Release and Apply

After verification, push this repository, then update its input in the dotfiles
repository:

```sh
git push
cd ~/dotfiles
nix flake update agent-skills
```

Apply the host configuration with `just switch` or `nixos-rebuild switch` on
NixOS, and `darwin-rebuild switch` on macOS.
