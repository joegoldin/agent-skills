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
      paths = [ plugin ] ++ hooksDrv ++ attributionDrv;
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
      paths = [ plugin ] ++ attributionDrv;
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
      paths = [ plugin ] ++ attributionDrv;
    })
    // {
      _codex = plugin._codex or { };
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
    ;
}
