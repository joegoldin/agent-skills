# Evaluates modules/agent-skills.nix against stub agent modules and asserts
# the fan-out lands where it should. Returns [ ] when everything passes.
#
# The stubs declare only the options the module writes into. That is the whole
# point: an arm that names an option no stub declares fails here rather than on
# a user's machine, and an arm guarded by `lib.optional` disappears cleanly
# when its stub is absent.
{ pkgs, lib }:
let
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

  base =
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
      };
    };

  # pi as pi-nix actually declares it: no mcpServers of its own, a
  # types.attrs settings blob, the phase-5 systemPrompt, and the autoMode
  # option phases 3 and 6 will grow.
  piStub =
    { lib, ... }:
    {
      options.programs.pi.coding-agent = {
        settings = lib.mkOption {
          type = lib.types.attrs;
          default = { };
        };
        systemPrompt = lib.mkOption {
          type = lib.types.lines;
          default = "";
        };
        autoMode = lib.mkOption {
          type = lib.types.attrs;
          default = { };
        };
      };
    };

  claudeStub =
    { lib, ... }:
    {
      options.programs.claude-nix = {
        mcpServers = lib.mkOption {
          type = lib.types.attrs;
          default = { };
        };
        globalClaudeMd = lib.mkOption {
          type = lib.types.lines;
          default = "";
        };
        autoMode = lib.mkOption {
          type = lib.types.attrs;
          default = { };
        };
      };
    };

  declaration = {
    programs.agent-skills = {
      enable = true;
      mcpServers.ctx = {
        command = "npx";
        args = [
          "-y"
          "ctx"
        ];
      };
      mcpServers.remote = {
        url = "https://x/mcp";
        bearerTokenEnvVar = "TOK";
      };
      autoMode = {
        allow = [ "read files" ];
        hard_deny = [ "exfiltrate secrets" ];
      };
    };
  };

  evalWith =
    modules:
    (lib.evalModules {
      specialArgs = { inherit pkgs; };
      modules = [
        base
        ../modules/agent-skills.nix
        declaration
      ]
      ++ modules;
    }).config;

  withPi = evalWith [ piStub ];
  withoutPi = evalWith [ claudeStub ];

  piMcp = builtins.fromJSON withPi.home.file.".agents/mcp.json".text;
  promptLib = import ../lib/prompt.nix { inherit lib; };
in
lib.debug.runTests {
  testPiMcpFileWritten = {
    expr = piMcp.mcpServers.ctx.command;
    expected = "npx";
  };
  testPiMcpRemoteShape = {
    expr = {
      inherit (piMcp.mcpServers.remote) url auth bearerTokenEnv;
    };
    expected = {
      url = "https://x/mcp";
      auth = "bearer";
      bearerTokenEnv = "TOK";
    };
  };
  testNoPiNoMcpFile = {
    expr = withoutPi.home.file ? ".agents/mcp.json";
    expected = false;
  };
  testAutoModeFansOutToPi = {
    expr = withPi.programs.pi.coding-agent.autoMode.hard_deny;
    expected = [ "exfiltrate secrets" ];
  };
  testAutoModeFansOutToClaude = {
    expr = withoutPi.programs.claude-nix.autoMode.allow;
    expected = [ "read files" ];
  };
  # Phase 5's pi arm, now checked against a stub that spells systemPrompt the
  # way pi-nix does. Before this file existed no test declared programs.pi at
  # all, so the arm was only ever exercised by its absence.
  testPiSystemPromptReceivesFullStack = {
    expr =
      withPi.programs.pi.coding-agent.systemPrompt == promptLib.mkPrompt {
        layers = [
          ../prompt/core
          ../prompt/shared
          ../prompt/pi
        ];
      };
    expected = true;
  };
}
