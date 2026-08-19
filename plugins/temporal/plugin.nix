# temporal — throttled time injection. Cross-agent plugin definition.
# The three hook-based CLIs get a Python hook; pi, which has no hook
# system, gets the equivalent TypeScript extension. State dir is per-CLI:
# $TEMPORAL_STATE_DIR for the hook targets, ~/.pi/.temporal by default in
# the extension.
{
  pkgs,
  lib,
  target,
  ...
}:
let
  isPi = target == "pi";
  stateSubdir =
    if target == "codex" then
      ".codex"
    else if target == "antigravity" then
      ".antigravity"
    else
      ".claude";
  # $HOME is expanded at runtime by the shell, not at nix-eval time.
  temporalScript = pkgs.writeShellScript "temporal-${target}" ''
    export TEMPORAL_STATE_DIR="$HOME/${stateSubdir}/.temporal"
    exec ${pkgs.python3}/bin/python3 ${./temporal.py} "$@"
  '';
  # Claude scopes SessionStart to specific triggers; the others fire on all.
  sessionMatcher = if target == "claude" then "startup|resume|clear|compact" else "";
in
{
  name = "temporal";
  description = "Use when the user asks about time/date hooks, why timestamps appear in context, or wants to tune the [⏱] injection.";
  # The extension is pure Node stdlib; only the Python hook needs python3.
  packages = lib.optionals (!isPi) [ pkgs.python3 ];
  skill.body = ''
    # temporal — time awareness hook

    Background-only — this plugin contributes a hook, not skill content
    you invoke directly. The hook injects a throttled `[⏱ time]` block at
    UserPromptSubmit and after compaction so the agent knows what time
    it is.

    Configure via env vars:
    - `TEMPORAL_INTERVAL` (seconds, default 300): min interval between injects.
    - `TEMPORAL_TTL_DAYS` (default 7): days before stale session state is swept.
  '';
  extensions = lib.optionals isPi [
    {
      name = "temporal";
      source = ./temporal.ts;
    }
  ];
  hooks = lib.optionals (!isPi) [
    {
      event = "UserPromptSubmit";
      matcher = "";
      name = "temporal-user-prompt-submit";
      command = "${temporalScript}";
    }
    {
      event = "SessionStart";
      matcher = sessionMatcher;
      name = "temporal-session-start";
      command = "${temporalScript}";
    }
  ];
}
