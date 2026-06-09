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
            pkgs = import nixpkgs {
              inherit system;
              config.allowUnfree = true;
            };
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
          vibecad = pkgs.callPackage ./packages/vibecad { };
          pxd = pkgs.callPackage ./packages/pxd { };

          # ── Claude plugin ──
          claude-plugin = build.buildPlugin {
            name = "agent-skills";
            description = "Agent skills, commands, and agents";
            inherit skills;
            hooksDir = ./hooks;
            attributionFile = ./ATTRIBUTION.md;
            extraPackages = [ vibecad pxd ];
          };

          # ── Antigravity plugin ──
          antigravity-plugin = build.buildAntigravityPlugin {
            name = "agent-skills";
            description = "Agent skills for Antigravity CLI";
            inherit skills;
            hooksDir = ./hooks;
            attributionFile = ./ATTRIBUTION.md;
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

          # ── Cross-agent plugins (rtk, temporal, code-notify) ──
          # Discovered from ./plugins; built per target. Exposed as
          # "<name>-<target>" packages (e.g. rtk-claude, temporal-codex).
          targetLibs = {
            claude = claudeLib;
            antigravity = agyLib;
            codex = codexLib;
          };
          discoveredPlugins = build.discoverPlugins ./plugins;
          crossPlugins = lib.listToAttrs (
            lib.concatMap (
              target:
              map (p: {
                name = "${p.name}-${target}";
                value = build.mkCrossAgentPlugin {
                  def = p.raw { inherit pkgs lib target; };
                  inherit target;
                  targetLib = targetLibs.${target};
                  attributionFile = ./ATTRIBUTION.md;
                };
              }) discoveredPlugins
            ) [ "claude" "antigravity" "codex" ]
          );

          perSkillPackages = lib.listToAttrs (
            map (s: {
              name = s.name;
              value = s.drv;
            }) skills
          );
        in
        perSkillPackages
        // crossPlugins
        // {
          default = claude-plugin;
          inherit
            claude-plugin
            antigravity-plugin
            codex-plugin
            codeNotify
            vibecad
            pxd
            ;
        }
      );

      checks = forAllSystems (
        { pkgs, ... }:
        let
          lib = pkgs.lib;
          mcp = import ./lib/mcp.nix { inherit lib; };
          # Fill submodule defaults exactly as the real option does.
          servers =
            (lib.evalModules {
              modules = [
                {
                  options.servers = lib.mkOption { type = lib.types.attrsOf mcp.normalizedModule; };
                  config.servers = {
                    ctx = {
                      command = "npx";
                      args = [ "-y" "ctx" ];
                    };
                    remote = {
                      url = "https://x/mcp";
                      headers.Authorization = "Bearer Y";
                      bearerTokenEnvVar = "TOK";
                    };
                    off = {
                      command = "nope";
                      disabled = true;
                    };
                  };
                }
              ];
            }).config.servers;
          claudeJson = pkgs.writeText "claude-mcp.json" (builtins.toJSON (mcp.mcpNativeFor "claude" servers));
          agyJson = pkgs.writeText "agy-mcp.json" (builtins.toJSON (mcp.mcpNativeFor "antigravity" servers));
          codexJson = pkgs.writeText "codex-mcp.json" (builtins.toJSON (mcp.mcpNativeFor "codex" servers));
        in
        {
          eval-mcp =
            pkgs.runCommand "eval-mcp" { nativeBuildInputs = [ pkgs.jq ]; } ''
              # disabled servers are omitted from every target
              jq -e 'has("off") | not' ${claudeJson} >/dev/null
              jq -e 'has("off") | not' ${agyJson} >/dev/null
              jq -e 'has("off") | not' ${codexJson} >/dev/null

              # stdio is identical across all three targets
              jq -e '.ctx.command == "npx" and (.ctx.args == ["-y","ctx"])' ${claudeJson} >/dev/null
              jq -e '.ctx.command == "npx"' ${agyJson} >/dev/null
              jq -e '.ctx.command == "npx"' ${codexJson} >/dev/null

              # claude remote → type:"http" + url + headers
              jq -e '.remote.type == "http" and .remote.url == "https://x/mcp" and .remote.headers.Authorization == "Bearer Y"' ${claudeJson} >/dev/null

              # antigravity remote → serverUrl (no url), + headers
              jq -e '.remote.serverUrl == "https://x/mcp" and (.remote | has("url") | not)' ${agyJson} >/dev/null

              # codex remote → url + bearer_token_env_var + http_headers (no headers/type)
              jq -e '.remote.url == "https://x/mcp" and .remote.bearer_token_env_var == "TOK" and .remote.http_headers.Authorization == "Bearer Y"' ${codexJson} >/dev/null
              jq -e '.remote | (has("type") | not) and (has("serverUrl") | not)' ${codexJson} >/dev/null

              touch $out
            '';
        }
      );

      # ── Re-exported home-manager modules ──
      homeManagerModules =
        {
          claude =
            {
              lib,
              pkgs,
              ...
            }:
            let
              build = import ./lib/default.nix {
                inherit pkgs lib;
                claudeLib = import "${claude-nix}/lib" { inherit pkgs; };
              };
              skills = build.discoverSkills ./skills;
              skillPermissions = map (s: "Skill(agent-skills:${s.name})") skills;
              claudePlugins = map (
                p: self.packages.${pkgs.system}."${p.name}-claude"
              ) (build.discoverPlugins ./plugins);
            in
            {
              imports = [ "${claude-nix}/modules/home-manager.nix" ];
              programs.claude-nix.plugins = lib.mkBefore (
                [ self.packages.${pkgs.system}.claude-plugin ] ++ claudePlugins
              );
              programs.claude-nix.extraPermissions.allow = skillPermissions;
              programs.claude-nix.extraHooks = build.foldClaudeHooks (
                map (p: p.passthru.claudeHooks or { }) claudePlugins
              );
              programs.claude-nix.statusLine.enable = true;
            };

          antigravity =
            {
              lib,
              pkgs,
              ...
            }:
            let
              build = import ./lib/default.nix {
                inherit pkgs lib;
                claudeLib = import "${claude-nix}/lib" { inherit pkgs; };
              };
              antigravityPlugins = map (
                p: self.packages.${pkgs.system}."${p.name}-antigravity"
              ) (build.discoverPlugins ./plugins);
            in
            {
              imports = [ "${antigravity-cli-nix}/modules/home-manager.nix" ];
              programs.antigravity-cli-nix.plugins = lib.mkBefore (
                [ self.packages.${pkgs.system}.antigravity-plugin ] ++ antigravityPlugins
              );
            };

          codex =
            {
              lib,
              pkgs,
              ...
            }:
            let
              build = import ./lib/default.nix {
                inherit pkgs lib;
                claudeLib = import "${claude-nix}/lib" { inherit pkgs; };
              };
              codexPlugins = map (
                p: self.packages.${pkgs.system}."${p.name}-codex"
              ) (build.discoverPlugins ./plugins);
            in
            {
              imports = [ "${codex-nix}/modules/home-manager.nix" ];
              programs.codex-nix.plugins = lib.mkBefore (
                [ self.packages.${pkgs.system}.codex-plugin ] ++ codexPlugins
              );
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

      # ── Positive list of claude-targeted plugin packages ──
      # Same set the homeManagerModules.claude wires into
      # programs.claude-nix.plugins. Exposed so downstream consumers
      # (claude-container's image build) can take the canonical list
      # without filtering by name suffix — a future skill named
      # `something-claude` would otherwise sneak into the container
      # under that pattern.
      claudePlugins = nixpkgs.lib.genAttrs systems (
        system:
        let
          pkgs = import nixpkgs {
            inherit system;
            config.allowUnfree = true;
          };
          build = import ./lib/default.nix {
            inherit pkgs;
            lib = pkgs.lib;
            claudeLib = import "${claude-nix}/lib" { inherit pkgs; };
          };
          discoveredPlugins = build.discoverPlugins ./plugins;
        in
        [ self.packages.${system}.claude-plugin ]
        ++ map (p: self.packages.${system}."${p.name}-claude") discoveredPlugins
      );
    };
}
