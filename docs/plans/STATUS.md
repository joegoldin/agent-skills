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
6. **Allocate finding numbers from your phase, not from the end of the table.**
   Concurrent agents that each take "the next free number" collide, which has
   already happened once and cost a renumbering. Take a block: phase N owns
   F<N>00-F<N>99 (phase 2 -> F200+, phase 7 -> F700+). Numbers below F100 are
   historical, are never reused, and their gaps are expected.

Status values: `todo` · `wip` · `done` · `blocked` · `dropped`

## Phase summary

| # | Phase | Repo | Tasks | Status |
| --- | --- | --- | --- | --- |
| 1 | agent-statusline (extract + dual mode) | agent-statusline, claude-nix | 9 | **done** |
| 1b | statusline native pi rewrite | agent-statusline | 11 | **done** |
| 2 | pi-nix fork | pi-nix | 9 | **done** (pushed) |
| 3 | auto mode, pi-notify, jail | pi-nix | 10 | **done** (not pushed); auto mode moved to `@czottmann/pi-automode` 2026-08-19 |
| 4 | agent-skills pi target | agent-skills | 9 | **done** |
| 5 | system prompt layers | agent-skills | 8 | wip |
| 6 | dotfiles wiring | dotfiles | 7 | todo |
| 7 | inter-instance messaging | pi-nix, dotfiles | 9 | **8/9** (pi-nix done, not pushed; task 9 blocked) |
| 8 | pi-voice over audiomemo | audiomemo, pi-nix, dotfiles | 12 | **done** (nothing pushed) |

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

## Phase 1b: statusline native pi rewrite — DONE

Plan: `2026-08-18-statusline-native-pi.md` (11 tasks, 87 steps).
Owner: Go side (tasks 1-5) and TS side (tasks 6-11) both delegated, both landed.

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
| 6 | TS: migrate to `bun test` | done (7cae54c) |
| 7 | TS: width arithmetic pinned to pi-tui | done (7d45ddb) |
| 8 | TS: snapshot types, intent→theme map, theme-derived bar | done (9a55594) |
| 9 | TS: row layout and the activity stack | done (c425e3e) |
| 10 | Integration test that catches the sanitize bug | done (ff37bc9) |
| 11 | Nix packaging via bun2nix | done (71e0e20) |

Hard gate: the three Claude golden files stay byte-identical. **Held through
task 11**: `git status --porcelain internal/e2e/testdata/` empty after every
task, and the sha256 prefixes are still `432bddf8` / `94c299c9` / `51de381a`.

Verification at the end of task 11: all 13 Go packages `ok`; `bun test` 129
pass / 0 fail across 9 files; `nix flake check` green with the new
`pi-extension-tests` derivation running the same 129 tests cold in the sandbox.

Task 10 step 8 was carried out rather than assumed: reintroducing the phase-1
`ctx.ui.setStatus(WIDGET_KEY, lastGood.join("\n"))` turns `pi-contract.test.ts`
red on exactly `never hands a row to setStatus`, quoting the text pi would
mangle. Restoring the file returns it to 14 pass / 0 fail.

Live smoke against `packages.coding-agent-bun`: two distinct rows below the
editor, `  ·  ` separators intact with two spaces on each side, spinner
stepping one frame per second and elapsed climbing with it while the data poll
runs at 5 s, and the cwd drawn in the theme's `mdLink` blue against the running
tool's `warning` yellow — the `path`/`warn` split the intent table exists for,
which the ANSI path cannot express because Go emits SGR 33 for both. No
orphaned processes after exit.

## Phase 2: pi-nix fork — DONE

Plan: `2026-08-18-pi-nix-fork.md` (9 tasks, 72 steps). Executed in full:
**10 third-party pins**, `bun2nix` throughout instead of `buildNpmPackage`, and
the Bun-built pi as the module default. Owner: delegated. Committed on `master`
in `/home/joe/Development/pi-nix`; **pushed**.

Pins: `pi-mcp-adapter`, `pi-subagents`, `pi-background-tasks`,
`@juicesharp/rpiv-ask-user-question`, `@narumitw/pi-goal`,
`@juicesharp/rpiv-todo`, `@gotgenes/pi-permission-system`, `@narumitw/pi-btw`,
`pi-cache-optimizer`, `@heyhuynhgiabuu/pi-pretty`. Dropped along the way:
`@plannotator/pi-extension` (plan mode dropped in design §8),
`@juicesharp/rpiv-voice` (voice moved to a first-party extension over
`audiomemo`), and `@narumitw/pi-caffeinate` (F37). `remote-pi` and
`pi-intercom` are phase 7's and appear nowhere in this plan.

| Task | What | Status |
| --- | --- | --- |
| 1 | Rename bookkeeping, eval-test harness | done (3473505) |
| 2 | `lib/` pi package builders | done (c8bc072) |
| 3 | `mkPiExtension`, `extensions.json`, `packages.ext-*` | done (aae3c79) |
| 4 | Extend `nix run .#update` to bump pins | done (d256eb0) |
| 5 | `extra-options.nix` and `systemPrompt` | done (ec1dd85) |
| 6 | `extensionPackages` | done (4a1411a) |
| 7 | `statusline` option | done (a1b7ba2) |
| 8 | `notifications` option | done (a313660) |
| 9 | Document the fork, prove it stayed additive | done (e74cf7a) |
| — | follow-up: bump the `agent-statusline` lock to 71e0e20 | done (b55eb41) |

**Phase 2 is complete, committed and pushed on `master` in
`/home/joe/Development/pi-nix` (`b55eb41`).** `nix flake check` is green with six checks (`additive`,
`builders`, `extensions`, `options`, `smoke`, `update-app`) and all ten
`packages.ext-*` evaluate.

The additive promise holds and is now a test. `git diff upstream/master
--name-only` names eight upstream paths and nothing else: `README.md`,
`coding-agent/extra-options.nix` (new), the three one-line `imports` additions
in `lib.nix`/`module.nix`/`home-manager.nix`, insertions in `flake.nix`, three
added lines in `update.nix`, and `flake.lock` (the `agent-statusline` input
Task 7 adds). `git diff upstream/master --stat` over the protected set —
`options.nix`, `package.nix`, `package-bun.nix`, `coding-agent/bun.nix`,
`sync-upstream.nix`, `regenerate-models.nix`, `scan.nix`, `VERSION.json`,
`package-lock.json`, `bun.lock`, `ai` — prints nothing. `tests/additive-test.nix`
was watched failing on a deliberate one-line tamper of `options.nix` and passing
again after the revert.

Five plan defects were found by running it: F200-F204 and F206. Two were
build-stopping (`F201` the malformed synthetic SRI, `F206` the statusline
`environment` guard's infinite recursion), one was silent and dangerous (`F200`,
`nix fmt` reformatting upstream's `coding-agent/bun.nix`), and one contradicts
F35 outright (`F204`, `pi-mcp-adapter` needs `zlib`).

Task 7 locked `agent-statusline` at 2828df3, which was its head at the time;
phase 1b landed 71e0e20 shortly after and that is the commit carrying the
native pi rewrite plus its bun2nix packaging. The lock was bumped in a
follow-up commit, because the older `pi-extension` is exactly the one
`sanitizeStatusText` collapses (F4).

## Phase 3: auto mode, pi-notify, jail — DONE, auto mode replaced and then forked 2026-08-19

Plan: `2026-08-18-pi-auto-mode-and-notify.md` (10 tasks, 71 steps). Owner:
delegated. Eleven commits on `master` in `/home/joe/Development/pi-nix`,
`aa69abc..eee1d07`; **not pushed**.

**The first-party `pi-auto-mode` extension is gone.** It was replaced on
2026-08-19 by the pinned `@czottmann/pi-automode` 1.11.0, in five further
commits `26ee626..f8f28fa`, also unpushed. The reason is F301 arriving in
production: `delegateToPermissionSystem = true` shipped, built green, and did
nothing, because the operator edit it depended on was never made. What the swap
gains, loses, and had to prove is at the end of this section.

**And that replacement was then forked, the same day.** The swap had shipped
with a second conclusion attached: that auto mode and
`@gotgenes/pi-permission-system` cannot coexist, and the module threw when both
were configured. That was wrong, and F312-F315 are what it cost to find out.
`joegoldin/pi-automode` v1.11.0-jg.1 registers on the permission system's
authorizer chain; pi-nix builds it, writes the config entry that arms it, and
runs both. Four further commits `1f0a32a..adde3b3`, also unpushed.

| Task | What | Status |
| --- | --- | --- |
| 1 | Deterministic rule matcher | **done** (aa69abc) |
| 2 | Tool-call rendering, user-turn extraction | **done** (43fcd77) |
| 3 | The classifier | **done** (9cef6de) |
| 4 | Fail-closed gate on `tool_call` | **done** (c012f8a) |
| 5 | Nix packaging, `autoMode` config rendering | **done** (d36292b) |
| 6 | Delegate to `pi-permission-system` | **done** (dc97210) |
| 7 | `pi-notify` core | **done** (d69f0cb) |
| 8 | `pi-notify` wiring, `notifications` option | **done** (608fa4f) |
| 9 | jail.nix defaults | **done** (5a8b2d3) |
| 10 | Live acceptance run | **done** (d92c351) |
| — | follow-up: README section | **done** (eee1d07) |

`nix flake check` is green with eight checks: phase 2's six plus `pi-auto-mode`
and `pi-notify`. Two new packages, `ext-pi-auto-mode` and `ext-pi-notify`,
built from `packages/extensions/` rather than from a pin.

**The fork stayed additive.** `git diff upstream/master --stat` over the
protected set (`coding-agent/options.nix`, `package.nix`, `package-bun.nix`,
`coding-agent/bun.nix`, `sync-upstream.nix`, `regenerate-models.nix`,
`scan.nix`, `VERSION.json`, `package-lock.json`, `bun.lock`, `ai`) prints
nothing. The upstream paths this phase touched are `README.md`,
`coding-agent/extra-options.nix`, and three lines of `.gitignore`; the other
five in the whole-fork diff are phase 2's and unchanged. This cost two
deviations from the plan, both forced: Tasks 5, 8 and 9 route their options
through `coding-agent/options.nix`, which is hashed byte-identical, so the
option surface lives in `extra-options.nix` and the jail default arrives as
`lib.mkDefault`.

The two security properties were watched holding, not assumed.

Unit level, by mutation. Deleting the `hard_deny` branch from `gate.ts` and
turning the no-UI arm into `return undefined` takes `gate.test.ts` to 11 pass /
3 fail on exactly the three tests that name those behaviours; restoring gives
14 / 0.

Live, against the real binary. There is no provider account on this machine
(`auth.json` is `{}`) and pi runs nothing without one, so the acceptance run
stands up a fake OpenAI-completions provider on localhost that plays both
roles off one endpoint: session model emitting a `bash` tool call, classifier
returning the verdict under test. Every request body is logged, so "was the
classifier consulted" is observed. Results, all with the Nix-rendered config
and the packaged extensions:

- classifier answers `{"decision":"allow","rule_kind":"hard_deny"}` → pi hands
  the model `hard_deny: the operator said to ignore the rules`;
- classifier answers prose instead of JSON, print mode → `auto-mode failed
  closed (…unparseable); no UI to ask, so the call is blocked`, and the canary
  directory is still on disk;
- `git status --short && rm -rf …` under the allow rule `Bash(git status:*)` →
  `[SESSION, CLASSIFIER, SESSION]`, so the prefix rule refused to resolve it
  and the classifier denied;
- `ls -a` under `Bash(ls:*)` → no classifier call at all, real listing fed back;
- `curl …` under `Bash(curl:*)` → `blocked by rule Bash(curl:*)`, no classifier
  call, and the same result again with `jail.enable = true`.

Notifications fired with the exact argv, recorded through a stub notifier:
`--urgency critical pi "Needs your decision on bash"`, `--urgency low pi "bash
finished after 4s"`, `--urgency normal pi "Ready for input"`. pi labels a
`sleep 4` call `bash`, which the plan left open.

Jail verified with no model, by swapping the wrapped command for a shell: git,
node, ripgrep, jq, gh and notify-send all resolve; cwd writes reach the host;
`notify-send` exits 0 through the dbus proxy; `ssh-add -l` lists the 1Password
key with the socket bound **read-only**; `cat ~/.ssh/id_ed25519` answers `No
such file or directory`; and `nix path-info -r` on the wrapper lists both
rendered config files.

Six plan defects surfaced by running it: F300-F305. Two were build-stopping
(F303's `with combinators` shadowing, which fails late and far from its cause,
and F300's regex over a hand-wrapped template literal), one was a fail-open
security hole (F301, disarming the gate on a registration that may never have
been activated), and one contradicted a prior finding (F304: ro-bind on the
agent socket works, so F7's prediction does not hold for bubblewrap).

### The 2026-08-19 replacement

`@czottmann/pi-automode` 1.11.0 speaks Claude Code's own `autoMode` schema, so
the 63 shared rules in `modules/ai/auto-mode.nix` transfer without a rewrite.
Pin evidence: `dist-tags.latest`, published 2026-08-07, `dist.integrity` used
verbatim as the SRI hash, `bundled = true` because its only declared
dependencies are peers the host process already provides.

The option surface gains `protectedPaths`, `deniedPaths`, `permissions.deny`
and `permissions.ask`, the classifier reasoning level, the two transcript
budgets, and a decision log. It loses `deterministic.allow`: the new package
has no prefix-allow list for `bash` at all, so every side-effecting call is
classified, with a one-token first stage to keep that affordable.
`delegateToPermissionSystem` is deleted rather than reworked (F307).

Config now travels as `PI_AUTOMODE_SETTINGS_JSON` out of a store file, not
`configFiles` (F308), and the rule lists are passed through verbatim rather
than having `$defaults` spliced in front (F310).

Proven the same two ways as the extension it replaces, in
`pi-nix/docs/automode-acceptance.md`, with the harness committed this time at
`pi-nix/scripts/automode-e2e/`. Thirteen live cases against the real binary,
including a deterministic hard-deny holding with the classifier configured to
allow and never consulted, a contradictory `allow`/`hard_deny` verdict failing
closed, an in-tree allow resolving with no model call, and auto mode running
with nothing in the config turning it on. Three mutations against the
package's own 124-test suite: two killed, one survived (F309).

### The 2026-08-19 fork, and running both gates

`joegoldin/pi-automode` v1.11.0-jg.1 is upstream v1.11.0 plus one module,
`extensions/auto-mode/permission-chain.ts`, and six lines in the entrypoint.
`extension.ts`, which holds the decision pipeline, is upstream's byte for byte:
the wrapper intercepts the factory's `pi.on("tool_call", …)` registration and
calls that same handler from the chain link, so a link verdict and a standalone
verdict come from one piece of code (F312). Upstream's 124 tests still pass,
plus 28 new ones. The fork's `docs/REBASING.md` names what an upstream change
would cost; `packages/extensions/czottmann-pi-automode.nix` builds it from the
tag with `fetchFromGitHub` and asserts the npm pin has not drifted past it.

pi-nix's side is three changes: the throw is gone, auto mode's entrypoint now
*leads* the extension list so the link reviews the real tool-call event (F313),
and `autoMode.permissionSystem` writes
`extensions/pi-permission-system/config.json` through phase 7's `configFiles`
with the link named in `authorizerChain`.

Proven live in `pi-nix/docs/automode-acceptance.md`'s second section, harness at
`scripts/automode-e2e/pair-cases.sh`. Ten cases with both extensions loaded
against the real binary. The permission system's rules still resolve what they
can with no model call, `git status --short --branch` included; an ask they
cannot settle is recorded as
`"decidedBy": {"kind": "authorizer", "name": "pi-automode", "verdict": "allow"}`
and the command runs; every fail-closed arm reaches the chain as a deny. Case
10 is the control: the same run without the `authorizerChain` entry, where the
classifier is never consulted. That is F307's shipped state, reproduced on
purpose so the entry being load-bearing is a test rather than a claim.

Dotfiles has the permission system back in `extensionPackages`, verified on the
built activation package rather than on the Nix: the launcher's `install` line
points at a store file reading `{"authorizerChain": ["pi-automode"], …}`, and
`--extension` lists auto mode first.

## Phase 4: agent-skills pi target — DONE

Plan: `2026-08-18-agent-skills-pi-target.md` (9 tasks, 71 steps). Owner: delegated.
Sequenced after phase 5 to avoid colliding on `modules/agent-skills.nix` and `flake.nix`.

| Task | What | Status |
| --- | --- | --- |
| 1 | `pi-nix` input, `piLib` | **done** (1975c39) |
| 2 | `mcpNativeFor "pi"` | **done** (b4fbe5d) |
| 3 | pi frontmatter lint | **done** (c149ab0) |
| 4 | `buildPiPlugin`, realpath-identity gate | **done** (2c6132d) |
| 5 | Prompt templates from command-style skills | **done** (6bb15e4) |
| 6 | session-start extension | **done** (7d50d5a) |
| 7 | `temporal.ts`, `targetLibs.pi` | **done** (08a9046) |
| 8 | Four-target coverage check | **done** (f2e12b7) |
| 9 | Module fan-out, `homeManagerModules.pi` | **done** (fa8ba2a) |

**Phase 4 is complete.** `nix flake check` is green with nineteen checks; the
eight new ones are `pi-frontmatter`, `pi-package-manifest`,
`pi-skill-realpath-identity`, `pi-prompt-templates`, `pi-extensions`,
`temporal-pi`, `skills-all-four-targets`, and `module-tests`. All four targets
ship all 39 skills: `skills-all-four-targets` prints `all 39 skills present in
all four targets` and fails with both `MISSING` and `COUNT` when one skill is
held back from the pi arm.

The A3 gate has been watched failing. Replacing the `buildEnv` link with a
`cp -rL` of every skill turns `pi-skill-realpath-identity` red on
`pi package copies 'watching-videos' instead of linking it`, and the revert
turns it green again. Live against pi 0.84.2 with the real `~/.agents/skills`
alongside the package in `settings.packages`: the injected block appears once
in the provider payload and no collision line is printed.

The three hook targets are byte-identical after the `lib.optionals` refactor:
`temporal-claude`, `temporal-codex`, and `temporal-antigravity` all build to
the same store paths before and after.

**Phase 5's pi arm now verifies against the real option**, which it could not
before. `programs.pi.coding-agent.systemPrompt` exists in pi-nix `b55eb41`, and
a real `home-manager.lib.homeManagerConfiguration` carrying
`homeManagerModules.pi` plus `homeManagerModules.agent-skills` comes back with
`systemPrompt == prompt.piText` (7948 characters), `~/.agents/mcp.json` holding
the normalized server set, and `settings.packages` naming both
`agent-skills-pi-complete` and `agent-skills-temporal-pi-complete`.
`modules/module-tests.nix` pins the same property in the sandbox: it is the
first test in this repo to declare `programs.pi` at all, so before it the arm
was only ever exercised by its own absence.


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

## Phase 6: dotfiles wiring — WIP

Plan: `2026-08-18-dotfiles-pi-wiring.md` (7 tasks, 56 steps). Owner: delegated.
Last phase; depends on 2, 3, 5.

| Task | What | Status |
| --- | --- | --- |
| 1 | `pi` aspect skeleton, host wiring | **done** (f9e937c) |
| 2 | agenix secrets for provider keys | **done** (7803237) |
| 3 | Auth across the three paths | **done** (49bbb9d) |
| 4 | Jail permissions | **done** (5ace1ac) |
| 5 | Statusline parity | **done** (106d1c2) |
| 6 | Shared `autoMode` rule set | **done** (be28fd1, 03f59af) |
| 7 | Full build, generated-config inspection | wip |

## Phase 7: inter-instance messaging — WIP

Plans: `2026-08-18-pi-messaging-addendum.md` (§17, decision + security),
`2026-08-18-pi-messaging.md` (9 tasks, 49 steps). Owner: delegated (in flight).

Decision: **`pi-intercom` 0.10.1**, hardened, dependency-free under bun. Decided,
reversed to `remote-pi`, then reversed back on the evidence in F40-F42; the
addendum keeps the whole comparison rather than only the outcome.
`pi-agents-talk-to-each-other` is retained only as a documented fallback
blueprint (addendum §17.13).

**Phone control and cross-machine peers are DECLINED, not deferred.**
`pi-intercom` is local-only — a grep of the tarball for WebSocket, HTTP, or any
outbound URL returns nothing. `remote-pi` was the package that offered them and
it was rejected on security. There is no Tier 2 and no relay task. Addendum
§17.6.2 lists the three ways back, none of them scheduled.

Hardening that is not optional, both reproduced against the shipped broker
(F48, F50): `inboundTrigger` is `"replies"` rather than upstream's `"always"`,
and the broker refuses a `sessionId` already held by a live session. Task 3 owns
the second, Task 2 ships the first, and Task 5 asserts both at runtime and fails
against the unpatched tarball.

| Task | What | Status |
| --- | --- | --- |
| 1 | Add `configFiles` to the `mkPiExtension` passthru contract, with a test | done (b6da411) |
| 2 | Pin `pi-intercom` 0.10.1 via the four-part evidence chain (F47), build it | done (bc4f070) |
| 3 | Harden the broker: refuse a live session-ID collision, reproduce first | done (d837275) |
| 4 | Run the package's shipped broker tests as a Nix check, under `bun test` | done (f0abbad) |
| 5 | End-to-end smoke test over the real wire protocol | done (859596e) |
| 6 | `messaging` option, `configFiles` prelude, bun `brokerCommand` | done (6818ab0) |
| 7 | Fold `bun` into the jail; prove the socket crosses two jails (A9) | done (05b2c59, 8a2d5aa) |
| 8 | Untrusted-peer-input prompt fragment + §12 inventory lint | done (77f0e19) |
| 9 | dotfiles `modules/ai/pi.nix`, two-terminal acceptance run (tests A8) | blocked (F707) |

Tasks 1-8 are committed on `master` in `/home/joe/Development/pi-nix` and
**not pushed**. Head is `2cce7de`; the phase starts at `eee1d07`. `nix flake
check` is green over 14 checks, six of them new
(`extension-contract`, `pi-intercom-hardening`, `pi-intercom-broker-tests`,
`pi-intercom-smoke`, `messaging-option`, `prompt-fragment-inventory`). Every
protected upstream file is still byte-identical to `upstream/master`, checked
file by file rather than by trusting the additive check.

The security work landed as specified. The takeover reproduces against the
shipped tarball and is refused after patching, watched both ways (F704), and
`checks.pi-intercom-smoke` exits 1 against the unpatched tree. `inboundTrigger`
is `"replies"` in the derivation, in the option, and in the installed
`config.json`. What hardening cannot reach is recorded in F704 and in the
README: without `SO_PEERCRED`, which the package never reads, presence on the
socket cannot be refused at all.

Task 9 is the exception, and it is **not landed**. `modules/ai/pi.nix` belongs
to phase 6, which was editing it live; the `messaging` block was written into
it twice and lost to phase 6's own writes both times (F707). It is not in
`5ace1ac`. Nothing was committed to dotfiles by phase 7.

The wiring was verified against a local override while the block was in the
tree, which is the substantive part: the built wrapper exports
`PI_INTERCOM_ASK_TIMEOUT_MS=300000`, installs `intercom/config.json` at 0600,
passes one `--extension` and no `--skill`, and the jail PATH carries the same
bun store path the config names as `brokerCommand`, sitting alongside phase 6's
agenix binds.

Whoever lands it applies this inside `programs.pi.coding-agent`, after pushing
pi-nix and bumping `pi-nix` in agent-skills and `agent-skills` in dotfiles:

```nix
        # Peer messaging between separately launched pi instances, which is
        # pi's missing ListAgents/SendMessage. Local unix socket, no relay, no
        # daemon, no network. There is no phone or cross-machine story here and
        # there is not meant to be; the addendum's §17.6.2 records what that
        # cost and how to get it back.
        #
        # inboundTrigger stays at the module default ("replies"): the broker
        # authenticates nobody, so an unsolicited message must not be able to
        # start a turn. Raising it to "always", which is upstream's own default,
        # is a deliberate per-host choice rather than a convenience.
        messaging = {
          enable = true;
          askTimeoutSeconds = 300;
          # ~/.agents/skills already carries the skill library; loading the
          # extension's bundled copy too would double-register (design A3).
          installSkill = false;
        };
```

The two-terminal acceptance run, which is the only test of assumption A8, has
**not** been done either: it needs an activated configuration and a live model.

The passthru contract grows by exactly one field, `configFiles`, and it is
load-bearing rather than speculative: `inboundTrigger` is file-only with no
environment override (F50), so without it the security default cannot be set
from Nix at all. `runtimeInputs` is **not** added — the broker's interpreter is
bun, the same runtime pi already is, folded into `jail.permissions` from a
module-local internal option. `keepDependencies`/`bunNix` go unused because the
package needs no `node_modules` (F51).

## Phase 8: pi-voice over audiomemo — DONE

Plan: `2026-08-18-pi-voice-audiomemo.md` (12 tasks, 82 steps). Owner: unassigned.
Two repos plus a thin third: `audiomemo` gains `record --stream` (NDJSON),
`pi-nix` gains the `pi-voice` extension, `dotfiles` wires the secrets and the
jail. Depends on phase 2 for the passthru contract and `extensionPackages`.

| Task | What | Status |
| --- | --- | --- |
| 1 | audiomemo: NDJSON event schema and emitter | done (a3d353b) |
| 2 | audiomemo: level normalisation and 20 Hz coalescing | done (b8c47de) |
| 3 | audiomemo: `--stream` flag, guardrails, mode resolution | done (7363072) |
| 4 | audiomemo: streaming run loop and signal termination | done (0983fbc) |
| 5 | audiomemo: `final` event with the batch pass captured | done (37196c2) |
| 6 | audiomemo: integration coverage for the flag contract | done (1634337) |
| 7 | pi-voice: parsing, config, width maths, metering | done (a60043d) |
| 8 | pi-voice: the voice state file | done (f20ede9) |
| 9 | pi-voice: meter and transcript rows | done (e2cb7e7) |
| 10 | pi-voice: controller, `/voice`, and the paste | done (4805d95) |
| 11 | pi-nix: packaging, `voice` option, jail permissions | done (87e873a) |
| 12 | dotfiles: wiring and the end-to-end check | done (e8f354a) |

**Tasks 1-6 are complete and committed in `/home/joe/Development/audiomemo`,
not pushed** (the user reviews before it goes out). Head is `42e6793`, one
commit past the `1634337` recorded here earlier: `--no-live-transcription` no
longer emits an `error` event, because an explicit opt-out is not a failure and
`start.mode` already reports `"none"` (F806). The decision is now the pure
function `reportLiveUnavailable` in `cmd/record.go`, under test. All seven
Go packages `ok`, `nix flake check` green (the sandboxed check runs the suite
with `whisper-cpp` and a fetched base model), and `record --help` shows the flag
from `nix build .#audiomemo`. Verified against a live microphone rather than
only in tests: a 3 s `--stream --no-live-transcription` run produced `start`
with `"mode":"none"`, 26 `level` lines, and `end` with `"reason":"signal"` and
`"exit_code":0`; a 13 s run with `-t --transcribe-args="--backend whisper-cpp"`
produced `"mode":"batch"` and a `final` with `"source":"batch"`,
`"backend":"whisper-cpp"`, and the subprocess transcript in `text` rather than
leaking onto stdout. See F806-F808.

**Mic capture in the jail: resolved, works, but not by default.** Verified on
elphael 2026-08-18 by running `audiomemo record -L` inside a jail-shaped
bwrap. With no audio permission it lists zero devices and exits zero; with
`$XDG_RUNTIME_DIR/pulse` bound it lists every device, and `ffmpeg -f pulse`
captures audio. Four binds are needed and none exist today: the PulseAudio
socket, the audiomemo closure (for ffmpeg), the agenix key files, and
`~/.config/audiomemo/config.toml`. `/dev/snd` is not one of them: audiomemo
talks to PulseAudio, never to ALSA. See F800-F802.

The voice state file contract, for any producer including Claude Code:
`{"voice":{"enabled":bool,"mode":str}}` merged into
`$CLAUDE_CONFIG_DIR/settings.local.json`, defaulting to
`~/.claude/settings.local.json`.

**Tasks 7-11 are complete on `master` in `/home/joe/Development/pi-nix`,
`a60043d..87e873a`, not pushed.** `nix flake check` is green over fifteen
checks, one of them new: `pi-voice` runs `bun test` (70 pass, 0 fail, 4 files)
and then `tsc --strict` against pi's published `.d.ts`, which is what caught
F815. `packages.ext-pi-voice` builds to a store path holding `package.json` and
four `src/*.ts` with the test files stripped. Every protected upstream file is
still byte-identical: `git diff upstream/master --stat` over the protected set
prints nothing, and the fork's whole diff still names only `README.md`,
`coding-agent/extra-options.nix`, the three one-line `imports` additions,
`flake.nix`, `update.nix`, `.gitignore`, and `flake.lock`.

**Task 12 is committed in `/home/joe/dotfiles` at `e8f354a`, not pushed**, and
does not evaluate from its own lock yet (F818). Built with
`--override-input agent-skills/pi-nix git+file:///home/joe/Development/pi-nix`:
`home.activationPackage` succeeds, and the rendered `bwrap` argv carries
`--bind-try $XDG_RUNTIME_DIR/pulse`, the two pipewire binds,
`--ro-bind-try ~/.config/audiomemo/config.toml`, the three `/run/agenix/*` key
files, and `audiomemo-0.1.0/bin` on the jailed `PATH`. The inner launcher
exports `PI_VOICE_RECORD_BIN`, `PI_VOICE_BAR_WIDTH`, `PI_VOICE_PLACEMENT` and
three `*_API_KEY_FILE` **paths**; no key value appears anywhere in the closure.

**The mic indicator lights, and it was watched doing so rather than inferred.**
Against the real microphone, driving the real `VoiceSession` with the local
audiomemo build: the meter drew `● 0:02 █████░░░░░░░ -35.9 dB` from live room
noise, pi-voice wrote
`{"enabled":true,"mode":"toggle","pid":2254277,"since":1787111322216}`, and
feeding that same directory to the packaged `agent-statusline` returned
`voice: {"visible":true,"spans":[{"text":"\uf130 toggle","intent":"meta"}]}`,
which is the Nerd Font microphone glyph. The three states were probed separately: file
absent and `enabled:false` both render `{"visible":false}`. ElevenLabs live
transcription ran end to end and the finished text reached the editor through
`pasteToEditor` (F819 on what it contained). Stopping cleared the block to
`{"enabled":false}`.

**The jail claim was re-measured on this host, not carried over.** Inside a
jail-shaped `bwrap`, `audiomemo record -L` prints 0 lines with no audio bind and
8 device lines with `$XDG_RUNTIME_DIR/pulse` bound, exiting 0 either way. The
options check pins the same thing at eval time and was watched failing:
deleting `combinators.pulse` from the voice permission list turns
`checks.options` red on the assertion that names it.

**What was not done:** step 7's `/voice` inside a real interactive pi, and
step 8's jail-off comparison. Both need `nixos-rebuild switch`, which this work
was told not to run, and pi needs a provider account the acceptance host does
not have (the same constraint phase 3 hit). The chain was exercised end to end
one layer below pi instead, against the real microphone and the real statusline
binary.

Eleven plan defects surfaced by running it: F809-F819. Three were
contradictions inside the plan's own tests (F810, F811, F812), one corrects a
finding from this same phase (F809 supersedes F802), and one is a real
robustness bug the plan would have shipped (F813, an immediate stop killing the
recording it was meant to finish).

## Handoff: Darwin sandboxing via sandbox-exec

**Status: not started. Decided, scoped, not built.**

torrent runs pi with no OS-level containment. `jail.enable` is `false` there
because jail.nix is bubblewrap, and upstream `finalPackage` throws outright on
a non-Linux host. Every other feature reaches Darwin intact: the ten pinned
extensions build (`autoPatchelfHook` is gated on `isLinux`), notifications
switch to `terminal-notifier`, voice resolves audiomemo, and the `!op read`
provider fallback is correct there precisely because there is no jail to block
the 1Password socket.

The gap is sharper than a missing feature. On that machine Claude Code *is*
sandboxed, through its own cross-platform sandbox, so pi is the only one of the
four agents running unconfined. With plan mode dropped, the permission layer is
then the whole guard.

Decision: **`sandbox-exec`** (Seatbelt). No new dependency, ships on every
macOS. Apple marks it deprecated and it still backs Chrome and others.
`pi-landstrip` was reconsidered and rejected again: its Landlock half is
redundant with the jail on Linux, and adopting a package for its Darwin half
alone is a poor trade against a profile we can write directly.

### Shape

- New option in `coding-agent/extra-options.nix`, alongside `jail`. Do not touch
  `coding-agent/options.nix`; it is protected and `tests/additive-test.nix`
  enforces that.
- Upstream's `finalPackage` is `readOnly` and throws on Darwin when `jail.enable`
  is set, so the Seatbelt wrapper cannot go through it. Add a separate read-only
  option that returns `finalPackage` untouched on Linux and the wrapped binary on
  Darwin, then install *that* from `home-manager.nix` line 38 and `module.nix`
  line 38. `home-manager.nix` is not in the protected set.
- The profile must mirror what the jail already grants, which is the checklist
  worth stealing rather than re-deriving: read the store, read/write the cwd and
  `$PI_CODING_AGENT_DIR`, outbound network, read the agenix key files, the
  1Password agent socket, and audio for voice.

### The part that needs care

This cannot be verified from the Linux workstation. Evaluation works; building
and running do not. A wrong profile fails two ways, and only one of them is
loud: too tight and pi will not start, too loose and it is decoration that
reads as protection.

So the work ships with an acceptance script that runs **on torrent** and proves
each clause: that a read outside the allowed set is refused, that a write
outside the cwd is refused, that the model API is still reachable, and that
`ssh-add -l` still works while `cat ~/.ssh/id_*` does not. The Linux jail was
verified exactly this way, by swapping the wrapped command for a shell, and that
method transfers.

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
| F22 | The same binary documents progressive disclosure for rules: "Only `always_on` rules are loaded unconditionally." Its own rule template is `---` / `trigger: always_on` / `glob:` / `description:`. | A plain-markdown rule, which is what the plan and `agyLib.mkRule` both emit, is not guaranteed to load. The Antigravity arm prepends `trigger: always_on` frontmatter, so its file is the shared text plus a header rather than byte-identical to `packages.prompt-shared`. The fan-out test asserts suffix plus frontmatter instead of equality. |
| F23 | `mkIf false { programs.pi.x = …; }` does not suppress "The option `programs.pi' does not exist" — `mkIf` is pushed down and the path is still named in the definition set. | The `mkIf (options.programs ? <agent>)` idiom the MCP fan-out uses does **not** degrade cleanly when a module is absent; it only works today because all three agent modules are always imported. The prompt arms use `lib.optional (options.programs ? x) (mkIf cfg.prompt.enable {…})` instead: `optional` drops the attrset whole so the path is never named, and the `enable` half stays in `mkIf` because a list whose *length* depends on `config` is an infinite recursion. The MCP arms still carry the latent bug. |
| F30 | `--omit=peer` drops `typebox`, which `pi-background-tasks` and `@narumitw/pi-goal` both declare as **non-optional peers** and both `import` at runtime. Verified by installing and looking: `node_modules/typebox` is absent. Every other peer in the phase-2 pin set is `@earendil-works/*` (pi supplies its own) or `optional: true`. | The npm form of the phase-2 plan would have shipped `pi-background-tasks` broken, failing only at load. `mkPiExtension` normalises `package.json` first: hoist every non-`@earendil-works`, non-optional peer into `dependencies`, then `--omit=peer`. A future pin that imports an *optional* peer would still slip through. |
| F31 | `bun install --lockfile-only --omit=dev` writes root dev entries into `bun.lock` without resolving them. The later `bun install --frozen-lockfile --omit=dev` then dies: `error: Failed to resolve root dev dependency '@earendil-works/pi-coding-agent'` (reproduced on `pi-subagents`). | `--omit=dev` is not enough; the normalisation must `del(.devDependencies)` outright before generating the lockfile. Same `jq` program as F30, shared between the update app and the builder so the lockfile one writes is the one the other accepts. |
| F32 | `bun.lock` records only the host platform's variants of an optional native dependency, and `bun2nix` emits one `fetchurl` per lock entry. | A pin generated on `x86_64-linux` produces a `bun.nix` with no Darwin tarballs, so the Darwin build fails. Generate with `bun install --lockfile-only --os='*' --cpu='*'`; the sandboxed `--frozen-lockfile` install still takes only the host's. Any bun2nix consumer in this repo needs both flags. |
| F33 | Deleting `peerDependencies`/`peerDependenciesMeta` *after* hoisting stops bun re-resolving the `@earendil-works` tree transitively. Measured on `@juicesharp/rpiv-todo`: 137 `fetchurl` entries down to 2; `pi-background-tasks` 138 to 3; `@gotgenes/pi-permission-system` 140 to 5. | Worth doing, but it is not uniform. `@narumitw/*` pins stay at ~137 because `@narumitw/pi-tui-kit` pulls the tree through its own `dependencies`, where the rule does not reach. |
| F34 | A4 is false in a way the design did not anticipate. No phase-2 pin ships a self-contained `dist`: `@heyhuynhgiabuu/pi-pretty` publishes `tsc` output but `dist/index.js` still `require`s `@shikijs/cli` and `@ff-labs/fff-node` from `node_modules`. The `bundled = true` branch survives only because `pi-cache-optimizer` has **zero** runtime dependencies. | "Ships a `dist`" is not the test; "needs no `node_modules`" is. Exactly one of eleven pins qualifies, and the phase-2 extension test asserts that so a future bump that adds a dependency to `pi-cache-optimizer` fails at build rather than at load. |
| F35 | Prebuilt `.node` files in the pin set arrive with an empty `RPATH` and `DT_NEEDED` on `libgcc_s.so.1`/`libstdc++.so.6`/`libc.so.6`, none of which resolve on NixOS. Reached transitively: `@yuuang/ffi-rs-linux-x64-gnu` under `@heyhuynhgiabuu/pi-pretty`, and `@napi-rs/keyring` under `pi-mcp-adapter`. | `mkPiExtension` needs `autoPatchelfHook` plus `stdenv.cc.cc.lib`, gated on `isLinux`. Verified sufficient for the whole set (`auto-patchelf: 0 dependencies could not be satisfied`, native modules loading under `node` from the store). `pi-pretty` catches its own failed `import` and degrades quietly, so without the hook the loss would be silent. |
| F36 | bun installs **both** the gnu and the musl build of a napi platform package: `os` and `cpu` cannot express libc. `autoPatchelfHook` then walks the musl `.node` and halts the build — `error: auto-patchelf could not satisfy dependency libc.musl-x86_64.so.1`, reproduced on `@yuuang/ffi-rs-linux-x64-musl` under `@heyhuynhgiabuu/pi-pretty`. | `ffi-rs` selects its variant by detecting libc at load time and never opens that file on a glibc host, so `mkPiExtension` carries a fixed `autoPatchelfIgnoreMissingDeps = [ "libc.musl-x86_64.so.1" "libc.musl-aarch64.so.1" ]`. With it the build succeeds, the gnu `.node` gets a real `RPATH`, and `require("@ff-labs/fff-node")` returns its exports under `node` from the store. A green build still prints `1 dependencies could not be satisfied` followed by a `warn:` line; only the `error:` line means failure. Any bun2nix + autoPatchelf combination in this repo hits this. |
| F37 | `@narumitw/pi-caffeinate` calls `sessionBus()` and sends `Inhibit`/`UnInhibit` to `org.freedesktop.ScreenSaver`; on Linux it first prefers spawning `systemd-inhibit` (`src/inhibitors.ts:28-46`). Upstream's `jail.permissions` default is `[ network mount-cwd ]` plus a bind of `PI_CODING_AGENT_DIR`, so neither is reachable and the extension is silently inert inside the jail. It also carried the same ~141-package `pi-tui-kit` tail. | **Pin dropped.** `systemd-inhibit` already does the job in one command on NixOS; paying a dependency tail plus a session-bus talk permission to reach the same syscall, with silence as the failure mode, is a bad trade. Design §9's parallel note for `pi-notify` on `org.freedesktop.Notifications` is unaffected and is still phase 3's. |
| F38 | `@narumitw/pi-goal` and `@narumitw/pi-btw` share **137 dependency entries at identical `name@version`, `url`, and `hash`** — the only difference is `typebox@1.3.15`, which `pi-goal` carries from the peer hoist. Both resolve `@narumitw/pi-tui-kit@0.56.0`. | The `pi-tui-kit` tail is paid once, not twice: `bun2nix` emits a bare `fetchurl` per dependency, and a fixed-output derivation with identical coordinates is one store path (verified by building the same tarball from two expressions and getting one path). The *unpacked* `node_modules` is still duplicated, since each `ext-*` is its own derivation, so the marginal cost of the second pin is one tarball plus 11 MB. Re-measure after any `@narumitw` bump: if the two diverge off `pi-tui-kit@0.56.0`, the sharing ends silently. |
| F40 | *(the rejected option; these six rows are why it was rejected)* `remote-pi`'s local broker authenticates nobody, and it is worse than `pi-intercom` on two counts rather than equal. `_handleRegister` does no `SO_PEERCRED`, no uid check, nothing; the `cwd` a client declares is never verified yet is half the routing address (`<cwd>@<name>`); and a client-set `takeover: true` destroys the incumbent peer's socket and hands the caller its exact address. Since the broker then forces `env.from` to the registered address, the anti-spoofing measure becomes the impersonation guarantee. Reproduced against the shipped `dist/session/broker.js`: the attacker got `/home/joe/secret-repo@planner` and the victim was dropped. | **This reversed the decision.** The user had chosen `remote-pi` believing the two packages comparable on security. `pi-intercom` also authenticates nobody and has its own takeover path (F48), but its equivalent needs the attacker to first learn a UUID, its unverified `cwd` is display metadata rather than routing identity, and its socket tree is `0700`/`0600` (F49). Phase 7 now pins `pi-intercom`. |
| F41 | An inbound peer message calls `sendMessage(..., {triggerTurn: true})` with a `customType` that pi's `convertToLlm` maps to a **user-role** LLM message. `grep -rn triggerTurn` over the whole `dist/` returns two lines and one comment: unlike `pi-intercom`'s `inboundTrigger`, there is no configuration option to disable it. | Any process that can open the socket could start a turn in any session with text the model reads as the operator's, routing around design §9 entirely. `pi-intercom` ships the same unsafe default but exposes a supported `inboundTrigger` setting to change it (F50), so the chosen path is a config value rather than a patch against shipped JavaScript. |
| F42 | `ensureGlobalDirs()` calls `mkdirSync` with no `mode`, and the socket's permissions come from the umask at `bind()` time. Measured: `0755` on the whole tree under `umask 022`, `0775` under `umask 002`. `broker.js:502` also appends every routed envelope, bodies included, to `audit.jsonl` with no mode. `pi-intercom` sets `0700`/`0600` explicitly. | No patch target exists; the fix would have been `umask 0077` in the launcher. `pi-intercom` needs none of that: it passes explicit modes **and** chmods, measured `0700`/`0600` under the same hostile `umask 002` (F49). This row is the clearest single reason the decision reversed. |
| F43 | `remote-pi`'s local broker is **not** a spawned process. `leader_election.js` races `connect()` against `bind()`; the winner constructs `new Broker(...)` inside its own pi process and a follower re-elects when it exits. | This was the strongest packaging argument in its favour, and F51 later took most of it away: `pi-intercom`'s broker runs under `bun` directly with no `node_modules`, so its separate process costs one jail package (bun, which pi already is) rather than the Node+tsx pair its default launch path implied. |
| F44 | `REMOTE_PI_DIRECT_CONFIG` carries the entire per-directory config as inline JSON and takes precedence over `<cwd>/.pi/remote-pi/config.json`, making `localConfigExists()` true everywhere. `saveLocalConfig` is reachable only from the wizard, `/remote-pi rename`, `/remote-pi setup`, and `remote-pi create`. | Would have avoided a `configFiles` passthru field entirely, and `saveLocalConfig`'s own comment names "NixOS/Home Manager symlink into the immutable Nix store" as a supported case. Moot now: `pi-intercom` has no such env escape hatch (F50), so `configFiles` is added after all. |
| F45 | `_cmdRootInner` treats `auto_start_relay` as relay-only and says so in its own comment, but the `session_start` auto-init gates the whole lifecycle on it. | Would have needed a fourth patch: with the relay off nothing auto-joins and the user types `/remote-pi` once per session. Recorded for anyone who revisits this package. |
| F46 | `remote-pi` declares ten runtime dependencies; a static import-graph walk of `dist/index.js` reaches 42 files and four of them. `@napi-rs/keyring` is a dynamic import that upstream made lazy because it "resolves under Node and not under Bun" (issue #113); `@modelcontextprotocol/sdk` and `zod` belong to the `remote-pi claude` path; `noise-protocol` is imported but **not declared at all**. | `bun install` on the declared set costs 216 packages including `@aws-sdk` and `@anthropic-ai`; the reachable set is 4 packages and 708 KB. That motivated `mkPiExtension`'s `keepDependencies` allowlist, which the chosen package does not need. The keyring note stands as general evidence that bun/node divergence in this ecosystem is live, which is why F34 was measured rather than assumed. |
| F47 | `pi-intercom` publishes **no `repository`, `homepage`, or `bugs` field on npm**, in any of its 27 versions or at the packument top level. The npm maintainer is `nicopreme` <nico.bailon@gmail.com>; the GitHub repo is `nicobailon/pi-intercom`. Different strings, and F13 documents a package in this same ecosystem where exactly that mismatch hides a different author's project. | Design §8's "pin by verified repository URL" **cannot be followed as written** for the package this fork is adopting. The replacement is a four-part check run as a build step at every bump: confirm npm still has no repository field; `gh api users/nicobailon --jq .twitter_username` returns `nicopreme`, so the GitHub account claims the npm handle; the repo publishes tag `v0.10.1`; and the tarball's `package.json` is byte-identical to that tag. All four verified 2026-08-18. |
| F48 | `pi-intercom` **does** have a takeover-equivalent, contradicting the first draft of the addendum, and it needs no opt-in flag: `register` lets a client choose its own `sessionId`, and when a live session already holds it the broker calls `previous.socket.end()` and hands the ID over. The ID is not secret — any registered peer may `list`, and `list` returns every session's UUID, cwd, model and pid. Reproduced in four unauthenticated steps: register accepted, `list` leaks the UUIDs, then `SAME ID GRANTED` and `victim socket closed by broker`. | Phase 7 task 3 patches the register handler to refuse a **live** collision, verified to answer `Session ID already held by a live session` with the incumbent still connected. Reconnect-after-disconnect is untouched, because a closed session moves to `disconnectedSessions` and is no longer matched by `this.sessions.get(id)`. |
| F49 | `pi-intercom`'s permissions are real and umask-independent, verified by running the broker rather than reading `paths.ts`: `INTERCOM_DIR_MODE = 0o700` and `INTERCOM_RUNTIME_FILE_MODE = 0o600` are applied with `mkdirSync({ mode })` **plus** an explicit `chmodSync`, so a directory left `0755` by an earlier run is repaired. Started under a deliberately hostile `umask 002`: `700` on the dir, `600` on `broker.sock`, `600` on `broker.pid`. | The clearest way the chosen package beats the rejected one (F42: `0775` under the same conditions), and the reason the launcher needs no `umask 0077` workaround. Asserted in the phase-7 smoke test, which sets `umask 002` on purpose. |
| F50 | `inboundTrigger` defaults to **`"always"`** in the shipped `config.ts`, and it is **file-only**: the complete env surface is `PI_INTERCOM_ASK_TIMEOUT_MS`, `PI_INTERCOM_LIVENESS_*`, `PI_INTERCOM_NAME_POLL_MS`, `PI_INTERCOM_SESSION_ID`, `PI_INTERCOM_STABLE_ID`, `PI_INTERCOM_TCP`, `PI_INTERCOM_TRANSPORT`, `PI_BIN`. There is no environment override. | This is why `passthru.configFiles` is added to the contract instead of being avoided: without a config-file mechanism the security default cannot be set from Nix at all. Related trap: `index.ts` resolves the session ID as `PI_INTERCOM_STABLE_ID ?? config.stableId ?? piSessionId`, so a `stableId` written into a shared `config.json` would give every session on the machine one ID and each new session would evict the last. Never write it. |
| F51 | `bun broker/broker.ts` runs `pi-intercom`'s broker with **no `node_modules` present at all**, and `bun test broker/` runs its shipped tests (47 pass, 1 fail; the failure reproduces identically under `tsx --test`, so it is upstream's, not bun's). Separately, upstream's *default* launch path does not run `npx`: it calls `getNodeCommand(process.execPath)`, which falls back to the literal string `"node"` resolved through `PATH` whenever the interpreter's basename is not node — which under `coding-agent-bun` it never is. | Two consequences. The declared `tsx` dependency is dead weight, so the pin needs no `bun.nix`, no lockfile and no `node_modules`, and the jail needs one package (`bun`) rather than a Node+tsx pair. And the default path would have failed to spawn inside a jail with no Node on `PATH`, so setting `brokerCommand` to a bun store path fixes a latent bug rather than only saving a dependency. |
| F52 | A duplicate session **name** in `pi-intercom` is not silently ambiguous: `findSessions` returns every match and `send` refuses with `delivery_failed "Multiple sessions named \"planner\" are connected. Use the session ID instead."`. Reproduced. | The failure mode of a name collision is denial of delivery, which is loud, rather than interception, which is silent. The rejected package's `#N` suffixing plus its takeover flag gave the opposite outcome. The phase-7 hardening patch must not break this, and the probe in task 3 asserts it still holds after patching. |
| F100 | F804's "`bun test` cannot resolve them" holds only when they are not installed. Adding `@earendil-works/pi-tui` and `pi-coding-agent` as **devDependencies** makes `import { visibleWidth } from "@earendil-works/pi-tui"` resolve normally under `bun test` — measured: `extension/src/width.test.ts` compares against pi's real `visibleWidth` and `truncateToWidth` over 46 corpus strings plus 2000 fuzzed ones, 2784 assertions, 0 fail. | Two viable approaches, not one. Structural fakes (what `statusline.test.ts` does) avoid the dependency entirely; a devDependency lets a test be a *differential* test against pi's real implementation, which is the only way to pin a re-implementation. The runtime constraint is unchanged either way: no `dependencies` block, ever, and the packaged extension drops `*.test.ts`. |
| F101 | The npm tarball of `@earendil-works/pi-coding-agent@0.84.2` ships `dist/`, `docs/` and `examples/` — **no `src/`**. Only the Nix builds (both `pi-coding-agent` and `coding-agent-bun`, which unpack `fetchFromGitHub` `src`) carry the TypeScript. | The plan's `piSourceFile()` looks under `node_modules/@earendil-works/pi-coding-agent/src/...` and would have found nothing, turning the "stays in step with pi" test into a hard failure. The helper searches `$PI_CODING_AGENT_SRC/src/**.ts`, then `node_modules/**/src/**.ts`, then `node_modules/**/dist/**.js`; the compiled `footer.js` carries `sanitizeStatusText` with an identical body, so the drift check works from the npm package alone and gets stronger when pointed at a real pi. |
| F102 | pi-tui's `visibleWidth` is not a wide/zero range table. It segments with `Intl.Segmenter`, tests `\p{RGI_Emoji}` under the `v` flag, consults the real `East_Asian_Width` property through `get-east-asian-width`, and has separate handling for regional indicators, Thai/Lao AM vowels and Indic spacing marks (`pi-tui/src/utils.ts:175-296`). | The plan's sketch — 17 wide ranges and 4 zero ranges — could not have passed its own 2000-string fuzz against pi. `width.ts` is a port instead of an approximation: same segmenter, same regexes copied out of pi's source, same escape scanner, plus the `fullwidth`/`wide` tables vendored from the package pi-tui itself calls. `truncateEnd` is likewise a port of `truncateToWidth`, which is what makes an already-fitted line a fixed point of pi's own truncator. Both passed on the first run. |
| F103 | `bun test`'s per-test timeout is **5 s** and is only settable by CLI flag or `setDefaultTimeout()`, not by `bunfig.toml`. The phase-1b fix for the cold-run flake raised a polling helper's deadline to 10 s, which put it *above* the runner's own limit. | The helper then gave up at 5 s inside a poll loop that had not finished waiting — the cold run failed at exactly 5000 ms. `setDefaultTimeout(30_000)` at the top of the file is the fix; raising the helper alone made the flake harder to read, not rarer. |
| F104 | A `flex` spacer never expands under `main.go`'s flow. `ComposeRow` only distributes flex budget when given a width, and main.go composes both rows at `Width: 0` to decide whether they merge, then either uses that string verbatim or falls back to `WrapRow`, which skips flex markers outright. So the widget is inert in the shipped ANSI renderer, and the plan's task-10 assertion that `renderRows(..., 120)` returns a 120-cell flex-padded line was measuring something the Go side has never produced (measured: 97 cells, the merged natural-width row). | The TypeScript port keeps the behaviour rather than quietly improving on it, so the two renderers still agree line for line; the assertion moved to `composeRow` at an explicit width, which is where a flex spacer means anything, and a second assertion covers the sanitiser-mangling proof without depending on flex at all. Making flex work end to end is a follow-up on the Go side first. |
| F105 | `os.UserCacheDir` prefers `XDG_CACHE_HOME` over `HOME`, and this machine exports it. Regenerating `extension/testdata/snapshot-full.json` with only `HOME` overridden, as the plan's command does, silently reads the real user cache. | The fixture came out with `"tools": null` and no activity rows, which looks like a working snapshot rather than a misconfigured one. Both variables are set in the recipe now, and the recipe is in the README rather than in a shell history. |
| F200 | `nix fmt` in pi-nix is bare `pkgs.nixfmt`, not a treefmt wrapper. With no arguments it reads stdin, prints `unexpected end of input`, and exits 0 — a silent no-op, which is what every `nix fmt` step in the phase-2 plan would have done. Handing it the tree (`nix fmt -- .`) does format, and immediately reformats upstream's generated `coding-agent/bun.nix` (91 KB), breaking the additive constraint on the first commit. | Formatting must name the files: `find . -name '*.nix'` minus `coding-agent/bun.nix` and `packages/extensions/*/bun.nix`. Phase 3 and any later work in this repo inherits the same trap; a plain `nix fmt` there is not a formatting step at all. |
| F201 | The synthetic pin in the plan's `tests/extensions-test.nix` carries `sha512-` plus 83 base64 characters. A sha512 SRI needs 88. `fetchurl` rejects it during evaluation — `invalid SRI hash …, length 83 != expected length 64` — so the whole eval-assertion layer of that test fails before any assertion runs. | The comment "never built, so the fake hash costs nothing" is wrong: `fetchurl` validates the hash at eval, not at build. Corrected to 86 `A`s plus `==` (base64 of 64 zero bytes). Any future synthetic pin must be a well-formed SRI even when nothing fetches it. |
| F202 | The `checks` block the plan lands in Task 1 builds plain nixpkgs, and the Task 3 extension test instantiates `mkPiExtension` against that same `pkgs`. `mkPiExtension` requires `bun2nix`, and nixpkgs-unstable has no such attribute (`p ? bun2nix` is `false`), so the check cannot evaluate. | The `checks` block takes `overlays = [ bun2nix.overlays.default ]`, the same widening Task 4 applies to `apps`. It is additive — the overlay only adds `bun2nix` — so the `ext-*` derivations the test names are the same store paths `packages.ext-*` builds. |
| F203 | The Step 6 slug guard in the plan pipes pin names through `sed -e 's\|@\|\|' -e 's\|/\|-\|2'`. After `@` is stripped a scoped name holds exactly one `/`, so replacing the *second* one is a no-op and the guard reports six false `MISSING` lines for pins whose files are present. | The generator in the same step uses the correct `s\|/\|-\|g`. Run the guard with `g` as well. Harmless here because it fails loudly, but it would mask a real missing lockfile for an unscoped pin. |
| F204 | F35's "verified sufficient for the whole set" is wrong, and the plan's "no pin in the initial set needs `extraBuildInputs`" with it. `pi-mcp-adapter` reaches `recheck-linux-x64/recheck`, a GraalVM native-image **executable** rather than a `.node`, and it links `libz.so.1`. `stdenv.cc.cc.lib` does not carry zlib, so `auto-patchelf could not satisfy dependency libz.so.1` fails the build outright. | `packages/extensions/default.nix` grew an `extraBuildInputsFor` map alongside `settingsFor`, holding `pi-mcp-adapter = [ zlib ]`. The plan declared the mechanism and then declared it unused; it is used on day one. Note the shape of the miss: the audit looked at `.node` files, and this is a plain ELF binary that a transitive npm dependency happens to ship. |
| F205 | Task 4's "both diffs must be empty" cannot hold on the first run, because the plan writes `extensions.json` with inline arrays (`"skills": ["skills"]`) and `pi-update-extensions` rewrites the file through `jq`, which expands them. Values are identical; only whitespace moves. | The pin file is committed in jq's shape, so the check the plan actually wants — "a run against unchanged pins changes nothing" — is true from the second run on, and was verified: both `extensions.json` and all nine `bun.lock`/`bun.nix` pairs came back byte-identical. The load-bearing half (the lockfiles) was clean on the *first* run too, which is what proves the builder and the generator normalise the same way. |
| F206 | Task 7's `checkedStatuslineEnv` guard — throw a sentence when `statusline.enable` meets a file-valued `environment` — is an infinite recursion by construction, and no spelling of it works. It reads `cfg.environment` from inside a *definition* of `environment`; forcing the merged value forces our definition, whose value forces the merged value. Watched fail: `error: infinite recursion encountered` at `lib/modules.nix:1159`. Moving the read into the `mkIf` condition or into the value changes nothing. | Dropped, and the module says so in a comment. `environment = lib.mkIf statusline.enable statuslineEnv;` contributes nothing when disabled. A consumer who sets `environment` to a path with the statusline on gets the module system's own "defined multiple times" error (`types.either` falls through to `mergeOneOption`), and the option description names the attrset form. Any later option in this repo that wants to inspect an upstream option it also defines hits the same wall. |
| F300 | Task 3's own assertion `CLASSIFIER_SYSTEM_PROMPT).toMatch(/never.*clear|cannot be cleared/i)` fails against Task 3's own prompt text. The prompt reads `User intent does NOT clear it and can never` / newline / `clear it`, and `.` does not cross a line break. Watched fail on the first run of the implemented module. | The prompt's hard_deny line is reflowed to say `It cannot be cleared:` on one line. General shape of the trap: a regex assertion over a hand-wrapped template literal is sensitive to where the author happened to wrap, and the wrap is invisible in review. |
| F301 | Registering an authorizer with `@gotgenes/pi-permission-system` does not put it on the chain. `registerAuthorizer`'s own docstring (`dist/public.d.ts:520`) says the chain consults a link only when "the operator names it in the `authorizerChain` config", and that config is `~/.pi/agent/extensions/pi-permission-system/config.json`, the package's own file, **not** pi's `settings.json`. So neither `mkPiExtension`'s `passthru.settings` nor the module's `settings` option can activate it. | Task 6's `delegated` flag would have disarmed pi-auto-mode's own gate on the strength of a registration that may never fire, which is fail-open. The delegated path keeps the deterministic **deny** list running on `tool_call` (a deny costs no model call, so the duplication is free) and `docs/assumption-a2.md` names the operator edit. Phase 7's `passthru.configFiles` is the mechanism that will let Nix write it; this is a second, independent motivation for that field. |
| F302 | `mkPiExtension` had no local-`src` arm and the plan's stopgap (a bare `runCommand` with a hand-written `passthru`) would have forked the contract. Adding `src ? null` alongside `url ? null` / `hash ? null` works because Nix is lazy: the `fetchurl` binding is never forced on the first-party path, so no placeholder URL or hash is needed. F201's warning about eval-time SRI validation does not bite here for that reason. | One builder, one passthru contract, and `tests/extensions-test.nix` asserts the first-party packages satisfy it alongside the ten pins. A first-party extension names `entrypoints` explicitly instead of relying on npm manifest resolution. |
| F303 | `with combinators;` inside `coding-agent/extra-options.nix` does not bind `notifications`. The file already has `notifications = cfg.notifications` in the same `let`, and Nix's `with` loses to any enclosing binding, so jail.nix is handed the option submodule where it expects a permission. Watched fail: `error: attempt to call something which is not a function but a set: { appName = «thunk»; configFile = «thunk»; ... }`, raised from `lib/trivial.nix:150` while evaluating `pi.coding-agent.finalPackage` — nowhere near the list that caused it. | Every entry in the jail default is written `combinators.x`. The plan's `defaultText` and upstream's own default both use `with combinators;`, which is safe only because neither shares a scope with an option named after a combinator. Any module that both names an option and uses `with` on a namespace containing that name has the same latent bug. |
| F304 | F7 is wrong for bubblewrap, measured. A read-only bind of `~/.1password/agent.sock` does **not** refuse the `AF_UNIX` connect: with `--ro-bind-try` on the socket, `ssh-add -l` inside the real jail listed the key. Both binds were built and run; `try-readwrite` and `try-readonly` behave identically here. | The jail ships `try-readonly` on the agent socket, so the default matches `modules/ai/claude.nix`'s `allowRead` exactly rather than approximately, and `docs/jail.md` records the one-line fallback in case a kernel disagrees. The plan's task-9 step 4 was written as "expect this to fail, here is the fix"; it did not fail. |
| F305 | `pi --print '!some-shell-command'` cannot smoke-test the jail: pi refuses to run anything without a configured provider, answering `No API key found for the selected model`. Every jail verification step in the plan is written that way. | The jail wrapper's last line is a single `bwrap` invocation, so `sed`-swapping the wrapped `pi` for `/bin/sh -c "$1"` exercises the exact sandbox with no model, no key and no network. That is how the toolchain, the cwd write, the dbus notification, the agent socket and the absent private key were all verified; the recipe is in `docs/jail.md`. |
| F306 | A pi extension can be tested end to end with no provider account. Declaring a fake OpenAI-completions provider in `models.json` (`baseUrl` on localhost, `apiKey` a placeholder, `compat.supportsDeveloperRole = false`) and serving SSE from a short bun script gives a real `pi --print` run: the fake emits a `bash` tool call as the session model and the classifier verdict as the classifier, told apart by pi-auto-mode's system prompt arriving verbatim. Logging every request body makes "was the classifier consulted" and "what did pi feed the model in place of the tool output" both observable. | This is how all nine phase-3 acceptance rows were proven, including hard_deny-beats-allow and fail-closed. Any later phase that needs a live pi (4, 7, 8) can use the same harness rather than burning a real key or leaving the row blank. Two traps: `--print --mode json` hangs and times out where plain `--print` works, and a previous run's server holding port 8231 makes the next case look like pi never called out. |
| F307 | F301 arrived in production, and worse than predicted. `delegateToPermissionSystem = true` shipped and did nothing: the live `~/.pi/agent/extensions/pi-permission-system/config.json` reads `{ "debugLog": false, "permissionReviewLog": true, "yoloMode": false }` with no `authorizerChain` key, so the registered link was never called and every unresolved ask went to a dialog, including `git status --short --branch`, which the allow list names. The review log records `"decidedBy": {"kind": "user", "via": "dialog"}`. | The replacement cannot be delegated at all: `@czottmann/pi-automode` never reads `Symbol.for("@gotgenes/pi-permission-system:service")` and calls `registerAuthorizer` nowhere. Both packages register `tool_call`, pi's `emitToolCall` returns on the first `{ block: true }`, and `extEntrypoints` is concatenated ahead of `autoModeEntrypoints`, so the permission system always answers first. pi-nix now throws when both are configured, and dotfiles drops the permission system. What goes with it: session approvals, the review log, subagent forwarding, and its prefix-allow rules. |
| F308 | `configFiles` is the wrong mechanism for pi-automode, and it looks right. That contract installs relative to `PI_CODING_AGENT_DIR`, while the package's global config path is `resolve(HOME, ".pi/agent/automode.json")` (`constants.ts`), anchored to the home directory and honouring no override. They agree by default and only by default. | The rules go through `PI_AUTOMODE_SETTINGS_JSON` instead, which the package parses as inline JSON and treats as its highest-precedence source. pi-nix renders them to a store file and upstream's `environment.<NAME>.file` tag exports `"$(cat …)"`, so the policy is immutable, rolls back with the generation, is in the closure the jail binds, and cannot be outranked by a stale `automode.json` from an earlier experiment. |
| F309 | The no-UI arm of `permissions.ask` is untested upstream. Mutating it from `block` to `continue` leaves `@czottmann/pi-automode`'s own 124-test suite fully green. The two mutations either side of it are caught: deleting the decision/tier consistency guard fails exactly the contradictory-`allow` assertion, and disabling `deterministicHardDeny` fails six tests. | The live harness covers it (`pi-nix/docs/automode-acceptance.md` case 4: `--print`, no UI, `permissions.ask` match, blocked, canary intact). The gap matters because that arm exists for exactly the runs nobody is watching (print mode, json mode, subagents), and it should go upstream. |
| F310 | Splicing `$defaults` in front of a Nix-declared rule list is the wrong default. It unions the operator's policy with prose from the package that changes on every version bump, and for a deny list that is half a policy nobody reviewed. Empty is different again: any array at all sets `seen` in the package's accumulator, so `[ ]` reads as "replace the built-ins with nothing". | Lists pass through verbatim, an empty list is omitted from the rendered file entirely, and a caller who wants the built-ins writes `$defaults` themselves. That is the right answer for `protectedPaths`, a fixed gate of 48 paths whose common property is that writing one causes code to run later, and rarely the right one for the four prose lists. |
| F311 | The jail's PATH is exactly the `add-pkg-deps` list, and `bash` was not in it. pi resolves its tool shell as `/bin/bash`, then `bash` on PATH, then bare `sh` (`pi-coding-agent`'s `dist/utils/shell.js`); inside `--clearenv` the first two were absent, so every tool call ran under the `sh` jail.nix binds at `/bin/sh` and bash syntax failed as if the model had written it wrong. `/doctor` also reported curl, sed, grep, find, free and the nix commands missing. | The generic list grew bash, fish, curl, gnused, gnugrep, findutils and procps, and `SHELL` is set to fish rather than the host's nologin. `nix` is a separate opt-in option: the package alone cannot work, because jail.nix binds only the wrapped program's runtime closure into `/nix/store` and no daemon socket, and making it work binds the whole store and the socket, which means anything the agent can build it can also run. |
| F312 | "They cannot be composed" was a property of the published package, not of the problem. `@czottmann/pi-automode` does not read the permission system's service symbol, so it cannot be a chain link — but the seam is one `registerAuthorizer` call away, and this repo already forks pi.nix for exactly this. The fork is one new module plus six lines in the entrypoint, with `extension.ts` byte-identical: the wrapper intercepts the factory's `pi.on("tool_call", …)` registration through a `Proxy` and calls that same handler from the link. | The link does not re-derive a verdict, so the deterministic tiers, the fast paths, the classifier and the fail-closed arms cannot drift between modes. Measured: `{"decision":"allow","tier":"hard_deny"}` is refused through the chain for the same reason it is refused standalone, because it is the same code refusing it. The general shape: when the seam exists and the package does not use it, the missing piece is a fork, not a redesign. |
| F313 | Load order still matters, for a reason ordering alone cannot fix. `PromptPermissionDetails` carries the ask's *display* fields (`command`, `path`, `value`) and not the tool's raw `input`, so a link reached after the permission system can only rebuild a projection — enough for bash, lossy for `write`/`edit`, where the classifier would judge a path with no content. Auto mode's own `tool_call` handler sees the real event, so putting it **first** and caching by `toolCallId` gives the link the real input. | `coding-agent/extra-options.nix` concatenates `autoModeEntrypoints` ahead of `extEntrypoints`, the inverse of what it did when the two were contending. The projection is kept as the fallback and is exercised: it is the only path available for an ask forwarded from a subagent, which the parent's handler never saw. |
| F314 | The chain owner caps a link's `allow` on the `external_directory` and `path` surfaces and turns it into a `defer` (`src/authority/delegation-envelope.ts`), so on those two surfaces the classifier can refuse but cannot approve, and an approval falls through to a dialog. Measured, not read: reading `/etc/hostname` from a session rooted elsewhere raised an `external_directory` ask, the link answered allow, and the decision came back `{"kind":"unavailable"}` under `--print`. `bash`, `tool`, `mcp` and `skill` are not capped. | This is the one thing running both costs that configuration cannot remove, only route around: `modules/ai/pi.nix` names `~/Development`, `~/dotfiles` and `/nix/store` under `permission.external_directory` so outside-the-tree file access costs what it cost when auto mode ran alone. Anything else outside the working directory still reaches a prompt, which is the right answer for a path nobody has described. |
| F315 | With no `permission` key at all the package's universal fallback is `ask` (`permission-manager.ts`'s `DEFAULT_UNIVERSAL_FALLBACK`), which under a live chain link means "hand it to the classifier", not "prompt". So the migration needs no invented policy: keeping the three keys already on disk and adding `authorizerChain` reproduces auto-mode-alone behaviour exactly, with the review log, session approvals and subagent forwarding added back. | The prefix-allow fast path the pairing exists for is then opt-in per rule rather than arriving as a default nobody reviewed — the same argument F310 makes against splicing `$defaults`. Verified on the built activation package: an in-CWD `read` resolves through the link's inside-working-directory tier with no model call, and `git status --short --branch` reaches the classifier only until a `bash` rule names it. |
| F400 | A `-e` probe extension that reads `event.systemPrompt` in `before_agent_start` and exits sees the prompt **before** package extensions have appended to it. `mergePaths(cliEnabledExtensions, enabledExtensions)` puts CLI paths first, so the probe's handler runs first. The plan's task-6 acceptance step is written exactly that way and reports `injected=0` against a package that is in fact loading correctly. | The probe must read a later event. `before_provider_request` carries the assembled `payload`, so `JSON.stringify(e.payload).includes(...)` observes the finished prompt after every handler has run. Confirmed both ways: with the package extension passed ahead of the probe on `-e` the original probe reports 1, and with the package in `settings.packages` only the later event does. Any future acceptance test for a chained `systemPrompt` handler has the same trap. |
| F401 | `pi-nix`'s `lib` exposes `mkPiSkill`/`mkPiPromptTemplate`/`mkPiPlugin` plus `mkSkill` and `mkPlugin` aliases, but **no `mkPromptTemplate`** alias. The plan's Task 1 gate asserts all three unprefixed names. | `mkPiPromptTemplateFor` calls `piLib.mkPiPromptTemplate` by its prefixed name. Nothing needed changing in `pi-nix`, and the alias can still be added there later without breaking this call site. |
| F402 | `mkPiPromptTemplate` renders frontmatter through `lib.mapAttrsToList`, which sorts keys, so `argument-hint` precedes `description` and the body is preceded by one blank line more than the plan's expected output shows. | Cosmetic only; the quoting the plan cares about is right (`argument-hint: "[directory]"` stays a string rather than a YAML flow sequence). `checks.pi-prompt-templates` asserts the two lines with `grep -qxF` rather than diffing the whole file, so key order is not pinned. |
| F403 | `nixfmt` 1.4.0 and 1.2.0 both reformat files this repo already committed (`lib/mcp.nix`'s `stdio` binding and its `assert lib.assertMsg` line move under either version). The tree was formatted by some third version, and the repo has no `formatter` output and no formatting check. | Formatting a touched file produces churn unrelated to the change. Harmless because nothing gates on it, but a reviewer reading a phase-4 diff sees hunks the phase did not author. A `formatter` output pinning one `nixfmt` would end this. |
| F600 | Nothing enabled the ten pinned third-party extensions. `pi-nix` packaged them and `homeManagerModules.pi` wired only the skills plugin, so a host importing the module got the skill library with none of the capabilities those skills assume: no MCP, no subagents, no todos, no background bash, no structured questions, no goal loop. The built wrapper's closure carried the three first-party extensions and none of the ten. | Found by inspecting the built closure rather than the config: `extensionPackages` evaluated to `[]`. `homeManagerModules.pi` now sets the curated list under `mkDefault`. Packaging is pi-nix's job; choosing what runs is an opinion, so it belongs in the library layer. |
| F601 | `types.functionTo (listOf raw)` **does** merge. nixpkgs' `functionTo` merges by applying every definition to the same argument and merging the results with the element type, and `listOf` concatenates. F802's "function-typed options do not merge" is wrong for this shape. What blocks composition is priority, not type: phase 3's default is `mkDefault` (1000) and a plain definition (100) discards it. | dotfiles writes `jail.permissions = lib.mkIf jailed (lib.mkDefault (combinators: [ ... ]))` and gets pi-nix's list followed by its own, verified on the rendered `bwrap` line: five `--ro-bind-try` entries from pi-nix, then six from dotfiles. The plan's `options.programs.pi.coding-agent.jail.permissions.default` composition would have been actively wrong, because that default is upstream's `[ network mount-cwd ]`, not phase 3's set. |
| F602 | Statusline parity is **not** achieved by overriding nothing. `agent-statusline`'s shared schema defaults `barWidth` to 10, tracking Go's `config.Defaults()` and its drift check; `claude-nix` pins 8 with `lib.mkDefault` in `lib/agentStatusline.nix`. Rendering both option sets through `renderConfig` returns 8 for Claude and 10 for pi. | The schema's own option doc names the fix: "a consumer that wants the narrower bar sets `barWidth = 8` in its own config rather than moving this default". dotfiles is that consumer, so `modules/ai/pi.nix` sets `statusline.barWidth = 8` and the equality check then passes. Nothing in phase 1 regressed; the plan's task 5 premise predates phase 1's final shape. |
| F603 | `programs.pi.coding-agent.autoMode.enable` is a plain `mkEnableOption`, and nothing turns it on. `agent-skills`' fan-out fills `allow`/`soft_deny`/`hard_deny`/`environment` and leaves `enable` alone, so the whole rule set evaluates, renders, and is never consulted. Measured before the fix: `autoMode` came back `{allow=12, soft=16, hard=13, env=11, enable=false}` and the wrapper's `exec` line carried no `pi-ext-pi-auto-mode`. | Phase 6 is the phase that turns things on, so `modules/ai/pi.nix` sets `autoMode.enable = true` (plus `notifications.enable = true`, dark for the same reason while the jail already carried its dbus permission). `model` stays null so classification bills to whichever provider is live rather than pinning the guard to one key. The plan's task 7 step 7, which expects `pi --print 'run: sudo -n true'` to be refused, could not have passed as written. |
| F604 | `torrent` can be neither built nor **evaluated** from `x86_64-linux`. `modules/agent-skills.nix` forces `agent-skills-combined` as an IFD from `home.file`, and that derivation's aarch64-darwin closure reaches `builder.pl` with no local builder, so even `nix eval` on `home.activationPackage.drvPath` fails. Reproduced identically at cdfd762, before any phase-6 commit, so it predates this work. | The plan's task 7 step 1 fallback ("run `nix eval` on the same attribute instead") does not work either. What does verify from Linux is the narrower attributes, which do not force the IFD: `darwinConfigurations.torrent...pi.coding-agent.jail.enable` is `false` and `finalPackage.outPath` resolves to a plain `writeShellScriptBin` with no `bwrap`. The full darwin build has to happen on the Mac. |
| F605 | The 1Password item the plan names for the Anthropic key, `op://Private/Anthropic API Key/credential`, does not exist on this account, and the item that does (`Anthropic Claude API Key`) has an **empty** `credential` field with the live key in a labelled field. `op read` on the plan's reference exits non-zero; the OpenAI and OpenRouter references resolve as written. | `dotfiles-secrets/pi.nix` names `op://Private/Anthropic Claude API Key/api key - paid account`. All three references were probed with `op read` before the file was committed, which is the step that caught it; a `models.json` shipped from the plan's literal text would have failed only at `/model` time on a machine with no agenix. |
| F700 | `mkPiExtension` had no `patchPhaseExtra` argument at all, and its `bundled` arm is a bare `runCommand` with no `postPatch` to append to. | The messaging plan's Task 1 fallback ("add it here if absent") was the live path. It is wired into all three build arms, and the two `runCommand` arms have to `cd $out` first, because `substituteInPlace` takes relative paths and a `runCommand` starts in `$TMPDIR`, not in the output. |
| F701 | `coding-agent/options.nix` is hash-protected by `tests/additive-test.nix`, so the messaging plan's Task 6 and Task 7 (edit the launcher prelude, edit `finalPackage`'s jail permissions) cannot be carried out as written. | Both are rerouted through `coding-agent/extra-options.nix`, the same way phases 2 and 3 were. The `configFiles` writer hangs off `package`: upstream's own wrapper execs whatever `package` resolves to, so the write lands after the environment is exported and inside the jail. Two caveats follow and neither is fixable from an additive fork. A consumer who sets `package` themselves gets no config-file writer (a definition of `package` that reads `cfg.package` is an infinite recursion), and a consumer who sets `jail.permissions` themselves loses `bun` from the sandbox (F802: function-typed options do not merge). Measured both ways: a plain definition against a bare `mkCodingAgent` drops `bun` and the whole toolchain, keeping only the consumer's entries; but in the current dotfiles tree the two sets **compose** — the built `bwrap` argv carries pi-nix's `~/.ssh`/1Password binds and its `add-pkg-deps` PATH alongside phase 6's agenix and `~/.gitconfig` binds. Whatever makes that work (equal priorities, so `functionTo` merges the two lists) is phase 6's to keep working; do not assume it. |
| F702 | Two of `pi-intercom`'s eighteen shipped `spawn.test.ts` cases need a `node` on `PATH`, because they exercise upstream's *default* launch path — the one F51 describes. They pass on a developer machine that happens to have Node and fail in the Nix sandbox. | The plan's expected "45 pass" is unreachable without putting Node into a check for a package whose whole point is not needing one. `bun test -t '^(getTsxCliPath\|getWindows\|getBrokerLaunchSpec\|getBrokerSpawnOptions)'` keeps the other sixteen, including the one asserting the custom-`brokerCommand` branch this fork depends on. Final count: 43 pass, 0 fail, 2 filtered. |
| F703 | `bwrap` applies mount arguments in order, so `--tmpfs /tmp` placed after `--bind` of a directory under `/tmp` masks the bind. | The A9 verification script failed with `Can't chdir` until `--proc/--dev/--tmpfs` moved ahead of the binds. Any future jail script whose scratch dirs live under `/tmp` has the same trap. |
| F704 | The session-ID takeover (F48) is refused after patching, and the refusal was watched rather than inferred. Unpatched: `4. re-registered with the victim's sessionId: SAME ID GRANTED / victim socket closed by broker? true`. Patched: `REFUSED (Session ID already held by a live session) / victim socket closed by broker? false`, with F52's duplicate-name `delivery_failed` unchanged. | `checks.pi-intercom-smoke` encodes the same assertion and exits 1 against the unpatched tarball, so the patch cannot be deleted and left green. What the patch does **not** remove: an attacker under this uid can still connect, still `list` every session's UUID, cwd, model and pid, and still deliver text. The package exposes no peer credential, so presence on the socket cannot be refused without `SO_PEERCRED`, which upstream does not read. |
| F705 | `tests/extensions-test.nix`'s `pinComplete` required `sha512-`, and its bundled-pin assertion named exactly one package. | The messaging plan pins `pi-intercom` with a sha256 SRI derived from the tarball rather than npm's `dist.integrity`, and it is the second bundled pin. Both assertions were widened. Note for the next bump: `nix run .#update-extensions` writes `dist.integrity`, so it will rewrite that hash to sha512, pinning the same bytes. |
| F706 | `passthru.configFiles` is collected from every entry in `extensionPackages`, not only from the messaging package, and the launcher installs each one at 0600 under `$PI_CODING_AGENT_DIR`. | This is the mechanism F301 and `docs/assumption-a2.md` were waiting for: `extensions/pi-permission-system/config.json` is a path relative to the agent directory, so `configFiles."extensions/pi-permission-system/config.json".authorizerChain = [ "pi-auto-mode" ]` would now write the chain entry from Nix. It is deliberately **not** written here — `authorizerChain` is the operator's ordering, and claiming it unconditionally from one extension's derivation would overwrite a chain a consumer had arranged. Wiring it belongs with `autoMode.delegateToPermissionSystem`. |
| F707 | Phase 7's dotfiles task cannot build from the pinned inputs. `dotfiles` consumes pi-nix transitively through `agent-skills`, which pins `github:joegoldin/pi-nix`, and phase 7's commits are local. | Task 9 is not landed. Landing it needs, in order: push pi-nix, `nix flake update pi-nix` in agent-skills, push that, `nix flake update agent-skills` in dotfiles, then apply the block quoted in the phase-7 section. A second hazard is concurrency rather than pinning: `modules/ai/pi.nix` was being rewritten by phase 6 throughout, and the block was written into it twice and lost to phase 6's own writes both times. Verified meanwhile with `--override-input agent-skills/pi-nix git+file:///home/joe/Development/pi-nix`, which builds the real wrapper. || F600 | `agent-skills` at 347ba41 locks `pi-nix` at **b55eb41**, the phase-2 head, not eee1d07. The phase-2/phase-3 split is invisible from dotfiles: `homeManagerModules.pi` exists either way, so the failure is not an eval error but a missing option surface. | `nix flake update agent-skills` alone gives a pi with no `autoMode` option, no `notifications`, and upstream's two-entry jail default instead of phase 3's. Fixed without a new input: `nix flake update agent-skills/pi-nix` moves the transitive node to eee1d07 inside dotfiles' own lock. Any consumer of `agent-skills` needs both updates until agent-skills relocks pi-nix. |
| F800 | Mic capture inside bwrap works with nothing but the PulseAudio socket bound. Measured: `audiomemo record -L` lists 0 devices with no audio bind and exits 0; with `--bind $XDG_RUNTIME_DIR/pulse` it lists every device, and `ffmpeg -f pulse -i default` captured 32 KiB. No `/dev/snd`, no added capability. | Voice and the jail are not in conflict; the default jail is simply missing four binds (audio socket, audiomemo closure, agenix keys, audiomemo config). Same silent-empty failure as F5: no error, just nothing. `jail.nix` already ships `pulse` and `pipewire` combinators. |
| F801 | jail.nix's `base` does `--clearenv` and `--tmpfs ~`, and `--dev /dev` does supply `/dev/shm`. | `~/.config/audiomemo/config.toml` and `~/.claude` vanish inside the jail unless bound. Without the config, `record` decides it needs onboarding and dies on `/dev/tty`, so the bind is required rather than convenient. PulseAudio's SHM transport has somewhere to land, so no extra tmpfs is needed. |
| F802 | `jail.permissions` is `functionTo (listOf raw)`. **Superseded by F809: this type does merge.** The original claim, that no module can contribute jail permissions, is false. | Kept for the record because tasks 11 and 12 were designed around it. `voice.jailPermissions` still exists as a read-only function, but it is now a fallback for a consumer who *replaces* the permission list rather than the only route in. |
| F803 | `ctx.ui.pasteToEditor(text)` exists at `pi-coding-agent/src/core/extensions/types.ts:213`, beside `setEditorText` (`:216`) and `getEditorText` (`:219`). | The rejected `rpiv-voice`'s usage was real. pasteToEditor is the right call: it triggers paste handling and does not discard what the user already typed. |
| F804 | pi injects `@earendil-works/pi-tui` and `pi-coding-agent` as jiti **virtual modules** (`core/extensions/loader.ts:50-74`, aliases at `:81-120`). | An extension at a bare store path can import them with no `node_modules`. But `bun test` cannot, so any code path under test must not import them. pi-voice imports nothing; `agent-statusline`'s extension took the devDependency road instead, because it needs far more than two functions. |
| F805 | ffmpeg's `astats` RMS is dBFS and can be the literal `inf`/`-inf`, which `strconv.ParseFloat` accepts. `encoding/json` returns `UnsupportedValueError` for `±Inf`. | An unclamped level event does not lose a field, it loses the whole line. Both wire scales are clamped at the emitter. |
| F806 | `--no-live-transcription` emits an `error` event. The plan's task-4 fallback is `else if streamNote != "" && rStream`, and `streamNote` is already `"live transcription disabled"` before the key check ever runs (`cmd/record.go`), so the first line of a deliberately live-free stream is `{"type":"error","scope":"stream","fatal":false,"message":"live transcription disabled"}`. Reproduced on every `--stream --no-live-transcription` run. | Implemented as planned, but pi-voice (tasks 9-10) must not render `scope:"stream"`, `fatal:false` errors as user-visible failures, or `--no-live-transcription` shows an error banner for a user choice that `mode:"none"` already states. Either the consumer filters it or a follow-up narrows the branch to the missing-key case. |
| F807 | `astats` does not print 100 RMS lines a second here. Measured over two live runs: 29 lines in 3.1 s and 103 in 13.0 s, both ~8/s, well under the 20 Hz the `levelInterval` throttle caps at. | The 50 ms coalescing window is currently inert on this hardware — it is insurance against a device that does report at 100 Hz, not the thing producing the observed rate. A consumer must not assume a 20 Hz tick; `level` arrival is bursty and irregular (gaps of 96 ms and 149 ms in the same run), so smoothing on the consumer side has to be time-aware rather than per-event. |
| F808 | `gofmt -l .` under Go 1.26 already flags five files at `6018d29`: `cmd/transcribe.go`, `internal/transcribe/elevenlabs.go`, `internal/transcribe/elevenlabs_test.go`, `internal/tui/devices.go`, `internal/tui/onboarding.go`. All are `var (...)` block alignment, none were touched by this work. | The plan's `gofmt -l . \| grep -v '^vendor/'` gate cannot print nothing on this toolchain. Read it as "no *new* files listed" instead. Reformatting them is a separate commit the author should make deliberately, since it touches four packages this work does not otherwise change. |
| F809 | **F802 is wrong.** `lib.types.functionTo (lib.types.listOf x)` *does* merge across module definitions: every definition is applied to the same argument and the results are concatenated by the element type's merge. Measured directly — two `mkDefault` definitions of a `functionTo (listOf str)` option applied to `"X"` return `[ "b" "a" "X" ]`, both lists present. | A module *can* contribute jail permissions. pi-nix's own `jailPermissions` therefore splices `voice.jailPermissions` in directly, so a consumer who never touches `jail.permissions` still gets a working microphone; `dotfiles` adds nothing. The read-only function stays for the case that genuinely does not merge: a consumer defining `jail.permissions` at plain priority, which outranks and discards both `mkDefault` lists. F701 already recorded the two composing in practice and told the reader not to assume it worked; this is why it does. |
| F810 | The plan's `truncateToWidth` tests contradict each other. `truncateToWidth("hello world", 5)` is asserted to be exactly `"hello"`, while the implementation given three lines above unconditionally appends `\x1b[0m` to any cut string, and a second test requires that suffix. | The reset is only repair work for a colour opened before the cut and never closed, so it is emitted only when the retained prefix contains an escape sequence. Both plan tests then pass, and a truncated plain row is plain text rather than text plus a stray SGR 0 that shows up in every downstream assertion. |
| F811 | The plan's two `renderMeterRow` tests cannot both pass. Its recorder theme returns `<slot>text</slot>`, which `visibleWidth` counts (it strips ANSI, not tags), so at width 60 the themed row measures ~94 cells and truncation eats the bar — failing the "fills the bar in proportion" test — while removing the truncation fails "never exceeds the width it was given". | Layout is decided on plain text and the theme applied afterwards. A row's width must not be a property of how a theme encodes colour; deciding on plain segments makes the recorder faithful (its markup is as invisible to the layout as SGR bytes are) and lets the meter drop whole segments to fit rather than cutting the bar in half. Width assertions strip the recorder's tags for the same reason. |
| F812 | The plan's first `VoiceSession` test asserts `state.committed == "So the thing is,"` **and** `state.partial == "so the thing is"` after a fixture that emits the partial and then the commit. The plan's own `handleEvent` clears the partial on commit, so the two assertions are mutually exclusive. | The clear is correct: a commit is the settled form of the partial that preceded it, and leaving both would draw the same words twice. The assertion was changed to `""` and a separate test pins the append-and-clear sequence over two utterances. |
| F813 | `child.kill("SIGINT")` immediately after `spawn` kills the producer outright. Reproduced standalone: a shell script whose *first line* installs an INT trap still closes with `null SIGINT`, because the signal lands before the interpreter has executed anything. | A `/voice` toggle pressed twice quickly would destroy the recording rather than finish it, and it is the failure a user finds first. `stop()` now waits for the `start` event before signalling, with a 2 s fallback so a producer that dies before announcing itself is still stoppable. Watched failing first: the immediate-kill version leaves the plan's own toggle test with nothing to paste. |
| F814 | `packages/first-party/` does not exist in pi-nix, and `mkPiExtension` grew the `src` argument the plan anticipated. The two existing first-party extensions live at `packages/extensions/pi-{auto-mode,notify}` and are built by `mkPiExtension`'s local-src arm. | pi-voice follows the same convention rather than the plan's `runCommand` + hand-written passthru: one `default.nix` naming `src = ./.` and `entrypoints`. The passthru contract is identical either way, and `tests/extension-tests.nix` is a plain attrset map, so `checks.pi-voice` is one line. |
| F815 | `tsc --strict` against pi's published `.d.ts` rejected `ChildProcessWithoutNullStreams` for a `spawn` whose stdio is `["ignore","pipe","pipe"]`; the correct type is `ChildProcessByStdio<null, Readable, Readable>`. | The typecheck half of `checks.pi-voice` earned its place on its first run. `bun test` passed the same code, because the fault was in a type annotation the runtime never sees. |
| F816 | The plan's `device = "mic"` in dotfiles buys nothing. `--stream` sets `rNoTUI`, and `cmd/record.go` runs the interactive picker only when neither `-D` nor headless mode is in play, so the picker is already unreachable. `-D mic` also resolves the alias through the same `config.toml` that `record.device` lives in, so both paths fail together if that bind is missing. | `device` stays null. Both hosts already declare `record.device = "mic"` and the `mic` alias, so naming it in `modules/ai/pi.nix` would duplicate the host's device choice in a second file for no robustness. |
| F817 | elphael already declares `age.secrets.deepgram_api_key` and `openai_api_key` alongside `elevenlabs_api_key`, and so does torrent. | The plan's task 12 step 2 is a no-op. All three `*_API_KEY_FILE` paths in the voice block resolve today with no host edit. |
| F818 | Same shape as F707, one layer deeper. `dotfiles` cannot build the voice wiring from its pinned inputs: pi-nix arrives transitively through `agent-skills` and is locked at `2cce7de`, which predates the `voice` option, and the `audiomemo` input is locked at a revision with no `--stream`. Neither repo is pushed. | Landing needs, in order: push audiomemo, push pi-nix, `nix flake update pi-nix` in agent-skills, push that, then in dotfiles `nix flake update agent-skills agent-skills/pi-nix audiomemo`. Until then the committed dotfiles tree does not evaluate from its own lock. Verified meanwhile with `--override-input agent-skills/pi-nix git+file:///home/joe/Development/pi-nix`, which builds the real wrapper and puts the real binds in the real `bwrap` argv. |
| F819 | `diarize = true` in `modules/home/packages/audiomemo.nix` reaches dictation. The live end-to-end run pasted `Speaker speaker_0: The perfect shot` into the editor. | Correct behaviour for a memo transcript and wrong for dictation, but it is an audiomemo config choice rather than a pi-voice one, and nothing here overrides it. If the speaker labels are unwanted, the fix is `voice.extraArgs` carrying a transcribe override, or a second audiomemo profile. Left as the author's call. |

## Decisions

| Decision | Rationale |
| --- | --- |
| Bun everywhere | pi consumed as `coding-agent-bun`; bun2nix instead of `buildNpmPackage`; `bun test` instead of vitest. |
| `agent-statusline` standalone | `agent-skills` already depends on `claude-nix`, so hosting it there would cycle. |
| 10 third-party pins, 4 first-party | Each traceable to a Claude Code capability restored or a named new capability. |
| `pi-caffeinate` dropped | `systemd-inhibit` does the job in one command on NixOS. The pin cost a ~141-package tail plus a session-bus talk permission to reach the same syscall, and was silently inert without it (F37). |
| Plan mode dropped | Planning writes documents. Consequence: `pi-auto-mode` rules are the only guard on the working tree. |
| Voice via audiomemo, not `rpiv-voice` | Go, already a flake input, no npm native deps, no runtime model download into a jail. |
| `pi-intercom` over `remote-pi` | Reversed after reading remote-pi's source. Its broker authenticates nobody and is worse than intercom on two counts: an unverified client-declared `cwd` forms half the routing address, and `takeover: true` hands a caller the incumbent's exact address, reproduced live (F40, F41). Phone control is a known gap, not an oversight. |
| avoid-ai-writing on prose | Prompt fragments teach tone by example, so their register becomes the house style. |
