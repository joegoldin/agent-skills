# Claude Code

Claude Code is managed declaratively through `claude-nix`.

## Integration Points

| Location | Responsibility |
|---|---|
| `flake.nix` | Exports `homeManagerModules.claude` and assembles plugins |
| `hooks/` | Repository-owned Claude hooks |
| `claude-nix/modules/home-manager.nix` | Upstream options and default settings |
| `modules/ai/claude.nix` in dotfiles | Host integration |

The Home Manager module imports the upstream module, installs the generated
plugins, adds a permission for every discovered skill, merges plugin hooks, and
enables the status line.

## Permissions

Use `programs.claude-nix.extraPermissions.{allow,ask,deny}` for additive
repository-wide permissions. Setting `programs.claude-nix.settings.permissions.*`
replaces the defaults from `claude-nix` rather than adding to them.

Skill-specific command permissions belong in the skill's `allowed-tools`
frontmatter.

## Hooks

Repository hooks live under `hooks/` and are folded into
`programs.claude-nix.extraHooks`. Cross-runtime plugin hooks are collected from
plugin passthru data in `flake.nix`.

## Target Build

From this repository:

```sh
nix build .#claude-plugin
nix flake check
```
