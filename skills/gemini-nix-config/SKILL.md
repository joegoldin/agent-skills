
# Gemini Nix Configuration

This dotfiles repo manages Gemini CLI declaratively via Nix using the `gemini-nix` library and home-manager module.

## Config File

Gemini CLI reads its configuration from `~/.gemini/settings.json` (JSON format). The home-manager module writes this file via an activation script that performs a jq deep-merge (`jq -s '.[0] * .[1]'`): Nix-generated keys are applied on top of any existing file, so user-written keys (like OAuth tokens) are preserved.

## gemini-nix Library

The `gemini-nix` repo provides these builders (available as `geminiLib`):

| Builder | Purpose |
|---------|---------|
| `mkSkill` | Produces `$out/skills/<name>/SKILL.md` with frontmatter |
| `mkCommand` | Produces `$out/commands/<name>.toml` (TOML format) |
| `mkContext` | Produces `$out/context/<name>.md` |
| `mkHook` | Pure attrset describing a hook entry (collected into settings.json) |
| `mkPlugin` | Bundles skills + commands + contexts into a single buildEnv; hooks ride as passthru |
| `mkGemini` | Optional wrapper script with extra args / env vars |

## Home-Manager Module

Module path: `programs.gemini-nix`

| Option | Type | Description |
|--------|------|-------------|
| `enable` | bool | Enable declarative Gemini CLI management |
| `package` | package | The gemini-cli package to install |
| `plugins` | list of packages | Plugin derivations from `mkPlugin` — skills/, commands/, context/ merged via buildEnv |
| `settings` | attrs | Contents of `~/.gemini/settings.json` — hooks from plugins merged on top |
| `extraPackages` | list of packages | Extra packages installed alongside gemini-cli |

## Activation Behavior

The activation script (`copyGeminiNixConfig`):

1. **settings.json** — If the file exists, deep-merges existing JSON with generated config via `jq -s '.[0] * .[1]'`. If no file exists, copies the generated config directly. Permissions set to 600.
2. **Skills** — Symlinked from the combined plugin buildEnv to `~/.gemini/skills` via `home.file`.
3. **Commands** — Symlinked to `~/.gemini/commands/` (TOML files).
4. **Context** — Symlinked to `~/.gemini/context/` (markdown files).

Hooks are collected from each plugin's `_gemini.hooks` passthru, grouped by event and matcher, and merged into settings.json under the `hooks` key.

## Key settings.json Options

```json
{
  "general": {
    "enableNotifications": true
  },
  "skills": {
    "enabled": true
  },
  "hooks": {
    "PreToolCall": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "name": "my-hook",
            "command": "/path/to/hook"
          }
        ]
      }
    ]
  }
}
```

## Commands

Commands are TOML files in `~/.gemini/commands/`. Built via `mkCommand`:

```toml
description = "What this command does"
prompt = "The prompt template for this command"
```

## Context Files

Context files are markdown documents placed in `~/.gemini/context/`. Built via `mkContext` — they provide persistent context that Gemini can reference during conversations.

## Dotfiles Config

The dotfiles Gemini configuration lives at:

```
hosts/common/home/gemini/default.nix
```

This file sets `programs.gemini-nix.enable`, `package`, and `settings` (notifications, skills enablement, etc.). Plugins are wired through the agent-skills flake.

## Build and Apply

```sh
# Build agent-skills standalone (quick check)
cd agent-skills && just build
# or: nix build .#gemini-plugin

# Apply to system (NixOS)
sudo nixos-rebuild switch --flake .

# Apply to system (macOS)
darwin-rebuild switch --flake .
```
