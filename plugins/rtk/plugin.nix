# rtk — Rust Token Killer. Cross-agent plugin definition.
# Claude is the only target that runs an executable rewrite hook; codex and
# antigravity get awareness markdown only (upstream convention). The awareness
# body is per-target (each CLI gets tailored guidance).
{
  pkgs,
  lib,
  target,
  ...
}:
let
  awarenessFile =
    if target == "antigravity" then
      ./hooks/antigravity/rules.md
    else if target == "codex" then
      ./hooks/codex/rtk-awareness.md
    else
      ./hooks/claude/rtk-awareness.md;
  awarenessBody = builtins.readFile awarenessFile;

  # Wrap the upstream rewrite script with rtk + jq on PATH (Claude PreToolUse).
  rtkRewrite = pkgs.writeShellScript "rtk-rewrite" ''
    export PATH=${lib.makeBinPath [ pkgs.rtk pkgs.jq ]}:$PATH
    exec ${pkgs.bash}/bin/bash ${./hooks/claude/rtk-rewrite.sh} "$@"
  '';
in
{
  name = "rtk";
  description = "Use when the user asks about RTK, `rtk gain`, command rewriting, or token-saving CLI proxy behavior.";
  packages = [ pkgs.rtk ];
  skill.body = ''
    # rtk — Rust Token Killer

    ${awarenessBody}

    ## When to use this skill

    Use when the user asks about RTK token savings, `rtk gain` analytics,
    debugging command rewriting, or wants to understand why a Bash call
    appears as `rtk <cmd>` instead of the raw command.

    Raw shell commands are rewritten automatically (Claude) or by your
    convention (Codex/Antigravity). Never wrap `rtk` calls in another `rtk`.
  '';
  hooks = lib.optionals (target == "claude") [
    {
      event = "PreToolUse";
      matcher = "Bash";
      name = "rtk-rewrite";
      command = "${rtkRewrite}";
    }
  ];
}
