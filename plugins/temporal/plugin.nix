# temporal — throttled time injection. Cross-agent plugin definition.
# Ships a Python hook that injects a `[⏱ time]` block at UserPromptSubmit and
# SessionStart. State dir is per-CLI via $TEMPORAL_STATE_DIR.
{
  pkgs,
  target,
  ...
}:
let
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
  packages = [ pkgs.python3 ];
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
  hooks = [
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
