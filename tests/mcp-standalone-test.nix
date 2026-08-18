# programs.agent-skills must evaluate on a host that installs none of the
# agents it fans out to. The fan-out arms use `lib.optional`, not `mkIf`,
# because `mkIf false` still leaves its option path in the definition set: a
# `mkIf` arm naming an undeclared option fails with "The option `programs.X'
# does not exist" regardless of the condition.
#
# Without this the module could only be imported by a host that installs every
# agent, which is the opposite of what `mcpServers` documents.
{ pkgs ? import <nixpkgs> { } }:
let
  lib = pkgs.lib;

  evaluated = lib.evalModules {
    modules = [
      (import ../modules/agent-skills.nix)
      { _module.args = { inherit pkgs; }; }
      {
        options.home = lib.mkOption {
          type = lib.types.attrs;
          default = { };
        };
        options.xdg = lib.mkOption {
          type = lib.types.attrs;
          default = { };
        };
        config.programs.agent-skills = {
          enable = true;
          mcpServers.demo.command = "true";
        };
      }
    ];
  };

  cfg = evaluated.config.programs.agent-skills;
in
assert cfg.enable;
# The declaration survives even though no target consumed it.
assert cfg.mcpServers ? demo;
pkgs.runCommand "mcp-standalone-tests" { } "touch $out"
