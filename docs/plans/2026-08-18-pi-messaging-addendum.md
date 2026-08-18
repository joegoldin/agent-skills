# Design addendum: inter-instance messaging for pi

Date: 2026-08-18
Status: proposed
Extends: `docs/plans/2026-08-18-pi-nix-agent-stack-design.md` as **§17**, a
seventh subsystem alongside `agent-statusline`, `pi-nix`, permissions/sandbox,
`pi-notify`, the `agent-skills` pi target, and the prompt fragments.

## 17. Inter-instance messaging

### 17.1 Context

The main spec catalogues six things pi omits and assigns each an ecosystem
answer (§1, §8). It misses a seventh, because the gap is not one of pi's
documented omissions — it is a capability Claude Code has that no one thinks to
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
`subagent-driven-development` do **not** name `SendMessage` or `ListAgents` —
`grep -rn "SendMessage\|ListAgents" --include='*.md'` over `agent-skills`
returns zero hits. Their hard dependency is fan-out dispatch, which §11 already
assigns to `pi-subagents`. So the skills do not break without messaging.

What they lose is the mid-flight half, and it is not small:

- `subagent-driven-development` runs implementer → reviewer → fix subagent in a
  loop and tells the coordinator not to pause between tasks. Without a peer
  channel, an implementer that hits genuine ambiguity has exactly one move:
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
scale reference — it is the phase-3 pin, not a messaging candidate.

| Package | Transport | External infra | dl/wk | ★ | Last publish | Ver. | Commits | License |
| --- | --- | --- | ---: | ---: | --- | ---: | ---: | --- |
| **`pi-intercom`** | Unix domain socket, auto-spawned broker, length-prefixed JSON | **none** | **6,965** | **440** | 2026-08-12 | 27 | 79 | MIT |
| `pi-mesh-extension` | local broker, `mesh.v1` | none | 6,447 | 2 | 2026-08-17 | 53 | 69 | MIT |
| `pi-crew` | orchestration over worktrees + task files | none | 1,708 | 49 | 2026-08-13 | 198 | 1,772 | MIT |
| `remote-pi` | UDS mesh locally; **WSS relay** for phone + cross-PC | relay (optional) | 837 | 261 | 2026-08-12 | 17 | 822 | MIT |
| `agent-comms` | TCP mesh, cross-harness rooms/DMs | daemon | 256 | 16 | 2026-08-03 | 58 | 342 | none |
| `pi-messenger` | file-based registry, shared broadcast room | none | 195 | 684 | 2026-07-30 | 23 | 50 | **none** |
| `@cryptolibertus/pi-peer` | UDS under `$TMPDIR/pi-peer-coms`, HMAC-SHA256 | none | 116 | 9 | **2026-05-28** | 48 | 202 | MIT |
| `pi-peer` (MinhDuyDEV) | HerdR workspace mux | **HerdR** | 59 | 0 | 2026-08-08 | 2 | 10 | MIT |
| `pi-agent-bus` | MessageBus pub/sub via `pi-link` | pi-link | 25 | 0 | 2026-06-05 | 7 | — | MIT |
| `pi-agents-talk-to-each-other` | file polling under `~/.pi/agent/rooms/` | none | 18 | 0 | 2026-06-28 | 3 | 18 | MIT |
| `pi-chat` (npm) | WebSocket → Cloudflare Worker | **relay** | 2 | — | 2026-03-24 | 1 | — | **none** |
| `lynxz/pi-chat` (GitHub) | HTTP + SSE server, Docker | **self-hosted server** | not published | 0 | 2026-07-20 | — | 6 | Unlicense |
| `wowyuarm/pi-talk-to-sessions` | reads another session's `.jsonl`, replays it into a throwaway sub-session | none | not published | 0 | 2026-07-14 | — | 2 | MIT |
| *(ref)* `pi-subagents` | child processes | none | 56,532 | — | — | 51 | — | — |

### 17.4 The four flagged candidates, individually

**1. `lynxz/pi-chat` — reject, and note the name hazard.**
The repo is a real design: a zero-dependency `node:http` + SSE chat server, a pi
extension with `chat_send` / `chat_history` / `chat_whoami`, room access tokens,
opt-in TLS, and a `docker-compose.yml` wiring two containerised agents. It is
also 6 commits old, 0 stars, unlicensed-by-Unlicense, and **not published to
npm**. It requires a server for the same-machine case that a socket solves for
free.

More importantly it exposes a supply-chain trap. The npm package named
`pi-chat` is a *different project by a different author*: one version, published
2026-03-24 (three and a half months before the GitHub repo was created), no
`repository` field, no license, a README pointing at `/Users/vegard/dev/irc-clone`,
no `pi` key in `package.json` (so it is not a pi package at all), and a client
whose `DEFAULT_SERVER` is hardcoded to a stranger's Cloudflare Worker. §8 already
warns to pin by verified repository URL rather than remembered author name.
This is that warning with a name attached.

**2. `Timur00Kh/pi-agents-talk-to-each-other` — reject on maturity, credit its honesty.**
File-based rooms under `~/.pi/agent/rooms/`, no daemon, no sockets. `room_list_agents`
and `room_send_message` are close to `ListAgents`/`SendMessage`, and it gates
`room_control_agent` behind an opt-in per-agent flag. It is also 18 commits, 3
versions, 0 stars, 18 dl/wk, last touched 2026-06-28, and its own README says
`reload` and `new_session` are broken because pi does not process slash commands
from extension-injected messages. Its safety notes are candid — "does not
authenticate senders", "the flag file is not cryptographically protected" — which
is more than most candidates manage, but candour is not a substitute for a
maintained project.

**3. `wowyuarm/pi-talk-to-sessions` — reject on category error.**
It does not do inter-instance messaging. It opens another session's `.jsonl`
**read-only**, rebuilds that session's effective context in a throwaway
in-memory sub-session with zero tools, asks it a question, and returns the
answer. The target is a transcript on disk, not a running process; nothing is
delivered to a live peer and a live peer cannot reply. 2 commits, not on npm.
The idea — interrogating a dormant session's memory — is genuinely useful and
orthogonal, but it is a retrieval feature, not this capability.

**4. `remote-pi` — strong project, wrong tier, and the relay premise needs correcting.**
261 stars, 822 commits, 17 npm versions, published 2026-08-12, MIT, a Flutter
mobile client, a Rust relay, and a bundled `dist/` (186 files). Real engineering.

**The relay is not required for agent-to-agent messaging.** Its own README:
"When multiple Pi agents run on the same machine, they discover each other
through a **Unix Domain Socket broker** managed by the extension… For targets on
that same machine, agents use the opaque addresses returned by `list_peers` — no
relay, no network, no extra config." The setup wizard confirms this in code —
`dist/session/setup_wizard.js` asks "Use the relay on this terminal to connect to
the remote mesh (mobile + PCs)?" and comments that "No" means "local-only: this
Pi joins the UDS mesh but doesn't open WSS."

So the framing in the brief is off by one tier: the relay buys **phone control
and cross-machine routing**, not peer messaging. Hosting one is indeed trivial
(§17.6), but for same-machine peers it buys nothing, and it drags in a
1.3 MB extension whose primary product is a mobile app.

Its local tools are also a weaker fit than the recommendation. `agent_send`
returns a delivery ACK; `agent_request` is marked DEPRECATED in the shipped
source ("prefer `agent_send` + observing your inbox"), which means the
request/response shape the skills actually need is the shape the project is
moving away from. It also ships a `tool_gate` that hard-codes `Read`/`Glob`/`Grep`
as auto-approved and everything else as "ask" — a fourth, uncoordinated
permission layer landing underneath §9's carefully ordered three.

### 17.5 Also-rans from the gallery and awesome-pi

`https://pi.dev/packages` and `BubblePtr/awesome-pi` (89★) were both swept.
awesome-pi's *Communication & Collaboration* section lists five entries:
`pi-crew`, `pi-intercom`, `@cryptolibertus/pi-peer`, `@llblab/pi-telegram`, and
`agent-comms`. The gallery's front page carries `pi-intercom` among 58 packages.

- **`pi-mesh-extension` (6,447 dl/wk) — reject on unverifiable popularity.**
  Downloads within 8% of the recommendation, against **2 stars**, a repository
  created 2026-08-07, and 53 published versions in 11 days. Downloads with no
  corroborating signal are not evidence of use; that ratio is the shape of
  automated installs, not adoption. Revisit in a quarter.
- **`pi-messenger` (684★) — reject on model and license.** Same author as the
  recommendation, and its README table draws the line for us: pi-messenger is a
  *shared broadcast room* with a file-based registry, for swarms working one
  task. We need targeted 1:1 addressing. It also has **no license field on npm
  and no license on the repository**, which is disqualifying for anything
  entering a Nix closure.
- **`pi-crew` (1,708 dl/wk, 1,772 commits) — reject on scope.** Team/workflow
  orchestration with worktrees and async task graphs, an 8.99 MB unpacked
  tarball, and 198 published versions. It subsumes plan mode, todos, and
  subagents — colliding head-on with §8's `@plannotator/pi-extension`,
  `@juicesharp/rpiv-todo`, and `pi-subagents`. Adopting it means re-deciding
  four pins at once.
- **`agent-comms` (ExaDev) — reject, but flag it for later.** Cross-harness
  rooms/DMs/presence over TCP for "Claude, Codex, Pi, Antigravity, and A2A
  agents" — the only candidate that spans all four agents in this setup, which
  is genuinely the right long-term shape. Today: 16★, 256 dl/wk, **no license
  on npm or the repo**, and a TCP daemon where a socket suffices. Watch it.
- **`@cryptolibertus/pi-peer` — reject on staleness and socket location.**
  Last publish 2026-05-28, ~3 months stale, 9★. It does authenticate — HMAC-SHA256
  over a per-peer token — which is more than the recommendation does. But its
  discovery directory is `$TMPDIR/pi-peer-coms`, i.e. `/tmp`, which is
  world-traversable and shared with every other user and daemon on the machine.
  A 46-file `src/peers/` tree including `hive-supervisor`, `plan-adversary`, and
  `self-improve` is also far more surface than the capability needs.
- **`pi-peer` (MinhDuyDEV) — reject.** Hard dependency on the HerdR workspace
  mux (`herdr.ts` shells out to it for pane identity). 0★, 10 commits, 2 versions.
- **`pi-agent-bus` — reject.** 25 dl/wk, last publish 2026-06-05, requires
  `pi-link`.

### 17.6 Recommendation

**Adopt `pi-intercom`, pinned by verified repository `nicobailon/pi-intercom`.
No relay. No new infrastructure of any kind.**

Five reasons, in order of weight.

1. **It is the only candidate whose popularity is corroborated.** 6,965 dl/wk
   *and* 440★ *and* 79 commits *and* 27 published versions over five months
   *and* placement on the pi.dev gallery front page *and* an awesome-pi listing.
   `pi-mesh-extension` matches only the first number.
2. **Same maintainer as `pi-mcp-adapter`.** §8 already pins `pi-mcp-adapter`
   (1,265★) and `pi-subagents`, both from `nicobailon`. Adding `pi-intercom`
   adds no new author to the trust surface — it consolidates onto one that is
   already load-bearing. `pi-intercom` ships explicit `pi-subagents` integration
   (`contact_supervisor`, gated on `PI_SUBAGENT_*` env vars), so the phase-3
   subagent axis and this peer axis interlock instead of competing.
3. **The semantics map onto the gap exactly, and then exceed it.**
   `intercom({action:"list"})` is `ListAgents` — name, short ID, cwd, model, and
   a live `idle`/`thinking`/`tool:<name>` status derived from pi lifecycle
   events. `intercom({action:"send"})` is `SendMessage`. `intercom({action:"ask"})`
   blocks the caller until the peer replies and returns the reply as the tool
   result — the thing `subagent-driven-development`'s implementer needs and that
   Claude Code does not have. `reply`, `pending`, `cancel`, and `supersedes` fill
   in the rest. Delivery into a busy peer goes through pi's steering queue at the
   next safe model boundary rather than aborting its turn.
4. **Zero infrastructure, and a real Nix seam.** A Unix domain socket at
   `$PI_CODING_AGENT_DIR/intercom/broker.sock`, in a directory created `0700`
   with runtime files `0600` (`broker/paths.ts`). The broker auto-spawns on first
   use and exits 5s after the last client leaves, so there is no daemon to
   manage. Critically, `config.json` exposes `brokerCommand`/`brokerArgs`, which
   lets the module replace the upstream `npx --no-install tsx` launch with a
   store path — no PATH resolution, no network, no npx.
5. **It packages purely with no build step.** Verified, not assumed:
   - The broker's transitive import set is **node builtins only** — `net`, `fs`,
     `path`, `crypto` plus relative `.ts` files. No `node_modules` required.
   - The extension's only bare imports are `@earendil-works/pi-ai`,
     `@earendil-works/pi-coding-agent`, `@earendil-works/pi-tui`, and `typebox`
     — all four present at
     `…-pi-coding-agent-0.84.2/lib/node_modules/`, which pi-nix's own wrapper
     exports as `NODE_PATH` (read directly out of `result/bin/pi`).
   - The single npm dependency is `tsx ^4.20.0`; `pkgs.tsx` is 4.21.0 and
     provides a `tsx` binary.

   So `bundled = true` (fetchurl the registry tarball, use as-is) is correct
   even though the package ships **no `dist/`** — see §17.8.

Weakest link, stated up front: the broker authenticates nobody. §17.9.

### 17.7 The relay, called out explicitly

The recommendation needs no relay. This section exists because the brief asks
for the cost to be stated anyway, and because a cross-machine tier is a
plausible later want — the user runs eleven Nix hosts.

**A relay is required only if pi instances on different machines must message
each other.** For the same-machine case — which is what
`subagent-driven-development` and `dispatching-parallel-agents` actually need —
both `pi-intercom` and `remote-pi` operate over a local socket with no server.

If cross-machine is adopted later (Tier 2, `remote-pi`), hosting on `erdtree`
entails:

| Item | Reality |
| --- | --- |
| Software | `relay/` in `jacobaraujo7/remote_pi`, tag `v0.4.0` = `cc2589f`. Rust 2024, axum 0.7 + tokio, `rusqlite` with `bundled` (no system sqlite). `Cargo.lock` committed. Source SRI: `sha256-0Mm7V4bTwNW7dxoeoSw/liCdiJlOxdKxIFUN3zsc79E=` |
| Nix | `rustPlatform.buildRustPackage` with `sourceRoot = "source/relay"`. Fallback `virtualisation.oci-containers` with `jacobmoura7/remote-pi-relay` |
| Deployment | Exactly the `wings.nix` shape: `den.aspects.erdtree.nixos`, one `systemd.services.*` with `DynamicUser` + `StateDirectory`, one port |
| Ports | One. `REMOTEPI_RELAY_PORT` (default 3000) serves the WS upgrade, `/health`, and `/mesh/*` together |
| State | SQLite at `REMOTEPI_MESH_DB_PATH`. Owner-signed membership metadata only, never message traffic. Rollback-journal mode, so `mesh.db` is the whole backup |
| CI | garnix already builds `erdtree`; a Rust derivation is one more `nix build` target |
| Effort | Genuinely trivial — one systemd unit and one `StateDirectory`, comparable to `attic-cache.nix`, an order of magnitude below `garnix.nix` |

**The part that is not trivial, and must not be glossed:**

- **The relay has no operator authentication to configure, so agenix has no
  server-side secret to hold.** Any peer that completes the Ed25519
  challenge-response is accepted; authorisation is per-route, from Owner-signed
  membership blobs the clients publish. There is no admin token, no allowlist,
  no bearer gate. An agenix secret would be inventing one.
- **Therefore the network *is* the boundary.** The honest deployment is
  tailnet-only: bind to `erdtree`'s `tailscale0` address, no Caddy vhost, no
  public DNS record, and the existing `trustedInterfaces = [ "tailscale0" ]`
  does the gating. Publishing it on `*.turnin.quest` behind Caddy — the reflex
  for every other service on that host — would expose an unauthenticated
  routing service to the internet.
- **agenix's real job here is the URL, not a credential.** House convention
  keeps hostnames in `dotfiles-secrets/domains.nix`; the client reads it via
  `environment.REMOTE_PI_RELAY_URL.file`, which the upstream `environment`
  option already supports with a tagged `{ file = …; }` value. The genuine key
  material — each host's Ed25519 pairing keypair under `~/.pi/remote/` — is
  generated on the client and must never enter the store or agenix.
- **Route eligibility is not proof of control.** The relay README, verbatim:
  a Pi↔Pi route is permitted when "any correctly signed Owner blob directly
  lists both canonical Pi keys… that check does not prove the Owner paired with
  or controls either Pi". Payloads are not end-to-end encrypted; Pi→Pi envelopes
  are parsed in the relay process for routing. Self-hosting collapses "the
  operator" onto the user, which is the only reason this is acceptable — and is
  precisely why the public `relay-rp1.jacobmoura.work` must never be the default.

### 17.8 Consequences for `mkPiExtension` (§8)

Packaging `pi-intercom` shows §8's `passthru` contract
`{piEntrypoint, settings, promptFragment}` is one field short and one field
mis-specified.

**`settings` is not the only configuration surface.** `pi-intercom` reads
`$PI_CODING_AGENT_DIR/intercom/config.json` — not `settings.json`. Carrying its
config on `passthru.settings` would write it to a file the extension never
reads. §8's stated rationale for `settings` ("adding or removing one is a single
list edit with no dangling config") holds only if the contract can express
extension-owned config files. Add:

```nix
passthru.configFiles = {
  # path relative to $PI_CODING_AGENT_DIR  →  JSON value
  "intercom/config.json" = { … };
};
```

The module writes these in the same launcher prelude that already merges
`settings.json` (§7's retained upstream behaviour), so the mechanism is one
code path, not two.

**Packages carry skills.** `pi-intercom`'s `package.json` has
`pi.skills = ["./skills"]`. Under `pi install` those load automatically; under
Nix we pass `--extension` and `--skill` explicitly, so the skill loads only if
we choose. Surface it as `passthru.piSkills :: listOf path` and let the module
decide — this is where A3 (double-loading against `~/.agents/skills`) gets
decided per package instead of globally.

**Extensions can need runtime binaries.** The broker launcher needs `nodejs` and
`tsx` on a path reachable from inside the jail. Carry them as
`passthru.runtimeInputs :: listOf package` so the module folds them into
`jail.permissions` via `add-pkg-deps` rather than the module hard-coding a
package list per extension.

**Amend the meaning of `bundled`.** §8 defines `bundled = true` as "ships
bundled `dist/`". `pi-intercom` ships **raw TypeScript with no `dist/`** and
still needs no build, because pi executes `.ts` extensions directly. Redefine
`bundled` as *"needs no npm build step"*, with the `false` branch reserved for
packages that genuinely require `buildNpmPackage`. This also disposes of A4 for
this package in the useful direction — and it matters, because `pi-intercom`
ships **no `package-lock.json`**, so `buildNpmPackage` could not be used here
even if we wanted to.

### 17.9 Security analysis

**Assets.** The agent's tool authority (bash under a jail with `network` and
`mount-cwd`), the session transcript, and the user's attention.

**Risk 1 — local message injection escalating to autonomous action. Most serious.**
The broker does not authenticate peers. Its README is explicit: `peerUid` "is
reserved for runtimes that can expose real peer credentials and is left unset
otherwise", and client-supplied cwd/model/pid/status "are display metadata, not
authentication". Any process running as the user that can open
`$PI_CODING_AGENT_DIR/intercom/broker.sock` can `register` and then `send` to
any session by name or ID.

With the upstream default `inboundTrigger: "always"`, that message **immediately
starts a model turn** in the target, and the injected text arrives as a *user*
message. This routes around §9 completely: layers 2 and 3 gate tool *calls*,
never the provenance of instructions. A malicious npm `postinstall`, a repo
`Makefile`, or a compromised extension running under the same uid gets to author
instructions for every other pi session on the box — including sessions whose
jail mounts a different repository. That is a lateral-movement primitive between
jails.

The jail makes this worse rather than better. §7's `configPermission`
bind-mounts `$PI_CODING_AGENT_DIR` into *every* pi jail, so the socket is inside
every sandbox by construction. That bind is exactly what makes cross-jail
messaging work; it is also what makes cross-jail injection work. The two cannot
be separated at the mount layer.

Mitigations adopted:

1. **Default `inboundTrigger = "replies"`.** Only a reply to an `ask` this
   session originated may auto-trigger a turn. An unsolicited `send` is still
   rendered inline and stored in session history — it is delivered, just not
   obeyed unprompted. `always` remains available as an explicit opt-in per host.
2. **A prompt fragment classifying intercom bodies as untrusted peer input**
   carrying no user authority. Per §12's governing rule it states policy and
   names no tool, so the §12 inventory lint still passes.
3. **`hard_deny` is the backstop.** §9 already says user intent does not clear
   `hard_deny`; a peer message is not the user, so it clears even less.

Residual: with `always` opted in, injection → autonomous turn is a single hop.
Documented, not solved. `0700` on the directory means the attacker must already
be the same uid or root — which is also the point at which most of this
machine's other defences have already lost.

**Risk 2 — `brokerCommand` is arbitrary code execution by config file.**
`config.json`'s `brokerCommand`/`brokerArgs` choose the executable pi spawns.
Upstream labels it "advanced trusted local configuration" and warns that "anyone
who can edit this config can choose the executable used for future broker
auto-spawns". Nix ownership *improves* this: the module writes the file with a
store path, eliminating both the `npx` PATH lookup and Node's `tsx` module
resolution. A same-uid attacker can still rewrite it — true of everything under
`$HOME`, and not made worse here.

**Risk 3 — the extension bus.** `pi-intercom` advertises `extension-bus-v1`:
any two extensions declaring the same namespace exchange 16 KiB payloads and up
to 64 KiB of shared state through the broker, with membership as the only
authorisation. We enable no namespace and none of §8's pins declare one. Worth
re-checking at every pin bump.

**Risk 4 — attention denial.** `ask` blocks the calling agent's turn for up to
**10 minutes** by default. A peer that never replies stalls the caller for the
whole timeout. Set `PI_INTERCOM_ASK_TIMEOUT_MS` deliberately rather than
inheriting the default.

**Risk 5 — supply chain by name.** See §17.4(1). `pi-chat` on npm is not
`lynxz/pi-chat` on GitHub. Every pin must be resolved through the registry's
`repository` field and confirmed against the repo, never by name recall.

**Risk 6 (Tier 2 only) — relay trust.** §17.7. Not adopted in this phase.

**Non-risk, worth recording.** Bubblewrap does not impede this. A Unix domain
socket is a filesystem object; two jails that bind-mount the same host directory
share the same inode and connect normally. No network namespace is involved.

### 17.10 New assumptions

Continuing §4's numbering. Each is called out again at its point of use in the
implementation plan.

| # | Assumption | Fallback if false |
| --- | --- | --- |
| A6 | pi resolves an extension's bare imports (`typebox`, `@earendil-works/*`) through the `NODE_PATH` pi-nix's wrapper exports. Verified present in the wrapper; unverified for Node's *native* ESM resolver, which ignores `NODE_PATH`. | Symlink pi's `lib/node_modules` into the extension derivation as its own `node_modules`. |
| A7 | `inboundTrigger: "replies"` still *delivers* unsolicited sends visibly (inline render + session history) rather than dropping them. | Ship `always` and rely on the §17.9 prompt fragment alone; revisit if that is too weak. |
| A8 | A broker auto-spawned from inside one bubblewrap jail stays reachable from a second, differently-mounted jail through the shared `$PI_CODING_AGENT_DIR` bind. | Start the broker from the pi wrapper *outside* the jail, before `jailBuilder` wraps. |
| A9 | `pi-intercom`'s presence listeners and §6's `agent-statusline` extension can both subscribe to pi's lifecycle events without interfering. | None expected; they are independent listeners. If they collide, drop intercom's `status` field. |
| A10 | A Nix-declared `intercom/config.json` is never rewritten by pi or by `pi install`. | Harmless — the prelude rewrites it on every launch regardless. |
| A11 | *(Tier 2)* `remote-pi` can be configured local-only, or relay-connected, non-interactively without running its `/remote-pi` wizard. | Run the wizard once per host and keep `~/.pi/remote/` outside Nix. |
| A12 | *(Tier 2)* `rustPlatform.buildRustPackage` builds the relay from `sourceRoot = "source/relay"` with the committed `Cargo.lock` and edition 2024. | `virtualisation.oci-containers` with `jacobmoura7/remote-pi-relay`. |

### 17.11 Rollout position

§15 orders the work 1–6. Messaging depends on `mkPiExtension` (phase 2) and on
the jail config (phase 3), and its prompt fragment wants to land with the other
fragments (phase 5). It slots in as **phase 3.5**: after the jail exists — so
A8 is answerable rather than hypothetical — and before the fragments are frozen.

Tier 2 (`remote-pi` + the `erdtree` relay) is **phase 7, optional**, and should
not be started until same-machine messaging has been used in anger for long
enough to know whether cross-machine is a real want or a tidy idea.

### 17.12 Risks

| Risk | Impact | Mitigation |
| --- | --- | --- |
| Local message injection → autonomous action | Cross-jail lateral movement | `inboundTrigger = "replies"` by default; untrusted-input prompt fragment; `hard_deny` backstop (§17.9) |
| A6 false: ESM resolver ignores `NODE_PATH` | Extension fails to load | Symlink pi's `lib/node_modules` into the derivation |
| A8 false: broker unreachable across jails | Messaging works only unjailed | Start the broker outside the jail from the pi wrapper |
| Pin churn — 27 versions in 5 months | Stale pin, or a breaking bump | `nix run .#update` already bumps every pin (§7); the broker protocol version is asserted in CI |
| `pi-mesh-extension` turns out to be the real winner | Wasted integration | The `messaging` option's `package` is overridable; the socket-broker shape is common to both |
| Upstream folds messaging into pi itself | Extension becomes redundant | Delete one pin; the `messaging` option keeps its shape |
