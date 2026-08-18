# Evaluates modules/agent-skills.nix against stub declarations for the four
# agent modules, and asserts each arm receives the right layer. The stubs are
# deliberately minimal: this test is about which text lands where, not about
# reproducing home-manager.
{
  pkgs ? import <nixpkgs> { },
}:
let
  lib = pkgs.lib;
  promptLib = import ../lib/prompt.nix { inherit lib; };

  expectedShared = promptLib.mkPrompt { layers = [ ../prompt/shared ]; };
  expectedPi = promptLib.mkPrompt {
    layers = [
      ../prompt/core
      ../prompt/shared
      ../prompt/pi
    ];
  };

  # Antigravity loads a rule unconditionally only when its frontmatter says
  # so, so its file is the shared text behind a two-line header rather than
  # the shared text alone. See modules/agent-skills.nix.
  expectedAgyRule = "---\ntrigger: always_on\n---\n\n" + expectedShared;

  fileStub = lib.types.attrsOf (
    lib.types.submodule {
      options = {
        text = lib.mkOption {
          type = lib.types.nullOr lib.types.lines;
          default = null;
        };
        source = lib.mkOption {
          type = lib.types.nullOr lib.types.path;
          default = null;
        };
      };
    }
  );

  stubs =
    { lib, ... }:
    {
      options = {
        home.file = lib.mkOption {
          type = fileStub;
          default = { };
        };
        xdg.configFile = lib.mkOption {
          type = fileStub;
          default = { };
        };
        programs.claude-nix.globalClaudeMd = lib.mkOption {
          type = lib.types.lines;
          default = "";
        };
        programs.claude-nix.mcpServers = lib.mkOption {
          type = lib.types.attrs;
          default = { };
        };
        programs.codex-nix.agentsMd = lib.mkOption {
          type = lib.types.lines;
          default = "";
        };
        programs.codex-nix.mcpServers = lib.mkOption {
          type = lib.types.attrs;
          default = { };
        };
        programs.antigravity-cli-nix.mcpServers = lib.mkOption {
          type = lib.types.attrs;
          default = { };
        };
      };
    };

  # `extra` is a module in its own right, not an attrset merged with `//`.
  # `//` is shallow, so `{ programs.agent-skills.enable = true; } // extra`
  # would drop `enable` whenever `extra` also touched `programs`, and every
  # assertion about the disabled case would then pass vacuously.
  eval =
    extra:
    (lib.evalModules {
      specialArgs = { inherit pkgs; };
      modules = [
        stubs
        ../modules/agent-skills.nix
        { programs.agent-skills.enable = true; }
        extra
      ];
    }).config;

  on = eval { };
  off = eval { programs.agent-skills.prompt.enable = false; };
  withExtra = eval { programs.agent-skills.prompt.extraShared = "Prefer tabs.\n"; };

  agyPath = ".gemini/config/rules/agent-skills-shared.md";
in
# The disabled case must be non-vacuous: prove the module is still enabled.
assert off.programs.agent-skills.enable;
assert on.programs.claude-nix.globalClaudeMd == expectedShared;
assert on.programs.codex-nix.agentsMd == expectedShared;
assert on.home.file.${agyPath}.text == expectedAgyRule;
assert lib.hasSuffix expectedShared on.home.file.${agyPath}.text;
assert on.programs.agent-skills.prompt.sharedText == expectedShared;
assert on.programs.agent-skills.prompt.piText == expectedPi;
# core/ must never reach the three agents that ship their own.
assert !(lib.hasInfix "# Working agreement" on.programs.claude-nix.globalClaudeMd);
assert !(lib.hasInfix "# Working agreement" on.programs.codex-nix.agentsMd);
assert !(lib.hasInfix "# Working agreement" on.home.file.${agyPath}.text);
# Disabling is a real off switch on every arm.
assert off.programs.claude-nix.globalClaudeMd == "";
assert off.programs.codex-nix.agentsMd == "";
assert !(off.home.file ? ${agyPath});
# extraShared appends, and reaches both composed texts.
assert lib.hasSuffix "Prefer tabs.\n" withExtra.programs.claude-nix.globalClaudeMd;
assert lib.hasInfix "Prefer tabs." withExtra.programs.agent-skills.prompt.piText;
# The pre-existing skills symlink and keep-file are untouched.
assert on.xdg.configFile ? "agent-skills/.keep";
pkgs.runCommand "prompt-fanout-tests" { } "touch $out"
