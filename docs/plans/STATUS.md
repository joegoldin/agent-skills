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
| 2 | pi-nix fork | pi-nix | 9 | todo (plan ready) |
| 3 | pi-auto-mode, pi-notify, jail | pi-nix | 10 | todo |
| 4 | agent-skills pi target | agent-skills | 9 | todo |
| 5 | system prompt layers | agent-skills | 8 | wip |
| 6 | dotfiles wiring | dotfiles | 7 | todo |
| 7 | inter-instance messaging | pi-nix, dotfiles | 11 | todo |
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
| 1 | Go: `render.Span` + intent table, ANSI as one encoding | done (d329430) |
| 2 | Go: eleven text widgets render spans | done (66ed8f9) |
| 3 | Go: bar + threshold widgets render spans | done (ff460a6) |
| 4 | Go: structured activity snapshot | done (305102d) |
| 5 | Go: `--emit json` | done (9dfa6db) |
| 6 | TS: migrate to `bun test` | todo |
| 7-9 | TS: component, theme tokens, tick + teardown | todo |
| 10 | Integration test that catches the sanitize bug | todo |
| 11 | Nix packaging via bun2nix | todo |

Hard gate: the three Claude golden files stay byte-identical. **Held through
task 5**: `git diff --stat internal/e2e/testdata/` empty, and the sha256 of
`idle/full/narrow.golden` unchanged across the one `-update` run (which was
filtered to `TestGolden/pi-full.json` and created exactly one new file).

The Go side is done. `--emit json` ships the wire format tasks 7-9 consume;
`--emit ansi` remains the default and is byte-identical to no flag at all in
both modes.

## Phase 2: pi-nix fork — TODO

Plan: `2026-08-18-pi-nix-fork.md` (9 tasks, 72 steps). Plan revised and ready to
execute: 11 third-party pins, `bun2nix` throughout instead of `buildNpmPackage`,
and the Bun-built pi as the module default. Owner: unassigned.

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
| 1 | `lib/prompt.nix` layer composition | **done** (7a776b3) |
| 2 | `lib/prompt-lint.nix` inventory lint | **done** (3962e0e) |
| 3 | `core/` fragments | **done** (2f732eb, 78 lines) |
| 4 | `shared/` fragments | **done** (635d2a6, 84 lines) |
| 5 | `pi/` fragment, lint as build gate | **done** (36fcc62 + 672a8e7) |
| 6 | Verify Antigravity rules path | **done** (no diff; see F21, F22) |
| 7 | codex-nix `agentsMd` → `types.lines` | **done** (060e548, pushed) |
| 8 | Four-arm fan-out, module eval test | **done** (672a8e7; module half swept into 38536c2) |

**Phase 5 is complete.** `nix flake check` passes with five new checks:
`prompt-tests`, `prompt-lint-tests`, `prompt-inventory`, `prompt-layering`,
`eval-prompt-fanout`. `codex-nix` is bumped to 060e548.

The lint is the load-bearing deliverable: fragments state policy, never
inventory. It must be seen to fail on a deliberate violation.

**The lint has been watched failing.** Appending `You are Claude; use the Read
tool and start with brainstorming.` to `prompt/shared/00-tone.md` returns all
three hits and nothing else:

    [ { rule = "skill-name"; term = "brainstorming"; }
      { rule = "tool-phrase"; term = "Read tool"; }
      { rule = "identity";    term = "claude"; } ]

Skill names come from `discoverSkills ./skills` ∪ `discoverPlugins ./plugins`,
so adding a skill widens the ban the same day.

**And it has been watched failing as a build gate.** One fragment naming a
skill, a tool, three identities, a date and two paths, plus one badly named
file, takes `nix flake check` down with every hit enumerated:

    error: prompt fragments state inventory, not policy:
      prompt/shared/00-tone.md: skill-name: brainstorming
      prompt/shared/00-tone.md: tool-name: registerTool
      prompt/shared/00-tone.md: tool-phrase: Read tool
      prompt/shared/00-tone.md: tool-phrase: Bash tools
      prompt/shared/00-tone.md: identity: claude
      prompt/shared/00-tone.md: identity: codex
      prompt/shared/00-tone.md: identity: sonnet
      prompt/shared/00-tone.md: date: 2026-08-18
      prompt/shared/00-tone.md: absolute-path: /home/
      prompt/shared/00-tone.md: absolute-path: ~/
      prompt/shared/9-Bad_Name.md: file name must match NN-kebab-case.md

All six rule classes and the file-name rule fire. Reverted, checks pass again.

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

Plans: `2026-08-18-pi-messaging-addendum.md` (§17, decision + security),
`2026-08-18-pi-messaging.md` (11 tasks, 67 steps). Owner: unassigned.

Decision: `remote-pi` 0.7.0 in local mode, `auto_start_relay: false`. The relay
on erdtree is deferred to Tier 2 (tasks 10-11) for phone control and
cross-machine peers. `pi-intercom` rejected; `pi-agents-talk-to-each-other`
retained only as a documented fallback blueprint (addendum §17.13).

Hardening that is not optional, all three measured against the shipped broker
(F23-F25): inbound peer messages do not start a model turn by default,
`takeover` is refused unconditionally, and the launcher runs at `umask 0077`.
Task 3 owns the first two and Task 6 the third; Task 5 asserts all three at
runtime and fails against the unpatched tarball.

| Task | What | Status |
| --- | --- | --- |
| 1 | `mkPiExtension`: bun2nix branch, `keepDependencies`, contract test | todo |
| 2 | Pin `remote-pi` 0.7.0, generate `bun.lock`/`bun.nix`, build `ext-remote-pi` | todo |
| 3 | Harden the broker: refuse `takeover`, gate the turn trigger, two tests | todo |
| 4 | Patch the `session_start` gate so local-only sessions join (A11) | todo |
| 5 | End-to-end smoke test over the real wire protocol, under bun | todo |
| 6 | `messaging` option, env-driven, `umask 0077` + `0700` repair | todo |
| 7 | Prove the socket crosses two jails (A8); nothing added to the jail | todo |
| 8 | Untrusted-peer-input prompt fragment + §12 inventory lint | todo |
| 9 | dotfiles `modules/ai/pi.nix`, two-terminal acceptance run (tests A7) | todo |
| 10 | *(Tier 2, deferred)* relay as a NixOS module on erdtree, tailnet-only | todo |
| 11 | *(Tier 2, deferred)* turn the relay arm on, pair a phone | todo |

The passthru contract is consumed, not widened: `remote-pi` uses `piEntrypoint`
(the package root, so pi reads its own `pi` manifest) and `promptFragment`, and
needs neither `configFiles` nor `runtimeInputs`. What it lost against
`pi-intercom` is written up in addendum §17.6.3; the item that will be felt is
blocking ask/answer as a single tool result.

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
| F20 | `git.go`'s worktree glyph comment says `nf-fa-tree (U+F1BB)`; the literal in the string is U+E5FB. | Under a byte-identical gate, glyph literals must be copied from source, never retyped from the comment that names them. The plan said so; this is the case that proves it. |
| F21 | `antigravity-cli-nix` exposes no instruction-file option and does not package the CLI at all, so the plan's `nix build …#default` step cannot run. The path had to come from the installed `agy` 1.1.11 binary's embedded docs: `~/.gemini/config/` is the global customization root and rules are markdown files under `rules/` beneath it. | `home.file.".gemini/config/rules/agent-skills-shared.md"` is the route, written directly rather than through any module option. Corroborated by `mcpConfigPaths`, which already defaults to `.gemini/config/mcp_config.json`. |
| F23 | `mkIf false { programs.pi.x = …; }` does not suppress "The option `programs.pi' does not exist" — `mkIf` is pushed down and the path is still named in the definition set. | The `mkIf (options.programs ? <agent>)` idiom the MCP fan-out uses does **not** degrade cleanly when a module is absent; it only works today because all three agent modules are always imported. The prompt arms use `lib.optional (options.programs ? x) (mkIf cfg.prompt.enable {…})` instead: `optional` drops the attrset whole so the path is never named, and the `enable` half stays in `mkIf` because a list whose *length* depends on `config` is an infinite recursion. The MCP arms still carry the latent bug. |
| F22 | The same binary documents progressive disclosure for rules: "Only `always_on` rules are loaded unconditionally." Its own rule template is `---` / `trigger: always_on` / `glob:` / `description:`. | A plain-markdown rule, which is what the plan and `agyLib.mkRule` both emit, is not guaranteed to load. The Antigravity arm prepends `trigger: always_on` frontmatter, so its file is the shared text plus a header rather than byte-identical to `packages.prompt-shared`. The fan-out test asserts suffix plus frontmatter instead of equality. |
| F23 | `remote-pi`'s local broker authenticates nobody, and it is worse than `pi-intercom` on two counts rather than equal. `_handleRegister` does no `SO_PEERCRED`, no uid check, nothing; the `cwd` a client declares is never verified yet is half the routing address (`<cwd>@<name>`); and a client-set `takeover: true` destroys the incumbent peer's socket and hands the caller its exact address. Since the broker then forces `env.from` to the registered address, the anti-spoofing measure becomes the impersonation guarantee. Reproduced against the shipped `dist/session/broker.js`: the attacker got `/home/joe/secret-repo@planner` and the victim was dropped. | Not a reason `remote-pi` beat intercom. It is the risk the hardening task exists to contain. Phase 7 task 3 patches `takeover` to `false` unconditionally; after the patch the attacker is demoted to `…@planner#2` and the victim stays connected. The unverified `cwd` survives hardening and is unfixable without `SO_PEERCRED`, so the task-8 prompt fragment tells the model the sender name is a claim, not a fact. |
| F24 | An inbound peer message calls `sendMessage(..., {triggerTurn: true})` with a `customType` that pi's `convertToLlm` maps to a **user-role** LLM message. `grep -rn triggerTurn` over the whole `dist/` returns two lines and one comment: unlike `pi-intercom`'s `inboundTrigger`, there is no configuration option to disable it. | Any process that can open the socket could start a turn in any session with text the model reads as the operator's, routing around design §9 entirely. Phase 7 task 3 patches it to an env gate defaulting to off, using upstream's own `triggerTurn: false` batching path so the message is still delivered and rendered. |
| F25 | `ensureGlobalDirs()` calls `mkdirSync` with no `mode`, and the socket's permissions come from the umask at `bind()` time. Measured: `0755` on the whole tree under `umask 022`, `0775` under `umask 002`. `broker.js:502` also appends every routed envelope, bodies included, to `audit.jsonl` with no mode. `pi-intercom` sets `0700`/`0600` explicitly. | No patch target exists, so the fix is `umask 0077` in the launcher plus a `chmod 0700` repair for trees left behind by a pre-Nix run. Measured to give `0700` on every directory and on the socket. |
| F26 | `remote-pi`'s local broker is **not** a spawned process. `leader_election.js` races `connect()` against `bind()`; the winner constructs `new Broker(...)` inside its own pi process and a follower re-elects when it exits. | The strongest packaging reason it beat `pi-intercom`, whose broker launches via `npx --no-install tsx`. Nothing to spawn means no `brokerCommand` to rewrite, no `passthru.runtimeInputs`, and no Node+tsx interpreter to fold into the jail, which is also why the bun switch costs phase 7 nothing. |
| F27 | `REMOTE_PI_DIRECT_CONFIG` carries the entire per-directory config as inline JSON and takes precedence over `<cwd>/.pi/remote-pi/config.json`, making `localConfigExists()` true everywhere. `saveLocalConfig` is reachable only from the wizard, `/remote-pi rename`, `/remote-pi setup`, and `remote-pi create`. | The setup wizard never fires and nothing is written into any repository working tree, so the phase-2 passthru contract needs no `configFiles` field. Retires the old assumption A11 about needing to run the wizard once per host. `saveLocalConfig`'s own comment names "NixOS/Home Manager symlink into the immutable Nix store" as a supported case. |
| F28 | `_cmdRootInner` treats `auto_start_relay` as relay-only and says so in its own comment, but the `session_start` auto-init gates the whole lifecycle on it. | With the relay off, which is the configuration phase 7 ships, nothing auto-joins and the user must type `/remote-pi` once per session. Task 4 drops the relay term from that one gate; the `isPrintMode` and `localConfigExists` guards stay. |
| F29 | `remote-pi` declares ten runtime dependencies; a static import-graph walk of `dist/index.js` reaches 42 files and four of them. `@napi-rs/keyring` is a dynamic import that upstream made lazy because it "resolves under Node and not under Bun" (issue #113); `@modelcontextprotocol/sdk` and `zod` belong to the `remote-pi claude` path; `noise-protocol` is imported but **not declared at all**. | `bun install` on the declared set costs 216 packages including `@aws-sdk` and `@anthropic-ai`; the reachable set is 4 packages and 708 KB. `mkPiExtension` gains a `keepDependencies` allowlist. On a Bun-built pi, Tier 2 pairing falls back to a plaintext `0600` `~/.pi/remote/identity.json` rather than the OS keyring. |
| F30 | `--omit=peer` drops `typebox`, which `pi-background-tasks` and `@narumitw/pi-goal` both declare as **non-optional peers** and both `import` at runtime. Verified by installing and looking: `node_modules/typebox` is absent. Every other peer in the phase-2 pin set is `@earendil-works/*` (pi supplies its own) or `optional: true`. | The npm form of the phase-2 plan would have shipped `pi-background-tasks` broken, failing only at load. `mkPiExtension` normalises `package.json` first: hoist every non-`@earendil-works`, non-optional peer into `dependencies`, then `--omit=peer`. A future pin that imports an *optional* peer would still slip through. |
| F31 | `bun install --lockfile-only --omit=dev` writes root dev entries into `bun.lock` without resolving them. The later `bun install --frozen-lockfile --omit=dev` then dies: `error: Failed to resolve root dev dependency '@earendil-works/pi-coding-agent'` (reproduced on `pi-subagents`). | `--omit=dev` is not enough; the normalisation must `del(.devDependencies)` outright before generating the lockfile. Same `jq` program as F30, shared between the update app and the builder so the lockfile one writes is the one the other accepts. |
| F32 | `bun.lock` records only the host platform's variants of an optional native dependency, and `bun2nix` emits one `fetchurl` per lock entry. | A pin generated on `x86_64-linux` produces a `bun.nix` with no Darwin tarballs, so the Darwin build fails. Generate with `bun install --lockfile-only --os='*' --cpu='*'`; the sandboxed `--frozen-lockfile` install still takes only the host's. Any bun2nix consumer in this repo needs both flags. |
| F33 | Deleting `peerDependencies`/`peerDependenciesMeta` *after* hoisting stops bun re-resolving the `@earendil-works` tree transitively. Measured on `@juicesharp/rpiv-todo`: 137 `fetchurl` entries down to 2; `pi-background-tasks` 138 to 3; `@gotgenes/pi-permission-system` 140 to 5. | Worth doing, but it is not uniform. `@narumitw/*` pins stay at ~137 because `@narumitw/pi-tui-kit` pulls the tree through its own `dependencies`, where the rule does not reach. |
| F34 | A4 is false in a way the design did not anticipate. No phase-2 pin ships a self-contained `dist`: `@heyhuynhgiabuu/pi-pretty` publishes `tsc` output but `dist/index.js` still `require`s `@shikijs/cli` and `@ff-labs/fff-node` from `node_modules`. The `bundled = true` branch survives only because `pi-cache-optimizer` has **zero** runtime dependencies. | "Ships a `dist`" is not the test; "needs no `node_modules`" is. Exactly one of eleven pins qualifies, and the phase-2 extension test asserts that so a future bump that adds a dependency to `pi-cache-optimizer` fails at build rather than at load. |
| F35 | Prebuilt `.node` files in the pin set arrive with an empty `RPATH` and `DT_NEEDED` on `libgcc_s.so.1`/`libstdc++.so.6`/`libc.so.6`, none of which resolve on NixOS. Reached transitively: `@yuuang/ffi-rs-linux-x64-gnu` under `@heyhuynhgiabuu/pi-pretty`, and `@napi-rs/keyring` under `pi-mcp-adapter`. | `mkPiExtension` needs `autoPatchelfHook` plus `stdenv.cc.cc.lib`, gated on `isLinux`. Verified sufficient for the whole set (`auto-patchelf: 0 dependencies could not be satisfied`, native modules loading under `node` from the store). `pi-pretty` catches its own failed `import` and degrades quietly, so without the hook the loss would be silent. |
| F36 | bun installs **both** the gnu and the musl build of a napi platform package: `os` and `cpu` cannot express libc. `autoPatchelfHook` then walks the musl `.node` and halts the build — `error: auto-patchelf could not satisfy dependency libc.musl-x86_64.so.1`, reproduced on `@yuuang/ffi-rs-linux-x64-musl` under `@heyhuynhgiabuu/pi-pretty`. | `ffi-rs` selects its variant by detecting libc at load time and never opens that file on a glibc host, so `mkPiExtension` carries a fixed `autoPatchelfIgnoreMissingDeps = [ "libc.musl-x86_64.so.1" "libc.musl-aarch64.so.1" ]`. With it the build succeeds, the gnu `.node` gets a real `RPATH`, and `require("@ff-labs/fff-node")` returns its exports under `node` from the store. A green build still prints `1 dependencies could not be satisfied` followed by a `warn:` line; only the `error:` line means failure. Any bun2nix + autoPatchelf combination in this repo hits this. |
| F37 | `@narumitw/pi-caffeinate` calls `sessionBus()` and sends `Inhibit`/`UnInhibit` to `org.freedesktop.ScreenSaver`; on Linux it first prefers spawning `systemd-inhibit` (`src/inhibitors.ts:28-46`). Upstream's `jail.permissions` default is `[ network mount-cwd ]` plus a bind of `PI_CODING_AGENT_DIR`. | Same class as `pi-notify` needing talk on `org.freedesktop.Notifications`: inert inside the jail, with no error. Phase 3 needs the session bus bound, talk permission on that name, and `systemd-inhibit` via `add-pkg-deps`. Config paths are fine — `pi-caffeinate`, `pi-pretty`, and `pi-cache-optimizer` all write under `getAgentDir()`, which the jail already binds. |

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
