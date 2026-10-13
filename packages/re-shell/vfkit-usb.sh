#!/usr/bin/env bash
set -euo pipefail

app=${RE_SHELL_VFKIT_APP:-$HOME/Applications/vfkit.app}
app=$(cd "$app" && pwd -P)
console=$(tty)
socket=
endpoint=
for arg in "$@"; do
  case "$arg" in
    unix:///*) socket=${arg#unix://}; endpoint=$arg ;;
  esac
done

# LaunchServices makes Accessory Access expose its menu. Keep the console on
# the launcher's terminal, including the PTY provided by script(1).
/usr/bin/open -n -W --stdin "$console" --stdout "$console" --stderr "$console" \
  -a "$app" --args "$@" &
app_wait=$!

app_pids() {
  # Match this executable and session, never every process named vfkit.
  while read -r pid command; do
    case "$command" in
      "$app/Contents/MacOS/vfkit "*)
        case " $command " in
          *" --restful-uri $endpoint "*) printf '%s\n' "$pid" ;;
        esac
        ;;
    esac
  done < <(/bin/ps -axo pid=,command=)
}

stop() {
  trap '' INT TERM
  if [ -n "$socket" ]; then
    /usr/bin/curl --silent --show-error --max-time 5 --unix-socket "$socket" \
      -X POST -H 'Content-Type: application/json' -d '{"state":"HardStop"}' \
      http://localhost/vm/state >/dev/null || true
    # The REST listener may not exist yet. LaunchServices starts the app in
    # another process group, so forward termination to this session explicitly.
    for ((attempt = 0; attempt < 50; attempt++)); do
      while read -r pid; do
        [ -n "$pid" ] && kill -TERM "$pid" 2>/dev/null || true
      done < <(app_pids)
      kill -0 "$app_wait" 2>/dev/null || break
      sleep 0.1
    done
    while read -r pid; do
      [ -n "$pid" ] && kill -KILL "$pid" 2>/dev/null || true
    done < <(app_pids)
  fi
  kill -KILL "$app_wait" 2>/dev/null || true
  wait "$app_wait" 2>/dev/null || true
  exit "$1"
}
trap 'stop 130' INT
trap 'stop 143' TERM
wait "$app_wait"
