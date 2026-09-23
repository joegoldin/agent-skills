#!/usr/bin/env bash
set -euo pipefail

# Read the rendered guidance directly; jq handles JSON escaping.
@JQ@ -n --rawfile guidance "@USING_AGENT_SKILLS@" '{
  hookSpecificOutput: {
    hookEventName: "SessionStart",
    additionalContext: $guidance
  }
}'
