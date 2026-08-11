# Web-uploadable skills bundle + CI — Design

Date: 2026-06-25

## Goal

Add a GitHub Actions workflow that builds the Nix flake and uploads a single
artifact containing every skill in the format that can be uploaded to the
Claude web/app "Customize > Skills" UI (per
[How to create custom skills](https://support.claude.com/en/articles/12512198)).

The upload format is a folder per skill whose root contains `SKILL.md` plus any
resource/script files. The Claude web UI accepts one skill (one zip) at a time,
where the skill folder is the zip root.

## Decisions (locked)

- **Skill scope:** all 29 skills under `skills/`.
- **CLI-backed skills:** bundle scripts for `avoid-ai-writing` only. Leave
  `pixeldrain`, `vibe-modeling`, `watching-videos` as-is (their CLIs need system
  binaries — `curl`/`jq`, OpenSCAD, `yt-dlp`/`ffmpeg` — that the web/app code
  sandbox can't `pip`/`npm` install; `watchyt` isn't even in this repo).
- **Artifact shape:** one combined zip containing all skill folders.
- **Triggers:** push to `main` + manual `workflow_dispatch`.
- **Nix in CI:** `DeterminateSystems/nix-installer-action` +
  `DeterminateSystems/magic-nix-cache-action`.

## Architecture

Two pieces: a new Nix flake output that assembles the bundle, and a thin
workflow that builds it and uploads the result.

### 1. `lib/default.nix`: `buildWebBundle`

A new builder, exported alongside the existing ones. Signature:

```nix
buildWebBundle = { name ? "web-skills", skills, avoidAiDetectSrc }: ...
```

Behavior:

- For every discovered skill, copy its per-skill derivation output
  (`$drv/skills/<name>`) to `$out/<name>` — **hoisted** out of the `skills/`
  subdirectory so each top-level entry is a complete, ready-to-zip skill folder
  (folder = zip root, as the upload docs require). The per-skill drv already
  writes `SKILL.md` with `name`/`description` frontmatter and copies
  `scripts/`/`references/`/`examples/`.
- **Special-case `avoid-ai-writing`:**
  - Copy `cli.js`, `patterns.js`, and `CATEGORIES.md` from `avoidAiDetectSrc`
    (`packages/avoid-ai-detect/`) into `$out/avoid-ai-writing/scripts/`.
    `cli.js` resolves `patterns.js` via `path.join(__dirname, 'patterns.js')`,
    so co-location makes `node scripts/cli.js` work with no env setup.
    `CATEGORIES.md` is reference-only (not loaded at runtime) but included so
    the docs are self-contained.
  - Rewrite the bundled `SKILL.md` (the *copied* file only) with a **surgical**
    `sed`, not a global replace — the file has 6 `avoid-ai-detect` occurrences
    and 2 of them are prose naming the engine, which must stay readable:
    - Command invocations (4): lines starting with `avoid-ai-detect ` and the
      piped form `| avoid-ai-detect` → `node scripts/cli.js` /
      `| node scripts/cli.js`.
    - Frontmatter `allowed-tools`: `Bash(avoid-ai-detect)` → `Bash(node)` and
      `Bash(avoid-ai-detect:*)` → `Bash(node:*)`, so the permitted tool matches
      the bundled invocation.
    - Prose mentions (the `## Optional: the \`avoid-ai-detect\` tool` heading and
      the "companion CLI" sentence) are left as-is — they correctly name the
      engine.
  - Add a `dependencies: node` frontmatter line (per the docs' optional
    `dependencies` field). No npm packages — the detector is pure Node stdlib,
    matching the "include the scripts, not the deps" intent.

The canonical `skills/avoid-ai-writing/SKILL.md` is **never modified**. The
Claude Code / Nix plugin continues to call the `avoid-ai-detect` binary on PATH;
the rewrite exists only inside the web bundle output.

### 2. `flake.nix`: `packages.<system>.web-skills`

Wire `buildWebBundle` into the existing `forAllSystems` packages block, passing
the already-discovered `skills` and `./packages/avoid-ai-detect` as the source.
Exposed as `web-skills` in the per-system packages set.

**Private-input safety:** the flake has a private SSH input (`codex-nix` via
`git+ssh`). `web-skills` is written to touch only the public inputs — it reuses
`skills` (which forces `claudeLib` from the public `claude-nix`) and never
forces `agyLib`/`codexLib`. By Nix's lazy evaluation, building `.#web-skills`
should not fetch `codex-nix`, so CI needs no SSH credentials.

### 3. `.github/workflows/build-web-skills.yml`

```
name: Build web skills bundle
on:
  push: { branches: [main] }
  workflow_dispatch: {}
jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      # Fallback (commented): webfactory/ssh-agent with CODEX_NIX_DEPLOY_KEY
      # only needed if the build unexpectedly fetches the private codex-nix input.
      - uses: DeterminateSystems/nix-installer-action@main
      - uses: DeterminateSystems/magic-nix-cache-action@main
      - run: nix build .#web-skills --print-build-logs
      - run: mkdir -p dist && cp -rL result/. dist/
      - uses: actions/upload-artifact@v4
        with:
          name: claude-skills
          path: dist
```

`cp -rL` dereferences the `result` symlink into real files (upload-artifact
does not follow store symlinks). The downloaded artifact is one zip
(`claude-skills.zip`) containing all 29 skill folders; to upload one skill to
the web/app UI, zip that single folder.

## Data flow

```
skills/<name>/{SKILL.md,scripts,...}   packages/avoid-ai-detect/{cli.js,patterns.js,CATEGORIES.md}
            │                                          │
   discoverSkills (existing)                           │
            │                                          │
       per-skill drv  ──────────────► buildWebBundle ◄─┘
            │                              │
            │              (hoist + avoid-ai-writing rewrite)
            ▼                              ▼
   packages.<sys>.web-skills  ──►  $out/<name>/SKILL.md (+ resources)
                                           │
                                  nix build (CI)
                                           │
                                  cp -rL → dist → upload-artifact
                                           │
                                  claude-skills.zip (one combined zip)
```

## Testing / verification

- `nix build .#web-skills` succeeds locally.
- `result/` contains 29 top-level folders, each with a `SKILL.md`.
- `result/avoid-ai-writing/scripts/` contains `cli.js`, `patterns.js`,
  `CATEGORIES.md`; its `SKILL.md` command blocks use `node scripts/cli.js` (no
  bare `avoid-ai-detect` *invocation*; prose naming the engine is retained), the
  `allowed-tools` line permits `Bash(node)`, and a `dependencies: node`
  frontmatter line is present.
- `node result/avoid-ai-writing/scripts/cli.js --help` runs (sanity check the
  bundled engine is self-contained).
- A spot-checked text-only skill (e.g. `brainstorming/SKILL.md`) is unchanged in
  content from its canonical source (minus frontmatter assembly).
- `nix flake check` still passes (no regression to existing outputs).
- Existing canonical `skills/avoid-ai-writing/SKILL.md` is byte-for-byte
  unchanged in git.

## Out of scope (YAGNI)

- GitHub Release attachment / stable download URLs.
- Per-skill separate artifacts.
- Porting `pxd`/`vibecad`/`watchyt` to run in the web sandbox.
- Any change to the existing Claude/Antigravity/Codex plugin outputs.
```
