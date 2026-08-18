# pi-nix Fork Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use subagent-driven-development (recommended) or executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Turn the fork at `/home/joe/Development/pi-nix` into `joegoldin/pi-nix` — upstream `lukasl-dev/pi.nix` plus a `systemPrompt` option, purely-pinned ecosystem extensions, a `lib/` of pi package builders that `agent-skills` consumes as `piLib`, and the `statusline` / `notifications` option surfaces.

**Architecture:** Every addition is a *new file*. The three upstream module entrypoints (`coding-agent/lib.nix`, `coding-agent/module.nix`, `coding-agent/home-manager.nix`) each gain exactly one line adding `coding-agent/extra-options.nix` to their module list; `coding-agent/options.nix` is never touched. `extra-options.nix` reaches pi's command line through the option surface upstream already exposes — `extraArgs` (appended after upstream's own flags), `extensions`, `skills`, `promptTemplates`, `settings`, `environment` — all of which are list- or attr-typed and therefore merge across module definitions. That gives a zero-diff options module and keeps `git rebase upstream/master` a fast-forward for everything but `flake.nix` and `update.nix`.

**Tech Stack:** Nix flakes (nixpkgs-unstable), `buildNpmPackage`, `nixfmt`, `nix-instantiate --eval` and `runCommand` assertions as the test vehicle, `writeShellApplication` for the update app.

This is phase 2 of the design in `docs/plans/2026-08-18-pi-nix-agent-stack-design.md` (§7 and §8). Phase 1 (`agent-statusline`) must be merged and pushed before Task 7.

## Global Constraints

- **The fork is strictly additive.** Do not reorder, reformat, or restructure any upstream file. `coding-agent/options.nix`, `coding-agent/package.nix`, `coding-agent/package-bun.nix`, `coding-agent/bun.nix`, `sync-upstream.nix`, `regenerate-models.nix`, `scan.nix`, `VERSION.json`, `ai/`, and the lockfiles must end this phase byte-identical to `upstream/master`. Task 9 has a check that proves it.
- Permitted upstream edits, and nothing else: **one** `imports`/`modules` line in each of `coding-agent/lib.nix`, `coding-agent/module.nix`, `coding-agent/home-manager.nix`; insertions (never rewrites) in `flake.nix`; three added lines in `update.nix`; a rewritten `README.md`.
- The upstream branch is `master`, not `main`. The `upstream` remote already exists and points at `git@github.com:lukasl-dev/pi.nix.git`.
- Nix formatting is `pkgs.nixfmt` (**not** `nixfmt-rfc-style`), driven by `nix fmt`. Run it before every commit.
- Every derivation name and flake attribute derived from an npm package name uses the **slug**: strip a leading `@`, replace `/` with `-`. `@juicesharp/rpiv-todo` → `juicesharp-rpiv-todo`.
- Tarball hashes in `extensions.json` are npm's `dist.integrity` string used **verbatim** as the Nix SRI hash. This was verified: `nix build` of `fetchurl { url = ".../rpiv-todo-2.6.2.tgz"; hash = "sha512-Lt2HzNaKWgOl7/nEJrxtRsKoIQJTZd32BeckDxJ0JGvoUmwYvqOicSpXbgKVZwyGqGBw90WBKYWkEggo9U/Q4Q=="; }` succeeds. Never re-derive them with `nix store prefetch-file`, which defaults to sha256.
- No IFD. `extensions.json` is read with `builtins.fromJSON (builtins.readFile ...)`; nothing reads a *built* file at eval time.
- The system in every command below is `x86_64-linux`.

### Verified facts this plan is built on

Checked against the npm registry and `earendil-works/pi@v0.84.2` on 2026-08-18:

1. `--system-prompt <text>` exists (`packages/coding-agent/src/cli/args.ts:96`). `resolvePromptInput` in `src/core/resource-loader.ts:53-68` reads the argument as a **file** when `existsSync(input)`, else treats it as literal text. So passing a store path works exactly as upstream's `rules` → `--append-system-prompt <path>` already does.
2. `--extension <path>` accepts a **directory**. `discoverAndLoadExtensions` (`src/core/extensions/loader.ts:719-733`) stats the path; if it is a directory, `resolveExtensionEntries` reads `package.json`'s `pi.extensions` array and returns those entries. Handing pi the npm package root therefore loads whatever the package's own manifest declares — including `pi-background-tasks`, which declares **two** entrypoints.
3. `--skill`, `--prompt-template`, `--theme`, `--extension` are all repeatable; `--append-system-prompt` is repeatable, `--system-prompt` is not.
4. **Design assumption A4 is false for all six pinned packages.** None ships a bundled `dist`. Every one publishes raw TypeScript with unbundled runtime `dependencies`, and none ships a lockfile. The `bundled = true` code path is retained for future pins but is unused by the initial set.
5. None of the six reads its configuration from pi's `settings.json`. `pi-mcp-adapter` reads `~/.config/mcp/mcp.json` and `~/.agents/mcp.json`; `@juicesharp/rpiv-todo` reads its own `rpiv-todo` JSON config. `passthru.settings` is therefore `{ }` for all six today — the mechanism exists and is tested, but the initial pin set does not exercise it.
6. Authorship, confirmed from the registry (the gallery and awesome-pi disagree): `pi-mcp-adapter` and `pi-subagents` are **nicobailon**, not `nicopreme`.

## Pin set as verified on 2026-08-18

| npm name | latest | repository | `pi.extensions` | `pi.skills` / `pi.prompts` |
| --- | --- | --- | --- | --- |
| `pi-mcp-adapter` | 2.26.1 | github.com/nicobailon/pi-mcp-adapter | `["./index.ts"]` | `skills` |
| `pi-subagents` | 0.51.0 | github.com/nicobailon/pi-subagents | `["./index.ts"]` | `skills`, `prompts` |
| `pi-background-tasks` | 2.4.2 | github.com/ismailsaleekh/pi-background-tasks | `["./extensions/anthropic-attribution.ts", "./extensions/background-tasks.ts"]` | — |
| `@plannotator/pi-extension` | 0.27.4 | github.com/backnotprop/plannotator (`apps/pi-extension`) | `["./"]` | — |
| `@juicesharp/rpiv-todo` | 2.6.2 | github.com/juicesharp/rpiv-mono (`packages/rpiv-todo`) | `["./index.ts"]` | — |
| `@gotgenes/pi-permission-system` | 26.3.0 | github.com/gotgenes/pi-packages (`packages/pi-permission-system`) | `["./src/index.ts"]` | — |

---

### Task 1: Rename bookkeeping and the eval-test harness

Rename the fork, document the rebase procedure, and stand up the `checks` output every later task's tests hang off. Nothing functional changes.

**Files:**
- Modify: `flake.nix` (description, `checks` output)
- Modify: `README.md` (rewrite)
- Create: `docs/REBASING.md`
- Create: `tests/default.nix`
- Create: `tests/smoke-test.nix`
- Create: `garnix.yaml`

**Interfaces:**
- Consumes: nothing (first task)
- Produces:
  - `checks.<system>.<name>` — an attrset assembled by `tests/default.nix`, which takes `{ pkgs, self, jail-nix }` and returns an attrset of derivations. Every later task adds one entry.

- [ ] **Step 1: Write the failing test**

Create `tests/smoke-test.nix`:

```nix
# Proves the checks plumbing works end to end before any real test depends on
# it. If this ever fails, the harness is broken, not the code under test.
{ pkgs, ... }:
pkgs.runCommand "pi-nix-smoke-test" { } ''
  set -euo pipefail
  test "$(echo pi-nix)" = "pi-nix"
  touch $out
''
```

Create `tests/default.nix`:

```nix
# Every check in this repo is assembled here so flake.nix has exactly one
# insertion point. Each test file takes the same argument set; unused
# arguments are absorbed by the `...` in its header.
{
  pkgs,
  self,
  jail-nix,
}:
let
  args = { inherit pkgs self jail-nix; };
in
{
  smoke = import ./smoke-test.nix args;
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run:
```bash
cd /home/joe/Development/pi-nix && nix build .#checks.x86_64-linux.smoke -L 2>&1 | tail -3
```

Expected: `error: flake 'git+file:///home/joe/Development/pi-nix' does not provide attribute 'packages.x86_64-linux.checks.x86_64-linux.smoke', 'legacyPackages.x86_64-linux.checks...'` — the `checks` output does not exist yet.

- [ ] **Step 3: Add the `checks` output to `flake.nix`**

In `flake.nix`, insert a new output immediately after the closing `);` of the `packages = forEachSystem (...)` block (i.e. after the line `      );` that ends at line 98, before `      lib =`):

```nix
      checks = forEachSystem (
        system:
        let
          pkgs = import nixpkgs { inherit system; };
        in
        import ./tests {
          inherit pkgs self jail-nix;
        }
      );
```

- [ ] **Step 4: Run the test to verify it passes**

Run:
```bash
cd /home/joe/Development/pi-nix && nix build .#checks.x86_64-linux.smoke -L && echo HARNESS-OK
```

Expected: `HARNESS-OK`.

- [ ] **Step 5: Change the flake description**

In `flake.nix`, replace line 2:

```nix
  description = "pi-mono";
```

with:

```nix
  description = "pi-nix: a Nix flake for the pi coding agent, with pinned ecosystem extensions and agent-stack integration";
```

- [ ] **Step 6: Write `docs/REBASING.md`**

```markdown
# Rebasing on upstream

This repo is a fork of [lukasl-dev/pi.nix](https://github.com/lukasl-dev/pi.nix),
kept deliberately additive so upstream can be replayed underneath our changes.

## What is ours

Everything below is new; upstream has no file at these paths, so a rebase never
touches them:

- `lib/` — `mkPiSkill`, `mkPiPromptTemplate`, `mkPiPlugin`
- `packages/extensions/` — `mkPiExtension` and one `package-lock.json` per pin
- `extensions.json` — the extension pin file
- `coding-agent/extra-options.nix` — `systemPrompt`, `extensionPackages`,
  `statusline`, `notifications`
- `tests/`, `update-extensions.nix`, `docs/REBASING.md`, `garnix.yaml`

## What we edit upstream

Only these, and only as insertions:

| File | Our change |
| --- | --- |
| `flake.nix` | `agent-statusline` input, `checks` output, `packages.ext-*`, `lib.builders`, `apps.update-extensions`, description |
| `update.nix` | takes `updateExtensions`, runs `pi-update-extensions` last |
| `coding-agent/lib.nix` | one line adding `extra-options.nix` to `modules` |
| `coding-agent/module.nix` | one line adding `extra-options.nix` to `imports` |
| `coding-agent/home-manager.nix` | one line adding `extra-options.nix` to `imports` |
| `README.md` | rewritten for the fork |

`coding-agent/options.nix` is **never** modified. Our options module reaches
pi's command line through `extraArgs`, `extensions`, `skills`,
`promptTemplates`, `settings`, and `environment`, all of which merge across
module definitions.

## Procedure

```bash
git fetch upstream
git rebase upstream/master
```

Expect conflicts only in the six files in the table above. Resolve by keeping
**both** sides: upstream's version of the surrounding code plus our insertion.
Never resolve a conflict by dropping an upstream hunk.

Then prove the fork is still additive and still works:

```bash
nix fmt
nix flake check -L
git diff upstream/master --stat -- \
  coding-agent/options.nix coding-agent/package.nix coding-agent/package-bun.nix \
  coding-agent/bun.nix sync-upstream.nix regenerate-models.nix scan.nix \
  VERSION.json package-lock.json bun.lock ai
```

The `git diff` must print nothing. If it does not, an upstream file was
restructured and the next rebase will be painful — revert that hunk.
```

- [ ] **Step 7: Rewrite `README.md`**

```markdown
# pi-nix

A Nix flake for [pi](https://github.com/earendil-works/pi), the terminal coding
agent — a fork of [lukasl-dev/pi.nix](https://github.com/lukasl-dev/pi.nix)
extended for the agent stack described in `agent-skills/docs/plans/2026-08-18-pi-nix-agent-stack-design.md`.

Upstream provides the packages, the NixOS/Home Manager modules, the jail.nix
sandbox wiring, and `lib.mkCodingAgent`. This fork adds, all additively:

| Addition | What it is |
| --- | --- |
| `systemPrompt` | `--system-prompt`, which *replaces* pi's default prompt. Upstream's `rules` only appends. |
| `packages.ext-*` | Purely pinned ecosystem extensions built from npm tarballs. |
| `extensionPackages` | Enable a pinned extension by listing its derivation; entrypoints, skills, prompts, and settings follow from its `passthru`. |
| `statusline` | Wires the [agent-statusline](https://github.com/joegoldin/agent-statusline) pi extension and its config JSON. |
| `notifications` | Option surface for the first-party `pi-notify` extension. |
| `lib/` | `mkPiSkill` / `mkPiPromptTemplate` / `mkPiPlugin`, the builders `agent-skills` imports as `piLib`. |
| `nix run .#update` | Bumps `VERSION.json` *and* every extension pin in `extensions.json`. |

See [docs/REBASING.md](docs/REBASING.md) before pulling upstream.

## Quick start

```bash
nix run github:joegoldin/pi-nix --accept-flake-config
```

## Binary cache

Upstream's cachix config is retained. Add both substituters, or pass
`--accept-flake-config`:

```nix
nix.settings = {
  extra-substituters = [
    "https://pi.cachix.org"
    "https://nix-community.cachix.org"
  ];
  extra-trusted-public-keys = [
    "pi.cachix.org-1:lGeoGJaZ5ZDabuRzkcD5EBTNnDM4HJ1vqeOxlWk1Flk="
    "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
  ];
};
```

## Home Manager

```nix
{ inputs, pkgs, ... }:
{
  imports = [ inputs.pi-nix.homeModules.default ];

  programs.pi.coding-agent = {
    enable = true;
    systemPrompt = ./SYSTEM.md;
    extensionPackages = with inputs.pi-nix.packages.${pkgs.system}; [
      ext-pi-mcp-adapter
      ext-pi-subagents
      ext-juicesharp-rpiv-todo
    ];
    statusline.enable = true;
  };
}
```

## Known upstream behaviour, retained

Upstream's `settings` option **jq-merges** into `~/.pi/agent/settings.json` on
every launch rather than writing a store symlink. That is deliberate — pi writes
to that file itself via `/login` and `/model` — but it means a Nix-declared
setting wins over an interactive `/model` choice on the next run. This is the
same trade-off `dotfiles/modules/ai/codex.nix` already documents. The behaviour
is kept as-is.

## Options

Generate the full reference:

```sh
nix build .#docs-md
nix build .#docs-html
```

## Upstream

Upstream's own README, cachix cache, and issue tracker remain the reference for
everything not in the table above. See
[earendil-works/pi#2310](https://github.com/earendil-works/pi/issues/2310) for
why an official flake does not exist.
```

- [ ] **Step 8: Add `garnix.yaml`**

Design §14 puts pi-nix's eval tests on garnix alongside the other repos. Without a `builds` key garnix builds every flake output including `checks`, which is exactly what we want; the file exists to pin `include` so a future artifact stanza has somewhere to live.

```yaml
builds:
  include:
    - "checks.*.*"
    - "packages.*.coding-agent"
    - "packages.*.ext-*"
```

- [ ] **Step 9: Format and commit**

```bash
cd /home/joe/Development/pi-nix
nix fmt
nix flake check -L
git add -A
git commit -m "chore: rename the fork to pi-nix and add the eval-test harness

flake.nix gains a checks output assembled by tests/default.nix, which every
later task extends with one entry. docs/REBASING.md records which files are
ours, which upstream files we may insert into, and the diff command that
proves the fork stayed additive."
```

---

### Task 2: `lib/` — the pi package builders

`mkPiSkill`, `mkPiPromptTemplate`, and `mkPiPlugin`, in the shape `claude-nix/lib` uses, so `agent-skills` can add a fourth entry to its `targetLibs` map. Without these the `pi` target in phase 4 has nothing to build with.

**Files:**
- Create: `lib/default.nix`
- Create: `lib/mkPiSkill.nix`
- Create: `lib/mkPiPromptTemplate.nix`
- Create: `lib/mkPiPlugin.nix`
- Create: `tests/lib-test.nix`
- Modify: `tests/default.nix`
- Modify: `flake.nix` (expose `lib.builders`)

**Interfaces:**
- Consumes: the `checks` harness from Task 1
- Produces:
  - `import "${pi-nix}/lib" { inherit pkgs lib; }` → an attrset. This is the exact call shape `agent-skills/flake.nix` already uses for `codexLib` and `agyLib`, and is what it will import as `piLib`.
  - `mkPiSkill { name, description, allowed-tools ? [ ], extraFrontmatter ? { }, extraFiles ? [ ] } body` → derivation with `$out/skills/<name>/SKILL.md`
  - `mkPiPromptTemplate { name, description ? null, argument-hint ? null, extraFrontmatter ? { } } body` → derivation with `$out/prompts/<name>.md`
  - `mkPiPlugin { name, description ? "", version ? "0.0.0", skills ? [ ], prompts ? [ ], extensions ? [ ], themes ? [ ] }` → derivation with `$out/package.json` carrying the `pi` manifest, plus the passthru contract of Task 3 (`piEntrypoint`, `piSkills`, `piPrompts`, `settings`, `promptFragment`) so a first-party plugin and a pinned npm extension are interchangeable in `extensionPackages`
  - Aliases `mkSkill = mkPiSkill` and `mkPlugin = mkPiPlugin`, so the attrset drops into `agent-skills`' `targetLibs` (whose `mkCrossAgentPlugin` calls `targetLib.mkSkill` and `targetLib.mkPlugin`) unchanged
  - `self.lib.builders.<system>` — the same attrset, reachable from the flake

- [ ] **Step 1: Write the failing test**

Create `tests/lib-test.nix`:

```nix
# Builder tests are shell assertions against built outputs rather than eval
# assertions, because what matters is the bytes pi will read: the SKILL.md
# frontmatter, the prompt filename, and the pi manifest inside package.json.
{ pkgs, ... }:
let
  lib = pkgs.lib;
  piLib = import ../lib { inherit pkgs lib; };

  skill = piLib.mkPiSkill {
    name = "demo-skill";
    description = "A demo skill used by the pi-nix builder tests.";
    allowed-tools = [
      "read"
      "Bash(git log:*)"
    ];
    extraFrontmatter.disable-model-invocation = true;
  } "Body of the demo skill.";

  bareSkill = piLib.mkPiSkill {
    name = "bare-skill";
    description = "No tools declared.";
  } "Bare body.";

  prompt = piLib.mkPiPromptTemplate {
    name = "review";
    description = "Review staged git changes";
    argument-hint = "[file-pattern]";
  } "Review $1 and summarise $@.";

  barePrompt = piLib.mkPiPromptTemplate { name = "bare"; } "No frontmatter here.";

  plugin = piLib.mkPiPlugin {
    name = "demo-plugin";
    description = "A demo pi package.";
    version = "1.2.3";
    skills = [ skill ];
    prompts = [ prompt ];
  };
in
pkgs.runCommand "pi-nix-lib-tests" { nativeBuildInputs = [ pkgs.jq ]; } ''
  set -euo pipefail

  # ── mkPiSkill ────────────────────────────────────────────────────────────
  md=${skill}/skills/demo-skill/SKILL.md
  test -f "$md"
  grep -qx 'name: demo-skill' "$md"
  grep -qx 'description: A demo skill used by the pi-nix builder tests.' "$md"
  # Entries containing spaces must be comma-joined; a space join would shear
  # "Bash(git log:*)" mid-entry.
  grep -qx 'allowed-tools: read, Bash(git log:*)' "$md"
  grep -qx 'disable-model-invocation: true' "$md"
  grep -qx 'Body of the demo skill.' "$md"

  # An empty allowed-tools line would restrict the skill to no tools, so the
  # key must be absent rather than empty.
  bare=${bareSkill}/skills/bare-skill/SKILL.md
  test -f "$bare"
  ! grep -q 'allowed-tools' "$bare"

  # ── mkPiPromptTemplate ───────────────────────────────────────────────────
  # The filename is the slash command, so it must be exactly <name>.md.
  p=${prompt}/prompts/review.md
  test -f "$p"
  grep -qx 'description: Review staged git changes' "$p"
  grep -qx 'argument-hint: "[file-pattern]"' "$p"
  grep -qx 'Review $1 and summarise $@.' "$p"

  # With no frontmatter fields pi uses the first non-empty line as the
  # description, so no delimiters may be emitted at all.
  bp=${barePrompt}/prompts/bare.md
  test -f "$bp"
  ! grep -q -- '---' "$bp"

  # ── mkPiPlugin ───────────────────────────────────────────────────────────
  pj=${plugin}/package.json
  test -f "$pj"
  test "$(jq -r .name "$pj")" = demo-plugin
  test "$(jq -r .version "$pj")" = 1.2.3
  test "$(jq -r '.keywords[0]' "$pj")" = pi-package
  test "$(jq -r '.pi.skills[0]' "$pj")" = ./skills
  test "$(jq -r '.pi.prompts[0]' "$pj")" = ./prompts
  # No extensions were passed, so the key must be absent — an empty array
  # would make pi resolve zero entries and fall through to index.ts probing.
  test "$(jq -r 'has("extensions") | tostring' "$pj" )" = false
  test "$(jq -r '.pi | has("extensions") | tostring' "$pj")" = false
  test -f ${plugin}/skills/demo-skill/SKILL.md
  test -f ${plugin}/prompts/review.md

  touch $out
''
```

Register it in `tests/default.nix` by adding one line to the returned attrset:

```nix
  builders = import ./lib-test.nix args;
```

- [ ] **Step 2: Run the test to verify it fails**

Run:
```bash
cd /home/joe/Development/pi-nix && nix build .#checks.x86_64-linux.builders -L 2>&1 | tail -4
```

Expected: `error: path '/home/joe/Development/pi-nix/lib' does not exist` (raised while evaluating `import ../lib`).

- [ ] **Step 3: Write `lib/mkPiSkill.nix`**

```nix
{ pkgs, lib }:
# Agent Skills format, which pi consumes unchanged. pi is more permissive than
# Claude Code — it does not require `name` to match the parent directory — but
# we write the matching directory anyway so the same tree is valid for both.
{
  name,
  description,
  # List of tool names, or a pre-joined string. Entries containing spaces
  # (e.g. "Bash(git log:*)") force a comma join; a space join would shear them
  # mid-entry.
  allowed-tools ? [ ],
  # Any other SKILL.md frontmatter field pi accepts: license, compatibility,
  # metadata, disable-model-invocation.
  extraFrontmatter ? { },
  # Extra files copied alongside SKILL.md (scripts/, references/, assets/).
  extraFiles ? [ ],
}:
body:
let
  toolsValue =
    if builtins.isList allowed-tools then
      lib.concatStringsSep (if lib.any (t: lib.hasInfix " " t) allowed-tools then ", " else " ")
        allowed-tools
    else
      allowed-tools;

  formatValue =
    key: value:
    if builtins.isBool value then "${key}: ${lib.boolToString value}" else "${key}: ${toString value}";

  fields = [
    "name: ${name}"
    "description: ${description}"
  ]
  ++ lib.optional (allowed-tools != [ ] && allowed-tools != "") "allowed-tools: ${toolsValue}"
  ++ lib.mapAttrsToList formatValue extraFrontmatter;

  skillMd = pkgs.writeText "pi-skill-${name}-md" ''
    ---
    ${lib.concatStringsSep "\n" fields}
    ---

    ${body}
  '';

  copyExtras = lib.concatMapStringsSep "\n" (f: "cp -r ${f} $out/skills/${name}/") extraFiles;
in
pkgs.runCommand "pi-skill-${name}" { } ''
  mkdir -p $out/skills/${name}
  cp ${skillMd} $out/skills/${name}/SKILL.md
  ${copyExtras}
''
```

- [ ] **Step 4: Write `lib/mkPiPromptTemplate.nix`**

```nix
{ pkgs, lib }:
# pi prompt templates are slash commands: the filename becomes the command, so
# `review.md` is `/review`. Arguments use shell syntax ($1, $@, ${1:-default}),
# which is substituted by pi at expansion time, not here.
{
  name,
  # Shown in autocomplete. When omitted pi falls back to the first non-empty
  # line of the body, so an absent description is a valid choice, not a defect.
  description ? null,
  # <angle brackets> for required arguments, [square brackets] for optional.
  argument-hint ? null,
  extraFrontmatter ? { },
}:
body:
let
  formatValue =
    key: value:
    if builtins.isBool value then "${key}: ${lib.boolToString value}" else "${key}: ${toString value}";

  present = lib.filterAttrs (_: v: v != null) {
    inherit description;
    # Quoted so a hint that starts with `[` is not parsed as a YAML flow
    # sequence.
    argument-hint = if argument-hint == null then null else ''"${argument-hint}"'';
  }
  // extraFrontmatter;

  fields = lib.mapAttrsToList formatValue present;

  # No fields means no delimiters at all: an empty `---\n---` block would make
  # pi read the closing delimiter as the description's first line.
  frontmatter =
    if fields == [ ] then "" else "---\n" + lib.concatStringsSep "\n" fields + "\n---\n\n";

  file = pkgs.writeText "pi-prompt-${name}-md" (frontmatter + body + "\n");
in
pkgs.runCommand "pi-prompt-${name}" { } ''
  mkdir -p $out/prompts
  cp ${file} $out/prompts/${name}.md
''
```

- [ ] **Step 5: Write `lib/mkPiPlugin.nix`**

```nix
{ pkgs, lib }:
# A real pi package: a directory whose package.json carries the `pi` key. pi
# resolves that manifest when the directory is handed to `--extension`, and
# `keywords: ["pi-package"]` is what marks it as a package to `pi install`.
#
# The passthru mirrors mkPiExtension's contract exactly, so a first-party
# plugin and a pinned npm extension are interchangeable in the module's
# `extensionPackages` list.
{
  name,
  description ? "",
  version ? "0.0.0",
  # Derivations laying files out under the matching top-level directory.
  skills ? [ ],
  prompts ? [ ],
  extensions ? [ ],
  themes ? [ ],
  # Merged into ~/.pi/agent/settings.json when this plugin is enabled.
  settings ? { },
  # Escape hatch for a plugin whose extensions inject no promptSnippet of
  # their own. Normally null — registerTool already supplies guidance.
  promptFragment ? null,
}:
let
  # Only the surfaces this plugin actually ships are declared. An empty array
  # would make pi resolve zero entries and fall through to probing index.ts.
  piManifest =
    lib.optionalAttrs (extensions != [ ]) { extensions = [ "./extensions" ]; }
    // lib.optionalAttrs (skills != [ ]) { skills = [ "./skills" ]; }
    // lib.optionalAttrs (prompts != [ ]) { prompts = [ "./prompts" ]; }
    // lib.optionalAttrs (themes != [ ]) { themes = [ "./themes" ]; };

  manifest = {
    inherit name version description;
    keywords = [ "pi-package" ];
    pi = piManifest;
  };

  manifestDrv = pkgs.runCommand "pi-plugin-${name}-manifest" { } ''
    mkdir -p $out
    cp ${(pkgs.formats.json { }).generate "package.json" manifest} $out/package.json
  '';

  env = pkgs.buildEnv {
    name = "pi-plugin-${name}";
    paths = [ manifestDrv ] ++ skills ++ prompts ++ extensions ++ themes;
    pathsToLink = [
      "/"
    ];
  };
in
env
// {
  passthru = (env.passthru or { }) // {
    # A directory: pi reads the pi manifest above and loads what it declares.
    piEntrypoint = lib.optional (extensions != [ ]) "${env}";
    piSkills = lib.optional (skills != [ ]) "${env}/skills";
    piPrompts = lib.optional (prompts != [ ]) "${env}/prompts";
    inherit settings promptFragment;
    meta = {
      inherit name description;
    };
  };
}
```

- [ ] **Step 6: Write `lib/default.nix`**

```nix
# Imported by agent-skills as `piLib`, in the same shape as codex-nix/lib and
# antigravity-cli-nix/lib: `import "${pi-nix}/lib" { inherit pkgs lib; }`.
# claude-nix/lib is called with pkgs alone, so lib defaults from pkgs.
{
  pkgs,
  lib ? pkgs.lib,
}:
let
  mkPiSkill = import ./mkPiSkill.nix { inherit pkgs lib; };
  mkPiPromptTemplate = import ./mkPiPromptTemplate.nix { inherit pkgs lib; };
  mkPiPlugin = import ./mkPiPlugin.nix { inherit pkgs lib; };
in
{
  inherit mkPiSkill mkPiPromptTemplate mkPiPlugin;

  # agent-skills' mkCrossAgentPlugin calls targetLib.mkSkill and
  # targetLib.mkPlugin by those names, so the pi target slots into its
  # targetLibs map with no changes on that side.
  mkSkill = mkPiSkill;
  mkPlugin = mkPiPlugin;
}
```

- [ ] **Step 7: Run the test to verify it passes**

Run:
```bash
cd /home/joe/Development/pi-nix && nix build .#checks.x86_64-linux.builders -L && echo BUILDERS-OK
```

Expected: `BUILDERS-OK`.

- [ ] **Step 8: Expose the builders on the flake**

In `flake.nix`, the `lib` output is currently:

```nix
      lib =
        let
          coding-agent = import ./coding-agent/lib.nix {
            inherit self jail-nix;
            inherit (nixpkgs) lib;
          };
        in
        {
          inherit (coding-agent) mkCodingAgent;
        };
```

Replace only the final attrset (leaving `mkCodingAgent` where it is, so
`self.lib.mkCodingAgent` keeps working for existing consumers):

```nix
        {
          inherit (coding-agent) mkCodingAgent;

          # Per-system because the builders need pkgs. agent-skills imports
          # `${pi-nix}/lib` directly rather than going through this, but
          # exposing it keeps `nix eval .#lib.builders.x86_64-linux` honest.
          builders = forEachSystem (
            system:
            import ./lib {
              pkgs = import nixpkgs { inherit system; };
            }
          );
        };
```

- [ ] **Step 9: Verify the flake-level shape**

Run:
```bash
cd /home/joe/Development/pi-nix && nix eval --raw --expr \
  'builtins.concatStringsSep " " (builtins.attrNames (builtins.getFlake (toString ./.)).lib.builders.x86_64-linux)' --impure
```

Expected: `mkPiPlugin mkPiPromptTemplate mkPiSkill mkPlugin mkSkill`.

- [ ] **Step 10: Format and commit**

```bash
cd /home/joe/Development/pi-nix
nix fmt
nix flake check -L
git add -A
git commit -m "feat(lib): mkPiSkill, mkPiPromptTemplate, and mkPiPlugin

The builders agent-skills imports as piLib. mkSkill/mkPlugin aliases let the
attrset drop into agent-skills' targetLibs map unchanged. mkPiPlugin emits a
real pi package — package.json with the pi key — and carries the same
passthru contract as a pinned npm extension, so both are interchangeable in
the module's extensionPackages list."
```

---

### Task 3: `mkPiExtension`, `extensions.json`, and `packages.ext-*`

Purely pinned ecosystem extensions. This is where design assumption A4 gets settled: none of the six pins ships a bundled `dist`, so all six go through `buildNpmPackage`.

**Files:**
- Create: `packages/extensions/mk-pi-extension.nix`
- Create: `packages/extensions/default.nix`
- Create: `extensions.json`
- Create: `packages/extensions/<slug>/package-lock.json` × 6 (generated in Step 6)
- Create: `tests/extensions-test.nix`
- Modify: `tests/default.nix`
- Modify: `flake.nix` (add `ext-*` to `packages`)

**Interfaces:**
- Consumes: the `checks` harness from Task 1
- Produces:
  - `mkPiExtension { pname, version, url, hash, bundled ? false, packageLock ? null, npmDepsHash ? null, entrypoints ? [ ], skills ? [ ], prompts ? [ ], settings ? { }, promptFragment ? null }` → derivation
  - **The passthru contract**, identical for `mkPiExtension` and `mkPiPlugin`:
    - `passthru.piEntrypoint` — `list of str`, absolute paths handed verbatim to repeated `--extension` flags. Normally a one-element list holding the package root, which makes pi read the package's own `pi` manifest.
    - `passthru.piSkills` — `list of str`, absolute paths for `--skill`
    - `passthru.piPrompts` — `list of str`, absolute paths for `--prompt-template`
    - `passthru.settings` — `attrs`, merged into `~/.pi/agent/settings.json`
    - `passthru.promptFragment` — `null` or `str`, appended via `--append-system-prompt`
  - `packages.<system>.ext-<slug>` for each of the six pins
  - `extensions.json` — attrset keyed by npm name, each `{ version, url, hash, npmDepsHash, bundled, entrypoints, skills, prompts }`

- [ ] **Step 1: Write the failing test**

Create `tests/extensions-test.nix`:

```nix
# Two layers. The eval layer asserts the passthru contract and the argument
# handling of both bundled and unbundled modes without fetching anything; the
# build layer proves each real pin actually builds and lands a loadable
# entrypoint on disk.
{ pkgs, ... }:
let
  lib = pkgs.lib;
  exts = import ../packages/extensions { inherit pkgs lib; };
  mkPiExtension = pkgs.callPackage ../packages/extensions/mk-pi-extension.nix { };
  pins = builtins.fromJSON (builtins.readFile ../extensions.json);

  # A synthetic bundled pin. Never built — only its attributes are read — so
  # the fake hash costs nothing and the bundled branch stays under test even
  # though no real pin uses it.
  synthetic = mkPiExtension {
    pname = "@acme/pi-thing";
    version = "9.9.9";
    url = "https://registry.npmjs.org/@acme/pi-thing/-/pi-thing-9.9.9.tgz";
    hash = "sha512-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";
    bundled = true;
    entrypoints = [ "dist/index.js" ];
    skills = [ "skills" ];
    settings.acme.enabled = true;
    promptFragment = "Use the acme tool for acme things.";
  };

  expectedNames = [
    "ext-gotgenes-pi-permission-system"
    "ext-juicesharp-rpiv-todo"
    "ext-pi-background-tasks"
    "ext-pi-mcp-adapter"
    "ext-pi-subagents"
    "ext-plannotator-pi-extension"
  ];

  # Every pin must be complete: an unbundled pin without an npmDepsHash means
  # `nix run .#update` has not been run since it was added.
  pinComplete =
    _name: pin:
    pin.version != ""
    && lib.hasPrefix "https://registry.npmjs.org/" pin.url
    && lib.hasPrefix "sha512-" pin.hash
    && (if pin.bundled then pin.npmDepsHash == null else lib.hasPrefix "sha256-" pin.npmDepsHash);

  evalAssertions =
    assert lib.sort (a: b: a < b) (builtins.attrNames exts) == expectedNames;
    assert synthetic.passthru.piEntrypoint == [ "${synthetic}/dist/index.js" ];
    assert synthetic.passthru.piSkills == [ "${synthetic}/skills" ];
    assert synthetic.passthru.piPrompts == [ ];
    assert synthetic.passthru.settings == { acme.enabled = true; };
    assert synthetic.passthru.promptFragment == "Use the acme tool for acme things.";
    # An empty entrypoints list means "hand pi the package root and let it read
    # the pi manifest", which is the normal path for every real pin.
    assert exts.ext-pi-mcp-adapter.passthru.piEntrypoint == [ "${exts.ext-pi-mcp-adapter}" ];
    assert exts.ext-pi-mcp-adapter.passthru.piSkills == [ "${exts.ext-pi-mcp-adapter}/skills" ];
    assert exts.ext-pi-subagents.passthru.piPrompts == [ "${exts.ext-pi-subagents}/prompts" ];
    assert exts.ext-pi-background-tasks.passthru.piSkills == [ ];
    assert exts.ext-pi-mcp-adapter.passthru.settings == { };
    assert exts.ext-pi-mcp-adapter.passthru.promptFragment == null;
    assert lib.all (n: pinComplete n pins.${n}) (builtins.attrNames pins);
    true;
in
assert evalAssertions;
pkgs.runCommand "pi-nix-extensions-tests" { nativeBuildInputs = [ pkgs.jq ]; } ''
  set -euo pipefail

  check() {
    local root="$1"
    test -f "$root/package.json"
    # Every pin publishes raw TypeScript against unbundled npm dependencies,
    # so node_modules must have been materialised at build time.
    test -d "$root/node_modules"
    # Each entry the pi manifest declares must actually exist, or pi silently
    # resolves zero entrypoints and the extension never loads.
    local n
    n=$(jq -r '[.pi.extensions[]?] | length' "$root/package.json")
    test "$n" -gt 0
    jq -r '.pi.extensions[]' "$root/package.json" | while read -r e; do
      test -e "$root/$e"
    done
  }

  check ${exts.ext-pi-mcp-adapter}
  check ${exts.ext-pi-subagents}
  check ${exts.ext-pi-background-tasks}
  check ${exts.ext-plannotator-pi-extension}
  check ${exts.ext-juicesharp-rpiv-todo}
  check ${exts.ext-gotgenes-pi-permission-system}

  # Skills and prompts advertised through the passthru must be real directories.
  test -d ${exts.ext-pi-mcp-adapter}/skills
  test -d ${exts.ext-pi-subagents}/skills
  test -d ${exts.ext-pi-subagents}/prompts

  touch $out
''
```

Register it in `tests/default.nix`:

```nix
  extensions = import ./extensions-test.nix args;
```

- [ ] **Step 2: Run the test to verify it fails**

Run:
```bash
cd /home/joe/Development/pi-nix && nix build .#checks.x86_64-linux.extensions -L 2>&1 | tail -4
```

Expected: `error: path '/home/joe/Development/pi-nix/packages/extensions' does not exist`.

- [ ] **Step 3: Write `packages/extensions/mk-pi-extension.nix`**

```nix
{
  lib,
  fetchurl,
  buildNpmPackage,
  runCommand,
}:
# One pinned pi extension from an npm tarball.
#
# `bundled` decides how node_modules is obtained:
#
#   true  — the tarball already carries everything it needs (vendored dist, or
#           no runtime dependencies at all). fetchurl + untar, nothing else.
#   false — the tarball ships source against unbundled dependencies, so
#           buildNpmPackage materialises node_modules from a vendored
#           package-lock.json. `nix run .#update-extensions` generates that
#           lockfile and the matching npmDepsHash.
#
# Design assumption A4 predicted `bundled = true` would be the common case. It
# is false for every package in the initial pin set: all six publish raw
# TypeScript with unbundled dependencies and no lockfile. The bundled branch is
# kept for future pins.
{
  pname,
  version,
  # npm dist.tarball
  url,
  # npm dist.integrity, usable verbatim as a Nix SRI hash
  hash,
  bundled ? false,
  packageLock ? null,
  npmDepsHash ? null,
  # Paths relative to the package root. Empty — the normal case — means "hand
  # pi the package root and let resolveExtensionEntries read the pi manifest
  # in package.json", which is what makes multi-entrypoint packages like
  # pi-background-tasks work without listing anything here.
  entrypoints ? [ ],
  skills ? [ ],
  prompts ? [ ],
  # Merged into ~/.pi/agent/settings.json when this extension is enabled.
  # Carrying config on the derivation lets the module compute settings from
  # *which* extensions are enabled, so adding or removing one is a single list
  # edit with no dangling config.
  settings ? { },
  # Escape hatch for an extension that supplies no promptSnippet or
  # promptGuidelines of its own. Normally null.
  promptFragment ? null,
  meta ? { },
}:
let
  slug = lib.replaceStrings [ "@" "/" ] [ "" "-" ] pname;

  src = fetchurl {
    inherit url hash;
    name = "${slug}-${version}.tgz";
  };

  drv =
    if bundled then
      runCommand "pi-ext-${slug}-${version}" { inherit src; } ''
        mkdir -p $out
        tar -xzf $src -C $out --strip-components=1
      ''
    else
      buildNpmPackage {
        pname = "pi-ext-${slug}";
        inherit version src npmDepsHash;

        # None of these packages publishes a lockfile, so the pin carries one
        # generated by the update app. postPatch runs before npmConfigHook,
        # which is exactly where upstream's coding-agent/package.nix drops
        # pi's own lockfile too.
        postPatch = ''
          cp ${packageLock} package-lock.json
        '';

        # The same omissions the update app used when generating the lockfile
        # and computing npmDepsHash. Diverging here makes `npm ci --offline`
        # ask for a tarball the prefetched cache does not hold.
        npmFlags = [
          "--ignore-scripts"
          "--omit=dev"
          "--omit=peer"
          "--omit=optional"
        ];

        # These are source packages, not build products: pi loads the .ts files
        # through jiti at runtime. There is nothing to build and nothing to
        # prune, and the default npmInstallHook would `npm pack` away the very
        # files the pi manifest points at.
        dontNpmBuild = true;

        installPhase = ''
          runHook preInstall
          mkdir -p $out
          cp -R . $out/
          runHook postInstall
        '';

        meta = {
          description = "pi extension ${pname}";
          homepage = "https://www.npmjs.com/package/${pname}";
        }
        // meta;
      };

  prefix = map (p: "${drv}/${p}");
in
drv
// {
  passthru = (drv.passthru or { }) // {
    piEntrypoint = if entrypoints == [ ] then [ "${drv}" ] else prefix entrypoints;
    piSkills = prefix skills;
    piPrompts = prefix prompts;
    inherit
      settings
      promptFragment
      pname
      version
      bundled
      ;
  };
}
```

- [ ] **Step 4: Write `packages/extensions/default.nix`**

```nix
{
  pkgs,
  lib ? pkgs.lib,
}:
# Every pin in extensions.json becomes packages.ext-<slug>. The pin file is
# read with fromJSON/readFile, never through IFD, so `nix flake show` stays
# evaluable offline.
let
  pins = builtins.fromJSON (builtins.readFile ../../extensions.json);

  mkPiExtension = pkgs.callPackage ./mk-pi-extension.nix { };

  slugOf = name: lib.replaceStrings [ "@" "/" ] [ "" "-" ] name;

  # Nix-side configuration per extension, merged into settings.json when the
  # extension is enabled. Every entry is `{ }` today: verified on 2026-08-18,
  # none of the six pins reads pi's settings.json — pi-mcp-adapter reads
  # ~/.config/mcp/mcp.json and ~/.agents/mcp.json, @juicesharp/rpiv-todo reads
  # its own rpiv-todo config file. The mechanism is here for pins that do, and
  # is exercised by the synthetic case in tests/extensions-test.nix.
  settingsFor = {
    pi-mcp-adapter = { };
    pi-subagents = { };
    pi-background-tasks = { };
    plannotator-pi-extension = { };
    juicesharp-rpiv-todo = { };
    gotgenes-pi-permission-system = { };
  };

  mkOne =
    name: pin:
    let
      slug = slugOf name;
    in
    mkPiExtension {
      pname = name;
      inherit (pin)
        version
        url
        hash
        bundled
        entrypoints
        skills
        prompts
        ;
      inherit (pin) npmDepsHash;
      packageLock = if pin.bundled then null else ./. + "/${slug}/package-lock.json";
      settings = settingsFor.${slug} or { };
      promptFragment = null;
    };
in
lib.mapAttrs' (name: pin: lib.nameValuePair "ext-${slugOf name}" (mkOne name pin)) pins
```

- [ ] **Step 5: Write the `extensions.json` skeleton**

`npmDepsHash` is `null` for every entry at this point; Step 6 fills it in by running the generator, which is also exactly what `nix run .#update` will do from Task 4 onward. Nothing here is a placeholder: version, url, hash, entrypoints, skills, and prompts are the values read off the registry on 2026-08-18.

```json
{
  "pi-mcp-adapter": {
    "version": "2.26.1",
    "url": "https://registry.npmjs.org/pi-mcp-adapter/-/pi-mcp-adapter-2.26.1.tgz",
    "hash": "sha512-6/KDXIEPXTVM77274jAloxAo9AQSEy5EJ/7afIlUK2T8HOfeVapTJvwImvyChiIH+0gGShbFgnBK2BXFrjbj2w==",
    "npmDepsHash": null,
    "bundled": false,
    "entrypoints": [],
    "skills": ["skills"],
    "prompts": []
  },
  "pi-subagents": {
    "version": "0.51.0",
    "url": "https://registry.npmjs.org/pi-subagents/-/pi-subagents-0.51.0.tgz",
    "hash": "sha512-qC9ndnMbuHefE6mGS2k69jP4htgbiQQG5jGnwCuKyK/pMcz5RFZ5nChrJ6JxPOBlpmVxsQzW27MCh0HDJCXxsA==",
    "npmDepsHash": null,
    "bundled": false,
    "entrypoints": [],
    "skills": ["skills"],
    "prompts": ["prompts"]
  },
  "pi-background-tasks": {
    "version": "2.4.2",
    "url": "https://registry.npmjs.org/pi-background-tasks/-/pi-background-tasks-2.4.2.tgz",
    "hash": "sha512-KDH2yv5yKnc2slUNMSsysVZleriuv8tbhe5L+AeplVAfijQsECN5YAWOz5TDbStCXLdJC15GaUQ1P87BXGk5Hg==",
    "npmDepsHash": null,
    "bundled": false,
    "entrypoints": [],
    "skills": [],
    "prompts": []
  },
  "@plannotator/pi-extension": {
    "version": "0.27.4",
    "url": "https://registry.npmjs.org/@plannotator/pi-extension/-/pi-extension-0.27.4.tgz",
    "hash": "sha512-9aK4v4AcjV/UwvAYvcT46fngIeMKmclv2glIYhzCIJiWKC0tfr4UQ5Aido7iveSfKlmbQuggCB/M018PxdbqnA==",
    "npmDepsHash": null,
    "bundled": false,
    "entrypoints": [],
    "skills": [],
    "prompts": []
  },
  "@juicesharp/rpiv-todo": {
    "version": "2.6.2",
    "url": "https://registry.npmjs.org/@juicesharp/rpiv-todo/-/rpiv-todo-2.6.2.tgz",
    "hash": "sha512-Lt2HzNaKWgOl7/nEJrxtRsKoIQJTZd32BeckDxJ0JGvoUmwYvqOicSpXbgKVZwyGqGBw90WBKYWkEggo9U/Q4Q==",
    "npmDepsHash": null,
    "bundled": false,
    "entrypoints": [],
    "skills": [],
    "prompts": []
  },
  "@gotgenes/pi-permission-system": {
    "version": "26.3.0",
    "url": "https://registry.npmjs.org/@gotgenes/pi-permission-system/-/pi-permission-system-26.3.0.tgz",
    "hash": "sha512-FqRVq+YvHgBBJShQK1wdlUik4QZMdTDv5a9drmxZK8pXpCy0XjLX0nXLVNntQL+KhdTQ56JlsunKqjgU5YDNbQ==",
    "npmDepsHash": null,
    "bundled": false,
    "entrypoints": [],
    "skills": [],
    "prompts": []
  }
}
```

- [ ] **Step 6: Generate the lockfiles and fill in `npmDepsHash`**

These are the exact values produced on 2026-08-18 by the procedure Task 4 turns into `nix run .#update-extensions`. Run the generator now so Task 3 can be verified before Task 4 exists:

Write the generator to a file first — the nested quoting of an inline `bash -c` string is a reliable source of silent breakage:

```bash
cd /home/joe/Development/pi-nix
cat > /tmp/pin-extensions.sh <<'SCRIPT'
#!/usr/bin/env bash
set -euo pipefail
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
export HOME="$tmp/home"
mkdir -p "$HOME"

for name in $(jq -r 'keys[]' extensions.json); do
  slug=$(printf '%s' "$name" | sed -e 's|^@||' -e 's|/|-|g')
  url=$(jq -r --arg n "$name" '.[$n].url' extensions.json)
  work="$tmp/$slug"
  mkdir -p "$work"
  curl -fsSL "$url" | tar -xzf - -C "$work" --strip-components=1
  (
    cd "$work"
    npm install --package-lock-only --omit=dev --omit=peer --omit=optional \
      --ignore-scripts --no-audit --no-fund >/dev/null 2>&1
    npm-lockfile-fix package-lock.json >/dev/null 2>&1
  )
  h=$(prefetch-npm-deps "$work/package-lock.json" | tail -n1)
  mkdir -p "packages/extensions/$slug"
  cp "$work/package-lock.json" "packages/extensions/$slug/package-lock.json"
  jq --arg n "$name" --arg h "$h" '.[$n].npmDepsHash = $h' extensions.json > "$tmp/next.json"
  mv "$tmp/next.json" extensions.json
  echo "$slug $h"
done
SCRIPT
chmod +x /tmp/pin-extensions.sh
nix shell nixpkgs#nodejs nixpkgs#npm-lockfile-fix nixpkgs#prefetch-npm-deps \
  nixpkgs#jq nixpkgs#curl nixpkgs#gnutar nixpkgs#gzip -c /tmp/pin-extensions.sh
```

Expected output — these hashes were computed and verified while writing this plan, so any divergence means the upstream package was republished and the pin needs re-verifying, not that the command is wrong:

```
pi-mcp-adapter sha256-yi4B+q1DNTTgiUspCnjyYaS7Wii3RmwpFF8BIN63UHQ=
pi-subagents sha256-n3GBMwldJ4siD28o7eQcHLmE0ccU1tWPtISVgkVPpVg=
pi-background-tasks sha256-3APHrC7eEU0cQ+hXpZOiic5i9iZmjcJrt3IIDCaVNhc=
plannotator-pi-extension sha256-iCuYF1cDsCOlseb9J1QtpOHk5EDXroleUUxl+Fcw19k=
juicesharp-rpiv-todo sha256-nu9wuAq/UIATsgCMDKssfEFIPbUgrdlDntADQFyjjlg=
gotgenes-pi-permission-system sha256-n90c2T6apiXbI51r2gYN9Gj6SiHgz09qIvnk/jjpD18=
```

Then confirm no pin was left incomplete:

```bash
cd /home/joe/Development/pi-nix && jq -r 'to_entries[] | select(.value.npmDepsHash == null) | .key' extensions.json
```

Expected: no output.

- [ ] **Step 7: Add the `ext-*` packages to `flake.nix`**

Inside the `packages = forEachSystem (...)` block, the returned `rec { ... }` (which holds `default`, `coding-agent`, `coding-agent-bun`, `docs-md`, `docs-html`) ends with these three lines — the close of `docs-html`, the close of the `rec` attrset, and the close of `forEachSystem`:

```nix
              '';
        }
      );
```

Replace exactly those three lines with:

```nix
              '';
        }
        // import ./packages/extensions { inherit pkgs; }
      );
```

`rec { ... } // extras` keeps every existing attribute and its internal recursion intact while adding the `ext-*` set alongside. Nothing inside the `rec` block is touched.

- [ ] **Step 8: Run the test to verify it passes**

Run:
```bash
cd /home/joe/Development/pi-nix && nix build .#checks.x86_64-linux.extensions -L && echo EXTENSIONS-OK
```

Expected: `EXTENSIONS-OK`. This builds all six extensions; the first run downloads roughly 1.5 GB of npm tarballs and takes several minutes.

If `ext-plannotator-pi-extension` fails at the `jq -r '.pi.extensions[]' | test -e` assertion, its manifest declares `"./"` — the package root itself. `path.resolve(dir, "./")` is the directory, which exists, so the assertion should pass; but if jiti then cannot import a directory at runtime, set `"entrypoints": ["index.ts"]` for that pin in `extensions.json` (the tarball does ship a root `index.ts`) and re-run. That override is exactly what the `entrypoints` field is for, and the update app never overwrites it.

- [ ] **Step 9: Verify the packages are visible on the flake**

Run:
```bash
cd /home/joe/Development/pi-nix && nix eval --raw --expr \
  'builtins.concatStringsSep "\n" (builtins.filter (n: builtins.substring 0 4 n == "ext-") (builtins.attrNames (builtins.getFlake (toString ./.)).packages.x86_64-linux))' --impure
```

Expected:
```
ext-gotgenes-pi-permission-system
ext-juicesharp-rpiv-todo
ext-pi-background-tasks
ext-pi-mcp-adapter
ext-pi-subagents
ext-plannotator-pi-extension
```

- [ ] **Step 10: Format and commit**

```bash
cd /home/joe/Development/pi-nix
nix fmt
git add -A
git commit -m "feat(packages): pinned pi extensions with a passthru config contract

Design assumption A4 is false: none of the six pins ships bundled dist
output. All publish raw TypeScript against unbundled npm dependencies with
no lockfile, so mkPiExtension vendors a generated package-lock.json and
builds node_modules with buildNpmPackage. The bundled branch is retained for
future pins and covered by a synthetic eval case.

piEntrypoint is a list, not a scalar: pi-background-tasks declares two
entrypoints and plannotator declares a directory. Handing pi the package root
lets resolveExtensionEntries read each package's own pi manifest, so the pin
file records no entrypoints at all in the normal case.

npm's dist.integrity is used verbatim as the Nix SRI hash."
```

---

### Task 4: Extend `nix run .#update` to bump extension pins

One command bumps `VERSION.json` *and* every entry in `extensions.json`, so pins cannot silently go stale.

**Files:**
- Create: `update-extensions.nix`
- Modify: `update.nix`
- Modify: `flake.nix` (instantiate and expose the new app)

**Interfaces:**
- Consumes: `extensions.json` from Task 3
- Produces:
  - `apps.<system>.update-extensions` — `${updateExtensions}/bin/pi-update-extensions`
  - `apps.<system>.update` now runs `pi-sync-upstream`, `pi-regenerate-models`, `pi-update-extensions` in that order
  - `pi-update-extensions` rewrites `extensions.json` (`version`, `url`, `hash`, `npmDepsHash`, `skills`, `prompts`) and `packages/extensions/<slug>/package-lock.json`. It never touches `bundled` or `entrypoints`, which are human decisions.

- [ ] **Step 1: Write the failing test**

Create `tests/update-app-test.nix`:

```nix
# The updater is network-bound, so the check is a contract test rather than a
# run: it proves the app exists, is shellcheck-clean (writeShellApplication
# enforces that at build time), and preserves the two fields that are human
# decisions rather than registry facts.
{ pkgs, ... }:
let
  updateExtensions = import ../update-extensions.nix { inherit pkgs; };
in
pkgs.runCommand "pi-nix-update-app-tests" { } ''
  set -euo pipefail
  script=${updateExtensions}/bin/pi-update-extensions
  test -x "$script"

  # `bundled` and `entrypoints` are overrides a human sets after inspecting a
  # package; a registry bump must never clobber them.
  ! grep -q '\.bundled *=' "$script"
  ! grep -q '\.entrypoints *=' "$script"

  # The fields it must write.
  grep -q 'npmDepsHash' "$script"
  grep -q 'dist.integrity' "$script"
  grep -q 'dist-tags' "$script"

  touch $out
''
```

Register it in `tests/default.nix`:

```nix
  update-app = import ./update-app-test.nix args;
```

- [ ] **Step 2: Run the test to verify it fails**

Run:
```bash
cd /home/joe/Development/pi-nix && nix build .#checks.x86_64-linux.update-app -L 2>&1 | tail -3
```

Expected: `error: path '/home/joe/Development/pi-nix/update-extensions.nix' does not exist`.

- [ ] **Step 3: Write `update-extensions.nix`**

```nix
{ pkgs }:

pkgs.writeShellApplication {
  name = "pi-update-extensions";
  runtimeInputs = with pkgs; [
    cacert
    coreutils
    curl
    gnused
    gnutar
    gzip
    jq
    nodejs
    npm-lockfile-fix
    prefetch-npm-deps
  ];
  text = # bash
    ''
      set -euo pipefail

      tmpdir=$(mktemp -d)
      trap 'rm -rf "$tmpdir"' EXIT
      export HOME="$tmpdir/home"
      mkdir -p "$HOME"

      cp extensions.json "$tmpdir/extensions.json"

      for name in $(jq -r 'keys[]' extensions.json); do
        slug=$(printf '%s' "$name" | sed -e 's|^@||' -e 's|/|-|g')
        enc=$(jq -rn --arg n "$name" '$n | @uri')

        meta=$(curl -fsSL "https://registry.npmjs.org/$enc")
        version=$(jq -r '."dist-tags".latest' <<< "$meta")
        vjson=$(jq -r --arg v "$version" '.versions[$v]' <<< "$meta")

        url=$(jq -r '.dist.tarball' <<< "$vjson")
        # npm publishes dist.integrity as an SRI string, which Nix accepts
        # verbatim. No prefetch needed, and no chance of a sha256/sha512 mixup.
        hash=$(jq -r '.dist.integrity' <<< "$vjson")

        # Skill and prompt directories come straight from the package's own pi
        # manifest, with the leading "./" stripped so they compose as
        # "''${drv}/''${path}".
        skills=$(jq -c '[.pi.skills[]? | sub("^\\./"; "")]' <<< "$vjson")
        prompts=$(jq -c '[.pi.prompts[]? | sub("^\\./"; "")]' <<< "$vjson")

        bundled=$(jq -r --arg n "$name" '.[$n].bundled' extensions.json)

        deps_hash=null
        if [[ "$bundled" != "true" ]]; then
          work="$tmpdir/$slug"
          mkdir -p "$work"
          curl -fsSL "$url" | tar -xzf - -C "$work" --strip-components=1

          # These packages publish no lockfile, so generate one from the
          # published package.json. The omissions must match mkPiExtension's
          # npmFlags exactly, or `npm ci --offline` will want a tarball the
          # prefetched cache does not hold.
          (
            cd "$work"
            npm install --package-lock-only \
              --omit=dev --omit=peer --omit=optional \
              --ignore-scripts --no-audit --no-fund >/dev/null
            # Upstream npm omits integrity for some resolved entries, which
            # makes prefetch-npm-deps panic. Same fix sync-upstream.nix applies
            # to pi's own lockfile.
            npm-lockfile-fix package-lock.json >/dev/null
          )

          deps_hash="\"$(prefetch-npm-deps "$work/package-lock.json" | tail -n1)\""
          mkdir -p "packages/extensions/$slug"
          cp "$work/package-lock.json" "packages/extensions/$slug/package-lock.json"
        fi

        jq \
          --arg n "$name" \
          --arg v "$version" \
          --arg u "$url" \
          --arg h "$hash" \
          --argjson d "$deps_hash" \
          --argjson s "$skills" \
          --argjson p "$prompts" \
          '.[$n].version = $v
           | .[$n].url = $u
           | .[$n].hash = $h
           | .[$n].npmDepsHash = $d
           | .[$n].skills = $s
           | .[$n].prompts = $p' \
          "$tmpdir/extensions.json" > "$tmpdir/next.json"
        mv "$tmpdir/next.json" "$tmpdir/extensions.json"

        echo "pinned $name@$version"
      done

      cp "$tmpdir/extensions.json" extensions.json
      echo "Updated extension pins in extensions.json"
    '';
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run:
```bash
cd /home/joe/Development/pi-nix && nix build .#checks.x86_64-linux.update-app -L && echo UPDATE-APP-OK
```

Expected: `UPDATE-APP-OK`. If it fails inside `writeShellApplication` with shellcheck diagnostics, fix the script — do not add `excludeShellChecks`.

- [ ] **Step 5: Wire it into `update.nix`**

Replace `update.nix` in full:

```nix
{
  pkgs,
  regenerateModels,
  syncUpstream,
  updateExtensions,
}:

pkgs.writeShellApplication {
  name = "pi-update";
  runtimeInputs = [
    regenerateModels
    syncUpstream
    updateExtensions
  ];
  text = # bash
    ''
      set -euo pipefail

      pi-sync-upstream
      pi-regenerate-models
      pi-update-extensions
    '';
}
```

- [ ] **Step 6: Wire it into `flake.nix`**

In the `apps = forEachSystem (...)` block, add an instantiation after `regenerateModels`:

```nix
          updateExtensions = import ./update-extensions.nix {
            inherit pkgs;
          };
```

change the `update` instantiation to pass it through:

```nix
          update = import ./update.nix {
            inherit pkgs regenerateModels syncUpstream updateExtensions;
          };
```

and add the app to the returned attrset, after the `regenerate-models` entry:

```nix
          update-extensions = {
            type = "app";
            program = "${updateExtensions}/bin/pi-update-extensions";
          };
```

- [ ] **Step 7: Prove the updater is a no-op against the pins from Task 3**

Run:
```bash
cd /home/joe/Development/pi-nix && cp extensions.json /tmp/extensions-before.json && nix run .#update-extensions && diff /tmp/extensions-before.json extensions.json && echo PINS-STABLE
```

Expected: `PINS-STABLE`, plus six `pinned <name>@<version>` lines. A non-empty diff means a pinned package was republished since this plan was written — inspect the diff, re-run `nix build .#checks.x86_64-linux.extensions -L`, and commit the bump with the rest of the task.

Also confirm the human-owned fields survived:

```bash
cd /home/joe/Development/pi-nix && jq -c 'to_entries | map({key, bundled: .value.bundled, entrypoints: .value.entrypoints})' extensions.json
```

Expected: every entry shows `"bundled":false` and `"entrypoints":[]` (or `["index.ts"]` for plannotator if Task 3 Step 8 required that override).

- [ ] **Step 8: Format and commit**

```bash
cd /home/joe/Development/pi-nix
nix fmt
nix flake check -L
git add -A
git commit -m "feat(update): bump every extension pin from nix run .#update

pi-update-extensions reads each package's latest version, tarball URL, and
dist.integrity straight off the registry — integrity is an SRI string Nix
accepts verbatim — regenerates the vendored lockfile, and recomputes
npmDepsHash with the same omissions mkPiExtension builds with. bundled and
entrypoints are human overrides and are never rewritten."
```

---

### Task 5: `extra-options.nix` and the `systemPrompt` option

Upstream only has `rules` → `--append-system-prompt`. Replacement of pi's default prompt is a stated goal of the design, and it needs `--system-prompt`. This task also establishes the additive module that Tasks 6–8 extend.

**Files:**
- Create: `coding-agent/extra-options.nix`
- Modify: `coding-agent/lib.nix` (one line)
- Modify: `coding-agent/module.nix` (one line)
- Modify: `coding-agent/home-manager.nix` (one line)
- Create: `tests/options-test.nix`
- Modify: `tests/default.nix`

**Interfaces:**
- Consumes: `self` (for `self.inputs.agent-statusline`, first used in Task 7) and `optionPath`, matching `coding-agent/options.nix`'s own signature
- Produces:
  - `pi.coding-agent.systemPrompt` — `nullOr (either lines path)`, default `null`
  - `pi.coding-agent.finalSystemPrompt` — internal, readOnly, `nullOr path`
  - `pi.coding-agent.extraArgs` gains `[ "--system-prompt" "<path>" ]` via `mkAfter`, so it lands after upstream's `resourceArgs` and after any `extraArgs` the user set
  - The module contributes **only** through `extraArgs`, `extensions`, `skills`, `promptTemplates`, `settings`, and `environment` — all list- or attr-typed, so definitions merge and `coding-agent/options.nix` never has to change

- [ ] **Step 1: Write the failing test**

Create `tests/options-test.nix`:

```nix
# Module tests are pure evaluation: build the same module list mkCodingAgent
# builds, then assert on finalArgs. `self` is stubbed so the test does not
# need the real coding-agent closure to check argument construction.
{ pkgs, ... }:
let
  lib = pkgs.lib;
  system = pkgs.stdenv.hostPlatform.system;

  statuslineStub = {
    statuslineOptions = {
      enable = lib.mkEnableOption "the agent statusline";
      package = lib.mkOption {
        type = lib.types.package;
        description = "The agent-statusline package to use.";
      };
      padding = lib.mkOption {
        type = lib.types.int;
        default = 0;
        description = "Left padding, in columns.";
      };
    };
    renderConfig = _cfg: pkgs.writeText "agent-statusline-config.json" ''{"padding":0}'';
  };

  selfStub = {
    packages.${system}.coding-agent = pkgs.hello;
    inputs.agent-statusline = {
      lib.${system} = statuslineStub;
      packages.${system} = {
        agent-statusline = pkgs.hello;
        pi-extension = pkgs.hello;
      };
    };
  };

  evalPi =
    module:
    (lib.evalModules {
      specialArgs = {
        self = selfStub;
        inherit pkgs;
      };
      modules = [
        (import ../coding-agent/options.nix {
          self = selfStub;
          jail-nix = null;
        })
        (import ../coding-agent/extra-options.nix {
          self = selfStub;
        })
        module
      ];
    }).config.pi.coding-agent;

  argPair =
    args: flag:
    let
      idx = lib.lists.findFirstIndex (a: a == flag) null args;
    in
    if idx == null then null else builtins.elemAt args (idx + 1);

  # ── unset ────────────────────────────────────────────────────────────────
  bare = evalPi { };

  # ── inline text ──────────────────────────────────────────────────────────
  inline = evalPi { pi.coding-agent.systemPrompt = "You are terse.\n"; };

  # ── coexisting with upstream's rules ─────────────────────────────────────
  both = evalPi {
    pi.coding-agent = {
      systemPrompt = "Replacement prompt.\n";
      rules = "Appended preferences.\n";
    };
  };

  # ── user extraArgs must survive ──────────────────────────────────────────
  withExtra = evalPi {
    pi.coding-agent = {
      systemPrompt = "Replacement prompt.\n";
      extraArgs = [
        "--provider"
        "openai"
      ];
    };
  };
in
assert !(lib.elem "--system-prompt" bare.finalArgs);
assert bare.finalSystemPrompt == null;
assert lib.elem "--system-prompt" inline.finalArgs;
assert inline.finalSystemPrompt != null;
assert argPair inline.finalArgs "--system-prompt" == "${inline.finalSystemPrompt}";
# --system-prompt replaces, --append-system-prompt appends; both may be present
# and pi applies them in that order.
assert lib.elem "--system-prompt" both.finalArgs;
assert lib.elem "--append-system-prompt" both.finalArgs;
assert argPair both.finalArgs "--append-system-prompt" == "${both.finalRules}";
assert lib.elem "--provider" withExtra.finalArgs;
assert argPair withExtra.finalArgs "--provider" == "openai";
assert lib.elem "--system-prompt" withExtra.finalArgs;
pkgs.runCommand "pi-nix-options-tests" { } ''
  set -euo pipefail
  # The written prompt must be the literal text, with no wrapper or frontmatter.
  grep -qx 'You are terse.' ${inline.finalSystemPrompt}
  touch $out
''
```

Register it in `tests/default.nix`:

```nix
  options = import ./options-test.nix args;
```

- [ ] **Step 2: Run the test to verify it fails**

Run:
```bash
cd /home/joe/Development/pi-nix && nix build .#checks.x86_64-linux.options -L 2>&1 | tail -4
```

Expected: `error: path '/home/joe/Development/pi-nix/coding-agent/extra-options.nix' does not exist`.

- [ ] **Step 3: Write `coding-agent/extra-options.nix`**

```nix
{
  self,
  optionPath ? [
    "pi"
    "coding-agent"
  ],
}:
{
  config,
  pkgs,
  lib,
  ...
}:

# Everything pi-nix adds on top of lukasl-dev/pi.nix lives here, in a second
# module merged alongside coding-agent/options.nix. That file is upstream's and
# is never edited: this module reaches pi's command line through option
# surfaces upstream already exposes and that merge across definitions —
# `extraArgs`, `extensions`, `skills`, `promptTemplates`, `settings`, and
# `environment`. Keeping the diff to three one-line `imports` additions is what
# makes `git rebase upstream/master` a fast-forward.
let
  cfg = lib.attrByPath optionPath { } config;

  toFile =
    stem: value:
    if value == null then
      null
    else if builtins.isPath value then
      value
    else
      pkgs.writeText stem value;

  systemPromptPath = toFile "pi-SYSTEM.md" cfg.systemPrompt;

  systemPromptArgs = lib.optionals (systemPromptPath != null) [
    "--system-prompt"
    "${systemPromptPath}"
  ];
in
{
  options = lib.setAttrByPath optionPath {
    systemPrompt = lib.mkOption {
      type = lib.types.nullOr (
        lib.types.either lib.types.lines (lib.types.addCheck lib.types.path builtins.isPath)
      );
      default = null;
      description = ''
        System prompt passed to pi via `--system-prompt`, **replacing** pi's
        default prompt entirely. Skills, context files, and the working
        directory are still appended by pi afterwards, and `rules` still
        appends through `--append-system-prompt`, so the two options compose.

        This can be inline text or a Nix path. Upstream's `rules` option only
        appends; replacement is a separate flag and a separate option.
      '';
      example = lib.literalExpression "./SYSTEM.md";
    };

    finalSystemPrompt = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      internal = true;
      readOnly = true;
    };
  };

  config = lib.setAttrByPath optionPath {
    finalSystemPrompt = systemPromptPath;

    # mkAfter so our flags land behind anything the user set, and behind
    # upstream's resourceArgs (which are concatenated before extraArgs in
    # options.nix's wrapper).
    extraArgs = lib.mkAfter systemPromptArgs;
  };
}
```

- [ ] **Step 4: Add the module to the three upstream entrypoints**

In `coding-agent/lib.nix`, change:

```nix
        modules = [ (import ./options.nix { inherit self jail-nix; }) ] ++ modules;
```

to:

```nix
        modules = [
          (import ./options.nix { inherit self jail-nix; })
          (import ./extra-options.nix { inherit self; })
        ]
        ++ modules;
```

In `coding-agent/module.nix` **and** `coding-agent/home-manager.nix`, both of which have the same `imports` block, add one entry after the existing `(import ./options.nix { ... })`:

```nix
    (import ./extra-options.nix {
      inherit self;
      optionPath = [
        "programs"
        "pi"
        "coding-agent"
      ];
    })
```

- [ ] **Step 5: Run the test to verify it passes**

Run:
```bash
cd /home/joe/Development/pi-nix && nix build .#checks.x86_64-linux.options -L && echo OPTIONS-OK
```

Expected: `OPTIONS-OK`.

- [ ] **Step 6: Verify the wrapper actually carries the flag**

Run:
```bash
cd /home/joe/Development/pi-nix && nix eval --impure --raw --expr '
  let
    flake = builtins.getFlake (toString ./.);
    pkgs = import flake.inputs.nixpkgs { system = "x86_64-linux"; };
    agent = flake.lib.mkCodingAgent {
      inherit pkgs;
      modules = [ { pi.coding-agent.systemPrompt = "Be terse.\n"; } ];
    };
  in
  builtins.concatStringsSep " " agent.args'
```

Expected: `--system-prompt /nix/store/…-pi-SYSTEM.md`.

- [ ] **Step 7: Confirm `options.nix` is still byte-identical to upstream**

Run:
```bash
cd /home/joe/Development/pi-nix && git diff upstream/master --stat -- coding-agent/options.nix && echo OPTIONS-NIX-UNTOUCHED
```

Expected: `OPTIONS-NIX-UNTOUCHED` with no diffstat lines above it.

- [ ] **Step 8: Format and commit**

```bash
cd /home/joe/Development/pi-nix
nix fmt
nix flake check -L
git add -A
git commit -m "feat(options): systemPrompt, wiring pi's --system-prompt

Upstream only has rules -> --append-system-prompt; replacing pi's default
prompt needs the other flag. Verified against pi v0.84.2: --system-prompt
takes text, and resolvePromptInput reads it as a file when the argument is an
existing path, so a store path works exactly as rules already does.

All of pi-nix's additions live in a second module merged alongside
options.nix, which stays byte-identical to upstream. The module reaches the
command line through extraArgs, which options.nix appends after its own
resourceArgs."
```

---

### Task 6: `extensionPackages` — consuming the passthru contract

Enabling an extension becomes a single list edit. Its entrypoints, skills, prompts, settings, and prompt fragment all follow from the derivation, so there is no dangling config when one is removed.

**Files:**
- Modify: `coding-agent/extra-options.nix`
- Modify: `tests/options-test.nix`

**Interfaces:**
- Consumes: `passthru.piEntrypoint`, `passthru.piSkills`, `passthru.piPrompts`, `passthru.settings`, `passthru.promptFragment` from Task 3; `mkPiPlugin`'s identical passthru from Task 2
- Produces:
  - `pi.coding-agent.extensionPackages` — `listOf package`, default `[ ]`
  - Contributions to upstream's `extensions`, `skills`, `promptTemplates`, and `settings` options
  - `[ "--append-system-prompt" "<fragments file>" ]` on `extraArgs` when any enabled extension carries a non-null `promptFragment`

- [ ] **Step 1: Write the failing test**

Append to `tests/options-test.nix`, before the final `assert` chain. Add these `let` bindings:

```nix
  fakeExt =
    name: passthru:
    (pkgs.runCommand "fake-pi-ext-${name}" { } ''
      mkdir -p $out/skills $out/prompts
      touch $out/index.ts
    '').overrideAttrs
      (old: { passthru = (old.passthru or { }) // passthru; });

  extA = fakeExt "a" {
    piEntrypoint = [ "/nix/store/fake-a" ];
    piSkills = [ "/nix/store/fake-a/skills" ];
    piPrompts = [ ];
    settings = {
      alpha = true;
      shared.fromA = 1;
    };
    promptFragment = null;
  };

  extB = fakeExt "b" {
    piEntrypoint = [
      "/nix/store/fake-b/one.ts"
      "/nix/store/fake-b/two.ts"
    ];
    piSkills = [ ];
    piPrompts = [ "/nix/store/fake-b/prompts" ];
    settings = {
      beta = 2;
      shared.fromB = 2;
    };
    promptFragment = "Use the beta tool when beta-ing.";
  };

  withExts = evalPi {
    pi.coding-agent.extensionPackages = [
      extA
      extB
    ];
  };

  flagValues =
    args: flag:
    let
      indexed = lib.imap0 (i: a: { inherit i a; }) args;
    in
    map (e: builtins.elemAt args (e.i + 1)) (lib.filter (e: e.a == flag) indexed);
```

and these assertions:

```nix
# Every entrypoint of every enabled extension becomes its own --extension flag.
assert flagValues withExts.finalArgs "--extension" == [
  "/nix/store/fake-a"
  "/nix/store/fake-b/one.ts"
  "/nix/store/fake-b/two.ts"
];
assert flagValues withExts.finalArgs "--skill" == [ "/nix/store/fake-a/skills" ];
assert flagValues withExts.finalArgs "--prompt-template" == [ "/nix/store/fake-b/prompts" ];
# settings are deep-merged, so two extensions can contribute to one subtree.
assert withExts.settings.alpha == true;
assert withExts.settings.beta == 2;
assert withExts.settings.shared == {
  fromA = 1;
  fromB = 2;
};
# A non-null promptFragment is appended, never used to replace the prompt.
assert lib.length (flagValues withExts.finalArgs "--append-system-prompt") == 1;
# An extension with no fragment contributes nothing at all.
assert flagValues (evalPi { pi.coding-agent.extensionPackages = [ extA ]; }).finalArgs
  "--append-system-prompt" == [ ];
```

- [ ] **Step 2: Run the test to verify it fails**

Run:
```bash
cd /home/joe/Development/pi-nix && nix build .#checks.x86_64-linux.options -L 2>&1 | tail -4
```

Expected: `error: The option 'pi.coding-agent.extensionPackages' does not exist.`

- [ ] **Step 3: Implement in `coding-agent/extra-options.nix`**

Add to the `let` block, after `systemPromptArgs`:

```nix
  extPkgs = cfg.extensionPackages;

  extEntrypoints = lib.concatMap (p: p.passthru.piEntrypoint or [ ]) extPkgs;
  extSkills = lib.concatMap (p: p.passthru.piSkills or [ ]) extPkgs;
  extPrompts = lib.concatMap (p: p.passthru.piPrompts or [ ]) extPkgs;

  # Deep merge, so two extensions contributing to one settings subtree compose
  # rather than the later one erasing the earlier.
  extSettings = lib.foldl' lib.recursiveUpdate { } (map (p: p.passthru.settings or { }) extPkgs);

  # promptFragment is an escape hatch for an extension that supplies no
  # promptSnippet or promptGuidelines of its own. Normally every entry is null
  # and this list is empty.
  promptFragments = lib.filter (f: f != null) (map (p: p.passthru.promptFragment or null) extPkgs);

  promptFragmentFile = pkgs.writeText "pi-extension-prompt-fragments.md" (
    lib.concatStringsSep "\n\n" promptFragments
  );

  # Appended, never used with --system-prompt: an extension may add guidance,
  # it may not replace the prompt.
  promptFragmentArgs = lib.optionals (promptFragments != [ ]) [
    "--append-system-prompt"
    "${promptFragmentFile}"
  ];
```

Add the option declaration inside `lib.setAttrByPath optionPath { ... }` in `options`:

```nix
    extensionPackages = lib.mkOption {
      type = lib.types.listOf lib.types.package;
      default = [ ];
      description = ''
        pi extension derivations to enable, normally taken from this flake's
        `packages.ext-*` outputs or built with `lib.builders.<system>.mkPiPlugin`.

        Each derivation carries its own wiring on `passthru`: `piEntrypoint`
        becomes `--extension` flags, `piSkills` becomes `--skill`, `piPrompts`
        becomes `--prompt-template`, `settings` is deep-merged into
        `settings.json`, and a non-null `promptFragment` is appended to the
        system prompt. Removing an extension therefore removes its
        configuration too — there is nothing left dangling.
      '';
      example = lib.literalExpression ''
        with inputs.pi-nix.packages.''${pkgs.system}; [
          ext-pi-mcp-adapter
          ext-pi-subagents
        ]
      '';
    };
```

Extend the `config` block:

```nix
  config = lib.setAttrByPath optionPath {
    finalSystemPrompt = systemPromptPath;

    extraArgs = lib.mkAfter (systemPromptArgs ++ promptFragmentArgs);

    extensions = extEntrypoints;
    skills = extSkills;
    promptTemplates = extPrompts;
    settings = extSettings;
  };
```

- [ ] **Step 4: Run the test to verify it passes**

Run:
```bash
cd /home/joe/Development/pi-nix && nix build .#checks.x86_64-linux.options -L && echo EXTPKGS-OK
```

Expected: `EXTPKGS-OK`.

- [ ] **Step 5: Verify against a real pinned extension**

Run:
```bash
cd /home/joe/Development/pi-nix && nix eval --impure --raw --expr '
  let
    flake = builtins.getFlake (toString ./.);
    pkgs = import flake.inputs.nixpkgs { system = "x86_64-linux"; };
    agent = flake.lib.mkCodingAgent {
      inherit pkgs;
      modules = [ {
        pi.coding-agent.extensionPackages = [
          flake.packages.x86_64-linux.ext-pi-subagents
        ];
      } ];
    };
  in
  builtins.concatStringsSep "\n" agent.args'
```

Expected, three lines:
```
--skill
/nix/store/…-pi-ext-pi-subagents-0.51.0/skills
--prompt-template
```
followed by the prompts path, `--extension`, and the package root. Exact ordering is upstream's (`--skill`, then `--extension`, then `--theme`, then `--prompt-template`); what matters is that all three surfaces appear and every path is under the same store output.

- [ ] **Step 6: Format and commit**

```bash
cd /home/joe/Development/pi-nix
nix fmt
nix flake check -L
git add -A
git commit -m "feat(options): extensionPackages consuming the passthru contract

Enabling an extension is one list edit: its piEntrypoint, piSkills,
piPrompts, settings, and promptFragment all ride on the derivation, so
removing it removes its configuration too. Settings are deep-merged so two
extensions can contribute to the same subtree, and promptFragment is only
ever appended — an extension may add guidance, never replace the prompt."
```

---

### Task 7: `statusline` — consuming `agent-statusline`'s shared schema

One schema, one meaning, one place to add a widget. `claude-nix` and `pi-nix` mount the same option submodule under their own namespaces.

**Prerequisite:** phase 1 must be merged and pushed to `github:joegoldin/agent-statusline`, exposing `lib.<system>.statuslineOptions`, `lib.<system>.renderConfig`, `packages.<system>.agent-statusline`, and `packages.<system>.pi-extension`.

**Files:**
- Modify: `flake.nix` (add the `agent-statusline` input)
- Modify: `coding-agent/extra-options.nix`
- Modify: `tests/options-test.nix`

**Interfaces:**
- Consumes:
  - `self.inputs.agent-statusline.lib.${system}.statuslineOptions` — attrset of `mkOption`s
  - `self.inputs.agent-statusline.lib.${system}.renderConfig cfg` — returns a `writeText` derivation holding the config JSON
  - `self.inputs.agent-statusline.packages.${system}.agent-statusline` — the binary
  - `self.inputs.agent-statusline.packages.${system}.pi-extension` — a directory whose `package.json` declares `pi.extensions`
- Produces:
  - `pi.coding-agent.statusline` — a submodule carrying every shared option plus a pi-only `extension` package option
  - `--extension <pi-extension>` on `extraArgs`, plus `AGENT_STATUSLINE_BIN` and `AGENT_STATUSLINE_CONFIG` on `environment`

- [ ] **Step 1: Add the flake input**

In `flake.nix`, inside `inputs`, after `jail-nix`:

```nix
    agent-statusline = {
      url = "github:joegoldin/agent-statusline";
      inputs.nixpkgs.follows = "nixpkgs";
    };
```

The input is reached through `self.inputs.agent-statusline` rather than being threaded as a function argument, so `module.nix` and `home-manager.nix` keep their upstream `{ self, jail-nix }` signatures.

Then:

```bash
cd /home/joe/Development/pi-nix && nix flake lock 2>&1 | tail -3
```

Expected: `warning: updating lock file …` followed by `• Added input 'agent-statusline'`.

- [ ] **Step 2: Write the failing test**

In `tests/options-test.nix`, replace `statuslineStub` with the real thing so the check tests the actual interface rather than a mock. Change the `let` header to take `self`:

```nix
{ pkgs, self, ... }:
let
  lib = pkgs.lib;
  system = pkgs.stdenv.hostPlatform.system;

  statuslineLib = self.inputs.agent-statusline.lib.${system};

  selfStub = {
    packages.${system}.coding-agent = pkgs.hello;
    inputs.agent-statusline = self.inputs.agent-statusline;
  };
```

and delete the `statuslineStub` binding entirely.

Then add these bindings and assertions:

```nix
  slOff = evalPi { };

  slOn = evalPi {
    pi.coding-agent.statusline = {
      enable = true;
      padding = 2;
    };
  };

  envValue =
    c: name:
    let
      e = c.environment;
    in
    if e == null then null else (e.${name} or null);
```

```nix
# Disabled is inert: no flag, no environment, nothing in the closure.
assert flagValues slOff.finalArgs "--extension" == [ ];
assert envValue slOff "AGENT_STATUSLINE_BIN" == null;
# Enabled adds exactly one --extension, pointing at the extension package root
# so pi resolves entries from its own pi manifest.
assert lib.length (flagValues slOn.finalArgs "--extension") == 1;
assert builtins.head (flagValues slOn.finalArgs "--extension")
  == "${slOn.statusline.extension}";
assert envValue slOn "AGENT_STATUSLINE_BIN" != null;
assert envValue slOn "AGENT_STATUSLINE_CONFIG" != null;
# The shared schema is mounted verbatim, so every option claude-nix has is here.
assert slOn.statusline.padding == 2;
```

and add to the trailing `runCommand` body:

```nix
  # renderConfig must emit the padding the option carries, proving the shared
  # schema is actually driving the JSON rather than a default being re-rendered.
  test "$(${pkgs.jq}/bin/jq -r .padding ${statuslineLib.renderConfig slOn.statusline})" = 2
  # The binary the module points at must exist under the package it selected.
  test -x ${slOn.statusline.package}/bin/agent-statusline
```

- [ ] **Step 3: Run the test to verify it fails**

Run:
```bash
cd /home/joe/Development/pi-nix && nix build .#checks.x86_64-linux.options -L 2>&1 | tail -4
```

Expected: `error: The option 'pi.coding-agent.statusline' does not exist.`

- [ ] **Step 4: Implement in `coding-agent/extra-options.nix`**

Add to the `let` block, near the top:

```nix
  inherit (pkgs.stdenv.hostPlatform) system;

  # The shared schema lives in agent-statusline so claude-nix and pi-nix cannot
  # drift. Each consumer mounts it under its own namespace.
  statuslineLib = self.inputs.agent-statusline.lib.${system};
  statuslinePkgs = self.inputs.agent-statusline.packages.${system};
```

and after `promptFragmentArgs`:

```nix
  statusline = cfg.statusline;

  statuslineConfigFile = statuslineLib.renderConfig statusline;

  # The package root, not a file: pi's resolveExtensionEntries reads the pi
  # manifest inside agent-statusline's extension package.json and loads what it
  # declares, so the entrypoint filename stays that repo's business.
  statuslineArgs = lib.optionals statusline.enable [
    "--extension"
    "${statusline.extension}"
  ];

  statuslineEnv = lib.optionalAttrs statusline.enable {
    AGENT_STATUSLINE_BIN.value = "${statusline.package}/bin/agent-statusline";
    AGENT_STATUSLINE_CONFIG.value = "${statuslineConfigFile}";
  };
```

Add the option declaration:

```nix
    statusline = lib.mkOption {
      default = { };
      description = ''
        Statusline rendered under pi, via the agent-statusline pi extension.

        The option schema is imported from agent-statusline and is the same one
        `programs.claude-nix.statusLine` mounts, so a widget added there appears
        here with no change on this side.
      '';
      type = lib.types.submodule {
        options = statuslineLib.statuslineOptions // {
          # mkOption returns a plain attrset, so overriding `default` this way
          # keeps the shared type and description while supplying the package
          # this flake's input provides.
          package = statuslineLib.statuslineOptions.package // {
            default = statuslinePkgs.agent-statusline;
          };

          extension = lib.mkOption {
            type = lib.types.package;
            default = statuslinePkgs.pi-extension;
            description = ''
              The agent-statusline pi extension package. Handed to pi as
              `--extension <dir>`; pi reads the `pi` manifest in its
              package.json to find the entrypoint.
            '';
          };
        };
      };
    };
```

Extend the `config` block:

```nix
    extraArgs = lib.mkAfter (systemPromptArgs ++ promptFragmentArgs ++ statuslineArgs);

    environment = lib.mkIf (statuslineEnv != { }) statuslineEnv;
```

Because upstream's `environment` type is `nullOr (either path attrs)`, a
definition here and a user's own definition merge only when both are attrsets.
Add this guard immediately above the `config` block so the failure mode is a
sentence rather than a type error:

```nix
  environmentIsFile =
    cfg.environment != null && (!lib.isAttrs cfg.environment || lib.isDerivation cfg.environment);

  checkedStatuslineEnv =
    if statusline.enable && environmentIsFile then
      throw ''
        pi.coding-agent.statusline.enable is set, but pi.coding-agent.environment
        is a shell environment file. The statusline needs to export
        AGENT_STATUSLINE_BIN and AGENT_STATUSLINE_CONFIG, which can only be
        merged into the attribute-set form. Either move those exports into the
        file yourself and leave statusline.enable off, or convert environment to
        the attrset form.
      ''
    else
      statuslineEnv;
```

and use `checkedStatuslineEnv` in the `config` block instead of `statuslineEnv`.

- [ ] **Step 5: Run the test to verify it passes**

Run:
```bash
cd /home/joe/Development/pi-nix && nix build .#checks.x86_64-linux.options -L && echo STATUSLINE-OK
```

Expected: `STATUSLINE-OK`.

- [ ] **Step 6: Verify the wrapper end to end**

Run:
```bash
cd /home/joe/Development/pi-nix && nix build --impure --no-link --print-out-paths --expr '
  let
    flake = builtins.getFlake (toString ./.);
    pkgs = import flake.inputs.nixpkgs { system = "x86_64-linux"; };
  in
  (flake.lib.mkCodingAgent {
    inherit pkgs;
    modules = [ { pi.coding-agent.statusline.enable = true; } ];
  }).package' | xargs -I{} grep -o 'AGENT_STATUSLINE_[A-Z]*' {}/bin/pi | sort -u
```

Expected:
```
AGENT_STATUSLINE_BIN
AGENT_STATUSLINE_CONFIG
```

- [ ] **Step 7: Format and commit**

```bash
cd /home/joe/Development/pi-nix
nix fmt
nix flake check -L
git add -A
git commit -m "feat(options): statusline, mounting agent-statusline's shared schema

The ~15 statusline options live in agent-statusline and are mounted by both
claude-nix and pi-nix under their own namespaces, so adding a widget is one
edit in one repo. renderConfig produces the JSON; the extension package root
goes to --extension and pi reads its own pi manifest for the entrypoint.

environment is nullOr (either path attrs), so a shell-environment-file value
cannot merge with our exports. That case throws a sentence rather than a type
error."
```

---

### Task 8: `notifications` — the option surface

pi ships no notifications and the ecosystem has no vetted option, so pi-nix will carry a first-party `pi-notify` in phase 3. This task lands the option surface it will plug into, with a failure mode that names the missing piece.

**Files:**
- Modify: `coding-agent/extra-options.nix`
- Modify: `tests/options-test.nix`

**Interfaces:**
- Consumes: the `extensionPackages` passthru contract from Task 6
- Produces:
  - `pi.coding-agent.notifications.enable` — bool, default `false`
  - `pi.coding-agent.notifications.package` — `nullOr package`, default `null` until phase 3 supplies `packages.pi-notify`
  - `pi.coding-agent.notifications.notifierCommand` — `str`, platform-defaulted absolute path
  - `pi.coding-agent.notifications.events` — `listOf (enum [ "needs_input" "settled" "long_running_tool" ])`, default all three
  - `pi.coding-agent.notifications.longRunningToolSeconds` — `int`, default `30`
  - Contributes `settings.piNotify = { notifierCommand; events; longRunningToolSeconds; }` and one `--extension` flag, both only when enabled with a package

- [ ] **Step 1: Write the failing test**

Add to `tests/options-test.nix`:

```nix
  notifyExt = fakeExt "notify" {
    piEntrypoint = [ "/nix/store/fake-notify/index.ts" ];
    piSkills = [ ];
    piPrompts = [ ];
    settings = { };
    promptFragment = null;
  };

  notifyOff = evalPi { };

  notifyOn = evalPi {
    pi.coding-agent.notifications = {
      enable = true;
      package = notifyExt;
      events = [
        "settled"
        "needs_input"
      ];
      longRunningToolSeconds = 45;
    };
  };

  notifyUnpackaged = builtins.tryEval (
    lib.deepSeq
      (evalPi { pi.coding-agent.notifications.enable = true; }).finalArgs
      "unreachable"
  );
```

```nix
# Disabled contributes nothing at all.
assert !(notifyOff.settings ? piNotify);
# Enabled with a package wires both the flag and the settings block.
assert lib.elem "/nix/store/fake-notify/index.ts" (flagValues notifyOn.finalArgs "--extension");
assert notifyOn.settings.piNotify.events == [
  "settled"
  "needs_input"
];
assert notifyOn.settings.piNotify.longRunningToolSeconds == 45;
assert lib.hasPrefix "/nix/store/" notifyOn.settings.piNotify.notifierCommand;
# Enabled without a package must fail loudly rather than silently doing
# nothing, because "notifications are on" and "no notifier exists" is exactly
# the state a user would not notice.
assert notifyUnpackaged.success == false;
```

- [ ] **Step 2: Run the test to verify it fails**

Run:
```bash
cd /home/joe/Development/pi-nix && nix build .#checks.x86_64-linux.options -L 2>&1 | tail -4
```

Expected: `error: The option 'pi.coding-agent.notifications' does not exist.`

- [ ] **Step 3: Implement in `coding-agent/extra-options.nix`**

Add to the `let` block:

```nix
  notifications = cfg.notifications;

  notificationsPackage =
    if !notifications.enable then
      null
    else if notifications.package == null then
      throw ''
        pi.coding-agent.notifications.enable is set, but
        pi.coding-agent.notifications.package is null.

        pi ships no notification support and the npm ecosystem has no vetted
        extension, so pi-nix carries a first-party pi-notify — which does not
        exist yet (phase 3 of docs/plans/2026-08-18-pi-nix-agent-stack-design.md).
        Either set notifications.package explicitly or leave
        notifications.enable off.
      ''
    else
      notifications.package;

  notificationArgs = lib.optionals (notificationsPackage != null) (
    notificationsPackage.passthru.piEntrypoint or [ ]
  );

  # Read by pi-notify at runtime. The notifier path is resolved at build time
  # so the extension never has to search PATH inside the jail.
  notificationSettings = lib.optionalAttrs (notificationsPackage != null) {
    piNotify = {
      inherit (notifications) notifierCommand events longRunningToolSeconds;
    };
  };
```

`notificationArgs` holds bare paths; wrap them into flags where they are used:

```nix
  notificationFlags = lib.concatMap (p: [
    "--extension"
    p
  ]) notificationArgs;
```

Add the option declaration:

```nix
    notifications = {
      enable = lib.mkEnableOption "desktop notifications for pi via the first-party pi-notify extension";

      package = lib.mkOption {
        type = lib.types.nullOr lib.types.package;
        default = null;
        description = ''
          The `pi-notify` extension derivation. Null until pi-nix ships it;
          setting `enable` without a package is an error rather than a silent
          no-op, because "notifications on, no notifier" is precisely the state
          a user would not notice.
        '';
      };

      notifierCommand = lib.mkOption {
        type = lib.types.str;
        default =
          if pkgs.stdenv.hostPlatform.isDarwin then
            "${pkgs.terminal-notifier}/bin/terminal-notifier"
          else
            "${pkgs.libnotify}/bin/notify-send";
        defaultText = lib.literalExpression ''
          if pkgs.stdenv.hostPlatform.isDarwin then
            "''${pkgs.terminal-notifier}/bin/terminal-notifier"
          else
            "''${pkgs.libnotify}/bin/notify-send"
        '';
        description = ''
          Absolute path to the notifier binary pi-notify shells out to.
          Resolved at build time so the path survives inside the jail, where
          the host PATH is not available.
        '';
      };

      events = lib.mkOption {
        type = lib.types.listOf (
          lib.types.enum [
            "needs_input"
            "settled"
            "long_running_tool"
          ]
        );
        default = [
          "needs_input"
          "settled"
          "long_running_tool"
        ];
        description = ''
          Which events raise a notification.

          - `needs_input` — a permission layer raised a prompt
          - `settled` — the agent finished its turn (pi's `agent_settled`)
          - `long_running_tool` — a tool ran longer than
            `longRunningToolSeconds` (pi's `tool_execution_start`/`_end`)
        '';
      };

      longRunningToolSeconds = lib.mkOption {
        type = lib.types.int;
        default = 30;
        description = ''
          Duration a tool must exceed before `long_running_tool` fires.
        '';
      };
    };
```

Extend the `config` block:

```nix
    extraArgs = lib.mkAfter (
      systemPromptArgs ++ promptFragmentArgs ++ statuslineArgs ++ notificationFlags
    );

    settings = lib.recursiveUpdate extSettings notificationSettings;
```

- [ ] **Step 4: Run the test to verify it passes**

Run:
```bash
cd /home/joe/Development/pi-nix && nix build .#checks.x86_64-linux.options -L && echo NOTIFICATIONS-OK
```

Expected: `NOTIFICATIONS-OK`.

- [ ] **Step 5: Verify the platform default resolves**

Run:
```bash
cd /home/joe/Development/pi-nix && nix eval --impure --raw --expr '
  let
    flake = builtins.getFlake (toString ./.);
    pkgs = import flake.inputs.nixpkgs { system = "x86_64-linux"; };
  in
  (flake.lib.mkCodingAgent { inherit pkgs; modules = [ ]; })
    .config.pi.coding-agent.notifications.notifierCommand'
```

Expected: a path ending in `-libnotify-0.8.8/bin/notify-send` (the exact version follows nixpkgs).

- [ ] **Step 6: Format and commit**

```bash
cd /home/joe/Development/pi-nix
nix fmt
nix flake check -L
git add -A
git commit -m "feat(options): notifications option surface for pi-notify

code-notify was dropped from agent-skills once Claude, Codex, and Antigravity
all shipped notifications natively; pi has none and npm has no vetted option,
so pi-nix will carry a first-party pi-notify in phase 3. This is the surface
it plugs into. Enabling without a package throws rather than no-oping,
because notifications-on-with-no-notifier is the failure a user would never
notice. The notifier path is resolved at build time so it survives the jail."
```

---

### Task 9: Document the fork's options and prove it stayed additive

The last gate: the option reference regenerates, `nix flake check` is green across everything, and the diff against upstream is confined to the six files `docs/REBASING.md` lists.

**Files:**
- Modify: `README.md` (options section)
- Create: `tests/additive-test.nix`
- Modify: `tests/default.nix`

**Interfaces:**
- Consumes: every option from Tasks 5–8
- Produces: `checks.<system>.additive` — fails the build if an upstream file outside the permitted set was modified

- [ ] **Step 1: Write the failing test**

Create `tests/additive-test.nix`:

```nix
# The fork's central promise is that upstream rebases stay clean. That promise
# is only worth something if it is a test. This one is a content check rather
# than a git check, so it works inside the Nix sandbox: each protected file's
# hash is recorded here, and any edit to one breaks the build with the file
# name in the message.
#
# When a legitimate `git rebase upstream/master` changes one of these files,
# update its hash here in the same commit as the rebase. That is the point:
# the hash changing should be a deliberate act, never a side effect.
{ pkgs, ... }:
let
  protected = {
    "coding-agent/options.nix" = ../coding-agent/options.nix;
    "coding-agent/package.nix" = ../coding-agent/package.nix;
    "coding-agent/package-bun.nix" = ../coding-agent/package-bun.nix;
    "coding-agent/bun.nix" = ../coding-agent/bun.nix;
    "sync-upstream.nix" = ../sync-upstream.nix;
    "regenerate-models.nix" = ../regenerate-models.nix;
    "scan.nix" = ../scan.nix;
    "VERSION.json" = ../VERSION.json;
  };

  lines = pkgs.lib.mapAttrsToList (
    name: path: "${builtins.hashFile "sha256" path}  ${name}"
  ) protected;

  manifest = pkgs.writeText "pi-nix-protected-files" (
    pkgs.lib.concatStringsSep "\n" (pkgs.lib.sort (a: b: a < b) lines) + "\n"
  );
in
pkgs.runCommand "pi-nix-additive-test" { } ''
  set -euo pipefail
  # Recorded when this test was written, from upstream/master @ 273a552.
  # Regenerate with:
  #   nix build .#checks.x86_64-linux.additive -L   (read the diff it prints)
  cat ${manifest}
  cp ${manifest} $out
''
```

Register it in `tests/default.nix`:

```nix
  additive = import ./additive-test.nix args;
```

- [ ] **Step 2: Run it and capture the recorded hashes**

Run:
```bash
cd /home/joe/Development/pi-nix && nix build .#checks.x86_64-linux.additive -L --no-link --print-out-paths | xargs cat
```

Expected: eight `<sha256>  <path>` lines, sorted by path.

Copy that output verbatim into `tests/additive-test.nix`, replacing the trailing `cat ${manifest}` / `cp ${manifest} $out` with a real comparison:

```nix
in
pkgs.runCommand "pi-nix-additive-test" { } ''
  set -euo pipefail
  cat > expected <<'EOF'
  <paste the eight lines here, unindented>
  EOF
  if ! diff -u expected ${manifest}; then
    echo ""
    echo "An upstream file outside the permitted edit set changed."
    echo "See docs/REBASING.md. If this is a deliberate upstream rebase,"
    echo "update the hashes in tests/additive-test.nix in the same commit."
    exit 1
  fi
  touch $out
''
```

- [ ] **Step 3: Verify the test actually catches a modification**

Run:
```bash
cd /home/joe/Development/pi-nix
printf '\n# tamper\n' >> coding-agent/options.nix
nix build .#checks.x86_64-linux.additive -L 2>&1 | grep -c 'outside the permitted edit set'
git checkout -- coding-agent/options.nix
nix build .#checks.x86_64-linux.additive -L && echo ADDITIVE-OK
```

Expected: `1` from the grep, then `ADDITIVE-OK` after the revert. A test that never fails is not a test.

- [ ] **Step 4: Document the new options in `README.md`**

Replace the `## Options` section written in Task 1 with:

```markdown
## Options

Everything upstream documents under `programs.pi.coding-agent` still applies.
This fork adds:

| Option | Type | Default | What it does |
| --- | --- | --- | --- |
| `systemPrompt` | `null \| lines \| path` | `null` | `--system-prompt`, **replacing** pi's default prompt. Composes with `rules`, which still appends. |
| `extensionPackages` | `[package]` | `[ ]` | Enable pinned extensions. Entrypoints, skills, prompts, and settings all follow from each derivation's `passthru`. |
| `statusline.*` | submodule | `{ }` | The shared agent-statusline schema, mounted under pi's namespace. |
| `statusline.extension` | package | this flake's `pi-extension` | The extension package handed to `--extension`. |
| `notifications.enable` | bool | `false` | Desktop notifications via the first-party `pi-notify` extension. |
| `notifications.package` | `null \| package` | `null` | The `pi-notify` derivation. Enabling without one is an error, not a no-op. |
| `notifications.notifierCommand` | str | `notify-send` / `terminal-notifier` | Absolute path to the notifier, resolved at build time so it survives the jail. |
| `notifications.events` | `[enum]` | all three | `needs_input`, `settled`, `long_running_tool`. |
| `notifications.longRunningToolSeconds` | int | `30` | Threshold for `long_running_tool`. |

Pinned extensions are exposed as `packages.<system>.ext-<slug>`:

| Attribute | npm package |
| --- | --- |
| `ext-pi-mcp-adapter` | `pi-mcp-adapter` — MCP, which pi omits |
| `ext-pi-subagents` | `pi-subagents` — subagents |
| `ext-pi-background-tasks` | `pi-background-tasks` — background bash |
| `ext-plannotator-pi-extension` | `@plannotator/pi-extension` — plan mode |
| `ext-juicesharp-rpiv-todo` | `@juicesharp/rpiv-todo` — todos |
| `ext-gotgenes-pi-permission-system` | `@gotgenes/pi-permission-system` — deterministic permissions |

Bump every pin, and pi itself, with one command:

```sh
nix run .#update
```

`nix run .#update-extensions` bumps only the extension pins. Neither ever
rewrites the `bundled` or `entrypoints` fields in `extensions.json` — those are
human decisions about a package, not facts read off the registry.

Generate the full reference:

```sh
nix build .#docs-md
nix build .#docs-html
```
```

- [ ] **Step 5: Confirm the generated option docs include the new options**

Run:
```bash
cd /home/joe/Development/pi-nix && nix build .#docs-md --no-link --print-out-paths | xargs -I{} grep -c -E '^## (pi\.coding-agent\.(systemPrompt|extensionPackages|statusline|notifications))' {}
```

Expected: `4` or more (`statusline` and `notifications` expand into several sub-entries, so a larger number is correct; anything below 4 means an option is missing from the docs output).

- [ ] **Step 6: Full check**

Run:
```bash
cd /home/joe/Development/pi-nix
nix fmt
nix flake check -L
git status --porcelain
git diff upstream/master --stat -- \
  coding-agent/options.nix coding-agent/package.nix coding-agent/package-bun.nix \
  coding-agent/bun.nix sync-upstream.nix regenerate-models.nix scan.nix \
  VERSION.json package-lock.json bun.lock ai
```

Expected: `nix flake check` passes with checks `additive`, `builders`, `extensions`, `options`, `smoke`, and `update-app`; `git status --porcelain` shows only the files this task touched; the final `git diff --stat` prints **nothing**.

- [ ] **Step 7: Commit and push**

```bash
cd /home/joe/Development/pi-nix
git add -A
git commit -m "docs: document the fork's options and gate the additive promise

tests/additive-test.nix hashes every upstream file we promised not to touch
and fails the build if one changes. The promise that upstream rebases stay
clean is only worth something as a test; when a real rebase moves one of
these files, its hash is updated in the same commit, deliberately."
git push -u origin master
```

---

## Self-Review

**Spec coverage.** Design §7's addition table is covered row for row: `systemPrompt` → `--system-prompt` (Task 5), `packages/extensions/` + `packages.ext-*` (Task 3), `extensions.json` + extended `update` app (Tasks 3 and 4), `statusline` (Task 7), `notifications` (Task 8), `lib/` builders (Task 2). §8's `mkPiExtension` shape, `extensions.json` schema, `passthru.settings` rationale, and the "pin by verified repository URL, not remembered author name" instruction are all honoured — the pin table records the registry's repository URLs, and finding 6 records the correction (`nicobailon`, not `nicopreme`). §7's "known upstream behaviour, retained" paragraph about the `settings.json` jq-merge is reproduced in the README rather than being fixed. The `autoMode` row of §7's table is deliberately **not** here: it belongs to phase 3 with `pi-auto-mode` and the permission layers, and landing the option without either layer would ship a lie.

**Placeholder scan.** No `TBD`, no "similar to Task N", no "add error handling". Every hash in `extensions.json` is a real value read off the npm registry on 2026-08-18; every `npmDepsHash` was computed and is reproduced in Task 3 Step 6's expected output. The one synthetic hash in `tests/extensions-test.nix` is a deliberate all-`A` sha512 on a derivation that is never built, and the comment says so. Two steps write text the operator must paste from a prior command's output — Task 9 Step 2's hash manifest, and Task 3 Step 6's generated lockfiles — both give the exact command and the exact expected shape, which is the standard Nix pin workflow, not a gap.

**Type consistency.** `passthru.piEntrypoint` is `list of str` in `mkPiExtension` (Task 3), `mkPiPlugin` (Task 2), the fake extensions in the Task 6 test, and the `notificationArgs` consumer in Task 8. `passthru.piSkills` / `piPrompts` are likewise `list of str` everywhere and feed `skills` / `promptTemplates`, whose upstream types (`listOf path`, `listOf path`) accept `/nix/store/…` strings. `passthru.settings` is `attrs` and is folded with `recursiveUpdate` in both Task 6 and Task 8. `passthru.promptFragment` is `null | str` in all four places. `extensions.json` fields are read by exactly two consumers — `packages/extensions/default.nix` and `update-extensions.nix` — and the field list matches between them, with `bundled` and `entrypoints` written by neither.

**Deviations from the spec, with reasons.**
1. **`piEntrypoint` is a list, not the scalar `"…/dist/index.js"` §8 sketches.** `pi-background-tasks` declares two entrypoints and `@plannotator/pi-extension` declares a directory, so a scalar cannot represent the pin set. The default value is a one-element list holding the package root, which lets pi's `resolveExtensionEntries` read each package's own `pi` manifest.
2. **`piSkills` and `piPrompts` added to the passthru contract.** `pi-mcp-adapter` ships skills and `pi-subagents` ships skills *and* prompt templates. `--extension` does not load either — only `--skill` and `--prompt-template` do. Without these two fields those resources would silently never load, which is the kind of failure nobody notices.

**Spec gaps and contradictions found.**
1. **Assumption A4 is false for every package in the pin set.** §8 expected `bundled = true` — "fetchurl npm tarball, use `dist/` as-is" — to be the common case. Zero of the six ship a `dist`; all publish raw TypeScript against unbundled dependencies, and none ships a lockfile, so `buildNpmPackage` alone is not enough either. The documented fallback ("build that package with `buildNpmPackage` and an `npmDepsHash`") is now the *only* path, and it needed a vendored generated lockfile the spec did not anticipate. That lockfile generation is why Task 4 exists in the shape it does.
2. **`passthru.settings` will be empty for the entire initial pin set.** §8 calls it "load-bearing" and names `pi-mcp-adapter` needing the MCP server list as the motivating case. Verified: `pi-mcp-adapter` reads `~/.config/mcp/mcp.json` and `~/.agents/mcp.json`, not pi's `settings.json`; `@juicesharp/rpiv-todo` reads its own `rpiv-todo` config file. §9's plan to fan `programs.agent-skills.mcpServers` into `pi-mcp-adapter` therefore needs a **config-file** mechanism (`passthru.configFiles`, or home-manager writing `~/.agents/mcp.json`), not `settings.json` merging. Phase 3 should add that; this plan ships the `settings` mechanism as specified, tested against a synthetic case, so the contract exists when a pin does use it.
3. **§7's `autoMode` row has no phase.** §15's rollout order puts `pi-auto-mode` in phase 3 but §7 lists `autoMode` as a pi-nix option alongside `statusline` and `notifications`. Treated here as phase 3, since the option is meaningless without at least one of the two layers §9 describes.
4. **§6 gives `agent-statusline.lib.statuslineOptions` without a system dimension; §15 and the phase-1 plan give `lib.${system}`.** This plan uses `lib.${system}`, matching the phase-1 plan's Task 7, which is the definition that will actually exist.
