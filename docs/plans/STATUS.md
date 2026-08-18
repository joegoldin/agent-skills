# pi stack: build status

Single source of truth for what is done, in flight, and not started across the
whole pi-alongside-Claude-Code effort. Everything here is derived from the design
at `2026-08-18-pi-nix-agent-stack-design.md` and the per-phase plans beside it.

**Last reconciled:** 2026-08-18

## How to update this file

Read this before editing. Several agents work in this repo at once.

1. **Edit only the section you own.** Each phase names its owner. If you need to
   change another phase's section, say so in your report instead.
2. **Use targeted string edits, never a whole-file rewrite.** A rewrite discards
   whatever another agent wrote between your read and your write.
3. **Do not commit this file.** The coordinating session commits it, so
   concurrent agents never collide in the index.
4. **Update as you go, not at the end.** Mark a task `wip` when you start it and
   `done` when its verification passes. A crashed agent should leave behind an
   accurate picture of how far it got.
5. **Record what you learned, not just what you did.** The Findings table is the
   most valuable part of this document: it is where a claim from documentation
   got corrected by reading source.

Status values: `todo` · `wip` · `done` · `blocked` · `dropped`

## Phase summary

| # | Phase | Repo | Tasks | Status |
| --- | --- | --- | --- | --- |
| 1 | agent-statusline (extract + dual mode) | agent-statusline, claude-nix | 9 | **done** |
| 1b | statusline native pi rewrite | agent-statusline | 11 | wip |
| 2 | pi-nix fork | pi-nix | 9 | todo (plan in revision) |
| 3 | pi-auto-mode, pi-notify, jail | pi-nix | 10 | todo |
| 4 | agent-skills pi target | agent-skills | 9 | todo |
| 5 | system prompt layers | agent-skills | 8 | wip |
| 6 | dotfiles wiring | dotfiles | 7 | todo |
| 7 | inter-instance messaging | pi-nix | 11 | todo (plan in revision) |
| 8 | pi-voice over audiomemo | audiomemo, pi-nix | TBD | todo (planning) |

## Phase 1: agent-statusline — DONE

Plan: `2026-08-18-agent-statusline.md`. Owner: coordinator.
Published at `github.com/joegoldin/agent-statusline`; `claude-nix` consumes it.

| Task | What | Status |
| --- | --- | --- |
| 1 | Scaffold repo, move source verbatim | done |
| 2 | `--mode` with autodetect | done |
| 3 | pi input decoder | done |
| 4 | Mode-aware cost widget | done |
| 5 | pi golden tests | done |
| 6 | pi tool timing + sidecar-sourced rows | done |
| 7 | Shared Nix option schema in `lib/` | done |
| 8 | pi extension | done (superseded by phase 1b) |
| 9 | claude-nix consumes the flake | done |

Verification held: Claude goldens byte-identical throughout, rendered
`statusline-config.json` byte-identical (`cmp`: 0 bytes differ), `nix flake
check` green in both repos.

Out of scope by decision: `pr` under pi (pi has no PR concept, widget hides).

## Phase 1b: statusline native pi rewrite — WIP

Plan: `2026-08-18-statusline-native-pi.md` (11 tasks, 87 steps).
Owner: Go side (tasks 1-5) delegated; TS side (tasks 6-11) not started.

Why it exists: the phase-1 pi integration is broken. pi's `sanitizeStatusText`
collapses newlines and runs of spaces, destroying the multi-row output and flex
spacers; nothing ticks, so the spinner and clocks freeze.

| Task | What | Status |
| --- | --- | --- |
| 1-5 | Go: spans, widget conversion, activity snapshot, `--emit json` | wip |
| 6 | TS: migrate to `bun test` | todo |
| 7-9 | TS: component, theme tokens, tick + teardown | todo |
| 10 | Integration test that catches the sanitize bug | todo |
| 11 | Nix packaging via bun2nix | todo |

Hard gate: the three Claude golden files stay byte-identical.

## Phase 2: pi-nix fork — TODO

Plan: `2026-08-18-pi-nix-fork.md` (9 tasks, 71 steps). Plan being revised for the
bun2nix switch and the settled pin set. Owner: unassigned.

| Task | What | Status |
| --- | --- | --- |
| 1 | Rename bookkeeping, eval-test harness | todo |
| 2 | `lib/` pi package builders | todo |
| 3 | `mkPiExtension`, `extensions.json`, `packages.ext-*` | todo |
| 4 | Extend `nix run .#update` to bump pins | todo |
| 5 | `extra-options.nix` and `systemPrompt` | todo |
| 6 | `extensionPackages` | todo |
| 7 | `statusline` option | todo |
| 8 | `notifications` option | todo |
| 9 | Document the fork, prove it stayed additive | todo |

## Phase 3: pi-auto-mode, pi-notify, jail — TODO

Plan: `2026-08-18-pi-auto-mode-and-notify.md` (10 tasks, 71 steps). Owner: unassigned.

| Task | What | Status |
| --- | --- | --- |
| 1 | Deterministic rule matcher | todo |
| 2 | Tool-call rendering, user-turn extraction | todo |
| 3 | The classifier | todo |
| 4 | Fail-closed gate on `tool_call` | todo |
| 5 | Nix packaging, `autoMode` config rendering | todo |
| 6 | Delegate to `pi-permission-system` | todo |
| 7 | `pi-notify` core | todo |
| 8 | `pi-notify` wiring, `notifications` option | todo |
| 9 | jail.nix defaults | todo |
| 10 | Live acceptance run | todo |

## Phase 4: agent-skills pi target — TODO

Plan: `2026-08-18-agent-skills-pi-target.md` (9 tasks, 71 steps). Owner: unassigned.
Sequenced after phase 5 to avoid colliding on `modules/agent-skills.nix` and `flake.nix`.

| Task | What | Status |
| --- | --- | --- |
| 1 | `pi-nix` input, `piLib` | todo |
| 2 | `mcpNativeFor "pi"` | todo |
| 3 | pi frontmatter lint | todo |
| 4 | `buildPiPlugin`, realpath-identity gate | todo |
| 5 | Prompt templates from command-style skills | todo |
| 6 | session-start extension | todo |
| 7 | `temporal.ts`, `targetLibs.pi` | todo |
| 8 | Four-target coverage check | todo |
| 9 | Module fan-out, `homeManagerModules.pi` | todo |

## Phase 5: system prompt layers — WIP

Plan: `2026-08-18-system-prompt-layers.md` (8 tasks, 58 steps). Owner: delegated.

| Task | What | Status |
| --- | --- | --- |
| 1 | `lib/prompt.nix` layer composition | wip |
| 2 | `lib/prompt-lint.nix` inventory lint | todo |
| 3 | `core/` fragments | todo |
| 4 | `shared/` fragments | todo |
| 5 | `pi/` fragment, lint as build gate | todo |
| 6 | Verify Antigravity rules path | todo |
| 7 | codex-nix `agentsMd` → `types.lines` | **done** (060e548, pushed) |
| 8 | Four-arm fan-out, module eval test | todo |

The lint is the load-bearing deliverable: fragments state policy, never
inventory. It must be seen to fail on a deliberate violation.

## Phase 6: dotfiles wiring — TODO

Plan: `2026-08-18-dotfiles-pi-wiring.md` (7 tasks, 56 steps). Owner: unassigned.
Last phase; depends on 2, 3, 5.

| Task | What | Status |
| --- | --- | --- |
| 1 | `pi` aspect skeleton, host wiring | todo |
| 2 | agenix secrets for provider keys | todo |
| 3 | Auth across the three paths | todo |
| 4 | Jail permissions | todo |
| 5 | Statusline parity | todo |
| 6 | Shared `autoMode` rule set | todo |
| 7 | Full build, generated-config inspection | todo |

## Phase 7: inter-instance messaging — TODO

Plans: `2026-08-18-pi-messaging-addendum.md`, `2026-08-18-pi-messaging.md`
(11 tasks). Being revised from `pi-intercom` to `remote-pi`. Owner: unassigned.

Decision: `remote-pi` in local mode. Relay on erdtree deferred to Tier 2 for
phone control and cross-machine.

Hardening that is not optional: `inboundTrigger` defaults to `"replies"`. With
`"always"`, any same-uid process can start a turn in any session, with text
arriving as a user message.

## Phase 8: pi-voice over audiomemo — TODO

Plan: `2026-08-18-pi-voice-audiomemo.md` (being written). Owner: unassigned.
Two repos: `audiomemo` gains `record --stream` (NDJSON); `pi-nix` gains the
`pi-voice` extension.

Open question: whether mic capture works inside the bwrap jail.

## Findings

Where reading source corrected what documentation claimed. Add rows as you find
them; this table is why the plans are trustworthy.

| # | Finding | Consequence |
| --- | --- | --- |
| F1 | pi's SDK docs deny that extensions can call an LLM. `ctx.modelRegistry.complete()` exists and four of pi's own examples use it. | Classifier needs no CLI shim. Assumption A1 resolved. |
| F2 | `pi-permission-system` publishes `registerAuthorizer()` and a globalThis symbol. | Layering needs no `tool_call` ordering. A2 moot. |
| F3 | pi has no vetoable stop event. | `/goal` cannot block; `pi-goal` pushes a continuation instead. |
| F4 | `sanitizeStatusText` collapses newlines and space runs. | Phase 1's pi statusline is broken; hence phase 1b. |
| F5 | The jail wraps pi-nix's wrapper, and binds only the runtime closure. | API keys silently resolve to empty. `op read` unusable under the jail on Linux; agenix is the only key path there. |
| F6 | `ExtensionContext` exposes no settings reader. | Extension config travels as a store path in an env var, not `passthru.settings`. |
| F7 | `AF_UNIX` connect needs write on the inode. | 1Password agent socket needs `try-readwrite`, not readonly. |
| F8 | `pi-notify` needs dbus talk on `org.freedesktop.Notifications`. | Otherwise silently inert inside the jail. |
| F9 | A4 is false: none of the pinned packages ships bundled `dist`. | `mkPiExtension` must resolve dependencies, now via bun2nix. |
| F10 | pi dedupes skills twice: by realpath silently, then by name with a warning. | A3 resolved; ship skills as `buildEnv` links to land in the silent path. |
| F11 | `pi-cache-optimizer` hard-bypasses itself on Responses-family APIs. | Nearly a no-op on Codex; value lands on OpenRouter. |
| F12 | `pi-landstrip` ships `shell.readAccess: "host"`. | Read confinement off by default; weaker than the jail, not additive. |
| F13 | npm `pi-chat` is not GitHub `lynxz/pi-chat`. | Pin by verified repo, never by name. |
| F14 | `claude-nix` ships `barWidth = 8`; Go's `Defaults()` says 10. | claude-nix pins 8 explicitly, or the bars silently narrow. |
| F15 | audiomemo already reads `*_API_KEY_FILE` for every backend. | Keys pass as agenix paths; nothing enters the store or the environment. |
| F16 | `mkOptionDefault` is priority 1500, same as an option's own default. | Overriding a schema default needs `mkDefault`. |
| F17 | dotfiles has no `homeConfigurations`; agent repos arrive through `agent-skills`. | Build target is the nixosConfiguration activation package; no new inputs needed. |
| F18 | pi's `--mode` flag is taken (`text|json|rpc`). | No pi extension may register one. |
| F19 | `/tmp/.git` exists on this machine. | `TestQueryNotARepoReturnsNil` states its precondition and skips. |

## Decisions

| Decision | Rationale |
| --- | --- |
| Bun everywhere | pi consumed as `coding-agent-bun`; bun2nix instead of `buildNpmPackage`; `bun test` instead of vitest. |
| `agent-statusline` standalone | `agent-skills` already depends on `claude-nix`, so hosting it there would cycle. |
| 11 third-party pins, 4 first-party | Each traceable to a Claude Code capability restored or a named new capability. |
| Plan mode dropped | Planning writes documents. Consequence: `pi-auto-mode` rules are the only guard on the working tree. |
| Voice via audiomemo, not `rpiv-voice` | Go, already a flake input, no npm native deps, no runtime model download into a jail. |
| `remote-pi` over `pi-intercom` | Covers local and remote in one; relay deferred. |
| avoid-ai-writing on prose | Prompt fragments teach tone by example, so their register becomes the house style. |
