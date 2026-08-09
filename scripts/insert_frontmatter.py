#!/usr/bin/env python3
"""Emit SKILL.md frontmatter from a skill.nix meta dump.

Driven by migrate-to-md-first.sh via env vars:
  META_JSON  json of the evaluated skill.nix attrset
  NAME       skill directory name
  MD         path to SKILL.md to prepend to; empty/unset = dry run (print)
"""
import json
import os

meta = json.loads(os.environ["META_JSON"])
name = os.environ["NAME"]
md_path = os.environ.get("MD", "")

assert meta["name"] == name, f"{name}: skill.nix name != directory name"
desc = meta["description"]
assert "\n" not in desc, f"{name}: description must be single-line"
assert 1 <= len(desc) <= 1024, f"{name}: description must be 1-1024 chars"


def yaml_scalar(s: str) -> str:
    """Quote only when a plain YAML scalar would be ambiguous."""
    needs_quote = (
        ": " in s
        or " #" in s
        or s.endswith(":")
        or s[0] in "\"'>|&*!%@`[]{},#- "
    )
    if needs_quote:
        return '"' + s.replace("\\", "\\\\").replace('"', '\\"') + '"'
    return s


lines = ["---", f"name: {name}", f"description: {yaml_scalar(desc)}"]
tools = meta.get("allowed-tools", [])
if tools:
    # Space-separated is the spec's portable form; entries with internal
    # spaces (e.g. "Bash(sem diff:*)") force the comma form, which Claude
    # Code also accepts.
    sep = ", " if any(" " in t for t in tools) else " "
    lines.append(f"allowed-tools: {sep.join(tools)}")
lines.append("---")
frontmatter = "\n".join(lines)

if not md_path:
    print(f"### {name}\n{frontmatter}\n")
else:
    with open(md_path) as fh:
        body = fh.read().lstrip("\n")
    with open(md_path, "w") as fh:
        fh.write(frontmatter + "\n\n" + body)
    print(f"migrated: {name}")
