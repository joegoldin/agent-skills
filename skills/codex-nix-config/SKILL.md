
# Codex Nix Configuration

This dotfiles repo manages Codex declaratively via Nix using the `codex-nix` library and home-manager module.

## Config File

Codex reads its configuration from `~/.codex/config.toml` (TOML format). The home-manager module writes this file via an activation script that performs a TOML deep-merge: Nix-generated keys are applied on top of any existing file, so user-written keys (like `trust_level`) are preserved.

## codex-nix Library

The `codex-nix` repo provides these builders (available as `codexLib`):

| Builder | Purpose |
|---------|---------|
| `mkSkill` | Produces `$out/skills/<name>/SKILL.md` with frontmatter |
| `mkHook` | Pure attrset describing a hook entry (collected into `hooks.json`) |
| `mkAgent` | Produces `$out/agents/<name>.toml` |
| `mkPlugin` | Bundles skills + agents into a single buildEnv; hooks and mcpServers ride as passthru |
| `mkCodex` | Optional wrapper script with extra args / env vars |

## Home-Manager Module

Module path: `programs.codex-nix`

| Option | Type | Description |
|--------|------|-------------|
| `enable` | bool | Enable declarative Codex management |
| `package` | package | The codex package to install |
| `plugins` | list of packages | Plugin derivations from `mkPlugin` — skills/, agents/ merged via buildEnv |
| `settings` | attrs | Contents of `~/.codex/config.toml` — MCP servers from plugins merged on top |
| `extraPackages` | list of packages | Extra packages installed alongside codex |
| `agentsMd` | string | Contents of `~/.codex/AGENTS.md` (written only if non-empty) |

## Activation Behavior

The activation script (`copyCodexNixConfig`):

1. **config.toml** — If the file exists, converts existing TOML to JSON, deep-merges with generated config via `jq -s '.[0] * .[1]'`, converts back to TOML. If no file exists, copies the generated config directly. Permissions set to 600.
2. **hooks.json** — Same deep-merge strategy: existing hooks are preserved, new hooks merged on top.
3. **Agent TOML files** — Copied from collected plugin agent derivations into `~/.codex/agents/`.
4. **AGENTS.md** — Written from `agentsMd` option if non-empty.

## Key config.toml Options

```toml
model = "o4-mini"
approval_policy = "on-request"   # "suggest", "auto-edit", "full-auto", "on-request"
sandbox_mode = "workspace-write" # "off", "read-only", "workspace-write"
web_search = true
model_reasoning_effort = "medium"

[mcp_servers.my-server]
command = "/path/to/mcp-server"
args = ["--flag"]
```

## Custom Agents

Agents are TOML files in `~/.codex/agents/`. Built via `mkAgent`:

```toml
description = "What this agent does"
developer_instructions = "System prompt for the agent"
model = "o4-mini"             # optional
sandbox_mode = "off"          # optional

[mcp_servers.some-server]     # optional
command = "/path/to/server"
```

## Dotfiles Config

The dotfiles Codex configuration lives at:

```
modules/ai/codex.nix   # den.aspects.codex (imports the codex hm module)
```

This file sets `programs.codex-nix.enable`, `package`, and `settings` (approval_policy, sandbox_mode, etc.). Plugins are wired through the agent-skills flake.

## Build and Apply

```sh
# Build the plugin standalone (quick check, from the agent-skills repo)
nix build .#codex-plugin

# Release: push agent-skills, bump the dotfiles input, switch
git push && cd ~/dotfiles && nix flake update agent-skills

# Apply to system (NixOS)
just switch   # or: sudo nixos-rebuild switch --flake .

# Apply to system (macOS)
darwin-rebuild switch --flake .
```
