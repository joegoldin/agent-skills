
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
| `agent-skills/skills/<name>/skill.nix` | Skill metadata (name, description, optional commands/agents/mcpServers/lspServers) |
| `agent-skills/skills/<name>/SKILL.md` | Skill content — the instructions loaded when the skill is invoked |
| `agent-skills/hooks/` | Claude hook scripts (e.g., session-start) |
| `agent-skills/ATTRIBUTION.md` | Attribution file bundled into all plugins |

## How to Add a Skill

1. Create `agent-skills/skills/<skill-name>/skill.nix`:

**Simple skill** (no packages needed):
```nix
{
  name = "my-skill";
  description = "When to use this skill";
}
```

**Skill with packages** (function form — receives `{ pkgs, lib, claudeLib }`):
```nix
{ pkgs, ... }:
{
  name = "my-skill";
  description = "When to use this skill";
  allowed-tools = [
    "Bash(${pkgs.sometool}/bin/sometool)"
  ];
}
```

**Skill with commands, agents, MCP servers, LSP servers:**
```nix
{ pkgs, lib, claudeLib, ... }:
{
  name = "my-skill";
  description = "When to use this skill";

  commands = [
    (claudeLib.mkCommand {
      name = "my-command";
      description = "What this command does";
      allowed-tools = [ "Bash" "Read" ];
    } ''
      Command prompt. Use $ARGUMENTS for user input.
    '')
  ];

  agents = [
    (claudeLib.mkAgent {
      name = "my-agent";
      description = "What this agent does";
      tools = [ "Bash" "Read" "Write" ];
    } ''
      Agent system prompt.
    '')
  ];

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

2. Create `agent-skills/skills/<skill-name>/SKILL.md` with the skill content.

3. That's it — `discoverSkills` auto-discovers any directory under `skills/` that contains a `skill.nix`.

## Permissions

- A `Skill(agent-skills:<name>)` allow is auto-generated for every discovered skill and merged into `~/.claude/settings.json` via `programs.claude-nix.extraPermissions.allow` (additive — concatenates with claude-nix's defaults).
- Per-skill Bash allows go in `allowed-tools` inside that skill's `skill.nix`.
- Repo-wide additive perms (e.g. a new Bash variant every skill should have) go in `agent-skills/flake.nix` via `programs.claude-nix.extraPermissions.{allow,ask,deny}`, **not** `programs.claude-nix.settings.permissions.*` — the latter is a full-list replacement (via `lib.recursiveUpdate`) and will silently nuke the defaults shipped by claude-nix.
- Default Bash/`rtk` allows themselves live upstream in `claude-nix/modules/home-manager.nix` (`defaultSettings.permissions.allow`).

## How the Build System Works

1. **`discoverSkills ./skills`** — scans for directories with `skill.nix`, evaluates each (handles both plain attrsets and functions), builds skill derivations with frontmatter-injected SKILL.md
2. **`buildPlugin`** — aggregates all skills' commands, agents, mcpServers, lspServers into a single Claude plugin via `claudeLib.mkPlugin`
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

Skills hot-reload in modern Claude Code, but commands and plugin structure require a rebuild.
