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

## Avoid AI Writing Skill

The `avoid-ai-writing` skill is vendored from
[conorbronsdon/avoid-ai-writing](https://github.com/conorbronsdon/avoid-ai-writing)
(MIT License, Copyright (c) 2026 Conor Bronsdon). Vendored at upstream commit
`6e1369dad98e61b165928f3849f225e11855cdaf` (v3.10.0):

- `SKILL.md` → `skills/avoid-ai-writing/SKILL.md`

The body is upstream prose, unmodified except for an attribution header comment.
Per this repo's convention the YAML frontmatter was moved out of `SKILL.md` into
`skills/avoid-ai-writing/skill.nix`, which the build regenerates. The upstream
detector engine, Cursor rules, test suite, and packaging are not vendored — the
skill is self-contained and needs no external tools.

Upstream credits its own pattern research to Pangram Labs, Wikipedia's "Signs of
AI writing," [blader/humanizer](https://github.com/blader/humanizer),
[brandonwise/humanizer](https://github.com/brandonwise/humanizer),
[Aboudjem/humanizer-skill](https://github.com/Aboudjem/humanizer-skill), and the
OpenClaw humanizer ecosystem. Those inline credits are preserved in the skill body.

## RTK (Rust Token Killer)

The `agent-skills-rtk` plugin vendors hook scripts and awareness markdowns from
[rtk-ai/rtk](https://github.com/rtk-ai/rtk) (Apache License 2.0). Vendored at
upstream commit `5a149a7fdb92afe758a0c28d805873ce61d8259f` from:

- `hooks/claude/rtk-rewrite.sh` → `plugins/rtk/hooks/claude/rtk-rewrite.sh`
- `hooks/claude/rtk-awareness.md` → `plugins/rtk/hooks/claude/rtk-awareness.md`
- `hooks/codex/rtk-awareness.md` → `plugins/rtk/hooks/codex/rtk-awareness.md`
- `hooks/antigravity/rules.md` → `plugins/rtk/hooks/antigravity/rules.md`

The full Apache-2.0 LICENSE is preserved at `plugins/rtk/LICENSE`. The `rtk`
binary itself is consumed unmodified from nixpkgs (`pkgs.rtk`).

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
