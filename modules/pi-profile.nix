{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.programs.pi.coding-agent;
  modelsJson = pkgs.writeText "pi-models.json" (
    builtins.toJSON {
      providers = config.programs.agent-skills.pi.providers;
    }
  );
in
{
  options.programs.agent-skills.pi.providers = lib.mkOption {
    type = lib.types.attrsOf lib.types.attrs;
    default = { };
    description = "Pi provider definitions. Use environment names or commands for credentials, never literal secrets.";
  };

  config = lib.mkIf cfg.enable {
    programs.pi.coding-agent = {
      statusline = {
        enable = true;
        barWidth = 8;
      };
      environment = {
        PI_SKIP_VERSION_CHECK.value = "1";
        PI_AUTOMODE_NO_STATUS_SLOT.value = "1";
        # pi-lens otherwise downloads language servers and linters into
        # ~/.pi-lens at runtime; it uses whatever the project's devshell puts
        # on PATH instead.
        PI_LENS_DISABLE_LSP_INSTALL.value = "1";
        PI_LENS_DISABLE_TOOL_INSTALL.value = "1";
      };
      autoMode = {
        enable = true;
        classifierModel = "openai/gpt-6-luna";
        allowInsideWorkingDirectory = true;
        deniedPaths = [
          "~/.ssh/*"
          "/run/agenix/*"
          "~/.aws/*"
          "~/.config/op/*"
          "~/.pi/agent/auth.json"
          "~/.claude/.credentials.json"
          "*.env"
          # "*.env" stops at the extension, so .env.local and friends need their own.
          "*.env.*"
        ];
        # The shared classifier policy covers persistence-related writes.
        protectedPaths = [ ];
        permissions.deny = [
          "bash(*/run/agenix/*)"
          "bash(*/.ssh/id_*)"
          "bash(*/agent/auth.json*)"
          "bash(*/.credentials.json*)"
          "write(*.env)"
          "edit(*.env)"
        ];
        log.enable = true;
        # Let the classifier answer `external_directory` asks (a write to /tmp,
        # a read in a sibling repo) instead of prompting for every one. `path`
        # stays excluded: it is the gate the agenix and auth.json denies below
        # sit on, and a link may never turn it into an allow.
        permissionSystem.delegationExcludedSurfaces = [ "path" ];
        permissionSystem.settings = {
          debugLog = false;
          permissionReviewLog = true;
          yoloMode = false;
          permission = {
            # Unlisted tools fall to the default `"*": "ask"`, and every ask
            # costs a classifier call. These two cannot do harm: `todo` edits
            # the agent's own task list, and a `read` outside the working
            # directory still asks through external_directory below, so in
            # practice this frees only /nix/store reads.
            read = "allow";
            todo = "allow";
            # Auto mode answers the ask for any other external path.
            external_directory = {
              "*" = "ask";
              "/nix/store" = "allow";
              "/nix/store/*" = "allow";
            };
            path = {
              "/run/agenix/*" = "deny";
              "/proc/*/environ" = "deny";
              "${config.home.homeDirectory}/.pi/agent/auth.json" = "deny";
            };
          };
        };
      };
      notifications = {
        enable = true;
        events = [
          "needs_input"
          "settled"
        ];
      };
      foreignSkills.enable = true;
      custom.enable = true;
      messaging = {
        enable = true;
        askTimeoutSeconds = 300;
        installSkill = false;
      };
      settings = {
        # Sign in with ChatGPT lives on the openai provider since pi 1.0;
        # openai-codex is the legacy one.
        defaultProvider = "openai";
        defaultModel = "gpt-6-astra";
        # Ctrl+P cycles only these; /model still lists every provider. Exact
        # references, because a glob such as `openai/*` is also checked against
        # bare model IDs and so matches OpenRouter's `openai/gpt-…` models.
        enabledModels = [
          "openai/gpt-6-astra"
          "openai/gpt-6.1-sol"
          "openai/gpt-6-sol"
          "openai/gpt-6-luna"
        ];
        defaultThinkingLevel = "medium";
        tuiMode = "regular";
        enableAnalytics = false;
        enableInstallTelemetry = false;
        quietStartup = true;
        # Built in since pi 0.99.0 but registered inactive. MCP servers reach
        # the model through codemode's searchTools() by default.
        defaultTools = [ "+codemode" ];
      };
    };

    home.file.".pi/agent/keybindings.json".text = builtins.toJSON {
      "tui.editor.deleteWordBackward" = [
        "ctrl+w"
        "alt+backspace"
        "ctrl+backspace"
      ];
    };
    # Pi's models option only seeds an absent file; activation also applies edits.
    home.activation.piModelsJson = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      run mkdir -p ${lib.escapeShellArg "${config.home.homeDirectory}/.pi/agent"}
      run install -m 0600 ${modelsJson} ${lib.escapeShellArg "${config.home.homeDirectory}/.pi/agent/models.json"}
    '';
  };
}
