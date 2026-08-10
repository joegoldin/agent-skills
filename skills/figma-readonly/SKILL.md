---
name: figma-readonly
description: Use when reading a Figma design from the terminal — the user pastes a figma.com URL or asks to extract colors, spacing, fonts, layout specs, node JSON, rendered PNGs, layer ids, or design comments from a Figma file, especially headless or with an agenix/file-based token, or when a Figma MCP is unavailable or rejects the file with an edit-access error.
allowed-tools: Bash(figr) Bash(figr:*)
---

# figma-readonly — read Figma designs from the terminal via the REST API

The bundled `figr` CLI is a strictly read-only Figma client (every request is a GET). It turns a pasted figma.com URL into layout specs, raw JSON, rendered images, layer searches, or design comments — no browser, no MCP, no edit access required. View access on the file is enough.

## When to use

- User pastes a `https://www.figma.com/design/...?node-id=...` URL and wants the design inspected, diffed against code, or exported.
- Extracting exact colors (hex + opacity), padding, item spacing, corner radii, font family/weight/size, or text content from a design node.
- A Figma MCP is unavailable, or fails with "you don't have edit access to this file" — the REST API works with view-only access.
- Headless/agent environments where the token lives in a file (agenix secret) rather than a browser session.

## Auth

`figr` resolves the token in this order:

1. `--token-file PATH` — explicit flag (preferred with agenix)
2. `$FIGMA_TOKEN_FILE` — path to a file containing the token
3. `$FIGMA_TOKEN` — raw token value
4. `/run/agenix/figma_token` (agenix on NixOS / nix-darwin)
5. `$XDG_CONFIG_HOME/figma/token` (default `~/.config/figma/token`)

The token is a Figma personal access token with the `file_read` scope. The file must be viewable by the token's account. Verify auth with `figr me`.

## Commands

Every `TARGET` is either a full figma.com URL (node id parsed from `?node-id=`, `1-2` normalized to `1:2`, branch URLs handled) or `FILE_KEY [NODE_ID]`.

```bash
figr spec TARGET [--depth N]     # human-readable tree: sizes, fills/strokes (hex+alpha),
                                 # radii, padding, gaps, layout mode, fonts, text, override flags
figr json TARGET [--depth N] [-o out.json]   # raw API JSON (file or node)
figr png TARGET [-o out.png] [--scale 0.5-4] [--format png|svg|jpg|pdf]
figr meta TARGET                 # file name, last modified, page list
figr find PATTERN TARGET         # search layer names → node ids + paths
figr comments TARGET             # design discussion: full text, newest thread first,
                                 # replies indented with ↳, [resolved] marked. Comments are
                                 # file-wide — a node id in the target is ignored.
figr me                          # verify token; prints account handle/email. Cheap — safe
                                 # to call anytime, not part of the file-content rate budget.
```

## Recipes

Design-to-code diff (the main workflow): render the node for the eyes, dump the spec for exact values:

```bash
figr png "$URL" -o /tmp/design.png     # look at it
figr spec "$URL" --depth 6             # exact hexes, paddings, gaps, font sizes
```

Find a specific layer's node id when you only have the file URL:

```bash
figr find "button" "$URL"
```

Check what designers said before implementing:

```bash
figr comments "$URL"
```

## Rate limits (will bite you)

Figma's file-content endpoints (`spec`, `json`, `find`, `meta`) share a small per-minute budget on non-enterprise plans — a burst of 3-4 calls can trigger long 429 cooldowns (minutes). `png` (`/images`) and `comments` have separate budgets. So: fetch once with generous `--depth`, save with `json -o`, and re-read the file instead of re-fetching. Space unavoidable repeat calls by minutes, not seconds.

## Gotchas

- `spec`/`find` on a whole file (no node id) downloads the entire document — can be huge and eats the rate budget. Prefer node-scoped targets or `--depth`.
- Colors print as `#rrggbb/alpha` (alpha omitted when 1). Fills marked `visible: false` in Figma are skipped.
- Text with mixed styling shows an `overrides=` flag (`bold-span`, `underline-span`, `color-span`, `link-span`); use `figr json` on that node for per-character detail.
- The Variables API is Enterprise-only, so `figr` doesn't wrap it.
