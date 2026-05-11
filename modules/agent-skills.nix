# Manages the shared ~/.agents/skills symlink.
# Import this module alongside the tool-specific modules (claude, gemini, codex).
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.programs.agent-skills;
  inherit (lib)
    mkOption
    mkEnableOption
    mkIf
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
  };

  config = mkIf cfg.enable {
    home.file = mkIf (builtins.pathExists "${combined}/skills") {
      ".agents/skills".source = "${combined}/skills";
    };

    xdg.configFile."agent-skills/.keep".text = "";
  };
}
