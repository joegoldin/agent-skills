# pi-nix Fork Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use subagent-driven-development (recommended) or executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Turn the fork at `/home/joe/Development/pi-nix` into `joegoldin/pi-nix` — upstream `lukasl-dev/pi.nix` plus a `systemPrompt` option, purely-pinned ecosystem extensions, a `lib/` of pi package builders that `agent-skills` consumes as `piLib`, and the `statusline` / `notifications` option surfaces. Everything JavaScript runs on Bun: the fork's default pi package becomes upstream's `coding-agent-bun`, and pinned extensions resolve their dependencies through `bun2nix` instead of `buildNpmPackage`.

**Architecture:** Every addition is a *new file*. The three upstream module entrypoints (`coding-agent/lib.nix`, `coding-agent/module.nix`, `coding-agent/home-manager.nix`) each gain exactly one line adding `coding-agent/extra-options.nix` to their module list; `coding-agent/options.nix` is never touched. `extra-options.nix` reaches pi's command line through the option surface upstream already exposes — `extraArgs` (appended after upstream's own flags), `extensions`, `skills`, `promptTemplates`, `settings`, `environment` — all of which are list- or attr-typed and therefore merge across module definitions. The same module sets `package = lib.mkDefault coding-agent-bun`, which beats upstream's own `default = coding-agent` without editing the option that declares it. That gives a zero-diff options module and keeps `git rebase upstream/master` a fast-forward for everything but `flake.nix` and `update.nix`.

**Tech Stack:** Nix flakes (nixpkgs-unstable), `bun2nix` 2.1.0 (already an upstream flake input, its overlay already applied in `flake.nix`), `bun` 1.3.13, `autoPatchelfHook`, `nixfmt`, `nix-instantiate --eval` and `runCommand` assertions as the test vehicle, `writeShellApplication` for the update app.

This is phase 2 of the design in `docs/plans/2026-08-18-pi-nix-agent-stack-design.md` (§7 and §8). Phase 1 (`agent-statusline`) must be merged and pushed before Task 7.

## Global Constraints

- **The fork is strictly additive.** Do not reorder, reformat, or restructure any upstream file. `coding-agent/options.nix`, `coding-agent/package.nix`, `coding-agent/package-bun.nix`, `coding-agent/bun.nix`, `sync-upstream.nix`, `regenerate-models.nix`, `scan.nix`, `VERSION.json`, `ai/`, and the lockfiles must end this phase byte-identical to `upstream/master`. Task 9 has a check that proves it.
- Permitted upstream edits, and nothing else: **one** `imports`/`modules` line in each of `coding-agent/lib.nix`, `coding-agent/module.nix`, `coding-agent/home-manager.nix`; insertions (never rewrites) in `flake.nix`; three added lines in `update.nix`; a rewritten `README.md`.
- The upstream branch is `master`, not `main`. The `upstream` remote already exists and points at `git@github.com:lukasl-dev/pi.nix.git`.
- Nix formatting is `pkgs.nixfmt` (**not** `nixfmt-rfc-style`), driven by `nix fmt`. Run it before every commit.
- **No npm anywhere in this phase.** Extension dependencies resolve through `bun2nix`, the same mechanism upstream already uses for `coding-agent-bun`. Nothing here calls `buildNpmPackage`, `prefetch-npm-deps`, or `npm-lockfile-fix`, and `extensions.json` carries no `npmDepsHash`. The per-pin lockfile is `bun.lock` plus a generated `bun.nix`, not `package-lock.json`.
- Every derivation name and flake attribute derived from an npm package name uses the **slug**: strip a leading `@`, replace `/` with `-`. `@juicesharp/rpiv-todo` → `juicesharp-rpiv-todo`.
- Tarball hashes in `extensions.json` are npm's `dist.integrity` string used **verbatim** as the Nix SRI hash. Re-verified on 2026-08-18 by building a bare `fetchurl` for three pins, including `hash = "sha512-L4JDDn2JqRND9IWywJPr9XhkixO38yeL4CCCEAJoqG4++YpaKdywY32w71+rvD4UUOqCSRHwCyXd3CTEf1jw9w=="` for `pi-goal-0.52.1.tgz` and `hash = "sha512-tAE0IcfoHo9s2u5VX2uFXkFYX7YId3uEcsjI1lWfiJI4jU8SzQHj1xqimM49pHSmUo3EVN/1RUm/tx5BLj2VTg=="` for `pi-cache-optimizer-2.8.3.tgz`. All three succeed. Never re-derive them with `nix store prefetch-file`, which defaults to sha256. `bun2nix` writes the same string into every `fetchurl` it generates, so one convention covers both layers.
- No IFD. `extensions.json` is read with `builtins.fromJSON (builtins.readFile ...)`; nothing reads a *built* file at eval time.
- The system in every command below is `x86_64-linux`.

### Verified facts this plan is built on

Checked against the npm registry, `bun` 1.3.13, `bun2nix` 2.1.0, and `earendil-works/pi@v0.84.2` on 2026-08-18:

1. `--system-prompt <text>` exists (`packages/coding-agent/src/cli/args.ts:96`). `resolvePromptInput` in `src/core/resource-loader.ts:53-68` reads the argument as a **file** when `existsSync(input)`, else treats it as literal text. So passing a store path works exactly as upstream's `rules` → `--append-system-prompt <path>` already does.
2. `--extension <path>` accepts a **directory**. `discoverAndLoadExtensions` (`src/core/extensions/loader.ts:719-733`) stats the path; if it is a directory, `resolveExtensionEntries` reads `package.json`'s `pi.extensions` array and returns those entries. Handing pi the npm package root therefore loads whatever the package's own manifest declares — including `pi-background-tasks`, which declares **two** entrypoints.
3. `--skill`, `--prompt-template`, `--theme`, `--extension` are all repeatable; `--append-system-prompt` is repeatable, `--system-prompt` is not.
4. **Design assumption A4 is false for all ten pinned packages.** None ships a bundled `dist` that carries its own dependencies. Ten publish raw TypeScript. `@heyhuynhgiabuu/pi-pretty` publishes `tsc` output under `dist/`, but `dist/index.js` still `require`s `@shikijs/cli` and `@ff-labs/fff-node` out of `node_modules`, so it is compiled, not bundled. The `bundled = true` path survives for a reason A4 did not anticipate: `pi-cache-optimizer` has **zero runtime dependencies**, so `fetchurl` plus `tar` is the entire build. It is the only pin that takes that branch.
5. **`bun install` needs two `package.json` edits before it yields a usable tree.** Both were found by running it, and both are load-bearing:
   - `--omit=peer` drops `typebox`, which `pi-background-tasks` and `@narumitw/pi-goal` each declare as a **non-optional peer** and each `import` at runtime (`pi-goal/src/tools.ts:8`). Verified: `node_modules/typebox` is absent afterwards. Every other peer across the pin set is either `@earendil-works/*`, which pi supplies itself, or carries `optional: true`.
   - Leaving `devDependencies` in place makes `bun install --frozen-lockfile --omit=dev` fail outright on `pi-subagents` with `error: Failed to resolve root dev dependency '@earendil-works/pi-coding-agent'`, because `--lockfile-only --omit=dev` records the entry without resolving it.

   One `jq` program fixes both. Task 3 Step 3 defines it once as `normalisePackageJson`; `mkPiExtension` and the update app run the identical string, so a lockfile generated by one always satisfies `--frozen-lockfile` in the other.
6. **The npm approach this document previously described would have shipped `pi-background-tasks` broken.** This is worth stating plainly, because it is the strongest single argument for the Bun switch and it is easy to miss inside fact 5. `pi-background-tasks` is not a new pin; it was in the original set, and the original plan built it with `npm ci --omit=peer`. That install succeeds, produces a tidy `node_modules`, and passes every assertion the old test made — and the extension then throws at load, because `typebox` is declared as a plain peer and imported at runtime. Nothing catches it until someone starts pi and watches the extension fail to register. `@narumitw/pi-goal` has the identical shape. The shared `jq` normaliser from fact 5 is what prevents both: it hoists exactly the peers pi does not supply into `dependencies` before the install runs, and `tests/extensions-test.nix` asserts `node_modules/typebox` exists in both outputs so a regression fails the build instead of the agent.
7. **Two pins carry native code, and both build only because `autoPatchelfHook` is present.** `pi-mcp-adapter` pulls `@napi-rs/keyring`. `@heyhuynhgiabuu/pi-pretty` pulls `@ff-labs/fff-node` → `ffi-rs` → `@yuuang/ffi-rs-linux-x64-gnu`, whose `.node` has an empty `RPATH` and `DT_NEEDED` on `libgcc_s.so.1`, `librt.so.1`, `libpthread.so.0`, `libdl.so.2`, and `libc.so.6`. The hook is gated on `isLinux`; Darwin's prebuilt dylibs need no patching. `pi-pretty` catches a failed `import("@ff-labs/fff-node")` and degrades to the SDK file tools, so a miss here is quiet rather than fatal, which is exactly why the hook has to be there rather than relied on to fail loudly.
8. **`autoPatchelfHook` then fails the build on a library nothing will ever load.** bun installs *both* the gnu and the musl variant of a napi platform package, because `os` and `cpu` cannot express libc. On `x86_64-linux` that leaves `@yuuang/ffi-rs-linux-x64-musl/ffi-rs.linux-x64-musl.node` in the tree, and the hook stops with `error: auto-patchelf could not satisfy dependency libc.musl-x86_64.so.1`. The fix is `autoPatchelfIgnoreMissingDeps = [ "libc.musl-x86_64.so.1" "libc.musl-aarch64.so.1" ]`, and it is safe for a specific reason rather than by convention: `ffi-rs`'s loader picks its variant by detecting libc at load time, so on a glibc host the musl `.node` is never `dlopen`ed at all. Patching it would be patching a file nothing reads. The list names exactly two musl libc sonames and nothing else, so it cannot mask a real missing library on the gnu build — that one still fails loudly, which is what fact 7 relies on. Verified: the build succeeds, the gnu `.node` gets a real `RPATH`, and `require("@ff-labs/fff-node")` returns its exports under `node` straight from the store.
9. **`bun2nix` generates a cross-platform dep set only if the lockfile was.** `bun install --lockfile-only --os='*' --cpu='*'` records every platform variant of an optional native dependency; the later `bun install --frozen-lockfile` inside the sandbox installs just the host's. Without the two overrides, a lockfile generated on `x86_64-linux` omits the Darwin tarballs and `ext-heyhuynhgiabuu-pi-pretty` fails to build on `aarch64-darwin`.
10. None of the ten reads its configuration from pi's `settings.json`. `pi-mcp-adapter` reads `~/.config/mcp/mcp.json` and `~/.agents/mcp.json`; the `@juicesharp/*` packages read their own `rpiv-*` config; `@heyhuynhgiabuu/pi-pretty` and `pi-cache-optimizer` both write under `getAgentDir()` (`~/.pi/agent`). `passthru.settings` is therefore `{ }` for all ten today. The mechanism exists and is tested against a synthetic case, but the initial pin set does not exercise it.
11. Authorship, confirmed from registry metadata rather than the gallery or awesome-pi, which disagree: `pi-mcp-adapter` and `pi-subagents` are **nicobailon**, not `nicopreme`. The `@narumitw/*` scope publishes out of **narumiruna/pi-extensions**. `pi-cache-optimizer` is **jiangge**.
12. `pi-cache-optimizer` declares `peerDependencies: { "@earendil-works/pi-coding-agent": ">=0.82.0" }`. The fork pins pi at 0.84.2, which satisfies it. Because that pin is `bundled = true`, nothing runs `bun install` for it, so nothing tries to fetch the peer at all; its `import` resolves at runtime against the pi build that loads it.

## Pin set as verified on 2026-08-18

Ten third-party packages. Three candidates the design once listed are deliberately absent: `@plannotator/pi-extension` (design §8 drops plan mode entirely), `remote-pi` (phase 7's messaging plan owns inter-instance messaging, and reversed to `pi-intercom`), and `@narumitw/pi-caffeinate`, dropped on the evidence in this plan and explained below the dependency table.

| npm name | latest | repository | `pi.extensions` | `pi.skills` / `pi.prompts` | `bundled` |
| --- | --- | --- | --- | --- | --- |
| `pi-mcp-adapter` | 2.26.1 | github.com/nicobailon/pi-mcp-adapter | `["./index.ts"]` | `skills` | false |
| `pi-subagents` | 0.51.0 | github.com/nicobailon/pi-subagents | `["./index.ts"]` | `skills`, `prompts` | false |
| `pi-background-tasks` | 2.4.2 | github.com/ismailsaleekh/pi-background-tasks | `["./extensions/anthropic-attribution.ts", "./extensions/background-tasks.ts"]` | — | false |
| `@juicesharp/rpiv-ask-user-question` | 2.6.2 | github.com/juicesharp/rpiv-mono (`packages/rpiv-ask-user-question`) | `["./index.ts"]` | — | false |
| `@narumitw/pi-goal` | 0.52.1 | github.com/narumiruna/pi-extensions (`packages/pi-goal`) | `["./src/index.ts"]` | — | false |
| `@juicesharp/rpiv-todo` | 2.6.2 | github.com/juicesharp/rpiv-mono (`packages/rpiv-todo`) | `["./index.ts"]` | — | false |
| `@gotgenes/pi-permission-system` | 26.3.0 | github.com/gotgenes/pi-packages (`packages/pi-permission-system`) | `["./src/index.ts"]` | — | false |
| `@narumitw/pi-btw` | 0.54.1 | github.com/narumiruna/pi-extensions (`packages/pi-btw`) | `["./src/index.ts"]` | — | false |
| `pi-cache-optimizer` | 2.8.3 | github.com/jiangge/pi-cache-optimizer | `["./index.ts"]` | — | **true** |
| `@heyhuynhgiabuu/pi-pretty` | 0.6.21 | github.com/heyhuynhgiabuu/pi-pretty | `["./dist/index.js"]` | — | false |

Runtime dependency shape, measured by running the exact Bun invocation Task 3 builds with. `bun deps` is the number of `fetchurl` entries in the generated `bun.nix`; `node_modules` is the installed tree:

| slug | bun deps | node_modules | notes |
| --- | --- | --- | --- |
| `pi-mcp-adapter` | 130 | 83 MB | `@napi-rs/keyring` is native |
| `pi-subagents` | 4 | 9.8 MB | |
| `pi-background-tasks` | 3 | 16 MB | `typebox` hoisted from peers |
| `juicesharp-rpiv-ask-user-question` | 2 | 6.2 MB | |
| `narumitw-pi-goal` | 138 | 17 MB | `typebox` hoisted from peers |
| `juicesharp-rpiv-todo` | 2 | 6.2 MB | |
| `gotgenes-pi-permission-system` | 5 | 31 MB | |
| `narumitw-pi-btw` | 137 | 11 MB | |
| `pi-cache-optimizer` | 0 | none | `bundled = true` |
| `heyhuynhgiabuu-pi-pretty` | 78 | 66 MB | `shiki` + native `ffi-rs` |

### `pi-goal` and `pi-btw` share one dependency tail, not two

Both come from `narumiruna/pi-extensions` and both depend on `@narumitw/pi-tui-kit`, which is where their ~137-package tail comes from. Measured rather than assumed: the two generated `bun.nix` files hold **137 entries in common at identical `name@version`, with identical `url` and `hash` on every one of them**. The only entry either has that the other lacks is `typebox@1.3.15`, which `pi-goal` carries because of the peer hoist. Both resolve `@narumitw/pi-tui-kit@0.56.0`.

Two consequences, and they differ:

- **The fetch and the store cost for those 137 tarballs is paid once.** `bun2nix` emits a bare `fetchurl { url; hash; }` per dependency, which is a fixed-output derivation, so identical coordinates give one store path no matter how many pins reference it. Verified by building the `pi-tui-kit` tarball twice from two separately-written expressions and getting a single path back. Adding the second `@narumitw` pin costs one extra tarball, not 137.
- **The *unpacked* `node_modules` is duplicated.** `ext-narumitw-pi-goal` and `ext-narumitw-pi-btw` are separate derivations that each `cp -R` their own tree, so the 17 MB and 11 MB are additive in the closure even though the tarballs behind them are not. That is inherent to giving each extension its own package root, which is what `--extension <dir>` requires.

So the marginal cost of keeping both is one tarball plus 11 MB, not a second full tail.

### Why `@narumitw/pi-caffeinate` is not in the set

It was pinned in an earlier draft and dropped on the evidence gathered here. It reached the same ~141-package tail through the same `pi-tui-kit`, and on top of that:

- it calls `sessionBus()` from `dbus-native` and sends `Inhibit`/`UnInhibit` to `org.freedesktop.ScreenSaver`, which needs the session bus socket bound into the jail and talk permission on that name;
- on Linux it prefers spawning `systemd-inhibit` (`src/inhibitors.ts:28-46`) and only falls back to D-Bus, so it also needs `add-pkg-deps` for a binary the jail does not otherwise carry;
- with neither, it is **silently inert** — no error, no notification, just a machine that sleeps mid-run.

`systemd-inhibit` already does the whole job in one command on NixOS. Paying a dependency tail and a new jail permission to reach the same syscall, with silence as the failure mode, is a bad trade. Design §9's note that `pi-notify` needs talk permission on `org.freedesktop.Notifications` still stands and is still phase 3's; this pin simply is not part of it.

Config paths for the pins that remain are fine as they stand: `@heyhuynhgiabuu/pi-pretty` and `pi-cache-optimizer` both read and write under `getAgentDir()`, which upstream's jail already binds read-write.

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

Expected: a `does not provide attribute` error naming `checks.x86_64-linux.smoke` — the `checks` output does not exist yet.

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

~~~~markdown
# Rebasing on upstream

This repo is a fork of [lukasl-dev/pi.nix](https://github.com/lukasl-dev/pi.nix),
kept deliberately additive so upstream can be replayed underneath our changes.

## What is ours

Everything below is new; upstream has no file at these paths, so a rebase never
touches them:

- `lib/` — `mkPiSkill`, `mkPiPromptTemplate`, `mkPiPlugin`
- `packages/extensions/` — `mkPiExtension`, `normalise-package-json.nix`, and
  one `bun.lock` plus one generated `bun.nix` per unbundled pin
- `extensions.json` — the extension pin file
- `coding-agent/extra-options.nix` — `systemPrompt`, `extensionPackages`,
  `statusline`, `notifications`
- `tests/`, `update-extensions.nix`, `docs/REBASING.md`, `garnix.yaml`

## What we edit upstream

Only these, and only as insertions:

| File | Our change |
| --- | --- |
| `flake.nix` | `agent-statusline` input, `checks` output, `packages.ext-*`, `lib.builders`, `apps.update-extensions`, the `bun2nix` overlay on the `apps` block's nixpkgs, description |
| `update.nix` | takes `updateExtensions`, runs `pi-update-extensions` last |
| `coding-agent/lib.nix` | one line adding `extra-options.nix` to `modules` |
| `coding-agent/module.nix` | one line adding `extra-options.nix` to `imports` |
| `coding-agent/home-manager.nix` | one line adding `extra-options.nix` to `imports` |
| `README.md` | rewritten for the fork |

`coding-agent/options.nix` is **never** modified. Our options module reaches
pi's command line through `extraArgs`, `extensions`, `skills`,
`promptTemplates`, `settings`, and `environment`, all of which merge across
module definitions, and it overrides the `package` default with `lib.mkDefault`
rather than editing the declaration.

`packages.default` stays upstream's `coding-agent`, because changing it would
be a rewrite rather than an insertion. The *module* default is the Bun build;
`nix run github:joegoldin/pi-nix` still gives you the npm one. Use
`nix run .#coding-agent-bun` to run the same binary the modules install.

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
~~~~

- [ ] **Step 7: Rewrite `README.md`**

~~~~markdown
# pi-nix

A Nix flake for [pi](https://github.com/earendil-works/pi), the terminal coding
agent — a fork of [lukasl-dev/pi.nix](https://github.com/lukasl-dev/pi.nix)
extended for the agent stack described in `agent-skills/docs/plans/2026-08-18-pi-nix-agent-stack-design.md`.

Upstream provides the packages, the NixOS/Home Manager modules, the jail.nix
sandbox wiring, and `lib.mkCodingAgent`. This fork adds, all additively:

| Addition | What it is |
| --- | --- |
| `systemPrompt` | `--system-prompt`, which *replaces* pi's default prompt. Upstream's `rules` only appends. |
| Bun by default | `programs.pi.coding-agent.package` defaults to upstream's `coding-agent-bun`. Set it explicitly to get the npm build back. |
| `packages.ext-*` | Purely pinned ecosystem extensions, built from npm tarballs with `bun2nix`. |
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

That runs upstream's `packages.default`, which is the npm build. The Home
Manager and NixOS modules default to the Bun build instead; `nix run
github:joegoldin/pi-nix#coding-agent-bun` runs the same binary they install.

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
      ext-juicesharp-rpiv-ask-user-question
      ext-narumitw-pi-goal
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
~~~~

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
  grep -qxF 'name: demo-skill' "$md"
  grep -qxF 'description: A demo skill used by the pi-nix builder tests.' "$md"
  # Entries containing spaces must be comma-joined; a space join would shear
  # "Bash(git log:*)" mid-entry.
  grep -qxF 'allowed-tools: read, Bash(git log:*)' "$md"
  grep -qxF 'disable-model-invocation: true' "$md"
  grep -qxF 'Body of the demo skill.' "$md"

  # An empty allowed-tools line would restrict the skill to no tools, so the
  # key must be absent rather than empty.
  bare=${bareSkill}/skills/bare-skill/SKILL.md
  test -f "$bare"
  ! grep -q 'allowed-tools' "$bare"

  # ── mkPiPromptTemplate ───────────────────────────────────────────────────
  # The filename is the slash command, so it must be exactly <name>.md.
  p=${prompt}/prompts/review.md
  test -f "$p"
  grep -qxF 'description: Review staged git changes' "$p"
  grep -qxF 'argument-hint: "[file-pattern]"' "$p"
  grep -qxF 'Review $1 and summarise $@.' "$p"

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

Purely pinned ecosystem extensions, built with Bun. This is where design assumption A4 gets settled: ten of the eleven pins need a real dependency install, and the one that does not needs it for a reason A4 never considered.

**Files:**
- Create: `packages/extensions/mk-pi-extension.nix`
- Create: `packages/extensions/normalise-package-json.nix`
- Create: `packages/extensions/default.nix`
- Create: `extensions.json`
- Create: `packages/extensions/<slug>/bun.lock` and `packages/extensions/<slug>/bun.nix` × 9 (generated in Step 6; `pi-cache-optimizer` gets neither)
- Create: `tests/extensions-test.nix`
- Modify: `tests/default.nix`
- Modify: `flake.nix` (add `ext-*` to `packages`, thread `bunPkgs` in)

**Interfaces:**
- Consumes: the `checks` harness from Task 1
- Produces:
  - `mkPiExtension { pname, version, url, hash, bundled ? false, bunLock ? null, bunNix ? null, entrypoints ? [ ], skills ? [ ], prompts ? [ ], settings ? { }, promptFragment ? null, extraBuildInputs ? [ ] }` → derivation
  - **The passthru contract**, identical for `mkPiExtension` and `mkPiPlugin`:
    - `passthru.piEntrypoint` — `list of str`, absolute paths handed verbatim to repeated `--extension` flags. Normally a one-element list holding the package root, which makes pi read the package's own `pi` manifest.
    - `passthru.piSkills` — `list of str`, absolute paths for `--skill`
    - `passthru.piPrompts` — `list of str`, absolute paths for `--prompt-template`
    - `passthru.settings` — `attrs`, merged into `~/.pi/agent/settings.json`
    - `passthru.promptFragment` — `null` or `str`, appended via `--append-system-prompt`
  - `packages.<system>.ext-<slug>` for each of the ten pins
  - `extensions.json` — attrset keyed by npm name, each `{ version, url, hash, bundled, entrypoints, skills, prompts }`. There is no aggregate dependency hash: `bun2nix` records one `fetchurl` per dependency in the per-pin `bun.nix`, each with npm's `dist.integrity` verbatim, so there is nothing to keep in sync by hand and nothing to go stale independently of the lockfile.

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
  pins = builtins.fromJSON (builtins.readFile ../extensions.json);

  mkPiExtension = pkgs.callPackage ../packages/extensions/mk-pi-extension.nix { };

  # A synthetic bundled pin. Never built — only its attributes are read — so
  # the fake hash costs nothing and the bundled branch stays under test on the
  # settings/promptFragment axes the real bundled pin does not exercise.
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
    "ext-heyhuynhgiabuu-pi-pretty"
    "ext-juicesharp-rpiv-ask-user-question"
    "ext-juicesharp-rpiv-todo"
    "ext-narumitw-pi-btw"
    "ext-narumitw-pi-goal"
    "ext-pi-background-tasks"
    "ext-pi-cache-optimizer"
    "ext-pi-mcp-adapter"
    "ext-pi-subagents"
  ];

  # A pin is complete when its tarball coordinates are real. There is no
  # dependency hash to check: bun2nix keeps those in the per-pin bun.nix, and
  # Step 6's guard proves every unbundled pin has one on disk.
  pinComplete =
    _name: pin:
    pin.version != ""
    && lib.hasPrefix "https://registry.npmjs.org/" pin.url
    && lib.hasPrefix "sha512-" pin.hash;

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
    # Exactly one pin takes the bundled branch, and it is the one with no
    # runtime dependencies. If a future bump gives pi-cache-optimizer a
    # dependency, this fires before anything ships a broken node_modules.
    assert pins."pi-cache-optimizer".bundled;
    assert lib.all (n: !pins.${n}.bundled) (lib.filter (n: n != "pi-cache-optimizer") (builtins.attrNames pins));
    assert lib.all (n: pinComplete n pins.${n}) (builtins.attrNames pins);
    true;
in
assert evalAssertions;
pkgs.runCommand "pi-nix-extensions-tests" { nativeBuildInputs = [ pkgs.jq ]; } ''
  set -euo pipefail

  check() {
    local root="$1"
    local wantDeps="$2"
    test -f "$root/package.json"
    if [ "$wantDeps" = deps ]; then
      # Every unbundled pin publishes source against dependencies it does not
      # vendor, so node_modules must have been materialised at build time.
      test -d "$root/node_modules"
    fi
    # Each entry the pi manifest declares must actually exist, or pi silently
    # resolves zero entrypoints and the extension never loads.
    local n
    n=$(jq -r '[.pi.extensions[]?] | length' "$root/package.json")
    test "$n" -gt 0
    jq -r '.pi.extensions[]' "$root/package.json" | while read -r e; do
      test -e "$root/$e"
    done
  }

  check ${exts.ext-pi-mcp-adapter} deps
  check ${exts.ext-pi-subagents} deps
  check ${exts.ext-pi-background-tasks} deps
  check ${exts.ext-juicesharp-rpiv-ask-user-question} deps
  check ${exts.ext-narumitw-pi-goal} deps
  check ${exts.ext-juicesharp-rpiv-todo} deps
  check ${exts.ext-gotgenes-pi-permission-system} deps
  check ${exts.ext-narumitw-pi-btw} deps
  check ${exts.ext-heyhuynhgiabuu-pi-pretty} deps
  check ${exts.ext-pi-cache-optimizer} nodeps

  # Skills and prompts advertised through the passthru must be real directories.
  test -d ${exts.ext-pi-mcp-adapter}/skills
  test -d ${exts.ext-pi-subagents}/skills
  test -d ${exts.ext-pi-subagents}/prompts

  # The two peers that must survive the --omit=peer install. Absent these, both
  # extensions load and then throw on their first `import { Type } from
  # "typebox"`, which is a failure that only shows up at runtime.
  test -d ${exts.ext-pi-background-tasks}/node_modules/typebox
  test -d ${exts.ext-narumitw-pi-goal}/node_modules/typebox

  # pi-cache-optimizer has no dependencies at all; a node_modules here would
  # mean the bundled branch quietly grew a bun install.
  ! test -e ${exts.ext-pi-cache-optimizer}/node_modules

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

- [ ] **Step 3: Write `packages/extensions/normalise-package-json.nix`**

The two `package.json` edits from verified fact 5, defined once. `mk-pi-extension.nix` runs this in `postPatch` and `update-extensions.nix` runs the same string before generating the lockfile. Sharing it is not tidiness: `bun install --frozen-lockfile` compares the lockfile against the manifest, so any divergence between generator and builder fails the build.

```nix
{ jq }:
# Emitted into a shell script; both consumers `source`-substitute it verbatim.
#
# Two edits, both required, both discovered by running bun rather than reading
# docs:
#
#   1. Hoist every peer dependency that is neither `@earendil-works/*` nor
#      marked optional into `dependencies`. pi supplies its own packages to
#      extensions at runtime, so those peers must stay omitted; everything else
#      is a real runtime import. pi-background-tasks and @narumitw/pi-goal both
#      declare `typebox` as a plain peer and both `import` it, so under a bare
#      `--omit=peer` they install cleanly and throw on load.
#
#   2. Delete devDependencies outright. `bun install --lockfile-only --omit=dev`
#      writes the root dev entries into bun.lock without resolving them, and the
#      later `--frozen-lockfile` run then dies with
#      `Failed to resolve root dev dependency '@earendil-works/pi-coding-agent'`
#      (reproduced on pi-subagents).
#
# peerDependencies and peerDependenciesMeta are dropped after the hoist so bun
# does not re-resolve the @earendil-works tree transitively. That alone takes
# @juicesharp/rpiv-todo from 137 fetchurl entries to 2.
''
  ${jq}/bin/jq '
    (.peerDependenciesMeta // {}) as $meta
    | .dependencies = ((.dependencies // {}) + ((.peerDependencies // {})
        | with_entries(select(
            (.key | startswith("@earendil-works/") | not)
            and (($meta[.key].optional // false) | not)))))
    | del(.devDependencies, .peerDependencies, .peerDependenciesMeta)
  ' package.json > package.json.normalised
  mv package.json.normalised package.json
''
```

- [ ] **Step 4: Write `packages/extensions/mk-pi-extension.nix`**

```nix
{
  lib,
  stdenv,
  fetchurl,
  runCommand,
  callPackage,
  bun,
  bun2nix,
  autoPatchelfHook,
}:
# One pinned pi extension from an npm tarball.
#
# `bundled` decides how node_modules is obtained:
#
#   true  — the tarball already carries everything it needs, or needs nothing.
#           fetchurl + untar, no bun at all.
#   false — the tarball ships source against unvendored dependencies, so
#           bun2nix's hook materialises node_modules from a vendored bun.lock
#           and the bun.nix generated from it. `nix run .#update-extensions`
#           regenerates both.
#
# Design assumption A4 predicted `bundled = true` would be the common case
# because packages would ship a self-contained dist. That is false for all
# eleven pins. The branch survives for an unrelated reason: pi-cache-optimizer
# has zero runtime dependencies, so there is nothing for bun to install.
{
  pname,
  version,
  # npm dist.tarball
  url,
  # npm dist.integrity, usable verbatim as a Nix SRI hash
  hash,
  bundled ? false,
  # Vendored bun.lock and the bun2nix-generated dep set built from it.
  bunLock ? null,
  bunNix ? null,
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
  # Extra libraries autoPatchelfHook must be able to find. Empty for every pin
  # in the initial set: the two with native code (@napi-rs/keyring under
  # pi-mcp-adapter, ffi-rs under pi-pretty) need only libc, libgcc_s, and
  # libstdc++, which stdenv.cc.cc.lib already supplies.
  extraBuildInputs ? [ ],
  meta ? { },
}:
let
  slug = lib.replaceStrings [ "@" "/" ] [ "" "-" ] pname;

  normalisePackageJson = callPackage ./normalise-package-json.nix { };

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
      stdenv.mkDerivation {
        pname = "pi-ext-${slug}";
        inherit version src;

        nativeBuildInputs = [
          bun2nix.hook
          bun
        ]
        # Prebuilt .node files arrive with an empty RPATH and DT_NEEDED on
        # libgcc_s/libstdc++/libc, none of which resolve on NixOS. Verified
        # against @yuuang/ffi-rs-linux-x64-gnu, which pi-pretty pulls in
        # transitively. macOS dylibs need no equivalent.
        ++ lib.optionals stdenv.hostPlatform.isLinux [ autoPatchelfHook ];

        buildInputs = lib.optionals stdenv.hostPlatform.isLinux (
          [ stdenv.cc.cc.lib ] ++ extraBuildInputs
        );

        # bun installs both the gnu and the musl build of a napi platform
        # package, because `os` and `cpu` cannot express libc. The musl .node
        # is never dlopened on a glibc host — ffi-rs selects its variant by
        # detecting libc at load time — but autoPatchelfHook still walks it and
        # halts the build on the libc it cannot find. Reproduced on
        # @yuuang/ffi-rs-linux-x64-musl under pi-pretty.
        autoPatchelfIgnoreMissingDeps = [
          "libc.musl-x86_64.so.1"
          "libc.musl-aarch64.so.1"
        ];

        bunDeps = bun2nix.fetchBunDeps { bunNix = import bunNix; };

        # Matches the flags the update app generated the lockfile with. A
        # divergence here makes --frozen-lockfile reject the vendored lock.
        bunInstallFlags = [
          "--linker=hoisted"
          "--frozen-lockfile"
          "--omit=dev"
          "--omit=peer"
        ];

        # These packages' install scripts are build tooling (napi, node-gyp) we
        # never want to run; the prebuilt platform packages are already in the
        # dep set.
        dontRunLifecycleScripts = true;

        # The normalisation must happen before bun2nix's hook runs its install,
        # and must be byte-identical to what the update app did.
        postPatch = ''
          ${normalisePackageJson}
          cp ${bunLock} bun.lock
        '';

        # These are source packages, not build products: pi loads the .ts files
        # through jiti at runtime, and pi-pretty ships tsc output already.
        dontBuild = true;
        # Stripping a prebuilt .node gains nothing and risks breaking it.
        dontStrip = true;

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

- [ ] **Step 5: Write `packages/extensions/default.nix`**

`bunPkgs` is nixpkgs with `bun2nix.overlays.default` applied. `flake.nix` already builds exactly that for `coding-agent-bun`; Step 8 passes the same value here instead of constructing a second one.

```nix
{
  pkgs,
  # nixpkgs with bun2nix.overlays.default applied. Defaults to pkgs so a caller
  # that already applied the overlay can pass one argument.
  bunPkgs ? pkgs,
  lib ? pkgs.lib,
}:
# Every pin in extensions.json becomes packages.ext-<slug>. The pin file is
# read with fromJSON/readFile, never through IFD, so `nix flake show` stays
# evaluable offline.
let
  pins = builtins.fromJSON (builtins.readFile ../../extensions.json);

  mkPiExtension = bunPkgs.callPackage ./mk-pi-extension.nix { };

  slugOf = name: lib.replaceStrings [ "@" "/" ] [ "" "-" ] name;

  # Nix-side configuration per extension, merged into settings.json when the
  # extension is enabled. Every entry is `{ }` today: verified on 2026-08-18,
  # none of the eleven pins reads pi's settings.json. pi-mcp-adapter reads
  # ~/.config/mcp/mcp.json and ~/.agents/mcp.json; the @juicesharp packages
  # read their own rpiv-* config; pi-pretty and pi-cache-optimizer both write
  # under getAgentDir(). The mechanism is here for
  # pins that do, and is exercised by the synthetic case in
  # tests/extensions-test.nix.
  settingsFor = {
    pi-mcp-adapter = { };
    pi-subagents = { };
    pi-background-tasks = { };
    juicesharp-rpiv-ask-user-question = { };
    narumitw-pi-goal = { };
    juicesharp-rpiv-todo = { };
    gotgenes-pi-permission-system = { };
    narumitw-pi-btw = { };
    pi-cache-optimizer = { };
    heyhuynhgiabuu-pi-pretty = { };
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
      bunLock = if pin.bundled then null else ./. + "/${slug}/bun.lock";
      bunNix = if pin.bundled then null else ./. + "/${slug}/bun.nix";
      settings = settingsFor.${slug} or { };
      promptFragment = null;
    };
in
lib.mapAttrs' (name: pin: lib.nameValuePair "ext-${slugOf name}" (mkOne name pin)) pins
```

- [ ] **Step 6: Write `extensions.json` and generate the lockfiles**

Every value below is read off the npm registry on 2026-08-18. `bundled` and `entrypoints` are the two human-owned fields; the update app never rewrites either.

```json
{
  "pi-mcp-adapter": {
    "version": "2.26.1",
    "url": "https://registry.npmjs.org/pi-mcp-adapter/-/pi-mcp-adapter-2.26.1.tgz",
    "hash": "sha512-6/KDXIEPXTVM77274jAloxAo9AQSEy5EJ/7afIlUK2T8HOfeVapTJvwImvyChiIH+0gGShbFgnBK2BXFrjbj2w==",
    "bundled": false,
    "entrypoints": [],
    "skills": ["skills"],
    "prompts": []
  },
  "pi-subagents": {
    "version": "0.51.0",
    "url": "https://registry.npmjs.org/pi-subagents/-/pi-subagents-0.51.0.tgz",
    "hash": "sha512-qC9ndnMbuHefE6mGS2k69jP4htgbiQQG5jGnwCuKyK/pMcz5RFZ5nChrJ6JxPOBlpmVxsQzW27MCh0HDJCXxsA==",
    "bundled": false,
    "entrypoints": [],
    "skills": ["skills"],
    "prompts": ["prompts"]
  },
  "pi-background-tasks": {
    "version": "2.4.2",
    "url": "https://registry.npmjs.org/pi-background-tasks/-/pi-background-tasks-2.4.2.tgz",
    "hash": "sha512-KDH2yv5yKnc2slUNMSsysVZleriuv8tbhe5L+AeplVAfijQsECN5YAWOz5TDbStCXLdJC15GaUQ1P87BXGk5Hg==",
    "bundled": false,
    "entrypoints": [],
    "skills": [],
    "prompts": []
  },
  "@juicesharp/rpiv-ask-user-question": {
    "version": "2.6.2",
    "url": "https://registry.npmjs.org/@juicesharp/rpiv-ask-user-question/-/rpiv-ask-user-question-2.6.2.tgz",
    "hash": "sha512-DS9yZHcaPr+/nf0x2CCfiXBod/1aWjGyakGM3lZAObuGDhYI0nFRE5gxTcCOfQug6JtJXjt1GlzyX8Pljefdzg==",
    "bundled": false,
    "entrypoints": [],
    "skills": [],
    "prompts": []
  },
  "@narumitw/pi-goal": {
    "version": "0.52.1",
    "url": "https://registry.npmjs.org/@narumitw/pi-goal/-/pi-goal-0.52.1.tgz",
    "hash": "sha512-L4JDDn2JqRND9IWywJPr9XhkixO38yeL4CCCEAJoqG4++YpaKdywY32w71+rvD4UUOqCSRHwCyXd3CTEf1jw9w==",
    "bundled": false,
    "entrypoints": [],
    "skills": [],
    "prompts": []
  },
  "@juicesharp/rpiv-todo": {
    "version": "2.6.2",
    "url": "https://registry.npmjs.org/@juicesharp/rpiv-todo/-/rpiv-todo-2.6.2.tgz",
    "hash": "sha512-Lt2HzNaKWgOl7/nEJrxtRsKoIQJTZd32BeckDxJ0JGvoUmwYvqOicSpXbgKVZwyGqGBw90WBKYWkEggo9U/Q4Q==",
    "bundled": false,
    "entrypoints": [],
    "skills": [],
    "prompts": []
  },
  "@gotgenes/pi-permission-system": {
    "version": "26.3.0",
    "url": "https://registry.npmjs.org/@gotgenes/pi-permission-system/-/pi-permission-system-26.3.0.tgz",
    "hash": "sha512-FqRVq+YvHgBBJShQK1wdlUik4QZMdTDv5a9drmxZK8pXpCy0XjLX0nXLVNntQL+KhdTQ56JlsunKqjgU5YDNbQ==",
    "bundled": false,
    "entrypoints": [],
    "skills": [],
    "prompts": []
  },
  "@narumitw/pi-btw": {
    "version": "0.54.1",
    "url": "https://registry.npmjs.org/@narumitw/pi-btw/-/pi-btw-0.54.1.tgz",
    "hash": "sha512-/zLu1ZJzDynMZLTObhuWb4/W/qaNoqvI1XDnu3ADVFhXANZvNTZXbdQDlYIvpRq2PzqEDLQZpV+fQOcfJslGXg==",
    "bundled": false,
    "entrypoints": [],
    "skills": [],
    "prompts": []
  },
  "pi-cache-optimizer": {
    "version": "2.8.3",
    "url": "https://registry.npmjs.org/pi-cache-optimizer/-/pi-cache-optimizer-2.8.3.tgz",
    "hash": "sha512-tAE0IcfoHo9s2u5VX2uFXkFYX7YId3uEcsjI1lWfiJI4jU8SzQHj1xqimM49pHSmUo3EVN/1RUm/tx5BLj2VTg==",
    "bundled": true,
    "entrypoints": [],
    "skills": [],
    "prompts": []
  },
  "@heyhuynhgiabuu/pi-pretty": {
    "version": "0.6.21",
    "url": "https://registry.npmjs.org/@heyhuynhgiabuu/pi-pretty/-/pi-pretty-0.6.21.tgz",
    "hash": "sha512-Cyk+YvfOkahMQBB3+UxJCzHB6e37jJZJGiTL0p2KL4ov3Sfn3HRcZmeKHi8vDxZGPJKIKJdy21l/nPicCm5j1w==",
    "bundled": false,
    "entrypoints": [],
    "skills": [],
    "prompts": []
  }
}
```

Now generate the per-pin `bun.lock` and `bun.nix`. This is the same procedure Task 4 turns into `nix run .#update-extensions`; run it here so Task 3 can be verified before Task 4 exists.

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
  bundled=$(jq -r --arg n "$name" '.[$n].bundled' extensions.json)
  [[ "$bundled" == "true" ]] && { echo "$name bundled, skipping"; continue; }

  slug=$(printf '%s' "$name" | sed -e 's|^@||' -e 's|/|-|g')
  url=$(jq -r --arg n "$name" '.[$n].url' extensions.json)
  work="$tmp/$slug"
  mkdir -p "$work"
  curl -fsSL "$url" | tar -xzf - -C "$work" --strip-components=1
  (
    cd "$work"
    jq '(.peerDependenciesMeta // {}) as $meta
        | .dependencies = ((.dependencies // {}) + ((.peerDependencies // {})
            | with_entries(select(
                (.key | startswith("@earendil-works/") | not)
                and (($meta[.key].optional // false) | not)))))
        | del(.devDependencies, .peerDependencies, .peerDependenciesMeta)' \
      package.json > package.json.normalised
    mv package.json.normalised package.json

    # --os/--cpu force every platform variant of an optional native dependency
    # into the lockfile, so the generated bun.nix is buildable on Darwin too.
    bun install --lockfile-only --omit=dev --omit=peer --os='*' --cpu='*' >/dev/null 2>&1
  )
  mkdir -p "packages/extensions/$slug"
  cp "$work/bun.lock" "packages/extensions/$slug/bun.lock"
  bun2nix -l "$work/bun.lock" -o "packages/extensions/$slug/bun.nix"
  echo "$slug $(grep -c 'fetchurl {' "packages/extensions/$slug/bun.nix") deps"
done
SCRIPT
chmod +x /tmp/pin-extensions.sh
nix shell nixpkgs#bun nixpkgs#jq nixpkgs#curl nixpkgs#gnutar nixpkgs#gzip nixpkgs#gnused \
  'github:nix-community/bun2nix?ref=2.1.0' -c /tmp/pin-extensions.sh
```

Expected output. These counts were produced and verified while writing this plan, so a divergence means an upstream package was republished and the pin needs re-verifying, not that the command is wrong:

```
@gotgenes/pi-permission-system gotgenes-pi-permission-system 5 deps
@heyhuynhgiabuu/pi-pretty heyhuynhgiabuu-pi-pretty 78 deps
@juicesharp/rpiv-ask-user-question juicesharp-rpiv-ask-user-question 2 deps
@juicesharp/rpiv-todo juicesharp-rpiv-todo 2 deps
@narumitw/pi-btw narumitw-pi-btw 137 deps
@narumitw/pi-goal narumitw-pi-goal 138 deps
pi-background-tasks pi-background-tasks 3 deps
pi-cache-optimizer bundled, skipping
pi-mcp-adapter pi-mcp-adapter 130 deps
pi-subagents pi-subagents 4 deps
```

Then confirm every unbundled pin got both files, and no bundled pin got either:

```bash
cd /home/joe/Development/pi-nix && jq -r 'to_entries[] | "\(.value.bundled) \(.key)"' extensions.json | \
  sed -e 's|@||' -e 's|/|-|2' | while read -r bundled slug; do
    for f in bun.lock bun.nix; do
      if [ "$bundled" = false ] && [ ! -f "packages/extensions/$slug/$f" ]; then echo "MISSING $slug/$f"; fi
      if [ "$bundled" = true ] && [ -f "packages/extensions/$slug/$f" ]; then echo "UNEXPECTED $slug/$f"; fi
    done
  done
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
        // import ./packages/extensions { inherit pkgs bunPkgs; }
      );
```

`rec { ... } // extras` keeps every existing attribute and its internal recursion intact while adding the `ext-*` set alongside. Nothing inside the `rec` block is touched, and `bunPkgs` is the binding upstream already computes a few lines above for `coding-agent-bun`, so no second overlay application appears anywhere.

- [ ] **Step 8: Run the test to verify it passes**

Run:
```bash
cd /home/joe/Development/pi-nix && nix build .#checks.x86_64-linux.extensions -L && echo EXTENSIONS-OK
```

Expected: `EXTENSIONS-OK`. This builds all ten extensions. The first run fetches every tarball in every `bun.nix` and takes several minutes; `ext-pi-mcp-adapter` (83 MB of node_modules) and `ext-heyhuynhgiabuu-pi-pretty` (66 MB) dominate.

Two failure modes, both hit while writing this plan:

- `error: Failed to resolve root dev dependency` from `bun install` means `del(.devDependencies)` did not run. Check that `postPatch` normalises before `bun2nix.hook` installs.
- `auto-patchelf: N dependencies could not be satisfied` names the missing library. If it is a real one, add it to that pin's `extraBuildInputs` in `packages/extensions/default.nix`; no pin in the initial set needs that. If it is `libc.musl-*`, it is the sibling musl build of a napi package that will never be opened, and it belongs in `autoPatchelfIgnoreMissingDeps` in `mk-pi-extension.nix` instead. Both entries are already there.

A *successful* build of `ext-heyhuynhgiabuu-pi-pretty` still prints `auto-patchelf: 1 dependencies could not be satisfied`, immediately followed by `warn: auto-patchelf ignoring missing libc.musl-x86_64.so.1`. That pair is the expected output, not a failure. The line to react to is the `error:` one.

- [ ] **Step 9: Verify the packages are visible on the flake**

Run:
```bash
cd /home/joe/Development/pi-nix && nix eval --raw --expr \
  'builtins.concatStringsSep "\n" (builtins.filter (n: builtins.substring 0 4 n == "ext-") (builtins.attrNames (builtins.getFlake (toString ./.)).packages.x86_64-linux))' --impure
```

Expected:
```
ext-gotgenes-pi-permission-system
ext-heyhuynhgiabuu-pi-pretty
ext-juicesharp-rpiv-ask-user-question
ext-juicesharp-rpiv-todo
ext-narumitw-pi-btw
ext-narumitw-pi-goal
ext-pi-background-tasks
ext-pi-cache-optimizer
ext-pi-mcp-adapter
ext-pi-subagents
```

- [ ] **Step 10: Format and commit**

```bash
cd /home/joe/Development/pi-nix
nix fmt
git add -A
git commit -m "feat(packages): pinned pi extensions built with bun2nix

Design assumption A4 is false: no pin ships a self-contained dist. Ten need a
real dependency install and go through bun2nix, the same mechanism upstream
already uses for coding-agent-bun. The bundled branch survives for a reason
A4 did not anticipate — pi-cache-optimizer has zero runtime dependencies, so
fetchurl plus tar is the whole build.

Two package.json edits are required before bun install produces a usable
tree, and both were found by running it. --omit=peer drops typebox, which
pi-background-tasks and @narumitw/pi-goal declare as plain peers and both
import; leaving devDependencies in place makes --frozen-lockfile die on
pi-subagents. normalise-package-json.nix defines the fix once so the update
app and the builder cannot drift.

piEntrypoint is a list, not a scalar: pi-background-tasks declares two
entrypoints. Handing pi the package root lets resolveExtensionEntries read
each package's own pi manifest, so the pin file records no entrypoints at all
in the normal case.

npm's dist.integrity is used verbatim as the Nix SRI hash, at the tarball
layer and inside every fetchurl bun2nix generates."
---

### Task 4: Extend `nix run .#update` to bump extension pins

One command bumps `VERSION.json` *and* every entry in `extensions.json`, so pins cannot silently go stale.

**Files:**
- Create: `update-extensions.nix`
- Modify: `update.nix`
- Modify: `flake.nix` (instantiate and expose the new app)

**Interfaces:**
- Consumes: `extensions.json` and `packages/extensions/normalise-package-json.nix` from Task 3
- Produces:
  - `apps.<system>.update-extensions` — `${updateExtensions}/bin/pi-update-extensions`
  - `apps.<system>.update` now runs `pi-sync-upstream`, `pi-regenerate-models`, `pi-update-extensions` in that order
  - `pi-update-extensions` rewrites `extensions.json` (`version`, `url`, `hash`, `skills`, `prompts`) and, for unbundled pins, `packages/extensions/<slug>/bun.lock` and `bun.nix`. It never touches `bundled` or `entrypoints`, which are human decisions.

- [ ] **Step 1: Write the failing test**

Create `tests/update-app-test.nix`:

```nix
# The updater is network-bound, so the check is a contract test rather than a
# run: it proves the app exists, is shellcheck-clean (writeShellApplication
# enforces that at build time), preserves the two fields that are human
# decisions rather than registry facts, and carries the normalisation and
# platform flags whose absence produces failures that only appear later.
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

  # No npm may reappear here by accident.
  ! grep -q 'npmDepsHash' "$script"
  ! grep -q 'prefetch-npm-deps' "$script"

  # The fields and mechanisms it must carry.
  grep -q 'dist.integrity' "$script"
  grep -q 'dist-tags' "$script"
  grep -q 'bun2nix' "$script"
  # Without --os/--cpu the generated bun.nix omits every non-host platform
  # variant and the Darwin build of ext-heyhuynhgiabuu-pi-pretty fails.
  grep -q -- "--os='\*'" "$script"
  grep -q -- "--cpu='\*'" "$script"
  # The normalisation must be the same string mkPiExtension applies, or
  # --frozen-lockfile rejects the lockfile this app just wrote.
  grep -q 'peerDependenciesMeta' "$script"
  grep -q 'del(.devDependencies' "$script"

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

let
  # The identical string mkPiExtension runs in postPatch. Sharing it is not
  # tidiness: bun install --frozen-lockfile compares the lockfile against the
  # manifest, so a generator that normalises differently from the builder
  # produces a lockfile the builder rejects.
  normalisePackageJson = pkgs.callPackage ./packages/extensions/normalise-package-json.nix { };
in
pkgs.writeShellApplication {
  name = "pi-update-extensions";
  runtimeInputs = with pkgs; [
    bun
    bun2nix
    cacert
    coreutils
    curl
    gnused
    gnutar
    gzip
    jq
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
        # bun2nix writes the same string into the fetchurl for every dependency
        # below, so one convention covers both layers.
        hash=$(jq -r '.dist.integrity' <<< "$vjson")

        # Skill and prompt directories come straight from the package's own pi
        # manifest, with the leading "./" stripped so they compose as
        # "''${drv}/''${path}".
        skills=$(jq -c '[.pi.skills[]? | sub("^\\./"; "")]' <<< "$vjson")
        prompts=$(jq -c '[.pi.prompts[]? | sub("^\\./"; "")]' <<< "$vjson")

        bundled=$(jq -r --arg n "$name" '.[$n].bundled' extensions.json)

        if [[ "$bundled" != "true" ]]; then
          work="$tmpdir/$slug"
          mkdir -p "$work"
          curl -fsSL "$url" | tar -xzf - -C "$work" --strip-components=1

          (
            cd "$work"
            ${normalisePackageJson}

            # --omit flags must match mkPiExtension's bunInstallFlags exactly.
            # --os/--cpu force every platform variant of an optional native
            # dependency into the lockfile; the build then installs only the
            # host's. Without them a lockfile generated on Linux omits the
            # Darwin tarballs and the Darwin build of that pin fails.
            bun install --lockfile-only \
              --omit=dev --omit=peer \
              --os='*' --cpu='*' >/dev/null
          )

          mkdir -p "packages/extensions/$slug"
          cp "$work/bun.lock" "packages/extensions/$slug/bun.lock"
          bun2nix -l "$work/bun.lock" -o "packages/extensions/$slug/bun.nix"
        fi

        jq \
          --arg n "$name" \
          --arg v "$version" \
          --arg u "$url" \
          --arg h "$hash" \
          --argjson s "$skills" \
          --argjson p "$prompts" \
          '.[$n].version = $v
           | .[$n].url = $u
           | .[$n].hash = $h
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

The `apps = forEachSystem (...)` block computes `pkgs` from plain nixpkgs. `update-extensions.nix` needs `pkgs.bun2nix`, so give that block the same overlay-applied nixpkgs the `packages` block already builds. Inside `apps`, change:

```nix
          pkgs = import nixpkgs { inherit system; };
```

to:

```nix
          pkgs = import nixpkgs {
            inherit system;
            overlays = [ bun2nix.overlays.default ];
          };
```

This is a widening, not a rewrite: every existing consumer in that block keeps working, because the overlay only adds `bun2nix`. Then add an instantiation after `regenerateModels`:

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
cd /home/joe/Development/pi-nix
cp extensions.json /tmp/extensions-before.json
cp -r packages/extensions /tmp/extensions-dir-before
nix run .#update-extensions
diff /tmp/extensions-before.json extensions.json
diff -r /tmp/extensions-dir-before packages/extensions
echo PINS-STABLE
```

Expected: `PINS-STABLE`, plus ten `pinned <name>@<version>` lines. Both diffs must be empty. The second one is the load-bearing check: it proves the app regenerates byte-identical `bun.lock` and `bun.nix` files, which is only true if its normalisation and flags match Task 3's generator exactly. A non-empty diff on `extensions.json` alone means a pinned package was republished — inspect it, re-run `nix build .#checks.x86_64-linux.extensions -L`, and commit the bump with the rest of the task.

Also confirm the human-owned fields survived:

```bash
cd /home/joe/Development/pi-nix && jq -c 'to_entries | map({key, bundled: .value.bundled, entrypoints: .value.entrypoints})' extensions.json
```

Expected: `"entrypoints":[]` everywhere, `"bundled":true` for `pi-cache-optimizer` alone.

- [ ] **Step 8: Format and commit**

```bash
cd /home/joe/Development/pi-nix
nix fmt
nix flake check -L
git add -A
git commit -m "feat(update): bump every extension pin from nix run .#update

pi-update-extensions reads each package's latest version, tarball URL, and
dist.integrity straight off the registry — integrity is an SRI string Nix
accepts verbatim — then regenerates the vendored bun.lock and the bun.nix
bun2nix builds from it. It shares normalise-package-json.nix with
mkPiExtension, so the lockfile it writes is the one --frozen-lockfile
accepts. --os='*' --cpu='*' keep every platform variant of a native optional
dependency in the lockfile, which is what makes the Darwin build of
pi-pretty possible from a Linux-generated pin. bundled and entrypoints are
human overrides and are never rewritten."
---

### Task 5: `extra-options.nix` and the `systemPrompt` option

Upstream only has `rules` → `--append-system-prompt`. Replacement of pi's default prompt is a stated goal of the design, and it needs `--system-prompt`. This task also flips the default package to the Bun build, and establishes the additive module that Tasks 6–8 extend.

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
  - `pi.coding-agent.package` now resolves to `coding-agent-bun` instead of `coding-agent`, via `lib.mkDefault` from this module rather than an edit to the option that declares it
  - The module contributes **only** through `package`, `extraArgs`, `extensions`, `skills`, `promptTemplates`, `settings`, and `environment`. The last six are list- or attr-typed and merge across definitions; `package` is a plain `package` option whose upstream `default` a `mkDefault` here outranks. `coding-agent/options.nix` never has to change either way

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
    packages.${system} = {
      coding-agent = pkgs.hello;
      # Distinguishable from coding-agent so the default-package assertion
      # below cannot pass by accident.
      coding-agent-bun = pkgs.cowsay;
    };
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
# The fork ships the Bun build by default. Upstream's option declares
# `default = coding-agent`; a mkDefault from extra-options.nix outranks it
# without options.nix changing.
assert bare.package == pkgs.cowsay;
# An explicit choice still wins, so the npm build stays reachable.
assert (evalPi { pi.coding-agent.package = pkgs.hello; }).package == pkgs.hello;
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
  grep -qxF 'You are terse.' ${inline.finalSystemPrompt}
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
  inherit (pkgs.stdenv.hostPlatform) system;
  # Upstream's options.nix inherits `coding-agent` from the same attrset and
  # makes it the option default. Taking the sibling here and handing it back
  # through mkDefault is how the fork changes that answer without touching the
  # file that asks the question.
  inherit (self.packages.${system}) coding-agent-bun;

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
    # Everything JavaScript in this stack runs on Bun, pi included. Upstream
    # builds both and defaults to the npm one; mkDefault flips that answer at
    # the lowest possible priority, so any explicit `package = ...` from a
    # consumer still wins and `packages.coding-agent` stays buildable.
    package = lib.mkDefault coding-agent-bun;

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

- [ ] **Step 7: Verify the default package really is the Bun build**

The eval test asserts this against a stub. Assert it once against the real
flake, because a stub cannot catch a wrong attribute name in
`self.packages.${system}`:

```bash
cd /home/joe/Development/pi-nix && nix eval --impure --raw --expr '
  let
    flake = builtins.getFlake (toString ./.);
    pkgs = import flake.inputs.nixpkgs { system = "x86_64-linux"; };
    agent = flake.lib.mkCodingAgent { inherit pkgs; modules = [ ]; };
  in
  agent.config.pi.coding-agent.package.pname'
```

Expected: `pi-coding-agent-bun`. If it prints `pi-coding-agent`, the
`mkDefault` is not reaching the option — check that `extra-options.nix` is in
the module list of whichever entrypoint the command exercised.

Then confirm the npm build is still reachable on request, so the fork narrows
nothing:

```bash
cd /home/joe/Development/pi-nix && nix eval --impure --raw --expr '
  let
    flake = builtins.getFlake (toString ./.);
    system = "x86_64-linux";
    pkgs = import flake.inputs.nixpkgs { inherit system; };
    agent = flake.lib.mkCodingAgent {
      inherit pkgs;
      modules = [ { pi.coding-agent.package = flake.packages.${system}.coding-agent; } ];
    };
  in
  agent.config.pi.coding-agent.package.pname'
```

Expected: `pi-coding-agent`.

- [ ] **Step 8: Confirm `options.nix` is still byte-identical to upstream**

Run:
```bash
cd /home/joe/Development/pi-nix && git diff upstream/master --stat -- coding-agent/options.nix && echo OPTIONS-NIX-UNTOUCHED
```

Expected: `OPTIONS-NIX-UNTOUCHED` with no diffstat lines above it.

- [ ] **Step 9: Format and commit**

```bash
cd /home/joe/Development/pi-nix
nix fmt
nix flake check -L
git add -A
git commit -m "feat(options): systemPrompt, and the Bun build as the default

Upstream only has rules -> --append-system-prompt; replacing pi's default
prompt needs the other flag. Verified against pi v0.84.2: --system-prompt
takes text, and resolvePromptInput reads it as a file when the argument is an
existing path, so a store path works exactly as rules already does.

The same module sets package = lib.mkDefault coding-agent-bun. Upstream
builds both variants and defaults to the npm one; mkDefault flips that at the
lowest priority, so an explicit package= still wins and packages.coding-agent
stays buildable. options.nix, which declares the option and its default, is
not touched.

All of pi-nix's additions live in a second module merged alongside
options.nix, which stays byte-identical to upstream. The module reaches the
command line through extraArgs, which options.nix appends after its own
resourceArgs."
```

---

### Task 6: `extensionPackages` — consuming the passthru contract

Enabling an extension becomes a single list edit. Its entrypoints, skills, prompts, settings, and prompt fragment all follow from the derivation, so there is no dangling config when one is removed.

The option takes `listOf package` and reads only `passthru`, which is what lets it accept two kinds of derivation without knowing the difference. A pinned npm tarball built by `mkPiExtension` (Task 3) and a package built from in-repo source by `mkPiPlugin` (Task 2) carry the identical passthru contract. That matters beyond this phase: the fork will host first-party extensions of its own — `pi-auto-mode` and `pi-notify` in phase 3, `pi-voice` alongside them — and each will live in its own `packages/<name>/` directory with a `default.nix` that ends in `mkPiPlugin`, then appear in `extensionPackages` next to the `ext-*` pins with no change on this side. Nothing in Task 6 references `extensions.json`, `packages/extensions/`, or the `ext-` prefix. Keep it that way; the moment this option learns where a derivation came from, the first-party extensions need a second code path.

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

Then add it to the `outputs` function's argument list. This is **mandatory**, not cosmetic: the outputs function destructures without a `...`, so Nix calling it with an input the pattern does not name fails with `error: function ... called with unexpected argument 'agent-statusline'`. Change:

```nix
  outputs =
    {
      self,
      nixpkgs,
      systems,
      bun2nix,
      jail-nix,
    }:
```

to:

```nix
  outputs =
    {
      self,
      nixpkgs,
      systems,
      bun2nix,
      jail-nix,
      agent-statusline,
    }:
```

The option module still reaches it through `self.inputs.agent-statusline` rather than being threaded a function argument, so `module.nix` and `home-manager.nix` keep their upstream `{ self, jail-nix }` signatures and stay one-line diffs.

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
    packages.${system} = {
      coding-agent = pkgs.hello;
      coding-agent-bun = pkgs.cowsay;
    };
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

Add to the `let` block, near the top. `system` is already bound there from
Task 5, so add only these two:

```nix
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

`notificationArgs` holds bare paths, so add the flag-pairing binding directly beneath it in the same `let` block:

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

  actual = pkgs.lib.mapAttrs (_name: path: builtins.hashFile "sha256" path) protected;

  # Recorded from upstream/master @ 273a552. Filled in by Step 2.
  expected = { };

  drifted = pkgs.lib.attrNames (
    pkgs.lib.filterAttrs (name: h: (expected.${name} or null) != h) actual
  );
in
pkgs.runCommand "pi-nix-additive-test"
  {
    drifted = pkgs.lib.concatStringsSep " " drifted;
    recorded = builtins.toJSON actual;
  }
  ''
    set -euo pipefail
    if [ -n "$drifted" ]; then
      echo "Upstream files outside the permitted edit set changed: $drifted"
      echo ""
      echo "See docs/REBASING.md. If this is a deliberate upstream rebase, paste"
      echo "these hashes into the expected binding in tests/additive-test.nix,"
      echo "in the same commit as the rebase:"
      echo "$recorded"
      exit 1
    fi
    touch $out
  ''
```

The comparison happens in Nix, not in shell, so there is no heredoc whose
indentation the `''` string could silently eat.

Register it in `tests/default.nix`:

```nix
  additive = import ./additive-test.nix args;
```

- [ ] **Step 2: Run it and record the hashes**

Run:
```bash
cd /home/joe/Development/pi-nix && nix build .#checks.x86_64-linux.additive -L 2>&1 | grep -A4 'Upstream files outside'
```

Expected: the failure message listing all eight paths, then a JSON object
mapping each path to its sha256.

Transcribe that JSON into the `expected` binding, giving:

```nix
  expected = {
    "VERSION.json" = "<hash from the JSON above>";
    "coding-agent/bun.nix" = "<hash>";
    "coding-agent/options.nix" = "<hash>";
    "coding-agent/package-bun.nix" = "<hash>";
    "coding-agent/package.nix" = "<hash>";
    "regenerate-models.nix" = "<hash>";
    "scan.nix" = "<hash>";
    "sync-upstream.nix" = "<hash>";
  };
```

Then confirm it is green:

```bash
cd /home/joe/Development/pi-nix && nix build .#checks.x86_64-linux.additive -L && echo RECORDED
```

Expected: `RECORDED`.

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

~~~~markdown
## Options

Everything upstream documents under `programs.pi.coding-agent` still applies.
This fork adds:

| Option | Type | Default | What it does |
| --- | --- | --- | --- |
| `package` | package | `coding-agent-bun` | Upstream declares this option with `coding-agent` as the default; the fork lowers a `mkDefault` onto it so the Bun build wins. Set it explicitly for the npm build. |
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
| `ext-juicesharp-rpiv-ask-user-question` | `@juicesharp/rpiv-ask-user-question` — AskUserQuestion |
| `ext-narumitw-pi-goal` | `@narumitw/pi-goal` — `/goal`, pushing rather than vetoing |
| `ext-juicesharp-rpiv-todo` | `@juicesharp/rpiv-todo` — todos |
| `ext-gotgenes-pi-permission-system` | `@gotgenes/pi-permission-system` — deterministic permissions |
| `ext-narumitw-pi-btw` | `@narumitw/pi-btw` — side questions off the main thread |
| `ext-pi-cache-optimizer` | `pi-cache-optimizer` — prefix-cache hit rate |
| `ext-heyhuynhgiabuu-pi-pretty` | `@heyhuynhgiabuu/pi-pretty` — TUI syntax highlighting |

Bump every pin, and pi itself, with one command:

```sh
nix run .#update
```

`nix run .#update-extensions` bumps only the extension pins, regenerating each
one's `bun.lock` and `bun.nix` as it goes. Neither ever rewrites the `bundled`
or `entrypoints` fields in `extensions.json` — those are human decisions about
a package, not facts read off the registry.

Generate the full reference:

```sh
nix build .#docs-md
nix build .#docs-html
```
~~~~

- [ ] **Step 5: Confirm the generated option docs include the new options**

Run:
```bash
cd /home/joe/Development/pi-nix && nix build .#docs-md --no-link --print-out-paths | xargs -I{} grep -c -E '^## (pi\.coding-agent\.(package|systemPrompt|extensionPackages|statusline|notifications))' {}
```

Expected: `5` or more (`statusline` and `notifications` expand into several sub-entries, so a larger number is correct; anything below 5 means an option is missing from the docs output).

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

**Spec coverage.** Design §7's addition table is covered row for row: `systemPrompt` → `--system-prompt` (Task 5), `packages/extensions/` + `packages.ext-*` (Task 3), `extensions.json` + extended `update` app (Tasks 3 and 4), `statusline` (Task 7), `notifications` (Task 8), `lib/` builders (Task 2). §8's `mkPiExtension` shape, `extensions.json` schema, `passthru.settings` rationale, and the "pin by verified repository URL, not remembered author name" instruction are all honoured: the pin table records the registry's repository URLs, and verified fact 11 records three corrections (`nicobailon` not `nicopreme`, `narumiruna/pi-extensions` for the `@narumitw` scope, `jiangge` for `pi-cache-optimizer`). §7's "known upstream behaviour, retained" paragraph about the `settings.json` jq-merge is reproduced in the README rather than being fixed. The `autoMode` row of §7's table is deliberately **not** here: it belongs to phase 3 with `pi-auto-mode` and the permission layers, and landing the option without either layer would ship a lie.

**The pin set is the one design §8 settles on.** Eleven third-party packages. `@plannotator/pi-extension` is gone, so nothing in this plan references plan mode. `remote-pi` is phase 7's and is not pinned here. `@juicesharp/rpiv-voice` was in an earlier draft of this plan and was removed when voice moved to a first-party extension over `audiomemo`; its sherpa-onnx/decibri native binaries and its 157 MB runtime Whisper model are no longer this phase's problem.

**Placeholder scan.** No `TBD`, no "similar to Task N", no "add error handling". Every `version`, `url`, and `hash` in `extensions.json` is a value read off the npm registry on 2026-08-18. There is no dependency hash to leave blank: `bun2nix` writes one `fetchurl` per dependency into the per-pin `bun.nix`, so the thing that used to be a transcribed `npmDepsHash` is now a generated file with a shape assertion on it (Task 3 Step 6). The one synthetic hash in `tests/extensions-test.nix` is a deliberate all-`A` sha512 on a derivation that is never built, and the comment says so. One step still has the operator transcribe values a prior command printed, Task 9 Step 2's eight upstream-file hashes, and it gives the exact command and the exact expected shape.

**Validated while writing, not just asserted.** Task 2's four files and its full test were built and run: `pi-nix-lib-tests` passes against the exact code in this plan. Task 5's `extra-options.nix` and its test were run against the real `coding-agent/options.nix` from the fork, confirming that `extraArgs = lib.mkAfter …` from a second module lands in `finalArgs` and coexists with `rules`. Task 6's and Task 8's additions were assembled on top and run the same way, including a deliberate tamper to prove the `--extension` ordering assertion and the `notifications`-without-a-package `tryEval` assertion both actually fire.

Task 3's Bun mechanism was validated by building it, not by reading `bun2nix`'s README. The `dist.integrity`-as-SRI convention was re-checked with a bare `fetchurl` for three pins. Every pin in the set was run through the exact normalise → `--lockfile-only` → `bun2nix` → `--frozen-lockfile` sequence, and the dependency counts in the pin-set table are the measured output. An `autoPatchelfHook` build of the hardest case available at the time finished with `auto-patchelf: 0 dependencies could not be satisfied`, and the resulting native modules loaded under `node` straight from the store, which is what establishes that the hook plus `stdenv.cc.cc.lib` is enough and no pin needs `extraBuildInputs`.

Both `package.json` edits in verified fact 5, and the musl carve-out in fact 8, came out of that run rather than out of a document. Each was found as a failure first: `node_modules/typebox` missing, and `error: Failed to resolve root dev dependency '@earendil-works/pi-coding-agent'`.

Every `nix` code block in this document parses under `nix-instantiate --parse`. The `grep -qxF` in the builder tests is `-F` deliberately: with plain `-qx`, `[file-pattern]` reads as a character class and `log:*)` as a repetition, and both assertions pass vacuously against the wrong content.

**Type consistency.** `passthru.piEntrypoint` is `list of str` in `mkPiExtension` (Task 3), `mkPiPlugin` (Task 2), the fake extensions in the Task 6 test, and the `notificationArgs` consumer in Task 8. `passthru.piSkills` / `piPrompts` are likewise `list of str` everywhere and feed `skills` / `promptTemplates`, whose upstream types (`listOf path`, `listOf path`) accept `/nix/store/…` strings. `passthru.settings` is `attrs` and is folded with `recursiveUpdate` in both Task 6 and Task 8. `passthru.promptFragment` is `null | str` in all four places. `extensions.json` fields are read by exactly two consumers, `packages/extensions/default.nix` and `update-extensions.nix`, and the field list matches between them, with `bundled` and `entrypoints` written by neither.

**Deviations from the spec, with reasons.**
1. **`piEntrypoint` is a list, not the scalar `"…/dist/index.js"` §8 sketches.** `pi-background-tasks` declares two entrypoints, so a scalar cannot represent the pin set. The default value is a one-element list holding the package root, which lets pi's `resolveExtensionEntries` read each package's own `pi` manifest.
2. **`piSkills` and `piPrompts` added to the passthru contract.** `pi-mcp-adapter` ships skills and `pi-subagents` ships skills *and* prompt templates. `--extension` does not load either; only `--skill` and `--prompt-template` do. Without these two fields those resources would silently never load, which is the kind of failure nobody notices.
3. **`extensions.json` has no `npmDepsHash` field, and §8's `mkPiExtension` sketch names one.** With `bun2nix` there is no aggregate hash to record. Each dependency gets its own `fetchurl` in the generated `bun.nix`, carrying npm's `dist.integrity` verbatim, which is the same convention the tarball pin already uses. The field disappears rather than going null.
4. **`mkPiExtension` gained `extraBuildInputs` and a fixed `autoPatchelfIgnoreMissingDeps`.** No pin in the initial set sets `extraBuildInputs`; it exists so the fix for a real missing library on a future pin is one line in `packages/extensions/default.nix` rather than a change to the builder. The ignore list is not optional and is not a workaround: bun installs the musl sibling of every napi platform package it installs, and that file is never opened on a glibc host.

**Spec gaps and contradictions found.**
1. **Assumption A4 is false for every package in the pin set, and its documented fallback is also insufficient.** §8 expected `bundled = true` — "fetchurl npm tarball, use `dist/` as-is" — to be the common case. No pin ships a self-contained `dist`. `@heyhuynhgiabuu/pi-pretty` comes closest and still `require`s `@shikijs/cli` and `@ff-labs/fff-node` out of `node_modules` at runtime. §8's fallback ("build that package with `buildNpmPackage` and an `npmDepsHash`") does not work either, because none of these packages publishes a lockfile. The mechanism that does work is a vendored lockfile plus a generated dependency set, which is why Task 4 has the shape it does. The `bundled` branch survives, but for `pi-cache-optimizer`, which has zero runtime dependencies, rather than for anything A4 predicted.
2. **npm and Bun disagree about peer dependencies, and the disagreement is a correctness bug rather than a preference.** Under `npm ci --omit=peer`, `pi-background-tasks` installs cleanly without `typebox` and throws on first load; the same is true of `@narumitw/pi-goal`. Under `bun install` with no omission, both work but each drags in the whole `@earendil-works/pi-coding-agent` tree that pi already supplies. Neither default is right. `normalise-package-json.nix` hoists exactly the peers that are not pi's, which is the only rule that produces a correct and small tree. Any future pin that declares a plain peer it imports gets this for free; a pin that declares an *optional* peer it imports would not, and would need the rule widened.
3. **`passthru.settings` will be empty for the entire initial pin set.** §8 calls it "load-bearing" and names `pi-mcp-adapter` needing the MCP server list as the motivating case. Verified: `pi-mcp-adapter` reads `~/.config/mcp/mcp.json` and `~/.agents/mcp.json`, not pi's `settings.json`; the `@juicesharp/*` packages read their own `rpiv-*` config; `pi-pretty` and `pi-cache-optimizer` write under `getAgentDir()`. §9's plan to fan `programs.agent-skills.mcpServers` into `pi-mcp-adapter` therefore needs a **config-file** mechanism (`passthru.configFiles`, or home-manager writing `~/.agents/mcp.json`), not `settings.json` merging. Phase 3 should add that; this plan ships the `settings` mechanism as specified and tested against a synthetic case, so the contract exists when a pin does use it.
4. **§7's `autoMode` row has no phase.** §15's rollout order puts `pi-auto-mode` in phase 3 but §7 lists `autoMode` as a pi-nix option alongside `statusline` and `notifications`. Treated here as phase 3, since the option is meaningless without at least one of the two layers §9 describes.
5. **§6 gives `agent-statusline.lib.statuslineOptions` without a system dimension; §15 and the phase-1 plan give `lib.${system}`.** This plan uses `lib.${system}`, matching the phase-1 plan's Task 7, which is the definition that will actually exist.
6. **One candidate was dropped on evidence this plan gathered.** `@narumitw/pi-caffeinate` needed a session-bus talk permission on `org.freedesktop.ScreenSaver` plus `systemd-inhibit` via `add-pkg-deps`, and is silently inert without both. `systemd-inhibit` already does that job directly on NixOS. The pin-set section records the reasoning; design §9's parallel note about `pi-notify` and `org.freedesktop.Notifications` is unaffected and is still phase 3's.

**What I would still watch.** The one pin I flagged for reconsideration, `@narumitw/pi-caffeinate`, was dropped, and the reasoning is recorded above the task list rather than only here. `@narumitw/pi-goal` and `@narumitw/pi-btw` keep the `@narumitw/pi-tui-kit` tail, and that is a deliberate and measured choice: the two share 137 dependency entries at identical `name@version`, `url`, and `hash`, so the tarballs are fetched and stored once, and the second pin costs one extra tarball plus its own 11 MB unpacked tree. If a future bump moves either off `pi-tui-kit@0.56.0`, that sharing ends silently and the closure roughly doubles for those two; the dependency-count table above is the thing to re-measure after any `@narumitw` bump.
