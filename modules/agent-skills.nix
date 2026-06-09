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
  inherit (lib)
    mkOption
    mkEnableOption
    mkIf
    mkMerge
    types
    ;

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
  };

  config = mkIf cfg.enable (mkMerge [
    {
      home.file = mkIf (builtins.pathExists "${combined}/skills") {
        ".agents/skills".source = "${combined}/skills";
      };

      xdg.configFile."agent-skills/.keep".text = "";
    }

    # Fan out normalized servers to each target whose module is imported.
    (mkIf (options.programs ? claude-nix) {
      programs.claude-nix.mcpServers = mcpLib.mcpNativeFor "claude" cfg.mcpServers;
    })
    (mkIf (options.programs ? codex-nix) {
      programs.codex-nix.mcpServers = mcpLib.mcpNativeFor "codex" cfg.mcpServers;
    })
    (mkIf (options.programs ? antigravity-cli-nix) {
      programs.antigravity-cli-nix.mcpServers = mcpLib.mcpNativeFor "antigravity" cfg.mcpServers;
    })
  ]);
}
