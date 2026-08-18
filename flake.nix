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
      # github: (not git+ssh) so CI — garnix injects its app token for github:
      # refs but has no SSH key — and tokenized local nix can fetch it.
      url = "github:joegoldin/codex-nix";
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

          vibecad = pkgs.callPackage ./packages/vibecad { };
          pxd = pkgs.callPackage ./packages/pxd { };
          figr = pkgs.callPackage ./packages/figr { };
          avoidAiDetect = pkgs.callPackage ./packages/avoid-ai-detect { };

          # ── Claude plugin ──
          # Skill-owned tool packages (figr, pxd, vibecad, avoid-ai-detect)
          # ride in via each skill's sidecar `packages`, not extraPackages.
          claude-plugin = build.buildPlugin {
            name = "agent-skills";
            description = "Agent skills, commands, and agents";
            inherit skills;
            hooksDir = ./hooks;
            attributionFile = ./ATTRIBUTION.md;
          };

          # ── Antigravity plugin ──
          antigravity-plugin = build.buildAntigravityPlugin {
            name = "agent-skills";
            description = "Agent skills for Antigravity CLI";
            inherit skills;
            hooksDir = ./hooks;
            attributionFile = ./ATTRIBUTION.md;
          };

          # ── Codex plugin ──
          codex-plugin = build.buildCodexPlugin {
            name = "agent-skills";
            description = "Agent skills for Codex";
            inherit skills;
            hooksDir = ./hooks;
            attributionFile = ./ATTRIBUTION.md;
          };

          # ── Cross-agent plugins (temporal) ──
          # Discovered from ./plugins; built per target. Exposed as
          # "<name>-<target>" packages (e.g. temporal-claude, temporal-codex).
          targetLibs = {
            claude = claudeLib;
            antigravity = agyLib;
            codex = codexLib;
          };
          discoveredPlugins = build.discoverPlugins ./plugins;
          crossPlugins = lib.listToAttrs (
            lib.concatMap
              (
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
              )
              [
                "claude"
                "antigravity"
                "codex"
              ]
          );

          perSkillPackages = lib.listToAttrs (
            map (s: {
              name = s.name;
              value = s.drv;
            }) skills
          );

          # ── Web/app uploadable skills bundle ──
          # One folder per skill (folder = zip root for the Claude web/app
          # "Customize > Skills" upload format). avoid-ai-writing ships its
          # Node detector vendored into scripts/ so it runs in the sandbox.
          web-skills = build.buildWebBundle {
            inherit skills;
            avoidAiDetectSrc = ./packages/avoid-ai-detect;
          };

          # One zip per skill (zip root = exactly one folder + one SKILL.md), the layout
          # the Claude web "Customize > Skills" upload UI requires. Published as a
          # garnix artifact (garnix.yaml `artifacts:`), replacing the GitHub workflow.
          web-skills-zips = pkgs.runCommand "web-skills-zips" { nativeBuildInputs = [ pkgs.zip ]; } ''
            mkdir -p $out staging
            cp -rL ${web-skills}/. staging/
            chmod -R u+w staging
            cd staging
            for name in */; do
              name="''${name%/}"
              zip -q -r -X "$out/$name.zip" "$name"
            done
          '';
        in
        perSkillPackages
        // crossPlugins
        // {
          default = claude-plugin;
          inherit web-skills web-skills-zips;
          avoid-ai-detect = avoidAiDetect;
          inherit
            claude-plugin
            antigravity-plugin
            codex-plugin
            vibecad
            pxd
            figr
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
                      args = [
                        "-y"
                        "ctx"
                      ];
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
          eval-mcp = pkgs.runCommand "eval-mcp" { nativeBuildInputs = [ pkgs.jq ]; } ''
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

          frontmatter-tests =
            let
              failures = import ./lib/frontmatter-tests.nix { inherit lib; };
            in
            if failures == [ ] then
              pkgs.runCommand "frontmatter-tests" { } "touch $out"
            else
              throw "frontmatter tests failed: ${builtins.toJSON failures}";

          lint-tests =
            let
              failures = import ./lib/lint-tests.nix { inherit lib; };
            in
            if failures == [ ] then
              pkgs.runCommand "lint-tests" { } "touch $out"
            else
              throw "lint tests failed: ${builtins.toJSON failures}";

          skills-lint =
            let
              build = import ./lib/default.nix {
                inherit pkgs lib;
                claudeLib = import "${claude-nix}/lib" { inherit pkgs; };
              };
              skills = build.discoverSkills ./skills;
              # toJSON forces every parsed/linted field deeply.
              summary = builtins.toJSON (
                map (s: {
                  inherit (s) name;
                  inherit (s.meta) description;
                  tools = s.meta.allowed-tools;
                  agents = map (a: a.name) (s.meta.agentSpecs or [ ]);
                }) skills
              );
            in
            pkgs.runCommand "skills-lint"
              {
                inherit summary;
                passAsFile = [ "summary" ];
              }
              ''
                cp "$summaryPath" $out
              '';

          # Builds the detector package, whose checkPhase runs the vendored
          # engine tests (patterns.test.js + categories.test.js).
          avoid-ai-detect = pkgs.callPackage ./packages/avoid-ai-detect { };
        }
      );

      # ── Re-exported home-manager modules ──
      homeManagerModules = {
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
            claudePlugins = map (p: self.packages.${pkgs.system}."${p.name}-claude") (
              build.discoverPlugins ./plugins
            );
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
            # Fall through to Sonnet if the primary model is unavailable.
            # Additive + rebuild-safe (unlike a declared `model`/`effortLevel`,
            # which would re-assert on every rebuild and clobber an in-session
            # /model or /effort switch — those are intentionally left unset).
            programs.claude-nix.fallbackModel = [ "claude-sonnet-5" ];

            # Preferences that were only ever runtime state in
            # ~/.claude/settings.json, so a fresh config dir (a container, a
            # new machine, an extraAccounts wrapper) started without them.
            # Both are set-and-forget rather than per-session, so declaring
            # them costs nothing to the rebuild-clobber caveat above.
            #
            # Auto permission mode and the fullscreen renderer are deliberately
            # absent: claude-nix defaults to both as of the bump below.
            programs.claude-nix.voice = {
              enabled = true;
              mode = "tap";
            };
            # Accept the multi-agent usage warning up front; until it is set,
            # auto mode prompts before every workflow run.
            programs.claude-nix.workflows.skipUsageWarning = true;
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
            antigravityPlugins = map (p: self.packages.${pkgs.system}."${p.name}-antigravity") (
              build.discoverPlugins ./plugins
            );
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
            codexPlugins = map (p: self.packages.${pkgs.system}."${p.name}-codex") (
              build.discoverPlugins ./plugins
            );
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
