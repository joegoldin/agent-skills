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

## Vibe Modeling Skill

The `vibe-modeling` skill methodology is distilled from
[cjtrowbridge/vibe-modeling](https://github.com/cjtrowbridge/vibe-modeling).
Upstream does not declare a license; this attribution is offered as a courtesy.
The skill prose is original; the `vibecad` CLI in `packages/vibecad/` is original
to this repo and adapts the upstream's design ideas (numbered revisions,
parameter JSON files, multi-view rendering) without copying upstream code.

## Avoid AI Writing Skill

The `avoid-ai-writing` skill is vendored from
[conorbronsdon/avoid-ai-writing](https://github.com/conorbronsdon/avoid-ai-writing)
(MIT License, Copyright (c) 2026 Conor Bronsdon), at upstream commit
`6e1369dad98e61b165928f3849f225e11855cdaf` (v3.10.0).

`SKILL.md` is the upstream `SKILL.md` body. Per this repo's convention the YAML
frontmatter was moved into `skills/avoid-ai-writing/skill.nix` (the build
regenerates it). The local changes are the linter section and the mentions that
follow from it.

Upstream also ships a Node detection engine (`detector/patterns.js`, 44
categories). This repo vendored it as `packages/avoid-ai-detect` through
v3.10.0 and has since replaced it with Vale. The pattern rules now live in the
`AvoidAI` Vale style at `packages/vale-agent-skills/styles/AvoidAI/`, written
from the `SKILL.md` catalog rather than translated from upstream code. The
document-level detectors that engine carried — sentence and paragraph
uniformity, cross-paragraph burstiness, punctuation-density distribution,
function-word trigram entropy, type-token ratio, the smart-punctuation
signature, bare-noun-phrase bullet lists — are reimplemented as Vale `script`
rules (Tengo) at the same thresholds. The 0-100 score and its classification
bands are reimplemented in `vale-skill score`, which weights Vale's own output
using the weight table and the `log2(words/50)` normalization from upstream's
scoring model. See `git log` for the removal.

Upstream credits its own pattern research to Pangram Labs, Wikipedia's "Signs of
AI writing," [blader/humanizer](https://github.com/blader/humanizer),
[brandonwise/humanizer](https://github.com/brandonwise/humanizer),
[Aboudjem/humanizer-skill](https://github.com/Aboudjem/humanizer-skill), and the
OpenClaw humanizer ecosystem. Those inline credits are preserved in the skill body.

## Simple English Skill

The `simple-english` skill is a synthesis of
[AminBlg/SimpleEnglish](https://github.com/AminBlg/SimpleEnglish) (MIT License,
Copyright (c) 2026 AminBlg), which paraphrases ASD-STE100 Issue 9 as an agent
skill. This repo's version keeps upstream's rule catalog, mode split, modal
ladder, and worked example; it replaces upstream's by-hand mechanical checklist
with the `SimpleEnglish` Vale style, rewrites the reference material, and adds
the profile mapping. Upstream's `prompts/` and `evals/` are not vendored.

ASD-STE100 itself is not reproduced. Both upstream and this skill paraphrase the
rules and omit the copyrighted dictionary. ASD-STE100 is a registered trademark
of ASD; the standard is a free download at asd-ste100.org. Neither upstream nor
this repo is affiliated with or endorsed by ASD or STEMG.

## Diátaxis Skill

The `diataxis` skill adapts [Diátaxis](https://diataxis.fr) by Daniele Procida,
published under **CC BY-SA 4.0**
([source](https://github.com/evildmp/diataxis-documentation-framework)).

`skills/diataxis/` is adapted material: the map, the compass, the four modes and
their principles, the language patterns, the workflow loop, and the functional /
deep quality distinction all come from diataxis.fr. The wording is largely
rewritten and the checklists, split recipes, and Vale rules are original, but the
framework and its structure are Procida's.

**`skills/diataxis/` and `packages/vale-agent-skills/styles/Diataxis/` are
therefore licensed CC BY-SA 4.0**, and anyone redistributing them must keep that
license and this attribution.

## Vale Package

`packages/vale-agent-skills/` wraps [Vale](https://vale.sh) (MIT License,
errata-ai) as packaged in nixpkgs. Vale itself is unmodified. None of the
third-party styles nixpkgs packages (`alex`, `Google`, `Microsoft`,
`proselint`, `Readability`, `write-good`) are included; the only styles on the
StylesPath are the three written here.

The `AvoidAI`, `SimpleEnglish`, and `Diataxis` styles, the config profiles, the
`vale-skill` launcher, and the tests are original to this repo, derived from the
skills they serve (and so inheriting their attributions above).

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
