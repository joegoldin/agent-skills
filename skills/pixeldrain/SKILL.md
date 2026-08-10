---
name: pixeldrain
description: Use when the user wants to upload, share, or fetch files via pixeldrain.com — file hosting, link sharing, byte-range downloads, thumbnails, or managing their pixeldrain account.
allowed-tools: Bash(pxd) Bash(pxd:*)
---

# pixeldrain — upload, share, fetch files via the pixeldrain.com API

Pixeldrain is a free file-hosting service with a clean HTTP API and per-file shareable URLs. This skill teaches the API contract; the bundled `pxd` CLI wraps `curl` so you don't have to assemble auth headers and multipart bodies by hand.

## When to use

- User asks to "upload this file", "share this somewhere", "host this on pixeldrain", or pastes a `https://pixeldrain.com/u/<id>` link they want you to fetch.
- User wants to mirror a small file (under a few hundred MB) somewhere with a short URL.
- User wants byte-range fetches or thumbnails of an existing pixeldrain file.

If the file is larger than ~1 GB or contains secrets, ask first — pixeldrain links are unguessable but publicly accessible.

## Auth

The `pxd` CLI resolves an API key in this order, falling back to anonymous mode if none is found:

1. `$PIXELDRAIN_API_KEY` env var.
2. `/run/agenix/pixeldrain_api_key` (NixOS/nix-darwin agenix decryption — preferred on this user's hosts).
3. `$XDG_CONFIG_HOME/pixeldrain/api_key` (default `~/.config/pixeldrain/api_key`).

Anonymous uploads work but aren't associated with the user's account. Most operations the user asks for (`pxd ls`, `pxd rm`) require auth.

## Commands

```bash
pxd put <file> [<name>]        # Upload via PUT. <name> defaults to basename.
pxd get <id> [<output>]        # Download by ID. Output filename inferred from /info if omitted.
pxd info <id> [<id>...]        # Metadata (size, name, mime, date_upload, views, downloads, etc.).
pxd rm <id>                    # Delete (owner only).
pxd ls                         # List the user's uploaded files (requires auth).
pxd ls-lists                   # List the user's file collections.
pxd thumb <id> [<w>x<h>]       # Download PNG thumbnail. WxH must be multiples of 16 (default 128x128).
```

## Recipes

### Upload and share

```bash
ID=$(pxd put ./report.pdf)
echo "https://pixeldrain.com/u/$ID"
```

The `put` command echoes only the file ID. The shareable URL is always `https://pixeldrain.com/u/<id>`.

### Batch metadata for multiple files

```bash
pxd info aBc123 deF456 gHi789 | jq '.files[] | {name, size, downloads}'
```

The API accepts up to 1000 comma-separated IDs per request — `pxd info` does this automatically when you pass multiple args.

### Range download (resume / partial fetch)

`pxd get` uses `curl -L` and accepts range manually:

```bash
curl -L -H "Range: bytes=0-1023" "https://pixeldrain.com/api/file/<id>" -o head.bin
```

For most use cases just `pxd get <id>` is enough.

### Download a thumbnail

```bash
pxd thumb aBc123 256x256   # writes thumb_aBc123.png
```

## Rate limiting

Pixeldrain doesn't publish blanket API rate limits, but **downloads are throttled when a file's download:view ratio exceeds 3:1**. The download page then requires a captcha. File owners bypass this. If a `pxd get` 429s or returns a captcha page, that's why — fall back to the user opening the URL in a browser.

## When uploads might be inappropriate

- **Secrets / credentials.** The URL is unguessable but not encrypted. Refuse and tell the user.
- **Files over ~2 GB.** Pixeldrain's max is generous but uploads can fail mid-stream; warn the user and suggest splitting.
- **Files the user can't legally redistribute.** Make a judgment call; ask if unsure.

## Security & permissions

`pxd` only talks to `https://pixeldrain.com/api/`. It reads the API key from the locations above and never writes it anywhere. Uploads happen via PUT with the file content as the request body (no multipart, no temp files).
