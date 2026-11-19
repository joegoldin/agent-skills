#!/usr/bin/env bash
set -euo pipefail

# Rex's hook is local-only and prints guidance matching the installed binary.
# Outside Rex there is no terminal context to add.
rex_context=""
if [[ "${REX_SESSION:-}" =~ ^session:[[:xdigit:]-]{36}$ && "${REX_BLOCK:-}" =~ ^block:[[:xdigit:]-]{36}$ ]] \
  && command -v rex >/dev/null 2>&1; then
  rex_context=$(rex __internal session-start --agent claude --feature-session-naming=false 2>/dev/null || true)
fi

[[ -n "$rex_context" ]] || exit 0
@JQ@ -n --arg rex "$rex_context" '{
  hookSpecificOutput: {
    hookEventName: "SessionStart",
    additionalContext: $rex
  }
}'
