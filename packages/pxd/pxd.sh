#!/usr/bin/env bash
# pxd — pixeldrain.com CLI (upload/download/info/list/delete)
#
# Auth resolution order:
#   1. $PIXELDRAIN_API_KEY
#   2. /run/agenix/pixeldrain_api_key  (agenix on NixOS / nix-darwin)
#   3. $XDG_CONFIG_HOME/pixeldrain/api_key  (default: ~/.config/pixeldrain/api_key)
# If none found, falls back to anonymous mode (uploads work but are not associated
# with your account — recommended to set up the agenix secret).

set -euo pipefail

API="https://pixeldrain.com/api"

usage() {
  cat <<'EOF'
pxd — pixeldrain.com CLI

Usage:
  pxd put <file> [<name>]      Upload file (PUT method, preferred). <name> defaults to basename.
  pxd get <id> [<output>]      Download file by ID. <output> defaults to basename from response.
  pxd info <id> [<id>...]      Fetch file metadata (comma-batched, max 1000 IDs per request).
  pxd rm <id>                  Delete file by ID (must own it).
  pxd ls                       List your uploaded files (requires auth).
  pxd ls-lists                 List your file collections (requires auth).
  pxd thumb <id> [<w>x<h>]     Download PNG thumbnail. WxH defaults to 128x128 (must be /16).

Environment:
  PIXELDRAIN_API_KEY            API key. Takes precedence over file lookups.
  XDG_CONFIG_HOME               Honored for the config dir fallback.
EOF
}

die() { echo "pxd: $*" >&2; exit 1; }

# Resolve API key. Empty string means anonymous mode.
resolve_key() {
  if [ -n "${PIXELDRAIN_API_KEY:-}" ]; then
    printf '%s' "$PIXELDRAIN_API_KEY"
    return
  fi
  if [ -r "/run/agenix/pixeldrain_api_key" ]; then
    tr -d '\n' < /run/agenix/pixeldrain_api_key
    return
  fi
  local cfg="${XDG_CONFIG_HOME:-$HOME/.config}/pixeldrain/api_key"
  if [ -r "$cfg" ]; then
    tr -d '\n' < "$cfg"
    return
  fi
  printf ''   # anonymous mode
}

# Build the basic-auth header value if we have a key.
auth_args() {
  local k; k=$(resolve_key)
  if [ -n "$k" ]; then
    echo "-u"
    echo ":$k"
  fi
}

cmd_put() {
  local file="${1:-}"
  [ -n "$file" ] || die "put requires a file path"
  [ -r "$file" ] || die "cannot read $file"
  local name="${2:-$(basename "$file")}"
  # URL-encode the name safely. jq handles RFC3986 reserved chars.
  local enc; enc=$(jq -rn --arg s "$name" '$s | @uri')
  # shellcheck disable=SC2046
  curl -sf $(auth_args) \
    -X PUT \
    -H "Content-Type: application/octet-stream" \
    --data-binary "@$file" \
    "$API/file/$enc"
  echo  # trailing newline (the API returns no \n)
}

cmd_get() {
  local id="${1:-}"
  [ -n "$id" ] || die "get requires a file ID"
  local out="${2:-}"
  if [ -z "$out" ]; then
    # Pull the filename from info{}, fall back to <id>.bin
    out=$(cmd_info "$id" 2>/dev/null | jq -r '.name // empty' || true)
    [ -n "$out" ] || out="$id.bin"
  fi
  # shellcheck disable=SC2046
  curl -sf $(auth_args) -L "$API/file/$id" -o "$out"
  echo "$out"
}

cmd_info() {
  local first="${1:-}"
  [ -n "$first" ] || die "info requires at least one ID"
  # API supports comma-separated IDs (max 1000); we just join all args.
  local joined; joined=$(printf "%s," "$@")
  joined="${joined%,}"
  # shellcheck disable=SC2046
  curl -sf $(auth_args) "$API/file/$joined/info"
  echo
}

cmd_rm() {
  local id="${1:-}"
  [ -n "$id" ] || die "rm requires a file ID"
  # shellcheck disable=SC2046
  curl -sf $(auth_args) -X DELETE "$API/file/$id"
  echo
}

cmd_ls() {
  local k; k=$(resolve_key)
  [ -n "$k" ] || die "ls requires auth (set PIXELDRAIN_API_KEY or configure /run/agenix/pixeldrain_api_key)"
  curl -sf -u ":$k" "$API/user/files"
  echo
}

cmd_ls_lists() {
  local k; k=$(resolve_key)
  [ -n "$k" ] || die "ls-lists requires auth"
  curl -sf -u ":$k" "$API/user/lists"
  echo
}

cmd_thumb() {
  local id="${1:-}"
  [ -n "$id" ] || die "thumb requires a file ID"
  local size="${2:-128x128}"
  local w h
  IFS=x read -r w h <<<"$size"
  # shellcheck disable=SC2046
  curl -sf $(auth_args) -L "$API/file/$id/thumbnail?width=$w&height=$h" -o "thumb_$id.png"
  echo "thumb_$id.png"
}

case "${1:-help}" in
  put)       shift; cmd_put "$@" ;;
  get)       shift; cmd_get "$@" ;;
  info)      shift; cmd_info "$@" ;;
  rm)        shift; cmd_rm "$@" ;;
  ls)        shift; cmd_ls "$@" ;;
  ls-lists)  shift; cmd_ls_lists "$@" ;;
  thumb)     shift; cmd_thumb "$@" ;;
  help|-h|--help) usage ;;
  *) usage; exit 2 ;;
esac
