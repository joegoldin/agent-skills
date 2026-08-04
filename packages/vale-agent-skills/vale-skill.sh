#!/usr/bin/env bash
# vale-skill — run Vale with one of the writing profiles this plugin ships.
#
# Vale does the linting; this only picks the .vale.ini. Every argument after the
# profile is handed straight to vale, so `--output=JSON`, `--minAlertLevel`,
# `--glob` and friends all work as usual. To drive vale yourself:
#
#     vale --config="$(vale-skill --config ai-writing)" draft.md
set -euo pipefail

self=$(basename "$0")
share=$(dirname "$(readlink -f "$0")")/../share/vale-agent-skills
CONFIGS=${VALE_SKILL_CONFIGS:-$share/configs}

profiles() {
  cat <<'EOF'
  ai-writing               strip AI writing patterns (blog defaults)
  ai-writing:linkedin      short-form social; formatting rules relax
  ai-writing:technical     code-adjacent prose; technical word senses allowed
  ai-writing:investor      high-trust audience; inflation escalates to errors
  ai-writing:docs          documentation; clarity over voice
  ai-writing:casual        Slack and notes; credibility killers only
  simple-english           ASD-STE100, descriptive text (25-word sentences)
  simple-english:procedural  ASD-STE100, instructions (20 words, condition first)
  simple-english:strict    ASD-STE100 with vocabulary discipline
  diataxis:tutorial        a lesson: no choices, no theory, guaranteed outcome
  diataxis:how-to          a recipe: goal-shaped, no lesson framing
  diataxis:reference       description of the machinery: neutral, no steps
  diataxis:explanation     discussion: context and alternatives, no procedure
  docs                     general docs quality (Google, write-good, alex)
EOF
}

usage() {
  cat <<EOF
usage: $self <profile> [vale options] [file...]
       $self --list
       $self --config <profile>      print the .vale.ini path
       $self --init <profile> [dir]  write the profile as <dir>/.vale.ini

profiles:
$(profiles)
EOF
}

config_for() {
  local profile=$1 file
  case $profile in
    ai-writing | ai-writing:*) file=avoid-ai${profile#ai-writing} ;;
    *) file=$profile ;;
  esac
  file=${file//:/-}.ini
  if [ ! -f "$CONFIGS/$file" ]; then
    echo "$self: unknown profile '$profile'" >&2
    echo "run '$self --list' for the profiles this plugin ships" >&2
    return 1
  fi
  printf '%s\n' "$CONFIGS/$file"
}

case ${1-} in
  '' | -h | --help)
    usage
    [ -n "${1-}" ] || exit 1
    exit 0
    ;;
  --list)
    profiles
    exit 0
    ;;
  --config)
    [ -n "${2-}" ] || { echo "$self: --config needs a profile" >&2; exit 1; }
    config_for "$2"
    exit 0
    ;;
  --init)
    [ -n "${2-}" ] || { echo "$self: --init needs a profile" >&2; exit 1; }
    src=$(config_for "$2")
    dir=${3:-.}
    dest=$dir/.vale.ini
    [ -e "$dest" ] && { echo "$self: $dest already exists" >&2; exit 1; }
    {
      echo "# Written by \`$self --init $2\`."
      echo "# Styles resolve through VALE_STYLES_PATH, which the packaged vale sets."
      cat "$src"
    } > "$dest"
    echo "wrote $dest"
    exit 0
    ;;
esac

config=$(config_for "$1")
shift
exec vale --config="$config" "$@"
