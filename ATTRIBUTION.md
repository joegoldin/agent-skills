# Attribution

## Superpowers Skills

The following skills are derived from [obra/superpowers](https://github.com/obra/superpowers),
licensed under the MIT License:

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

These skills have been copied and may be modified from their originals.
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
