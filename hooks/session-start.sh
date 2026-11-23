#!/usr/bin/env bash
set -euo pipefail

# Rex's hook is local-only and prints guidance matching the installed binary.
# Outside Rex there is no terminal context to add.
rex_context=""
rex_uuid='[[:xdigit:]]{8}(-[[:xdigit:]]{4}){3}-[[:xdigit:]]{12}'
if [[ "${REX_BLOCK:-}" =~ ^block:${rex_uuid}$ ]] \
  && [[ -z "${REX_SESSION:-}" || "$REX_SESSION" =~ ^session:${rex_uuid}$ ]] \
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
