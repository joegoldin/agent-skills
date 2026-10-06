---
name: nix-helper
description: Lint and format Nix code with statix and nixfmt while developing or reviewing it. Use when writing, changing or reviewing .nix files for correctness; for a format-only request just run nixfmt on the files asked about.
allowed-tools: Bash(statix:*) Bash(nixfmt:*)
---

# Nix helper

When you change or review Nix code:

1. Run `statix check` on the changed files and fix what it reports within the
   scope of the task. Leave findings in untouched code alone and mention them.
2. Format the changed files with `nixfmt`, and only those, so the diff stays
   about the change.

For questions about options and packages, the nixos MCP server answers from
the real option and package sets; prefer it to recalling option names. The
nixd language server is available for definitions and evaluation errors.
