# Design addendum: inter-instance messaging for pi

Date: 2026-08-18
Status: **decided**. `remote-pi`, local mode. Revised 2026-08-18 after triage.
Extends: `docs/plans/2026-08-18-pi-nix-agent-stack-design.md` as **§17**, a
seventh subsystem alongside `agent-statusline`, `pi-nix`, permissions/sandbox,
`pi-notify`, the `agent-skills` pi target, and the prompt fragments.

> **Revision note.** The first version of this addendum recommended
> `pi-intercom`. That recommendation was **overruled**: the user chose
> **`remote-pi` in its local mode** and explicitly rejected `pi-intercom`.
> The comparison, the measurements, and the reasoning that produced the
> original recommendation are all retained below, because deleting them would
> hide the trade. But §17.6 now records the decision that was actually taken,
> §17.6.3 states plainly what `pi-intercom` was better at, and §17.9 is
> rewritten around `remote-pi`'s **own** authentication model, read out of its
> shipped source rather than assumed from intercom's.

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
| **`remote-pi`** | **in-process UDS broker, leader-elected**; WSS relay only for phone + cross-PC | **none in local mode** | 837 | 261 | 2026-08-12 | 17 | 822 | MIT | **CHOSEN (local mode)** |
| `pi-intercom` | Unix domain socket, auto-spawned broker process, length-prefixed JSON | none | 6,965 | 440 | 2026-08-12 | 27 | 79 | MIT | rejected by decision |
| `pi-mesh-extension` | local broker, `mesh.v1` | none | 6,447 | 2 | 2026-08-17 | 53 | 69 | MIT | rejected |
| `pi-crew` | orchestration over worktrees + task files | none | 1,708 | 49 | 2026-08-13 | 198 | 1,772 | MIT | rejected |
| `agent-comms` | TCP mesh, cross-harness rooms/DMs | daemon | 256 | 16 | 2026-08-03 | 58 | 342 | none | rejected, watch |
| `pi-messenger` | file-based registry, shared broadcast room | none | 195 | 684 | 2026-07-30 | 23 | 50 | **none** | rejected |
| `@cryptolibertus/pi-peer` | UDS under `$TMPDIR/pi-peer-coms`, HMAC-SHA256 | none | 116 | 9 | **2026-05-28** | 48 | 202 | MIT | rejected |
| `pi-peer` (MinhDuyDEV) | HerdR workspace mux | **HerdR** | 59 | 0 | 2026-08-08 | 2 | 10 | MIT | rejected |
| `pi-agent-bus` | MessageBus pub/sub via `pi-link` | pi-link | 25 | 0 | 2026-06-05 | 7 | — | MIT | rejected |
| `pi-agents-talk-to-each-other` | file polling under `~/.pi/agent/rooms/` | none | 18 | 0 | 2026-06-28 | 3 | 18 | MIT | **not installed; retained as fallback blueprint (§17.13)** |
| `pi-chat` (npm) | WebSocket → Cloudflare Worker | **relay** | 2 | — | 2026-03-24 | 1 | — | **none** | rejected; retained as the supply-chain exemplar (§17.4.3) |
| `lynxz/pi-chat` (GitHub) | HTTP + SSE server, Docker | **self-hosted server** | not published | 0 | 2026-07-20 | — | 6 | Unlicense | rejected |
| `wowyuarm/pi-talk-to-sessions` | reads another session's `.jsonl`, replays it into a throwaway sub-session | none | not published | 0 | 2026-07-14 | — | 2 | MIT | rejected, superseded |
| *(ref)* `pi-subagents` | child processes | none | 56,532 | — | — | 51 | — | — | phase-3 pin |

### 17.4 The flagged candidates, individually

#### 17.4.1 `remote-pi`: chosen. What it actually is, read from its source.

Registry facts, `curl -s https://registry.npmjs.org/remote-pi`, 2026-08-18:

| Field | Value |
| --- | --- |
| latest | `0.7.0`, published `2026-08-12T01:38:16.937Z` |
| repository | `git+https://github.com/jacobaraujo7/remote_pi.git`, `directory: pi-extension` |
| license | MIT (`LICENSE` present in the tarball) |
| `pi` manifest | `{ extensions: ["./dist"], image: "…/branding/banner.png" }` |
| dist integrity | `sha512-L2kMTFiuqn5j6NU+Re7M1bOMeRJGBsyp8IrlTSWFF7H7JHzjtBjnOMbCOMuNlN4vkeLLYURXXbsrOCOrE6b4hQ==` |
| SRI (`nix hash file --sri --type sha256`) | `sha256-YhImMDS77zPxcDpkpaFPhHDyAxqI2VjADmIjSm7EIKM=` |
| `fileCount` / `unpackedSize` | 186 / 1,283,803 B |
| dependencies | 10 declared; **4 actually reachable** — see below |
| dist bundled? | **yes** — `dist/` holds compiled `.js` + `.d.ts` + `.js.map`; there is no `src/` and no build step |
| repo | 261★, 71 forks, 822 commits, created 2026-05-22, last push `2026-08-18T21:14:43Z`, primary language **Dart** (the mobile app dominates the line count; the extension is the `pi-extension/` subdirectory) |

**The local transport is an in-process Unix-domain-socket broker with leader
election. There is no broker process.** This is the single most important
structural fact and it is not what the first draft of this addendum assumed.
`session/leader_election.js` `joinOrLead(sockPath)` first tries to *connect* to
`~/.pi/remote/sessions/local/broker.sock`; on failure it tries to *bind* it,
with jittered backoff and stale-socket cleanup on an `EADDRINUSE`/`ECONNREFUSED`
race. Whoever wins the bind becomes the **leader** and constructs
`new Broker({ server, auditPath })` *inside its own pi process*; everyone else
is a **follower** holding a client socket. When the leader exits, a follower
re-runs the election and takes over. `session/global_config.js` fixes the
session name at `LOCAL_SESSION_NAME = "local"`: one broker per machine, no
named rooms, no multi-session UX.

Consequences, all of which matter under Nix:

- **Nothing is spawned.** No `npx`, no `tsx`, no `brokerCommand`, no daemon,
  no interpreter to inject into the sandbox. `pi-intercom`'s packaging problem
  (replacing `npx --no-install tsx` with a store path) simply does not exist
  here. This is also why the bun switch is cheap: there is no second runtime.
- **The broker's lifetime is a pi session's lifetime.** No 5s linger, no
  orphaned process, no PID file.
- **`passthru.runtimeInputs` is unnecessary.** §17.8.

**Local mode needs no relay. Verified in code, not quoted from the README.** `_cmdRootInner` in `dist/index.js` reads, verbatim:

```js
// Returning user with config: ALWAYS join the local UDS mesh on connect; the
// relay is the only thing gated by auto_start_relay. So auto_start_relay:false
// now means "local mesh, no relay" …
const config = loadLocalConfig(cwd);
if (!_meshNode) await _cmdJoin(ctx);
if (effectiveAutoStartRelay(config) && _state === "idle") await _cmdStart(ctx);
```

`_cmdJoin` is unconditional; `_cmdStart` (the relay) is gated. With
`auto_start_relay: false` the default community relay
(`kDefaultRelayUrl = "https://relay-rp1.jacobmoura.work"`, `config.js:13`) is
never dialled. There is no outbound network in Tier 1.

**The setup wizard is two questions and is fully bypassable.**
`session/setup_wizard.js` asks (1) agent name, (2) "Use the relay on this
terminal to connect to the remote mesh (mobile + PCs)?", then a save/confirm.
It writes exactly `{ agent_name, auto_start_relay }` to
`<cwd>/.pi/remote-pi/config.json`. The README still describes a third
"default session" question; the code dropped it when the local mesh became
single-session. **`session/local_config.js` accepts the whole local config
inline from the `REMOTE_PI_DIRECT_CONFIG` environment variable**, which takes
precedence over the file and makes `localConfigExists()` true, so the wizard
never fires. That single fact retires the old assumption A11 and means the
package needs **no `passthru.configFiles` and no file written into any repo**.

**What it writes to disk, exhaustively.** With `REMOTE_PI_DIRECT_CONFIG` set,
`saveLocalConfig` is reachable only from `/remote-pi rename`, `/remote-pi
setup`, the first-run wizard, and `remote-pi create`. None of those run
automatically, so **nothing is written into any repository working tree**.
Under `$REMOTE_PI_HOME` (default `$HOME`) it writes:

| Path | What | Written by |
| --- | --- | --- |
| `.pi/remote/sessions/local/broker.sock` | the UDS | leader's `server.listen()` |
| `.pi/remote/sessions/local/session.json` | session metadata | `index.js:3808` |
| `.pi/remote/sessions/local/audit.jsonl` | **every routed envelope, bodies included** | `broker.js:502`, `appendFile` |
| `.pi/remote/skills/agent-network/SKILL.md` | copy of the packaged skill | `index.js:3660-3669` |
| `.pi/remote-pi/socks/<sha256(realpath(cwd))[:12]>.sock` | per-(cwd,name) lock | `session/address.js`, `cwd_lock.js` |
| `.pi/remote/identity.json` *(relay only, 0600)* | Ed25519 identity fallback | `pairing/storage.js` |

Note `.pi/remote/identity.json` resolves through `homedir()`, **not**
`REMOTE_PI_HOME`. That inconsistency only matters in Tier 2.

**pi APIs and events it hooks.** Three tools via `pi.registerTool` in
`session/tools.js`: `agent_send`, `list_peers`, and the deprecated
`agent_request`. Around 30 slash commands via `pi.registerCommand`. And these
lifecycle events in `index.js`: `resources_discover`, `context`, `input`,
`model_select`, `thinking_level_select`, `agent_start`, `message_start`,
`message_update`, `tool_execution_start`, `tool_execution_end`, `message_end`,
`agent_end`, `turn_start`, `turn_end`, `session_before_compact`,
`session_compact`, `session_start`, `session_shutdown`. It **self-registers a
skill directory**: `pi.on("resources_discover", () => ({ skillPaths: [skillsDir()] }))`
(`index.js:1816`) after copying its `SKILL.md` into `~/.pi/remote/skills/`.
That is the package loading its own skill without `--skill`, which is why
`passthru.piSkills` is the wrong lever for it and `REMOTE_PI_HOME` is the right
one.

**Correction to the first draft: the `tool_gate` is not a fourth permission
layer.** `session/tool_gate.js` does hard-code `Read`/`Glob`/`Grep` as
auto-approved and everything else as `ask`, but it is consumed only by
`session/agent_bridge.js`, and a static import-graph walk from `dist/index.js`
(42 files reached) shows **neither `agent_bridge` nor `tool_gate` is
reachable from the extension entrypoint**. `index.js`'s own header comment
says so: "why we don't use AgentBridge directly here". The gate belongs to the
mobile-app bridge, which Tier 1 never constructs. The earlier claim that it
"lands a fourth uncoordinated permission layer underneath §9's three" was
wrong, and is withdrawn.

**Dependency reality.** `package.json` declares ten runtime dependencies, but
the extension's static import graph from `dist/index.js` needs only:

| Package | Status |
| --- | --- |
| `@earendil-works/pi-coding-agent`, `@earendil-works/pi-tui`, `typebox` | supplied by pi's own `lib/node_modules` via `NODE_PATH` |
| `@noble/ed25519`, `croner`, `qrcode-terminal`, `ws` | **the four that must be materialised** |
| `@napi-rs/keyring` | **dynamic** `await import(…)`, pairing only |
| `@modelcontextprotocol/sdk`, `zod` | reachable only from `mcp/mesh_server.js` — the `remote-pi claude` path, not the pi extension |
| `noise-protocol` | imported by `pairing/noise-sha256.js` but **not declared as a dependency at all** — an upstream bug, harmless here because that file is unreachable from `index.js` |

Installing the declared set with `bun install --production` pulls **216
packages** (the `@earendil-works` and MCP trees drag in `@aws-sdk`,
`@anthropic-ai`, `@google/genai`). Pruning `dependencies` to the four gives
**4 packages, 708 KB, zero transitive deps**, measured. §17.8.

**It is already Bun-aware, and says so.** `pairing/storage.js` carries a long
comment on issue #113 explaining that a *static* `import { AsyncEntry } from
"@napi-rs/keyring"` "takes the WHOLE extension down at load time" on "a
Bun-compiled `pi`", because the napi loader's fallback
`require("@napi-rs/keyring-<triple>")` "resolves under Node and not under Bun".
It was made lazy for exactly that reason, with a documented `0600`
file-identity fallback. Since phase 2 now builds `packages.coding-agent-bun`,
this is the difference between a package that loads and one that does not.

**It is also already Nix-aware.** `saveLocalConfig`'s comment names the case
directly: "a read-only `config.json` is a legitimate deployment (NixOS/Home
Manager symlink into the immutable Nix store, read-only root, EPERM)", and
guards both `mkdirSync` and `writeFileSync` so it warns instead of taking pi
down. Upstream has thought about us.

**What is weak, stated up front.** Its authentication model is *worse* than
`pi-intercom`'s. Unauthenticated registration with a **client-supplied `cwd`
that becomes half the routing address**, an unauthenticated `takeover` flag
that evicts a live peer, a hardcoded `triggerTurn: true` with **no
configuration knob**, and `0755` on the whole socket tree because no `mode` is
ever passed to `mkdirSync`. All four are demonstrated with running code in
§17.9, and all four are fixed by an explicit, tested hardening task in the
implementation plan. That plan does not ship this package unhardened.

#### 17.4.2 `pi-intercom`: the overruled recommendation, kept on the record.

The measurements that produced the original recommendation stand and are worth
keeping, because they are the price of the decision:

- **The only candidate whose popularity is corroborated across every axis.**
  6,965 dl/wk *and* 440★ *and* 79 commits *and* 27 published versions over five
  months *and* the pi.dev gallery front page *and* an awesome-pi listing.
- **Same maintainer as `pi-mcp-adapter` and `pi-subagents`** (`nicobailon`),
  both already pinned by §8. Adopting it added no new author to the trust
  surface. Adopting `remote-pi` does add one.
- **Zero runtime dependencies on the broker path.** Its broker's transitive
  import set is node builtins only.
- **Explicit `0700` directory / `0600` runtime files** in `broker/paths.ts`.
- **A configurable `inboundTrigger`** with a `"replies"` setting, which is
  precisely the safe default this addendum's first version specified.
- **A `pi-subagents` bridge** (`contact_supervisor`, gated on `PI_SUBAGENT_*`).

Its costs, equally on the record: it ships **raw TypeScript with no `dist/`**
and **no `package-lock.json`**, and launches its broker as a **separate process
via `npx --no-install tsx`**. Under the phase-2 decision to build
`coding-agent-bun` and package extensions with **bun2nix**, both of those are
now active liabilities rather than neutral facts: the packaging would have to
supply a Node+tsx interpreter inside the jail purely to run a sidecar that
`remote-pi` does not need at all.

§17.6.3 states what was given up.

#### 17.4.3 `pi-chat`: rejected, preserved as the pin-by-verified-repo exemplar.

Keep this finding. It is the live example of §8's rule, and the rule is only as
memorable as its counter-example.

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

§8 already says: pin by verified repository URL, never by remembered author
name. This is that rule with a name attached, and it is why the implementation
plan's first pin step prints the registry's `repository` field and **stops** if
it does not read `jacobaraujo7/remote_pi`.

#### 17.4.4 `wowyuarm/pi-talk-to-sessions`: rejected, superseded.

It does not do inter-instance messaging. It opens another session's `.jsonl`
**read-only**, rebuilds that session's effective context in a throwaway
in-memory sub-session with zero tools, asks it a question, and returns the
answer. The target is a transcript on disk, not a running process; nothing is
delivered to a live peer and a live peer cannot reply. 2 commits, not on npm.
The idea (interrogating a dormant session's memory) is useful and orthogonal,
but `remote-pi` supersedes the use case it was being considered for, and a
retrieval feature over `.jsonl` files is not this capability.

### 17.5 Also-rans from the gallery and awesome-pi

`https://pi.dev/packages` and `BubblePtr/awesome-pi` (89★) were both swept.
awesome-pi's *Communication & Collaboration* section lists five entries:
`pi-crew`, `pi-intercom`, `@cryptolibertus/pi-peer`, `@llblab/pi-telegram`, and
`agent-comms`. The gallery's front page carries `pi-intercom` among 58 packages.

- **`pi-mesh-extension` (6,447 dl/wk): reject on unverifiable popularity.**
  Downloads within 8% of `pi-intercom`, against **2 stars**, a repository
  created 2026-08-07, and 53 published versions in 11 days. Downloads with no
  corroborating signal are not evidence of use; that ratio is the shape of
  automated installs, not adoption. Revisit in a quarter.
- **`pi-messenger` (684★): reject on model and license.** A *shared broadcast
  room* with a file-based registry, for swarms working one task; we need
  targeted 1:1 addressing. It also has **no license field on npm and no license
  on the repository**, which is disqualifying for anything entering a Nix
  closure.
- **`pi-crew` (1,708 dl/wk, 1,772 commits): reject on scope.** Team/workflow
  orchestration with worktrees and async task graphs, an 8.99 MB unpacked
  tarball, and 198 published versions. It subsumes plan mode, todos, and
  subagents, colliding head-on with §8's `@plannotator/pi-extension`,
  `@juicesharp/rpiv-todo`, and `pi-subagents`. Adopting it means re-deciding
  four pins at once.
- **`agent-comms` (ExaDev): reject, but flag it for later.** Cross-harness
  rooms/DMs/presence over TCP for "Claude, Codex, Pi, Antigravity, and A2A
  agents", the only candidate that spans all four agents in this setup, which
  is the right long-term shape. Today: 16★, 256 dl/wk, **no license
  on npm or the repo**, and a TCP daemon where a socket suffices. Watch it.
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

**Adopt `remote-pi`, pinned by verified repository `jacobaraujo7/remote_pi`,
version `0.7.0`, run in local mode: `auto_start_relay: false`. No relay. No
new infrastructure of any kind in this phase.**

#### 17.6.1 Why the decision is defensible on its merits

1. **Nothing is spawned, which is the whole packaging problem gone.** The
   broker lives in the leader pi process (§17.4.1). There is no
   `brokerCommand`, no `npx`, no `tsx`, no sidecar interpreter to fold into
   `jail.permissions`. Under the phase-2 move to `coding-agent-bun` that is the
   difference between packaging one derivation and packaging a second runtime
   to serve it.
2. **It ships a real prebuilt `dist/` and a clean bun2nix path.** Pruned to
   the four reachable dependencies, `bun install` produces a 1,072-byte
   `bun.lock` and `bun2nix -o bun.nix` produces four `fetchurl` entries, both
   reproduced verbatim in the implementation plan. No `.ts` execution, no
   jiti reliance, no `buildNpmPackage` lockfile vendoring.
3. **It is configurable entirely by environment.** `REMOTE_PI_DIRECT_CONFIG`
   (whole local config as inline JSON), `REMOTE_PI_RELAY` (relay URL),
   `REMOTE_PI_HOME` (state root). Nothing is written into a repository, and
   the `passthru` contract needs **no `configFiles` field**, so the plan consumes
   phase 2's contract as it stands instead of widening it.
4. **It is already Bun-aware and already Nix-aware**, in its own source
   comments, for the exact two reasons that would have bitten us (§17.4.1).
5. **Actively maintained.** 822 commits, last push the day of this decision,
   71 forks, MIT, `Cargo.lock` and `bun.lock` committed upstream, a Flutter
   client and a Rust relay alongside the extension.
6. **One package covers the growth path.** Standing up the relay later (§17.7)
   turns on phone control and cross-machine routing with **no second pin and
   no second protocol**. Tier 2 is a configuration change, not an adoption
   decision. With `pi-intercom` it would have been a second package speaking a
   second wire format.
7. **Sender attribution is in-band and honest.** A delivered message reaches
   the model as `[agent-network] message from "<address>" (id=…):` with a
   footer telling it how to reply, rendered in the *tool* timeline rather than
   as the user's own message; `index.js` calls that last point out as a fixed
   bug. And `broker.js` forces `env.from = conn.address` on every routed
   envelope, so a registered peer cannot spoof another peer's address on a
   message it sends.

#### 17.6.2 Why it is not chosen on popularity

`remote-pi` has 837 dl/wk against `pi-intercom`'s 6,965, an 8.3× gap, and 261★
against 440★. On the corroboration test the first draft applied,
`pi-intercom` wins and `remote-pi` places second. `remote-pi` clears the bar
(261★ + 822 commits + 71 forks is corroborated adoption, unlike
`pi-mesh-extension`'s 6,447 dl/wk against 2★) but it does not win on it. The
decision rests on §17.6.1, not on the numbers, and pretending otherwise would
be dishonest.

#### 17.6.3 What was given up: five things `pi-intercom` was better at

The user is entitled to know the cost. Ranked by how much it will actually be
felt:

1. **Blocking ask/answer as a tool result. Lost, and this is the one that will
   hurt.**
   `intercom({action:"ask"})` blocks the caller's turn until the peer replies
   and returns the reply *as the tool result*. That is exactly the shape
   `subagent-driven-development`'s implementer needs when it hits real
   ambiguity mid-task: ask, get an answer, continue the same turn. `remote-pi`
   has the shape (`agent_request`) but ships it **deprecated in its own
   source**: "DEPRECATED, prefer `agent_send` + observing your inbox".
   `agent_send` waits only for a 5s broker delivery ACK; the peer's actual
   answer arrives later as a separate inbound message correlated by `re`. So
   the ask/answer pattern becomes two turns and a correlation id instead of one
   tool call. It still works. It is worse, and it is the shape upstream is
   moving away from, so it will not improve.
2. **A safe inbound default that upstream supports. Lost; we build it
   ourselves.** `pi-intercom` has an `inboundTrigger` config with `always` / `replies`
   / `never`, so the safe posture was a one-line config choice supported by the
   maintainer. `remote-pi` hardcodes `triggerTurn: true` with **no knob**
   (§17.9 Risk 1). We now have to carry a `substituteInPlace` patch, and that
   patch is a maintenance cost at every pin bump.
3. **`pi-subagents` integration. Lost entirely.** `pi-intercom` ships
   `contact_supervisor`, gated on `PI_SUBAGENT_*` env vars, so the phase-3
   child axis and this peer axis interlock. `grep -rni "subagent"` over
   `remote-pi`'s entire `dist/` returns **zero hits**. A `pi-subagents` worker
   cannot reach its spawning session through `remote-pi` unless that spawning
   session happens to be a registered mesh peer in the same cwd. Because
   `remote-pi` keys identity on `(cwd, name)` and a subagent inherits its
   parent's cwd, that is *plausible*, but it is nowhere designed, tested, or
   documented. Treat it as unavailable until measured. **Phase 3 should re-open
   this**: if the subagent↔supervisor channel
   turns out to matter more than the peer channel, adding `pi-intercom`
   *alongside* `remote-pi` purely for `contact_supervisor` is a legitimate
   later move, and the `messaging.package` option keeps it a one-line change.
4. **Trust-surface consolidation. Lost.** `nicobailon` already carries
   `pi-mcp-adapter` (1,265★) and `pi-subagents` in this closure.
   `jacobaraujo7` is a new author on the trust surface, and `remote-pi`
   materialises four npm dependencies where `pi-intercom`'s broker needed none.
5. **Corroborated popularity. Lost.** §17.6.2.

Two things people might expect to be on this list and are not: `pi-intercom`
is **not** better on packaging purity (it ships no `dist/` and no lockfile, so
under bun2nix it is strictly harder), and it is **not** better on jail
integration (its socket lives under `$PI_CODING_AGENT_DIR`, but §17.9 shows
that bind is a liability as much as a convenience, and `REMOTE_PI_HOME` lets
`remote-pi` land in the same place by choice).

### 17.7 The relay: deferred, not cancelled

**Tier 1 (now) runs local-only and needs no relay.** Tier 2 stays fully
specified here so standing it up later is a configuration decision rather than
a research project. The user runs eleven Nix hosts and a phone; the want is
plausible, not hypothetical.

**A relay is required only for (a) phone control and (b) messaging between pi
instances on different machines.** For the same-machine case, which is what
`subagent-driven-development` and `dispatching-parallel-agents` actually need,
`remote-pi` operates over the local socket with no server (§17.4.1, verified in
`_cmdRootInner`).

Hosting on `erdtree` entails:

| Item | Reality |
| --- | --- |
| Software | `relay/` in `jacobaraujo7/remote_pi`, tag `v0.4.0` = `cc2589f`. Rust 2024, axum 0.7 + tokio, `rusqlite` with `bundled` (no system sqlite). `Cargo.lock` committed. Source SRI: `sha256-0Mm7V4bTwNW7dxoeoSw/liCdiJlOxdKxIFUN3zsc79E=` |
| Nix | `rustPlatform.buildRustPackage` with `sourceRoot = "source/relay"`. Fallback `virtualisation.oci-containers` with `ghcr.io/jacobaraujo7/remote-pi-relay:latest` |
| Deployment | Exactly the `wings.nix` shape: `den.aspects.erdtree.nixos`, one `systemd.services.*` with `DynamicUser` + `StateDirectory`, one port |
| Ports | One. `REMOTEPI_RELAY_PORT` (default 3000) serves the WS upgrade, `/health`, and `/mesh/*` together |
| State | SQLite at `REMOTEPI_MESH_DB_PATH`. Owner-signed membership metadata only, never message traffic. Rollback-journal mode, so `mesh.db` is the whole backup |
| Client config | `REMOTE_PI_RELAY` env var (**not** `REMOTE_PI_RELAY_URL` — corrected), or `~/.pi/remote/config.json`, or the built-in default. Precedence in that order, `config.js:36-51`. The URL **must** be `http://` or `https://`; `ws://`/`wss://` are rejected at validation and converted internally |
| CI | garnix already builds `erdtree`; a Rust derivation is one more `nix build` target |
| Effort | One systemd unit and one `StateDirectory`. Comparable to `attic-cache.nix`, an order of magnitude below `garnix.nix` |

**The part that is not trivial, and must not be glossed:**

- **The relay has no operator authentication to configure, so agenix has no
  server-side secret to hold.** Any peer that completes the Ed25519
  challenge-response is accepted; authorisation is per-route, from Owner-signed
  membership blobs the clients publish. There is no admin token, no allowlist,
  no bearer gate. An agenix secret would be inventing one.
- **Therefore the network *is* the boundary.** The honest deployment is
  tailnet-only: bind to `erdtree`'s `tailscale0` address, no Caddy vhost, no
  public DNS record, and the existing `trustedInterfaces = [ "tailscale0" ]`
  does the gating. Upstream agrees: its own README recommends putting the
  self-hosted relay behind Tailscale/WireGuard "so **only your devices** can
  even reach the WebSocket port". Publishing it on `*.turnin.quest` behind
  Caddy, the reflex for every other service on that host, would expose an
  unauthenticated routing service to the internet.
- **agenix's real job here is the URL, not a credential.** House convention
  keeps hostnames in `dotfiles-secrets/domains.nix`; the client reads it into
  `REMOTE_PI_RELAY`. The key material that matters, each host's Ed25519 pairing
  keypair, in the platform keyring or falling back to `~/.pi/remote/identity.json`
  at `0600`, is generated on the client and must never enter the store or
  agenix.
- **Route eligibility is not proof of control.** The README, verbatim: a Pi↔Pi
  route is permitted when "any correctly signed Owner blob lists both canonical
  Pi keys", and "that does not prove the Owner paired with or controls either
  Pi". Payloads are **not** end-to-end encrypted: "Fields such as `ct` are
  wire containers, not a systemwide end-to-end confidentiality guarantee… A
  relay operator can see routed plaintext protocol content and metadata".
  Self-hosting collapses "the operator" onto the user, which is the only reason
  this is acceptable, and is why the public
  `relay-rp1.jacobmoura.work` must never be the default.
- **On a Bun-built pi, pairing falls back to the file identity.** The platform
  keyring binding does not resolve under Bun (upstream issue #113, §17.4.1), so
  Tier 2 on `coding-agent-bun` will use `~/.pi/remote/identity.json` at `0600`
  rather than the OS keyring. That path is documented and supported, but it is
  a plaintext key on disk, and it must be said before anyone pairs a phone.

### 17.8 Consequences for `mkPiExtension` (§8): much smaller than first thought

The first version of this addendum argued for three new `passthru` fields
(`configFiles`, `piSkills`, `runtimeInputs`) and a redefinition of `bundled`.
Packaging `remote-pi` instead of `pi-intercom` retires most of that.

**Consume the phase-2 contract; do not redefine it.** As of this writing,
`docs/plans/2026-08-18-pi-nix-fork.md` Task 3 defines, for both `mkPiExtension`
and `mkPiPlugin`:

| Field | Type |
| --- | --- |
| `passthru.piEntrypoint` | **`list of str`** — absolute paths for repeated `--extension`; defaults to a one-element list holding the package root, which makes pi read the package's own `pi` manifest |
| `passthru.piSkills` | `list of str` — absolute paths for `--skill` |
| `passthru.piPrompts` | `list of str` — absolute paths for `--prompt-template` |
| `passthru.settings` | `attrs` — merged into `~/.pi/agent/settings.json` |
| `passthru.promptFragment` | `null` or `str` — appended via `--append-system-prompt` |

`remote-pi` uses **`piEntrypoint` (default: the package root, so pi reads
`pi.extensions = ["./dist"]`) and `promptFragment`, and nothing else.**

- **`configFiles` is not needed.** `REMOTE_PI_DIRECT_CONFIG` carries the whole
  local config inline (§17.4.1). Nothing is written to disk by us.
- **`runtimeInputs` is not needed.** Nothing is spawned (§17.4.1), so no
  binary has to exist inside the jail beyond pi itself.
- **`piSkills` is deliberately left empty.** The package registers its own
  skill directory through `resources_discover` after copying `SKILL.md` into
  `~/.pi/remote/skills/`. Passing `--skill` as well would double-register.
  Design assumption A3 is therefore decided *for this package* by controlling
  `REMOTE_PI_HOME`, not by a `--skill` flag.
- **`bundled` keeps its §8 meaning.** `remote-pi` ships a real prebuilt
  `dist/`, and still needs `node_modules` for four packages, so it takes the
  ordinary dependency-materialising branch. The proposed redefinition of
  `bundled` as "needs no npm build step" was an artefact of `pi-intercom`
  shipping raw TypeScript, and is withdrawn.

**Two things `mkPiExtension` does need, both arguments rather than passthru:**

1. **A bun2nix path.** Phase 2 is moving from `buildNpmPackage`/`npmDepsHash`
   to `bun2nix` (already a flake input of the fork, `github:nix-community/bun2nix?ref=2.1.0`,
   and already used by `coding-agent/package-bun.nix` via `bun2nix.hook` +
   `bun2nix.fetchBunDeps`). Extensions must be built the same way, from a
   committed per-extension `bun.lock` + `bun.nix`.
2. **Dependency pruning.** A `keepDependencies :: listOf str` argument that
   rewrites the package's `dependencies` before the lockfile is generated.
   Without it `remote-pi` drags 216 packages including `@aws-sdk` and
   `@anthropic-ai` into the closure to satisfy declarations its extension
   entrypoint never touches. With it: 4 packages, 708 KB.

**Stated mismatch, so it is visible rather than silent.** At the time of
writing, `docs/plans/2026-08-18-pi-nix-fork.md` is being revised concurrently
and its Task 3 text still shows the `buildNpmPackage`/`npmDepsHash` signature.
This plan assumes phase 2 lands the five passthru fields above **unchanged**
and switches the build to bun2nix. If phase 2 also adds `configFiles` or
`runtimeInputs`, `remote-pi` simply does not use them and nothing breaks. If
phase 2 keeps `buildNpmPackage`, Task 1 of the implementation plan is the
adapter and says so in its own header comment.

### 17.9 Security analysis: `remote-pi`'s own model, measured

**Assets.** The agent's tool authority (bash under a jail with `network` and
`mount-cwd`), the session transcript, and the user's attention.

Everything in this section was verified by running `remote-pi 0.7.0`'s own
shipped `dist/session/{global_config,leader_election,broker}.js` under
`REMOTE_PI_HOME=/tmp/…` on 2026-08-18. The transcripts are reproduced.

#### Risk 1: inbound peer message starts a turn, with no knob. Most serious.

`dist/index.js` delivers every inbound mesh envelope like this:

```js
pi.sendMessage(_meshMessageForAgent(env),
  isLast ? { triggerTurn: true, deliverAs: "followUp" } : { triggerTurn: false });
```

and `_meshMessageForAgent` builds `{ customType: "remote-pi:mesh-message",
content, display: true }`, whose own comment says: "the SDK's `convertToLlm`
maps custom → **a user-role LLM message**, so the agent still sees + replies to
it".

So an inbound message from any peer **starts a model turn** and arrives as a
user-role message. `grep -rn "triggerTurn"` over the whole `dist/` returns
exactly those two lines and one comment: **there is no configuration option to
disable it.** This is `pi-intercom`'s `inboundTrigger: "always"` behaviour,
hardcoded.

This routes around §9 completely: layers 2 and 3 gate tool *calls*, never the
provenance of instructions.

Two things here beat `pi-intercom`. The body is wrapped in
`[agent-network] message from "<address>" (id=…):`, so provenance reaches the
model in-band, and it renders in the app's *tool* timeline rather than as the
user's own message. Neither changes the authority the text carries.

**Mitigation (Tier 1, mandatory, implemented as a plan task with tests):**
patch `dist/index.js` so `triggerTurn` is read from the environment, defaulting
to **`false`**. `triggerTurn: false` is upstream's own delivery path for every
non-final message in a batch, so the message is still appended to the session
and displayed. The agent sees it on its next turn; it just does not get to
*start* one. `REMOTE_PI_INBOUND_TRIGGER=always` restores upstream behaviour as
an explicit per-host opt-in.

#### Risk 2: unauthenticated registration with a client-supplied address.

`broker.js` `_handleRegister` accepts `{ type: "register", name, cwd,
takeover? }` and performs **no credential check**. No `SO_PEERCRED`, no
`getPeerCredentials`, no uid comparison: `grep -rn
"peerUid\|SO_PEERCRED\|process.getuid"` over `dist/` returns one unrelated
`systemctl --user` helper and nothing else. The only validation is `isValidRegisteredCwd` (a
length/shape bound) and `sanitizeMeshName`.

Measured, against the real broker:

```
register reply: {"type":"register_ack","address_assigned":"/tmp@attacker","name_assigned":"attacker"}
```

The `cwd` is **client-supplied and never verified against the peer's actual
working directory**, and it is *half the routing address*: `composeAddress`
yields `<cwd>@<name>`. So a process can register as
`/home/joe/some-other-repo@planner` from anywhere on the machine. `broker.js`
does force `env.from = conn.address` on routed envelopes, which stops a
registered peer spoofing a *different* peer on a message it sends. But it pins
you to the address you *claimed*, not to one you proved.

Compared with `pi-intercom`: intercom's README says `peerUid` "is reserved for
runtimes that can expose real peer credentials and is left unset otherwise"
and that client-supplied cwd/model/pid/status "are display metadata, not
authentication". So neither authenticates. The difference is that in
`pi-intercom` the unverified cwd is *only* display metadata, whereas in
`remote-pi` it is **load-bearing routing identity**.

#### Risk 3: unauthenticated `takeover` evicts a live peer. Worse than intercom.

`_identityForRegister(cwd, requested, takeover)`:

```js
if (takeover && cwd && this.peers.has(direct.address)) {
  return { ...direct, replaceAddress: direct.address };
}
```

and `_dropPeerAt` deletes the incumbent from the peer map, blanks its address so
its own close handler cannot clean up the replacement, and `socket.destroy()`s
it. The flag is set purely by the client: `req.takeover === true`. It exists for
legitimate daemon restarts. It is gated on nothing.

Measured, three connections against one real broker:

```
victim  ack: {"type":"register_ack","address_assigned":"/home/joe/secret-repo@planner","name_assigned":"planner"}
attacker ack: {"type":"register_ack","address_assigned":"/home/joe/secret-repo@planner","name_assigned":"planner"}
victim  socket DESTROYED by broker
```

The attacker now **owns the victim's exact address**. Every subsequent
`agent_send` aimed at `/home/joe/secret-repo@planner` is delivered to the
attacker, and every envelope the attacker emits carries `from` =
`/home/joe/secret-repo@planner`, broker-forced and therefore *credible*. The
anti-spoofing measure becomes the impersonation guarantee. `pi-intercom` has no
equivalent primitive.

**Mitigation (Tier 1, mandatory):** patch `broker.js` to pass `false` for
`takeover` unconditionally. Nothing in local mode needs it; `#N` suffixing
already handles same-name collisions. The plan carries an end-to-end regression
test that attempts the takeover above and asserts the attacker is demoted to
`…@planner#2` and the victim's socket stays open.

#### Risk 4: the socket tree is `0755`, and the audit log holds message bodies.

`ensureGlobalDirs()` is `mkdirSync(SESSIONS_DIR, { recursive: true })` with **no
`mode`**. Same at `index.js:3808` for the per-session directory. The socket is
created by `server.listen(sockPath)`, whose mode is `0777 & ~umask`. Measured:

```
umask         : 0022
~/.pi/remote  : 755
sessions dir  : 755
session dir   : 755
broker.sock   : 755
```

Under the default `umask 022` this is *survivable*: connecting to a Unix socket
on Linux requires **write** permission on the socket inode, and `0755` denies
write to group and other, so only the owner can connect. But that is an
accident of umask, not a design. Re-measured under `umask 002`, which is a
Debian-style default, a shared-group setup, or any systemd unit with
`UMask=0002`:

```
umask 002 -> broker.sock mode: 775
```

**Group-writable.** At that point every member of the user's group can open the
broker and exercise Risks 2 and 3.

`pi-intercom` creates its directory `0700` and its runtime files `0600`
explicitly (`broker/paths.ts`). `remote-pi` passes no mode anywhere.

Separately, `broker.js:502` `appendFile`s every routed envelope, **bodies
included**, to `~/.pi/remote/sessions/local/audit.jsonl` with no `mode`
argument, so `0666 & ~umask`. Inter-agent message traffic is a plaintext log
under a `0755` tree.

**Mitigation (Tier 1, mandatory):** the pi launcher sets `umask 0077` before
exec, and pre-creates/`chmod 0700`s `$REMOTE_PI_HOME/.pi/remote/sessions/local`
and `$REMOTE_PI_HOME/.pi/remote-pi/socks` so an already-`0755` tree from a
pre-Nix run is repaired rather than inherited. `umask 0077` applies to
everything pi writes for the rest of the process. That side effect is intended.

#### Risk 5: the jail bind is a cross-jail lateral-movement primitive.

§7's `configPermission` bind-mounts `$PI_CODING_AGENT_DIR` into *every* pi
jail. Whatever directory holds the broker socket is, by construction, inside
every sandbox: that bind is exactly what makes cross-jail messaging work, and
exactly what makes cross-jail injection work. The two cannot be separated at
the mount layer.

`remote-pi` puts its socket under `$REMOTE_PI_HOME/.pi/remote/`, default
`$HOME`, which the jail does **not** necessarily bind. The implementation plan
sets `REMOTE_PI_HOME="$PI_CODING_AGENT_DIR"` in the launcher. That is an ugly
path (`~/.pi/agent/.pi/remote/`), chosen so the mesh state lands inside the
directory the jail already binds and cross-jail messaging works without a new
mount. The security consequence is the same either way; it is written down here
so nobody discovers it later.

Combined with Risks 1–3 unhardened, the chain would be: a malicious npm
`postinstall`, a repo `Makefile`, or a compromised extension running under the
same uid registers on the broker, takes over another repository's agent
address, and authors user-role instructions that immediately start a turn in a
pi session whose jail mounts a *different* repository. With the three
mitigations, the same attacker can still register and still deliver text. It
cannot take an address that is in use, and what it delivers does not start a
turn and is labelled as peer input by the prompt fragment.

Residual: an attacker already running as this uid can rewrite the launcher, the
config, or `$PATH`. `0700` and a patched broker do not fix that and are not
claimed to. They fix the cheap path, the one that needs nothing but a connect(2)
to a socket sitting at `0755`.

#### Risk 6: attention and correctness, not security.

`agent_send` unicast blocks on a **5s** broker ACK (`ACK_TIMEOUT_MS`), which is
short and safe. The deprecated `agent_request` blocks for **30s**
(`LEGACY_REQUEST_TIMEOUT_MS`). Neither approaches `pi-intercom`'s 10-minute
`ask` default, so the attention-denial risk that mitigation targeted is
materially smaller here. `list_peers` is a 2s metadata query.

#### Risk 7: supply chain by name.

See §17.4.3. `pi-chat` on npm is not `lynxz/pi-chat` on GitHub. Every pin must
be resolved through the registry's `repository` field and confirmed against the
repo, never by name recall. For this pin the field must read
`git+https://github.com/jacobaraujo7/remote_pi.git`.

#### Risk 8 (Tier 2 only): relay trust.

§17.7. Not adopted in this phase. Note also that on a Bun-built pi the
Ed25519 identity falls back to a `0600` file rather than the OS keyring.

#### One non-risk, recorded so nobody re-derives it.

Bubblewrap does not impede this. A Unix domain socket is a filesystem object;
two jails that bind-mount the same host directory share the same inode and
connect normally. No network namespace is involved. And in local mode no
outbound network is opened at all: `_cmdStart` is the only caller of the relay
client, and it is gated on `auto_start_relay`.

### 17.10 New assumptions

Continuing §4's numbering. Each is called out again at its point of use in the
implementation plan. A11 and A12 from the first version are superseded.

| # | Assumption | Fallback if false |
| --- | --- | --- |
| A6 | **Verified true.** pi resolves an extension's bare imports (`typebox`, `@earendil-works/*`) through the `NODE_PATH` the pi wrapper exports, *including under Bun*. Measured: `NODE_PATH=… bun run probe.js` resolved a bare specifier on bun 1.3.13, and `coding-agent/package-bun.nix` sets `--prefix NODE_PATH : $out/lib/node_modules`. | Symlink pi's `lib/node_modules` into the extension derivation as its own `node_modules`. |
| A7 | `pi.sendMessage(msg, { triggerTurn: false })` still *delivers* the message (appended to the session, `display: true` rendered) rather than dropping it. Upstream uses that exact call for every non-final message in a batch, so it is upstream's own semantics — but it has not been observed end-to-end in a live pi. | Ship `triggerTurn: true` and rely on the §17.9 prompt fragment alone; revisit if that is too weak. |
| A8 | A broker bound inside one bubblewrap jail stays reachable from a second, differently-mounted jail through the shared `$PI_CODING_AGENT_DIR` bind, given `REMOTE_PI_HOME="$PI_CODING_AGENT_DIR"`. | Set `REMOTE_PI_HOME` to a host path bound into every jail by an explicit `jail.permissions` entry instead of relying on `configPermission`. |
| A9 | `remote-pi`'s ~18 lifecycle listeners and §6's `agent-statusline` extension can both subscribe to pi's events without interfering. `remote-pi` also owns the window title and a footer segment (`📡 local (N)`), which *is* a plausible collision with the statusline. | Statusline wins; disable `remote-pi`'s footer by leaving the relay off (the `🟢 relay` segment never renders) and accept the `📡 local (N)` segment, or drop the statusline's peer field. |
| A10 | `REMOTE_PI_DIRECT_CONFIG` fully suppresses the first-run wizard in an interactive session, because `localConfigExists(cwd)` returns true for any parseable object. Read in `local_config.js`; not yet observed in a live pi. | Run `/remote-pi setup` once per repository and let it write `<cwd>/.pi/remote-pi/config.json`; add that path to the repo `.gitignore`. |
| A11 | *(supersedes old A11)* With `auto_start_relay: false`, `_cmdRootInner` still joins the local mesh — verified in source — **but** the `session_start` auto-init at `index.js:2110` is gated on `effectiveAutoStartRelay(...)`, so a local-only session does **not** auto-join and needs one `/remote-pi` per session. The plan patches that gate. | Accept one `/remote-pi` invocation per session; it is idempotent and prints status. |
| A12 | *(supersedes old A12)* bun2nix `2.1.0` builds an extension's four-package `node_modules` from a committed `bun.lock` + `bun.nix` the same way it builds pi's own. The `bun.nix` for this pin was generated and is reproduced verbatim in the plan. | Vendor the four tarballs as individual `fetchurl`s and assemble `node_modules` in `installPhase`; at four packages with zero transitive deps this is tractable by hand. |
| A13 | Pruning `dependencies` to `@noble/ed25519`, `croner`, `qrcode-terminal`, `ws` leaves every code path the *extension* uses intact. Derived from a static import-graph walk of `dist/index.js` (42 files). `remote-pi claude` (MCP) and Noise pairing are knowingly broken by the pruning. | Restore `@modelcontextprotocol/sdk` + `zod` (for `remote-pi claude`) or `@napi-rs/keyring` + `noise-protocol` (for pairing) to `keepDependencies` at Tier 2. |

### 17.11 Rollout position

§15 orders the work 1–6. Messaging depends on `mkPiExtension` (phase 2) and on
the jail config (phase 3), and its prompt fragment wants to land with the other
fragments (phase 5). It slots in as **phase 3.5**: after the jail exists, so A8
is answerable rather than hypothetical, and before the fragments are frozen.

Tier 2 (the `erdtree` relay + phone pairing + cross-machine peers) is **phase 7,
optional**, and should not be started until same-machine messaging has been
used in anger for long enough to know whether cross-machine is a real want or a
tidy idea. It is deferred, not cancelled: §17.7 stays specified so the decision
stays cheap.

### 17.12 Risks

| Risk | Impact | Mitigation |
| --- | --- | --- |
| Inbound message auto-starts a turn as a user-role message | Cross-jail lateral movement | Patch `triggerTurn` to default `false` (§17.9 Risk 1); untrusted-input prompt fragment; `hard_deny` backstop |
| Unauthenticated `takeover` steals a live peer's address | Full impersonation of another repo's agent | Patch `takeover` to `false` unconditionally, with an end-to-end regression test (§17.9 Risk 3) |
| `0755` socket tree; `0664` audit log under `umask 002` | Group-local attacker gets the broker and the message log | `umask 0077` in the launcher + explicit `0700` pre-creation (§17.9 Risk 4) |
| A11: local-only sessions do not auto-join | Silent no-op — peers never see each other | Patch the `session_start` gate; fallback is one `/remote-pi` per session |
| A7 false: `triggerTurn: false` drops rather than defers | Messages silently lost | Revert to `true` + prompt fragment; the smoke test would catch it |
| Pin churn — 17 versions since 2026-05-22, four `substituteInPlace` patches | A bump breaks a patch | `--replace-fail` makes every patch a build-time drift alarm; `nix run .#update` bumps the pin and CI runs the takeover regression test |
| No `pi-subagents` bridge | Subagent↔supervisor channel unavailable | Re-open in phase 3; `messaging.package` makes adding `pi-intercom` alongside a one-line change (§17.6.3 item 3) |
| Footer/title collision with `agent-statusline` | Cosmetic | A9 |
| Upstream folds messaging into pi itself | Extension becomes redundant | Delete one pin; the `messaging` option keeps its shape |

### 17.13 Retained fallback blueprint: `pi-agents-talk-to-each-other`

**Not installed.** Kept here, deliberately, as the design to fall back to if
`remote-pi`'s transport proves troublesome: leader-election races, a broker that
dies with the wrong pi, or a patch that stops applying at a pin bump.

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

1. **It has no transport to go wrong.** Every failure mode in §17.9 Risks 2–4
   is a property of a socket broker. A directory of JSON files has filesystem
   permissions as its *only* access-control mechanism, which is exactly the
   mechanism Nix and the jail are already good at.
2. **One file, MIT, 1,443 lines.** That is small enough to vendor and audit in
   full rather than pin, which is the honest response to "the upstream project
   is unmaintained".
3. **Its safety notes are candid**: "does not authenticate senders", "the flag
   file is not cryptographically protected". Candour is not a substitute for
   maintenance, but it does mean the threat model is already written down.

If it is ever adopted, adopt it as a *vendored blueprint*, not a pin: copy the
file into `pi-nix/packages/extensions/`, keep the MIT notice, and treat the
polling loop and the room schema as the parts worth keeping.
