#!/usr/bin/env bash
set -euo pipefail

# Rex's hook is local-only and prints guidance matching the installed binary.
# Outside Rex (or without the binary), leave the shared startup hook unchanged.
rex_context=""
if [[ "${REX_SESSION:-}" =~ ^session:[[:xdigit:]-]{36}$ && "${REX_BLOCK:-}" =~ ^block:[[:xdigit:]-]{36}$ ]] \
  && command -v rex >/dev/null 2>&1; then
  rex_context=$(rex __internal session-start --agent claude --feature-session-naming=false 2>/dev/null || true)
fi

# Read the rendered guidance directly; jq handles JSON escaping.
@JQ@ -n --rawfile guidance "@USING_AGENT_SKILLS@" --arg rex "$rex_context" '{
  hookSpecificOutput: {
    hookEventName: "SessionStart",
    additionalContext: ($guidance + (if $rex == "" then "" else "\n\n" + $rex end))
  }
}'
