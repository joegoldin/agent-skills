#!/usr/bin/env bash
# avoid-ai-detect — deterministic AI-writing detector (CLI launcher).
# Original to joegoldin/agent-skills. The engine (patterns.js) is vendored from
# conorbronsdon/avoid-ai-writing (MIT). See ATTRIBUTION.md.
set -euo pipefail

SHARE="${AVOID_AI_DETECT_SHARE:-$(dirname "$(readlink -f "$0")")/../share/avoid-ai-detect}"

exec node "$SHARE/cli.js" "$@"
