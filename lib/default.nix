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

  # ── Build using-agent-skills content (shared across targets) ──
  buildUsingAgentSkillsContent =
    skills:
    let
      usingAgentSkillsSkill = lib.findFirst (s: s.name == "using-agent-skills") null skills;
    in
    if usingAgentSkillsSkill != null then
      let
        meta = usingAgentSkillsSkill.meta;
        body = builtins.readFile (usingAgentSkillsSkill.dir + "/SKILL.md");
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
      usingAgentSkillsContent = buildUsingAgentSkillsContent skills;
      skillContentFile = pkgs.writeText "using-agent-skills-content" usingAgentSkillsContent;
    in
    pkgs.runCommand "${name}-hooks" { } ''
      mkdir -p $out/hooks
      for item in ${hooksDir}/*; do
        basename=$(basename "$item")
        case "$basename" in
          *.sh)
            substitute "$item" $out/hooks/"$basename" \
              --replace-fail @USING_AGENT_SKILLS@ ${skillContentFile}
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

  # ── Cross-agent plugins ──
  # Discovered from ./plugins/<name>/plugin.nix. Each is a function
  # `{ pkgs, lib, target, ... }: { name; description; skill ? null; hooks ? [ ]; packages ? [ ]; }`.
  # mkCrossAgentPlugin builds one for a single target using that target's
  # mkPlugin/mkSkill/mkHook.
  discoverPlugins =
    pluginsDir:
    let
      entries = builtins.readDir pluginsDir;
      dirNames = builtins.attrNames (lib.filterAttrs (_: type: type == "directory") entries);
      validNames = builtins.filter (
        name: builtins.pathExists (pluginsDir + "/${name}/plugin.nix")
      ) dirNames;
    in
    map (name: {
      inherit name;
      dir = pluginsDir + "/${name}";
      raw = import (pluginsDir + "/${name}/plugin.nix");
    }) validNames;

  # A plugin's declarative hooks → Claude settings.hooks fragment:
  #   { <Event> = [ { matcher; hooks = [ { type = "command"; command; } ]; } ]; }
  toClaudeHooks =
    hooks:
    lib.mapAttrs (
      _event: hs:
      map (h: {
        matcher = h.matcher or "";
        hooks = [
          {
            type = "command";
            command = h.command;
          }
        ];
      }) hs
    ) (lib.groupBy (h: h.event) hooks);

  # Merge Claude hook fragments from several plugins, concatenating the entry
  # list per event (plugin order preserved, e.g. code-notify before rtk).
  foldClaudeHooks =
    fragments:
    lib.foldl' (
      acc: frag: acc // lib.mapAttrs (event: entries: (acc.${event} or [ ]) ++ entries) frag
    ) { } fragments;

  # Build one cross-agent plugin for a single target. Claude's mkPlugin has no
  # `hooks` arg, so claude hooks are surfaced via passthru.claudeHooks for the
  # home-manager module to fold into programs.claude-nix.settings.hooks.
  mkCrossAgentPlugin =
    {
      def,
      target,
      targetLib,
      attributionFile ? null,
    }:
    let
      pluginName = "agent-skills-${def.name}";
      hooks = def.hooks or [ ];
      packages = def.packages or [ ];
      skillSpec = def.skill or null;

      # Written directly (not via targetLib.mkSkill for Claude) so the
      # allowed-tools frontmatter line is omitted when empty — an empty line
      # would otherwise restrict the skill to no tools.
      claudeSkill =
        body:
        pkgs.runCommand "skill-${def.name}-claude" { } ''
          mkdir -p $out/skills/${def.name}
          cat > $out/skills/${def.name}/SKILL.md <<'SKILLEOF'
---
name: ${def.name}
description: ${def.description}
---

${body}
SKILLEOF
        '';

      skillDrv =
        if skillSpec == null then
          null
        else if target == "claude" then
          claudeSkill skillSpec.body
        else
          targetLib.mkSkill {
            inherit (def) name description;
          } skillSpec.body;

      skills = lib.optional (skillDrv != null) skillDrv;

      attributionDrv = lib.optional (attributionFile != null) (
        pkgs.runCommand "${pluginName}-${target}-attribution" { } ''
          mkdir -p $out
          cp ${attributionFile} $out/ATTRIBUTION
        ''
      );

      targetHooks = map (
        h:
        targetLib.mkHook {
          inherit (h) event command;
          matcher = h.matcher or "";
          name = h.name or "${def.name}-${lib.toLower h.event}";
        }
      ) hooks;
    in
    if target == "claude" then
      let
        plugin = targetLib.mkPlugin {
          name = pluginName;
          inherit (def) description;
          inherit skills;
        };
      in
      pkgs.buildEnv {
        name = "${pluginName}-claude-complete";
        paths = [ plugin ] ++ packages ++ attributionDrv;
        passthru = {
          meta = {
            name = pluginName;
            inherit (def) description;
          };
          claudeHooks = toClaudeHooks hooks;
        };
      }
    else
      let
        plugin = targetLib.mkPlugin {
          name = pluginName;
          inherit (def) description;
          inherit skills;
          hooks = targetHooks;
        };
      in
      (pkgs.buildEnv {
        name = "${pluginName}-${target}-complete";
        paths = [ plugin ] ++ packages ++ attributionDrv;
        passthru.meta = {
          name = pluginName;
          inherit (def) description;
        };
      })
      // lib.optionalAttrs (target == "codex") { _codex = plugin._codex or { }; };

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
    discoverPlugins
    mkCrossAgentPlugin
    toClaudeHooks
    foldClaudeHooks
    ;
}
