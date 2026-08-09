# md-first agent-skills Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use subagent-driven-development (recommended) or executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make `SKILL.md` (with hand-authored, spec-proper YAML frontmatter, shipped verbatim) the source of truth for every skill; shrink `skill.nix` to an optional sidecar carrying only `packages` / `mcpServers` / `lspServers`.

**Architecture:** A pure-Nix frontmatter parser (`lib/frontmatter.nix`) reads only the three fields the build system consumes (`name`, `description`, `allowed-tools`); everything else passes through in the file untouched, so every current and future Claude Code frontmatter field works with zero plumbing. `discoverSkills` keys on `SKILL.md` instead of `skill.nix`. Subagents move to `agents/*.md`. The three Nix-defined commands become skills (commands are merged into skills in Claude Code). A lint (`lib/lint.nix`) enforces the contract at eval time; flake checks force it.

**Tech Stack:** Nix (flake, pure eval — no IFD), bash/python3 for the one-time migration, existing claude-nix/codex-nix/antigravity-cli-nix plugin libraries (their interfaces are unchanged).

**Design doc:** `docs/plans/2026-08-09-md-first-skills-design.md`

## Global Constraints

- Repo: `~/Development/agent-skills`, branch `main`. All paths below are relative to the repo root.
- No import-from-derivation. The parser and lint run in pure Nix at eval time.
- Frontmatter fields parsed by Nix (`name`, `description`, `allowed-tools`) must be single-line scalars / simple lists. All other fields are never parsed by Nix.
- Portable frontmatter field set (agentskills.io spec, and what claude.ai uploads accept): `name`, `description`, `license`, `compatibility`, `metadata`, `allowed-tools`.
- Claude Code extension field set: `when_to_use`, `argument-hint`, `arguments`, `disable-model-invocation`, `user-invocable`, `disallowed-tools`, `model`, `effort`, `context`, `agent`, `background`, `hooks`, `paths`, `shell`.
- `name` is required in frontmatter and must equal the skill directory name; lowercase alphanumerics and single hyphens only; max 64 chars. `description` is required, single-line, 1–1024 chars.
- `allowed-tools` is authored as a space-separated string by default; comma-separated when any entry contains a space (e.g. `Bash(sem diff:*)`). Block-list YAML form is also accepted by the parser.
- Optional `skill.nix` sidecar may contain ONLY `packages`, `mcpServers`, `lspServers`. It may be an attrset or a function of (a subset of) `{ pkgs, lib }`.
- Format all changed `.nix` files with `nixfmt` before each commit; keep `statix` clean.
- Test commands assume the current system is `aarch64-darwin`; substitute the builder's system in `.#checks.<system>.<name>` if different.
- Flake output names and shapes must not change (`claude-plugin`, `antigravity-plugin`, `codex-plugin`, `web-skills`, `web-skills-zips`, per-skill packages, `homeManagerModules`).

---

### Task 1: Frontmatter parser (`lib/frontmatter.nix`)

**Files:**
- Create: `lib/frontmatter.nix`
- Create: `lib/frontmatter-tests.nix`
- Modify: `flake.nix` (the existing `checks = forAllSystems (...)` attrset, which currently contains `eval-mcp` and `avoid-ai-detect`)

**Interfaces:**
- Produces: `import ./frontmatter.nix { inherit lib; }` →
  - `parse :: string -> { fields :: attrs-of-string; items :: attrs-of-list-of-string; keys :: [string]; body :: string; }` — throws if the text does not start with a `---` frontmatter block.
  - `parseFile :: path -> (same result)`.
  - `parseToolList :: parsed -> string(key) -> [string]` — resolves block-list > comma-separated > space-separated forms.
- Consumed by: Tasks 2 and 4.

- [ ] **Step 1: Write the failing test file**

Create `lib/frontmatter-tests.nix`:

```nix
# Eval-time unit tests for lib/frontmatter.nix. Returns the list of failed
# tests from lib.debug.runTests — empty list means all pass.
{ lib }:
let
  fm = import ./frontmatter.nix { inherit lib; };
  sample = ''
    ---
    name: my-skill
    description: Use when testing the parser
    allowed-tools: Bash(git:*) Read
    context: fork
    ---

    # Body

    ---

    More body after a horizontal rule.
  '';
  commaSample = ''
    ---
    name: comma
    description: "Has: a colon"
    allowed-tools: Bash(sem diff:*), Bash(sem impact:*)
    ---
    body
  '';
  blockSample = ''
    ---
    name: block
    description: Block list tools
    allowed-tools:
      - Bash(git:*)
      - Read
    metadata:
      author: joe
    ---
    body
  '';
in
lib.debug.runTests {
  testName = {
    expr = (fm.parse sample).fields.name;
    expected = "my-skill";
  };
  testKeysInOrder = {
    expr = (fm.parse sample).keys;
    expected = [
      "name"
      "description"
      "allowed-tools"
      "context"
    ];
  };
  testSpaceSeparatedTools = {
    expr = fm.parseToolList (fm.parse sample) "allowed-tools";
    expected = [
      "Bash(git:*)"
      "Read"
    ];
  };
  testBodyKeepsHorizontalRule = {
    expr =
      lib.hasInfix "More body after a horizontal rule." (fm.parse sample).body
      && lib.hasInfix "---" (fm.parse sample).body;
    expected = true;
  };
  testCommaSeparatedTools = {
    expr = fm.parseToolList (fm.parse commaSample) "allowed-tools";
    expected = [
      "Bash(sem diff:*)"
      "Bash(sem impact:*)"
    ];
  };
  testQuotedDescriptionUnwrapped = {
    expr = (fm.parse commaSample).fields.description;
    expected = "Has: a colon";
  };
  testBlockListTools = {
    expr = fm.parseToolList (fm.parse blockSample) "allowed-tools";
    expected = [
      "Bash(git:*)"
      "Read"
    ];
  };
  testNestedMapIgnored = {
    # metadata's nested "author: joe" line must not become a top-level key
    expr = builtins.elem "author" (fm.parse blockSample).keys;
    expected = false;
  };
  testMissingToolsIsEmpty = {
    expr = fm.parseToolList (fm.parse "---\nname: x\ndescription: y\n---\nbody") "allowed-tools";
    expected = [ ];
  };
  testMissingFrontmatterThrows = {
    expr = (builtins.tryEval (fm.parse "# no frontmatter here")).success;
    expected = false;
  };
  testUnterminatedFrontmatterThrows = {
    expr = (builtins.tryEval (fm.parse "---\nname: x\nno closing marker")).success;
    expected = false;
  };
}
```

- [ ] **Step 2: Wire the check into flake.nix**

In `flake.nix`, inside the existing `checks = forAllSystems (...)` returned attrset (the one containing `eval-mcp` and `avoid-ai-detect`), add:

```nix
          frontmatter-tests =
            let
              failures = import ./lib/frontmatter-tests.nix { inherit lib; };
            in
            if failures == [ ] then
              pkgs.runCommand "frontmatter-tests" { } "touch $out"
            else
              throw "frontmatter tests failed: ${builtins.toJSON failures}";
```

- [ ] **Step 3: Run the check to verify it fails**

Run: `cd ~/Development/agent-skills && nix build .#checks.aarch64-darwin.frontmatter-tests 2>&1 | tail -5`
Expected: FAIL — error opening `lib/frontmatter.nix`, "No such file or directory".

- [ ] **Step 4: Implement the parser**

Create `lib/frontmatter.nix`:

```nix
# Pure-Nix parser for the SKILL.md / agents/*.md frontmatter subset the
# build system consumes (name, description, allowed-tools, tools). All other
# frontmatter fields pass through in the shipped file untouched — this
# parser only reads, it never rewrites.
#
# Supported value forms (single-line only):
#   key: plain scalar
#   key: "double-quoted scalar"   (\" and \\ escapes)
#   key: 'single-quoted scalar'
#   key: a b c                    (space-separated tool list)
#   key: a, b, c                  (comma-separated tool list)
#   key:                          (block list)
#     - a
#     - b
# Nested maps (e.g. metadata:) are tolerated and ignored: their indented
# lines are neither top-level keys nor list items of a consumed field.
{ lib }:
rec {
  # Strip surrounding quotes from a scalar and trim whitespace.
  unquote =
    raw:
    let
      s = lib.trim raw;
      dq = builtins.match "\"(.*)\"" s;
      sq = builtins.match "'(.*)'" s;
    in
    if dq != null then
      builtins.replaceStrings [ "\\\"" "\\\\" ] [ "\"" "\\" ] (builtins.head dq)
    else if sq != null then
      builtins.head sq
    else
      s;

  # parse :: string -> { fields; items; keys; body; }
  parse =
    text:
    let
      lines = lib.splitString "\n" text;
      hasFm = lines != [ ] && builtins.head lines == "---";
      rest = if hasFm then builtins.tail lines else [ ];
      endIdx = lib.lists.findFirstIndex (l: l == "---") null rest;
      fmLines = lib.sublist 0 endIdx rest;
      bodyLines = lib.drop (endIdx + 1) rest;
      keyMatch = l: builtins.match "([A-Za-z0-9_-]+):[[:space:]]*(.*)" l;
      itemMatch = l: builtins.match "[[:space:]]+-[[:space:]]+(.*)" l;
      folded = builtins.foldl' (
        acc: line:
        let
          m = keyMatch line;
          item = itemMatch line;
          key = builtins.head m;
        in
        if m != null then
          {
            fields = acc.fields // {
              ${key} = unquote (lib.last m);
            };
            items = acc.items // {
              ${key} = [ ];
            };
            current = key;
            keys = acc.keys ++ [ key ];
          }
        else if item != null && acc.current != null then
          acc
          // {
            items = acc.items // {
              ${acc.current} = acc.items.${acc.current} ++ [ (unquote (builtins.head item)) ];
            };
          }
        else
          # Anything else (nested map lines, blank lines) ends any open
          # block list and is otherwise ignored.
          acc // { current = null; }
      ) { fields = { }; items = { }; current = null; keys = [ ]; } fmLines;
    in
    if !hasFm || endIdx == null then
      throw "agent-skills: file must start with a '---'-delimited YAML frontmatter block"
    else
      {
        inherit (folded) fields items keys;
        body = lib.concatStringsSep "\n" bodyLines;
      };

  parseFile = path: parse (builtins.readFile path);

  # Tool lists: block-list form wins, then comma-separated, then
  # space-separated. Entries containing spaces MUST use the comma or block
  # form (lint enforces this).
  parseToolList =
    parsed: key:
    let
      inline = parsed.fields.${key} or "";
      block = parsed.items.${key} or [ ];
    in
    if block != [ ] then
      block
    else if inline == "" then
      [ ]
    else if lib.hasInfix "," inline then
      map lib.trim (lib.splitString "," inline)
    else
      builtins.filter (t: t != "") (lib.splitString " " inline);
}
```

- [ ] **Step 5: Run the check to verify it passes**

Run: `nix build .#checks.aarch64-darwin.frontmatter-tests && echo OK`
Expected: `OK` (empty failure list; derivation builds).

If a test fails, `runTests` reports `{ name; expected; result; }` triples in the thrown JSON — fix the parser, not the test, unless the test contradicts the contract above.

- [ ] **Step 6: Format and commit**

```bash
nixfmt lib/frontmatter.nix lib/frontmatter-tests.nix flake.nix
git add lib/frontmatter.nix lib/frontmatter-tests.nix flake.nix
git commit -m "feat(lib): pure-Nix SKILL.md frontmatter parser with eval tests"
```

---

### Task 2: Contract lint (`lib/lint.nix`)

**Files:**
- Create: `lib/lint.nix`
- Create: `lib/lint-tests.nix`
- Modify: `flake.nix` (same `checks` attrset as Task 1)

**Interfaces:**
- Consumes: `parse` / `parseToolList` from Task 1 (tests only).
- Produces: `import ./lint.nix { inherit lib; }` →
  - `portableFields :: [string]`, `claudeCodeFields :: [string]`, `knownFields :: [string]`, `sidecarKeys :: [string]`
  - `validateSkillMd :: { dirName :: string; parsed :: (parse result); } -> (parse result)` — returns `parsed` unchanged or throws a message naming the skill.
  - `validateSidecar :: string(dirName) -> attrs -> attrs` — returns the attrs or throws.
- Consumed by: Task 4.

- [ ] **Step 1: Write the failing test file**

Create `lib/lint-tests.nix`:

```nix
{ lib }:
let
  fm = import ./frontmatter.nix { inherit lib; };
  lint = import ./lint.nix { inherit lib; };
  ok = fm.parse ''
    ---
    name: good-skill
    description: Use when testing lint
    allowed-tools: Bash(git:*) Read
    context: fork
    ---
    body
  '';
  tryValidate = args: (builtins.tryEval (lint.validateSkillMd args)).success;
in
lib.debug.runTests {
  testValidSkill = {
    expr = tryValidate {
      dirName = "good-skill";
      parsed = ok;
    };
    expected = true;
  };
  testNameDirMismatch = {
    expr = tryValidate {
      dirName = "other-dir";
      parsed = ok;
    };
    expected = false;
  };
  testUppercaseName = {
    expr = tryValidate {
      dirName = "Bad-Name";
      parsed = fm.parse "---\nname: Bad-Name\ndescription: y\n---\nbody";
    };
    expected = false;
  };
  testMissingDescription = {
    expr = tryValidate {
      dirName = "x";
      parsed = fm.parse "---\nname: x\n---\nbody";
    };
    expected = false;
  };
  testUnknownKey = {
    expr = tryValidate {
      dirName = "x";
      parsed = fm.parse "---\nname: x\ndescription: y\nfrobnicate: z\n---\nbody";
    };
    expected = false;
  };
  testClaudeCodeFieldAllowed = {
    expr = tryValidate {
      dirName = "x";
      parsed = fm.parse "---\nname: x\ndescription: y\ndisable-model-invocation: true\n---\nbody";
    };
    expected = true;
  };
  testSpaceFormWithInternalSpacesRejected = {
    # Bash(sem diff:*) space-split would shear mid-entry; must use commas.
    expr = tryValidate {
      dirName = "x";
      parsed = fm.parse "---\nname: x\ndescription: y\nallowed-tools: Bash(sem diff:*) Bash(sem impact:*)\n---\nbody";
    };
    expected = false;
  };
  testMultilineDescriptionMarkerRejected = {
    expr = tryValidate {
      dirName = "x";
      parsed = fm.parse "---\nname: x\ndescription: >\n---\nbody";
    };
    expected = false;
  };
  testSidecarGood = {
    expr =
      (builtins.tryEval (
        lint.validateSidecar "x" {
          packages = [ ];
          mcpServers = { };
          lspServers = { };
        }
      )).success;
    expected = true;
  };
  testSidecarRejectsLegacyKeys = {
    expr = (builtins.tryEval (lint.validateSidecar "x" { description = "nope"; })).success;
    expected = false;
  };
}
```

- [ ] **Step 2: Wire the check into flake.nix**

Add to the same `checks` attrset:

```nix
          lint-tests =
            let
              failures = import ./lib/lint-tests.nix { inherit lib; };
            in
            if failures == [ ] then
              pkgs.runCommand "lint-tests" { } "touch $out"
            else
              throw "lint tests failed: ${builtins.toJSON failures}";
```

- [ ] **Step 3: Run the check to verify it fails**

Run: `nix build .#checks.aarch64-darwin.lint-tests 2>&1 | tail -5`
Expected: FAIL — error opening `lib/lint.nix`.

- [ ] **Step 4: Implement the lint**

Create `lib/lint.nix`:

```nix
# Contract lint for md-first skills. Field tiers:
#  - portableFields: the agentskills.io open spec — the only keys claude.ai
#    web uploads / the Skills API accept.
#  - claudeCodeFields: Claude Code's documented extensions — valid in plugin
#    skills, stripped for the web bundle.
{ lib }:
let
  portableFields = [
    "name"
    "description"
    "license"
    "compatibility"
    "metadata"
    "allowed-tools"
  ];
  claudeCodeFields = [
    "when_to_use"
    "argument-hint"
    "arguments"
    "disable-model-invocation"
    "user-invocable"
    "disallowed-tools"
    "model"
    "effort"
    "context"
    "agent"
    "background"
    "hooks"
    "paths"
    "shell"
  ];
  knownFields = portableFields ++ claudeCodeFields;
  sidecarKeys = [
    "packages"
    "mcpServers"
    "lspServers"
  ];
  charCount = c: s: lib.count (x: x == c) (lib.stringToCharacters s);
in
{
  inherit
    portableFields
    claudeCodeFields
    knownFields
    sidecarKeys
    ;

  validateSkillMd =
    { dirName, parsed }:
    let
      f = parsed.fields;
      err = msg: throw "agent-skills: skill '${dirName}': ${msg}";
      unknown = builtins.filter (k: !(builtins.elem k knownFields)) parsed.keys;
      name = f.name or "";
      desc = f.description or "";
      inlineTools = f.allowed-tools or "";
      spaceTokens =
        if inlineTools == "" || lib.hasInfix "," inlineTools then
          [ ]
        else
          builtins.filter (t: t != "") (lib.splitString " " inlineTools);
      unbalanced = builtins.filter (t: charCount "(" t != charCount ")" t) spaceTokens;
    in
    if name == "" then
      err "frontmatter must set name (equal to the directory name)"
    else if builtins.match "[a-z0-9]+(-[a-z0-9]+)*" name == null || lib.stringLength name > 64 then
      err "name '${name}' violates the spec: lowercase alphanumerics and single hyphens, max 64 chars"
    else if name != dirName then
      err "frontmatter name '${name}' must equal the directory name"
    else if
      builtins.elem desc [
        ""
        ">"
        "|"
        ">-"
        "|-"
      ]
    then
      err "description must be a non-empty single-line scalar (no folded/literal YAML blocks)"
    else if lib.stringLength desc > 1024 then
      err "description exceeds the spec's 1024-character cap"
    else if unknown != [ ] then
      err "unknown frontmatter key(s): ${toString unknown} (typo? known fields: portable ∪ Claude Code extensions)"
    else if unbalanced != [ ] then
      err "allowed-tools entries containing spaces must use the comma-separated or block-list form (shorn token(s): ${toString unbalanced})"
    else
      parsed;

  validateSidecar =
    dirName: attrs:
    let
      bad = builtins.filter (k: !(builtins.elem k sidecarKeys)) (builtins.attrNames attrs);
    in
    if bad != [ ] then
      throw "agent-skills: skill '${dirName}': skill.nix may only contain ${toString sidecarKeys}; found: ${toString bad}. name/description/allowed-tools belong in SKILL.md frontmatter; commands are skills now; subagents go in agents/*.md"
    else
      attrs;
}
```

- [ ] **Step 5: Run both checks to verify they pass**

Run: `nix build .#checks.aarch64-darwin.lint-tests .#checks.aarch64-darwin.frontmatter-tests && echo OK`
Expected: `OK`

- [ ] **Step 6: Format and commit**

```bash
nixfmt lib/lint.nix lib/lint-tests.nix flake.nix
git add lib/lint.nix lib/lint-tests.nix flake.nix
git commit -m "feat(lib): md-first skill contract lint with eval tests"
```

---

### Task 3: One-time migration script

**Files:**
- Create: `scripts/migrate-to-md-first.sh`
- Create: `scripts/insert_frontmatter.py`

**Interfaces:**
- Consumes: plain-attrset `skill.nix` files (everything except gh-checks, nix-helper, writing-skills, which are function-style and skipped).
- Produces: SKILL.md files gaining a frontmatter block; plain skill.nix files `git rm`'d. Task 4 runs it for real; this task only dry-runs.

- [ ] **Step 1: Write the python emitter**

Create `scripts/insert_frontmatter.py`:

```python
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
```

- [ ] **Step 2: Write the driver**

Create `scripts/migrate-to-md-first.sh`:

```bash
#!/usr/bin/env bash
# One-time migration for the md-first refactor: move name/description/
# allowed-tools out of plain-attrset skill.nix files into SKILL.md
# frontmatter, then git rm the skill.nix. Function-style skill.nix files
# (gh-checks, nix-helper, writing-skills) are skipped — migrated by hand.
#
# Usage: scripts/migrate-to-md-first.sh [--dry-run]
set -euo pipefail
cd "$(dirname "$0")/.."
dry_run="${1:-}"

for nixfile in skills/*/skill.nix; do
  dir=$(dirname "$nixfile")
  name=$(basename "$dir")
  if ! meta=$(nix eval --json --impure --expr "import $PWD/$nixfile" 2>/dev/null); then
    echo "SKIP (function-style; migrate by hand): $name"
    continue
  fi
  if [ "$dry_run" = "--dry-run" ]; then
    META_JSON="$meta" NAME="$name" MD="" python3 scripts/insert_frontmatter.py
  else
    META_JSON="$meta" NAME="$name" MD="$dir/SKILL.md" python3 scripts/insert_frontmatter.py
    git rm -q "$nixfile"
  fi
done
```

Then: `chmod +x scripts/migrate-to-md-first.sh`

- [ ] **Step 3: Dry-run and inspect the output**

Run: `scripts/migrate-to-md-first.sh --dry-run`
Expected:
- `SKIP (function-style; migrate by hand):` lines for exactly `gh-checks`, `nix-helper`, `writing-skills`.
- A `### <name>` + frontmatter block for every other skill. Spot-check three:
  - `brainstorming` → no `allowed-tools` line.
  - `sem` → `allowed-tools: Bash(sem diff:*), Bash(sem impact:*), Bash(sem context:*), Bash(sem blame:*), Bash(sem log:*), Bash(sem entities:*)` (comma form — entries contain spaces).
  - `figma-readonly` → `allowed-tools: Bash(figr) Bash(figr:*)` (space form).
- No description is quoted unless it contains `": "`, `" #"`, or starts with a special character (as of writing, none should be quoted).

If any assertion fires or output looks wrong, fix the script — do not proceed.

- [ ] **Step 4: Verify nothing was modified**

Run: `git status --short`
Expected: only the two new untracked files under `scripts/`.

- [ ] **Step 5: Commit**

```bash
git add scripts/migrate-to-md-first.sh scripts/insert_frontmatter.py
git commit -m "feat(scripts): one-time skill.nix -> frontmatter migration script"
```

---

### Task 4: Switchover — lib rewrite + migration

This task is atomic by necessity: the lib flip and the skill migration must land together for the build to stay green. Do not commit until the final step.

**Files:**
- Modify: `lib/default.nix` (functions: `evalSkillNix`→`evalSidecar`, `buildSkillDrv`, `discoverSkills`, `buildUsingAgentSkillsContent`, `buildSkillForTarget`, `buildPlugin`, `buildAntigravityPlugin`, `buildCodexPlugin`, and the export attrset)
- Modify: `flake.nix` (add `skills-lint` check)
- Modify: every `skills/*/SKILL.md` (via the Task 3 script)
- Delete: every plain `skills/*/skill.nix` (via the script)
- Modify: `skills/gh-checks/SKILL.md`; Delete: `skills/gh-checks/skill.nix`
- Modify: `skills/nix-helper/SKILL.md`, `skills/nix-helper/skill.nix`; Create: `skills/nix-helper/agents/nix-analyzer.md`
- Modify: `skills/writing-skills/SKILL.md` (frontmatter only), `skills/writing-skills/skill.nix`

**Interfaces:**
- Consumes: `parse`/`parseFile`/`parseToolList` (Task 1), `validateSkillMd`/`validateSidecar` (Task 2).
- Produces: `discoverSkills` now returns per-skill `{ name; dir; parsed; meta; drv; }` where `meta = { name; description; allowed-tools :: [string]; agentSpecs :: [spec]; }` merged with the validated sidecar attrs (`packages`/`mcpServers`/`lspServers`). `parsed.body` is the frontmatter-stripped body. Everything downstream (`buildPlugin`, flake `perSkillPackages`, `homeManagerModules.claude` `skillPermissions`) keeps working off `s.name` / `s.meta` / `s.drv`.

- [ ] **Step 1: Capture a baseline build for later diffing**

```bash
nix build .#claude-plugin -o /tmp/agent-skills-before
```
Expected: builds successfully (pre-change state).

- [ ] **Step 2: Rewrite lib/default.nix — imports and sidecar eval**

At the top of the `let` block (after `mcpLib = ...`), add:

```nix
  fm = import ./frontmatter.nix { inherit lib; };
  lintLib = import ./lint.nix { inherit lib; };
```

Replace the entire `evalSkillNix` definition (and its doc comment) with:

```nix
  # Evaluate an optional skill.nix sidecar. Sidecars carry only what
  # markdown cannot express: packages, mcpServers, lspServers. A sidecar
  # may be an attrset or a function of (a subset of) { pkgs, lib }.
  evalSidecar =
    dirName: raw:
    let
      args = { inherit pkgs lib; };
      attrs =
        if builtins.isFunction raw then
          raw (builtins.intersectAttrs (builtins.functionArgs raw) args)
        else
          raw;
    in
    lintLib.validateSidecar dirName attrs;
```

- [ ] **Step 3: Replace buildSkillDrv (verbatim copy, no frontmatter synthesis)**

```nix
  # A skill directory is shipped verbatim: SKILL.md (frontmatter included)
  # and all assets, minus the Nix sidecar and the agents/ source dir.
  buildSkillDrv =
    name: skillDir:
    pkgs.runCommand "skill-${name}" { } ''
      mkdir -p $out/skills/${name}
      for item in ${skillDir}/*; do
        basename=$(basename "$item")
        case "$basename" in
          skill.nix|agents) ;;
          *) cp -r "$item" $out/skills/${name}/ ;;
        esac
      done
    '';
```

- [ ] **Step 4: Replace discoverSkills (key on SKILL.md, parse + lint, agents/*.md)**

```nix
  # Parse agents/<name>.md files into target-neutral agent specs:
  #   { name; description; prompt; tools ? [ ]; model ? ...; }
  loadAgentSpecs =
    skillName: dir:
    let
      agentsDir = dir + "/agents";
      mdFiles = builtins.filter (n: lib.hasSuffix ".md" n) (
        builtins.attrNames (builtins.readDir agentsDir)
      );
    in
    if !builtins.pathExists agentsDir then
      [ ]
    else
      map (
        fname:
        let
          parsed = fm.parseFile (agentsDir + "/${fname}");
          stem = lib.removeSuffix ".md" fname;
        in
        {
          name = parsed.fields.name or stem;
          description =
            parsed.fields.description
              or (throw "agent-skills: skill '${skillName}': agents/${fname} must set description");
          tools = fm.parseToolList parsed "tools";
          prompt = parsed.body;
        }
        // lib.optionalAttrs (parsed.fields ? model) { model = parsed.fields.model; }
      ) mdFiles;

  discoverSkills =
    skillsDir:
    let
      entries = builtins.readDir skillsDir;
      dirNames = builtins.attrNames (lib.filterAttrs (_: type: type == "directory") entries);
      validNames = builtins.filter (
        name: builtins.pathExists (skillsDir + "/${name}/SKILL.md")
      ) dirNames;
    in
    map (
      name:
      let
        dir = skillsDir + "/${name}";
        parsed = lintLib.validateSkillMd {
          dirName = name;
          parsed = fm.parseFile (dir + "/SKILL.md");
        };
        sidecar =
          if builtins.pathExists (dir + "/skill.nix") then
            evalSidecar name (import (dir + "/skill.nix"))
          else
            { };
      in
      {
        inherit name dir parsed;
        meta = {
          inherit name;
          description = parsed.fields.description;
          allowed-tools = fm.parseToolList parsed "allowed-tools";
          agentSpecs = loadAgentSpecs name dir;
        }
        // sidecar;
        drv = buildSkillDrv name dir;
      }
    ) validNames;
```

- [ ] **Step 5: Replace buildUsingAgentSkillsContent (read verbatim)**

```nix
  # ── Build using-agent-skills content (shared across targets) ──
  buildUsingAgentSkillsContent =
    skills:
    let
      usingAgentSkillsSkill = lib.findFirst (s: s.name == "using-agent-skills") null skills;
    in
    if usingAgentSkillsSkill != null then
      builtins.readFile (usingAgentSkillsSkill.dir + "/SKILL.md")
    else
      "";
```

- [ ] **Step 6: Replace buildSkillForTarget (parsed body, exclude agents/)**

```nix
  # ── Build a skill using a target's mkSkill ──
  # Targets rebuild their own frontmatter from name/description/
  # allowed-tools; Claude Code-only fields intentionally do not carry over.
  buildSkillForTarget =
    targetMkSkill: skill:
    let
      extraFiles =
        let
          entries = builtins.readDir skill.dir;
          extras = lib.filterAttrs (
            name: _: name != "skill.nix" && name != "SKILL.md" && name != "agents"
          ) entries;
        in
        map (name: skill.dir + "/${name}") (builtins.attrNames extras);
    in
    targetMkSkill {
      inherit (skill.meta) name description;
      allowed-tools = skill.meta.allowed-tools or [ ];
      inherit extraFiles;
    } skill.parsed.body;
```

- [ ] **Step 7: Update the three plugin builders**

In `buildPlugin`, delete the `allCommands` and `allAgents` lines, add a `skillPackages` line, and update the `mkPlugin` call and `buildEnv` paths:

```nix
      allAgentSpecs = lib.concatMap (s: s.meta.agentSpecs or [ ]) skills;
      claudeSpecAgents = map (a: mkClaudeAgentFromSpec a) allAgentSpecs;
      allMcpServers = lib.foldl' (acc: s: acc // (s.meta.mcpServers or { })) { } skills;
      allLspServers = lib.foldl' (acc: s: acc // (s.meta.lspServers or { })) { } skills;
      skillPackages = lib.concatMap (s: s.meta.packages or [ ]) skills;

      plugin = claudeLib.mkPlugin {
        inherit name description;
        skills = map (s: s.drv) skills;
        agents = claudeSpecAgents;
        mcpServers = allMcpServers;
        lspServers = allLspServers;
      };
```

and at the bottom of `buildPlugin`:

```nix
    pkgs.buildEnv {
      name = "${name}-complete";
      paths = [ plugin ] ++ hooksDrv ++ attributionDrv ++ extraPackages ++ skillPackages;
    };
```

In `buildAntigravityPlugin` and `buildCodexPlugin`, add the same `skillPackages = lib.concatMap (s: s.meta.packages or [ ]) skills;` binding and append `++ skillPackages` to their `buildEnv` `paths`.

- [ ] **Step 8: Update the export attrset**

In the final exported set, replace `evalSkillNix` with `evalSidecar` (keep everything else).

- [ ] **Step 9: Run the migration script for real**

```bash
scripts/migrate-to-md-first.sh
git status --short | head -40
```
Expected: every plain skill.nix deleted (`D`), every corresponding SKILL.md modified (`M`), and `SKIP` printed for gh-checks, nix-helper, writing-skills.

- [ ] **Step 10: Hand-migrate gh-checks**

Delete `skills/gh-checks/skill.nix` (`git rm skills/gh-checks/skill.nix`).

Prepend to `skills/gh-checks/SKILL.md` (replacing the leading blank line so the file starts with `---`):

```markdown
---
name: gh-checks
description: Use when reading CI check statuses, viewing test/lint failure logs, or diagnosing why PR checks are failing
argument-hint: "[pr-number]"
---
```

Then insert this section into the body, immediately after the intro line `Read and diagnose GitHub Actions CI check statuses and failure logs for pull requests.` (this absorbs the deleted `/gh-checks` command's step list; `/gh-checks` now invokes the skill directly since commands are merged into skills):

```markdown
## Workflow

1. Identify the PR — use `$ARGUMENTS` if given, otherwise detect from the current branch
2. Fetch check statuses and show a summary table
3. For any failing checks, fetch the failure logs
4. Categorize failures (test, lint, build, security, etc.)
5. Propose fixes or next steps
```

- [ ] **Step 11: Hand-migrate nix-helper**

Prepend to `skills/nix-helper/SKILL.md`:

```markdown
---
name: nix-helper
description: Helps with Nix development and formatting
allowed-tools: Bash(statix:*) Bash(nixfmt:*)
---
```

Replace `skills/nix-helper/skill.nix` entirely with:

```nix
{ pkgs, lib }:
{
  packages = [
    pkgs.statix
    pkgs.nixfmt
  ];

  mcpServers = {
    nixos = {
      command = "${pkgs.mcp-nixos}/bin/mcp-nixos";
    };
  };

  lspServers = {
    nix = {
      command = lib.getExe pkgs.nixd;
      extensionToLanguage = {
        ".nix" = "nix";
      };
    };
  };
}
```

Create `skills/nix-helper/agents/nix-analyzer.md`:

```markdown
---
name: nix-analyzer
description: Specialized agent for analyzing Nix code
tools: Read, Glob, Grep, Bash(statix:*)
---

You are an expert Nix code analyzer. When asked to analyze Nix code:

1. Search for all .nix files in the project
2. Run statix to identify anti-patterns
3. Analyze the flake structure and dependencies
4. Provide recommendations for improvements
5. Explain any complex Nix patterns found

Be thorough and educational in your analysis.
```

The two commands (`format-nix`, `nix-dotfiles`) are deliberately dropped here — Task 5 recreates them as skills.

- [ ] **Step 12: Hand-migrate writing-skills**

Prepend to `skills/writing-skills/SKILL.md`:

```markdown
---
name: writing-skills
description: Use when creating new skills, editing existing skills, or verifying skills work before deployment
allowed-tools: Bash(dot:*)
---
```

Replace `skills/writing-skills/skill.nix` entirely with:

```nix
{ pkgs }:
{
  packages = [ pkgs.graphviz ];
}
```

- [ ] **Step 13: Add the skills-lint flake check**

In the `checks` attrset in `flake.nix`, add (note: `claude-nix` is in scope from the flake's `outputs` arguments):

```nix
          skills-lint =
            let
              build = import ./lib/default.nix {
                inherit pkgs lib;
                claudeLib = import "${claude-nix}/lib" { inherit pkgs; };
              };
              skills = build.discoverSkills ./skills;
              # toJSON forces every parsed/linted field deeply.
              summary = builtins.toJSON (
                map (s: {
                  inherit (s) name;
                  inherit (s.meta) description;
                  tools = s.meta.allowed-tools;
                  agents = map (a: a.name) (s.meta.agentSpecs or [ ]);
                }) skills
              );
            in
            pkgs.runCommand "skills-lint"
              {
                inherit summary;
                passAsFile = [ "summary" ];
              }
              ''
                cp "$summaryPath" $out
              '';
```

- [ ] **Step 14: Build everything and fix until green**

```bash
nix build .#checks.aarch64-darwin.skills-lint && cat result
nix build .#claude-plugin .#antigravity-plugin .#codex-plugin
```
Expected: lint output lists every skill with its description; all three plugins build. Typical failures at this point are lint messages naming a specific skill/field — fix the named SKILL.md, not the lint.

- [ ] **Step 15: Diff against the baseline**

```bash
nix build .#claude-plugin -o /tmp/agent-skills-after
diff -r /tmp/agent-skills-before/skills /tmp/agent-skills-after/skills | head -80
diff -r /tmp/agent-skills-before/commands /tmp/agent-skills-after/commands 2>&1 | head
diff -r /tmp/agent-skills-before/agents /tmp/agent-skills-after/agents | head
```
Expected differences ONLY:
- Every SKILL.md: frontmatter field order/format (e.g. `allowed-tools` as a string instead of Nix's `toString` list join); `argument-hint` on gh-checks; body content otherwise identical (gh-checks gains the Workflow section).
- `commands/` gone or empty (format-nix, nix-dotfiles, gh-checks commands removed; the first two return as skills in Task 5).
- `agents/nix-analyzer.md`: `tools:` line now `Read, Glob, Grep, Bash(statix:*)` (plain name, no store path).
- Store paths for statix/nixfmt/graphviz now appear as `bin/` entries in the buildEnv root (from `skillPackages`).

Any body-content drift beyond the above is a bug — fix before committing.

- [ ] **Step 16: Format, run all checks, commit**

```bash
nixfmt lib/default.nix flake.nix skills/nix-helper/skill.nix skills/writing-skills/skill.nix
nix flake check
git add -A
git commit -m "feat!: md-first skills — SKILL.md frontmatter is the source of truth

- discoverSkills keys on SKILL.md; frontmatter shipped verbatim
- skill.nix reduced to optional sidecar (packages/mcpServers/lspServers)
- agents move to agents/*.md; commands removed (become skills)
- contract lint enforced via checks.skills-lint"
```

---

### Task 5: format-nix and nix-dotfiles as skills

**Files:**
- Create: `skills/format-nix/SKILL.md`
- Create: `skills/format-nix/skill.nix`
- Create: `skills/nix-dotfiles/SKILL.md`

**Interfaces:**
- Consumes: the md-first contract from Task 4 (auto-discovery; sidecar `packages` land on PATH via the plugin buildEnv).
- Produces: `/format-nix` and `/nix-dotfiles` slash commands (skills with `disable-model-invocation: true`).

- [ ] **Step 1: Create skills/format-nix/SKILL.md**

```markdown
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
```

- [ ] **Step 2: Create skills/format-nix/skill.nix**

```nix
{ pkgs }:
{
  packages = [
    pkgs.nixfmt
    pkgs.fd
  ];
}
```

- [ ] **Step 3: Create skills/nix-dotfiles/SKILL.md**

Body is ported verbatim from the deleted `nix-dotfiles` command in nix-helper's old skill.nix, with the one store path (`${pkgs.nixfmt}/bin/nixfmt`) replaced by plain `nixfmt`:

````markdown
---
name: nix-dotfiles
description: Make changes to the NixOS/nix-darwin dotfiles with full repo context pre-loaded
disable-model-invocation: true
argument-hint: "<what to change>"
---

You are working in a multi-platform Nix dotfiles repo organized around
the dendritic pattern with den (github:denful/den): every non-underscore
.nix file under modules/ is auto-loaded as a flake-parts module, features
are den *aspects* (one file per feature, carrying nixos/darwin/homeManager
halves together), and hosts are den *entities* that select aspects via
`includes`. Read the repo's README.md for the architecture; the key rule:
a NEW file under modules/ is immediately live — disable by underscore-
prefixing, never by commenting an import.

## Hosts (modules/hosts/<dir>/)

| Host | Platform | Config dir |
|------|----------|------------|
| joe-desktop | NixOS (x86_64-linux), KDE Plasma 6 | modules/hosts/joe-desktop/ |
| office-pc | NixOS (x86_64-linux), compute/training, AMD GPU | modules/hosts/office-pc/ |
| joe-steamdeck | NixOS (x86_64-linux), Jovian/Steam Deck | modules/hosts/joe-steamdeck/ |
| Joes-MacBook-Pro | macOS (aarch64-darwin) | modules/hosts/macbook/ |
| cloud-proxy | NixOS VPS (caddy reverse proxy) | modules/hosts/cloud-proxy/ |
| oracle-cloud-bastion | NixOS server (hostName "bastion") | modules/hosts/oracle-cloud-bastion/ |
| racknerd-cloud-agent | NixOS server (attic cache) | modules/hosts/racknerd-cloud-agent/ |

Each host dir: default.nix (entity + aspect includes + agenix secrets),
system.nix (base system), machine.nix (hardware tuning), home.nix
(host-specific home config), plus per-concern sibling files — all merge
into den.aspects.<host> by name.

## Key Files — Where to make changes

| What you want to do | File(s) to edit |
|---------------------|-----------------|
| Add a CLI package for every full home | modules/home/packages/default.nix (cli-packages aspect) |
| Add a workstation package | modules/home/packages/workstation.nix (linux-only: linux-workstation.nix) |
| Add a host-specific package | modules/hosts/<host>/home.nix (or its _packages payload) |
| Define a custom package from source | modules/flake/_pkgs/ (register in its default.nix) |
| Add a flake input | flake.nix (inputs; reference it only in the owning aspect) |
| Add an overlay | modules/flake/_overlays/default.nix (see its README) |
| New home-manager feature | modules/home/<feature>.nix as den.aspects.<feature>.homeManager, then add to a host's includes / home-baseline / users/joe.nix |
| NixOS system config for one host | modules/hosts/<host>/system.nix or a new sibling aspect file |
| Shared system feature | modules/system/<feature>.nix (aspect) |
| macOS homebrew package | modules/hosts/macbook/homebrew.nix |
| macOS system settings | modules/hosts/macbook/mac-system.nix |
| KDE Plasma config | modules/home/plasma.nix (shared) or modules/hosts/<host>/home.nix + _plasma-panels.nix |
| Fish shell config | modules/home/fish/ |
| Git config | modules/home/git.nix |
| AI tooling (claude/codex/antigravity/mcp) | modules/ai/ |
| User scripts (bins) | modules/home/bin/_scripts/<name>.nix |

## Package Patterns (copy these)

**Nixpkgs stable:** `pkgs.packageName`
**Nixpkgs unstable:** `unstable.packageName` (overlay provides `pkgs.unstable.*`)
**Custom package from GitHub (npm/yarn):** See `modules/flake/_pkgs/default.nix`
**Custom package from GitHub (Go):** See `modules/home/_go.nix` — `buildGoModule` examples
**Custom package from GitHub (binary):** See `modules/home/_sprites.nix` — platform-specific binary fetch
**Custom Python package:** See `modules/home/_python/custom-pypi-packages.nix` (or run the `setup-python-packages` bins command)
**Shell wrapper:** See `google-chrome-stable` or `aws-cli` in `modules/flake/_pkgs/default.nix`
**Flake input package:** Add input to `flake.nix`, use via overlay or direct reference

## Overlays (modules/flake/_overlays/default.nix)

- `additions` — custom packages from `modules/flake/_pkgs/`
- `modifications` — patches to existing packages
- `unstable-packages` — makes `pkgs.unstable.*` available
- `llm-agents-packages` — Claude Code, Codex, Gemini CLI
- `mcps-packages` — MCP servers

## Conventions

- Formatter: nixfmt (pre-commit hook enforced)
- Lint: statix, gitleaks
- Dual nixpkgs: stable (nixos-26.05) + unstable channel (`pkgs.unstable.*`)
- No URL pins (flake.lock is the pin; update via `just flake-update`)
- Apply NixOS: `just switch` (nh) or `sudo nixos-rebuild switch --flake .`
- Apply macOS: `darwin-rebuild switch --flake .`
- Test build: `nix build .#packageName`

## Your task

$ARGUMENTS

Read the relevant files first, then make the changes. Follow existing patterns in the repo. Format changed .nix files with `nixfmt`.
````

- [ ] **Step 4: Build and verify discovery**

```bash
nix build .#checks.aarch64-darwin.skills-lint && grep -o '"format-nix"\|"nix-dotfiles"' result | sort -u
nix build .#claude-plugin
ls result/skills/ | grep -E 'format-nix|nix-dotfiles'
head -8 result/skills/format-nix/SKILL.md
```
Expected: both names in the lint summary; both dirs in the plugin; format-nix's SKILL.md starts with the frontmatter above.

- [ ] **Step 5: Format and commit**

```bash
nixfmt skills/format-nix/skill.nix
git add skills/format-nix skills/nix-dotfiles
git commit -m "feat(skills): format-nix and nix-dotfiles as command-style skills"
```

---

### Task 6: Web bundle — portable frontmatter filter

**Files:**
- Modify: `lib/default.nix` (`buildWebBundle` only)

**Interfaces:**
- Consumes: skill drvs (SKILL.md now carries frontmatter with possibly Claude Code-only fields).
- Produces: `web-skills` folders whose SKILL.md frontmatter contains only the six portable fields, so claude.ai uploads pass the "Unexpected key(s)" validator.

- [ ] **Step 1: Add the filter step**

In `buildWebBundle`'s shell script, insert this block immediately after the `chmod -R u+w $out` line and before the XML-tag neutralization loop:

```bash
      # ── Restrict frontmatter to the agentskills.io portable field set ──
      # claude.ai uploads reject any other key ("Unexpected key(s) in
      # SKILL.md frontmatter"). Claude Code-only fields (argument-hint,
      # context, disable-model-invocation, ...) are dropped here; they keep
      # working in the plugin, which ships the file verbatim. Indented
      # continuation lines (block lists, metadata maps) follow their key's
      # keep/drop decision.
      for f in $out/*/SKILL.md; do
        awk '
          NR==1 && $0=="---" { fm=1; print; next }
          fm && $0=="---"    { fm=0; print; next }
          fm {
            if ($0 ~ /^[A-Za-z0-9_-]+:/) {
              key=$0; sub(/:.*/, "", key)
              keep = (key=="name" || key=="description" || key=="license" || key=="compatibility" || key=="metadata" || key=="allowed-tools")
            }
            if (keep) print
            next
          }
          { print }
        ' "$f" > "$f.tmp" && mv "$f.tmp" "$f"
      done
```

- [ ] **Step 2: Make the avoid-ai-writing dependency note spec-proper**

Still in `buildWebBundle`, replace the line:

```bash
        sed -i '0,/^description:/ s/^description:/dependencies: node>=18\ndescription:/' "$aaw/SKILL.md"
```

with (`compatibility` is a portable field, so it survives the filter regardless of step ordering):

```bash
        sed -i '0,/^description:/ s/^description:/compatibility: Requires Node.js 18 or newer (engine is Node stdlib only)\ndescription:/' "$aaw/SKILL.md"
```

Also update that block's preceding comment line `# Declare the runtime dependency (Node stdlib; no npm packages).` to `# Declare the runtime dependency via the spec's compatibility field.`

- [ ] **Step 3: Build and verify**

```bash
nix build .#web-skills
grep -rE '^(argument-hint|disable-model-invocation|context|user-invocable|when_to_use|paths|model|effort|agent|background|hooks|shell|arguments|disallowed-tools):' result/*/SKILL.md; echo "exit=$?"
head -6 result/avoid-ai-writing/SKILL.md
head -4 result/cc-nix-config/SKILL.md
nix build .#web-skills-zips && ls result | head -3
```
Expected: the grep finds nothing (`exit=1`); avoid-ai-writing shows `compatibility: Requires Node.js 18 or newer...` and `Bash(node...)` allowed-tools; the renamed `cc-nix-config` folder's `name:` field says `cc-nix-config`; zips build.

- [ ] **Step 4: Format and commit**

```bash
nixfmt lib/default.nix
git add lib/default.nix
git commit -m "feat(web-bundle): filter frontmatter to portable spec fields"
```

---

### Task 7: Update claude-nix-config skill docs

**Files:**
- Modify: `skills/claude-nix-config/SKILL.md`

**Interfaces:** none (documentation only) — but it must describe the Task 4 contract accurately.

- [ ] **Step 1: Update the Key Files table**

Replace the row:

```markdown
| `agent-skills/skills/<name>/skill.nix` | Skill metadata (name, description, optional commands/agents/mcpServers/lspServers) |
| `agent-skills/skills/<name>/SKILL.md` | Skill content — the instructions loaded when the skill is invoked |
```

with:

```markdown
| `agent-skills/skills/<name>/SKILL.md` | The skill — YAML frontmatter (name, description, allowed-tools, any Claude Code field) + instructions, shipped verbatim |
| `agent-skills/skills/<name>/skill.nix` | Optional sidecar — ONLY `packages`, `mcpServers`, `lspServers` (things markdown can't express) |
| `agent-skills/skills/<name>/agents/*.md` | Optional subagents — frontmatter (description, tools, model) + prompt body, built per-target |
```

- [ ] **Step 2: Replace the "How to Add a Skill" section**

Replace everything from the `## How to Add a Skill` heading through the line `3. That's it — discoverSkills auto-discovers any directory under skills/ that contains a skill.nix.` (inclusive) with:

````markdown
## How to Add a Skill

1. Create `agent-skills/skills/<skill-name>/SKILL.md`. Frontmatter is the
   source of truth and is shipped verbatim — any Claude Code frontmatter
   field works with zero Nix changes:

```markdown
---
name: my-skill
description: Use when [triggering conditions]
allowed-tools: Bash(sometool:*) Read
---

Skill instructions here.
```

Rules (enforced by `checks.skills-lint` at build time):
- `name` must equal the directory name (lowercase, hyphens, max 64 chars)
- `description` is required, single-line, max 1024 chars
- `allowed-tools` is a space-separated string; use commas when an entry
  contains a space (e.g. `Bash(sem diff:*), Bash(sem impact:*)`)
- Reference tools by plain command name, never by Nix store path — put the
  package in the sidecar instead (next step) so it lands on PATH

2. Only if the skill needs Nix-level things, add a `skill.nix` sidecar.
   Allowed keys: `packages`, `mcpServers`, `lspServers` — nothing else:

```nix
{ pkgs, lib }:
{
  packages = [ pkgs.sometool ];

  mcpServers = {
    my-server = {
      command = "${pkgs.my-mcp}/bin/my-mcp";
    };
  };

  lspServers = {
    my-lang = {
      command = lib.getExe pkgs.my-lsp;
      extensionToLanguage = { ".ext" = "my-lang"; };
    };
  };
}
```

3. Only if the skill ships subagents, add `agents/<agent-name>.md`:

```markdown
---
name: my-agent
description: What this agent does
tools: Read, Glob, Grep
---

Agent system prompt.
```

4. That's it — `discoverSkills` auto-discovers any directory under
   `skills/` containing a `SKILL.md`.

**Commands are skills.** To make a slash-command-style workflow, create a
normal skill with `disable-model-invocation: true` and an `argument-hint`
in its frontmatter (see `skills/format-nix/` for the pattern). Do not use
`claudeLib.mkCommand` for skills in this repo.
````

- [ ] **Step 3: Update the Permissions bullet**

Replace:

```markdown
- Per-skill Bash allows go in `allowed-tools` inside that skill's `skill.nix`.
```

with:

```markdown
- Per-skill Bash allows go in `allowed-tools` inside that skill's SKILL.md frontmatter.
```

- [ ] **Step 4: Update "How the Build System Works" step 1-2**

Replace:

```markdown
1. **`discoverSkills ./skills`** — scans for directories with `skill.nix`, evaluates each (handles both plain attrsets and functions), builds skill derivations with frontmatter-injected SKILL.md
2. **`buildPlugin`** — aggregates all skills' commands, agents, mcpServers, lspServers into a single Claude plugin via `claudeLib.mkPlugin`
```

with:

```markdown
1. **`discoverSkills ./skills`** — scans for directories with `SKILL.md`, parses/lints the frontmatter (`lib/frontmatter.nix` + `lib/lint.nix`), evaluates the optional sidecar, parses `agents/*.md`, and builds a verbatim-copy skill derivation
2. **`buildPlugin`** — aggregates all skills' agents, mcpServers, lspServers, and sidecar packages into a single Claude plugin via `claudeLib.mkPlugin`
```

- [ ] **Step 5: Verify the skill still lints and commit**

```bash
nix build .#checks.aarch64-darwin.skills-lint
git add skills/claude-nix-config/SKILL.md
git commit -m "docs(claude-nix-config): document the md-first skill contract"
```

---

### Task 8: writing-skills content refresh

**Files:**
- Modify: `skills/writing-skills/SKILL.md`

**Interfaces:** none (content only). The frontmatter was already added in Task 4; this task updates the stale guidance inside the body.

- [ ] **Step 1: Replace the stale frontmatter guidance**

In `skills/writing-skills/SKILL.md`, under `## SKILL.md Structure`, replace this block:

```markdown
**Frontmatter (YAML):**
- Two required fields: `name` and `description` (see [agentskills.io/specification](https://agentskills.io/specification) for all supported fields)
- Max 1024 characters total
- `name`: Use letters, numbers, and hyphens only (no parentheses, special chars)
- `description`: Third-person, describes ONLY when to use (NOT what it does)
  - Start with "Use when..." to focus on triggering conditions
  - Include specific symptoms, situations, and contexts
  - **NEVER summarize the skill's process or workflow** (see SDO section for why)
  - Keep under 500 characters if possible
```

with:

```markdown
**Frontmatter (YAML):**
- Two required fields: `name` and `description` (see Frontmatter Reference below for the full field list and which tier each field belongs to)
- `name`: REQUIRED. Must equal the skill's directory name. Lowercase letters, numbers, and single hyphens only; no leading/trailing/consecutive hyphens; max 64 characters
- `description`: REQUIRED. Single line, max 1024 characters. Third-person, describes ONLY when to use (NOT what it does)
  - Start with "Use when..." to focus on triggering conditions
  - Include specific symptoms, situations, and contexts
  - **NEVER summarize the skill's process or workflow** (see SDO section for why)
  - Keep under 500 characters if possible
- Keep SKILL.md under 500 lines (~5k tokens). Move deep reference material to separate files with explicit load triggers: "Read references/api-errors.md if the API returns a non-200 status" beats "see references/ for details"
```

- [ ] **Step 2: Fix the invalid name in the structure template**

In the template a few lines below, replace:

```markdown
---
name: Skill-Name-With-Hyphens
description: Use when [specific triggering conditions and symptoms]
---
```

with:

```markdown
---
name: skill-name-with-hyphens
description: Use when [specific triggering conditions and symptoms]
---
```

- [ ] **Step 3: Insert the Frontmatter Reference and repo-contract sections**

Insert the following immediately BEFORE the `## Skill Discovery Optimization (SDO)` heading:

````markdown
## Frontmatter Reference

Two tiers. Which one you write for depends on where the skill ships:

**Portable tier** — the [agentskills.io](https://agentskills.io/specification) open standard. claude.ai web uploads and the Skills API accept ONLY these six fields and reject anything else:

| Field | Notes |
|-------|-------|
| `name` | Required. Must match the directory name. Lowercase/hyphens, max 64 chars |
| `description` | Required. Max 1024 chars, single line |
| `license` | Optional. License name or bundled file reference |
| `compatibility` | Optional, max 500 chars. Environment requirements (e.g. "Requires Node.js 18+") |
| `metadata` | Optional. Free-form string-to-string map |
| `allowed-tools` | Optional, experimental. Space-separated string of pre-approved tools |

**Claude Code tier** — extensions that work in Claude Code (including plugin skills like this repo's). Use freely here; they're stripped from web-upload bundles automatically:

| Field | Purpose |
|-------|---------|
| `when_to_use` | Extra trigger context appended to description in listings |
| `argument-hint` | Autocomplete hint, e.g. `"[pr-number]"` (quote it — starts with `[`) |
| `arguments` | Named positional args for `$name` substitution |
| `disable-model-invocation` | `true` = only the user can invoke (via `/name`) |
| `user-invocable` | `false` = hide from the `/` menu (background knowledge) |
| `allowed-tools` / `disallowed-tools` | Pre-approve / remove tools for the invoking turn |
| `model`, `effort` | Override model/effort while the skill is active |
| `context: fork` + `agent`, `background` | Run the skill in a forked subagent context |
| `hooks` | Hooks scoped to the skill's lifecycle |
| `paths` | Glob patterns limiting when the skill auto-activates |
| `shell` | `bash` (default) or `powershell` for inline `!` commands |

**Commands are skills.** A skill invoked as `/name` with `$ARGUMENTS` in its body replaces the old separate command concept. For a command-style workflow: `disable-model-invocation: true` + `argument-hint`.

## This Repo's Contract (agent-skills)

- SKILL.md frontmatter is the source of truth and ships verbatim; `checks.skills-lint` enforces name/description rules and rejects unknown keys at build time
- `allowed-tools`: space-separated string; switch to comma-separated when any entry contains a space (`Bash(sem diff:*), Bash(sem impact:*)`)
- Never put Nix store paths in frontmatter. Use plain command names (`Bash(dot:*)`) and declare the package in the optional `skill.nix` sidecar — allowed sidecar keys: `packages`, `mcpServers`, `lspServers`, nothing else
- Subagents live in `agents/<name>.md` (frontmatter: description, tools, model; body = prompt); they're built for Claude, Codex, and Antigravity from the one file
- Codex/Antigravity targets receive only name/description/allowed-tools + body; don't rely on Claude Code-tier fields for behavior those targets need
````

- [ ] **Step 4: Verify size and lint, then commit**

```bash
wc -l skills/writing-skills/SKILL.md
nix build .#checks.aarch64-darwin.skills-lint
git add skills/writing-skills/SKILL.md
git commit -m "docs(writing-skills): refresh frontmatter guidance for current spec"
```
Expected: lint passes. (The file was already over the 500-line guidance before this task; the added sections are the up-to-date reference that earns their keep — do not trim unrelated content in this task.)

---

### Task 9: Final verification and cleanup

**Files:**
- Delete: `scripts/migrate-to-md-first.sh`, `scripts/insert_frontmatter.py`

- [ ] **Step 1: Remove the one-time migration script**

```bash
git rm scripts/migrate-to-md-first.sh scripts/insert_frontmatter.py
```
(It has served its purpose; it stays in git history.)

- [ ] **Step 2: Full build matrix**

```bash
nix flake check
nix build .#claude-plugin .#antigravity-plugin .#codex-plugin .#web-skills .#web-skills-zips
nix build .#brainstorming .#sem .#nix-helper
```
Expected: all succeed. `nix flake check` runs eval-mcp, avoid-ai-detect, frontmatter-tests, lint-tests, and skills-lint.

- [ ] **Step 3: Spot-check the shipped artifacts**

```bash
nix build .#claude-plugin
head -6 result/skills/sem/SKILL.md          # comma-form allowed-tools
head -6 result/skills/gh-checks/SKILL.md    # argument-hint present
cat result/agents/nix-analyzer.md | head -8 # plain-name tools
ls result/bin | grep -E 'statix|nixfmt|dot|fd'  # sidecar packages on PATH
grep -c '^---$' result/skills/using-agent-skills/SKILL.md  # >= 2 (frontmatter shipped)
```
Expected: all as annotated.

- [ ] **Step 4: Commit**

```bash
git commit -m "chore: remove one-time migration script"
```

- [ ] **Step 5: Report follow-ups (do not do them in this repo)**

Note for the user in the final summary:
- Push and bump the dotfiles input when ready: `git push`, then in `~/Development/dotfiles`: `nix flake update agent-skills` and rebuild.
- The `/gh-checks`, `/format-nix`, `/nix-dotfiles` commands now come from skills; verify autocomplete after the dotfiles rebuild.
