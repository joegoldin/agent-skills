# Contract lint for md-first skills. Field tiers:
#  - portableFields: the agentskills.io open spec — the only keys claude.ai
#    web uploads / the Skills API accept.
#  - claudeCodeFields: Claude Code's documented extensions — valid in plugin
#    skills, stripped for the web bundle.
{ lib }:
let
  portableFields = [
    "name"
    "description"
    "license"
    "compatibility"
    "metadata"
    "allowed-tools"
  ];
  claudeCodeFields = [
    "when_to_use"
    "argument-hint"
    "arguments"
    "disable-model-invocation"
    "user-invocable"
    "disallowed-tools"
    "model"
    "effort"
    "context"
    "agent"
    "background"
    "hooks"
    "paths"
    "shell"
    "version"
  ];
  knownFields = portableFields ++ claudeCodeFields;
  sidecarKeys = [
    "packages"
    "mcpServers"
    "lspServers"
  ];
  # agents/<name>.md frontmatter. `name`/`description` are the required pair;
  # everything else is optional and forwarded to whichever targets model it
  # (Claude takes all of these; Codex and Antigravity take the subset their
  # own agent format has). Nested `mcpServers`/`hooks` maps are deliberately
  # absent: the parser reads single-line values only, so declare those in the
  # skill's `skill.nix` sidecar instead.
  agentFields = [
    "name"
    "description"
    "tools"
    "disallowed-tools"
    "skills"
    "model"
    "effort"
    "permission-mode"
    "max-turns"
    "memory"
    "isolation"
    "background"
    "initial-prompt"
    "color"
  ];
  # Kebab frontmatter key -> the camelCase name Claude Code's agent schema
  # uses. Both spellings are accepted on the way in.
  agentFieldAliases = {
    "disallowed-tools" = "disallowedTools";
    "permission-mode" = "permissionMode";
    "max-turns" = "maxTurns";
    "initial-prompt" = "initialPrompt";
  };
  # Both the kebab spelling and the camelCase one Claude Code's schema uses.
  agentKnownFields = agentFields ++ builtins.attrValues agentFieldAliases;
  charCount = c: s: lib.count (x: x == c) (lib.stringToCharacters s);
  # pi's own skill validation, transcribed from
  # pi v0.84.2 packages/coding-agent/src/core/skills.ts (validateName /
  # validateDescription). Kept independent of the agent-skills rules above
  # so a future loosening of validateSkillMd cannot silently ship a skill
  # pi would warn about.
  piMaxNameLength = 64;
  piMaxDescriptionLength = 1024;
  piNamePattern = "[a-z0-9-]+";
in
{
  inherit
    portableFields
    claudeCodeFields
    knownFields
    sidecarKeys
    agentFields
    agentFieldAliases
    agentKnownFields
    piMaxNameLength
    piMaxDescriptionLength
    piNamePattern
    ;

  # Diagnostics pi would emit for this skill; [ ] means pi loads it cleanly.
  # pi falls back to the parent directory name when `name` is absent, and
  # ignores every frontmatter key it does not model, so only name and
  # description are checked.
  piSkillWarnings =
    { dirName, parsed }:
    let
      f = parsed.fields;
      name = f.name or dirName;
      desc = f.description or "";
    in
    lib.optional (
      lib.stringLength name > piMaxNameLength
    ) "name exceeds ${toString piMaxNameLength} characters"
    ++ lib.optional (
      builtins.match piNamePattern name == null
    ) "name contains invalid characters (must be lowercase a-z, 0-9, hyphens only)"
    ++ lib.optional (lib.trim desc == "") "description is required"
    ++ lib.optional (
      lib.stringLength desc > piMaxDescriptionLength
    ) "description exceeds ${toString piMaxDescriptionLength} characters";

  validateAgentMd =
    {
      skillName,
      fileName,
      parsed,
    }:
    let
      unknown = builtins.filter (k: !(builtins.elem k agentKnownFields)) parsed.keys;
      err = msg: throw "agent-skills: skill '${skillName}': agents/${fileName}: ${msg}";
    in
    if !(parsed.fields ? description) || parsed.fields.description == "" then
      err "must set a non-empty description"
    else if unknown != [ ] then
      err "unknown frontmatter key(s): ${toString unknown} (known: ${toString agentKnownFields})"
    else
      parsed;

  validateSkillMd =
    { dirName, parsed }:
    let
      f = parsed.fields;
      err = msg: throw "agent-skills: skill '${dirName}': ${msg}";
      unknown = builtins.filter (k: !(builtins.elem k knownFields)) parsed.keys;
      name = f.name or "";
      desc = f.description or "";
      inlineTools = f.allowed-tools or "";
      blockTools = parsed.items.allowed-tools or [ ];
      # Key present but no value in any form: an empty allowed-tools line
      # restricts the skill to no tools — reject rather than ship the trap.
      emptyTools = builtins.elem "allowed-tools" parsed.keys && inlineTools == "" && blockTools == [ ];
      spaceTokens =
        if inlineTools == "" || lib.hasInfix "," inlineTools then
          [ ]
        else
          builtins.filter (t: t != "") (lib.splitString " " inlineTools);
      # Shear detection is a paren-balance heuristic: it catches Bash(...)
      # entries split mid-parens by the space form, but a space-containing
      # entry with no parens (e.g. a hypothetical `mcp__foo bar`) would
      # shear silently — use the comma form for any entry with spaces.
      unbalanced = builtins.filter (t: charCount "(" t != charCount ")" t) spaceTokens;
    in
    if name == "" then
      err "frontmatter must set name (equal to the directory name)"
    else if builtins.match "[a-z0-9]+(-[a-z0-9]+)*" name == null || lib.stringLength name > 64 then
      err "name '${name}' violates the spec: lowercase alphanumerics and single hyphens, max 64 chars"
    else if name != dirName then
      err "frontmatter name '${name}' must equal the directory name"
    else if
      builtins.elem desc [
        ""
        ">"
        "|"
        ">-"
        "|-"
      ]
    then
      err "description must be a non-empty single-line scalar (no folded/literal YAML blocks)"
    else if lib.stringLength desc > 1024 then
      err "description exceeds the spec's 1024-character cap"
    else if unknown != [ ] then
      err "unknown frontmatter key(s): ${toString unknown} (typo? known fields: portable ∪ Claude Code extensions)"
    else if emptyTools then
      err "allowed-tools is present but empty — an empty allowed-tools line restricts the skill to no tools; remove the key instead"
    else if unbalanced != [ ] then
      err "allowed-tools entries containing spaces must use the comma-separated or block-list form (shorn token(s): ${toString unbalanced})"
    else
      parsed;

  validateSidecar =
    dirName: attrs:
    let
      bad = builtins.filter (k: !(builtins.elem k sidecarKeys)) (builtins.attrNames attrs);
    in
    if bad != [ ] then
      throw "agent-skills: skill '${dirName}': skill.nix may only contain ${toString sidecarKeys}; found: ${toString bad}. name/description/allowed-tools belong in SKILL.md frontmatter; subagents go in agents/*.md; command-style workflows are skills with disable-model-invocation"
    else
      attrs;
}
