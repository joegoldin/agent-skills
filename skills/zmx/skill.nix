{
  name = "zmx";
  description = "Use when running long-lived or persistent terminal processes — dev servers, builds, remote SSH/container shells that must survive disconnects or outlive the task — or when the user mentions zmx, session persistence, attach/detach, or asks to run or inspect something in a named session.";
  allowed-tools = [
    "Bash(zmx)"
    "Bash(zmx:*)"
  ];
}
