# Mechanical enforcement of the governing rule for prompt fragments:
# fragments state POLICY, never INVENTORY.
#
# Everything a harness fills in for itself — the skill list, the tool schemas,
# the model, the date, the working directory — must never be hand-written into
# a fragment, because a hand-written copy is a copy that goes stale silently
# and contradicts the injected truth sitting next to it in the same context.
#
# Matching is token-based rather than substring-based, which buys word
# boundaries for free: "sem" does not match inside "semantic", and
# "writing-plans" matches as one token because hyphens are part of a token.
{ lib }:
rec {
  # Tool identifiers that are never ordinary English, so a bare token match is
  # safe. Covers the four harnesses' built-ins plus the pi extension API names
  # a fragment might be tempted to explain instead of letting registerTool
  # inject them.
  harnessTools = [
    "WebFetch"
    "WebSearch"
    "TodoWrite"
    "NotebookEdit"
    "MultiEdit"
    "SlashCommand"
    "ExitPlanMode"
    "BashOutput"
    "KillShell"
    "ToolSearch"
    "AskUserQuestion"
    "apply_patch"
    "update_plan"
    "view_image"
    "str_replace_editor"
    "registerTool"
    "registerCommand"
    "promptSnippet"
    "promptGuidelines"
  ];

  # Tool identifiers that ARE ordinary English. Banning the bare token would
  # forbid "Read the error before retrying" — a policy sentence we want. So
  # these are caught only in the phrase that actually names inventory:
  # "<Tool> tool" / "<Tool> tools", capitalised as the tool is.
  ambiguousTools = [
    "Read"
    "Write"
    "Edit"
    "Task"
    "Agent"
    "Skill"
    "Grep"
    "Glob"
    "Bash"
    "Search"
    "Fetch"
  ];

  # Harness and model-family names. `shared/` reaches four different agents,
  # so naming any one of them in a fragment is wrong by construction; and a
  # model name is stale the moment the model rolls.
  identityTerms = [
    "claude"
    "opus"
    "sonnet"
    "haiku"
    "fable"
    "gpt"
    "codex"
    "gemini"
    "antigravity"
    "grok"
    "llama"
    "anthropic"
    "openai"
  ];

  # Split on everything that is not an identifier character. Hyphens and
  # underscores stay inside tokens so "writing-plans" and "apply_patch" are
  # each one token. builtins.split interleaves separators as lists, hence the
  # isString filter.
  tokenize =
    text: builtins.filter (t: builtins.isString t && t != "") (builtins.split "[^A-Za-z0-9_-]+" text);

  bigrams =
    toks:
    if toks == [ ] then
      [ ]
    else
      lib.zipListsWith (a: b: {
        first = a;
        second = b;
      }) toks (builtins.tail toks);

  # Returns every violation found in `text`. An empty list is a pass.
  lint =
    { skillNames, text }:
    let
      toks = tokenize text;
      lower = map lib.toLower toks;
      hit = rule: term: { inherit rule term; };

      skillHits = map (hit "skill-name") (
        lib.unique (lib.intersectLists (map lib.toLower skillNames) lower)
      );

      toolHits = map (hit "tool-name") (lib.unique (lib.intersectLists harnessTools toks));

      phraseHits = map (b: hit "tool-phrase" "${b.first} ${b.second}") (
        builtins.filter (
          b:
          builtins.elem b.first ambiguousTools
          && builtins.elem (lib.toLower b.second) [
            "tool"
            "tools"
          ]
        ) (bigrams toks)
      );

      identityHits = map (hit "identity") (lib.unique (lib.intersectLists identityTerms lower));

      # An ISO date survives tokenisation intact, because digits and hyphens
      # are both token characters — so this needs no multiline regex.
      dateHits = map (hit "date") (
        lib.unique (
          builtins.filter (t: builtins.match "[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]" t != null) toks
        )
      );

      # Path separators are stripped by tokenize, so these are raw substring
      # checks against the original text.
      pathHits = map (hit "absolute-path") (
        builtins.filter (p: lib.hasInfix p text) [
          "/home/"
          "/Users/"
          "~/"
        ]
      );
    in
    skillHits ++ toolHits ++ phraseHits ++ identityHits ++ dateHits ++ pathHits;
}
