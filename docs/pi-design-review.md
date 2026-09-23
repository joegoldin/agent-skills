# Pi design review

Reviewed 2026-09-23 with two independent Claude Opus 5.5 investigations, then
checked recommendations against Pi 0.87.1 and the selected extensions.

## Keep the existing architecture

Public pi-nix supplies packages and runtime mechanisms. This repository supplies
the personal profile. Dotfiles supplies machine integration. Neither Maki nor
Strands justifies adding another framework, plugin loader, or memory subsystem.

## Useful ideas

- **Small skills bootstrap.** Both projects list skills and load their bodies on
  demand without a mandatory workflow bootstrap. Keep our short selection rules:
  use the smallest relevant set, make brainstorming/plans opt-in, and do not treat
  a skill as authorization for unrelated actions. Remove repeated tool-loading
  instructions only when all supported runtimes supply them themselves.
- **Guidance belongs with the capability.** Maki's tools contribute their own
  prompt hints. Pi already supports tool descriptions and extension guidance;
  keep tool-specific instructions there instead of duplicating them globally.
- **Concise subagent results.** Maki explicitly asks research agents for findings
  and file references instead of code dumps. Use that in research briefs; a new
  global workflow or extension is unnecessary.
- **Stable prompt prefixes.** Strands puts changing environment context after
  stable cached content. Our temporal plugin changes the system prompt every
  five minutes. A targeted follow-up should measure cache hits and test moving
  time context into Pi messages without losing time-awareness after compaction.
  No cache savings have been measured here.

## Already covered

Pi's compaction prompt already preserves goals, constraints, progress, decisions,
next steps, and critical context. Its default reserves 16,384 tokens and retains
20,000 recent tokens. Do not replace it with another summarizer just because the
other projects have one.

Pi's Bash tool saves full output when truncating its preview. MCP adapter 2.37.0
also has an output guard with saved full output and bounded details. Strands'
lower thresholds might be worth testing on actual large-output sessions, but
another offloader would duplicate existing machinery.

The sem skill already covers code structure and budgeted symbol context. Do not
import Maki's language-specific indexers or code-execution runtime.

## Pretty

Keep Pretty 0.6.29. It is not merely a theme: it changes tool implementations,
rendering, and search through FFF. The user values that behavior. The inspected
Linux package is approximately 67 MiB, with a 186 MiB total closure; the latter
is not its marginal storage cost. No interactive latency benchmark was run.

## Do not copy

Skip mandatory todo updates, default-on memory extraction, forced planning,
another prompt templating layer, and redundant truncation layers. Benchmark
claims from either project are not evidence of savings in this Pi profile.

## Sources

- Maki, revision `4a3227cc25d9701825bb540e1652f60b45f2a4dd`:
  [system prompt](https://github.com/tontinton/maki/blob/4a3227cc25d9701825bb540e1652f60b45f2a4dd/maki-agent/src/prompts/system.md),
  [skills](https://github.com/tontinton/maki/blob/4a3227cc25d9701825bb540e1652f60b45f2a4dd/plugins/skill/init.lua),
  [research prompt](https://github.com/tontinton/maki/blob/4a3227cc25d9701825bb540e1652f60b45f2a4dd/maki-agent/src/prompts/research.md).
- [Strands introduction](https://strandsagents.com/blog/introducing-strands-harness/);
  harness-sdk revision `08f5bdd3ad105af661f76c98b9adb0af024ae7f7`:
  [prompt](https://github.com/strands-agents/harness-sdk/blob/08f5bdd3ad105af661f76c98b9adb0af024ae7f7/harness-ts/src/prompt.ts),
  [output offloader](https://github.com/strands-agents/harness-sdk/blob/08f5bdd3ad105af661f76c98b9adb0af024ae7f7/strands-ts/src/vended-plugins/context-offloader/plugin.ts),
  [message injection](https://github.com/strands-agents/harness-sdk/blob/08f5bdd3ad105af661f76c98b9adb0af024ae7f7/strands-ts/src/injection/message-injection.ts).
- Pi 0.87.1: `packages/coding-agent/src/core/compaction/compaction.ts`,
  `core/tools/bash.ts`; MCP adapter 2.37.0: `mcp-output-guard.ts`;
  local temporal integration: `plugins/temporal/temporal.ts`.
