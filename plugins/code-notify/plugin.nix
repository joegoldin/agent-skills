# code-notify — desktop notifications for agent events. Cross-agent, hook-only
# (no skill). Same three hooks on every target; previously baked separately into
# each target's main plugin / settings.
{
  pkgs,
  ...
}:
let
  codeNotify = pkgs.callPackage ../../packages/code-notify { };
  notifier = "${codeNotify}/lib/code-notify/core/notifier.sh";
in
{
  name = "code-notify";
  description = "Desktop notifications for agent events (Notification, Stop, long-running Bash).";
  skill = null;
  hooks = [
    {
      event = "Notification";
      matcher = "";
      name = "code-notify-notification";
      command = "${notifier} notification";
    }
    {
      event = "Stop";
      matcher = "";
      name = "code-notify-stop";
      command = "${notifier} stop";
    }
    {
      event = "PreToolUse";
      matcher = "Bash";
      name = "code-notify-pretooluse";
      command = "${notifier} PreToolUse";
    }
  ];
}
