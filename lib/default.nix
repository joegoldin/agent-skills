{
  pkgs,
  lib,
  claudeLib,
  agyLib ? null,
  codexLib ? null,
}:
let
  # Import a skill.nix — handles both plain attrsets and functions.
  # For non-Claude targets, pass claudeLib as a stub so skill.nix files
  # that reference claudeLib builders (mkCommand, mkAgent) don't break.
  evalSkillNix =
    raw:
    if builtins.isFunction raw then
      raw {
        inherit pkgs lib claudeLib;
      }
    else
      raw;

  buildSkillDrv =
    name: meta: skillDir:
    let
      skillBody = builtins.readFile (skillDir + "/SKILL.md");
      frontmatterFields = [
        "name: ${meta.name}"
        "description: ${meta.description}"
      ]
      ++
        lib.optional ((meta.allowed-tools or [ ]) != [ ])
          "allowed-tools: ${toString (meta.allowed-tools or [ ])}";
      frontmatter = "---\n" + lib.concatStringsSep "\n" frontmatterFields + "\n---";
      skillMdContent = frontmatter + "\n\n" + skillBody;
      skillMd = pkgs.writeText "skill-${name}-md" skillMdContent;
    in
    pkgs.runCommand "skill-${name}" { } ''
      mkdir -p $out/skills/${name}
      cp ${skillMd} $out/skills/${name}/SKILL.md

      for item in ${skillDir}/*; do
        basename=$(basename "$item")
        case "$basename" in
          skill.nix|SKILL.md) ;;
          *) cp -r "$item" $out/skills/${name}/ ;;
        esac
      done
    '';

  discoverSkills =
    skillsDir:
    let
      entries = builtins.readDir skillsDir;
      dirNames = builtins.attrNames (lib.filterAttrs (_: type: type == "directory") entries);
      validNames = builtins.filter (
        name: builtins.pathExists (skillsDir + "/${name}/skill.nix")
      ) dirNames;
    in
    map (name: rec {
      inherit name;
      dir = skillsDir + "/${name}";
      meta = evalSkillNix (import (dir + "/skill.nix"));
      drv = buildSkillDrv name meta dir;
    }) validNames;

  # ── Build using-superpowers content (shared across targets) ──
  buildUsingSuperpowersContent =
    skills:
    let
      usingSuperpowersSkill = lib.findFirst (s: s.name == "using-superpowers") null skills;
    in
    if usingSuperpowersSkill != null then
      let
        meta = usingSuperpowersSkill.meta;
        body = builtins.readFile (usingSuperpowersSkill.dir + "/SKILL.md");
        fields = [
          "name: ${meta.name}"
          "description: ${meta.description}"
        ]
        ++
          lib.optional ((meta.allowed-tools or [ ]) != [ ])
            "allowed-tools: ${toString (meta.allowed-tools or [ ])}";
      in
      "---\n" + lib.concatStringsSep "\n" fields + "\n---\n\n" + body
    else
      "";

  # ── Build session-start hooks derivation (shared across all targets) ──
  buildSessionStartHooks =
    name: skills: hooksDir:
    let
      usingSuperpowersContent = buildUsingSuperpowersContent skills;
      skillContentFile = pkgs.writeText "using-superpowers-content" usingSuperpowersContent;
    in
    pkgs.runCommand "${name}-hooks" { } ''
      mkdir -p $out/hooks
      for item in ${hooksDir}/*; do
        basename=$(basename "$item")
        case "$basename" in
          *.sh)
            substitute "$item" $out/hooks/"$basename" \
              --replace-fail @USING_SUPERPOWERS_SKILL@ ${skillContentFile}
            chmod +x $out/hooks/"$basename"
            ;;
          *) cp "$item" $out/hooks/"$basename" ;;
        esac
      done
    '';

  buildTargetSessionStartHooks =
    {
      mkHook,
      name,
      skills,
      hooksDir,
    }:
    let
      hooksDrv = buildSessionStartHooks name skills hooksDir;
    in
    [
      (mkHook {
        event = "SessionStart";
        matcher = "startup|resume|clear|compact";
        name = "agent-skills-session-start";
        command = "${hooksDrv}/hooks/session-start.sh";
      })
    ];

  buildAntigravityHooks =
    {
      name,
      skills,
      hooksDir,
    }:
    assert agyLib != null;
    buildTargetSessionStartHooks {
      inherit name skills hooksDir;
      mkHook = agyLib.mkHook;
    };

  buildCodexHooks =
    {
      name,
      skills,
      hooksDir,
    }:
    assert codexLib != null;
    buildTargetSessionStartHooks {
      inherit name skills hooksDir;
      mkHook = codexLib.mkHook;
    };

  # ── Claude plugin ──
  buildPlugin =
    {
      name,
      description,
      skills,
      hooksDir ? null,
      attributionFile ? null,
      extraPackages ? [ ],
    }:
    let
      allCommands = lib.concatMap (s: s.meta.commands or [ ]) skills;
      allAgents = lib.concatMap (s: s.meta.agents or [ ]) skills;
      allMcpServers = lib.foldl' (acc: s: acc // (s.meta.mcpServers or { })) { } skills;
      allLspServers = lib.foldl' (acc: s: acc // (s.meta.lspServers or { })) { } skills;

      plugin = claudeLib.mkPlugin {
        inherit name description;
        skills = map (s: s.drv) skills;
        commands = allCommands;
        agents = allAgents;
        mcpServers = allMcpServers;
        lspServers = allLspServers;
      };

      hooksDrv = lib.optional (hooksDir != null) (buildSessionStartHooks name skills hooksDir);

      attributionDrv = lib.optional (attributionFile != null) (
        pkgs.runCommand "${name}-attribution" { } ''
          mkdir -p $out
          cp ${attributionFile} $out/ATTRIBUTION
        ''
      );
    in
    pkgs.buildEnv {
      name = "${name}-complete";
      paths = [ plugin ] ++ hooksDrv ++ attributionDrv ++ extraPackages;
    };

  # ── Build a skill using a target's mkSkill ──
  buildSkillForTarget =
    targetMkSkill: skill:
    let
      meta = skill.meta;
      skillBody = builtins.readFile (skill.dir + "/SKILL.md");
      extraFiles =
        let
          entries = builtins.readDir skill.dir;
          extras = lib.filterAttrs (name: _: name != "skill.nix" && name != "SKILL.md") entries;
        in
        map (name: skill.dir + "/${name}") (builtins.attrNames extras);
    in
    targetMkSkill {
      inherit (meta) name description;
      allowed-tools = meta.allowed-tools or [ ];
      inherit extraFiles;
    } skillBody;

  # ── Antigravity plugin ──
  buildAntigravityPlugin =
    {
      name,
      description,
      skills,
      hooks ? [ ],
      mcpServers ? [ ],
      hooksDir ? null,
      attributionFile ? null,
      extraPackages ? [ ],
    }:
    assert agyLib != null;
    let
      agySkills = map (buildSkillForTarget agyLib.mkSkill) skills;

      sessionStartHooks =
        if hooksDir != null then buildAntigravityHooks { inherit name skills hooksDir; } else [ ];

      plugin = agyLib.mkPlugin {
        inherit name description mcpServers;
        skills = agySkills;
        hooks = hooks ++ sessionStartHooks;
      };

      attributionDrv = lib.optional (attributionFile != null) (
        pkgs.runCommand "${name}-antigravity-attribution" { } ''
          mkdir -p $out
          cp ${attributionFile} $out/ATTRIBUTION
        ''
      );
    in
    pkgs.buildEnv {
      name = "${name}-antigravity-complete";
      paths = [ plugin ] ++ attributionDrv ++ extraPackages;
      passthru.meta = { inherit name description; };
    };

  # ── Codex plugin ──
  buildCodexPlugin =
    {
      name,
      description,
      skills,
      hooks ? [ ],
      hooksDir ? null,
      attributionFile ? null,
      extraPackages ? [ ],
    }:
    assert codexLib != null;
    let
      codexSkills = map (buildSkillForTarget codexLib.mkSkill) skills;

      allMcpServers = lib.foldl' (acc: s: acc // (s.meta.mcpServers or { })) { } skills;

      sessionStartHooks =
        if hooksDir != null then buildCodexHooks { inherit name skills hooksDir; } else [ ];

      plugin = codexLib.mkPlugin {
        inherit name;
        description = description;
        skills = codexSkills;
        hooks = hooks ++ sessionStartHooks;
        mcpServers = allMcpServers;
      };

      attributionDrv = lib.optional (attributionFile != null) (
        pkgs.runCommand "${name}-codex-attribution" { } ''
          mkdir -p $out
          cp ${attributionFile} $out/ATTRIBUTION
        ''
      );
    in
    (pkgs.buildEnv {
      name = "${name}-codex-complete";
      paths = [ plugin ] ++ attributionDrv ++ extraPackages;
    })
    // {
      _codex = plugin._codex or { };
    };
  # ── RTK plugin (per-target) ──
  # For Claude: PreToolUse hook + awareness skill body.
  # For Codex/Antigravity: awareness markdown only (upstream chose markdown-only).
  buildRtkPlugin =
    {
      target,                        # "claude" | "codex" | "antigravity"
      rtkPkg,                        # pkgs.rtk
      hooksDir,                      # path: .../plugins/rtk/hooks
      attributionFile ? null,
    }:
    let
      # Awareness markdown lives at hooks/<target>/(rtk-awareness.md|rules.md)
      awarenessFile =
        if target == "claude" then "${hooksDir}/claude/rtk-awareness.md"
        else if target == "codex" then "${hooksDir}/codex/rtk-awareness.md"
        else "${hooksDir}/antigravity/rules.md";
      awarenessBody = builtins.readFile awarenessFile;

      skillBody = ''
        # rtk — Rust Token Killer

        ${awarenessBody}

        ## When to use this skill

        Use when the user asks about RTK token savings, `rtk gain` analytics,
        debugging command rewriting, or wants to understand why a Bash call
        appears as `rtk <cmd>` instead of the raw command.

        Raw shell commands are rewritten automatically (Claude) or by your
        convention (Codex/Antigravity). Never wrap `rtk` calls in another `rtk`.
      '';

      desc = "Use when the user asks about RTK, `rtk gain`, command rewriting, or token-saving CLI proxy behavior.";

    in
    if target == "claude" then
      let
        # Build the rtk-rewrite.sh hook with rtk + jq on PATH.
        rtkHookWrapper = pkgs.writeShellScript "rtk-rewrite" ''
          export PATH=${lib.makeBinPath [ rtkPkg pkgs.jq ]}:$PATH
          exec ${pkgs.bash}/bin/bash ${hooksDir}/claude/rtk-rewrite.sh "$@"
        '';

        # Build a SKILL.md derivation directly without using buildSkillDrv,
        # because buildSkillDrv calls builtins.readFile at eval time and can't
        # consume a derivation output. We construct the same $out/skills/rtk/
        # layout that claudeLib.mkPlugin expects.
        skill = pkgs.runCommand "skill-rtk-claude" { } ''
          mkdir -p $out/skills/rtk
          cat > $out/skills/rtk/SKILL.md <<'SKILLEOF'
---
name: rtk
description: ${desc}
---

${skillBody}
SKILLEOF
        '';

        plugin = claudeLib.mkPlugin {
          name = "agent-skills-rtk";
          description = "RTK command rewriting + skill (Claude)";
          skills = [ skill ];
          commands = [ ];
          agents = [ ];
          mcpServers = { };
          lspServers = { };
        };

        attributionDrv = lib.optional (attributionFile != null) (
          pkgs.runCommand "rtk-claude-attribution" { } ''
            mkdir -p $out
            cp ${attributionFile} $out/ATTRIBUTION
          ''
        );
      in
      pkgs.buildEnv {
        name = "agent-skills-rtk-claude-complete";
        paths = [ plugin rtkPkg ] ++ attributionDrv;
        passthru._claudeRtkHook = rtkHookWrapper;
      }
    else if target == "codex" then
      let
        codexSkill = codexLib.mkSkill {
          name = "rtk";
          description = desc;
        } skillBody;
        plugin = codexLib.mkPlugin {
          name = "agent-skills-rtk";
          description = "RTK awareness (Codex)";
          skills = [ codexSkill ];
        };
        attributionDrv = lib.optional (attributionFile != null) (
          pkgs.runCommand "rtk-codex-attribution" { } ''
            mkdir -p $out
            cp ${attributionFile} $out/ATTRIBUTION
          ''
        );
      in
      (pkgs.buildEnv {
        name = "agent-skills-rtk-codex-complete";
        paths = [ plugin rtkPkg ] ++ attributionDrv;
      })
      // { _codex = plugin._codex or { }; }
    else  # antigravity
      let
        agySkill = agyLib.mkSkill {
          name = "rtk";
          description = desc;
        } skillBody;
        plugin = agyLib.mkPlugin {
          name = "agent-skills-rtk";
          description = "RTK awareness (Antigravity)";
          skills = [ agySkill ];
        };
        attributionDrv = lib.optional (attributionFile != null) (
          pkgs.runCommand "rtk-agy-attribution" { } ''
            mkdir -p $out
            cp ${attributionFile} $out/ATTRIBUTION
          ''
        );
      in
      pkgs.buildEnv {
        name = "agent-skills-rtk-antigravity-complete";
        paths = [ plugin rtkPkg ] ++ attributionDrv;
        passthru.meta = { name = "agent-skills-rtk"; description = "RTK awareness (Antigravity)"; };
      };

  # ── Temporal plugin (per-target) ──
  # Ships a Python time-injection hook. State dir is per-CLI via $TEMPORAL_STATE_DIR.
  buildTemporalPlugin =
    {
      target,            # "claude" | "codex" | "antigravity"
      scriptDir,         # path: .../plugins/temporal
      stateDir,          # absolute path: where this CLI keeps its state, e.g. "/home/joe/.claude/.temporal"
      attributionFile ? null,
    }:
    let
      python3 = pkgs.python3;
      # stateDir may contain $HOME — we leave it unquoted in the export so the
      # shell expands it at runtime, not nix-eval time.
      temporalScript = pkgs.writeShellScript "temporal-${target}" ''
        export TEMPORAL_STATE_DIR="${stateDir}"
        exec ${python3}/bin/python3 ${scriptDir}/temporal.py "$@"
      '';

      attributionDrv = lib.optional (attributionFile != null) (
        pkgs.runCommand "temporal-${target}-attribution" { } ''
          mkdir -p $out
          cp ${attributionFile} $out/ATTRIBUTION
        ''
      );

      emptySkill = ''
        # temporal — time awareness hook

        Background-only — this plugin contributes a hook, not skill content
        you invoke directly. The hook injects a throttled `[⏱ time]` block at
        UserPromptSubmit and after compaction so the agent knows what time
        it is.

        Configure via env vars:
        - `TEMPORAL_INTERVAL` (seconds, default 300): min interval between injects.
        - `TEMPORAL_TTL_DAYS` (default 7): days before stale session state is swept.
      '';

    in
    if target == "claude" then
      let
        # Same approach as buildRtkPlugin: build the skill derivation directly
        # to avoid buildSkillDrv's eval-time readFile constraint.
        desc = "Use when the user asks about time/date hooks, why timestamps appear in context, or wants to tune the [⏱] injection.";
        skill = pkgs.runCommand "skill-temporal-claude" { } ''
          mkdir -p $out/skills/temporal
          cat > $out/skills/temporal/SKILL.md <<'SKILLEOF'
---
name: temporal
description: ${desc}
---

${emptySkill}
SKILLEOF
        '';
        plugin = claudeLib.mkPlugin {
          name = "agent-skills-temporal";
          description = "Throttled time injection (Claude)";
          skills = [ skill ];
          commands = [ ];
          agents = [ ];
          mcpServers = { };
          lspServers = { };
        };
      in
      pkgs.buildEnv {
        name = "agent-skills-temporal-claude-complete";
        paths = [ plugin python3 ] ++ attributionDrv;
        passthru._temporalScript = temporalScript;
      }
    else if target == "codex" then
      let
        codexSkill = codexLib.mkSkill {
          name = "temporal";
          description = "Use when the user asks about time/date hooks or `[⏱]` annotations.";
        } emptySkill;
        plugin = codexLib.mkPlugin {
          name = "agent-skills-temporal";
          description = "Throttled time injection (Codex)";
          skills = [ codexSkill ];
          hooks = [
            (codexLib.mkHook {
              event = "UserPromptSubmit";
              name = "temporal-user-prompt-submit";
              command = "${temporalScript}";
            })
            (codexLib.mkHook {
              event = "SessionStart";
              name = "temporal-session-start";
              command = "${temporalScript}";
            })
          ];
        };
      in
      (pkgs.buildEnv {
        name = "agent-skills-temporal-codex-complete";
        paths = [ plugin python3 ] ++ attributionDrv;
      })
      // { _codex = plugin._codex or { }; }
    else  # antigravity
      let
        agySkill = agyLib.mkSkill {
          name = "temporal";
          description = "Use when the user asks about time/date hooks or `[⏱]` annotations.";
        } emptySkill;
        plugin = agyLib.mkPlugin {
          name = "agent-skills-temporal";
          description = "Throttled time injection (Antigravity)";
          skills = [ agySkill ];
          hooks = [
            (agyLib.mkHook {
              event = "SessionStart";
              name = "temporal-session-start";
              command = "${temporalScript}";
            })
            # Best-effort UserPromptSubmit: if Antigravity ignores unknown events,
            # this silently no-ops and we fall back to SessionStart-only behaviour.
            (agyLib.mkHook {
              event = "UserPromptSubmit";
              name = "temporal-user-prompt-submit";
              command = "${temporalScript}";
            })
          ];
        };
      in
      pkgs.buildEnv {
        name = "agent-skills-temporal-antigravity-complete";
        paths = [ plugin python3 ] ++ attributionDrv;
        passthru.meta = {
          name = "agent-skills-temporal";
          description = "Throttled time injection (Antigravity)";
        };
      };

in
{
  inherit
    discoverSkills
    buildPlugin
    evalSkillNix
    buildSkillDrv
    buildSkillForTarget
    buildAntigravityPlugin
    buildCodexPlugin
    buildAntigravityHooks
    buildCodexHooks
    buildSessionStartHooks
    buildRtkPlugin
    buildTemporalPlugin
    ;
}
