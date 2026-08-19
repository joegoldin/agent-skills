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
    pi-nix = {
      # github: (not git+ssh) for the same reason codex-nix uses it — garnix
      # injects its app token for github: refs but has no SSH key.
      url = "github:joegoldin/pi-nix";
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
      pi-nix,
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
          piLib = import "${pi-nix}/lib" { inherit pkgs lib; };
          build = import ./lib/default.nix {
            inherit
              pkgs
              lib
              claudeLib
              agyLib
              codexLib
              piLib
              ;
          };

          skills = build.discoverSkills ./skills;

          promptLib = import ./lib/prompt.nix { inherit lib; };
          sharedPromptText = promptLib.mkPrompt { layers = [ ./prompt/shared ]; };
          piPromptText = promptLib.mkPrompt {
            layers = [
              ./prompt/core
              ./prompt/shared
              ./prompt/pi
            ];
          };

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

          # ── pi package ──
          # Skills ride in as the same per-skill derivations the Claude
          # plugin ships, which is what makes the ~/.agents/skills double
          # load free (design §11, assumption A3).
          pi-plugin = build.buildPiPlugin {
            name = "agent-skills";
            description = "Agent skills for pi";
            inherit skills;
            extensionsDir = ./extensions;
            attributionFile = ./ATTRIBUTION.md;
          };

          # ── Cross-agent plugins (temporal) ──
          # Discovered from ./plugins; built per target. Exposed as
          # "<name>-<target>" packages (e.g. temporal-claude, temporal-codex).
          targetLibs = {
            claude = claudeLib;
            antigravity = agyLib;
            codex = codexLib;
            pi = piLib;
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
                "pi"
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
          prompt-shared = pkgs.writeText "agent-skills-shared-prompt.md" sharedPromptText;
          prompt-pi = pkgs.writeText "agent-skills-pi-SYSTEM.md" piPromptText;
          avoid-ai-detect = avoidAiDetect;
          inherit
            claude-plugin
            antigravity-plugin
            codex-plugin
            pi-plugin
            vibecad
            pxd
            figr
            ;
        }
      );

      checks = forAllSystems (
        { pkgs, system, ... }:
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
          piJson = pkgs.writeText "pi-mcp.json" (builtins.toJSON (mcp.mcpNativeFor "pi" servers));
        in
        {
          mcp-standalone-tests = import ./tests/mcp-standalone-test.nix { inherit pkgs; };
          eval-mcp = pkgs.runCommand "eval-mcp" { nativeBuildInputs = [ pkgs.jq ]; } ''
            # disabled servers are omitted from every target
            jq -e 'has("off") | not' ${claudeJson} >/dev/null
            jq -e 'has("off") | not' ${agyJson} >/dev/null
            jq -e 'has("off") | not' ${codexJson} >/dev/null

            # stdio is identical across all four targets
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

            # disabled servers are omitted from the pi target too
            jq -e 'has("off") | not' ${piJson} >/dev/null
            jq -e '.ctx.command == "npx" and (.ctx.args == ["-y","ctx"])' ${piJson} >/dev/null

            # pi remote -> pi-mcp-adapter shape: url + headers + auth/bearerTokenEnv
            jq -e '.remote.url == "https://x/mcp" and .remote.headers.Authorization == "Bearer Y"' ${piJson} >/dev/null
            jq -e '.remote.auth == "bearer" and .remote.bearerTokenEnv == "TOK"' ${piJson} >/dev/null

            # pi must not inherit any other target's remote spelling
            jq -e '.remote | (has("type") | not) and (has("serverUrl") | not) and (has("bearer_token_env_var") | not) and (has("http_headers") | not)' ${piJson} >/dev/null

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

          # Every shipped skill must load into pi without a diagnostic. The
          # agent-skills rules are strictly stricter than pi's, so this
          # should never fire — it fires only if that stops being true.
          pi-frontmatter =
            let
              lintLib = import ./lib/lint.nix { inherit lib; };
              build = import ./lib/default.nix {
                inherit pkgs lib;
                claudeLib = import "${claude-nix}/lib" { inherit pkgs; };
              };
              skills = build.discoverSkills ./skills;
              offenders = lib.concatMap (
                s:
                map (w: "${s.name}: ${w}") (
                  lintLib.piSkillWarnings {
                    dirName = s.name;
                    inherit (s) parsed;
                  }
                )
              ) skills;
            in
            if offenders == [ ] then
              pkgs.runCommand "pi-frontmatter" { } "touch $out"
            else
              throw "pi frontmatter violations: ${builtins.toJSON offenders}";

          # ── A3 gate ──
          # pi de-duplicates skills by canonicalised real path BEFORE it
          # de-duplicates by name (skills.ts loadSkills: realPathSet is
          # consulted first, and a hit is skipped silently; a name hit that
          # is not a real-path hit raises a startup collision warning).
          # ~/.agents/skills and the pi package therefore cost nothing only
          # while both bottom out at the same skill-<name> derivation.
          # A cp -r in buildPiPlugin would still "work" and would still
          # de-duplicate — it would just print one warning per skill on every
          # session start. This check is the only thing that notices.
          pi-skill-realpath-identity =
            let
              piTree = self.packages.${system}.pi-plugin;
              claudeTree = self.packages.${system}.claude-plugin;
              build = import ./lib/default.nix {
                inherit pkgs lib;
                claudeLib = import "${claude-nix}/lib" { inherit pkgs; };
              };
              skills = build.discoverSkills ./skills;
            in
            pkgs.runCommand "pi-skill-realpath-identity"
              {
                inherit piTree claudeTree;
                names = lib.concatStringsSep " " (map (s: s.name) skills);
                sources = lib.concatStringsSep " " (map (s: "${s.name}=${s.drv}") skills);
              }
              ''
                fail=0
                for pair in $sources; do
                  n="''${pair%%=*}"
                  drv="''${pair#*=}"
                  want="$(realpath "$drv/skills/$n/SKILL.md")"
                  got_pi="$(realpath "$piTree/skills/$n/SKILL.md")"
                  got_cc="$(realpath "$claudeTree/skills/$n/SKILL.md")"
                  if [ "$got_pi" != "$want" ]; then
                    echo "pi package copies '$n' instead of linking it:"
                    echo "  want $want"
                    echo "  got  $got_pi"
                    fail=1
                  fi
                  if [ "$got_pi" != "$got_cc" ]; then
                    echo "realpath drift between pi and claude trees for '$n':"
                    echo "  pi     $got_pi"
                    echo "  claude $got_cc"
                    fail=1
                  fi
                done
                [ "$fail" = 0 ] || exit 1
                touch $out
              '';

          # The pi manifest must be present and well-formed; pi's
          # readPiManifest returns null (and silently falls back to
          # convention directories) for anything it cannot parse.
          pi-package-manifest =
            let
              piTree = self.packages.${system}.pi-plugin;
            in
            pkgs.runCommand "pi-package-manifest" { nativeBuildInputs = [ pkgs.jq ]; } ''
              jq -e '.pi.skills == ["./skills"]' ${piTree}/package.json >/dev/null
              jq -e '.keywords | index("pi-package")' ${piTree}/package.json >/dev/null
              jq -e '.name == "agent-skills"' ${piTree}/package.json >/dev/null
              touch $out
            '';

          # Command-style skills (disable-model-invocation) get a pi prompt
          # template so they are reachable as /name, not just /skill:name.
          # Model-invocable skills must NOT get one.
          pi-prompt-templates =
            let
              piTree = self.packages.${system}.pi-plugin;
            in
            pkgs.runCommand "pi-prompt-templates" { nativeBuildInputs = [ pkgs.jq ]; } ''
              jq -e '.pi.prompts == ["./prompts"]' ${piTree}/package.json >/dev/null

              test -f ${piTree}/prompts/format-nix.md
              test -f ${piTree}/prompts/nix-dotfiles.md

              # description and argument-hint carried over from frontmatter
              grep -qxF 'description: Format all Nix files in the project with nixfmt' \
                ${piTree}/prompts/format-nix.md
              grep -qxF 'argument-hint: "[directory]"' ${piTree}/prompts/format-nix.md
              grep -qxF 'argument-hint: "<what to change>"' ${piTree}/prompts/nix-dotfiles.md

              # body carried over verbatim, including pi-native $ARGUMENTS
              grep -qF '$ARGUMENTS' ${piTree}/prompts/format-nix.md

              # Claude-only frontmatter must not leak into the template
              grep -q '^disable-model-invocation:' ${piTree}/prompts/format-nix.md && exit 1
              grep -q '^allowed-tools:' ${piTree}/prompts/format-nix.md && exit 1

              # model-invocable skills get no template
              test ! -e ${piTree}/prompts/using-agent-skills.md
              test ! -e ${piTree}/prompts/writing-skills.md

              # ...but they are still shipped as skills
              test -f ${piTree}/skills/format-nix/SKILL.md
              test -f ${piTree}/skills/using-agent-skills/SKILL.md

              touch $out
            '';

          pi-extensions =
            let
              piTree = self.packages.${system}.pi-plugin;
            in
            pkgs.runCommand "pi-extensions" { nativeBuildInputs = [ pkgs.jq ]; } ''
              jq -e '.pi.extensions == ["./extensions"]' ${piTree}/package.json >/dev/null
              test -f ${piTree}/extensions/agent-skills-session-start.ts

              # The build-time placeholder must be gone and replaced by a
              # store path that exists and holds the real skill.
              ! grep -q '@USING_AGENT_SKILLS@' ${piTree}/extensions/agent-skills-session-start.ts
              p=$(grep -o '/nix/store/[^"]*using-agent-skills-content' \
                    ${piTree}/extensions/agent-skills-session-start.ts | head -1)
              test -n "$p"
              grep -q 'name: using-agent-skills' "$p"

              # Only type imports — a value import from @earendil-works
              # would fail to resolve from a /nix/store path.
              ! grep -E '^import[^t]' ${piTree}/extensions/agent-skills-session-start.ts \
                | grep -q '@earendil-works'

              touch $out
            '';

          temporal-pi =
            let
              tree = self.packages.${system}.temporal-pi;
            in
            pkgs.runCommand "temporal-pi" { nativeBuildInputs = [ pkgs.jq ]; } ''
              jq -e '.name == "agent-skills-temporal"' ${tree}/package.json >/dev/null
              jq -e '.pi.extensions == ["./extensions"]' ${tree}/package.json >/dev/null
              test -f ${tree}/extensions/temporal.ts
              test -f ${tree}/skills/temporal/SKILL.md

              # the pi build must not drag in the Python the hook targets need
              test ! -e ${tree}/bin/python3

              # behaviour parity with temporal.py: the three env knobs and
              # both stamp forms must be present
              grep -qF 'TEMPORAL_INTERVAL' ${tree}/extensions/temporal.ts
              grep -qF 'TEMPORAL_TTL_DAYS' ${tree}/extensions/temporal.ts
              grep -qF 'TEMPORAL_STATE_DIR' ${tree}/extensions/temporal.ts
              grep -qF 'post-compaction time check' ${tree}/extensions/temporal.ts
              grep -qF 'unix_ms=' ${tree}/extensions/temporal.ts

              touch $out
            '';

          # Design §14: every skill must build for all four targets. This
          # catches the failure mode where one target's mkSkill silently
          # drops a skill whose frontmatter it cannot model.
          skills-all-four-targets =
            let
              build = import ./lib/default.nix {
                inherit pkgs lib;
                claudeLib = import "${claude-nix}/lib" { inherit pkgs; };
              };
              skills = build.discoverSkills ./skills;
            in
            pkgs.runCommand "skills-all-four-targets"
              {
                trees = lib.concatStringsSep " " [
                  "claude=${self.packages.${system}.claude-plugin}"
                  "antigravity=${self.packages.${system}.antigravity-plugin}"
                  "codex=${self.packages.${system}.codex-plugin}"
                  "pi=${self.packages.${system}.pi-plugin}"
                ];
                names = lib.concatStringsSep " " (map (s: s.name) skills);
                expected = toString (builtins.length skills);
              }
              ''
                fail=0
                for pair in $trees; do
                  t="''${pair%%=*}"
                  tree="''${pair#*=}"

                  # every discovered skill is present, with a non-empty SKILL.md
                  for n in $names; do
                    f="$tree/skills/$n/SKILL.md"
                    if [ ! -f "$f" ]; then
                      echo "MISSING: $t is missing skill '$n'"
                      fail=1
                    elif [ ! -s "$f" ]; then
                      echo "EMPTY: $t ships an empty SKILL.md for '$n'"
                      fail=1
                    fi
                  done

                  # and no target ships extras or drops any
                  got=$(ls -1 "$tree/skills" | wc -l)
                  if [ "$got" != "$expected" ]; then
                    echo "COUNT: $t ships $got skills, expected $expected"
                    fail=1
                  fi
                done
                [ "$fail" = 0 ] || exit 1
                echo "all $expected skills present in all four targets"
                touch $out
              '';

          prompt-tests =
            let
              failures = import ./lib/prompt-tests.nix { inherit lib; };
            in
            if failures == [ ] then
              pkgs.runCommand "prompt-tests" { } "touch $out"
            else
              throw "prompt tests failed: ${builtins.toJSON failures}";

          prompt-lint-tests =
            let
              failures = import ./lib/prompt-lint-tests.nix { inherit lib; };
            in
            if failures == [ ] then
              pkgs.runCommand "prompt-lint-tests" { } "touch $out"
            else
              throw "prompt lint tests failed: ${builtins.toJSON failures}";

          # The governing rule from the design's §12, as a build gate: prompt
          # fragments state policy, never inventory. Skill names come from the
          # real tree, so adding a skill immediately widens the ban.
          prompt-inventory =
            let
              promptLib = import ./lib/prompt.nix { inherit lib; };
              promptLint = import ./lib/prompt-lint.nix { inherit lib; };
              build = import ./lib/default.nix {
                inherit pkgs lib;
                claudeLib = import "${claude-nix}/lib" { inherit pkgs; };
              };
              skillNames =
                map (s: s.name) (build.discoverSkills ./skills)
                ++ map (p: p.name) (build.discoverPlugins ./plugins);
              layers = {
                core = ./prompt/core;
                shared = ./prompt/shared;
                pi = ./prompt/pi;
              };
              checkFragment =
                layer: dir: name:
                let
                  prefix = "prompt/${layer}/${name}";
                  nameFailure = lib.optional (
                    !promptLib.validateFragmentName name
                  ) "${prefix}: file name must match NN-kebab-case.md";
                  termFailures = map (v: "${prefix}: ${v.rule}: ${v.term}") (
                    promptLint.lint {
                      inherit skillNames;
                      text = promptLib.readFragment dir name;
                    }
                  );
                in
                nameFailure ++ termFailures;
              failures = lib.concatLists (
                lib.mapAttrsToList (
                  layer: dir: lib.concatMap (checkFragment layer dir) (promptLib.fragmentNames dir)
                ) layers
              );
            in
            if failures == [ ] then
              pkgs.runCommand "prompt-inventory" { } "touch $out"
            else
              throw "prompt fragments state inventory, not policy:\n  ${lib.concatStringsSep "\n  " failures}";

          # core/ replaces pi's default prompt and must never be appended to
          # the agents that ship equivalent guidance built in.
          prompt-layering =
            let
              promptLib = import ./lib/prompt.nix { inherit lib; };
              core = promptLib.mkPrompt { layers = [ ./prompt/core ]; };
              shared = promptLib.mkPrompt { layers = [ ./prompt/shared ]; };
              piPrompt = promptLib.mkPrompt {
                layers = [
                  ./prompt/core
                  ./prompt/shared
                  ./prompt/pi
                ];
              };
              failures =
                lib.optional (core == "") "core layer is empty"
                ++ lib.optional (shared == "") "shared layer is empty"
                ++ lib.optional (
                  !(lib.hasInfix (lib.removeSuffix "\n" shared) piPrompt)
                ) "pi prompt does not contain the shared layer verbatim"
                ++ lib.optional (lib.hasInfix (lib.removeSuffix "\n" core) shared) "shared layer contains core content; core is pi-only";
            in
            if failures == [ ] then
              pkgs.runCommand "prompt-layering" { } "touch $out"
            else
              throw "prompt layering: ${lib.concatStringsSep "; " failures}";

          eval-prompt-fanout = import ./tests/prompt-fanout-test.nix { inherit pkgs; };

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
          piLib = import "${pi-nix}/lib" {
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
