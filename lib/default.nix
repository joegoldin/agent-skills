{
  pkgs,
  lib,
  claudeLib,
  geminiLib ? null,
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

  # Build a single skill derivation: SKILL.md with frontmatter + extra files
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

      # Copy extra files (everything except skill.nix and SKILL.md)
      for item in ${skillDir}/*; do
        basename=$(basename "$item")
        case "$basename" in
          skill.nix|SKILL.md) ;;
          *) cp -r "$item" $out/skills/${name}/ ;;
        esac
      done
    '';

  # Discover all skills in a directory
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

  # ── Build hooks derivation for Claude (uses ${CLAUDE_PLUGIN_ROOT}) ──
  buildClaudeHooks =
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

  # ── Claude plugin (backward compatible) ──
  buildPlugin =
    {
      name,
      description,
      skills,
      hooksDir ? null,
      attributionFile ? null,
    }:
    let
      # Aggregate optional components from all skills
      allCommands = lib.concatMap (s: s.meta.commands or [ ]) skills;
      allAgents = lib.concatMap (s: s.meta.agents or [ ]) skills;
      allMcpServers = lib.foldl' (acc: s: acc // (s.meta.mcpServers or { })) { } skills;
      allLspServers = lib.foldl' (acc: s: acc // (s.meta.lspServers or { })) { } skills;

      # Build the plugin
      plugin = claudeLib.mkPlugin {
        inherit name description;
        skills = map (s: s.drv) skills;
        commands = allCommands;
        agents = allAgents;
        mcpServers = allMcpServers;
        lspServers = allLspServers;
      };

      # Hooks derivation
      hooksDrv = lib.optional (hooksDir != null) (buildClaudeHooks name skills hooksDir);

      # Attribution derivation
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

  # ── Gemini plugin ──
  buildGeminiPlugin =
    {
      name,
      description,
      skills,
      hooks ? [ ],
      attributionFile ? null,
    }:
    assert geminiLib != null;
    let
      # Build each skill using geminiLib.mkSkill
      geminiSkills = map (buildSkillForTarget geminiLib.mkSkill) skills;

      # Build the plugin
      plugin = geminiLib.mkPlugin {
        inherit name;
        description = description;
        skills = geminiSkills;
        inherit hooks;
      };

      # Attribution derivation
      attributionDrv = lib.optional (attributionFile != null) (
        pkgs.runCommand "${name}-gemini-attribution" { } ''
          mkdir -p $out
          cp ${attributionFile} $out/ATTRIBUTION
        ''
      );
    in
    pkgs.buildEnv {
      name = "${name}-gemini-complete";
      paths = [ plugin ] ++ attributionDrv;
    };

  # ── Codex plugin ──
  buildCodexPlugin =
    {
      name,
      description,
      skills,
      hooks ? [ ],
      attributionFile ? null,
    }:
    assert codexLib != null;
    let
      # Build each skill using codexLib.mkSkill
      codexSkills = map (buildSkillForTarget codexLib.mkSkill) skills;

      # Aggregate MCP servers from skill metadata (MCP is universal)
      allMcpServers = lib.foldl' (acc: s: acc // (s.meta.mcpServers or { })) { } skills;

      # Build the plugin
      plugin = codexLib.mkPlugin {
        inherit name;
        description = description;
        skills = codexSkills;
        inherit hooks;
        mcpServers = allMcpServers;
      };

      # Attribution derivation
      attributionDrv = lib.optional (attributionFile != null) (
        pkgs.runCommand "${name}-codex-attribution" { } ''
          mkdir -p $out
          cp ${attributionFile} $out/ATTRIBUTION
        ''
      );
    in
    pkgs.buildEnv {
      name = "${name}-codex-complete";
      paths = [ plugin ] ++ attributionDrv;
    };
in
{
  inherit
    discoverSkills
    buildPlugin
    evalSkillNix
    buildSkillDrv
    buildSkillForTarget
    buildGeminiPlugin
    buildCodexPlugin
    ;
}
