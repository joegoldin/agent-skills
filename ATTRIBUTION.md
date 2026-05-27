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
- using-superpowers
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
