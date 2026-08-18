# Manages the shared ~/.agents/skills symlink and the normalized,
# fan-out MCP configuration for all installed agents.
# Import this module alongside the tool-specific modules (claude, antigravity, codex).
{
  config,
  lib,
  options,
  pkgs,
  ...
}:
let
  cfg = config.programs.agent-skills;
  mcpLib = import ../lib/mcp.nix { inherit lib; };
  promptLib = import ../lib/prompt.nix { inherit lib; };
  inherit (lib)
    mkOption
    mkEnableOption
    mkIf
    mkMerge
    types
    ;

  sharedText = promptLib.mkPrompt {
    layers = [ ../prompt/shared ];
    extra = cfg.prompt.extraShared;
  };

  # core/ replaces pi's default prompt, which is why it is pi-only: the other
  # three harnesses ship equivalent harness mechanics built in, and appending
  # ours would duplicate and contradict them.
  piText = promptLib.mkPrompt {
    layers = [
      ../prompt/core
      ../prompt/shared
      ../prompt/pi
    ];
    extra = cfg.prompt.extraShared;
  };

  # Antigravity applies progressive disclosure to rules: per the shipped CLI's
  # embedded customization docs, only `always_on` rules load unconditionally.
  # A behavioural layer the model may decline to read is worth nothing, so the
  # rule file carries the frontmatter the CLI's own rule template uses.
  agyRuleText = "---\ntrigger: always_on\n---\n\n" + sharedText;

  # Combine all skill plugins into a single tree
  combined = pkgs.buildEnv {
    name = "agent-skills-combined";
    paths = cfg.plugins;
  };
in
{
  options.programs.agent-skills = {
    enable = mkEnableOption "shared agent skills directory at ~/.agents/skills";

    plugins = mkOption {
      type = types.listOf types.package;
      default = [ ];
      description = ''
        List of plugin derivations whose skills/ directories are merged
        and symlinked into `~/.agents/skills`.
      '';
    };

    mcpServers = mkOption {
      type = types.attrsOf mcpLib.normalizedModule;
      default = { };
      example = lib.literalExpression ''
        {
          nixos.command = "mcp-nixos";
          context7 = {
            command = "npx";
            args = [ "-y" "@upstash/context7-mcp" ];
          };
          figma = {
            url = "https://mcp.figma.com/mcp";
            bearerTokenEnvVar = "FIGMA_OAUTH_TOKEN";
          };
        }
      '';
      description = ''
        Normalized MCP servers declared once and fanned out to every installed
        agent (claude-nix, codex-nix, antigravity-cli-nix) in that agent's
        native format. Each server is stdio (`command`/`args`/`env`) or remote
        (`url`/`headers`/`bearerTokenEnvVar`). `disabled = true` omits a server
        from every target. Only targets whose home-manager module is imported
        receive config.
      '';
    };

    prompt = {
      enable = mkOption {
        type = types.bool;
        default = true;
        description = ''
          Append the shared behavioural-preference layer to every installed
          agent, and give pi the full replacement system prompt.
        '';
      };

      extraShared = mkOption {
        type = types.lines;
        default = "";
        example = "Prefer tabs over spaces in this repository.\n";
        description = ''
          Extra markdown appended after the shared layer, for every agent.
          Subject to the same governing rule as the tracked fragments —
          state policy, not inventory — but not covered by the build lint,
          which only sees the tracked tree.
        '';
      };

      sharedText = mkOption {
        type = types.str;
        readOnly = true;
        description = ''
          The composed shared layer. Read-only; set `extraShared` to add to
          it. Exposed so other modules can reuse the exact text.
        '';
      };

      piText = mkOption {
        type = types.str;
        readOnly = true;
        description = ''
          The composed pi system prompt: core + shared + pi. Read-only.
        '';
      };
    };
  };

  config = mkIf cfg.enable (
    mkMerge (
      [
        {
          home.file = mkIf (builtins.pathExists "${combined}/skills") {
            ".agents/skills".source = "${combined}/skills";
          };

          xdg.configFile."agent-skills/.keep".text = "";
        }

        { programs.agent-skills.prompt = { inherit sharedText piText; }; }
      ]
      # Fan out normalized servers to each target whose module is imported.
      # `optional`, not `mkIf`: a `mkIf false` arm still leaves its option path
      # in the definition set, so naming an undeclared option fails evaluation
      # with "The option `programs.X' does not exist" no matter what the
      # condition says. Without this the module could only be imported by a
      # host that installs every agent, which is the opposite of what
      # `mcpServers` promises.
      ++ lib.optional (options.programs ? claude-nix) {
        programs.claude-nix.mcpServers = mcpLib.mcpNativeFor "claude" cfg.mcpServers;
      }
      ++ lib.optional (options.programs ? codex-nix) {
        programs.codex-nix.mcpServers = mcpLib.mcpNativeFor "codex" cfg.mcpServers;
      }
      ++ lib.optional (options.programs ? antigravity-cli-nix) {
        programs.antigravity-cli-nix.mcpServers = mcpLib.mcpNativeFor "antigravity" cfg.mcpServers;
      }
      # ── System prompt fan-out ──
      # Same "is this module imported" question the MCP arms above ask, but asked
      # with `optional` rather than `mkIf`. `mkIf false` still leaves the option
      # path in the definition set, so a `mkIf` arm naming an undeclared option
      # fails with "The option `programs.pi' does not exist" instead of going
      # quiet — and pi-nix's module is the one target that may legitimately be
      # absent. `optional` drops the attrset whole, so the path is never named.
      #
      # The three non-pi agents get the shared layer only; pi gets the full
      # replacement prompt.
      ++ lib.optional (options.programs ? claude-nix) (
        mkIf cfg.prompt.enable { programs.claude-nix.globalClaudeMd = sharedText; }
      )
      ++ lib.optional (options.programs ? codex-nix) (
        mkIf cfg.prompt.enable { programs.codex-nix.agentsMd = sharedText; }
      )
      # Antigravity has no instruction-file option; its global customization root
      # is `~/.gemini/config/` and rules live in `rules/` beneath it, per the
      # shipped CLI's embedded docs. The file name is namespaced so hand-written
      # rules can sit alongside.
      ++ lib.optional (options.programs ? antigravity-cli-nix) (
        mkIf cfg.prompt.enable {
          home.file.".gemini/config/rules/agent-skills-shared.md".text = agyRuleText;
        }
      )
      # pi-nix's `systemPrompt` option passes --system-prompt, which fully
      # replaces pi's default; skills and context files still append after it.
      ++ lib.optional (options.programs ? pi) (
        mkIf cfg.prompt.enable { programs.pi.coding-agent.systemPrompt = piText; }
      )
    )
  );
}
