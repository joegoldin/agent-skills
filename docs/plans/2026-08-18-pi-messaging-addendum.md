# Design addendum: inter-instance messaging for pi

Date: 2026-08-18
Status: **decided**. `pi-intercom` 0.10.1, hardened. Revised twice; see below.
Extends: `docs/plans/2026-08-18-pi-nix-agent-stack-design.md` as **§17**, a
seventh subsystem alongside `agent-statusline`, `pi-nix`, permissions/sandbox,
`pi-notify`, the `agent-skills` pi target, and the prompt fragments.

> **Revision history, because the reasoning matters more than the outcome.**
>
> 1. First draft recommended `pi-intercom` on adoption evidence.
> 2. The user overruled it and chose `remote-pi` in local mode, partly for its
>    phone-control growth path. This document was rewritten around `remote-pi`,
>    and that rewrite included reading `remote-pi`'s shipped source and running
>    its broker.
> 3. That reading produced findings F40-F42: `remote-pi` authenticates nobody,
>    ships an unauthenticated `takeover` flag that evicts a live peer and hands
>    over its exact address, hardcodes `triggerTurn: true` with no configuration
>    knob, and creates its whole socket tree `0755` (`0775` under `umask 002`).
>    On that evidence the user reversed the decision back to `pi-intercom`.
>
> The `remote-pi` analysis is **kept in full** (§17.4.2). It is not dead weight:
> it is the record of the comparison, and §17.6.3 names exactly what choosing
> `pi-intercom` gives up. Everything asserted about `pi-intercom` in §17.4.1 and
> §17.9 has now been held to the same standard — read from the shipped tarball
> and reproduced by running it, not read from its README.

## 17. Inter-instance messaging

### 17.1 Context

The main spec catalogues six things pi omits and assigns each an ecosystem
answer (§1, §8). It misses a seventh, because the gap is not one of pi's
documented omissions. It is a capability Claude Code has that no one thinks to
enumerate: **separately launched agent processes can address each other by
name.**

This is distinct from subagents. §8 pins `pi-subagents` for the child-process
axis: one session spawns workers, workers return results, the tree collapses.
Phase 3 delivers it. Inter-instance messaging is the *peer* axis: two pi
processes the user started independently, in different terminals, possibly in
different repositories, each with its own long-lived context, talking to each
other while both remain alive. `pi-subagents` cannot do this and is not
intended to; a child is not a peer.

### 17.2 The capability gap

Claude Code exposes three things over one substrate:

| Claude Code | What it does |
| --- | --- |
| `Agent` | spawn a named agent with a fresh context |
| `ListAgents` | enumerate live agents and their state |
| `SendMessage` | address a *previously spawned* agent by ID or name, with its context intact |

pi has none of the three natively. §8 covers the first with `pi-subagents`. The
second and third have no assignment at all.

**A correction to the brief, stated plainly.** `dispatching-parallel-agents` and
`subagent-driven-development` do **not** name `SendMessage` or `ListAgents`.
`grep -rn "SendMessage\|ListAgents" --include='*.md'` over `agent-skills`
returns zero hits. Their hard dependency is fan-out dispatch, which §11 already
assigns to `pi-subagents`. So the skills do not break without messaging.

What they lose is the mid-flight half, and it is not small:

- `subagent-driven-development` runs implementer → reviewer → fix subagent in a
  loop and tells the coordinator not to pause between tasks. Without a peer
  channel, an implementer that hits real ambiguity has exactly one move:
  fail the task and report BLOCKED. It cannot ask.
- `dispatching-parallel-agents` dispatches N agents concurrently and reviews
  them only on return. Without a peer channel, an agent visibly heading the
  wrong way runs to completion and wastes the whole budget.

Both are the same missing primitive: *reach a running agent*. Claude Code's
`SendMessage` supplies it; pi supplies nothing.

There is also a plain user-facing case with no Claude Code analogue at all:
hand findings from a research session in one repo to an execution session in
another, without copy-pasting through the terminal.

### 17.3 Candidates

Everything below was measured on **2026-08-18**. npm figures are the week
2026-08-09 → 2026-08-15 from `api.npmjs.org/downloads/point/last-week`;
repository figures from `gh repo view` and the `Link: … rel="last"` header on
`/commits?per_page=1`. `pi-subagents` (56,532 dl/wk) is included only as a
scale reference; it is the phase-3 pin, not a messaging candidate.

| Package | Transport | External infra | dl/wk | ★ | Last publish | Ver. | Commits | License | Outcome |
| --- | --- | --- | ---: | ---: | --- | ---: | ---: | --- | --- |
| **`pi-intercom`** | Unix domain socket, auto-spawned broker process, length-prefixed JSON | **none** | **6,965** | **440** | 2026-08-12 | 27 | 79 | MIT | **CHOSEN, hardened** |
| `pi-mesh-extension` | local broker, `mesh.v1` | none | 6,447 | 2 | 2026-08-17 | 53 | 69 | MIT | rejected |
| `pi-crew` | orchestration over worktrees + task files | none | 1,708 | 49 | 2026-08-13 | 198 | 1,772 | MIT | rejected |
| `remote-pi` | in-process UDS broker, leader-elected; WSS relay for phone + cross-PC | none locally, relay for remote | 837 | 261 | 2026-08-12 | 17 | 822 | MIT | **rejected on security (§17.4.2)** |
| `agent-comms` | TCP mesh, cross-harness rooms/DMs | daemon | 256 | 16 | 2026-08-03 | 58 | 342 | none | rejected, watch |
| `pi-messenger` | file-based registry, shared broadcast room | none | 195 | 684 | 2026-07-30 | 23 | 50 | **none** | rejected |
| `@cryptolibertus/pi-peer` | UDS under `$TMPDIR/pi-peer-coms`, HMAC-SHA256 | none | 116 | 9 | **2026-05-28** | 48 | 202 | MIT | rejected |
| `pi-peer` (MinhDuyDEV) | HerdR workspace mux | **HerdR** | 59 | 0 | 2026-08-08 | 2 | 10 | MIT | rejected |
| `pi-agent-bus` | MessageBus pub/sub via `pi-link` | pi-link | 25 | 0 | 2026-06-05 | 7 | — | MIT | rejected |
| `pi-agents-talk-to-each-other` | file polling under `~/.pi/agent/rooms/` | none | 18 | 0 | 2026-06-28 | 3 | 18 | MIT | **not installed; retained as fallback blueprint (§17.12)** |
| `pi-chat` (npm) | WebSocket → Cloudflare Worker | **relay** | 2 | — | 2026-03-24 | 1 | — | **none** | rejected; retained as the supply-chain exemplar (§17.4.3) |
| `lynxz/pi-chat` (GitHub) | HTTP + SSE server, Docker | **self-hosted server** | not published | 0 | 2026-07-20 | — | 6 | Unlicense | rejected |
| `wowyuarm/pi-talk-to-sessions` | reads another session's `.jsonl`, replays it into a throwaway sub-session | none | not published | 0 | 2026-07-14 | — | 2 | MIT | rejected, superseded |
| *(ref)* `pi-subagents` | child processes | none | 56,532 | — | — | 51 | — | — | phase-3 pin |

### 17.4 The finalists, read from source and run

#### 17.4.1 `pi-intercom`: chosen. What it actually is.

Registry facts, `curl -s https://registry.npmjs.org/pi-intercom`, 2026-08-18:

| Field | Value |
| --- | --- |
| latest | `0.10.1`, published `2026-08-12T21:07:04.254Z` |
| **repository** | **absent. No `repository`, `homepage`, or `bugs` field in any of the 27 published versions, nor at the packument top level.** See the pin hazard below |
| npm maintainer | `nicopreme` <`nico.bailon@gmail.com`> |
| license | MIT (`LICENSE` present in the tarball) |
| `pi` manifest | `{ extensions: ["./index.ts"], skills: ["./skills"] }` |
| dist integrity | `sha512-ZkOVR08LzNFLI80LnvzOrxjfmhg3kSVPtrPVTTrkAhc4bT3PedfKcnQzuQ9+Gc1BGb2aObW/M0qPt6+xBMl/CQ==` |
| SRI (`nix hash file --sri --type sha256`) | `sha256-3j/X2r1AWSaShIz0I9BH2nxmVLY5BKpuRirI5X19zEI=` |
| `fileCount` / `unpackedSize` | 30 / 358,344 B |
| dependencies | `{ "tsx": "^4.20.0" }`, and **we do not need it** (below) |
| peerDependencies | `@earendil-works/pi-ai`, `@earendil-works/pi-coding-agent`, `@earendil-works/pi-tui`, `typebox` — all supplied by pi |
| ships `dist/`? | no. Raw TypeScript, 30 files, executed directly |
| repo | `nicobailon/pi-intercom`, 440★, 79 forks, 79 commits, created 2026-03-12, last push 2026-08-16, TypeScript, MIT |

**Pin hazard, and it is a serious one.** §8's rule is "pin by verified
repository URL rather than remembered author name". **For this package that
rule cannot be followed as written, because there is no repository URL to
verify against.** npm knows only the maintainer handle `nicopreme`; the GitHub
repo is `nicobailon/pi-intercom`. Those are different strings, and §17.4.3
documents a package in this same ecosystem where exactly that mismatch hides a
different author's project.

The link is real, and here is the evidence chain that establishes it, which is
what the implementation plan makes into a build step rather than a memory:

1. `gh api users/nicobailon` returns `"twitter_username": "nicopreme"` — the
   GitHub account itself claims the npm handle.
2. The repo publishes tag `v0.10.1`, matching the npm version exactly.
3. `package.json` in the tarball is byte-identical to `package.json` at the
   repo's `v0.10.1`.

Any one of those alone is weak. Together they are the substitute for the field
upstream did not set. **Re-run all three at every pin bump**, and if any one of
them stops holding, stop.

**Transport.** A Unix domain socket at
`$PI_CODING_AGENT_DIR/intercom/broker.sock` (default `~/.pi/agent/intercom/`),
4-byte big-endian length prefix plus JSON. The broker is a **separate process**,
auto-spawned by the first session under a `broker.spawn.lock`, exiting after
the last client leaves. On Windows it uses a named pipe, or TCP on `127.0.0.1`
behind `PI_INTERCOM_TRANSPORT=tcp`; neither applies here, but the TCP path is
the only one with an endpoint credential (`stateId`), which tells you the UDS
path was never meant to carry one.

**Permissions, verified by running it rather than read from source.**
`broker/paths.ts` declares `INTERCOM_DIR_MODE = 0o700` and
`INTERCOM_RUNTIME_FILE_MODE = 0o600`, and applies them with `mkdirSync({ mode })`
**plus an explicit `chmodSync`**, which means a directory left `0755` by an
earlier run is repaired rather than inherited. Started under a deliberately
hostile `umask 002`:

```
700 …/intercom
600 …/intercom/broker.sock
600 …/intercom/broker.pid
700 …/intercom/extension-state
```

Umask-independent, unlike `remote-pi`. This is the single clearest way in which
the chosen package is better than the rejected one, and it is the reason the
launcher does not need the `umask 0077` workaround the `remote-pi` plan carried.

**Tools.** One tool, `intercom`, with actions `list`, `send`, `ask`, `reply`,
`pending`, `cancel`, and `supersedes`. `list` is `ListAgents`: name, short ID,
cwd, model, and a live `idle`/`thinking`/`tool:<name>` status derived from pi
lifecycle events. `send` is `SendMessage`. **`ask` blocks the caller's turn
until the peer replies and returns the reply as the tool result** — the thing
`subagent-driven-development`'s implementer needs, and the thing Claude Code
does not have. Default timeout `DEFAULT_ASK_TIMEOUT_MS = 10 * 60 * 1000`, i.e.
ten minutes, overridable by `PI_INTERCOM_ASK_TIMEOUT_MS`.

**`pi-subagents` bridge.** Confirmed present, not inferred: `skills/pi-intercom/SKILL.md`
and the README both document a child-only `contact_supervisor` tool that
registers only when `pi-subagents` supplies bridge metadata through
`PI_SUBAGENT_CHILD_AGENT`, `PI_SUBAGENT_ORCHESTRATOR_SESSION_ID`,
`PI_SUBAGENT_RUN_ID` and friends. §8 already pins `pi-subagents`, so the
phase-3 child axis and this peer axis interlock instead of competing.

**It runs under bun, and that removes its only dependency.** This is the fact
that most changes the packaging, and it was measured rather than assumed:

- `bun broker/broker.ts` starts the broker cleanly, in a tree with **no
  `node_modules` at all**, printing `Intercom broker started (pid: …)`.
- `broker/broker.ts`'s transitive import set is node builtins plus relative
  `.ts` files. No `@earendil-works`, no `typebox`, nothing from npm.
- `config.ts`'s own doc comment reads `/** Broker command used to spawn the
  broker process (e.g. "npx" or "bun") */`. Upstream contemplates bun.
- `broker/spawn.ts` takes the non-default branch whenever `brokerCommand` is
  not literally `npx` with `["--no-install","tsx"]`, spawning
  `command [...args] brokerPath` directly. Setting `brokerCommand` to a bun
  store path and `brokerArgs` to `[]` gives `bun …/broker/broker.ts`.

So `tsx` is never invoked, and the declared `tsx` dependency is dead weight for
us: **zero runtime npm dependencies, no `bun.nix`, no lockfile, nothing to
install.**

**The default launch path would break under a Bun-built pi, which is why the
above is not optional.** `getBrokerLaunchSpec` on the default config does *not*
run `npx`. It calls `getNodeCommand(process.execPath)`, which checks whether
the running interpreter's basename matches `/^node(?:js)?(?:\.exe)?$/i`. Under
`packages.coding-agent-bun` the basename is `bun`, so it falls back to the
literal string `"node"` and resolves it through `PATH`. Inside a jail with no
Node on `PATH`, the broker fails to spawn. The first draft of this addendum
described the default as "`npx --no-install tsx`" and treated a Node interpreter
in the sandbox as the cost; both were wrong in detail, and the correct answer is
cheaper than either.

**Free CI coverage.** The published tarball includes seven `broker/*.test.ts`
files. `bun test broker/` gives **47 pass, 1 fail** across 48 tests. The single
failure, `extension bus negotiates, routes, elects an owner, and persists
state`, fails **identically under `tsx --test`**, so it is an upstream or
environment issue and not a bun regression; the plan names it with that reason
rather than silencing it.

**What is weak, stated up front.** The broker authenticates nobody, and it has
a session-ID takeover that needs no flag. Both are reproduced with running code
in §17.9, and both are fixed by an explicit, tested hardening task. This plan
does not ship this package unhardened either.

#### 17.4.2 `remote-pi`: rejected on security. Kept in full, because it is the comparison.

The user chose this package first, believing it comparable to `pi-intercom` on
security and better on capability. Reading its shipped source disproved the
first half. The findings are worth keeping in one place.

Its strengths, which were never the problem:

- **The local broker is not a separate process.** `session/leader_election.js`
  races `connect()` against `bind()` on
  `~/.pi/remote/sessions/local/broker.sock`; the winner constructs
  `new Broker(...)` inside its own pi process and a follower re-elects when the
  leader exits. Nothing to spawn, nothing to put on `PATH`.
- **Local mode needs no relay**, verified in `_cmdRootInner`:
  `_cmdJoin` is unconditional and only the relay is gated on
  `auto_start_relay`.
- **It is configurable entirely by environment** (`REMOTE_PI_DIRECT_CONFIG`,
  `REMOTE_PI_HOME`, `REMOTE_PI_RELAY`), writes nothing into a repository, and
  its own source comments name NixOS/Home-Manager read-only store symlinks and
  Bun's module resolution as cases it handles.
- **A phone and a cross-machine mesh**, over a self-hostable Rust relay.
- 261★, 822 commits, 71 forks, MIT, actively maintained.

What disqualified it, all measured against the shipped `dist/`:

1. **Unauthenticated registration where the client-supplied `cwd` is
   load-bearing routing identity.** `_handleRegister` does no `SO_PEERCRED`, no
   uid check; `composeAddress` yields `<cwd>@<name>` from values the client
   declares. A process can register as `/home/joe/some-other-repo@planner` from
   anywhere on the machine. `pi-intercom` is also unauthenticated, but its
   unverified `cwd` is display metadata only.
2. **An unauthenticated `takeover` flag that evicts a live peer.**
   `_identityForRegister` honours `req.takeover === true` by calling
   `_dropPeerAt`, which blanks the incumbent's address and destroys its socket.
   Measured: the attacker was granted `/home/joe/secret-repo@planner`, the exact
   address of the live victim, and the victim's socket was destroyed. Because
   the broker then forces `env.from` to the registered address, the
   anti-spoofing measure becomes the impersonation guarantee.
3. **`triggerTurn: true` hardcoded, with no configuration option anywhere.**
   `grep -rn triggerTurn` over the whole `dist/` returns two lines and one
   comment. Inbound peer messages reach the model as user-role messages and
   start a turn, and nothing short of patching the shipped JavaScript changes
   it.
4. **`0755` on the whole socket tree**, because `mkdirSync` is called with no
   `mode` anywhere and the socket inherits `0777 & ~umask`. Measured `755` under
   `umask 022` and **`775` under `umask 002`**, at which point every member of
   the user's group can open the broker and exercise items 1 and 2. The
   `audit.jsonl` written by `broker.js:502` records every routed message body in
   plaintext under that tree.

Items 2 and 4 have no counterpart in `pi-intercom`'s favour-of-`remote-pi`
column and are what reversed the decision. Item 3 is a difference of degree:
`pi-intercom` has the same unsafe default, but exposes a supported setting to
change it (§17.9 Risk 1).

Adoption also favours the choice: `pi-intercom` has 8.3× the weekly downloads
(6,965 against 837) and 440★ against 261★.

#### 17.4.3 `pi-chat`: rejected, preserved as the pin-by-verified-repo exemplar

Keep this finding. It is the live example of §8's rule, and §17.4.1 has just
shown that the rule's *mechanism* is missing for the package we are adopting,
which makes the example more relevant rather than less.

The GitHub repo `lynxz/pi-chat` is a real design: a zero-dependency
`node:http` + SSE chat server, a pi extension with `chat_send` / `chat_history`
/ `chat_whoami`, room access tokens, opt-in TLS, and a `docker-compose.yml`
wiring two containerised agents. It is 6 commits old, 0 stars,
unlicensed-by-Unlicense, **not published to npm**, and requires a server for
the same-machine case a socket solves for free. Rejected on those grounds.

**The npm package named `pi-chat` is a different project by a different
author.** One version, published **2026-03-24, three and a half months before
the GitHub repo was created**. No `repository` field, no license, a README
pointing at `/Users/vegard/dev/irc-clone`, **no `pi` key in `package.json`** (so
it is not a pi package at all), and a client whose `DEFAULT_SERVER` is
hardcoded to a stranger's Cloudflare Worker. Anyone who pinned "the pi-chat I
read about on GitHub" by name would have installed a stranger's relay client.

Note what the two packages have in common: **no `repository` field**. That is
not evidence against `pi-intercom`, but it does mean the cheap check that would
have caught `pi-chat` is unavailable, which is why §17.4.1 replaces it with a
three-part evidence chain the plan re-runs at every bump.

#### 17.4.4 `wowyuarm/pi-talk-to-sessions`: rejected, superseded

It does not do inter-instance messaging. It opens another session's `.jsonl`
**read-only**, rebuilds that session's effective context in a throwaway
in-memory sub-session with zero tools, asks it a question, and returns the
answer. The target is a transcript on disk, not a running process; nothing is
delivered to a live peer and a live peer cannot reply. 2 commits, not on npm.
The idea (interrogating a dormant session's memory) is useful and orthogonal,
but it is a retrieval feature, not this capability.

### 17.5 Also-rans from the gallery and awesome-pi

`https://pi.dev/packages` and `BubblePtr/awesome-pi` (89★) were both swept.
awesome-pi's *Communication & Collaboration* section lists five entries:
`pi-crew`, `pi-intercom`, `@cryptolibertus/pi-peer`, `@llblab/pi-telegram`, and
`agent-comms`. The gallery's front page carries `pi-intercom` among 58 packages.

- **`pi-mesh-extension` (6,447 dl/wk): reject on unverifiable popularity.**
  Downloads within 8% of the recommendation, against **2 stars**, a repository
  created 2026-08-07, and 53 published versions in 11 days. Downloads with no
  corroborating signal are not evidence of use; that ratio is the shape of
  automated installs, not adoption. Revisit in a quarter.
- **`pi-messenger` (684★): reject on model and license.** Same author as the
  recommendation, and its README table draws the line for us: a *shared
  broadcast room* with a file-based registry, for swarms working one task. We
  need targeted 1:1 addressing. It also has **no license field on npm and no
  license on the repository**, which is disqualifying for anything entering a
  Nix closure.
- **`pi-crew` (1,708 dl/wk, 1,772 commits): reject on scope.** Team/workflow
  orchestration with worktrees and async task graphs, an 8.99 MB unpacked
  tarball, and 198 published versions. It subsumes plan mode, todos, and
  subagents, colliding head-on with §8's `@plannotator/pi-extension`,
  `@juicesharp/rpiv-todo`, and `pi-subagents`. Adopting it means re-deciding
  four pins at once.
- **`agent-comms` (ExaDev): reject, but flag it for later.** Cross-harness
  rooms/DMs/presence over TCP for "Claude, Codex, Pi, Antigravity, and A2A
  agents", the only candidate that spans all four agents in this setup, which
  is the right long-term shape. Today: 16★, 256 dl/wk, **no license on npm or
  the repo**, and a TCP daemon where a socket suffices. Watch it.
- **`@cryptolibertus/pi-peer`: reject on staleness and socket location.**
  Last publish 2026-05-28, ~3 months stale, 9★. It does authenticate, with
  HMAC-SHA256 over a per-peer token, which is more than **either** finalist
  does, and that is worth remembering when reading §17.9. But its discovery
  directory is `$TMPDIR/pi-peer-coms`, i.e. `/tmp`, which is world-traversable
  and shared with every other user and daemon on the machine. A 46-file
  `src/peers/` tree including `hive-supervisor`, `plan-adversary`, and
  `self-improve` is also far more surface than the capability needs.
- **`pi-peer` (MinhDuyDEV): reject.** Hard dependency on the HerdR workspace
  mux (`herdr.ts` shells out to it for pane identity). 0★, 10 commits, 2 versions.
- **`pi-agent-bus`: reject.** 25 dl/wk, last publish 2026-06-05, requires
  `pi-link`.

### 17.6 Decision

**Adopt `pi-intercom` 0.10.1, pinned by the three-part evidence chain of
§17.4.1 because npm carries no repository field, run over bun with `tsx`
dropped, and hardened per §17.9. No relay. No new infrastructure of any kind.**

#### 17.6.1 Why

1. **Its popularity is the only corroborated popularity in the field.**
   6,965 dl/wk *and* 440★ *and* 79 commits *and* 27 published versions over
   five months *and* placement on the pi.dev gallery front page *and* an
   awesome-pi listing. `pi-mesh-extension` matches only the first number;
   `remote-pi` trails on the first two.
2. **It is materially safer at rest, and that is measured.** `0700` on the
   directory and `0600` on the socket and pid file, applied with explicit modes
   *and* a `chmodSync` repair, holding under a hostile `umask 002`. The rejected
   alternative is `0775` under the same conditions.
3. **`ask` exists.** A blocking request that returns the peer's reply as the
   tool result is the primitive `subagent-driven-development` actually needs.
   `remote-pi` has the shape and ships it deprecated in its own source.
4. **The `pi-subagents` bridge exists**, so the phase-3 child axis and this
   peer axis interlock rather than compete.
5. **No new author on the trust surface.** §8 already pins `pi-mcp-adapter`
   (1,265★) and `pi-subagents`, both from the same maintainer.
6. **Zero runtime dependencies under bun, and no build step.** No `bun.nix`, no
   lockfile, no `node_modules`, no interpreter beyond the bun that pi already
   is. §17.4.1.
7. **A real Nix seam.** `config.json` exposes `brokerCommand`/`brokerArgs`,
   which lets the module replace the upstream launch with a store path, so
   nothing resolves through `PATH` or the network.

#### 17.6.2 What was given up: phone control and cross-machine, and they are not small

**`pi-intercom` is local-only. There is no remote story at all** — a grep of
the whole tarball for WebSocket, HTTP, or any outbound URL returns nothing but
internal function names. Adopting it means:

- **No phone control.** The user wanted this. `remote-pi` ships a Flutter
  client, QR pairing, and typed quick actions (compact, new session, model
  picker, thinking level) driven from a phone. Nothing in the pinned set
  replaces that. The nearest ecosystem alternative is `@llblab/pi-telegram`,
  listed in awesome-pi and not evaluated here.
- **No cross-machine peers.** The user runs eleven Nix hosts. Peer messaging
  stops at the machine boundary, and the `erdtree` relay that would have
  crossed it is not being built.

This is a **declined capability, not a deferred one**. It does not come back by
finishing a later phase; it comes back only by adopting a second package. The
honest framing: the user traded a working phone channel for a broker that keeps
its socket at `0600` and refuses to hand a live session's identity to whoever
asks. That was the right trade on the evidence in §17.4.2, and it is still a
trade.

If phone control becomes the priority again, the options in order of cost are:
run `remote-pi` **alongside** `pi-intercom` with its mesh unused and only its
relay arm enabled, so the injection surface is the phone rather than the local
socket; adopt `@llblab/pi-telegram`; or revisit `remote-pi` if upstream fixes
the `takeover` flag and the directory modes. All three are out of scope here
and none is scheduled.

#### 17.6.3 Two claims from the first draft that were wrong

Recorded because the plan's build steps depend on them being right now.

1. **"Pinned by verified repository `nicobailon/pi-intercom`."** There is no
   `repository` field on npm, in any of 27 versions. §17.4.1 replaces the check.
2. **"The broker launches via `npx --no-install tsx`, so the jail needs `nodejs`
   and `tsx`."** The default path runs `process.execPath` plus tsx's `cli.mjs`,
   falling back to the literal `"node"` when the interpreter is not Node — which
   under a Bun-built pi it is not. The fix is to point `brokerCommand` at bun,
   at which point the jail needs neither.

A third claim was wrong in `pi-intercom`'s favour and is corrected against it:
the first draft said intercom has **no** takeover-equivalent primitive. It does.
§17.9 Risk 2.

### 17.7 Security analysis: `pi-intercom`'s model, measured

**Assets.** The agent's tool authority (bash under a jail with `network` and
`mount-cwd`), the session transcript, and the user's attention.

Everything in this section was produced by running `pi-intercom 0.10.1`'s own
`broker/broker.ts` under `bun`, with `PI_CODING_AGENT_DIR` pointed at a
scratch directory, on 2026-08-18. Transcripts are reproduced.

#### Risk 1: inbound peer message starts a turn. Upstream default is `"always"`.

`config.ts`'s shipped defaults, verbatim:

```ts
const defaults: IntercomConfig = {
  brokerCommand: "npx",
  brokerArgs: ["--no-install", "tsx"],
  confirmSend: false,
  inboundTrigger: "always",
  enabled: true,
  replyHint: true,
};
```

With `inboundTrigger: "always"` an inbound message **immediately starts a model
turn** in the target, and the injected text arrives as a *user* message. This
routes around §9 completely: layers 2 and 3 gate tool *calls*, never the
provenance of instructions. A malicious npm `postinstall`, a repo `Makefile`, or
a compromised extension running under the same uid gets to author instructions
for every other pi session on the box, including sessions whose jail mounts a
different repository. That is a lateral-movement primitive between jails.

Unlike the rejected alternative, this one is **configurable**:
`inboundTrigger` accepts `"always"`, `"replies"`, or `"never"`, validated in
`loadConfig`. But it is file-only: the full env surface is
`PI_INTERCOM_ASK_TIMEOUT_MS`, `PI_INTERCOM_LIVENESS_*`, `PI_INTERCOM_NAME_POLL_MS`,
`PI_INTERCOM_SESSION_ID`, `PI_INTERCOM_STABLE_ID`, `PI_INTERCOM_TCP`,
`PI_INTERCOM_TRANSPORT`, and `PI_BIN`. **There is no env override for
`inboundTrigger`**, which is precisely why the passthru contract has to grow a
config-file mechanism (§17.8).

**Mitigation, mandatory:** the module writes `inboundTrigger: "replies"` into
`$PI_CODING_AGENT_DIR/intercom/config.json`. Only a reply to an `ask` this
session originated may auto-trigger a turn. An unsolicited `send` is still
rendered inline and stored in session history: it is delivered, just not obeyed
unprompted. `"always"` remains available as an explicit per-host opt-in.

#### Risk 2: a session-ID takeover that needs no flag. Reproduced.

`broker.ts`'s register handler lets the client choose its own session ID, and
displaces whoever holds it:

```ts
let id: string = randomUUID();
if (clientMessage.sessionId !== undefined) { … id = clientMessage.sessionId; }
…
const previous = this.sessions.get(id);
…
if (previous) {
  this.clearAskEdgesForSession(id);
  this.clearMessageReceiptRoutesForSession(id);
  previous.socket.end();
}
```

The rejected package needed an explicit `takeover: true` to do this.
`pi-intercom` needs no flag: supplying a `sessionId` that is already in use is
sufficient. The attacker must first learn the UUID, but that costs one
unauthenticated round trip, because a registered peer may `list`.

Reproduced end to end, four steps against one live broker:

```
1. unauthenticated register ACCEPTED, sessionId = 7b573829-821c-4a4e-9a8c-74ea4a209cfa
2. list leaks ids: planner=7b573829… cwd=/home/joe/secret-repo trustedLocal=true peerUid=undefined
                 | spy=76dc6eb7… cwd=/home/joe/secret-repo trustedLocal=true peerUid=undefined
3. second session registered under the SAME name 'planner'; victim evicted? false
   sending to 'planner' now returns: delivery_failed "Multiple sessions named \"planner\" are connected. Use the session ID instead."
4. re-registered with the victim's sessionId: SAME ID GRANTED
   victim socket closed by broker? true
```

Read the four lines carefully, because two of them are bad and one is good:

- **Step 1** confirms what the README says: `peerUid` "is reserved for runtimes
  that can expose real peer credentials and is left unset otherwise", and
  cwd/model/pid/status "are display metadata, not authentication". Measured:
  `peerUid=undefined`, and `trustedLocal=true` is set purely because the
  transport is a UDS on a non-Windows host, not because anything was checked.
- **Step 2** shows `list` hands every session's UUID to any peer that asks. The
  ID is not a secret and cannot be treated as one.
- **Step 3 is the good news, and it is a design win.** Registering a
  second session under an existing *name* does **not** evict anyone and does
  **not** silently fan out: `findSessions` returns both and the send is refused
  with `delivery_failed`. The failure mode of a name collision is denial of
  delivery, which is loud, not interception, which is silent. The rejected
  package's `#N` suffixing plus its takeover flag gave the opposite outcome.
- **Step 4 is the hole.** The victim's ID was granted to the attacker and the
  victim's socket was closed by the broker.

**Mitigation, mandatory:** patch the register handler to refuse a `sessionId`
already held by a **live** session, rather than evicting its holder. Reconnect
after a real disconnect is unaffected, because a closed session moves to
`disconnectedSessions` and is no longer found by `this.sessions.get(id)`, so
restart-stable addressing via `stableId` keeps working. Verified: the patched
broker answers `{"type":"error","error":"Session ID already held by a live
session"}` and the incumbent stays connected.

**Do not set `stableId` in the Nix-written config.** `index.ts` resolves the
session ID as `PI_INTERCOM_STABLE_ID ?? config.stableId ?? piSessionId`. A
single value written into a shared `config.json` would give every session on the
machine the same ID, and each new session would evict the last. The default
`piSessionId` is correct and must stay.

#### Risk 3: `brokerCommand` is arbitrary code execution by config file

`config.json`'s `brokerCommand`/`brokerArgs` choose the executable pi spawns.
Upstream labels it advanced trusted local configuration and warns that anyone
who can edit the config can choose the executable used for future broker
auto-spawns. Nix ownership *improves* this: the module writes the file with a
bun store path, eliminating both the `PATH` lookup for `"node"` and tsx's module
resolution. A same-uid attacker can still rewrite it, which is true of
everything under `$HOME` and is not made worse here.

#### Risk 4: the jail bind is a cross-jail lateral-movement primitive

§7's `configPermission` bind-mounts `$PI_CODING_AGENT_DIR` into *every* pi jail,
and the socket lives under it by construction. That bind is exactly what makes
cross-jail messaging work, and exactly what makes cross-jail injection work. The
two cannot be separated at the mount layer. Unlike the rejected package this
needs no path gymnastics — intercom already puts its socket where the jail
already binds — but the consequence is identical and is stated here rather than
discovered later.

With Risks 1 and 2 mitigated, an attacker under the same uid can still connect
and still deliver text. It cannot take a live session's identity, and what it
delivers does not start a turn and is labelled as peer input by the §17.9
prompt fragment. Residual: an attacker already running as this uid can rewrite
the launcher, the config, or `$PATH`. `0600` and a patched broker do not fix
that and are not claimed to.

#### Risk 5: the extension bus

`pi-intercom` advertises `extension-bus-v1`: any two extensions declaring the
same namespace exchange 16 KiB payloads and up to 64 KiB of shared state through
the broker, with membership as the only authorisation. We enable no namespace
and none of §8's pins declare one. Worth re-checking at every pin bump.

#### Risk 6: attention denial

`ask` blocks the calling agent's turn for up to **ten minutes** by default
(`DEFAULT_ASK_TIMEOUT_MS`). A peer that never replies stalls the caller for the
whole timeout. Set `PI_INTERCOM_ASK_TIMEOUT_MS` deliberately rather than
inheriting the default.

#### Risk 7: supply chain by name, sharpened

§17.4.1 and §17.4.3. This package has **no `repository` field**, so the check
§8 mandates does not exist. The three-part evidence chain replaces it and is a
build step, not a memory.

#### One non-risk, recorded so nobody re-derives it

Bubblewrap does not impede this. A Unix domain socket is a filesystem object;
two jails that bind-mount the same host directory share the same inode and
connect normally. No network namespace is involved. Local mode opens no outbound
network at all, because there is no network code in the package.

### 17.8 Consequences for `mkPiExtension` (§8)

Phase 2 (`docs/plans/2026-08-18-pi-nix-fork.md` Task 3) fixes the passthru
contract at:

| Field | Type |
| --- | --- |
| `passthru.piEntrypoint` | **`list of str`**, absolute paths for repeated `--extension`; defaults to a one-element list holding the package root, so pi reads the package's own `pi` manifest |
| `passthru.piSkills` | `list of str`, absolute paths for `--skill` |
| `passthru.piPrompts` | `list of str`, absolute paths for `--prompt-template` |
| `passthru.settings` | `attrs`, merged into `~/.pi/agent/settings.json` |
| `passthru.promptFragment` | `null` or `str`, appended via `--append-system-prompt` |

and its builder arguments have grown `bunNix`, `keepDependencies`, and
`patchPhaseExtra` for bun2nix-built extensions.

`pi-intercom` consumes that contract with **one addition there is no way
around**:

**`settings` is not the only configuration surface, and for this package it is
the wrong one.** `pi-intercom` reads
`$PI_CODING_AGENT_DIR/intercom/config.json`, never `settings.json`, and
`inboundTrigger` — the security default this whole plan turns on — **has no
environment override** (§17.9 Risk 1). Carrying its config on
`passthru.settings` would write it to a file the extension never reads. Add:

```nix
passthru.configFiles = {
  # path relative to $PI_CODING_AGENT_DIR  →  JSON value
  "intercom/config.json" = { … };
};
```

The module writes these in the same launcher prelude that already merges
`settings.json`, so the mechanism is one code path, not two. This is the field
the `remote-pi` revision of this document was able to drop, because that package
took its whole config from an environment variable. It comes back now, and it is
load-bearing rather than speculative.

Three things the first draft asked for that are **not** needed:

- **`passthru.runtimeInputs` is not needed as a contract field.** The broker is
  spawned from inside the jail, so its interpreter must be in there, but that
  interpreter is `bun` — the same runtime pi already is. The module folds
  `[ pkgs.bun ]` into `jail.permissions` via `add-pkg-deps` from a module-local
  internal option, without widening the package contract.
- **`keepDependencies` and `bunNix` go unused.** With `brokerCommand` pointed at
  bun, `tsx` is never invoked, so `pi-intercom` needs no `node_modules` at all.
- **`bundled` needs no redefinition.** The package requires no install and no
  build step; it is consumed as an unpacked tarball. `piSkills` is real here and
  is used: `package.json` declares `pi.skills = ["./skills"]`, and under Nix we
  pass `--skill` only if we choose. Design assumption A3 is decided per package
  by an `installSkill` option defaulting to `false`.

### 17.9 The untrusted-input prompt fragment

The config default stops an unsolicited message from *starting* a turn. A
prompt fragment stops a delivered one from being *obeyed*. Per §12's governing
rule the fragment states policy and names no tool, skill, model, or path, so the
§12 inventory lint passes. `hard_deny` is the backstop: §9 already says user
intent does not clear it, and a peer is not the user, so it clears even less.

One line in that fragment is specific to this transport and is why it is not
generic boilerplate: **the name a message arrives under is a claim, not a fact.**
Any process under this uid can register, and until the Risk 2 patch it could
take a live session's identity outright.

### 17.10 New assumptions

Continuing §4's numbering.

| # | Assumption | Fallback if false |
| --- | --- | --- |
| A6 | **Verified true.** pi resolves an extension's bare imports (`typebox`, `@earendil-works/*`) through the `NODE_PATH` the pi wrapper exports, *including under Bun*. Measured: `NODE_PATH=… bun run probe.js` resolved a bare specifier on bun 1.3.13, and `coding-agent/package-bun.nix` sets `--prefix NODE_PATH : $out/lib/node_modules`. | Symlink pi's `lib/node_modules` into the extension derivation as its own `node_modules`. |
| A7 | **Verified true.** `bun broker/broker.ts` starts the broker with no `node_modules` present, so `tsx` can be dropped entirely. Measured. | Restore the `tsx` dependency, build `node_modules` with bun2nix, and set `brokerCommand` to a node store path. |
| A8 | `inboundTrigger: "replies"` still *delivers* unsolicited sends visibly (inline render plus session history) rather than dropping them. Read in `index.ts`; not yet observed in a live pi. | Ship `"always"` and rely on the §17.9 fragment alone; revisit if that is too weak. |
| A9 | A broker auto-spawned from inside one bubblewrap jail stays reachable from a second, differently-mounted jail through the shared `$PI_CODING_AGENT_DIR` bind. | Start the broker from the pi wrapper *outside* the jail, before `jailBuilder` wraps. |
| A10 | `pi-intercom`'s presence listeners and §6's `agent-statusline` extension can both subscribe to pi's lifecycle events without interfering. | None expected; they are independent listeners. If they collide, drop intercom's `status` field. |
| A11 | A Nix-declared `intercom/config.json` is never rewritten by pi or by `pi install`. | Harmless: the prelude rewrites it on every launch regardless. |
| A12 | The register-handler patch does not break restart-stable addressing, because a cleanly closed session moves to `disconnectedSessions` and is no longer matched by `this.sessions.get(id)`. Read in `broker.ts`; the patched broker was observed refusing a *live* collision. | Narrow the patch to refuse only when the incumbent socket is still writable. |

### 17.11 Rollout position

§15 orders the work 1–6. Messaging depends on `mkPiExtension` (phase 2) and on
the jail config (phase 3), and its prompt fragment wants to land with the other
fragments (phase 5). It slots in as **phase 3.5**: after the jail exists, so A9
is answerable rather than hypothetical, and before the fragments are frozen.

There is no Tier 2. §17.6.2 explains why, and what it would cost to get one.

### 17.12 Risks

| Risk | Impact | Mitigation |
| --- | --- | --- |
| Inbound message auto-starts a turn as a user-role message | Cross-jail lateral movement | `inboundTrigger = "replies"` written by the module (§17.9 Risk 1); untrusted-input prompt fragment; `hard_deny` backstop |
| Session-ID takeover evicts a live peer | Full impersonation of another session | Patch the register handler to refuse a live collision, with an end-to-end regression test (§17.9 Risk 2) |
| Pin cannot be verified by repository URL | A future bump installs a different author's package | Three-part evidence chain re-run as a build step at every bump (§17.4.1) |
| Default launch path resolves `"node"` through `PATH` | Broker fails to spawn under a Bun-built pi in a jail | `brokerCommand` is a bun store path, `brokerArgs` empty; asserted in the option's eval test |
| A8 false: `"replies"` drops rather than defers | Messages silently lost | Revert to `"always"` plus the fragment; the two-terminal acceptance step catches it |
| Pin churn, 27 versions in 5 months, plus two patches | A bump breaks a patch | `--replace-fail` makes every patch a build-time drift alarm; the shipped broker tests run in CI |
| No phone control, no cross-machine | A stated want goes unmet | Declined, not deferred. §17.6.2 lists the three ways back |
| Upstream folds messaging into pi itself | Extension becomes redundant | Delete one pin; the `messaging` option keeps its shape |

### 17.13 Retained fallback blueprint: `pi-agents-talk-to-each-other`

**Not installed.** Kept here as the design to fall back to if `pi-intercom`'s
transport proves troublesome: a broker process that dies with the wrong pi, a
spawn lock that wedges, or a patch that stops applying at a pin bump.

`Timur00Kh/pi-agents-talk-to-each-other` is **1,443 lines in a single file**,
a **pure file bus** with **no daemon and no sockets**: rooms under
`~/.pi/agent/rooms/`, discovered and drained by polling. `room_list_agents` and
`room_send_message` map onto `ListAgents`/`SendMessage`, and it gates
`room_control_agent` behind an opt-in per-agent flag file.

Why it is not the choice: 18 commits, 3 versions, 0 stars, 18 dl/wk, last
touched 2026-06-28, and its own README admits `reload` and `new_session` are
broken because pi does not process slash commands from extension-injected
messages.

Why it is worth keeping written down anyway:

1. **It has no transport to go wrong.** Both §17.9 Risk 2 and the rejected
   package's takeover flag are properties of a socket broker holding a session
   table. A directory of JSON files has filesystem permissions as its only
   access-control mechanism, which is exactly the mechanism Nix and the jail are
   already good at.
2. **One file, MIT, 1,443 lines.** Small enough to vendor and audit in full
   rather than pin, which is the honest response to "the upstream project is
   unmaintained".
3. **Its safety notes are candid**: "does not authenticate senders", "the flag
   file is not cryptographically protected". Candour is not a substitute for
   maintenance, but it does mean the threat model is already written down.

If it is ever adopted, adopt it as a *vendored blueprint*, not a pin: copy the
file into `pi-nix/packages/extensions/`, keep the MIT notice, and treat the
polling loop and the room schema as the parts worth keeping.
