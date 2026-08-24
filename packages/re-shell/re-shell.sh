#!/usr/bin/env bash
# Launcher for the `re-shell` reverse-engineering environment. Installed
# globally by the reverse-engineering skill's sidecar so the shell can be
# entered from any directory without a checkout of agent-skills.
#
# On Linux it is `nix develop` on the devShell. On macOS the shell cannot run
# natively — it is x86_64-linux and a third of it needs Linux kernel interfaces
# — so it runs in a disposable vfkit microVM that shares this directory as
# /work and powers off when the shell exits. See lib/re-vm.nix.
set -euo pipefail

flake=${RE_SHELL_FLAKE:-github:joegoldin/agent-skills}
state_dir=${RE_SHELL_STATE_DIR:-${XDG_DATA_HOME:-$HOME/.local/share}/re-shell}
refresh=

usage() {
  cat <<EOF
Usage: re-shell [-f FLAKE] [-r] [command [args...]]

Enters the agent-skills reverse-engineering environment in the current
directory. With no command, starts an interactive shell in it; otherwise runs
the command in it and exits with the command's status.

Options:
  -f FLAKE   Flake reference to take the shell from
             (default: \$RE_SHELL_FLAKE, else $flake).
             Use '-f .' to work against a local agent-skills checkout.
  -r         Rebuild rather than reuse the cached macOS VM runner.
  -h         Show this help.

The environment is large and unfree; the first entry downloads several GB.

macOS specifics:
  The shell runs in a microVM. Only the launch directory is visible to it, as
  /work; the guest's nix store persists in \$RE_SHELL_STATE_DIR
  ($state_dir) so the download happens once. Tune with
  RE_SHELL_CPUS (default 6), RE_SHELL_MEM in MiB (default 8192), and
  RE_SHELL_STORE_SIZE in MiB (default 81920). Ghidra's GUI needs a display the
  guest does not have — drive it headless (ghidra-analyzeHeadless, pyghidra).
EOF
}

while getopts ':f:rh' opt; do
  case $opt in
    f) flake=$OPTARG ;;
    r) refresh=1 ;;
    h)
      usage
      exit 0
      ;;
    :)
      echo "re-shell: -$OPTARG requires an argument" >&2
      exit 2
      ;;
    ?)
      echo "re-shell: unknown option -$OPTARG" >&2
      usage >&2
      exit 2
      ;;
  esac
done
shift $((OPTIND - 1))

if ! command -v nix >/dev/null 2>&1; then
  echo "re-shell: nix is not on PATH; the shell is a nix devShell" >&2
  exit 127
fi

if [ "$(uname -s)" != Darwin ]; then
  # Run the user's own shell rather than the devShell's bash: the environment
  # is exported either way, and dropping into a foreign shell loses their
  # prompt, history, and aliases mid-analysis.
  if [ "$#" -eq 0 ]; then
    set -- "${SHELL:-bash}"
  fi
  exec nix develop "$flake#re-shell" --command "$@"
fi

# ── macOS: run the shell in a microVM ──

case $(uname -m) in
  arm64) ;;
  *)
    echo "re-shell: macOS support needs Apple silicon (Virtualization.framework + Rosetta)" >&2
    exit 1
    ;;
esac

workdir=$PWD
# A path flake reference is meaningless inside the guest, so a local checkout
# travels as a share instead. Anything else (github:, git+ssh:) is fetched by
# the guest over NAT.
flake_dir_nix=null
flake_src=$flake
case $flake in
  .|./*|/*|../*)
    flake_dir=$(cd "$flake" && pwd)
    flake_dir_nix="\"$flake_dir\""
    # git+file, not path:, so the runner is built from the tracked tree rather
    # than from whatever result symlinks and scratch dirs are lying around.
    flake_src="git+file://$flake_dir"
    ;;
esac

# Per-directory session state: the control share carries the command in and the
# exit status back out, and the runner symlink is both a build cache and the gc
# root that keeps the guest closure alive.
session_id=$(printf '%s' "$workdir" | sha256sum | cut -c1-16)
ctl_dir="$state_dir/sessions/$session_id"
mkdir -p "$ctl_dir" "$state_dir/sockets"
rm -f "$ctl_dir/cmd" "$ctl_dir/status"
if [ "$#" -gt 0 ]; then
  # %q so the guest's `bash -lc` sees the arguments this shell saw, not a
  # re-split approximation of them.
  printf '%q ' "$@" > "$ctl_dir/cmd"
fi

runner_link="$ctl_dir/runner"
if [ -n "$refresh" ] || [ ! -e "$runner_link" ]; then
  cat > "$ctl_dir/vm.nix" <<EOF
(builtins.getFlake "$flake_src").lib.mkReShellVm {
  workdir = "$workdir";
  stateDir = "$state_dir";
  ctlDir = "$ctl_dir";
  socketPath = "$state_dir/sockets/$session_id.sock";
  flakeRef = "$flake";
  flakeDir = $flake_dir_nix;
  hostSystem = "aarch64-darwin";
  vcpu = ${RE_SHELL_CPUS:-6};
  mem = ${RE_SHELL_MEM:-8192};
  storeSize = ${RE_SHELL_STORE_SIZE:-81920};
}
EOF
  nix build --impure --out-link "$runner_link" --file "$ctl_dir/vm.nix"
fi

# vfkit's stdio console is a real terminal device: without a tty it fails with
# "operation not supported by device" before the guest ever boots. Non-interactive
# callers (agents, CI, `re-shell cmd | tee`) get one from script(1).
if [ -t 0 ]; then
  if [ "$#" -eq 0 ]; then
    # Ctrl-C would otherwise be interpreted by this terminal and caught by
    # vfkit, which shuts the guest down — so interrupting a running tool would
    # end the whole session. Handing the intr key to the guest instead makes
    # Ctrl-C mean what it means in any other shell, and leaves Ctrl-] as the
    # way out if the VM stops responding.
    saved_stty=$(stty -g)
    trap 'stty "$saved_stty" 2>/dev/null' EXIT INT TERM
    stty intr '^]'
    echo "re-shell: Ctrl-C goes to the guest; Ctrl-] kills the VM" >&2
  fi
  "$runner_link/bin/microvm-run"
else
  script -q /dev/null "$runner_link/bin/microvm-run" >/dev/null
fi

# A command's output and status come back through the control share rather than
# the console, which also carries the guest's boot log.
if [ -e "$ctl_dir/out" ]; then
  cat "$ctl_dir/out"
  rm -f "$ctl_dir/out"
fi
if [ -e "$ctl_dir/err" ]; then
  cat "$ctl_dir/err" >&2
  rm -f "$ctl_dir/err"
fi
if [ -r "$ctl_dir/status" ]; then
  status=$(cat "$ctl_dir/status")
  rm -f "$ctl_dir/status" "$ctl_dir/cmd"
  exit "$status"
fi
if [ -e "$ctl_dir/cmd" ]; then
  rm -f "$ctl_dir/cmd"
  echo "re-shell: the VM exited without running the command" >&2
  exit 1
fi
