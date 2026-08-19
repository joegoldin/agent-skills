{ lib }:
let
  inherit (lib)
    filterAttrs
    mapAttrs
    optionalAttrs
    types
    mkOption
    ;

  # Normalized per-server schema. Exactly one of `command` (stdio) or `url`
  # (remote) should be set; `disabled = true` omits the server everywhere.
  normalizedModule = types.submodule {
    options = {
      command = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "Executable for a stdio MCP server.";
      };
      args = mkOption {
        type = types.listOf types.str;
        default = [ ];
        description = "Arguments for the stdio command.";
      };
      env = mkOption {
        type = types.attrsOf types.str;
        default = { };
        description = "Environment variables (written literally — no raw secrets).";
      };
      url = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "URL for a remote (HTTP) MCP server. Setting this selects remote transport.";
      };
      headers = mkOption {
        type = types.attrsOf types.str;
        default = { };
        description = "HTTP headers for a remote server (claude/antigravity native; mapped to Codex http_headers).";
      };
      bearerTokenEnvVar = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "Codex-only: name of an env var holding the bearer token for a remote server.";
      };
      disabled = mkOption {
        type = types.bool;
        default = false;
        description = "If true, omit this server from every target.";
      };
    };
  };

  # Translate one normalized server to a target's native attrs.
  toNative =
    target: name: s:
    let
      isRemote = s.url != null;
      stdio = {
        command = s.command;
      }
      // optionalAttrs (s.args != [ ]) { inherit (s) args; }
      // optionalAttrs (s.env != { }) { inherit (s) env; };
    in
    assert lib.assertMsg (
      (s.command != null) != isRemote
    ) "agent-skills mcpServers.${name}: set exactly one of `command` (stdio) or `url` (remote).";
    if !isRemote then
      stdio
    else if target == "claude" then
      {
        type = "http";
        url = s.url;
      }
      // optionalAttrs (s.headers != { }) { inherit (s) headers; }
    else if target == "antigravity" then
      {
        serverUrl = s.url;
      }
      // optionalAttrs (s.headers != { }) { inherit (s) headers; }
    else if target == "codex" then
      {
        url = s.url;
      }
      // optionalAttrs (s.bearerTokenEnvVar != null) { bearer_token_env_var = s.bearerTokenEnvVar; }
      // optionalAttrs (s.headers != { }) { http_headers = s.headers; }
    else if target == "pi" then
      # pi has no native MCP; this is pi-mcp-adapter's mcp.json schema.
      # `headers` is spelled the same as claude/antigravity; the bearer-token
      # env var is `bearerTokenEnv` and must be paired with auth = "bearer".
      {
        url = s.url;
      }
      // optionalAttrs (s.headers != { }) { inherit (s) headers; }
      // optionalAttrs (s.bearerTokenEnvVar != null) {
        auth = "bearer";
        bearerTokenEnv = s.bearerTokenEnvVar;
      }
    else
      throw "agent-skills mcpServers.${name}: unknown target '${target}' (known: claude, antigravity, codex, pi)";

  # Translate a whole normalized server set for one target, dropping disabled.
  mcpNativeFor =
    target: servers:
    mapAttrs (name: toNative target name) (filterAttrs (_name: s: !s.disabled) servers);
in
{
  inherit normalizedModule mcpNativeFor;
}
