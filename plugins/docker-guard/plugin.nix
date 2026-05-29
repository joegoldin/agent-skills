# docker-guard — PreToolUse hook that validates docker commands before they
# run. Self-gates on git remote so it only enforces inside the
# claude-container project; everywhere else it's a silent passthrough.
#
# The hook is bash + jq. It rejects:
#   - docker commands with shell metacharacters that bypass pattern matching
#     (`#`, `$( ... )`, backticks)
#   - docker run/build using images outside the claude-container* /
#     claude-proxy* prefixes
{
  pkgs,
  lib,
  target,
  ...
}:
let
  guardScript = pkgs.writeShellScript "docker-guard" (builtins.readFile ./docker-guard.sh);
  # Only Claude exposes the PreToolUse event today; antigravity / codex
  # builds will still receive the plugin in the bundle but emit no hooks.
  isClaude = target == "claude";
in
{
  name = "docker-guard";
  description = "Use when the user asks about docker safety, why docker commands are being blocked, or how to tune the docker image allowlist for claude-container.";
  packages = [ pkgs.jq ];
  skill.body = ''
    # docker-guard — docker command safety hook

    Background-only — this plugin contributes a PreToolUse hook, not
    skill content you invoke directly. The hook rejects docker commands
    that try to escape the claude-container / claude-proxy image
    allowlist or hide behind shell metacharacters.

    Scope: enforces only inside the `claude-container` project (matched
    by git origin URL). In every other project it silently no-ops.

    Don't try to disable or replace the hook from inside a session —
    deny outputs are non-blocking notes and the user can override.
  '';
  hooks = lib.optionals isClaude [
    {
      event = "PreToolUse";
      matcher = "Bash";
      name = "docker-guard-pre-bash";
      command = "${guardScript}";
    }
  ];
}
