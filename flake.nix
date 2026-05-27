{
  description = "Agent skills, commands, and hooks for Claude, Antigravity, and Codex";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    claude-nix = {
      url = "github:joegoldin/claude-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    antigravity-cli-nix = {
      url = "github:joegoldin/antigravity-cli-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    codex-nix = {
      url = "git+ssh://git@github.com/joegoldin/codex-nix.git";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      claude-nix,
      antigravity-cli-nix,
      codex-nix,
      ...
    }:
    let
      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "aarch64-darwin"
        "x86_64-darwin"
      ];
      forAllSystems =
        f:
        nixpkgs.lib.genAttrs systems (
          system:
          f {
            pkgs = import nixpkgs { inherit system; };
            inherit system;
          }
        );
    in
    {
      packages = forAllSystems (
        { pkgs, ... }:
        let
          lib = pkgs.lib;
          claudeLib = import "${claude-nix}/lib" { inherit pkgs; };
          agyLib = import "${antigravity-cli-nix}/lib" { inherit pkgs lib; };
          codexLib = import "${codex-nix}/lib" { inherit pkgs lib; };
          build = import ./lib/default.nix {
            inherit
              pkgs
              lib
              claudeLib
              agyLib
              codexLib
              ;
          };

          skills = build.discoverSkills ./skills;

          codeNotify = pkgs.callPackage ./packages/code-notify { };
          wakatimePlugin = pkgs.callPackage ./packages/wakatime-plugin { };
          vibecad = pkgs.callPackage ./packages/vibecad { };
          pxd = pkgs.callPackage ./packages/pxd { };

          notifier = "${codeNotify}/lib/code-notify/core/notifier.sh";

          # ── Claude plugin ──
          claude-plugin = build.buildPlugin {
            name = "agent-skills";
            description = "Agent skills, commands, and agents";
            inherit skills;
            hooksDir = ./hooks;
            attributionFile = ./ATTRIBUTION.md;
            extraPackages = [ vibecad pxd ];
          };

          # ── Antigravity plugin (with code-notify hooks baked in) ──
          antigravity-plugin = build.buildAntigravityPlugin {
            name = "agent-skills";
            description = "Agent skills for Antigravity CLI";
            inherit skills;
            hooksDir = ./hooks;
            attributionFile = ./ATTRIBUTION.md;
            hooks = [
              (agyLib.mkHook {
                event = "Notification";
                name = "code-notify-notification";
                command = "${notifier} notification";
              })
              (agyLib.mkHook {
                event = "Stop";
                name = "code-notify-stop";
                command = "${notifier} stop";
              })
              (agyLib.mkHook {
                event = "PreToolUse";
                matcher = "Bash";
                name = "code-notify-pretooluse";
                command = "${notifier} PreToolUse";
              })
            ];
            extraPackages = [ vibecad pxd ];
          };

          # ── Codex plugin ──
          codex-plugin = build.buildCodexPlugin {
            name = "agent-skills";
            description = "Agent skills for Codex";
            inherit skills;
            hooksDir = ./hooks;
            attributionFile = ./ATTRIBUTION.md;
            extraPackages = [ vibecad pxd ];
          };

          # ── RTK plugins (per-target) ──
          claude-rtk-plugin = build.buildRtkPlugin {
            target = "claude";
            rtkPkg = pkgs.rtk;
            hooksDir = ./plugins/rtk/hooks;
            attributionFile = ./ATTRIBUTION.md;
          };

          antigravity-rtk-plugin = build.buildRtkPlugin {
            target = "antigravity";
            rtkPkg = pkgs.rtk;
            hooksDir = ./plugins/rtk/hooks;
            attributionFile = ./ATTRIBUTION.md;
          };

          codex-rtk-plugin = build.buildRtkPlugin {
            target = "codex";
            rtkPkg = pkgs.rtk;
            hooksDir = ./plugins/rtk/hooks;
            attributionFile = ./ATTRIBUTION.md;
          };

          # ── Temporal plugins (per-target) ──
          claude-temporal-plugin = build.buildTemporalPlugin {
            target = "claude";
            scriptDir = ./plugins/temporal;
            stateDir = "$HOME/.claude/.temporal";
            attributionFile = ./ATTRIBUTION.md;
          };

          antigravity-temporal-plugin = build.buildTemporalPlugin {
            target = "antigravity";
            scriptDir = ./plugins/temporal;
            stateDir = "$HOME/.antigravity/.temporal";
            attributionFile = ./ATTRIBUTION.md;
          };

          codex-temporal-plugin = build.buildTemporalPlugin {
            target = "codex";
            scriptDir = ./plugins/temporal;
            stateDir = "$HOME/.codex/.temporal";
            attributionFile = ./ATTRIBUTION.md;
          };

          perSkillPackages = lib.listToAttrs (
            map (s: {
              name = s.name;
              value = s.drv;
            }) skills
          );
        in
        perSkillPackages
        // {
          default = claude-plugin;
          inherit
            claude-plugin
            claude-rtk-plugin
            claude-temporal-plugin
            antigravity-plugin
            antigravity-rtk-plugin
            antigravity-temporal-plugin
            codex-plugin
            codex-rtk-plugin
            codex-temporal-plugin
            codeNotify
            vibecad
            pxd
            wakatimePlugin
            ;
        }
      );

      # ── Re-exported home-manager modules ──
      homeManagerModules =
        let
          mkCodeNotifyHooks =
            codeNotify:
            let
              notifier = "${codeNotify}/lib/code-notify/core/notifier.sh";
            in
            {
              Notification = [
                {
                  matcher = "";
                  hooks = [
                    {
                      type = "command";
                      command = "${notifier} notification";
                    }
                  ];
                }
              ];
              Stop = [
                {
                  matcher = "";
                  hooks = [
                    {
                      type = "command";
                      command = "${notifier} stop";
                    }
                  ];
                }
              ];
              PreToolUse = [
                {
                  matcher = "Bash";
                  hooks = [
                    {
                      type = "command";
                      command = "${notifier} PreToolUse";
                    }
                  ];
                }
              ];
            };
        in
        {
          claude =
            {
              lib,
              pkgs,
              ...
            }:
            let
              codeNotify = self.packages.${pkgs.system}.codeNotify;
              claudeRtkPlugin = self.packages.${pkgs.system}.claude-rtk-plugin;
              claudeRtkHook = claudeRtkPlugin.passthru._claudeRtkHook;
              claudeTemporalPlugin = self.packages.${pkgs.system}.claude-temporal-plugin;
              claudeTemporalScript = claudeTemporalPlugin.passthru._temporalScript;
              skills =
                (import ./lib/default.nix {
                  inherit pkgs lib;
                  claudeLib = import "${claude-nix}/lib" { inherit pkgs; };
                }).discoverSkills
                  ./skills;
              skillPermissions = map (s: "Skill(agent-skills:${s.name})") skills;
            in
            {
              imports = [ "${claude-nix}/modules/home-manager.nix" ];
              programs.claude-nix.plugins = lib.mkBefore [
                self.packages.${pkgs.system}.claude-plugin
                self.packages.${pkgs.system}.claude-rtk-plugin
                self.packages.${pkgs.system}.claude-temporal-plugin
              ];
              programs.claude-nix.settings = {
                permissions.allow = skillPermissions;
                hooks =
                  let
                    codeNotifyHooks = mkCodeNotifyHooks codeNotify;
                    rtkPreToolUse = [
                      {
                        matcher = "Bash";
                        hooks = [{ type = "command"; command = "${claudeRtkHook}"; }];
                      }
                    ];
                    temporalUserPromptSubmit = [
                      {
                        matcher = "";
                        hooks = [{ type = "command"; command = "${claudeTemporalScript}"; }];
                      }
                    ];
                    temporalSessionStart = [
                      {
                        matcher = "startup|resume|clear|compact";
                        hooks = [{ type = "command"; command = "${claudeTemporalScript}"; }];
                      }
                    ];
                  in
                  codeNotifyHooks // {
                    PreToolUse = (codeNotifyHooks.PreToolUse or [ ]) ++ rtkPreToolUse;
                    UserPromptSubmit = (codeNotifyHooks.UserPromptSubmit or [ ]) ++ temporalUserPromptSubmit;
                    SessionStart = (codeNotifyHooks.SessionStart or [ ]) ++ temporalSessionStart;
                  };
              };
            };

          antigravity =
            {
              lib,
              pkgs,
              ...
            }:
            {
              imports = [ "${antigravity-cli-nix}/modules/home-manager.nix" ];
              programs.antigravity-cli-nix.plugins = lib.mkBefore [
                self.packages.${pkgs.system}.antigravity-plugin
                self.packages.${pkgs.system}.antigravity-rtk-plugin
                self.packages.${pkgs.system}.antigravity-temporal-plugin
              ];
            };

          codex =
            {
              lib,
              pkgs,
              ...
            }:
            let
              codeNotify = self.packages.${pkgs.system}.codeNotify;
              notifier = "${codeNotify}/lib/code-notify/core/notifier.sh";
              codexLib = import "${codex-nix}/lib" { inherit pkgs lib; };
            in
            {
              imports = [ "${codex-nix}/modules/home-manager.nix" ];
              programs.codex-nix.plugins = lib.mkBefore [
                (
                  self.packages.${pkgs.system}.codex-plugin
                  // {
                    _codex = (self.packages.${pkgs.system}.codex-plugin._codex or { }) // {
                      hooks = (self.packages.${pkgs.system}.codex-plugin._codex.hooks or [ ]) ++ [
                        (codexLib.mkHook {
                          event = "Notification";
                          name = "code-notify-notification";
                          command = "${notifier} notification";
                        })
                        (codexLib.mkHook {
                          event = "Stop";
                          name = "code-notify-stop";
                          command = "${notifier} stop";
                        })
                        (codexLib.mkHook {
                          event = "PreToolUse";
                          matcher = "Bash";
                          name = "code-notify-pretooluse";
                          command = "${notifier} PreToolUse";
                        })
                      ];
                    };
                  }
                )
                self.packages.${pkgs.system}.codex-rtk-plugin
                self.packages.${pkgs.system}.codex-temporal-plugin
              ];
            };

          agent-skills =
            {
              lib,
              pkgs,
              ...
            }:
            {
              imports = [ ./modules/agent-skills.nix ];
              programs.agent-skills.enable = lib.mkDefault true;
              programs.agent-skills.plugins = lib.mkBefore [
                self.packages.${pkgs.system}.claude-plugin
              ];
            };
        };

      # ── Re-exported libs ──
      lib = forAllSystems (
        { pkgs, ... }:
        {
          claudeLib = import "${claude-nix}/lib" { inherit pkgs; };
          agyLib = import "${antigravity-cli-nix}/lib" {
            inherit pkgs;
            lib = pkgs.lib;
          };
          codexLib = import "${codex-nix}/lib" {
            inherit pkgs;
            lib = pkgs.lib;
          };
        }
      );
    };
}
