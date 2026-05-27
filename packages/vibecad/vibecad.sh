#!/usr/bin/env bash
# vibecad — agentic OpenSCAD iteration helper
# Subcommands: init <name>, render [<name>], views [<name>], revise [<name>]

set -euo pipefail

SHARE="${VIBECAD_SHARE:-$(dirname "$(readlink -f "$0")")/../share/vibecad}"

usage() {
  cat <<'EOF'
vibecad — agentic OpenSCAD iteration helper

Usage:
  vibecad init <design-name>        Scaffold designs/<name>/ with model.scad + rev_0001.json
  vibecad render [<design-name>]    Render current revision to STL (designs/<name>/output/rev_NNNN.stl)
  vibecad views [<design-name>]     Render 16 turntable PNG views (designs/<name>/output/rev_NNNN/view_<NN>.png)
  vibecad revise [<design-name>]    Create rev_NNNN+1.json inheriting from current rev
  vibecad current [<design-name>]   Print current revision number

If <design-name> is omitted, vibecad uses the design in the current working dir
(must contain a model.scad and at least one rev_*.json).
EOF
}

die() { echo "vibecad: $*" >&2; exit 1; }

# Resolve <design-dir> from either an explicit name (looked up under ./designs/<name>)
# or from the current working dir (must already look like a design dir).
resolve_design_dir() {
  local name="${1:-}"
  if [ -n "$name" ]; then
    if [ -d "designs/$name" ]; then echo "designs/$name"; return; fi
    if [ -d "$name" ]; then echo "$name"; return; fi
    die "design '$name' not found (looked at designs/$name and $name)"
  fi
  if [ -f "model.scad" ]; then echo "."; return; fi
  die "no design name given and no model.scad in CWD"
}

# Find current rev_NNNN.json (lex-sorted last match)
current_rev() {
  local dir="$1"
  ls "$dir"/rev_*.json 2>/dev/null | sort | tail -1 || true
}

cmd_init() {
  local name="${1:-}"
  [ -n "$name" ] || die "init requires a design name"
  local dir="designs/$name"
  [ ! -e "$dir" ] || die "$dir already exists"
  mkdir -p "$dir/output"
  cat > "$dir/model.scad" <<'SCAD'
// Edit this — read parameters from rev_NNNN.json via the agent.
$fn = 64;
cube([20, 20, 20], center = true);
SCAD
  cat > "$dir/rev_0001.json" <<'JSON'
{
  "comment": "Initial revision. Add your parameters here; the agent reads this when rendering.",
  "params": {}
}
JSON
  echo "scaffolded $dir/"
  echo "  model.scad   — edit OpenSCAD source"
  echo "  rev_0001.json — add parameters here"
}

cmd_render() {
  local dir; dir=$(resolve_design_dir "${1:-}")
  local rev; rev=$(current_rev "$dir")
  [ -n "$rev" ] || die "no rev_*.json in $dir — run 'vibecad init <name>' first"
  local base; base=$(basename "$rev" .json)
  local out="$dir/output/$base.stl"
  mkdir -p "$dir/output"
  # Read params from rev_*.json and pass each as -D key=value to openscad.
  local args=()
  while IFS=$'\t' read -r k v; do
    args+=( -D "$k=$v" )
  done < <(jq -r '(.params // {}) | to_entries[] | [.key, (.value | tojson)] | @tsv' "$rev")
  openscad "${args[@]}" -o "$out" "$dir/model.scad"
  echo "wrote $out"
}

cmd_views() {
  local dir; dir=$(resolve_design_dir "${1:-}")
  local rev; rev=$(current_rev "$dir")
  [ -n "$rev" ] || die "no rev_*.json in $dir — run 'vibecad init <name>' first"
  local base; base=$(basename "$rev" .json)
  local outdir="$dir/output/$base"
  mkdir -p "$outdir"
  local args=()
  while IFS=$'\t' read -r k v; do
    args+=( -D "$k=$v" )
  done < <(jq -r '(.params // {}) | to_entries[] | [.key, (.value | tojson)] | @tsv' "$rev")
  # views.py prints 16 camera specs separated by newlines.
  local i=0
  while IFS= read -r cam; do
    i=$((i+1))
    local png; png=$(printf "%s/view_%02d.png" "$outdir" "$i")
    openscad "${args[@]}" --camera="$cam" --imgsize=800,600 --colorscheme=Tomorrow -o "$png" "$dir/model.scad"
  done < <(python3 "$SHARE/views.py")
  echo "wrote 16 views under $outdir/"
}

cmd_revise() {
  local dir; dir=$(resolve_design_dir "${1:-}")
  local cur; cur=$(current_rev "$dir")
  [ -n "$cur" ] || die "no rev_*.json in $dir — run 'vibecad init <name>' first"
  local n; n=$(basename "$cur" .json | sed 's/^rev_//')
  local next; next=$(printf "rev_%04d.json" $((10#$n + 1)))
  cp "$cur" "$dir/$next"
  echo "$dir/$next"
}

cmd_current() {
  local dir; dir=$(resolve_design_dir "${1:-}")
  current_rev "$dir" || die "no revisions found in $dir"
}

case "${1:-help}" in
  init)    shift; cmd_init "$@" ;;
  render)  shift; cmd_render "$@" ;;
  views)   shift; cmd_views "$@" ;;
  revise)  shift; cmd_revise "$@" ;;
  current) shift; cmd_current "$@" ;;
  help|-h|--help) usage ;;
  *) usage; exit 2 ;;
esac
