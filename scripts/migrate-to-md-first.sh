#!/usr/bin/env bash
# One-time migration for the md-first refactor: move name/description/
# allowed-tools out of plain-attrset skill.nix files into SKILL.md
# frontmatter, then git rm the skill.nix. Function-style skill.nix files
# (gh-checks, nix-helper, writing-skills) are skipped — migrated by hand.
#
# Usage: scripts/migrate-to-md-first.sh [--dry-run]
set -euo pipefail
cd "$(dirname "$0")/.."
dry_run="${1:-}"

for nixfile in skills/*/skill.nix; do
  dir=$(dirname "$nixfile")
  name=$(basename "$dir")
  if ! meta=$(nix eval --json --impure --expr "import $PWD/$nixfile" 2>/dev/null); then
    echo "SKIP (function-style; migrate by hand): $name"
    continue
  fi
  if [ "$dry_run" = "--dry-run" ]; then
    META_JSON="$meta" NAME="$name" MD="" python3 scripts/insert_frontmatter.py
  else
    META_JSON="$meta" NAME="$name" MD="$dir/SKILL.md" python3 scripts/insert_frontmatter.py
    git rm -q "$nixfile"
  fi
done
