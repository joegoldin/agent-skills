{
  pkgs,
  lib,
  claudeLib,
}:
let
  # Import a skill.nix — handles both plain attrsets and functions
  evalSkillNix =
    raw: if builtins.isFunction raw then raw { inherit pkgs lib claudeLib; } else raw;

  # Build a single skill derivation: SKILL.md with frontmatter + extra files
  buildSkillDrv =
    name: meta: skillDir:
    let
      skillBody = builtins.readFile (skillDir + "/SKILL.md");
      frontmatterFields =
        [ "name: ${meta.name}" "description: ${meta.description}" ]
        ++ lib.optional ((meta.allowed-tools or [ ]) != [ ]) "allowed-tools: ${
          toString (meta.allowed-tools or [ ])
        }";
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
      meta = evalSkillNix (import (skillsDir + "/${name}/skill.nix"));
      drv = buildSkillDrv name meta (skillsDir + "/${name}");
    }) validNames;

  # Build the complete plugin from discovered skills
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
      hooksDrv = lib.optional (hooksDir != null) (
        pkgs.runCommand "${name}-hooks" { } ''
          mkdir -p $out/hooks
          cp -r ${hooksDir}/* $out/hooks/
          chmod +x $out/hooks/*.sh 2>/dev/null || true
        ''
      );

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
in
{
  inherit
    discoverSkills
    buildPlugin
    evalSkillNix
    buildSkillDrv
    ;
}
