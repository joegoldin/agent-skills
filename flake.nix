{
  description = "Agent skills, commands, and hooks for Claude, Gemini, and Codex";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    claude-nix = {
      url = "github:joegoldin/claude-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    gemini-nix = {
      url = "github:joegoldin/gemini-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    codex-nix = {
      url = "path:/home/joe/Development/codex-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      claude-nix,
      gemini-nix,
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
          geminiLib = import "${gemini-nix}/lib" { inherit pkgs lib; };
          codexLib = import "${codex-nix}/lib" { inherit pkgs lib; };
          build = import ./lib/default.nix {
            inherit
              pkgs
              lib
              claudeLib
              geminiLib
              codexLib
              ;
          };

          # Discover and build all skills
          skills = build.discoverSkills ./skills;

          # code-notify package
          codeNotify = pkgs.callPackage ./packages/code-notify.nix { };

          # ── Claude plugin ──
          claude-plugin = build.buildPlugin {
            name = "agent-skills";
            description = "Agent skills, commands, and agents";
            inherit skills;
            hooksDir = ./hooks;
            attributionFile = ./ATTRIBUTION.md;
          };

          # ── Gemini plugin ──
          gemini-plugin = build.buildGeminiPlugin {
            name = "agent-skills";
            description = "Agent skills for Gemini CLI";
            inherit skills;
            attributionFile = ./ATTRIBUTION.md;
          };

          # ── Codex plugin ──
          codex-plugin = build.buildCodexPlugin {
            name = "agent-skills";
            description = "Agent skills for Codex";
            inherit skills;
            attributionFile = ./ATTRIBUTION.md;
          };

          # Per-skill packages (auto-generated)
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
            gemini-plugin
            codex-plugin
            codeNotify
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
              programs.claude-nix.plugins = lib.mkDefault [
                self.packages.${pkgs.system}.claude-plugin
              ];
              programs.claude-nix.settings = {
                permissions.allow = skillPermissions;
                hooks = mkCodeNotifyHooks codeNotify;
              };
            };

          gemini =
            {
              lib,
              pkgs,
              ...
            }:
            let
              codeNotify = self.packages.${pkgs.system}.codeNotify;
              notifier = "${codeNotify}/lib/code-notify/core/notifier.sh";
              geminiLib = import "${gemini-nix}/lib" { inherit pkgs lib; };
            in
            {
              imports = [ "${gemini-nix}/modules/home-manager.nix" ];
              programs.gemini-nix.plugins = lib.mkDefault [
                (
                  self.packages.${pkgs.system}.gemini-plugin
                  // {
                    _gemini = (self.packages.${pkgs.system}.gemini-plugin._gemini or { }) // {
                      hooks = (self.packages.${pkgs.system}.gemini-plugin._gemini.hooks or [ ]) ++ [
                        (geminiLib.mkHook {
                          event = "Notification";
                          name = "code-notify-notification";
                          command = "${notifier} notification";
                        })
                        (geminiLib.mkHook {
                          event = "Stop";
                          name = "code-notify-stop";
                          command = "${notifier} stop";
                        })
                        (geminiLib.mkHook {
                          event = "PreToolUse";
                          matcher = "Bash";
                          name = "code-notify-pretooluse";
                          command = "${notifier} PreToolUse";
                        })
                      ];
                    };
                  }
                )
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
              programs.codex-nix.plugins = lib.mkDefault [
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
              programs.agent-skills.plugins = lib.mkDefault [
                self.packages.${pkgs.system}.claude-plugin
              ];
            };
        };

      # ── Re-exported libs ──
      lib = forAllSystems (
        { pkgs, ... }:
        {
          claudeLib = import "${claude-nix}/lib" { inherit pkgs; };
          geminiLib = import "${gemini-nix}/lib" {
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
