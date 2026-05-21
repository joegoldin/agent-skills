
# Antigravity CLI Nix Configuration

This dotfiles repo manages Google Antigravity CLI declaratively via Nix using
the `antigravity-cli-nix` library and home-manager module.

## Config Paths

Antigravity reads its config from `~/.gemini/antigravity-cli/`:

| Path | Purpose |
|---|---|
| `~/.gemini/antigravity-cli/settings.json` | Global settings (permissions, sandbox, statusline, env) |
| `~/.gemini/antigravity-cli/mcp_config.json` | Global MCP servers (not managed by us; per-plugin scoping only) |
| `~/.gemini/antigravity-cli/plugins/<name>/plugin.json` | Per-plugin marker — required for discovery |
| `~/.gemini/antigravity-cli/plugins/<name>/skills/` | Per-plugin skills |
| `~/.gemini/antigravity-cli/plugins/<name>/agents/` | Per-plugin subagents |
| `~/.gemini/antigravity-cli/plugins/<name>/rules/` | Per-plugin rules (context files) |
| `~/.gemini/antigravity-cli/plugins/<name>/hooks.json` | Per-plugin hooks |
| `~/.gemini/antigravity-cli/plugins/<name>/mcp_config.json` | Per-plugin MCP servers |

The home-manager module writes `settings.json` via an activation script
that performs a jq deep-merge (`jq -s '.[0] * .[1]'`): Nix-generated keys
are applied on top of any existing file, so user-managed keys are
preserved.

## agyLib Builders

The `antigravity-cli-nix` repo provides these builders (available as
`agyLib`):

| Builder | Purpose |
|---|---|
| `mkSkill` | Produces `$out/skills/<name>/SKILL.md` with YAML frontmatter |
| `mkAgent` | Produces `$out/agents/<name>.md` |
| `mkRule` | Produces `$out/rules/<name>.md` |
| `mkHook` | Pure attrset; collected into per-plugin `hooks.json` |
| `mkMcpServer` | Pure attrset; collected into per-plugin `mcp_config.json` |
| `mkPlugin` | Bundles skills/agents/rules/hooks/mcpServers; writes `plugin.json` |
| `mkAgy` | Optional wrapper script with extra args / env vars |

## Home-Manager Module

Module path: `programs.antigravity-cli-nix`

| Option | Type | Description |
|---|---|---|
| `enable` | bool | Enable declarative Antigravity CLI management |
| `package` | package | The antigravity package (default `pkgs.llm-agents.antigravity`) |
| `plugins` | list of packages | Plugin derivations from `mkPlugin` — symlinked into `~/.gemini/antigravity-cli/plugins/<name>/` |
| `settings` | attrs | Contents of `~/.gemini/antigravity-cli/settings.json` |
| `extraPackages` | list of packages | Extra packages installed alongside antigravity |

Each plugin's `passthru.meta.name` determines its install directory.

## Plugin Structure

A plugin derivation produces this on-disk layout:

```
agy-plugin-<name>/
├── plugin.json         # required marker: { name, description }
├── skills/<name>/SKILL.md
├── agents/<name>.md
├── rules/<name>.md
├── hooks.json          # only when hooks list is non-empty
└── mcp_config.json     # only when mcpServers list is non-empty
```

## Dotfiles Config

Antigravity-specific dotfiles config lives at:

```
hosts/common/home/antigravity/default.nix
```

Plugins are wired through the agent-skills flake.

## Build and Apply

```sh
# Build agent-skills antigravity plugin standalone
cd agent-skills && nix build .#antigravity-plugin

# Inspect the result tree
find result/ -maxdepth 3

# Apply to system (NixOS)
sudo nixos-rebuild switch --flake .

# Apply to system (macOS)
darwin-rebuild switch --flake .
```
