#!/usr/bin/env bash
# Test the bundled Vale styles and config profiles against fixtures.
#
# Three assertions, driven by tests/cases.tsv:
#
#   cover:<prefix>  every rule in the style whose name starts with <prefix>
#                   fires at least once on the fixture. A new rule with no
#                   fixture coverage fails the build.
#   clean           the fixture produces zero alerts, so the rules stay off
#                   ordinary human prose.
#   (all configs)   every profile in configs/ loads without a fatal error.
#
# Vale exit codes: 0 = clean, 1 = alerts found, 2 = fatal (bad rule, missing
# style). Only 2 is a failure here.
set -uo pipefail

here=$(cd "$(dirname "$0")" && pwd)
root=$(dirname "$here")
vale=${VALE:-vale}
configs=${VALE_SKILL_CONFIGS:-$root/configs}
styles=${VALE_SKILL_STYLES:-$root/styles}
fixtures=$here/fixtures

# Vale writes a config cache under $HOME; keep it out of the source tree.
export HOME=${TMPDIR:-/tmp}/vale-agent-skills-test-home
mkdir -p "$HOME"

failures=0
fail() { echo "  FAIL $*"; failures=$((failures + 1)); }

run_vale() {
  # $1 = config, $2 = file. Prints the fired check names, one per line.
  "$vale" --config="$configs/$1" --no-exit --output=JSON "$2" 2>"$HOME/stderr" |
    grep -o '"Check": *"[^"]*"' | sed 's/.*"\([^"]*\)"$/\1/' | sort -u
  return "${PIPESTATUS[0]}"
}

echo "== every config profile loads =="
printf 'A short line of prose.\n' > "$HOME/probe.md"
for cfg in "$configs"/*.ini; do
  name=$(basename "$cfg")
  "$vale" --config="$cfg" --no-exit "$HOME/probe.md" >/dev/null 2>"$HOME/stderr"
  if [ "$?" = 2 ]; then
    fail "$name did not load"; sed 's/^/    /' "$HOME/stderr"
  else
    echo "  ok   $name"
  fi
done

echo "== fixtures =="
while IFS=$'\t' read -r cfg fixture assertion; do
  case "$cfg" in ''|\#*) continue ;; esac
  fired=$(run_vale "$cfg" "$fixtures/$fixture")
  if [ "$?" = 2 ]; then
    fail "$fixture: vale stopped with a fatal error"
    sed 's/^/    /' "$HOME/stderr"
    continue
  fi

  case "$assertion" in
    clean)
      if [ -n "$fired" ]; then
        fail "$fixture should be clean under $cfg but flagged:"
        echo "$fired" | sed 's/^/    /'
      else
        echo "  ok   $fixture is clean under $cfg"
      fi
      ;;
    cover:*)
      prefix=${assertion#cover:}
      style=${prefix%%.*}
      missing=""
      for path in "$styles/$style"/*.yml; do
        rule="$style.$(basename "$path" .yml)"
        case "$rule" in "$prefix"*) ;; *) continue ;; esac
        echo "$fired" | grep -qx "$rule" || missing="$missing $rule"
      done
      if [ -n "$missing" ]; then
        fail "$fixture covers no case for:$missing"
      else
        echo "  ok   $fixture covers every $prefix rule"
      fi
      ;;
    *)
      fail "unknown assertion '$assertion' in cases.tsv"
      ;;
  esac
done < "$here/cases.tsv"

if [ "$failures" -gt 0 ]; then
  echo "$failures failure(s)"
  exit 1
fi
echo "all checks passed"
