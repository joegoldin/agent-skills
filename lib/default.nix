{
  pkgs,
  lib,
  claudeLib,
  agyLib ? null,
  codexLib ? null,
  piLib ? null,
}:
let
  mcpLib = import ./mcp.nix { inherit lib; };

  fm = import ./frontmatter.nix { inherit lib; };
  lintLib = import ./lint.nix { inherit lib; };

  # Evaluate an optional skill.nix sidecar. Sidecars carry only what
  # markdown cannot express: packages, mcpServers, lspServers. A sidecar
  # may be an attrset or a function of (a subset of) { pkgs, lib }.
  evalSidecar =
    dirName: raw:
    let
      args = { inherit pkgs lib; };
      attrs =
        if builtins.isFunction raw then
          raw (builtins.intersectAttrs (builtins.functionArgs raw) args)
        else
          raw;
    in
    lintLib.validateSidecar dirName attrs;

  # ── Target-neutral agent spec → per-target agent derivation ──
  # Skills declare subagents once as a spec so the same definition lands in
  # every target's native format:
  #   { name; description; prompt; tools ? [ ];
  #     model? effort? permissionMode? maxTurns? memory? isolation?
  #     background? initialPrompt? color? disallowedTools? skills? }
  # Claude/Antigravity take (attrs: body); Codex takes a single attrs with the
  # prompt as `developer_instructions` and has no tool-restriction field.
  # Each target is handed only the fields its own format models, so a
  # Claude-specific field on a shared spec degrades rather than erroring.
  pickSpec =
    keys: a:
    lib.filterAttrs (k: _: builtins.elem k keys) (
      builtins.removeAttrs a [
        "prompt"
        "tools"
      ]
    );

  claudeAgentKeys = [
    "name"
    "description"
    "model"
    "effort"
    "permissionMode"
    "maxTurns"
    "memory"
    "isolation"
    "background"
    "initialPrompt"
    "color"
    "disallowedTools"
    "skills"
  ];

  mkClaudeAgentFromSpec =
    a:
    claudeLib.mkAgent (
      pickSpec claudeAgentKeys a
      // {
        tools = a.tools or [ ];
      }
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

  # A skill directory is shipped verbatim: SKILL.md (frontmatter included)
  # and all assets, minus the Nix sidecar and the agents/ source dir.
  buildSkillDrv =
    name: skillDir:
    pkgs.runCommand "skill-${name}" { } ''
      mkdir -p $out/skills/${name}
      for item in ${skillDir}/*; do
        basename=$(basename "$item")
        case "$basename" in
          skill.nix|agents) ;;
          *) cp -r "$item" $out/skills/${name}/ ;;
        esac
      done
    '';

  # Parse agents/<name>.md files into target-neutral agent specs:
  #   { name; description; prompt; tools ? [ ]; model ? ...; }
  loadAgentSpecs =
    skillName: dir:
    let
      agentsDir = dir + "/agents";
      mdFiles = builtins.filter (n: lib.hasSuffix ".md" n) (
        builtins.attrNames (builtins.readDir agentsDir)
      );
      # Optional scalars, keyed by the spec attr they become. Each accepts
      # either the kebab frontmatter spelling or the camelCase one; absent
      # keys stay absent so the target builder omits them entirely.
      scalarKeys = {
        model = [ "model" ];
        effort = [ "effort" ];
        permissionMode = [
          "permission-mode"
          "permissionMode"
        ];
        maxTurns = [
          "max-turns"
          "maxTurns"
        ];
        memory = [ "memory" ];
        isolation = [ "isolation" ];
        background = [ "background" ];
        initialPrompt = [
          "initial-prompt"
          "initialPrompt"
        ];
        color = [ "color" ];
      };
      listKeys = {
        disallowedTools = [
          "disallowed-tools"
          "disallowedTools"
        ];
        skills = [ "skills" ];
      };
    in
    if !builtins.pathExists agentsDir then
      [ ]
    else
      map (
        fname:
        let
          parsed = lintLib.validateAgentMd {
            inherit skillName;
            fileName = fname;
            parsed = fm.parseFile (agentsDir + "/${fname}");
          };
          stem = lib.removeSuffix ".md" fname;
          scalarAttrs = lib.concatMapAttrs (
            attr: aliases:
            let
              hit = lib.findFirst (k: parsed.fields ? ${k}) null aliases;
            in
            lib.optionalAttrs (hit != null) { ${attr} = parsed.fields.${hit}; }
          ) scalarKeys;
          listAttrs = lib.concatMapAttrs (
            attr: aliases:
            let
              vals = lib.concatMap (k: fm.parseToolList parsed k) aliases;
            in
            lib.optionalAttrs (vals != [ ]) { ${attr} = vals; }
          ) listKeys;
          optionals = scalarAttrs // listAttrs;
        in
        {
          name = parsed.fields.name or stem;
          inherit (parsed.fields) description;
          tools = fm.parseToolList parsed "tools";
          prompt = parsed.body;
        }
        // optionals
      ) mdFiles;

  discoverSkills =
    skillsDir:
    let
      entries = builtins.readDir skillsDir;
      dirNames = builtins.attrNames (lib.filterAttrs (_: type: type == "directory") entries);
      validNames = builtins.filter (name: builtins.pathExists (skillsDir + "/${name}/SKILL.md")) dirNames;
    in
    map (
      name:
      let
        dir = skillsDir + "/${name}";
        parsed = lintLib.validateSkillMd {
          dirName = name;
          parsed = fm.parseFile (dir + "/SKILL.md");
        };
        sidecar =
          if builtins.pathExists (dir + "/skill.nix") then
            evalSidecar name (import (dir + "/skill.nix"))
          else
            { };
      in
      {
        inherit name dir parsed;
        meta = {
          inherit name;
          description = parsed.fields.description;
          allowed-tools = fm.parseToolList parsed "allowed-tools";
          agentSpecs = loadAgentSpecs name dir;
        }
        // sidecar;
        # Forcing `parsed` here runs validateSkillMd's whole check chain, so any
        # lint violation fails every build that instantiates the skill drv — not
        # just checks.skills-lint.
        drv = builtins.seq parsed (buildSkillDrv name dir);
      }
    ) validNames;

  # Sidecar-declared tool packages, aggregated into every target's buildEnv
  # so skill-referenced commands are on PATH.
  skillPackagesOf = skills: lib.concatMap (s: s.meta.packages or [ ]) skills;

  # ── Web/app uploadable skills bundle ──
  # Emits $out/<name>/ for every skill so each top-level folder is a complete,
  # ready-to-zip skill (folder = zip root for the Claude web/app
  # "Customize > Skills" upload format). Reuses each skill's per-skill drv
  # (SKILL.md with frontmatter + scripts/references/examples already assembled).
  #
  # avoid-ai-writing is made self-contained for the web/app code sandbox: the
  # pure-Node detector (cli.js + patterns.js) is vendored into its scripts/ and
  # the SKILL.md command invocations are rewritten to `node scripts/cli.js`.
  # No deps are bundled — the engine is Node stdlib only.
  buildWebBundle =
    {
      name ? "web-skills",
      skills,
      avoidAiDetectSrc,
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

      # ── Restrict frontmatter to the agentskills.io portable field set ──
      # claude.ai uploads reject any other key ("Unexpected key(s) in
      # SKILL.md frontmatter"). Claude Code-only fields (argument-hint,
      # context, disable-model-invocation, ...) are dropped here; they keep
      # working in the plugin, which ships the file verbatim. Indented
      # continuation lines (block lists, metadata maps) follow their key's
      # keep/drop decision.
      for f in $out/*/SKILL.md; do
        awk '
          NR==1 && $0=="---" { fm=1; print; next }
          fm && $0=="---"    { fm=0; print; next }
          fm {
            if ($0 ~ /^[A-Za-z0-9_-]+:/) {
              key=$0; sub(/:.*/, "", key)
              keep = (${lib.concatMapStringsSep " || " (f: ''key=="${f}"'') lintLib.portableFields})
            }
            if (keep) print
            next
          }
          { print }
        ' "$f" > "$f.tmp" && mv "$f.tmp" "$f"
      done

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

      # ── Make avoid-ai-writing self-contained for the web/app sandbox ──
      aaw=$out/avoid-ai-writing
      if [ -d "$aaw" ]; then
        chmod -R u+w "$aaw"
        mkdir -p "$aaw/scripts"
        # Only the two files the engine actually needs at runtime; cli.js
        # resolves patterns.js via __dirname. (CATEGORIES.md is docs-only and
        # neither loaded nor referenced, so it is deliberately not copied.)
        cp ${avoidAiDetectSrc}/cli.js "$aaw/scripts/cli.js"
        cp ${avoidAiDetectSrc}/patterns.js "$aaw/scripts/patterns.js"

        # Surgical rewrite: command invocations + allowed-tools only. Prose
        # mentions of the engine name are intentionally left intact.
        sed -i \
          -e 's#^avoid-ai-detect #node scripts/cli.js #' \
          -e 's#| avoid-ai-detect#| node scripts/cli.js#' \
          -e 's#Bash(avoid-ai-detect:\*)#Bash(node:*)#' \
          -e 's#Bash(avoid-ai-detect)#Bash(node)#' \
          "$aaw/SKILL.md"

        # Declare the runtime dependency via the spec's compatibility field.
        sed -i '0,/^description:/ s/^description:/compatibility: Requires Node.js 18 or newer (engine is Node stdlib only)\ndescription:/' "$aaw/SKILL.md"
      fi
    '';

  # ── Build using-agent-skills content (shared across targets) ──
  buildUsingAgentSkillsContent =
    skills:
    let
      usingAgentSkillsSkill = lib.findFirst (s: s.name == "using-agent-skills") null skills;
    in
    if usingAgentSkillsSkill != null then
      builtins.readFile (usingAgentSkillsSkill.dir + "/SKILL.md")
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
      # Target-neutral agent specs → Claude agents. Skills declare agents once
      # as `{ name; description; prompt; tools?; model?; }` so the same spec can
      # be re-targeted to Codex/Antigravity by the other build functions.
      allAgentSpecs = lib.concatMap (s: s.meta.agentSpecs or [ ]) skills;
      claudeSpecAgents = map (a: mkClaudeAgentFromSpec a) allAgentSpecs;
      allMcpServers = lib.foldl' (acc: s: acc // (s.meta.mcpServers or { })) { } skills;
      allLspServers = lib.foldl' (acc: s: acc // (s.meta.lspServers or { })) { } skills;
      skillPackages = skillPackagesOf skills;

      plugin = claudeLib.mkPlugin {
        inherit name description;
        skills = map (s: s.drv) skills;
        agents = claudeSpecAgents;
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
      paths = [ plugin ] ++ hooksDrv ++ attributionDrv ++ extraPackages ++ skillPackages;
    };

  # ── Build a skill using a target's mkSkill ──
  # Targets rebuild their own frontmatter from name/description/
  # allowed-tools; Claude Code-only fields intentionally do not carry over.
  buildSkillForTarget =
    targetMkSkill: skill:
    let
      extraFiles =
        let
          entries = builtins.readDir skill.dir;
          extras = lib.filterAttrs (
            name: _: name != "skill.nix" && name != "SKILL.md" && name != "agents"
          ) entries;
        in
        map (name: skill.dir + "/${name}") (builtins.attrNames extras);
    in
    targetMkSkill {
      inherit (skill.meta) name description;
      allowed-tools = skill.meta.allowed-tools or [ ];
      inherit extraFiles;
    } skill.parsed.body;

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

      skillPackages = skillPackagesOf skills;

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
      paths = [ plugin ] ++ attributionDrv ++ extraPackages ++ skillPackages;
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

      skillPackages = skillPackagesOf skills;

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
      paths = [ plugin ] ++ attributionDrv ++ extraPackages ++ skillPackages;
    })
    // {
      _codex = plugin._codex or { };
    };

  # A command-style skill: invoked by the user, hidden from the model's
  # skill list. pi honours `disable-model-invocation` natively
  # (formatSkillsForPrompt filters them out) and registers every skill as
  # /skill:<name>; the prompt template is what gives it the short /<name>
  # form plus an argument hint in the autocomplete.
  isPiCommandSkill = skill: (skill.parsed.fields."disable-model-invocation" or "false") == "true";

  # SKILL.md frontmatter → pi prompt-template frontmatter. `description` is
  # required (pi otherwise takes the first 60 characters of the body);
  # `argument-hint` is forwarded when present. Everything else is dropped:
  # a prompt template is a body plus those two fields, nothing more.
  mkPiPromptTemplateFor =
    skill:
    assert piLib != null;
    piLib.mkPiPromptTemplate (
      {
        inherit (skill.meta) name description;
      }
      // lib.optionalAttrs (skill.parsed.fields ? "argument-hint") {
        argument-hint = skill.parsed.fields."argument-hint";
      }
    ) skill.parsed.body;

  # ── pi package ──
  # pi consumes a *package*: a directory whose package.json carries a `pi`
  # key naming the resource directories (pi.dev/docs/latest/packages). One
  # entry in settings.packages loads skills, prompt templates, and
  # extensions together.
  #
  # A3 (design §4): skills are the SAME skill-<name> derivations the Claude
  # plugin ships, linked in by buildEnv — never copied. pi's loadSkills
  # consults a realpath set before its name map, so a skill reachable via
  # both ~/.agents/skills and this package is dropped silently rather than
  # raising a startup collision warning. checks.pi-skill-realpath-identity
  # is the gate; do not replace the link with a copy.
  buildPiPlugin =
    {
      name,
      description,
      skills,
      attributionFile ? null,
      extraPackages ? [ ],
    }:
    assert piLib != null;
    let
      skillPackages = skillPackagesOf skills;

      prompts = map mkPiPromptTemplateFor (builtins.filter isPiCommandSkill skills);

      plugin = piLib.mkPlugin {
        inherit name description prompts;
        skills = map (s: s.drv) skills;
      };

      attributionDrv = lib.optional (attributionFile != null) (
        pkgs.runCommand "${name}-pi-attribution" { } ''
          mkdir -p $out
          cp ${attributionFile} $out/ATTRIBUTION
        ''
      );
    in
    pkgs.buildEnv {
      name = "${name}-pi-complete";
      paths = [ plugin ] ++ attributionDrv ++ extraPackages ++ skillPackages;
      passthru.meta = { inherit name description; };
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
  # list per event (plugin order preserved).
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
    evalSidecar
    buildSkillDrv
    buildSkillForTarget
    buildAntigravityPlugin
    buildCodexPlugin
    buildPiPlugin
    isPiCommandSkill
    mkPiPromptTemplateFor
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
