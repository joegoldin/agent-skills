#!/usr/bin/env bash
# PreToolUse hook: validates docker commands beyond pattern matching.
# Rejects:
#   - docker commands containing shell metacharacters that allow bypass (# $( `)
#   - docker run / docker build where the image is not claude-container* or claude-proxy*
#
# Stdin: tool-call JSON. Stdout JSON to deny; exit 0 silently to allow.

set -eu

input=$(cat 2>/dev/null || true)
cmd=$(printf '%s' "$input" | jq -r '.tool_input.command // ""' 2>/dev/null || echo "")

case "$cmd" in
  *docker*) ;;
  *) exit 0 ;;
esac

deny() {
  jq -n --arg r "$1" '{
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "deny",
      permissionDecisionReason: $r
    }
  }'
  exit 0
}

case "$cmd" in
  *docker*\#*)   deny "docker command contains # (comment-trick: pattern matches but shell drops the comment)";;
  *docker*'$('*) deny "docker command contains \$( (command substitution; potential image forgery)";;
  *docker*'`'*)  deny "docker command contains backtick (command substitution; potential image forgery)";;
esac

if printf '%s' "$cmd" | grep -qE 'docker[[:space:]]+(run|build)[[:space:]]'; then
  subcmd=$(printf '%s' "$cmd" | grep -oE 'docker[[:space:]]+(run|build)' | awk '{print $2}' | head -1)
  after=$(printf '%s' "$cmd" | sed -E "s/^.*docker[[:space:]]+${subcmd}[[:space:]]+//")

  flag_with_value='^(--name|-v|--volume|-e|--env|-p|--publish|--label|-l|--network|--user|-u|--workdir|-w|--entrypoint|--restart|--hostname|-h|-t|--tag|-f|--file|--cpus|--memory|-m|--add-host|--cap-add|--cap-drop|--device|--dns|--ipc|--mount|--pid|--uts)$'

  set -- $after
  image=""
  tag=""
  while [ $# -gt 0 ]; do
    tok="$1"
    case "$tok" in
      -*)
        if printf '%s' "$tok" | grep -qE "$flag_with_value"; then
          case "$tok" in
            -t|--tag) tag="${2:-}";;
          esac
          if [ $# -ge 2 ]; then shift 2; else shift; fi
        else
          shift
        fi
        ;;
      *)
        image="$tok"; break ;;
    esac
  done

  case "$subcmd" in
    run)
      case "$image" in
        claude-container*|claude-proxy*) ;;
        *) deny "docker run image must be claude-container* or claude-proxy* (got: '${image:-<none>}')";;
      esac
      ;;
    build)
      case "$tag" in
        claude-container*|claude-proxy*) ;;
        *) deny "docker build must use -t/--tag claude-container* or claude-proxy* (got: '${tag:-<none>}')";;
      esac
      ;;
  esac
fi

exit 0
