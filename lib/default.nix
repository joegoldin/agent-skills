{
  pkgs,
  lib,
  claudeLib,
  agyLib ? null,
  codexLib ? null,
}:
let
  mcpLib = import ./mcp.nix { inherit lib; };

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

  # ── Target-neutral agent spec → per-target agent derivation ──
  # Skills declare subagents once as a spec so the same definition lands in
  # every target's native format:
  #   { name; description; prompt; tools ? [ ]; model ? null; }
  # Claude/Antigravity take (attrs: body); Codex takes a single attrs with the
  # prompt as `developer_instructions` and has no tool-restriction field.
  mkClaudeAgentFromSpec =
    a:
    claudeLib.mkAgent (
      {
        inherit (a) name description;
        tools = a.tools or [ ];
      }
      // lib.optionalAttrs (a ? model) { inherit (a) model; }
    ) a.prompt;

  mkCodexAgentFromSpec =
    a:
    assert codexLib != null;
    codexLib.mkAgent (
      {
        inherit (a) name description;
        developer_instructions = a.prompt;
      }
      // lib.optionalAttrs (a ? model) { inherit (a) model; }
    );

  mkAgyAgentFromSpec =
    a:
    assert agyLib != null;
    agyLib.mkAgent (
      {
        inherit (a) name description;
        tools = a.tools or [ ];
      }
      // lib.optionalAttrs (a ? model) { inherit (a) model; }
    ) a.prompt;

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

  # ── Web/app uploadable skills bundle ──
  # Emits $out/<name>/ for every skill so each top-level folder is a complete,
  # ready-to-zip skill (folder = zip root for the Claude web/app
  # "Customize > Skills" upload format). Reuses each skill's per-skill drv
  # (SKILL.md with frontmatter + scripts/references/examples already assembled).
  #
  # The Vale-backed skills (avoid-ai-writing, simple-english, diataxis) each
  # carry their own style and config profiles, because the web/app sandbox has
  # no Nix and therefore no `vale-skill` launcher. SKILL.md invocations are
  # rewritten to plain `vale --config=vale/<profile>.ini`, which works for
  # anyone who has Vale on PATH and degrades to a by-hand audit for anyone who
  # does not (each skill says so).
  buildWebBundle =
    {
      name ? "web-skills",
      skills,
      valeSrc,
    }:
    let
      copyCmds = lib.concatMapStringsSep "\n" (
        s: "cp -r ${s.drv}/skills/${s.name} $out/${s.name}"
      ) skills;
    in
    pkgs.runCommand name { } ''
      mkdir -p $out
      ${copyCmds}
      chmod -R u+w $out

      # ── Neutralize XML-like tags in every SKILL.md ──
      # The web/app uploader rejects XML tags in skills (e.g. <HARD-GATE>,
      # <path>, <SUBAGENT-STOP>). Convert tag-like <foo>/</foo> to [foo]/[/foo],
      # which keeps the prose readable. The pattern requires '<' immediately
      # followed by an optional '/' and a letter, so it leaves shell/code intact:
      # redirects (2>&1, > out), comparisons (a < b), and version pins (node>=18).
      for f in $out/*/SKILL.md; do
        sed -E -i 's#<(/?[A-Za-z][^<>]*)>#[\1]#g' "$f"
      done

      # ── Rename skills whose name contains the reserved word "claude" ──
      # The uploader rejects skill names containing "claude" (the name field
      # only — body/description mentions are fine). Rewrite the name field and
      # rename the folder (claude -> cc) so the skill uploads. The glob is
      # expanded before the loop, so renaming during iteration is safe.
      for d in $out/*/; do
        name="$(basename "$d")"
        new="$(printf '%s' "$name" | sed -E 's/[Cc]laude/cc/g')"
        if [ "$new" != "$name" ]; then
          sed -i -E '/^name:/ s/[Cc]laude/cc/g' "$out/$name/SKILL.md"
          mv "$out/$name" "$out/$new"
        fi
      done

      # ── Vendor the Vale styles + configs into the skills that use them ──
      # Each skill gets vale/styles/<Style>/ plus its profile .ini files, with
      # `StylesPath = styles` prepended so Vale resolves the style relative to
      # the config it was given. Every profile is vendored: the styles are ours
      # and the bundle needs nothing else.
      vendor_vale() {
        skill=$1
        style=$2
        prefix=$3
        [ -d "$out/$skill" ] || return 0
        chmod -R u+w "$out/$skill"
        mkdir -p "$out/$skill/vale/styles"
        cp -r ${valeSrc}/styles/"$style" "$out/$skill/vale/styles/$style"
        for cfg in ${valeSrc}/configs/"$prefix"*.ini; do
          {
            echo "StylesPath = styles"
            cat "$cfg"
          } > "$out/$skill/vale/$(basename "$cfg")"
        done
        chmod -R u+w "$out/$skill/vale"
      }
      vendor_vale avoid-ai-writing AvoidAI avoid-ai
      vendor_vale simple-english SimpleEnglish simple-english
      vendor_vale diataxis Diataxis diataxis

      # ── Rewrite `vale-skill` invocations to plain `vale --config=` ──
      # The launcher only exists in the Nix plugin. Profile forms first
      # (longest match wins), then the meta-commands, then any leftover
      # mention of the launcher in prose.
      for f in $out/avoid-ai-writing/SKILL.md $out/avoid-ai-writing/references/*.md \
               $out/simple-english/SKILL.md $out/simple-english/references/*.md \
               $out/diataxis/SKILL.md $out/diataxis/references/*.md; do
        [ -f "$f" ] || continue
        sed -E -i \
          -e 's#vale --config="\$\(vale-skill --config ai-writing\)"#vale --config=vale/avoid-ai.ini#g' \
          -e 's#vale-skill --list#ls vale/*.ini#g' \
          -e 's#vale-skill ai-writing:([a-z-]+)#vale --config=vale/avoid-ai-\1.ini#g' \
          -e 's#vale-skill ai-writing#vale --config=vale/avoid-ai.ini#g' \
          -e 's#vale-skill simple-english:([a-z-]+)#vale --config=vale/simple-english-\1.ini#g' \
          -e 's#vale-skill simple-english#vale --config=vale/simple-english.ini#g' \
          -e 's#vale-skill diataxis:([a-z-]+)#vale --config=vale/diataxis-\1.ini#g' \
          -e 's|^vale-skill score.*|# the 0-100 score subcommand ships with the Nix plugin, not this bundle|' \
          -e 's#vale-skill#vale#g' \
          "$f"
      done
    '';

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
      # Target-neutral agent specs → Claude agents. Skills declare agents once
      # as `{ name; description; prompt; tools?; model?; }` so the same spec can
      # be re-targeted to Codex/Antigravity by the other build functions.
      allAgentSpecs = lib.concatMap (s: s.meta.agentSpecs or [ ]) skills;
      claudeSpecAgents = map (a: mkClaudeAgentFromSpec a) allAgentSpecs;
      allMcpServers = lib.foldl' (acc: s: acc // (s.meta.mcpServers or { })) { } skills;
      allLspServers = lib.foldl' (acc: s: acc // (s.meta.lspServers or { })) { } skills;

      plugin = claudeLib.mkPlugin {
        inherit name description;
        skills = map (s: s.drv) skills;
        commands = allCommands;
        agents = allAgents ++ claudeSpecAgents;
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

      agyAgents = map mkAgyAgentFromSpec (lib.concatMap (s: s.meta.agentSpecs or [ ]) skills);

      # Skill-scoped MCP servers → Antigravity per-plugin mcp_config.json.
      # stdio (command/args/env) passes through verbatim (identical across
      # targets); remote servers would need serverUrl/header conversion.
      skillMcpServers = lib.foldl' (acc: s: acc // (s.meta.mcpServers or { })) { } skills;
      agyMcpServers = lib.mapAttrsToList (n: c: agyLib.mkMcpServer ({ name = n; } // c)) skillMcpServers;

      sessionStartHooks =
        if hooksDir != null then buildAntigravityHooks { inherit name skills hooksDir; } else [ ];

      plugin = agyLib.mkPlugin {
        inherit name description;
        skills = agySkills;
        agents = agyAgents;
        hooks = hooks ++ sessionStartHooks;
        mcpServers = mcpServers ++ agyMcpServers;
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

      codexAgents = map mkCodexAgentFromSpec (lib.concatMap (s: s.meta.agentSpecs or [ ]) skills);

      sessionStartHooks =
        if hooksDir != null then buildCodexHooks { inherit name skills hooksDir; } else [ ];

      plugin = codexLib.mkPlugin {
        inherit name;
        description = description;
        skills = codexSkills;
        hooks = hooks ++ sessionStartHooks;
        mcpServers = allMcpServers;
        agents = codexAgents;
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

  # A plugin's declarative hooks → Claude hooks fragment consumed by
  # programs.claude-nix.extraHooks:
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
  # list per event (plugin order preserved, e.g. code-notify before temporal).
  foldClaudeHooks =
    fragments:
    lib.foldl' (
      acc: frag: acc // lib.mapAttrs (event: entries: (acc.${event} or [ ]) ++ entries) frag
    ) { } fragments;

  # Build one cross-agent plugin for a single target. Claude hooks are
  # surfaced via passthru.claudeHooks for the home-manager module to fold
  # into programs.claude-nix.extraHooks (additive per-event lists).
  # claudeLib.mkPlugin's hooks/hooksDir args are an alternative path for
  # plugins that ship their own self-contained hook scripts.
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
    buildWebBundle
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
  inherit (mcpLib) mcpNativeFor normalizedModule;
}
