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
       $self score [profile] <file...>   0-100 AI-writing score
       $self --list
       $self --config <profile>      print the .vale.ini path
       $self --init <profile> [dir]  write the profile as <dir>/.vale.ini

profiles:
$(profiles)
EOF
}

# Weights per rule, carried over from the avoid-ai-detect scoring model so the
# number means what it used to. Anything unlisted scores 2, which is what that
# model used as its fallback. Vale does the detection; this only adds up.
weights() {
  cat <<'EOF'
AvoidAI.CitationMarkup 15
AvoidAI.BoilerplateCluster 12
AvoidAI.FutureNarrative 12
AvoidAI.Hashtags 12
AvoidAI.TrackingParams 12
AvoidAI.CutoffDisclaimer 10
AvoidAI.Placeholders 10
AvoidAI.BulletNounPhrases 10
AvoidAI.Homoglyphs 9
AvoidAI.ChatArtifacts 8
AvoidAI.Sycophancy 8
AvoidAI.SocialEndorsement 8
AvoidAI.FormulaicOpener 8
AvoidAI.HedgeStack 6
AvoidAI.ReasoningArtifacts 6
AvoidAI.SmartPunctSignature 6
AvoidAI.PunctuationDistribution 6
AvoidAI.Tier1 5
AvoidAI.TechnicalExceptions 5
AvoidAI.Attribution 5
AvoidAI.RealActualInflation 5
AvoidAI.SentenceUniformity 5
AvoidAI.ParagraphUniformity 5
AvoidAI.CrossParagraphRhythm 5
AvoidAI.GrammarRepetition 5
AvoidAI.SignificanceInflation 4
AvoidAI.EmDash 4
AvoidAI.EmDashBudget 4
AvoidAI.HeadingCase 4
AvoidAI.Tier2 3
AvoidAI.Tier2Cluster 3
AvoidAI.Boilerplate 3
AvoidAI.GenericConclusion 3
AvoidAI.AcknowledgmentLoop 3
AvoidAI.Novelty 3
AvoidAI.Templates 3
AvoidAI.VocabularyDiversity 3
AvoidAI.BoldOveruse 3
AvoidAI.Emoji 3
AvoidAI.ListLabelPeriods 3
AvoidAI.ExcessiveStructure 3
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

score() {
  profile=ai-writing
  if [ -n "${1-}" ] && [ ! -e "$1" ]; then
    profile=$1
    shift
  fi
  [ "$#" -gt 0 ] || { echo "$self: score needs at least one file" >&2; exit 1; }

  config=$(config_for "$profile") || exit 1

  files=""
  for a in "$@"; do
    [ -f "$a" ] && files="$files $a"
  done
  [ -n "$files" ] || { echo "$self: no readable files given" >&2; exit 1; }
  # shellcheck disable=SC2086
  total_words=$(wc -w $files | tail -1 | awk '{print $1}')

  {
    weights
    echo "@@@"
    # One line per alert, deduplicated by (rule, message) the way the original
    # scoring model deduplicated by (type, text), then counted per rule.
    vale --config="$config" --no-exit --output=line "$@" |
      sed -E 's/^.*:[0-9]+:[0-9]+:([A-Za-z0-9_.-]+):(.*)$/\1\t\2/' |
      sort -u |
      cut -f1 |
      sort |
      uniq -c
  } | awk -v words="$total_words" -v profile="$profile" '
      /^@@@$/ { mode = 1; next }
      mode == 0 { weight[$1] = $2; next }
      { counts[$2] = $1 }
      END {
        raw = 0
        for (rule in counts) {
          w = (rule in weight) ? weight[rule] : 2
          points[rule] = w * counts[rule]
          raw += points[rule]
        }
        # Longer texts get more chances to trigger, so normalize by
        # log2(words/50) exactly as the original detector did.
        factor = log(words / 50.0) / log(2)
        if (factor < 1) factor = 1
        s = int(raw / factor + 0.5)
        if (s > 100) s = 100

        label = "Heavy AI patterns"
        if (s == 0)       label = "Clean"
        else if (s <= 15) label = "Minimal AI signals"
        else if (s <= 35) label = "Some AI patterns"
        else if (s <= 60) label = "Moderate AI signals"
        else if (s <= 80) label = "Strong AI signals"

        printf "AI-writing score: %d/100 - %s\n", s, label
        printf "%s profile, %d words, %d weighted signals\n", profile, words, raw
        if (raw == 0) exit
        printf "\n%8s  %-34s %s\n", "points", "rule", "hits x weight"

        # Heaviest contributor first. Small array, so an insertion sort keeps
        # this portable across awk implementations (no asorti in mawk).
        n = 0
        for (rule in counts) { n++; order[n] = rule }
        for (i = 2; i <= n; i++) {
          key = order[i]
          j = i - 1
          while (j >= 1 && points[order[j]] < points[key]) { order[j+1] = order[j]; j-- }
          order[j+1] = key
        }
        for (i = 1; i <= n; i++) {
          rule = order[i]
          w = (rule in weight) ? weight[rule] : 2
          printf "%8d  %-34s %d x %d\n", points[rule], rule, counts[rule], w
        }
      }
    '
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
  score)
    shift
    score "$@"
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
