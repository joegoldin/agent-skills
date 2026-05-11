{
  name = "shellbox-cli";
  description = "Use when interacting with shellbox.dev — creating, managing, or connecting to ephemeral Linux microVMs over SSH. Covers box lifecycle (stock + OCI-backed), keepalive/wakeup/cron modes, custom domains, public IPv6 + mosh, billing/funds/refunds, multi-device SSH key management, file transfer (scp/sftp), and IDE remote access. Trigger when the user mentions shellbox, asks for a quick remote dev box reachable over SSH, or runs commands like `ssh shellbox.dev …`.";
  # `ssh shellbox.dev …` is the control plane and is host-scoped.
  # `scp:*` / `sftp:*` cannot be host-scoped — Claude's permission
  # matcher only does prefix matching, and the host appears mid-argv
  # (`scp file user@host:path`). Risk accepted: an agent could in
  # principle scp to other hosts, but the typical use is shellbox box
  # transfers. Interactive box logins (`ssh <name>@shellbox.dev`) and
  # mosh still prompt.
  allowed-tools = [
    "Bash(ssh shellbox.dev:*)"
    "Bash(scp:*)"
    "Bash(sftp:*)"
  ];
}
