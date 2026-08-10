---
name: format-nix
description: Format all Nix files in the project with nixfmt
disable-model-invocation: true
argument-hint: "[directory]"
allowed-tools: Bash(nixfmt:*) Bash(fd:*)
---

Format all Nix files using nixfmt.

If an argument is provided, format files in that directory.
Otherwise, format all .nix files in the current directory.

Use: fd -e nix -x nixfmt

$ARGUMENTS
