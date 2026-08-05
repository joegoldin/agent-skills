#!/usr/bin/env bash
# Test the bundled Vale styles, config profiles, and the vale-skill launcher.
#
# Four assertions:
#
#   (all configs)   every profile in configs/ loads without a fatal error.
#   cover:<prefix>  every rule in the style whose name starts with <prefix>
#                   fires on at least one of the fixtures mapped to it. A new
#                   rule with no fixture coverage fails the build.
#   expect:A,B      the named rules fire on this fixture (wrap regressions).
#   clean           the fixture produces zero alerts, so the rules stay off
#                   ordinary human prose.
#   (score)         the launcher scores the AI fixture above zero and the
#                   human fixture at exactly zero.
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
rm -rf "$HOME"
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
prefixes=""
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
    expect:*)
      # Named rules must fire on this fixture. Used for regressions that a
      # union-style coverage check would not catch -- phrases split across a
      # hard line wrap, for one.
      want=$(printf '%s' "${assertion#expect:}" | tr ',' ' ')
      absent=""
      for rule in $want; do
        echo "$fired" | grep -qx "$rule" || absent="$absent $rule"
      done
      if [ -n "$absent" ]; then
        fail "$fixture did not trip:$absent"
      else
        echo "  ok   $fixture trips every expected rule"
      fi
      ;;
    cover:*)
      prefix=${assertion#cover:}
      # Coverage accumulates across every fixture mapped to the same prefix,
      # so each rule can be exercised by whichever fixture suits it.
      key=$(printf '%s' "$prefix" | tr '.' '_')
      echo "$fired" >> "$HOME/cover_$key"
      case " $prefixes " in
        *" $prefix "*) ;;
        *) prefixes="$prefixes $prefix" ;;
      esac
      echo "  ok   $fixture linted under $cfg"
      ;;
    *)
      fail "unknown assertion '$assertion' in cases.tsv"
      ;;
  esac
done < "$here/cases.tsv"

echo "== rule coverage =="
for prefix in $prefixes; do
  style=${prefix%%.*}
  key=$(printf '%s' "$prefix" | tr '.' '_')
  missing=""
  for path in "$styles/$style"/*.yml; do
    rule="$style.$(basename "$path" .yml)"
    case "$rule" in "$prefix"*) ;; *) continue ;; esac
    grep -qx "$rule" "$HOME/cover_$key" || missing="$missing $rule"
  done
  if [ -n "$missing" ]; then
    fail "no fixture covers:$missing"
  else
    echo "  ok   every $prefix rule fires on a fixture"
  fi
done

echo "== score =="
export VALE_SKILL_CONFIGS=$configs
ai_score=$(bash "$root/vale-skill.sh" score "$fixtures/ai-isms.md" 2>"$HOME/stderr" |
  sed -n '1s|.*score: \([0-9]*\)/100.*|\1|p')
clean_score=$(bash "$root/vale-skill.sh" score "$fixtures/ai-clean.md" 2>>"$HOME/stderr" |
  sed -n '1s|.*score: \([0-9]*\)/100.*|\1|p')
if [ -z "$ai_score" ] || [ -z "$clean_score" ]; then
  fail "vale-skill score produced no score"; sed 's/^/    /' "$HOME/stderr"
elif [ "$ai_score" -le 0 ]; then
  fail "ai-isms.md scored $ai_score, expected above zero"
elif [ "$clean_score" -ne 0 ]; then
  fail "ai-clean.md scored $clean_score, expected zero"
else
  echo "  ok   ai-isms.md scores $ai_score, ai-clean.md scores $clean_score"
fi

if [ "$failures" -gt 0 ]; then
  echo "$failures failure(s)"
  exit 1
fi
echo "all checks passed"
