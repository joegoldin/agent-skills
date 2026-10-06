---
name: agent-skills-nix-config
description: Build contract and release flow for the agent-skills Nix repository, plus each runtime's Home Manager settings (Claude Code, Codex, Antigravity, Pi). Use when changing skill packaging, sidecars, subagents, or how a runtime is configured through Nix.
---

# Agent Skills Nix Configuration

This repository is the source of truth for skills shared by Claude Code,
Codex, Antigravity CLI, and Pi. Use `writing-skills` for authoring method and
this skill for the repository's build contract.

For one runtime's settings, permissions, hooks and Home Manager options, read
its reference:

- [references/claude.md](references/claude.md): Claude Code through `claude-nix`
- [references/codex.md](references/codex.md): Codex through `codex-nix`
- [references/antigravity.md](references/antigravity.md): Antigravity CLI
  through `antigravity-cli-nix`
- Pi: `modules/pi-profile.nix` here holds the profile (extensions, auto-mode
  denied paths, prompt); `modules/ai/pi.nix` in the dotfiles enables it

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
- A single-line `description`, maximum 1024 characters for the build and 300
  for the `skill-style` check, with no unquoted `: ` or ` #` (runtimes parse
  it as YAML and drop a skill whose value breaks)
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

To try a change on this machine before releasing it, build the dotfiles
against the working copy:

```sh
cd ~/Development/dotfiles
nix build --no-link --override-input agent-skills path:$HOME/Development/agent-skills \
  .#darwinConfigurations.torrent.config.home-manager.users.joe.home.path
```

## Release and Apply

This repository and the dotfiles are colocated jj repositories; make VCS
writes with jj. After verification, commit, move the bookmark and push:

```sh
jj commit -m "feat(skills): ..." <paths>
jj bookmark set main -r @-
jj git push -b main
```

Then update the input in the dotfiles, commit the lock, and apply:

```sh
cd ~/Development/dotfiles
nix flake update agent-skills
jj commit -m "chore(flake): bump agent-skills" flake.lock
jj bookmark set main -r @-
just switch
```

`just switch` picks nix-darwin or NixOS for the current host.
