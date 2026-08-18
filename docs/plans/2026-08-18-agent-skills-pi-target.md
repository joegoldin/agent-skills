# agent-skills `pi` Target Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use subagent-driven-development (recommended) or executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a fourth target, `pi`, to `agent-skills`, so the same skill library, the same cross-agent plugins, and the same normalized MCP declaration serve pi exactly as they serve Claude Code, Codex, and Antigravity.

**Architecture:** `agent-skills` already models "one skill, four renderings" — `discoverSkills` produces target-neutral records, and each `build*Plugin` re-targets them through that agent's `lib`. pi slots into that shape with one wrinkle: pi has no hook system, so the two things that are hooks today (the `using-agent-skills` session injector and the `temporal` timestamp injector) become TypeScript **extensions** shipped inside a real pi *package* — a directory with a `package.json` carrying the `pi` manifest key and `skills/`, `prompts/`, `extensions/` trees. The whole package is handed to pi as one entry in `settings.packages`.

**Tech Stack:** Nix (flakes, `nixfmt`), TypeScript (pi extensions, no build step — pi loads `.ts` directly), `pi-mcp-adapter` for MCP.

This is **phase 4** of the design in `docs/plans/2026-08-18-pi-nix-agent-stack-design.md` (§11), and it resolves assumption **A3**.

---

## Assumption A3 — RESOLVED (verified empirically, 2026-08-18, pi v0.84.2)

> A3: "Skills provided by both `~/.agents/skills` and a pi package de-duplicate by name. Fallback if false: use pi's `--no-*` discovery-disabling flags to pick a single source."

**Finding: A3 is TRUE, and there is a strictly better mechanism available than the one it assumes. No `--no-*` flag is needed.**

pi collapses skills in `loadSkills()` (`packages/coding-agent/src/core/skills.ts`) using **two** de-duplication passes, in this order:

```ts
function addSkills(result: LoadSkillsResult) {
    for (const skill of result.skills) {
        const realPath = canonicalizePath(skill.filePath);   // = realpathSync()

        // Skip silently if we've already loaded this exact file (via symlink)
        if (realPathSet.has(realPath)) {
            continue;                                        // ← pass 1: SILENT
        }

        const existing = skillMap.get(skill.name);
        if (existing) {
            collisionDiagnostics.push({                      // ← pass 2: WARNS
                type: "collision",
                message: `name "${skill.name}" collision`,
                collision: { resourceType: "skill", name: skill.name,
                             winnerPath: existing.filePath, loserPath: skill.filePath },
            });
        } else {
            skillMap.set(skill.name, skill);
            realPathSet.add(realPath);
        }
    }
}
```

Every source — `~/.agents/skills`, `.pi/skills`, `settings.skills`, package `skills/` arrays, and `--skill` — is merged into a single `skillPaths` list and handed to one `loadSkills()` call with `includeDefaults: false` (`resource-loader.ts:676`), so all four sources share one `skillMap` and one `realPathSet`.

The two passes differ in cost, and the difference is the whole design decision:

| Both sources resolve to… | Pass | Result | User sees |
| --- | --- | --- | --- |
| **the same real path** (symlinks) | 1 | dropped silently | nothing |
| different real paths, same `name` (copies) | 2 | first wins, loser recorded | a warning line per skill at TUI startup (`interactive-mode.ts:1581`) |

`interactive-mode.ts:1787-1789` formats every skill diagnostic into the startup banner, so a copy-based pi package would print **one warning per skill on every session start** — currently 39 lines. A symlink-based package prints none.

**Empirical confirmation.** Built `pi` from the local fork and probed the assembled system prompt with a throwaway extension:

```
── CASE 1 symlink+symlink (same realpath) ──   PROBE demo-occurrences=3  skill-blocks=1
── CASE 2 symlink+copy   (diff realpath) ──   PROBE demo-occurrences=3  skill-blocks=1
── CASE 3 single source        (baseline) ──   PROBE demo-occurrences=3  skill-blocks=1
```

and then end-to-end, with a real pi package on a local absolute path in `settings.packages` alongside the live `~/.agents/skills`:

```
PROBE ext-loaded=1 total-skills=38 demo-blocks=1
PROBE loc=…/a3/agents/skills/demo/SKILL.md
```

One `<skill>` block in all cases; the package's extension loaded; the `~/.agents/skills` copy won.

**Consequence for this plan, and it is load-bearing:** `buildPiPlugin` must place the **same `skill-<name>` derivations the Claude plugin already ships** into the package's `skills/`, linked by `buildEnv`, never `cp -r`'d. Then `realpath(~/.agents/skills/<n>/SKILL.md)` and `realpath(<pi-package>/skills/<n>/SKILL.md)` are byte-identical, pass 1 fires, and the double-load is free. Task 4 introduces `checks.pi-skill-realpath-identity` as the mechanical gate for exactly this, because the property is invisible in the built output and a well-meaning future `cp -r` would silently cost 39 warnings a session.

---

## Global Constraints

- **The pi package's `skills/` must contain `buildEnv` links to the same `skill-<name>` derivations the Claude plugin ships.** Never `cp`, never re-render through `piLib.mkSkill`. `checks.pi-skill-realpath-identity` enforces it. See A3 above.
- **No `--no-skills` / `--no-extensions` / `--no-prompt-templates`.** They are the A3 fallback and are not needed. `--no-skills` would also disable *package* skills, not just `~/.agents/skills`.
- **No skill content translation.** pi implements the Agent Skills standard and treats unknown frontmatter keys as `[key: string]: unknown` (`skills.ts:67-71`) — Claude Code's extensions pass through inert. Skills ship verbatim.
- **pi extensions are plain `.ts`, loaded from a `/nix/store` path with no `node_modules` beside them.** Only `import type` from `@earendil-works/pi-coding-agent` is permitted; value imports would fail to resolve. Verified: a type-only import loads cleanly from an arbitrary local path.
- New builder arguments follow the existing optional-lib convention: `piLib ? null` in `lib/default.nix`, guarded by `assert piLib != null;` inside the functions that need it, so `import ./lib/default.nix { inherit pkgs lib; claudeLib = …; }` keeps working for the callers that pass only `claudeLib`.
- Nix formatting: `nixfmt` (`nix fmt`). TypeScript: 2-space indent, tabs are not used in this repo's `.ts`.
- Every new invariant lands as a `flake.nix` `checks.*` entry so garnix runs it.
- Version pinned during development: pi `v0.84.2` (`pi-nix/VERSION.json`). Line numbers cited in comments refer to that tag.
- Do not `git push`; commit only.

---

### Task 1: Add the `pi-nix` input and expose `piLib`

Pure plumbing. Nothing builds for pi yet; this task only makes `piLib` reachable and proves it has the three functions the rest of the plan consumes.

**Files:**
- Modify: `/home/joe/Development/agent-skills/flake.nix` (inputs, `outputs` arg list, `lib` re-export)
- Modify: `/home/joe/Development/agent-skills/lib/default.nix` (accept `piLib ? null`)

**Interfaces:**
- Consumes, from phase 2's `pi-nix` (`${pi-nix}/lib`, imported as `{ inherit pkgs lib; }` exactly like `codexLib` and `agyLib`):
  - `piLib.mkSkill :: { name :: str, description :: str, allowed-tools ? [str], extraFiles ? [path], extraFrontmatter ? attrsOf (str|bool) } -> str -> derivation` producing `$out/skills/<name>/SKILL.md`. Signature is deliberately `claudeLib.mkSkill` ∪ `codexLib.mkSkill` so `buildSkillForTarget` needs no pi special case.
  - `piLib.mkPromptTemplate :: { name :: str, description :: str, argument-hint ? str } -> str -> derivation` producing `$out/prompts/<name>.md`.
  - `piLib.mkPlugin :: { name, description ? "", version ? "0.0.0", skills ? [drv], prompts ? [drv], extensions ? [drv], themes ? [drv] } -> derivation` producing a `buildEnv` whose root holds a generated `package.json` with the `pi` manifest key plus the linked resource trees.
  - `piLib` deliberately has **no `mkHook`**. pi has no hook system; the pi arm of `mkCrossAgentPlugin` (Task 7) branches on that.
- Produces: `self.lib.<system>.piLib`, and a `piLib` argument threaded into `lib/default.nix`.

- [ ] **Step 1: Write the failing check**

Run:
```bash
cd /home/joe/Development/agent-skills
nix eval .#lib.x86_64-linux.piLib --apply 'l: builtins.isFunction l.mkSkill && builtins.isFunction l.mkPlugin && builtins.isFunction l.mkPromptTemplate'
```

Expected **now**: `error: attribute 'piLib' missing`. That is the failing test.

- [ ] **Step 2: Add the flake input**

In `flake.nix`, inside `inputs`, after the `codex-nix` block:

```nix
    pi-nix = {
      # github: (not git+ssh) for the same reason codex-nix uses it — garnix
      # injects its app token for github: refs but has no SSH key.
      url = "github:joegoldin/pi-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
```

- [ ] **Step 3: Bind it in `outputs`**

Change the `outputs` argument list from

```nix
    {
      self,
      nixpkgs,
      claude-nix,
      antigravity-cli-nix,
      codex-nix,
      ...
    }:
```

to

```nix
    {
      self,
      nixpkgs,
      claude-nix,
      antigravity-cli-nix,
      codex-nix,
      pi-nix,
      ...
    }:
```

- [ ] **Step 4: Instantiate `piLib` in `packages` and thread it into `build`**

In the `packages = forAllSystems (…)` let-block, after `codexLib`:

```nix
          piLib = import "${pi-nix}/lib" { inherit pkgs lib; };
          build = import ./lib/default.nix {
            inherit
              pkgs
              lib
              claudeLib
              agyLib
              codexLib
              piLib
              ;
          };
```

- [ ] **Step 5: Accept the argument in `lib/default.nix`**

Change the header of `lib/default.nix` from

```nix
{
  pkgs,
  lib,
  claudeLib,
  agyLib ? null,
  codexLib ? null,
}:
```

to

```nix
{
  pkgs,
  lib,
  claudeLib,
  agyLib ? null,
  codexLib ? null,
  piLib ? null,
}:
```

- [ ] **Step 6: Re-export `piLib` from the flake's `lib`**

In the `lib = forAllSystems (…)` block, after the `codexLib` entry:

```nix
          piLib = import "${pi-nix}/lib" {
            inherit pkgs;
            lib = pkgs.lib;
          };
```

- [ ] **Step 7: Lock, format, and run the check to see it pass**

Run:
```bash
cd /home/joe/Development/agent-skills
nix flake lock --update-input pi-nix
nix fmt
nix eval .#lib.x86_64-linux.piLib --apply 'l: builtins.isFunction l.mkSkill && builtins.isFunction l.mkPlugin && builtins.isFunction l.mkPromptTemplate'
```

Expected: `true`.

If any of the three is missing, the gap is in `pi-nix/lib` (phase 2), not here — fix it there against the signatures in this task's Interfaces block and re-lock.

- [ ] **Step 8: Confirm nothing else moved**

Run:
```bash
cd /home/joe/Development/agent-skills && nix flake check 2>&1 | tail -20
```

Expected: passes, exactly as before this task. `piLib` is reachable but unused.

- [ ] **Step 9: Commit**

```bash
cd /home/joe/Development/agent-skills
git add -A
git commit -m "feat(pi): add the pi-nix input and expose piLib

Plumbing only — piLib is reachable from lib/default.nix and the flake's
lib re-export, but nothing builds for pi yet. lib/default.nix takes it as
piLib ? null so the callers that pass only claudeLib keep working."
```

---

### Task 2: The `pi` arm of `mcpNativeFor`

`programs.agent-skills.mcpServers` is already normalized once and fanned out per agent. pi's consumer is `pi-mcp-adapter`, whose per-server schema is `command`/`args`/`env` for stdio and `url`/`headers`/`auth`/`bearerTokenEnv` for HTTP. That last pair is the only real difference from Codex, which spells the same idea `bearer_token_env_var`.

**Files:**
- Modify: `/home/joe/Development/agent-skills/lib/mcp.nix`
- Modify: `/home/joe/Development/agent-skills/flake.nix` (`checks.eval-mcp`)

**Interfaces:**
- Consumes: `mcp.normalizedModule` fields `command`, `args`, `env`, `url`, `headers`, `bearerTokenEnvVar`, `disabled` (all pre-existing; **no new option is added**)
- Produces: `mcpNativeFor "pi" :: attrsOf normalized -> attrsOf piNative`, where `piNative` for a remote server is
  `{ url :: str; headers ? attrsOf str; auth ? "bearer"; bearerTokenEnv ? str; }`
  and for a stdio server is the same `{ command; args?; env?; }` every other target gets.

- [ ] **Step 1: Write the failing assertions into `checks.eval-mcp`**

In `flake.nix`, in the `checks` let-block, after `codexJson`:

```nix
          piJson = pkgs.writeText "pi-mcp.json" (builtins.toJSON (mcp.mcpNativeFor "pi" servers));
```

and inside the `eval-mcp` `runCommand` script, append before `touch $out`:

```bash
            # disabled servers are omitted from the pi target too
            jq -e 'has("off") | not' ${piJson} >/dev/null

            # stdio is identical across all four targets
            jq -e '.ctx.command == "npx" and (.ctx.args == ["-y","ctx"])' ${piJson} >/dev/null

            # pi remote → pi-mcp-adapter shape: url + headers + auth/bearerTokenEnv
            jq -e '.remote.url == "https://x/mcp" and .remote.headers.Authorization == "Bearer Y"' ${piJson} >/dev/null
            jq -e '.remote.auth == "bearer" and .remote.bearerTokenEnv == "TOK"' ${piJson} >/dev/null

            # pi must not inherit any other target's remote spelling
            jq -e '.remote | (has("type") | not) and (has("serverUrl") | not) and (has("bearer_token_env_var") | not) and (has("http_headers") | not)' ${piJson} >/dev/null
```

- [ ] **Step 2: Run it to see it fail**

Run:
```bash
cd /home/joe/Development/agent-skills && nix build .#checks.x86_64-linux.eval-mcp --no-link 2>&1 | tail -20
```

Expected: the build fails. `mcpNativeFor "pi"` currently falls through to the unlabelled `else # codex` branch, so `.remote.bearer_token_env_var` is emitted and the `has("bearer_token_env_var") | not` assertion fails.

- [ ] **Step 3: Add the pi arm and make the codex fallthrough explicit**

In `lib/mcp.nix`, replace the tail of `toNative`:

```nix
    else if target == "antigravity" then
      {
        serverUrl = s.url;
      }
      // optionalAttrs (s.headers != { }) { inherit (s) headers; }
    else # codex
      {
        url = s.url;
      }
      // optionalAttrs (s.bearerTokenEnvVar != null) { bearer_token_env_var = s.bearerTokenEnvVar; }
      // optionalAttrs (s.headers != { }) { http_headers = s.headers; };
```

with:

```nix
    else if target == "antigravity" then
      {
        serverUrl = s.url;
      }
      // optionalAttrs (s.headers != { }) { inherit (s) headers; }
    else if target == "codex" then
      {
        url = s.url;
      }
      // optionalAttrs (s.bearerTokenEnvVar != null) { bearer_token_env_var = s.bearerTokenEnvVar; }
      // optionalAttrs (s.headers != { }) { http_headers = s.headers; }
    else if target == "pi" then
      # pi has no native MCP; this is pi-mcp-adapter's mcp.json schema.
      # `headers` is spelled the same as claude/antigravity; the bearer-token
      # env var is `bearerTokenEnv` and must be paired with auth = "bearer".
      {
        url = s.url;
      }
      // optionalAttrs (s.headers != { }) { inherit (s) headers; }
      // optionalAttrs (s.bearerTokenEnvVar != null) {
        auth = "bearer";
        bearerTokenEnv = s.bearerTokenEnvVar;
      }
    else
      throw "agent-skills mcpServers.${name}: unknown target '${target}' (known: claude, antigravity, codex, pi)";
```

The unlabelled `else # codex` becoming explicit is deliberate: a typo'd target now throws instead of silently rendering Codex JSON.

- [ ] **Step 4: Run it to see it pass**

Run:
```bash
cd /home/joe/Development/agent-skills && nix fmt && nix build .#checks.x86_64-linux.eval-mcp --no-link && echo EVAL_MCP_OK
```

Expected: `EVAL_MCP_OK`.

- [ ] **Step 5: Prove the throw fires**

Run:
```bash
cd /home/joe/Development/agent-skills
nix eval --impure --expr '
  let
    lib = (import <nixpkgs> { }).lib;
    mcp = import ./lib/mcp.nix { inherit lib; };
  in
    builtins.tryEval (builtins.toJSON (mcp.mcpNativeFor "gemini" {
      remote = { command = null; args = [ ]; env = { }; url = "https://x/mcp";
                 headers = { }; bearerTokenEnvVar = null; disabled = false; };
    }))
'
```

Expected: `{ success = false; value = false; }`.

- [ ] **Step 6: Commit**

```bash
cd /home/joe/Development/agent-skills
git add -A
git commit -m "feat(pi): mcpNativeFor pi arm for pi-mcp-adapter

Remote servers render as url + headers + auth/bearerTokenEnv, reusing the
same normalized bearerTokenEnvVar field Codex spells bearer_token_env_var.
The codex fallthrough is now an explicit branch so an unknown target throws
instead of quietly emitting Codex JSON."
```

---

### Task 3: pi frontmatter lint

pi enforces a *subset* of what `validateSkillMd` already enforces: `name` ≤ 64 chars matching `^[a-z0-9-]+$`, `description` non-empty and ≤ 1024 chars. Everything else is `[key: string]: unknown` and ignored. So the useful lint is not "check the skills again" — it is **encoding pi's rules independently and asserting containment**, so a future loosening of `validateSkillMd` cannot silently break pi.

**Files:**
- Modify: `/home/joe/Development/agent-skills/lib/lint.nix`
- Modify: `/home/joe/Development/agent-skills/lib/lint-tests.nix`
- Modify: `/home/joe/Development/agent-skills/flake.nix` (`checks.pi-frontmatter`)

**Interfaces:**
- Consumes: `fm.parse` output (`{ fields; items; keys; body; }`) from `lib/frontmatter.nix`
- Produces:
  - `lint.piMaxNameLength :: int` = `64`
  - `lint.piMaxDescriptionLength :: int` = `1024`
  - `lint.piNamePattern :: str` = `"[a-z0-9-]+"`
  - `lint.piSkillWarnings :: { dirName :: str, parsed } -> [str]` — the diagnostics pi would emit, `[ ]` when pi loads the skill cleanly

- [ ] **Step 1: Write the failing tests**

In `lib/lint-tests.nix`, add inside the `let` block, after `mkParsed`:

```nix
  piWarn = dirName: parsed: lint.piSkillWarnings { inherit dirName parsed; };
  # Every frontmatter sample that agent-skills accepts must also be clean
  # for pi. This is the containment property, checked as a property rather
  # than restated case by case.
  acceptedSamples = [
    ok
    (mkParsed name64 "y")
    (mkParsed "x" desc1024)
    (fm.parse "---\nname: x\ndescription: y\ndisable-model-invocation: true\n---\nbody")
  ];
```

and add these cases to the `runTests` attrset:

```nix
  testPiAcceptsValidSkill = {
    expr = piWarn "good-skill" ok;
    expected = [ ];
  };
  testPiRejectsUppercaseName = {
    expr = piWarn "Bad-Name" (fm.parse "---\nname: Bad-Name\ndescription: y\n---\nbody");
    expected = [ "name contains invalid characters (must be lowercase a-z, 0-9, hyphens only)" ];
  };
  testPiRejectsMissingDescription = {
    expr = piWarn "x" (fm.parse "---\nname: x\n---\nbody");
    expected = [ "description is required" ];
  };
  testPiRejectsName65 = {
    expr = piWarn name65 (mkParsed name65 "y");
    expected = [ "name exceeds 64 characters" ];
  };
  testPiRejectsDescription1025 = {
    expr = piWarn "x" (mkParsed "x" desc1025);
    expected = [ "description exceeds 1024 characters" ];
  };
  testPiFallsBackToDirName = {
    # pi uses the parent directory name when frontmatter omits `name`
    # (skills.ts: `const name = frontmatter.name || parentDirName`), so a
    # nameless SKILL.md in a well-named directory is clean for pi even
    # though validateSkillMd rejects it.
    expr = piWarn "good-skill" (fm.parse "---\ndescription: y\n---\nbody");
    expected = [ ];
  };
  testPiIsMorePermissiveThanAgentSkills = {
    # `--leading-hyphen` passes pi's ^[a-z0-9-]+$ but fails agent-skills'
    # stricter [a-z0-9]+(-[a-z0-9]+)* — proof the containment runs one way.
    expr = {
      pi = piWarn "-x" (fm.parse "---\nname: -x\ndescription: y\n---\nbody") == [ ];
      agentSkills = tryValidate {
        dirName = "-x";
        parsed = fm.parse "---\nname: -x\ndescription: y\n---\nbody";
      };
    };
    expected = {
      pi = true;
      agentSkills = false;
    };
  };
  testAgentSkillsAcceptanceImpliesPiClean = {
    expr = lib.all (p: piWarn (p.fields.name or "x") p == [ ]) acceptedSamples;
    expected = true;
  };
```

- [ ] **Step 2: Run to see it fail**

Run:
```bash
cd /home/joe/Development/agent-skills && nix build .#checks.x86_64-linux.lint-tests --no-link 2>&1 | tail -10
```

Expected: `error: attribute 'piSkillWarnings' missing`.

- [ ] **Step 3: Implement `piSkillWarnings` in `lib/lint.nix`**

In the `let` block, after `charCount`:

```nix
  # pi's own skill validation, transcribed from
  # pi v0.84.2 packages/coding-agent/src/core/skills.ts (validateName /
  # validateDescription). Kept independent of the agent-skills rules above
  # so a future loosening of validateSkillMd cannot silently ship a skill
  # pi would warn about.
  piMaxNameLength = 64;
  piMaxDescriptionLength = 1024;
  piNamePattern = "[a-z0-9-]+";
```

Add all four to the `inherit` list of the returned attrset:

```nix
  inherit
    portableFields
    claudeCodeFields
    knownFields
    sidecarKeys
    agentFields
    agentFieldAliases
    agentKnownFields
    piMaxNameLength
    piMaxDescriptionLength
    piNamePattern
    ;
```

and add the function itself to the returned attrset, next to `validateSkillMd`:

```nix
  # Diagnostics pi would emit for this skill; [ ] means pi loads it cleanly.
  # pi falls back to the parent directory name when `name` is absent, and
  # ignores every frontmatter key it does not model, so only name and
  # description are checked.
  piSkillWarnings =
    { dirName, parsed }:
    let
      f = parsed.fields;
      name = f.name or dirName;
      desc = f.description or "";
    in
    lib.optional (lib.stringLength name > piMaxNameLength)
      "name exceeds ${toString piMaxNameLength} characters"
    ++ lib.optional (builtins.match piNamePattern name == null)
      "name contains invalid characters (must be lowercase a-z, 0-9, hyphens only)"
    ++ lib.optional (lib.trim desc == "") "description is required"
    ++ lib.optional (lib.stringLength desc > piMaxDescriptionLength)
      "description exceeds ${toString piMaxDescriptionLength} characters";
```

- [ ] **Step 4: Run to see the unit tests pass**

Run:
```bash
cd /home/joe/Development/agent-skills && nix fmt && nix build .#checks.x86_64-linux.lint-tests --no-link && echo LINT_TESTS_OK
```

Expected: `LINT_TESTS_OK`.

- [ ] **Step 5: Add the repo-wide check**

In `flake.nix` `checks`, after `lint-tests`:

```nix
          # Every shipped skill must load into pi without a diagnostic. The
          # agent-skills rules are strictly stricter than pi's, so this
          # should never fire — it fires only if that stops being true.
          pi-frontmatter =
            let
              lintLib = import ./lib/lint.nix { inherit lib; };
              build = import ./lib/default.nix {
                inherit pkgs lib;
                claudeLib = import "${claude-nix}/lib" { inherit pkgs; };
              };
              skills = build.discoverSkills ./skills;
              offenders = lib.concatMap (
                s:
                map (w: "${s.name}: ${w}") (lintLib.piSkillWarnings {
                  dirName = s.name;
                  inherit (s) parsed;
                })
              ) skills;
            in
            if offenders == [ ] then
              pkgs.runCommand "pi-frontmatter" { } "touch $out"
            else
              throw "pi frontmatter violations: ${builtins.toJSON offenders}";
```

- [ ] **Step 6: Run the repo-wide check**

Run:
```bash
cd /home/joe/Development/agent-skills && nix build .#checks.x86_64-linux.pi-frontmatter --no-link && echo PI_FRONTMATTER_OK
```

Expected: `PI_FRONTMATTER_OK`.

Prove it can fail — temporarily break a skill and confirm the throw names it:

```bash
cd /home/joe/Development/agent-skills
sed -i '0,/^description:/ s/^description:.*/description:/' skills/format-nix/SKILL.md
nix build .#checks.x86_64-linux.pi-frontmatter --no-link 2>&1 | grep -o 'format-nix: [^"]*'
git checkout skills/format-nix/SKILL.md
```

Expected: the grep prints a `format-nix: …` line. (`validateSkillMd` rejects the empty description first, so the message may come from either lint; what matters is that the build fails and names the skill.)

- [ ] **Step 7: Commit**

```bash
cd /home/joe/Development/agent-skills
git add -A
git commit -m "test(pi): lint every skill against pi's own frontmatter rules

piSkillWarnings transcribes pi's validateName/validateDescription rather
than reusing the agent-skills rules, so the containment (ours are strictly
stricter) is a checked property instead of an assumption. checks.pi-frontmatter
runs it over the whole library."
```

---

### Task 4: `buildPiPlugin` — the pi package, skills only

The first task that produces a pi artifact. Scope is deliberately narrow: a `package.json` with the `pi` manifest key plus `skills/`. Prompts and extensions arrive in Tasks 5 and 6. The A3 gate lands here, before anything can break it.

**Files:**
- Modify: `/home/joe/Development/agent-skills/lib/default.nix` (`buildPiPlugin`, exported)
- Modify: `/home/joe/Development/agent-skills/flake.nix` (`pi-plugin` package, `checks.pi-skill-realpath-identity`, `checks.pi-package-manifest`)

**Interfaces:**
- Consumes: `piLib.mkPlugin` (Task 1); `discoverSkills` records `{ name; dir; parsed; meta; drv; }`; `skillPackagesOf`
- Produces:
  - `build.buildPiPlugin :: { name, description, skills, attributionFile ? null, extraPackages ? [ ] } -> derivation`
  - `packages.<system>.pi-plugin`

- [ ] **Step 1: Write the failing checks**

In `flake.nix` `checks`, after `pi-frontmatter`:

```nix
          # ── A3 gate ──
          # pi de-duplicates skills by canonicalised real path BEFORE it
          # de-duplicates by name (skills.ts loadSkills: realPathSet is
          # consulted first, and a hit is skipped silently; a name hit that
          # is not a real-path hit raises a startup collision warning).
          # ~/.agents/skills and the pi package therefore cost nothing only
          # while both bottom out at the same skill-<name> derivation.
          # A cp -r in buildPiPlugin would still "work" and would still
          # de-duplicate — it would just print one warning per skill on every
          # session start. This check is the only thing that notices.
          pi-skill-realpath-identity =
            let
              piTree = self.packages.${system}.pi-plugin;
              claudeTree = self.packages.${system}.claude-plugin;
              build = import ./lib/default.nix {
                inherit pkgs lib;
                claudeLib = import "${claude-nix}/lib" { inherit pkgs; };
              };
              skills = build.discoverSkills ./skills;
            in
            pkgs.runCommand "pi-skill-realpath-identity"
              {
                inherit piTree claudeTree;
                names = lib.concatStringsSep " " (map (s: s.name) skills);
                sources = lib.concatStringsSep " " (map (s: "${s.name}=${s.drv}") skills);
              }
              ''
                fail=0
                for pair in $sources; do
                  n="''${pair%%=*}"
                  drv="''${pair#*=}"
                  want="$(realpath "$drv/skills/$n/SKILL.md")"
                  got_pi="$(realpath "$piTree/skills/$n/SKILL.md")"
                  got_cc="$(realpath "$claudeTree/skills/$n/SKILL.md")"
                  if [ "$got_pi" != "$want" ]; then
                    echo "pi package copies '$n' instead of linking it:"
                    echo "  want $want"
                    echo "  got  $got_pi"
                    fail=1
                  fi
                  if [ "$got_pi" != "$got_cc" ]; then
                    echo "realpath drift between pi and claude trees for '$n':"
                    echo "  pi     $got_pi"
                    echo "  claude $got_cc"
                    fail=1
                  fi
                done
                [ "$fail" = 0 ] || exit 1
                touch $out
              '';

          # The pi manifest must be present and well-formed; pi's
          # readPiManifest returns null (and silently falls back to
          # convention directories) for anything it cannot parse.
          pi-package-manifest =
            let
              piTree = self.packages.${system}.pi-plugin;
            in
            pkgs.runCommand "pi-package-manifest" { nativeBuildInputs = [ pkgs.jq ]; } ''
              jq -e '.pi.skills == ["./skills"]' ${piTree}/package.json >/dev/null
              jq -e '.keywords | index("pi-package")' ${piTree}/package.json >/dev/null
              jq -e '.name == "agent-skills"' ${piTree}/package.json >/dev/null
              touch $out
            '';
```

- [ ] **Step 2: Run to see it fail**

Run:
```bash
cd /home/joe/Development/agent-skills && nix build .#checks.x86_64-linux.pi-package-manifest --no-link 2>&1 | tail -5
```

Expected: `error: attribute 'pi-plugin' missing`.

- [ ] **Step 3: Implement `buildPiPlugin` in `lib/default.nix`**

Insert after `buildCodexPlugin`, before the `# ── Cross-agent plugins ──` comment:

```nix
  # ── pi package ──
  # pi consumes a *package*: a directory whose package.json carries a `pi`
  # key naming the resource directories (pi.dev/docs/latest/packages). One
  # entry in settings.packages loads skills, prompt templates, and
  # extensions together.
  #
  # A3 (design §4): skills are the SAME skill-<name> derivations the Claude
  # plugin ships, linked in by buildEnv — never copied. pi's loadSkills
  # consults a realpath set before its name map, so a skill reachable via
  # both ~/.agents/skills and this package is dropped silently rather than
  # raising a startup collision warning. checks.pi-skill-realpath-identity
  # is the gate; do not replace the link with a copy.
  buildPiPlugin =
    {
      name,
      description,
      skills,
      attributionFile ? null,
      extraPackages ? [ ],
    }:
    assert piLib != null;
    let
      skillPackages = skillPackagesOf skills;

      plugin = piLib.mkPlugin {
        inherit name description;
        skills = map (s: s.drv) skills;
      };

      attributionDrv = lib.optional (attributionFile != null) (
        pkgs.runCommand "${name}-pi-attribution" { } ''
          mkdir -p $out
          cp ${attributionFile} $out/ATTRIBUTION
        ''
      );
    in
    pkgs.buildEnv {
      name = "${name}-pi-complete";
      paths = [ plugin ] ++ attributionDrv ++ extraPackages ++ skillPackages;
      passthru.meta = { inherit name description; };
    };
```

and add `buildPiPlugin` to the exported `inherit` list at the bottom of the file, after `buildCodexPlugin`.

- [ ] **Step 4: Add the `pi-plugin` package**

In `flake.nix`, after the `codex-plugin` block:

```nix
          # ── pi package ──
          # Skills ride in as the same per-skill derivations the Claude
          # plugin ships, which is what makes the ~/.agents/skills double
          # load free (design §11, assumption A3).
          pi-plugin = build.buildPiPlugin {
            name = "agent-skills";
            description = "Agent skills for pi";
            inherit skills;
            attributionFile = ./ATTRIBUTION.md;
          };
```

and add `pi-plugin` to the exported attrset alongside `codex-plugin`:

```nix
          inherit
            claude-plugin
            antigravity-plugin
            codex-plugin
            pi-plugin
            vibecad
            pxd
            figr
            ;
```

- [ ] **Step 5: Build and inspect the tree by hand**

Run:
```bash
cd /home/joe/Development/agent-skills && nix fmt && nix build .#pi-plugin --no-link --print-out-paths
```

Then, with `P` set to that path:
```bash
P=$(nix build .#pi-plugin --no-link --print-out-paths)
cat $P/package.json
ls $P/skills | head -5
ls -l $P/skills/format-nix
realpath $P/skills/format-nix/SKILL.md
```

Expected: `package.json` contains `"pi": { "skills": ["./skills"] }` and `"keywords": ["pi-package"]`; `skills/` lists every skill; `skills/format-nix` is a symlink; the `realpath` ends in `-skill-format-nix/skills/format-nix/SKILL.md`.

- [ ] **Step 6: Run both checks to see them pass**

Run:
```bash
cd /home/joe/Development/agent-skills
nix build .#checks.x86_64-linux.pi-package-manifest --no-link && echo MANIFEST_OK
nix build .#checks.x86_64-linux.pi-skill-realpath-identity --no-link && echo REALPATH_OK
```

Expected: `MANIFEST_OK` then `REALPATH_OK`.

- [ ] **Step 7: Prove the A3 gate actually catches a copy**

Temporarily break it, confirm the check fires, then revert:

```bash
cd /home/joe/Development/agent-skills
python3 - <<'PY'
import re, pathlib
p = pathlib.Path("lib/default.nix")
s = p.read_text()
s = s.replace(
    "        skills = map (s: s.drv) skills;\n      };\n\n      attributionDrv = lib.optional (attributionFile != null) (\n        pkgs.runCommand \"${name}-pi-attribution\"",
    "        skills = map (s: pkgs.runCommand \"copied-${s.name}\" { } ''\n          mkdir -p $out/skills\n          cp -rL ${s.drv}/skills/${s.name} $out/skills/${s.name}\n        '') skills;\n      };\n\n      attributionDrv = lib.optional (attributionFile != null) (\n        pkgs.runCommand \"${name}-pi-attribution\"",
    1)
p.write_text(s)
PY
nix build .#checks.x86_64-linux.pi-skill-realpath-identity --no-link 2>&1 | grep -m1 "copies"
git checkout lib/default.nix
nix build .#checks.x86_64-linux.pi-skill-realpath-identity --no-link && echo REALPATH_OK_AGAIN
```

Expected: a `pi package copies '…' instead of linking it:` line, then `REALPATH_OK_AGAIN`.

- [ ] **Step 8: Commit**

```bash
cd /home/joe/Development/agent-skills
git add -A
git commit -m "feat(pi): buildPiPlugin emitting a real pi package

package.json carries the pi manifest key; skills/ links the same
skill-<name> derivations the Claude plugin ships. That link is what makes
the ~/.agents/skills double load free: pi's loadSkills consults a realpath
set before its name map, so an identically-resolving skill is skipped
silently instead of raising a startup collision warning (assumption A3,
verified against pi v0.84.2). checks.pi-skill-realpath-identity is the gate."
```

---

### Task 5: Command-style skills become pi prompt templates

`disable-model-invocation: true` marks a skill as a command-style workflow. pi honours that field natively — `formatSkillsForPrompt` filters those skills out of the model-visible list — and separately registers every skill as `/skill:<name>`. What it does not give you is the short `/name` form with an argument hint, which is what a prompt template is. Two skills qualify today: `format-nix` and `nix-dotfiles`, both already carrying `argument-hint` and `$ARGUMENTS`, which pi substitutes natively.

**Files:**
- Modify: `/home/joe/Development/agent-skills/lib/default.nix`
- Modify: `/home/joe/Development/agent-skills/flake.nix` (`checks.pi-prompt-templates`)

**Interfaces:**
- Consumes: `piLib.mkPromptTemplate` (Task 1); `skill.parsed.fields."disable-model-invocation"` and `skill.parsed.fields."argument-hint"` — both already parsed by `lib/frontmatter.nix`, which unquotes `"[directory]"` to `[directory]`
- Produces:
  - `build.isPiCommandSkill :: skillRecord -> bool`
  - `buildPiPlugin` gains a `prompts` list in its `piLib.mkPlugin` call; `package.json` gains `"prompts": ["./prompts"]`

- [ ] **Step 1: Write the failing check**

In `flake.nix` `checks`, after `pi-package-manifest`:

```nix
          # Command-style skills (disable-model-invocation) get a pi prompt
          # template so they are reachable as /name, not just /skill:name.
          # Model-invocable skills must NOT get one.
          pi-prompt-templates =
            let
              piTree = self.packages.${system}.pi-plugin;
            in
            pkgs.runCommand "pi-prompt-templates" { nativeBuildInputs = [ pkgs.jq ]; } ''
              jq -e '.pi.prompts == ["./prompts"]' ${piTree}/package.json >/dev/null

              test -f ${piTree}/prompts/format-nix.md
              test -f ${piTree}/prompts/nix-dotfiles.md

              # description and argument-hint carried over from frontmatter
              grep -qxF 'description: Format all Nix files in the project with nixfmt' \
                ${piTree}/prompts/format-nix.md
              grep -qxF 'argument-hint: "[directory]"' ${piTree}/prompts/format-nix.md
              grep -qxF 'argument-hint: "<what to change>"' ${piTree}/prompts/nix-dotfiles.md

              # body carried over verbatim, including pi-native $ARGUMENTS
              grep -qF '$ARGUMENTS' ${piTree}/prompts/format-nix.md

              # Claude-only frontmatter must not leak into the template
              grep -q '^disable-model-invocation:' ${piTree}/prompts/format-nix.md && exit 1
              grep -q '^allowed-tools:' ${piTree}/prompts/format-nix.md && exit 1

              # model-invocable skills get no template
              test ! -e ${piTree}/prompts/using-agent-skills.md
              test ! -e ${piTree}/prompts/writing-skills.md

              # ...but they are still shipped as skills
              test -f ${piTree}/skills/format-nix/SKILL.md
              test -f ${piTree}/skills/using-agent-skills/SKILL.md

              touch $out
            '';
```

Note `writing-skills` is asserted absent on purpose: it *mentions* `disable-model-invocation` in its body but does not set it in frontmatter, so a body-grep implementation would wrongly produce a template for it.

- [ ] **Step 2: Run to see it fail**

Run:
```bash
cd /home/joe/Development/agent-skills && nix build .#checks.x86_64-linux.pi-prompt-templates --no-link 2>&1 | tail -5
```

Expected: fails on `jq -e '.pi.prompts == ["./prompts"]'` — the manifest has no `prompts` key yet.

- [ ] **Step 3: Add the predicate and the template builder**

In `lib/default.nix`, immediately above `buildPiPlugin`:

```nix
  # A command-style skill: invoked by the user, hidden from the model's
  # skill list. pi honours `disable-model-invocation` natively
  # (formatSkillsForPrompt filters them out) and registers every skill as
  # /skill:<name>; the prompt template is what gives it the short /<name>
  # form plus an argument hint in the autocomplete.
  isPiCommandSkill = skill: (skill.parsed.fields."disable-model-invocation" or "false") == "true";

  # SKILL.md frontmatter → pi prompt-template frontmatter. `description` is
  # required (pi otherwise takes the first 60 characters of the body);
  # `argument-hint` is forwarded when present. Everything else is dropped:
  # a prompt template is a body plus those two fields, nothing more.
  mkPiPromptTemplateFor =
    skill:
    assert piLib != null;
    piLib.mkPromptTemplate (
      {
        inherit (skill.meta) name description;
      }
      // lib.optionalAttrs (skill.parsed.fields ? "argument-hint") {
        argument-hint = skill.parsed.fields."argument-hint";
      }
    ) skill.parsed.body;
```

- [ ] **Step 4: Wire prompts into `buildPiPlugin`**

In `buildPiPlugin`'s `let`, before `plugin`:

```nix
      prompts = map mkPiPromptTemplateFor (builtins.filter isPiCommandSkill skills);
```

and change the `piLib.mkPlugin` call to:

```nix
      plugin = piLib.mkPlugin {
        inherit name description prompts;
        skills = map (s: s.drv) skills;
      };
```

Add `isPiCommandSkill` and `mkPiPromptTemplateFor` to the exported `inherit` list.

- [ ] **Step 5: Run to see it pass**

Run:
```bash
cd /home/joe/Development/agent-skills && nix fmt && nix build .#checks.x86_64-linux.pi-prompt-templates --no-link && echo PROMPTS_OK
```

Expected: `PROMPTS_OK`.

- [ ] **Step 6: Eyeball the rendered template**

Run:
```bash
P=$(cd /home/joe/Development/agent-skills && nix build .#pi-plugin --no-link --print-out-paths)
cat $P/prompts/format-nix.md
```

Expected, exactly:
```
---
description: Format all Nix files in the project with nixfmt
argument-hint: "[directory]"
---

Format all Nix files using nixfmt.

If an argument is provided, format files in that directory.
Otherwise, format all .nix files in the current directory.

Use: fd -e nix -x nixfmt

$ARGUMENTS
```

If `argument-hint` renders unquoted, the value `[directory]` is a YAML flow sequence and pi will not read it as a string — fix `mkPromptTemplate` in `pi-nix` to always quote, not this repo.

- [ ] **Step 7: Verify the A3 gate still holds**

Run:
```bash
cd /home/joe/Development/agent-skills && nix build .#checks.x86_64-linux.pi-skill-realpath-identity --no-link && echo REALPATH_STILL_OK
```

Expected: `REALPATH_STILL_OK`. Adding a second resource directory changes how `buildEnv` links `skills/`; this confirms it still bottoms out at the same derivations.

- [ ] **Step 8: Commit**

```bash
cd /home/joe/Development/agent-skills
git add -A
git commit -m "feat(pi): command-style skills become pi prompt templates

disable-model-invocation skills gain a prompts/<name>.md slash command
carrying description and argument-hint from frontmatter, so they are
reachable as /format-nix rather than only /skill:format-nix. They remain
shipped as skills; pi filters them out of the model-visible list itself."
```

---

### Task 6: `hooks/session-start.sh` becomes `extensions/agent-skills-session-start.ts`

The `SessionStart` hook injects the whole `using-agent-skills` skill plus a legacy-directory warning as `additionalContext`. pi has no hooks, so this becomes an extension. The nearest pi equivalent of `additionalContext` is appending to `event.systemPrompt` in `before_agent_start` — the pattern the upstream `claude-rules.ts` example uses, and one that chains cleanly when several extensions do it.

One behavioural difference is deliberate and worth stating: Claude injects once, as a transcript message; pi re-appends to a system prompt that is rebuilt every turn. The steady-state content is identical, and because the appended string is byte-stable it does not disturb prompt caching. The one part that must *not* repeat — the "IN YOUR FIRST REPLY" legacy warning — is gated to the first turn after each session start.

**Files:**
- Create: `/home/joe/Development/agent-skills/extensions/agent-skills-session-start.ts`
- Modify: `/home/joe/Development/agent-skills/lib/default.nix` (`buildPiExtensions`, `buildPiPlugin` gains `extensionsDir`)
- Modify: `/home/joe/Development/agent-skills/flake.nix` (`pi-plugin` passes `extensionsDir`, `checks.pi-extensions`)

**Interfaces:**
- Consumes: `buildUsingAgentSkillsContent` (existing, in `lib/default.nix`); `piLib.mkPlugin`'s `extensions` argument
- Produces:
  - `build.buildPiExtensions :: str -> [skillRecord] -> path -> derivation` producing `$out/extensions/*.ts` with `@USING_AGENT_SKILLS@` substituted
  - `buildPiPlugin` gains `extensionsDir ? null`; `package.json` gains `"extensions": ["./extensions"]`

- [ ] **Step 1: Write the failing check**

In `flake.nix` `checks`, after `pi-prompt-templates`:

```nix
          pi-extensions =
            let
              piTree = self.packages.${system}.pi-plugin;
            in
            pkgs.runCommand "pi-extensions" { nativeBuildInputs = [ pkgs.jq ]; } ''
              jq -e '.pi.extensions == ["./extensions"]' ${piTree}/package.json >/dev/null
              test -f ${piTree}/extensions/agent-skills-session-start.ts

              # The build-time placeholder must be gone and replaced by a
              # store path that exists and holds the real skill.
              ! grep -q '@USING_AGENT_SKILLS@' ${piTree}/extensions/agent-skills-session-start.ts
              p=$(grep -o '/nix/store/[^"]*using-agent-skills-content' \
                    ${piTree}/extensions/agent-skills-session-start.ts | head -1)
              test -n "$p"
              grep -q 'name: using-agent-skills' "$p"

              # Only type imports — a value import from @earendil-works
              # would fail to resolve from a /nix/store path.
              ! grep -E '^import[^t]' ${piTree}/extensions/agent-skills-session-start.ts \
                | grep -q '@earendil-works'

              touch $out
            '';
```

- [ ] **Step 2: Run to see it fail**

Run:
```bash
cd /home/joe/Development/agent-skills && nix build .#checks.x86_64-linux.pi-extensions --no-link 2>&1 | tail -5
```

Expected: fails on `jq -e '.pi.extensions == ["./extensions"]'`.

- [ ] **Step 3: Write the extension**

Create `/home/joe/Development/agent-skills/extensions/agent-skills-session-start.ts`:

```ts
/**
 * agent-skills session-start context injection, for pi.
 *
 * pi has no hook system, so this is the extension form of
 * hooks/session-start.sh. That hook emits SessionStart additionalContext;
 * the pi equivalent is appending to event.systemPrompt in
 * before_agent_start, which pi chains across extensions.
 *
 * Difference from the hook, deliberate: Claude injects once as a transcript
 * message, pi re-appends every turn to a system prompt it rebuilds anyway.
 * The appended string is byte-stable, so caching is unaffected. The legacy
 * warning is the one part that must not repeat, so it is gated to the first
 * turn after each session start — matching the hook's once-per-session
 * delivery of "IN YOUR FIRST REPLY AFTER SEEING THIS MESSAGE".
 *
 * @USING_AGENT_SKILLS@ is replaced at Nix build time with the store path of
 * the rendered using-agent-skills SKILL.md, exactly as the shell hook does.
 */
import { existsSync, readFileSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

const SKILL_CONTENT_PATH = "@USING_AGENT_SKILLS@";
const LEGACY_SKILLS_DIR = join(homedir(), ".config", "superpowers", "skills");

const LEGACY_WARNING =
  "\n\n<important-reminder>IN YOUR FIRST REPLY AFTER SEEING THIS MESSAGE YOU MUST TELL THE USER:" +
  "⚠️ **WARNING:** Superpowers now uses Claude Code's skills system. Custom skills in " +
  "~/.config/superpowers/skills will not be read. Move custom skills to ~/.claude/skills instead. " +
  "To make this message go away, remove ~/.config/superpowers/skills</important-reminder>";

function readSkillContent(): string {
  try {
    return readFileSync(SKILL_CONTENT_PATH, "utf-8");
  } catch {
    return "Error reading using-agent-skills skill";
  }
}

function buildBlock(warning: string): string {
  return (
    "<EXTREMELY_IMPORTANT>\n" +
    "You have agent skills.\n\n" +
    "**Below is the full content of your 'agent-skills:using-agent-skills' skill - " +
    "your introduction to using skills. For all other skills, use the 'Skill' tool:**\n\n" +
    readSkillContent() +
    "\n\n" +
    warning +
    "\n</EXTREMELY_IMPORTANT>"
  );
}

export default function agentSkillsSessionStart(pi: ExtensionAPI) {
  // Read once per process; the store path is immutable.
  const steady = buildBlock("");
  let warnPending = false;

  const armWarning = () => {
    warnPending = existsSync(LEGACY_SKILLS_DIR);
  };

  pi.on("session_start", () => {
    armWarning();
  });

  // Post-compaction context refresh, the analogue of the hook's
  // "compact" SessionStart matcher.
  pi.on("session_compact", () => {
    armWarning();
  });

  pi.on("before_agent_start", (event) => {
    const block = warnPending ? buildBlock(LEGACY_WARNING) : steady;
    warnPending = false;
    return { systemPrompt: `${event.systemPrompt}\n\n${block}` };
  });
}
```

- [ ] **Step 4: Add `buildPiExtensions` to `lib/default.nix`**

Immediately above `buildPiPlugin`:

```nix
  # ── pi extensions ──
  # Same substitution contract as buildSessionStartHooks: every .ts under
  # the directory gets @USING_AGENT_SKILLS@ replaced with the store path of
  # the rendered using-agent-skills SKILL.md.
  buildPiExtensions =
    name: skills: extensionsDir:
    let
      skillContentFile = pkgs.writeText "using-agent-skills-content" (
        buildUsingAgentSkillsContent skills
      );
    in
    pkgs.runCommand "${name}-pi-extensions" { } ''
      mkdir -p $out/extensions
      for item in ${extensionsDir}/*.ts; do
        substitute "$item" $out/extensions/"$(basename "$item")" \
          --replace-fail @USING_AGENT_SKILLS@ ${skillContentFile}
      done
    '';
```

`--replace-fail` is load-bearing: an extension that stops referencing the placeholder fails the build rather than shipping stale wiring.

- [ ] **Step 5: Wire it into `buildPiPlugin`**

Add `extensionsDir ? null,` to the argument set (after `skills,`), add to the `let`:

```nix
      extensions = lib.optional (extensionsDir != null) (
        buildPiExtensions name skills extensionsDir
      );
```

and extend the `mkPlugin` call:

```nix
      plugin = piLib.mkPlugin {
        inherit
          name
          description
          prompts
          extensions
          ;
        skills = map (s: s.drv) skills;
      };
```

Add `buildPiExtensions` to the exported `inherit` list.

- [ ] **Step 6: Pass the directory from `flake.nix`**

In the `pi-plugin` block:

```nix
          pi-plugin = build.buildPiPlugin {
            name = "agent-skills";
            description = "Agent skills for pi";
            inherit skills;
            extensionsDir = ./extensions;
            attributionFile = ./ATTRIBUTION.md;
          };
```

- [ ] **Step 7: Run to see it pass**

Run:
```bash
cd /home/joe/Development/agent-skills && nix fmt && nix build .#checks.x86_64-linux.pi-extensions --no-link && echo EXTENSIONS_OK
```

Expected: `EXTENSIONS_OK`.

- [ ] **Step 8: Run the extension against real pi**

This is the only step that proves the TypeScript actually loads. It needs a built pi.

```bash
cd /home/joe/Development/pi-nix && nix build .#coding-agent --no-link --print-out-paths
```

Then, with `PI` set to that path and `P` to the pi-plugin path:

```bash
PI=$(cd /home/joe/Development/pi-nix && nix build .#coding-agent --no-link --print-out-paths)
P=$(cd /home/joe/Development/agent-skills && nix build .#pi-plugin --no-link --print-out-paths)
T=$(mktemp -d); mkdir -p "$T/agent" "$T/cwd"
printf '{"packages":["%s"]}\n' "$P" > "$T/agent/settings.json"
cat > "$T/probe.ts" <<'EOF'
export default function (pi: any) {
  pi.on("before_agent_start", (e: any) => {
    const sp: string = e.systemPrompt;
    console.error("PROBE injected=" + (sp.includes("You have agent skills.") ? 1 : 0));
    console.error("PROBE prompts-visible=" + (sp.includes("format-nix") ? 1 : 0));
    process.exit(0);
  });
}
EOF
cd "$T/cwd" && PI_OFFLINE=1 PI_CODING_AGENT_DIR="$T/agent" \
  "$PI/bin/pi" --offline --no-context-files --no-session -e "$T/probe.ts" \
  --print x --provider anthropic --model claude-sonnet-4-5 --api-key sk-invalid \
  2>&1 </dev/null | grep -E 'PROBE|collision'
```

Expected: `PROBE injected=1`, and **no `collision` line** — the A3 property, observed live against the real `~/.agents/skills`. The `sk-invalid` key means the run ends in a 401 after the probe has already printed; that is fine.

- [ ] **Step 9: Commit**

```bash
cd /home/joe/Development/agent-skills
git add -A
git commit -m "feat(pi): session-start context injection as a pi extension

pi has no hooks, so hooks/session-start.sh becomes an extension appending
to event.systemPrompt in before_agent_start. The using-agent-skills store
path is substituted at build time exactly as the shell hook does; the
legacy-directory warning is gated to the first turn after each session
start so the once-only wording stays once-only."
```

---

### Task 7: `temporal` builds for pi, and `targetLibs` gains its fourth entry

`temporal` is the only cross-agent plugin. For the three hook-based targets it ships a Python script wired to `UserPromptSubmit` and `SessionStart`. pi gets a TypeScript extension instead, so the plugin definition needs a way to say "for this target, an extension rather than a hook" — a small, principled widening of the cross-agent plugin contract.

**Files:**
- Create: `/home/joe/Development/agent-skills/plugins/temporal/temporal.ts`
- Modify: `/home/joe/Development/agent-skills/plugins/temporal/plugin.nix`
- Modify: `/home/joe/Development/agent-skills/lib/default.nix` (`mkCrossAgentPlugin` pi arm)
- Modify: `/home/joe/Development/agent-skills/flake.nix` (`targetLibs.pi`, target list, `checks.temporal-pi`)

**Interfaces:**
- Consumes: `piLib.mkSkill`, `piLib.mkPlugin`; the cross-agent plugin definition `{ name; description; skill ? null; hooks ? [ ]; packages ? [ ]; }`
- Produces:
  - Cross-agent plugin definitions may declare `extensions :: [ { name :: str; source :: path; } ]`. `mkCrossAgentPlugin` renders each to `$out/extensions/<name>.ts`.
  - `packages.<system>.temporal-pi`
  - `targetLibs.pi = piLib`, and `"pi"` in the target list

- [ ] **Step 1: Write the failing check**

In `flake.nix` `checks`, after `pi-extensions`:

```nix
          temporal-pi =
            let
              tree = self.packages.${system}.temporal-pi;
            in
            pkgs.runCommand "temporal-pi" { nativeBuildInputs = [ pkgs.jq ]; } ''
              jq -e '.name == "agent-skills-temporal"' ${tree}/package.json >/dev/null
              jq -e '.pi.extensions == ["./extensions"]' ${tree}/package.json >/dev/null
              test -f ${tree}/extensions/temporal.ts
              test -f ${tree}/skills/temporal/SKILL.md

              # the pi build must not drag in the Python the hook targets need
              test ! -e ${tree}/bin/python3

              # behaviour parity with temporal.py: the three env knobs and
              # both stamp forms must be present
              grep -qF 'TEMPORAL_INTERVAL' ${tree}/extensions/temporal.ts
              grep -qF 'TEMPORAL_TTL_DAYS' ${tree}/extensions/temporal.ts
              grep -qF 'TEMPORAL_STATE_DIR' ${tree}/extensions/temporal.ts
              grep -qF 'post-compaction time check' ${tree}/extensions/temporal.ts
              grep -qF 'unix_ms=' ${tree}/extensions/temporal.ts

              touch $out
            '';
```

- [ ] **Step 2: Run to see it fail**

Run:
```bash
cd /home/joe/Development/agent-skills && nix build .#checks.x86_64-linux.temporal-pi --no-link 2>&1 | tail -5
```

Expected: `error: attribute 'temporal-pi' missing`.

- [ ] **Step 3: Write `temporal.ts`**

Create `/home/joe/Development/agent-skills/plugins/temporal/temporal.ts`:

```ts
/**
 * Time-awareness extension for pi. Port of temporal.py, which serves the
 * three hook-based CLIs.
 *
 * Mapping:
 *   UserPromptSubmit  →  before_agent_start   (throttled by TEMPORAL_INTERVAL)
 *   SessionStart      →  session_start        (unthrottled, fires once)
 *   SessionStart:compact → session_compact    (post-compaction refresh)
 *
 * pi has no additionalContext, so the stamp is appended to the system
 * prompt, which pi rebuilds every turn. Between throttle windows the SAME
 * stamp string is re-appended rather than a fresh one: a per-turn timestamp
 * would invalidate the prompt cache on every request, which is precisely
 * what TEMPORAL_INTERVAL exists to prevent.
 *
 * Env:
 *   TEMPORAL_STATE_DIR  State directory. Default ~/.pi/.temporal, matching
 *                       the per-CLI convention in plugin.nix.
 *   TEMPORAL_INTERVAL   Min seconds between per-turn injects (default 300, 0=always).
 *   TEMPORAL_TTL_DAYS   Days before a stale session JSON is swept (default 7).
 */
import { mkdirSync, readFileSync, readdirSync, rmSync, statSync, writeFileSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";
import type { ExtensionAPI, ExtensionContext } from "@earendil-works/pi-coding-agent";

const INTERVAL_S = Number.parseInt(process.env.TEMPORAL_INTERVAL ?? "300", 10);
const TTL_S = Number.parseInt(process.env.TEMPORAL_TTL_DAYS ?? "7", 10) * 86400;
const DIR = process.env.TEMPORAL_STATE_DIR ?? join(homedir(), ".pi", ".temporal");

interface State {
  start_ms?: number;
  last_inject_ms?: number;
}

function pad(n: number): string {
  return String(n).padStart(2, "0");
}

function fmt(s: number): string {
  if (s < 60) return `${s}s`;
  if (s < 3600) return `${Math.floor(s / 60)}m${pad(s % 60)}s`;
  return `${Math.floor(s / 3600)}h${pad(Math.floor((s % 3600) / 60))}m`;
}

function sweep(): void {
  try {
    mkdirSync(DIR, { recursive: true });
    const now = Date.now();
    for (const f of readdirSync(DIR)) {
      if (!f.endsWith(".json")) continue;
      const p = join(DIR, f);
      try {
        if (now - statSync(p).mtimeMs > TTL_S * 1000) rmSync(p, { force: true });
      } catch {
        /* best effort, exactly as the Python */
      }
    }
  } catch {
    /* best effort */
  }
}

function statePath(sessionId: string): string {
  return join(DIR, `${sessionId || "nosession"}.json`);
}

function readState(p: string): State {
  try {
    return JSON.parse(readFileSync(p, "utf-8")) as State;
  } catch {
    return {};
  }
}

function writeState(p: string, s: State): void {
  try {
    writeFileSync(p, JSON.stringify(s));
  } catch {
    /* best effort */
  }
}

function stampFor(startMs: number, nowMs: number): string {
  const local = new Date(nowMs);
  const tz =
    new Intl.DateTimeFormat("en-US", { timeZoneName: "short" })
      .formatToParts(local)
      .find((p) => p.type === "timeZoneName")?.value ?? "";
  const utc = local.toISOString().replace(/\.\d{3}Z$/, "Z");
  const sessionS = Math.floor((nowMs - startMs) / 1000);
  return (
    `now=${pad(local.getHours())}:${pad(local.getMinutes())} ${tz} | ` +
    `utc=${utc} | unix_ms=${nowMs} | session=${fmt(sessionS)}`
  );
}

export default function temporal(pi: ExtensionAPI) {
  let sessionId = "";
  let pending: string | null = null;
  let lastEmitted = "";

  const load = (ctx: ExtensionContext): { path: string; state: State; nowMs: number } => {
    sessionId = ctx.sessionManager.getSessionId() ?? sessionId;
    const path = statePath(sessionId);
    const state = readState(path);
    const nowMs = Date.now();
    if (state.start_ms === undefined) state.start_ms = nowMs;
    return { path, state, nowMs };
  };

  pi.on("session_start", (_event, ctx) => {
    sweep();
    const { path, state, nowMs } = load(ctx);
    pending = `[⏱ ${stampFor(state.start_ms as number, nowMs)}]`;
    writeState(path, state);
  });

  pi.on("session_compact", (_event, ctx) => {
    const { path, state, nowMs } = load(ctx);
    pending = `[⏱ post-compaction time check — ${stampFor(state.start_ms as number, nowMs)}]`;
    writeState(path, state);
  });

  pi.on("before_agent_start", (event, ctx) => {
    const { path, state, nowMs } = load(ctx);

    if (pending !== null) {
      lastEmitted = pending;
      pending = null;
      state.last_inject_ms = nowMs;
      writeState(path, state);
    } else {
      const elapsed = Math.floor((nowMs - (state.last_inject_ms ?? 0)) / 1000);
      if (INTERVAL_S === 0 || elapsed >= INTERVAL_S) {
        lastEmitted = `[⏱ ${stampFor(state.start_ms as number, nowMs)}]`;
        state.last_inject_ms = nowMs;
        writeState(path, state);
      }
    }

    if (lastEmitted === "") return;
    return { systemPrompt: `${event.systemPrompt}\n\n${lastEmitted}` };
  });
}
```

- [ ] **Step 4: Teach `plugin.nix` about pi**

Rewrite `/home/joe/Development/agent-skills/plugins/temporal/plugin.nix`:

```nix
# temporal — throttled time injection. Cross-agent plugin definition.
# The three hook-based CLIs get a Python hook; pi, which has no hook
# system, gets the equivalent TypeScript extension. State dir is per-CLI:
# $TEMPORAL_STATE_DIR for the hook targets, ~/.pi/.temporal by default in
# the extension.
{
  pkgs,
  lib,
  target,
  ...
}:
let
  isPi = target == "pi";
  stateSubdir =
    if target == "codex" then
      ".codex"
    else if target == "antigravity" then
      ".antigravity"
    else
      ".claude";
  # $HOME is expanded at runtime by the shell, not at nix-eval time.
  temporalScript = pkgs.writeShellScript "temporal-${target}" ''
    export TEMPORAL_STATE_DIR="$HOME/${stateSubdir}/.temporal"
    exec ${pkgs.python3}/bin/python3 ${./temporal.py} "$@"
  '';
  # Claude scopes SessionStart to specific triggers; the others fire on all.
  sessionMatcher = if target == "claude" then "startup|resume|clear|compact" else "";
in
{
  name = "temporal";
  description = "Use when the user asks about time/date hooks, why timestamps appear in context, or wants to tune the [⏱] injection.";
  # The extension is pure Node stdlib; only the Python hook needs python3.
  packages = lib.optionals (!isPi) [ pkgs.python3 ];
  skill.body = ''
    # temporal — time awareness hook

    Background-only — this plugin contributes a hook, not skill content
    you invoke directly. The hook injects a throttled `[⏱ time]` block at
    UserPromptSubmit and after compaction so the agent knows what time
    it is.

    Configure via env vars:
    - `TEMPORAL_INTERVAL` (seconds, default 300): min interval between injects.
    - `TEMPORAL_TTL_DAYS` (default 7): days before stale session state is swept.
  '';
  extensions = lib.optionals isPi [
    {
      name = "temporal";
      source = ./temporal.ts;
    }
  ];
  hooks = lib.optionals (!isPi) [
    {
      event = "UserPromptSubmit";
      matcher = "";
      name = "temporal-user-prompt-submit";
      command = "${temporalScript}";
    }
    {
      event = "SessionStart";
      matcher = sessionMatcher;
      name = "temporal-session-start";
      command = "${temporalScript}";
    }
  ];
}
```

- [ ] **Step 5: Add the pi arm to `mkCrossAgentPlugin`**

In `lib/default.nix`, inside `mkCrossAgentPlugin`'s `let`, after `targetHooks`:

```nix
      # pi has no hooks; a cross-agent plugin declares `extensions` for it
      # instead, each rendered to $out/extensions/<name>.ts.
      piExtensions = map (
        e:
        pkgs.runCommand "pi-extension-${def.name}-${e.name}" { } ''
          mkdir -p $out/extensions
          cp ${e.source} $out/extensions/${e.name}.ts
        ''
      ) (def.extensions or [ ]);
```

Then insert a `pi` branch between the `claude` branch and the trailing `else`:

```nix
    else if target == "pi" then
      let
        plugin = targetLib.mkPlugin {
          name = pluginName;
          inherit (def) description;
          inherit skills;
          extensions = piExtensions;
        };
      in
      pkgs.buildEnv {
        name = "${pluginName}-pi-complete";
        paths = [ plugin ] ++ packages ++ attributionDrv;
        passthru.meta = {
          name = pluginName;
          inherit (def) description;
        };
      }
    else
```

The existing `hooks` handling stays untouched: `def.hooks` is empty for pi, so `targetHooks` is `[ ]` and `targetLib.mkHook` — which `piLib` does not define — is never reached.

- [ ] **Step 6: Add pi to `targetLibs` and the target list**

In `flake.nix`:

```nix
          targetLibs = {
            claude = claudeLib;
            antigravity = agyLib;
            codex = codexLib;
            pi = piLib;
          };
```

and

```nix
              [
                "claude"
                "antigravity"
                "codex"
                "pi"
              ]
```

- [ ] **Step 7: Run to see it pass**

Run:
```bash
cd /home/joe/Development/agent-skills && nix fmt && nix build .#checks.x86_64-linux.temporal-pi --no-link && echo TEMPORAL_PI_OK
```

Expected: `TEMPORAL_PI_OK`.

- [ ] **Step 8: Confirm the three hook targets are untouched**

Run:
```bash
cd /home/joe/Development/agent-skills
for t in claude antigravity codex; do
  echo "── $t"
  nix build .#temporal-$t --no-link --print-out-paths
done
```

Expected: all three build. Diff one against the pre-change output to confirm the `lib.optionals` refactor changed nothing for them:

```bash
cd /home/joe/Development/agent-skills
git stash && BEFORE=$(nix build .#temporal-claude --no-link --print-out-paths) && git stash pop
AFTER=$(nix build .#temporal-claude --no-link --print-out-paths)
[ "$BEFORE" = "$AFTER" ] && echo TEMPORAL_CLAUDE_UNCHANGED || diff -r "$BEFORE" "$AFTER"
```

Expected: `TEMPORAL_CLAUDE_UNCHANGED`. A differing store path means the refactor altered the Claude output — find out why before continuing.

- [ ] **Step 9: Run the temporal extension against real pi**

```bash
PI=$(cd /home/joe/Development/pi-nix && nix build .#coding-agent --no-link --print-out-paths)
TP=$(cd /home/joe/Development/agent-skills && nix build .#temporal-pi --no-link --print-out-paths)
T=$(mktemp -d); mkdir -p "$T/agent" "$T/cwd" "$T/state"
printf '{"packages":["%s"]}\n' "$TP" > "$T/agent/settings.json"
cat > "$T/probe.ts" <<'EOF'
export default function (pi: any) {
  pi.on("before_agent_start", (e: any) => {
    const m = e.systemPrompt.match(/\[⏱ [^\]]*\]/);
    console.error("PROBE stamp=" + (m ? m[0] : "NONE"));
    process.exit(0);
  });
}
EOF
cd "$T/cwd" && PI_OFFLINE=1 TEMPORAL_STATE_DIR="$T/state" PI_CODING_AGENT_DIR="$T/agent" \
  "$PI/bin/pi" --offline --no-context-files -e "$T/probe.ts" \
  --print x --provider anthropic --model claude-sonnet-4-5 --api-key sk-invalid \
  2>&1 </dev/null | grep PROBE
ls "$T/state"
```

Expected: a `PROBE stamp=[⏱ now=HH:MM … | utc=…Z | unix_ms=… | session=…]` line, and one `<session-id>.json` in the state dir. The probe's own extension loads via `-e`, which survives package loading; `--no-session` is omitted here because temporal keys its state on the session id.

- [ ] **Step 10: Commit**

```bash
cd /home/joe/Development/agent-skills
git add -A
git commit -m "feat(pi): temporal builds for pi, and targetLibs gains its fourth entry

pi has no hooks, so cross-agent plugin definitions may now declare
extensions[] alongside hooks[]; temporal picks one or the other from its
target argument. temporal.ts reproduces temporal.py's throttle, TTL sweep,
and stamp format, re-appending the same stamp between throttle windows so
the prompt cache survives. The three hook targets build byte-identically."
```

---

### Task 8: Assert every skill builds for all four targets

The design's testing section (§14) asks for exactly this. It is the check that catches a skill whose frontmatter one target accepts and another silently drops.

**Files:**
- Modify: `/home/joe/Development/agent-skills/flake.nix` (`checks.skills-all-four-targets`)

**Interfaces:**
- Consumes: `self.packages.<system>.{claude,antigravity,codex,pi}-plugin`; `discoverSkills`
- Produces: `checks.<system>.skills-all-four-targets`

- [ ] **Step 1: Write the check**

In `flake.nix` `checks`, after `temporal-pi`:

```nix
          # Design §14: every skill must build for all four targets. This
          # catches the failure mode where one target's mkSkill silently
          # drops a skill whose frontmatter it cannot model.
          skills-all-four-targets =
            let
              build = import ./lib/default.nix {
                inherit pkgs lib;
                claudeLib = import "${claude-nix}/lib" { inherit pkgs; };
              };
              skills = build.discoverSkills ./skills;
            in
            pkgs.runCommand "skills-all-four-targets"
              {
                trees = lib.concatStringsSep " " [
                  "claude=${self.packages.${system}.claude-plugin}"
                  "antigravity=${self.packages.${system}.antigravity-plugin}"
                  "codex=${self.packages.${system}.codex-plugin}"
                  "pi=${self.packages.${system}.pi-plugin}"
                ];
                names = lib.concatStringsSep " " (map (s: s.name) skills);
                expected = toString (builtins.length skills);
              }
              ''
                fail=0
                for pair in $trees; do
                  t="''${pair%%=*}"
                  tree="''${pair#*=}"

                  # every discovered skill is present, with a non-empty SKILL.md
                  for n in $names; do
                    f="$tree/skills/$n/SKILL.md"
                    if [ ! -f "$f" ]; then
                      echo "MISSING: $t is missing skill '$n'"
                      fail=1
                    elif [ ! -s "$f" ]; then
                      echo "EMPTY: $t ships an empty SKILL.md for '$n'"
                      fail=1
                    fi
                  done

                  # and no target ships extras or drops any
                  got=$(ls -1 "$tree/skills" | wc -l)
                  if [ "$got" != "$expected" ]; then
                    echo "COUNT: $t ships $got skills, expected $expected"
                    fail=1
                  fi
                done
                [ "$fail" = 0 ] || exit 1
                echo "all $expected skills present in all four targets"
                touch $out
              '';
```

- [ ] **Step 2: Run it**

Run:
```bash
cd /home/joe/Development/agent-skills && nix fmt && nix build .#checks.x86_64-linux.skills-all-four-targets --no-link -L 2>&1 | tail -3
```

Expected: a line like `all 39 skills present in all four targets`, then success.

- [ ] **Step 3: Prove it can fail**

Run:
```bash
cd /home/joe/Development/agent-skills
mkdir -p skills/probe-target-coverage
cat > skills/probe-target-coverage/SKILL.md <<'EOF'
---
name: probe-target-coverage
description: Temporary skill used to prove the four-target check fires
---
body
EOF
nix build .#checks.x86_64-linux.skills-all-four-targets --no-link && echo "UNEXPECTED PASS"
rm -rf skills/probe-target-coverage
nix build .#checks.x86_64-linux.skills-all-four-targets --no-link && echo COVERAGE_OK_AGAIN
```

Expected: the middle build **passes** (a genuinely well-formed skill does build for all four) and prints `UNEXPECTED PASS`, then `COVERAGE_OK_AGAIN`. That is the right outcome and confirms the count assertion tracks the library rather than a frozen number. To see a real failure, instead break one target:

```bash
cd /home/joe/Development/agent-skills
python3 - <<'PY'
import pathlib
p = pathlib.Path("flake.nix"); s = p.read_text()
s = s.replace("            inherit skills;\n            extensionsDir = ./extensions;",
              "            skills = builtins.tail skills;\n            extensionsDir = ./extensions;", 1)
p.write_text(s)
PY
nix build .#checks.x86_64-linux.skills-all-four-targets --no-link 2>&1 | grep -m2 -E 'MISSING|COUNT'
git checkout flake.nix
nix build .#checks.x86_64-linux.skills-all-four-targets --no-link && echo COVERAGE_OK_AGAIN
```

Expected: `MISSING: pi is missing skill '…'` and `COUNT: pi ships 38 skills, expected 39`, then `COVERAGE_OK_AGAIN`.

- [ ] **Step 4: Full flake check**

Run:
```bash
cd /home/joe/Development/agent-skills && nix flake check -L 2>&1 | tail -20
```

Expected: passes. This is the first point at which every new check runs together with the pre-existing ones.

- [ ] **Step 5: Commit**

```bash
cd /home/joe/Development/agent-skills
git add -A
git commit -m "test(pi): assert every skill builds for all four targets

Design §14's coverage gate. Checks presence, non-emptiness, and count per
target, so a skill silently dropped by one target's mkSkill fails the build
rather than going missing at runtime."
```

---

### Task 9: The home-manager module — MCP fan-out, shared `autoMode`, and `homeManagerModules.pi`

`modules/agent-skills.nix` already fans one `mcpServers` declaration out to whichever agents are present, guarded by `mkIf (options.programs ? <agent>)`. pi joins that pattern, and `autoMode` — the new shared option from design §9 — is introduced here with the same fan-out shape.

pi's MCP arm differs from the other three in where it writes. Claude, Codex, and Antigravity each own an `mcpServers` option; pi has no MCP at all, and its adapter reads config files. `pi-mcp-adapter`'s documented precedence list includes `~/.agents/mcp.json` — the tool-agnostic sibling of the `~/.agents/skills` directory this module already manages. Writing there is both the least surprising location and the one that needs no pi-nix option.

**Files:**
- Modify: `/home/joe/Development/agent-skills/modules/agent-skills.nix`
- Modify: `/home/joe/Development/agent-skills/flake.nix` (`homeManagerModules.pi`)

**Interfaces:**
- Consumes: `mcpLib.mcpNativeFor "pi"` (Task 2); `pi-nix.homeManagerModules.coding-agent`; `programs.pi.coding-agent.settings` (`types.attrs`, jq-merged into `~/.pi/agent/settings.json` on launch)
- Produces:
  - `programs.agent-skills.autoMode :: submodule { allow, soft_deny, hard_deny, environment :: listOf str }`
  - `~/.agents/mcp.json` when pi is present
  - `homeManagerModules.pi`

- [ ] **Step 1: Write the failing eval tests**

Create `/home/joe/Development/agent-skills/modules/module-tests.nix`:

```nix
# Evaluates modules/agent-skills.nix against stub agent modules and asserts
# the fan-out lands where it should. Returns [ ] when everything passes.
{ pkgs, lib }:
let
  # A stand-in for each agent's home-manager module: declares only the
  # options modules/agent-skills.nix writes into.
  stubAgent =
    name: extra:
    { lib, ... }:
    {
      options.programs.${name} = {
        mcpServers = lib.mkOption {
          type = lib.types.attrs;
          default = { };
        };
      }
      // extra lib;
    };

  autoModeOption =
    lib: {
      autoMode = lib.mkOption {
        type = lib.types.attrs;
        default = { };
      };
    };

  evalWith =
    modules:
    (lib.evalModules {
      specialArgs = { inherit pkgs; };
      modules = [
        ../modules/agent-skills.nix
        {
          _module.args = { inherit pkgs; };
          programs.agent-skills = {
            enable = true;
            mcpServers.ctx = {
              command = "npx";
              args = [
                "-y"
                "ctx"
              ];
            };
            mcpServers.remote = {
              url = "https://x/mcp";
              bearerTokenEnvVar = "TOK";
            };
            autoMode = {
              allow = [ "read files" ];
              hard_deny = [ "exfiltrate secrets" ];
            };
          };
          home.file = lib.mkOption { type = lib.types.attrs; };
          xdg.configFile = lib.mkOption { type = lib.types.attrs; };
        }
      ]
      ++ modules;
    }).config;

  withPi = evalWith [
    (stubAgent "pi" (_: { }))
    (
      { lib, ... }:
      {
        options.programs.pi.coding-agent = {
          settings = lib.mkOption {
            type = lib.types.attrs;
            default = { };
          };
        }
        // autoModeOption lib;
      }
    )
  ];
  withoutPi = evalWith [ (stubAgent "claude-nix" autoModeOption) ];

  piMcp = builtins.fromJSON withPi.home.file.".agents/mcp.json".text;
in
lib.debug.runTests {
  testPiMcpFileWritten = {
    expr = piMcp.mcpServers.ctx.command;
    expected = "npx";
  };
  testPiMcpRemoteShape = {
    expr = {
      inherit (piMcp.mcpServers.remote) url auth bearerTokenEnv;
    };
    expected = {
      url = "https://x/mcp";
      auth = "bearer";
      bearerTokenEnv = "TOK";
    };
  };
  testNoPiNoMcpFile = {
    expr = withoutPi.home.file ? ".agents/mcp.json";
    expected = false;
  };
  testAutoModeFansOutToPi = {
    expr = withPi.programs.pi.coding-agent.autoMode.hard_deny;
    expected = [ "exfiltrate secrets" ];
  };
  testAutoModeFansOutToClaude = {
    expr = withoutPi.programs.claude-nix.autoMode.allow;
    expected = [ "read files" ];
  };
}
```

Wire it into `flake.nix` `checks`, after `skills-all-four-targets`:

```nix
          module-tests =
            let
              failures = import ./modules/module-tests.nix { inherit pkgs lib; };
            in
            if failures == [ ] then
              pkgs.runCommand "module-tests" { } "touch $out"
            else
              throw "module tests failed: ${builtins.toJSON failures}";
```

- [ ] **Step 2: Run to see it fail**

Run:
```bash
cd /home/joe/Development/agent-skills && nix build .#checks.x86_64-linux.module-tests --no-link 2>&1 | tail -10
```

Expected: fails — `programs.agent-skills.autoMode` is not a declared option, and no `.agents/mcp.json` is produced.

- [ ] **Step 3: Declare `autoMode`**

In `modules/agent-skills.nix`, add to `options.programs.agent-skills`, after `mcpServers`:

```nix
    autoMode = mkOption {
      default = { };
      type = types.submodule {
        options = {
          allow = mkOption {
            type = types.listOf types.str;
            default = [ ];
            description = "Natural-language rules describing what the agent may do without prompting.";
          };
          soft_deny = mkOption {
            type = types.listOf types.str;
            default = [ ];
            description = ''
              Destructive actions that explicit user intent clears. The
              classifier sees recent user turns alongside these rules.
            '';
          };
          hard_deny = mkOption {
            type = types.listOf types.str;
            default = [ ];
            description = "Security boundaries. User intent does not clear these.";
          };
          environment = mkOption {
            type = types.listOf types.str;
            default = [ ];
            description = "Facts about this machine the classifier should assume.";
          };
        };
      };
      example = lib.literalExpression ''
        {
          allow = [ "read and search files anywhere in the working tree" ];
          soft_deny = [ "delete files outside the working tree" ];
          hard_deny = [ "read or transmit credentials, tokens, or private keys" ];
          environment = [ "this is a NixOS machine; the system is rebuilt, not mutated" ];
        }
      '';
      description = ''
        Auto-mode rules declared once and fanned out to every installed
        agent that models them (claude-nix's native classifier, and both of
        pi's permission layers). Only agents whose home-manager module is
        imported *and* which declare an `autoMode` option receive config.
      '';
    };
```

- [ ] **Step 4: Add the pi arms to the fan-out**

In the `mkMerge` list, after the antigravity arm:

```nix
    # pi has no MCP of its own; pi-mcp-adapter reads a standard MCP config
    # file. ~/.agents/mcp.json is the tool-agnostic path in its precedence
    # list, and the sibling of the ~/.agents/skills directory this module
    # already owns — so no pi-nix option is needed for this.
    (mkIf (options.programs ? pi) {
      home.file.".agents/mcp.json".text = builtins.toJSON {
        mcpServers = mcpLib.mcpNativeFor "pi" cfg.mcpServers;
      };
    })

    # Auto-mode rules fan out the same way, but with a second guard: the
    # shared option can land before claude-nix and pi-nix grow their own
    # arms (design §9, rollout phases 3 and 6), so an agent that is present
    # but does not yet model autoMode is skipped rather than erroring.
    (mkIf (options.programs ? claude-nix && options.programs.claude-nix ? autoMode) {
      programs.claude-nix.autoMode = cfg.autoMode;
    })
    (mkIf (options.programs ? pi && options.programs.pi.coding-agent ? autoMode) {
      programs.pi.coding-agent.autoMode = cfg.autoMode;
    })
```

- [ ] **Step 5: Run to see it pass**

Run:
```bash
cd /home/joe/Development/agent-skills && nix fmt && nix build .#checks.x86_64-linux.module-tests --no-link && echo MODULE_TESTS_OK
```

Expected: `MODULE_TESTS_OK`.

- [ ] **Step 6: Add `homeManagerModules.pi`**

In `flake.nix`, after the `codex` entry in `homeManagerModules`:

```nix
        pi =
          {
            lib,
            pkgs,
            ...
          }:
          let
            build = import ./lib/default.nix {
              inherit pkgs lib;
              claudeLib = import "${claude-nix}/lib" { inherit pkgs; };
            };
            piPlugins = map (p: self.packages.${pkgs.system}."${p.name}-pi") (
              build.discoverPlugins ./plugins
            );
            piPackages = [ self.packages.${pkgs.system}.pi-plugin ] ++ piPlugins;
          in
          {
            imports = [ pi-nix.homeManagerModules.coding-agent ];
            # pi loads a package directory wholesale — its skills, prompt
            # templates, and extensions in one entry. Local absolute paths
            # are a first-class package source, so the store paths go in
            # directly with no npm or git round trip.
            #
            # Caveat, inherited from upstream (design §7): `settings` is
            # types.attrs and is jq-merged into ~/.pi/agent/settings.json on
            # every launch, so a Nix-declared key wins over an interactive
            # change to that key. Same trade-off as modules/ai/codex.nix.
            programs.pi.coding-agent.settings.packages = map toString piPackages;
          };
```

- [ ] **Step 7: Evaluate the module against a real home-manager**

Run:
```bash
cd /home/joe/Development/agent-skills
nix eval --impure --expr '
  let
    flake = builtins.getFlake (toString ./.);
    pkgs = import <nixpkgs> { system = builtins.currentSystem; };
    hm = builtins.getFlake "github:nix-community/home-manager";
    cfg = hm.lib.homeManagerConfiguration {
      inherit pkgs;
      modules = [
        flake.homeManagerModules.pi
        flake.homeManagerModules.agent-skills
        {
          home.username = "probe";
          home.homeDirectory = "/home/probe";
          home.stateVersion = "24.11";
          programs.pi.coding-agent.enable = true;
          programs.agent-skills.mcpServers.nixos.command = "mcp-nixos";
        }
      ];
    };
  in {
    packages = cfg.config.programs.pi.coding-agent.settings.packages;
    mcp = builtins.fromJSON cfg.config.home.file.".agents/mcp.json".text;
  }
' --json | jq .
```

Expected: `packages` is a list of `/nix/store/…-agent-skills-pi-complete` and `…-agent-skills-temporal-pi-complete` paths, and `mcp.mcpServers.nixos.command == "mcp-nixos"`.

- [ ] **Step 8: Full flake check**

Run:
```bash
cd /home/joe/Development/agent-skills && nix flake check -L 2>&1 | tail -25
```

Expected: passes.

- [ ] **Step 9: Commit**

```bash
cd /home/joe/Development/agent-skills
git add -A
git commit -m "feat(pi): pi arms for the MCP and auto-mode fan-outs, plus homeManagerModules.pi

pi has no MCP option to write into, so the normalized server set renders to
~/.agents/mcp.json — the tool-agnostic path in pi-mcp-adapter's precedence
list and the sibling of the ~/.agents/skills directory this module already
owns. autoMode is declared here and fanned out to claude-nix and pi with a
second guard, so the shared option can land before either agent grows its
own arm. homeManagerModules.pi hands pi the built packages via
settings.packages; local absolute paths are a first-class package source."
```

---

## Self-Review

**Spec coverage.** This plan implements design §11 in full. Each of its four rows is a task: all skills → `skills/` (Task 4), `disable-model-invocation` skills → `prompts/*.md` with `description` and `argument-hint` (Task 5), `hooks/session-start.sh` → `extensions/*.ts` on pi's session events (Task 6), and `programs.agent-skills.mcpServers` → pi-mcp-adapter settings (Tasks 2 and 9). The `targetLibs` map gains its fourth entry in Task 7, so `temporal` — the only cross-agent plugin — builds for pi like the other three. §14's two `agent-skills` requirements land in Tasks 3 (pi frontmatter lint) and 8 (four-target coverage). §9's `autoMode` fan-out lands in Task 9 following the existing `mkIf (options.programs ? …)` pattern, with an added second guard so it degrades cleanly until phases 3 and 6 give claude-nix and pi-nix their arms. §12 (prompt fragments) and §13 (`modules/ai/pi.nix`) are phases 5 and 6 and are out of scope.

**Assumption A3, resolved.** True, and the fallback is not needed. pi de-duplicates skills twice: silently by canonicalized real path, then noisily by name. Both were confirmed against pi v0.84.2 source and by running the built binary — one `<skill>` block in every configuration, including the real end-to-end shape with a package on a local absolute path in `settings.packages` alongside the live `~/.agents/skills`. The plan therefore keeps `~/.agents/skills` *and* ships skills in the pi package, and steers into the silent pass by linking rather than copying the `skill-<name>` derivations. `checks.pi-skill-realpath-identity` (Task 4) is the gate, and Task 4 Step 7 deliberately breaks the property to prove the gate fires — because a copy would still de-duplicate correctly and would fail only as 39 warning lines per session, which no other check would notice.

**Interfaces consumed from phase 2's `piLib`.** Exactly three, all named in design §7: `mkSkill` (the `claudeLib.mkSkill` ∪ `codexLib.mkSkill` signature, so `buildSkillForTarget` needs no pi branch), `mkPromptTemplate`, and `mkPlugin` (with `skills`, `prompts`, `extensions`, `themes`, emitting the `pi` manifest key). `piLib` has no `mkHook`, and Task 7's `mkCrossAgentPlugin` pi branch is written so `targetLib.mkHook` is never reached. If phase 2 lands different names, Task 1 Step 7 is the gate that catches it before anything is built on top.

**Placeholder scan.** No `TODO`, no `…`, no invented API. Every pi API used is quoted from the v0.84.2 source: `pi.on("session_start" | "session_compact" | "before_agent_start")`, `BeforeAgentStartEventResult.systemPrompt` (chained across extensions), `ctx.sessionManager.getSessionId()`, `readPiManifest`'s `pi.{extensions,skills,prompts,themes}` string arrays, `settings.packages` accepting local absolute paths via `isLocalPath`, `disable-model-invocation` filtering in `formatSkillsForPrompt`, and prompt-template `description`/`argument-hint`. The `pi-mcp-adapter` remote schema (`url`, `headers`, `auth: "bearer"`, `bearerTokenEnv`) and the `~/.agents/mcp.json` precedence entry come from the shipped npm package's README, not from memory. Type-only imports resolving from an arbitrary local path were verified by running pi, not assumed.

**Type consistency.** `piSkillWarnings :: { dirName, parsed } -> [str]` is introduced in Task 3 Step 3 with the signature its Task 3 Step 1 tests and its Task 3 Step 5 check both call. `isPiCommandSkill` and `mkPiPromptTemplateFor` are introduced in Task 5 Step 3 and consumed in Step 4. `buildPiExtensions :: str -> [skillRecord] -> path -> derivation` is introduced in Task 6 Step 4 and applied in Step 5 with that argument order. `buildPiPlugin` accumulates arguments monotonically — `skills` (Task 4), `prompts` derived internally (Task 5), `extensionsDir` (Task 6) — and no earlier call site breaks, because every addition is either internal or defaulted. The cross-agent plugin `extensions :: [ { name; source; } ]` field is declared in Task 7 Step 4's `plugin.nix` and consumed in Step 5's `mkCrossAgentPlugin` under those exact attribute names. `mcpNativeFor "pi"` output keys asserted in Task 2 Step 1 are the keys produced in Step 3 and the keys read in Task 9's `module-tests.nix`.

**Known gaps carried forward.** (1) `hooks/session-start.sh` and `plugins/temporal/temporal.py` are two different injectors; design §11's table conflates them into one row ("`hooks/session-start.sh` (temporal)"). This plan treats them separately — Task 6 ports the `using-agent-skills` injector, Task 7 ports temporal — because they have different owners, different lifetimes, and different pi events. (2) The pi package and the `~/.agents/skills` symlink both remain, by choice: dropping either would work, but keeping both means pi behaves identically whether or not the package is loaded, and the A3 gate makes it free. (3) `programs.pi.coding-agent.settings` is `types.attrs`, so two modules setting `settings.packages` silently last-wins; that is upstream's shape, documented in design §7 and repeated in the Task 9 comment rather than worked around. (4) Nothing here depends on phase 1's `agent-statusline` or phase 3's `pi-auto-mode`; Task 9 declares `autoMode` and fans it out, but the consuming options are those phases' work.
