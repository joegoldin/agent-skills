# Attribution

## Superpowers Skills

The following skills are derived from [obra/superpowers](https://github.com/obra/superpowers)
(vendored at upstream **v6.1.1**), licensed under the MIT License:

- brainstorming
- dispatching-parallel-agents
- executing-plans
- finishing-a-development-branch
- receiving-code-review
- requesting-code-review
- subagent-driven-development
- systematic-debugging
- test-driven-development
- using-git-worktrees
- using-agent-skills (formerly using-superpowers)
- verification-before-completion
- writing-plans
- writing-skills

These skills have been copied and modified from their originals. Local changes are
kept minimal and are limited to:

- **Genericization** — the `Superpowers` project name and its filesystem
  conventions are renamed for this plugin: cross-skill references drop the
  `superpowers:` namespace prefix, `~/.config/superpowers/` → `~/.config/agent-skills/`,
  `.superpowers/brainstorm/` → `.agent-skills/brainstorm/`, `docs/superpowers/{plans,specs}/`
  → `docs/plans/`, `using-superpowers` → `using-agent-skills`, and visible
  "Superpowers" UI branding is dropped. Frontmatter is moved into each skill's
  `skill.nix` (the Nix build regenerates it).
- **Worktree conventions** — `using-git-worktrees` / `finishing-a-development-branch`
  default new worktrees to `~/.worktrees/$project/$BRANCH_NAME` and recognize the
  legacy `~/.config/agent-skills/worktrees/` path.
- **`brainstorming` visual companion** — `scripts/server.cjs` `brandMarkup()` is
  neutralized to render nothing, which drops the Superpowers brand footer and
  avoids the remote `primeradiant.com` brand-image request (a version-tagged
  beacon) so the companion never phones home.
- **`using-agent-skills` harness references** — scoped to this plugin's build
  targets: `references/codex-tools.md` (Codex) and `references/antigravity-tools.md`
  (Antigravity). Upstream's `copilot`/`gemini`/`pi` reference files are not vendored.

See the superpowers repository for the original versions.

## Other Skills

- **watching-videos** — pairs with the `watchyt` CLI in
  [joegoldin/dotfiles](https://github.com/joegoldin/dotfiles), which is a
  customized port of [bradautomates/claude-video](https://github.com/bradautomates/claude-video)
  (MIT License). The skill itself is original; the CLI it drives is the port.

- **pixeldrain** — pairs with the `pxd` CLI in `packages/pxd/` (original to this
  repo). The skill prose and the CLI are both original; only the underlying
  pixeldrain.com HTTP API is third-party. API documentation:
  https://pixeldrain.com/api

- **gh-stack** — synthesized from the official agent skill and documentation
  shipped in [github/gh-stack](https://github.com/github/gh-stack) (MIT License),
  at upstream **v0.1.0**. Upstream's `skills/gh-stack/` (`SKILL.md`,
  `references/{commands,stack-design,troubleshooting}.md`) and its docs site
  (`docs/src/content/docs/reference/{rest,merge,graphql,webhooks}-api.md`) were
  merged and restructured rather than vendored: upstream's three reference files
  are consolidated into `references/cli.md`, and `references/api.md` — covering
  the REST `/stacks` endpoints, the async merge API, GraphQL, and webhooks — is
  written from the upstream API docs, which upstream's skill does not cover.
  Frontmatter lives in `skill.nix` per this repo's convention, and the
  description is rewritten as triggering conditions only. Factual details
  (the `view --json` schema, exit codes 0–10) were verified against the v0.1.0
  Go source rather than the prose, which is incomplete on both.

## Vibe Modeling Skill

The `vibe-modeling` skill methodology is distilled from
[cjtrowbridge/vibe-modeling](https://github.com/cjtrowbridge/vibe-modeling).
Upstream does not declare a license; this attribution is offered as a courtesy.
The skill prose is original; the `vibecad` CLI in `packages/vibecad/` is original
to this repo and adapts the upstream's design ideas (numbered revisions,
parameter JSON files, multi-view rendering) without copying upstream code.

## Avoid AI Writing Skill + Detector

The `avoid-ai-writing` skill and the `avoid-ai-detect` detector CLI are vendored
from [conorbronsdon/avoid-ai-writing](https://github.com/conorbronsdon/avoid-ai-writing)
(MIT License, Copyright (c) 2026 Conor Bronsdon), at upstream commit
`6e1369dad98e61b165928f3849f225e11855cdaf` (v3.10.0).

**Skill (`skills/avoid-ai-writing/`).** `SKILL.md` is the upstream `SKILL.md`
body. Per this repo's convention the YAML frontmatter was moved into
`skills/avoid-ai-writing/skill.nix` (the build regenerates it), and a short local
section documenting the `avoid-ai-detect` CLI was added. The body is otherwise
upstream.

**Detector (`packages/avoid-ai-detect/`).** The engine and its tests are copied
byte-for-byte (verifiably unmodified) from upstream `detector/`:

- `patterns.js` → `packages/avoid-ai-detect/patterns.js`
- `CATEGORIES.md` → `packages/avoid-ai-detect/CATEGORIES.md`
- `patterns.test.js` → `packages/avoid-ai-detect/patterns.test.js`
- `categories.test.js` → `packages/avoid-ai-detect/categories.test.js`

The upstream MIT `LICENSE` is preserved at `packages/avoid-ai-detect/LICENSE`.
`default.nix`, `cli.js`, and `avoid-ai-detect.sh` are original to this repo: a
Nix package plus a thin CLI (read file or stdin, run `AIDetector.analyzeText`,
print a report or `--json`) wrapping the unmodified zero-dependency engine with
`nodejs`. The skill calls the resulting `avoid-ai-detect` binary. Upstream's
Cursor rules, GitHub workflows, and demo assets are not vendored; this repo
builds its own multi-agent plugins.

Upstream credits its own pattern research to Pangram Labs, Wikipedia's "Signs of
AI writing," [blader/humanizer](https://github.com/blader/humanizer),
[brandonwise/humanizer](https://github.com/brandonwise/humanizer),
[Aboudjem/humanizer-skill](https://github.com/Aboudjem/humanizer-skill), and the
OpenClaw humanizer ecosystem. Those inline credits are preserved in the skill body.

## Prose Craft Skill

The `prose-craft` skill teaches generative writing techniques and keeps the
coined terminology (freighting, telescoping, melted-together words, line-ups,
recyclables with its simile-reforming / antiquing / soldering / culturing moves,
netting, and hieroglyphics) from Gary and Glynis Hoffman's *Adios, Strunk and
White: A Handbook for the New Academic Essay*.

Copyright protects expression, not methods or ideas (17 USC 102(b)). This skill
reproduces none of the book: every line of prose and every example in `SKILL.md`
is original to this repo. The book is credited here as the source of the
techniques and their names. No part of *Adios, Strunk and White*, or any summary
of it, is included.

## temporal hook

The `agent-skills-temporal` plugin vendors `temporal.py` from
[asakin's gist](https://gist.github.com/asakin/e4225721bb8f16dd6bc34f4eec5499f9)
(v1). A v2 with extended features lives at
https://github.com/asakin/claude-context-hook.

Vendored with minor modifications:

- `$TEMPORAL_STATE_DIR` env var honored (defaults preserved) so each CLI gets
  a distinct state directory.
- `SessionStart` fires on startup/resume in addition to compact, to support
  non-Claude CLIs that may not pass a `source` field.
- Defensive `OSError` / `JSONDecodeError` handling around state I/O.

See `plugins/temporal/README.md` for the diff narrative. The gist's license
is not explicitly declared (GitHub gist default); we credit upstream by
linkback as a courtesy.

## Reverse Engineering Skills + re-shell devShell

The `reverse-engineering`, `android-re`, `windows-re`, and `web-re` skills, and
the `devShells.<linux>.re-shell` output in `flake.nix`, are derived from
[schlarpc/re-shell](https://github.com/schlarpc/re-shell) and the accompanying
write-up
[*Everything I own, owned*](https://schlarp.com/posts/everything-i-own-owned/).

**No upstream license.** re-shell declares no license (no `LICENSE` file, GitHub
reports no SPDX id), so its prose is all-rights-reserved and is not vendored.
Following the same courtesy-credit approach this repo uses for `vibe-modeling`
and `prose-craft`: the skills port the *facts* — tool names, invocations,
command tables, workflow steps, and technical gotchas, which are uncopyrightable
methods and facts under 17 USC 102(b) — and the prose in every `SKILL.md` is
original to this repo. No `SKILL.md` or `CLAUDE.md` text from re-shell is copied.

**devShell.** The `re-shell` devShell adapts upstream's `flake.nix`: the same
uv2nix + pyproject-nix + pyproject-build-systems machinery, the same package
set, the same environment variables and `wordlists` linkFarm, and the
`pyproject.toml` / `uv.lock` / `package.json` / `package-lock.json` workspace
files (upstream's lockfiles, which pin a known-building dependency closure).
Local changes: it is scoped to `x86_64-linux` (the toolchain is x86_64-centric —
some tools have no aarch64 build — and this keeps Darwin and aarch64 evaluation
of the plugin outputs intact); Python is pinned to 3.13 because `uv.lock`'s
wheels stop at cp313; it is entered through the `re-shell` launcher
(`packages/re-shell`), which on macOS boots the shell in a vfkit microVM built
by `lib/re-vm.nix` — original code, using
[microvm.nix](https://github.com/microvm-nix/microvm.nix) (MIT) as a flake
input, with no upstream equivalent; it is exposed as an opt-in
`nix develop .#re-shell` rather than bundled into the plugin buildEnv; upstream's
`treefmt`/`systems` inputs and the in-shell formatter are dropped; and it uses
this repo's `config.allowUnfree = true` instead of upstream's per-package
`allowUnfreePredicate`. Upstream's own exclusions are carried over with their
reasons: `androguard` (broken `dataset` dep in nixpkgs) and `blackboxprotobuf`
(hard-pins `protobuf==3.10.0`).

## tscircuit Skill

The `tscircuit` skill is vendored from
[tscircuit/skill](https://github.com/tscircuit/skill) (MIT License, Copyright
(c) 2026 tscircuit), at upstream commit
`14554d694f38b78c0f7ebde387263074ddd4bf2a`. The upstream `LICENSE` is preserved
at `skills/tscircuit/LICENSE`.

Upstream's flat layout is restructured for this repo: `CLI.md`, `SYNTAX.md`,
`WORKFLOW.md`, `CHECKLIST.md`, and `FOOTPRINTS.md` become
`references/{cli,syntax,workflow,checklist,footprints}.md`, `elements/` becomes
`references/elements/`, and `templates/` and `scripts/` are kept as-is. The
`SKILL.md` body is upstream's with its paths updated for that layout. Local
changes beyond paths:

- The description is rewritten as triggering conditions, and upstream's blanket
  `allowed-tools: Read, Write, Grep, Glob, Bash` is narrowed to local `tsci`
  subcommands (`tsci push`, `tsci login`, and `tsci dev` prompt).
- A "This setup" section notes that `tsci` comes from the dotfiles kicad module
  (so `tsci upgrade` / `tsci agent` do not apply) and that `tsci export -f
  kicad_pcb` hands off to the `konnect` skill for KiCAD edits. The CLI primer's
  prereqs and the scripts' "tsci not found" hint carry the same note.
- Each element page's "Local docs" link pointed into an uncloned
  `docs/` checkout that upstream `.gitignore`s; they now point at the matching
  page on https://docs.tscircuit.com.
- Upstream's `README.md` and `.gitignore` are not vendored.
- `references/field-notes.md` is original to this repo: divergences between the
  installed CLI and upstream's references, recorded from board work here. The
  `pcbkeepout` element page carries a pointer to it.
