# Design: a first-class pi stack alongside Claude Code

Date: 2026-08-18
Status: approved, pending implementation

## 1. Context

[pi](https://pi.dev) is a minimal terminal coding harness: small core, extended
through TypeScript extensions, skills, prompt templates, and themes. The goal is
to make pi a first-class agent in this Nix setup, on equal footing with Claude
Code, Codex, and Antigravity, driven by the same `agent-skills` library and the
same statusline, without bloating pi the way `oh-my-pi`/omp does.

Upstream [lukasl-dev/pi.nix](https://github.com/lukasl-dev/pi.nix) already
packages pi well. We fork it to `joegoldin/pi-nix` and add what this setup needs,
keeping the fork additive so upstream rebases stay clean.

### What pi gives us for free

- **`~/.agents/skills` is a native discovery path.** `programs.agent-skills`
  already populates it, so the existing skills are readable by pi with zero
  build work.
- **Skills follow the Agent Skills standard**, and pi is *more* permissive than
  Claude: it drops the requirement that `name` match the parent directory.
- **`--system-prompt` fully replaces** pi's default prompt, and skills plus
  context files are still appended afterward. `~/.pi/agent/SYSTEM.md` does the
  same declaratively.
- **Prompt templates are slash commands** with `$1`/`$@` arguments and an
  `argument-hint` frontmatter field.
- **The extension API is rich**: lifecycle events (`session_start`,
  `before_agent_start`, `tool_call`, `tool_execution_*`, `agent_settled`,
  `after_provider_response`), `registerTool`/`registerCommand`/`registerFlag`,
  and TUI surfaces `ctx.ui.setStatus`/`setWidget`.
- **`registerTool` carries `promptSnippet` and `promptGuidelines`**, so
  extensions inject their own system-prompt guidance.

### What pi deliberately omits

No MCP, no subagents, no permission popups, no plan mode, no todos, no
background bash, and no sandbox of any kind. pi's own security doc recommends
*external* isolation (container, VM, or bubblewrap) for unattended work.

Every one of those gaps has a vetted ecosystem answer. Weekly npm downloads
measured 2026-08-18:

| Gap | Package | dl/wk |
| --- | --- | --- |
| MCP | `pi-mcp-adapter` | 154k |
| Subagents | `pi-subagents` | 57k |
| Background bash | `pi-background-tasks` | 19k |
| Plan mode | `@plannotator/pi-extension` | 12k |
| Todos | `@juicesharp/rpiv-todo` | 7k |
| Permissions | `@gotgenes/pi-permission-system` | 5k |

## 2. Goals

1. `pi` runs from this Nix config with the full `agent-skills` library.
2. The Claude Code statusline renders identically under pi.
3. Claude-Code-style auto mode: the agent proceeds without prompting, governed
   by rules declared once and honoured by both agents.
4. A slimmed custom system prompt replaces pi's default.
5. Real sandboxing, since pi ships none.
6. Desktop notifications, which pi lacks and the other three now have natively.
7. Everything pure, pinned, rollback-able, and buildable offline.

## 3. Non-goals

- Adopting `oh-my-pi`/omp, or any hard fork of pi itself.
- Replacing the system prompt of Claude Code, Codex, or Antigravity. They ship
  their own; we only *append* shared behavioural preferences.
- Runtime `pi install` from npm as the primary distribution path.
- Reimplementing anything the ecosystem already does well.

## 4. Verified vs. assumed

Facts asserted in this spec were verified against pi.dev docs, the npm registry,
and the local repos on 2026-08-18. The following are **assumptions requiring
verification during implementation**, called out again at their point of use:

| # | Assumption | Fallback if false |
| --- | --- | --- |
| A1 | ~~An extension can make its own LLM call.~~ **RESOLVED TRUE.** `ctx.modelRegistry.complete()` is a documented-in-source facade *"exposed to extensions"*; four extensions in pi's own `examples/` call it. pi's SDK docs page denies this and is simply wrong. | Not needed. |
| A2 | ~~Multiple extensions on `tool_call` have observable ordering.~~ **RESOLVED MOOT.** `pi-permission-system` publishes `registerAuthorizer()` plus a `globalThis` symbol slot, so delegation is a direct typed call for unresolved `ask`s. Ordering never enters into it. | Not needed; the built-in matcher stays as a live fallback. |
| A3 | Skills provided by both `~/.agents/skills` and a pi package de-duplicate by name. | Use pi's `--no-*` discovery-disabling flags to pick a single source. **Fallback confirmed available** — see below. |
| A4 | Each pinned npm extension ships bundled `dist` output. | Build that package with `buildNpmPackage` and an `npmDepsHash`. |
| A5 | The pi extension can shell to `gh` to populate the `pr` widget. | **Resolved: dropped.** pi has no PR concept, so the extension omits `pr` and the widget hides, as the fallback anticipated. |

### Verified against pi 0.84.2

The fork builds and runs (`nix build .#coding-agent`), and `pi --help` on the
resulting binary confirms:

- `--system-prompt <text>` is documented as *"System prompt (default: coding
  assistant prompt)"* — it **replaces** rather than appends, which §12 depends on.
- `--append-system-prompt` exists separately and is repeatable.
- `--no-skills`, `--no-extensions`, and `--no-prompt-templates` all exist, so
  assumption A3's fallback is real rather than hoped for.
- `--skill`, `--extension`, and `--prompt-template` are each repeatable, matching
  what pi.nix's option module already generates.

One naming hazard for later phases: **pi's own `--mode` flag is already taken**
(`text | json | rpc` output mode). `agent-statusline` also takes a `--mode`, but
that is a different binary and the two never collide. No pi extension should
register a `--mode` flag.

## 5. Repo topology

```
             ┌─────────────────────┐
             │  agent-statusline   │  NEW · standalone
             │  · Go binary        │  depends only on nixpkgs
             │  · pi extension TS  │
             └──────────┬──────────┘
                   ▲          ▲
        ┌──────────┘          └──────────┐
   ┌────┴──────┐                    ┌────┴────┐
   │ claude-nix│                    │ pi-nix  │  NEW · fork of
   └────┬──────┘   ┌───────────┐    └────┬────┘  lukasl-dev/pi.nix
        │          │antigravity│         │
        │          │ codex-nix │         │
        └────┬─────┴─────┬─────┴─────────┘
             ▼           ▼
        ┌──────────────────────┐
        │     agent-skills     │  4th target: pi
        └──────────┬───────────┘
                   ▼
             ┌───────────┐
             │  dotfiles │  modules/ai/pi.nix
             └───────────┘
```

`agent-statusline` must be standalone: `agent-skills` already depends on
`claude-nix`, so moving the statusline into `agent-skills` would create a cycle.
It owns **both** the Go binary and the pi extension, because they share a JSON
contract and must version and test together.

No cycles: `agent-statusline` depends on nothing but nixpkgs; `agent-skills`
depends on the four agent repos and none depend back on it.

## 6. `agent-statusline`

Extracted from `claude-nix/packages/claude-statusline`, renamed, and taught a
second input mode. Claude-mode output must remain byte-identical.

### Principle

**TypeScript stays dumb, Go owns translation.** The pi extension emits JSON
describing only what pi natively knows. Go decodes it into the existing
canonical `Status` and renders. All harness translation stays under golden tests.

### Layout

```
internal/input/
  status.go        canonical Status — unchanged; all widgets read this
  claude/          decode Claude Code stdin JSON — existing behaviour
  pi/              decode pi-shaped JSON — NEW
internal/transcript/
  claude/          Claude JSONL — existing
  pi/              pi session format
cmd/agent-statusline
  --mode claude|pi   default: autodetect on JSON shape
  hook               gains a pi invocation writing the same tool-timing sidecar
```

Go module path becomes `github.com/joegoldin/agent-statusline`. Cache directory
moves to `~/.cache/agent-statusline/`; it is a cache, so it simply repopulates.

### Mode-gated behaviour changes

1. **`cost`** currently hides unless Anthropic rate limits indicate overage — a
   Claude Max assumption. Under pi the auth is Codex/API-key/OpenRouter, so cost
   is the primary meter and always shows. Claude mode keeps today's gating.
2. **`rate_limits`** populates in pi mode only when `after_provider_response`
   yields `anthropic-ratelimit-*` headers. With the chosen auth paths that is
   effectively never; the widget already hides cleanly when absent.
3. Everything else is mode-independent.

### Shared config schema

The ~15 statusline options (`row1`, `row2`, `hide`, `padding`,
`refreshInterval`, `gitCacheTtlSeconds`, `barWidth`, thresholds, …) currently
live in `claude-nix/modules/home-manager.nix`. Duplicating them into `pi-nix`
would guarantee drift, so `agent-statusline` exposes them:

```
agent-statusline.lib.statuslineOptions   ← imported by claude-nix AND pi-nix
agent-statusline.lib.renderConfig        ← options → config JSON
```

Each consumer mounts the submodule under its own namespace
(`programs.claude-nix.statusLine`, `programs.pi.coding-agent.statusline`). One
schema, one meaning, one place to add a widget.

### Widget coverage under pi

- **Available**: `model` (`ctx.model`), `context`, `context_bar`, `tokens`
  (`ctx.getContextUsage()`), `cwd`, `session_name`, `effort`
  (`ctx.thinkingLevel`), `duration`, `burn`, `compaction`, and `git` (shells out
  itself, harness-independent).
- **Computed**: `cost`, as a plain sum over assistant messages. Verified
  during implementation: every pi API adapter calls `calculateCost()`
  internally, so `usage.cost.total` arrives already priced — tier-aware and
  already applying Anthropic's 2x 1h-cache-write rule. No pricing table is
  read and there is no drift risk.
- **Via the `hook` seam**: `activity`, driven by `tool_execution_start`,
  `tool_execution_update`, and `tool_execution_end`.
- **Assumption A5**: `pr`, requiring the extension to shell to `gh`.
- **Absent by design**: `rate_limits` on non-Anthropic auth.

## 7. `pi-nix`: the delta vs. upstream

Fork of `lukasl-dev/pi.nix`, renamed to `pi-nix`, retaining an `upstream` remote
and a documented rebase procedure. Untouched: `package.nix`, `package-bun.nix`,
`bun.nix`, jail wiring, `sync-upstream`, `regenerate-models`, cachix config.

Additions, all additive:

| Addition | Rationale |
| --- | --- |
| `systemPrompt` option → `--system-prompt` | Upstream only has `rules` → `--append-system-prompt`. Replacement is required. |
| `packages/extensions/` + `packages.ext-*` | Pinned derivations so ecosystem extensions enter the closure purely. |
| `extensions.json` + extended `update` app | `nix run .#update` bumps `VERSION.json` *and* every extension pin. |
| `autoMode` option | Natural-language rule lists feeding both permission layers. |
| `statusline` option | Wires the `agent-statusline` extension and its config JSON. |
| `notifications` option | Configures the first-party `pi-notify` extension (§10). |
| `lib/` builder functions | `mkPiPlugin` / `mkPiSkill` / `mkPiPromptTemplate`, exposed as flake `lib` in the shape `claude-nix/lib` uses. This is what `agent-skills` imports as `piLib` in §11; without it the `pi` target has nothing to build with. |

### Known upstream behaviour, retained

Upstream's `settings` option jq-merges into `~/.pi/agent/settings.json` on every
launch rather than writing a store symlink. This is deliberate — pi writes to
that file itself via `/login` and `/model` — but it means Nix-declared settings
win over interactive `/model` choices on each run. This is the same trade-off
already documented in `modules/ai/codex.nix`. Keep the behaviour; document it.

## 8. Extension packaging

```nix
mkPiExtension {
  pname   = "pi-mcp-adapter";
  version = "…";                # from extensions.json
  bundled = true;               # true  → fetchurl npm tarball, use dist/ as-is
                                # false → buildNpmPackage + npmDepsHash
  passthru = {
    piEntrypoint   = "…/dist/index.js";  # what --extension receives
    settings       = { … };              # merged into settings.json
    promptFragment = null;               # escape hatch; normally null
  };
}
```

`extensions.json` holds `{name, version, hash, npmDepsHash, bundled}` per
package (assumption A4 decides `bundled` per package).

> **Correction found during planning:** `ExtensionContext` exposes no settings
> reader, so `passthru.settings` cannot deliver configuration to an extension at
> runtime. Extensions that need config read a store path from an environment
> variable instead (`PI_AUTO_MODE_CONFIG`, `PI_NOTIFY_CONFIG`). The attribute
> still drives what the module writes into `settings.json` for pi itself.

**`passthru.settings` is load-bearing.** Several extensions need configuration —
`pi-mcp-adapter` needs the MCP server list, the permission extensions need rules.
Carrying config on the derivation lets the module compute settings from *which
extensions are enabled*, so adding or removing one is a single list edit with no
dangling config.

`promptFragment` exists but should normally stay `null`, because `registerTool`
already supplies `promptSnippet`/`promptGuidelines`. It is an escape hatch for an
extension that does not, not the normal path.

### Initial pin set

| Extension | Fills | Source |
| --- | --- | --- |
| `pi-mcp-adapter` | MCP (nix-helper's server and future ones) | npm |
| `pi-subagents` | `dispatching-parallel-agents`, `subagent-driven-development` | npm |
| `pi-background-tasks` | background bash | npm |
| `@plannotator/pi-extension` | plan mode (`writing-plans`, `brainstorming`) | npm |
| `@juicesharp/rpiv-todo` | TodoWrite, which `using-agent-skills` mandates | npm |
| `@gotgenes/pi-permission-system` | deterministic permission layer | npm |
| `pi-auto-mode` | classifier layer | first-party |
| `pi-notify` | desktop notifications | first-party |
| `agent-statusline` extension | statusline | `agent-statusline` repo |

Pin each by **verified repository URL**, not by remembered author name: the pi
package gallery and awesome-pi disagree on authorship for several packages
(`nicopreme` vs `nicobailon`), so authorship must be confirmed at pin time.

## 9. Permissions and sandbox

Three layers, each with one job:

```
┌───────────────────────────────────────────────────┐
│ jail.nix (bubblewrap)          CONTAINMENT        │
│ network · mount-cwd · add-pkg-deps[toolchain]     │
│ try-readonly: 1Password agent.sock, known_hosts,  │
│               ~/.ssh/config                       │
│ → mirrors the claude-nix extraSandbox allowlist   │
├───────────────────────────────────────────────────┤
│ pi-permission-system            FAST POLICY       │
│ deterministic allow / deny / ask · audit log      │
│ → resolves the clear-cut majority, no model call  │
├───────────────────────────────────────────────────┤
│ pi-auto-mode (first-party)      JUDGEMENT         │
│ only what layer 2 marked "ask"                    │
│ classifier + session context → soft/hard deny     │
└───────────────────────────────────────────────────┘
```

> **Two jail corrections found during planning:** `~/.1password/agent.sock` needs
> `try-readwrite`, not `try-readonly` — an `AF_UNIX` connect requires write on the
> inode. And `pi-notify` (§10) needs dbus talk permission on
> `org.freedesktop.Notifications` or it is silently inert inside the jail.

### Shared rules

`modules/agent-skills.nix` already fans one declaration out to whichever agents
are present, via `mkIf (options.programs ? claude-nix)`. Auto-mode rules use
exactly that pattern:

```
programs.agent-skills.autoMode = {
  allow = [ … ]; soft_deny = [ … ];
  hard_deny = [ … ]; environment = [ … ];
}
        │
        ├──► programs.claude-nix.autoMode          (native classifier)
        └──► programs.pi.coding-agent.autoMode     (both pi layers)
```

`programs.agent-skills.mcpServers` gains a pi arm the same way, feeding
`pi-mcp-adapter`.

### Semantics

- `allow` — proceed without prompting.
- `soft_deny` — destructive, but explicit user intent clears it. The classifier
  therefore receives recent user turns from `ctx.sessionManager` alongside the
  rules.
- `hard_deny` — a security boundary; user intent does not clear it.
- `environment` — facts about this machine the classifier should assume.

### Failure behaviour

A classifier that is unavailable or erroring **fails closed**. With a UI
(`ctx.hasUI`) that means falling back to a prompt; in `print`/`json` mode it
means blocking. A broken classifier must never silently widen permissions.

### Build order (mitigates A2)

Build `pi-auto-mode` first with deterministic matching implemented *inside* it,
then attempt to delegate that layer to `pi-permission-system`. If ordering turns
out to be unobservable, the fallback is already the shipped state rather than a
rewrite; the loss is `pi-permission-system`'s audit log and subagent forwarding.

## 10. Notifications: `pi-notify`

`code-notify` was dropped from `agent-skills` in commit `70501d8` because
Claude, Codex, and Antigravity all ship notifications natively. pi does not, and
the ecosystem has no vetted option (`pi-notify` on npm: 69 dl/wk). So pi-nix
carries a first-party extension reproducing the old intent:

| Old hook | pi equivalent |
| --- | --- |
| `Notification` (agent needs input) | `pi-auto-mode` / permission layer raising a prompt |
| `Stop` (agent finished) | `agent_settled` |
| `PreToolUse:Bash` (long-running command) | `tool_execution_start`/`end` with a duration threshold |

Implementation shells out to a Nix-baked notifier — `notify-send` on Linux,
`terminal-notifier` or `osascript` on Darwin — so the binary path is resolved at
build time. Configured through the pi-nix `notifications` option (enable,
duration threshold, which events).

## 11. `agent-skills`: the `pi` target

A fourth entry in the existing `targetLibs` map, so cross-agent plugins build for
pi exactly as they do for the other three:

```nix
targetLibs = { claude = claudeLib; antigravity = agyLib;
               codex = codexLib;  pi = piLib; };
```

`buildPiPlugin` emits a real pi package — a `package.json` carrying the `pi` key
— with:

| Source | → | pi form |
| --- | --- | --- |
| all skills | → | `skills/` (Agent Skills format, already compatible) |
| skills with `disable-model-invocation` | → | `prompts/*.md` slash commands; `description` and `argument-hint` from frontmatter |
| `hooks/session-start.sh` (temporal) | → | `extensions/temporal.ts` on `session_start` |
| `programs.agent-skills.mcpServers` | → | `pi-mcp-adapter` settings |

Skills need no content translation. The work is in the three non-skill rows.
Assumption A3 (double-loading against `~/.agents/skills`) is resolved here.

## 12. System prompt

```
prompt/
  core/     harness mechanics · PI ONLY (replaces pi's default)
  shared/   behavioural preferences · appended to ALL FOUR agents
  pi/       pi deltas · expected to stay nearly empty

pi        SYSTEM.md = core + shared + pi   → --system-prompt
claude    CLAUDE.md = shared               → globalClaudeMd (currently unset)
codex     AGENTS.md = shared               → ~/.codex/AGENTS.md (currently empty)
antigrav  its file  = shared
```

`core/` carries what Claude Code and Codex already have built in — tool-use
discipline, search strategy, terminal output conventions — and therefore must
never be appended to them.

`shared/` carries preferences that hold regardless of harness: tone, code
conventions, verification discipline, refusal posture. Both target files are
currently empty or unset, so blast radius is minimal.

`pi/` is expected to stay nearly empty, because extensions inject their own
guidance via `promptSnippet`/`promptGuidelines`.

### Governing rule

**Fragments state policy, never inventory.** No skill names — pi injects the
skill list in XML per the Agent Skills spec. No tool lists — `registerTool`
injects those. No model names, dates, or working directories.

This is enforced mechanically: a CI lint greps the fragments for known skill
names and tool names and fails the build. The constraint is a test, not a habit.

## 13. dotfiles wiring

`modules/ai/pi.nix`, a `den.aspects.pi.homeManager` aspect matching the existing
three, with the same `lib.mkIf (pkgs ? llm-agents)` guard and shape.

Auth, per the chosen paths — ChatGPT/Codex `/login`, 1Password- or agenix-backed
API keys, and OpenRouter — uses `environment.<NAME>.file` pointing at an agenix
path, or pi's `!command` key resolution for `op read`. No secret enters the Nix
store.

## 14. Testing

- **`agent-statusline`**: golden tests per mode. Claude-mode goldens must remain
  byte-identical through the rename — the regression gate for the daily driver.
- **`agent-skills`**: extend the existing lint test to cover pi frontmatter, and
  assert every skill builds for all four targets.
- **`pi-nix`**: eval tests that each `ext-*` builds and its `passthru.settings`
  merges cleanly.
- **Prompt fragments**: the inventory lint from §12.
- All run on garnix, matching current CI.

## 15. Rollout order

1. **`agent-statusline`** — extract, rename, dual-mode, keep Claude goldens
   green. Lands entirely inside the existing Claude setup with no behaviour
   change, and proves the shared-config-schema refactor before pi depends on it.
2. **`pi-nix`** — fork, rename, `systemPrompt` option, extension packaging.
3. **`pi-auto-mode`, `pi-notify`, jail config.**
4. **`agent-skills` pi target.**
5. **Prompt fragments**, plus wiring `shared/` to all four agents.
6. **`modules/ai/pi.nix`.**

## 16. Risks

| Risk | Impact | Mitigation |
| --- | --- | --- |
| A1 false: extensions cannot call an LLM | Classifier needs a rewrite | Shell out to a small CLI |
| A2 false: `tool_call` ordering unobservable | Lose `pi-permission-system` | Build order in §9 makes the fallback the starting state |
| Upstream pi.nix diverges | Rebase pain | Keep the fork strictly additive; `upstream` remote plus documented procedure |
| Extension churn | Pins go stale | `nix run .#update` bumps everything in one command |
| pi's `settings.json` merge overwrites interactive choices | Surprising `/model` behaviour | Documented; same trade-off as codex-nix |
| Claude statusline regression during rename | Breaks daily driver | Byte-identical golden tests as the gate |
