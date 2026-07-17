# Using garnix CI (self-hosted)

## Overview

A self-hosted fork of [garnix CI](https://garnix.io) (`garnix-io/garnix-ci`,
open-sourced 2026) runs on the **erdtree** NixOS host. It provides Nix-native
CI + hosting: on every push it evaluates a repo's flake, builds the requested
attributes in a sandbox, and uploads the results to its own S3/B2-backed binary
cache so other machines pull pre-built closures instead of rebuilding.

- **Fork:** `github.com/joegoldin/garnix-ci-selfhosted` (GitHub repo renamed from
  `garnix-ci`). Development happens directly on **`main`** (the old
  `self-hosting` dev branch was merged in and deleted); the deployed flake input
  tracks `main`. Checked out locally at `~/Development/garnix-ci`.
- **Self-hosting-only.** Stripe/billing, product-plan limits/entitlements, and
  Hetzner Cloud are *removed* (not merely bypassed): the sole provisioner is the
  local microVM daemon, `getPlan` always returns one synthetic unlimited
  "Self-Hosted" plan, and the `products` / `repo_owner_has_product` /
  `repo_owner_usage_limits` tables plus all stripe columns were dropped. Usage
  tracking (CI minutes / deploy time / hosts) is kept, just uncapped.
- **Deployment:** a set of `den` aspects in the dotfiles repo (see below), built
  and pushed to erdtree with `just build-to-erdtree`.
- **Real domains, issuer URLs, keys, and B2 regions live in the private
  `dotfiles-secrets` repo** (`domains.nix`, `garnix.nix`, `attic.nix`) — never
  hardcode them in public repos (this skill, the fork frontend, the public
  dotfiles repo). Refer to them by their attr names.

This skill is a reference for operating the instance, not a tutorial for garnix
itself — for that, read the re-hosted docs at `<garnixDomain>/docs` (mirror of
`garnix.io/docs`).

## Architecture (on erdtree)

| Service | systemd unit | Port | Notes |
|---|---|---|---|
| Backend (Haskell/Servant) | `garnixServer.service` | 8321 | `GARNIX_SELF_HOST_MODE=1`; listens on 127.0.0.1 behind the gateway |
| Frontend (Next.js standalone) | `frontend.service` | 3000 | Serves the SPA; **does not** serve `/_next/static` — Caddy does, from `${frontendPkg}/public` |
| PostgreSQL 18 | `postgresql.service` | 9178 | db `garnix`, user `garnix`, TLS `verify-full` |
| OpenSearch | (opensearch) | 9200 | build-log storage; fluent-bit ships logs into it |
| Caddy | reverse proxy | 443 | vhosts for the web UI, the cache, and `/docs` |
| oauth2-proxy | (oauth2-proxy) | — | Authentik OIDC; injects `X-Auth-Request-*` headers |

The dotfiles aspects that define all of this:

- `modules/hosts/erdtree/garnix.nix` — the main aspect: backend, frontend,
  postgres, opensearch, Caddy vhosts, oauth2-proxy, the cache vhost. Sets
  `modulesOrg`, the cache domain, self-host env, per-bucket B2 secrets.
- `modules/hosts/erdtree/attic-cache.nix` — makes erdtree itself substitute from
  attic so garnix builds skip already-cached derivations.
- `modules/services/binary-caches.nix` — the fleet-wide client aspect: every
  machine substitutes from **both** attic and the garnix cache (combined
  `attic-netrc`), and workstations carry the attic-client HM config.

## Deploying changes

### Config / aspect changes (dotfiles)

```
just build-to-erdtree           # build on erdtree (default; it's beefy)
just build-to-erdtree --local   # build on this workstation, copy the closure over
```

Use `--local` when you have already built the exact garnix store paths locally
(e.g. right after gating a fork change) so erdtree doesn't recompile the Haskell
backend. The recipe injects `NIX_CONFIG="access-tokens = github.com=$(gh auth
token)"` so the private flake inputs fetch.

> **Deploying restarts `garnixServer`, which kills any in-flight builds.** They
> are left orphaned (status NULL, no end_time) and show "Pending" forever in the
> UI. Cancel them from the build page ("Cancel build") or in the DB. Avoid
> deploying while a long build (the fork's own `backend_garnix*`) is running.

### Fork (backend/frontend) code changes

1. Edit in `~/Development/garnix-ci` on branch `main`.
2. **`git add` any NEW files** — a git-repo flake excludes untracked files from
   its source, so nix builds fail with `can't find source for …`. Modified
   tracked files are picked up from the working tree without staging.
3. Compile-gate (see next section).
4. Commit + push the fork; then in dotfiles bump the input and deploy:
   ```
   set -x NIX_CONFIG "access-tokens = github.com=$(gh auth token)"
   nix flake update garnix-ci     # input is github:joegoldin/garnix-ci-selfhosted (main)
   just build-to-erdtree --local
   ```

### Compile gates (do this before deploying fork changes)

The backend uses `postgresql-typed`, whose `pgSQL` quasi-quoter **connects to a
live Postgres at compile time** to typecheck SQL. Bare `cabal build` therefore
fails with `Network.Socket.connect: does not exist`. Build the nix package
instead — its sandbox spins up a temporary Postgres:

```
nix build .#backend_garnixHaskellPackage --no-link --print-out-paths   # backend
nix build .#frontend_default            --no-link                       # frontend (runs next build → typechecks TS)
```

Check the exit status directly — do **not** pipe through `tail`, which masks
nix's non-zero exit. On failure, read the real error with
`nix log /nix/store/<hash>-garnix-0.1.0.0.drv`.

**Faster inner loop** (seconds, not a full nix build): point `postgresql-typed`
at an already-running dev Postgres and `cabal build lib:garnix` inside the dev
shell. The dev-shell Postgres socket lives under `/tmp/garnix-specs.*/pg-tmp/test`
(session-random suffix; migrations must be applied to it):

```
nix develop -c bash -c '
  export TPG_HOST=/tmp/garnix-specs.XXXX/pg-tmp/test \
         TPG_SOCK=/tmp/garnix-specs.XXXX/pg-tmp/test/.s.PGSQL.9178 \
         TPG_PORT=9178 TPG_USER=garnix TPG_PASS=garnix TPG_DB=garnix
  cd backend && cabal build lib:garnix'          # or: cabal build test:spec
```

Use this while iterating; run the authoritative `nix build` gate before deploying.

## Secrets & agenix

Two tiers, deliberately separated:

1. **Private non-secret config** → the `dotfiles-secrets` repo as plain `.nix`
   data (`domains.nix`, `garnix.nix`, `attic.nix`): domains, issuer/client IDs,
   cache public keys, B2 region, group names. Imported by the aspects. Kept out
   of the *public* dotfiles repo but not encrypted.
2. **Real secrets** → agenix `.age` files, decrypted by the host key at runtime
   into `/run/agenix/…`, never in the Nix store. Managed with the
   **`secret-helper`** util (or `agenix -e`).

Secrets this instance needs (in `dotfiles-secrets/*.age`):

- oauth2-proxy cookie secret + OIDC client secret
- per-bucket B2 keys: `s3-cache-{public,private}-{access-key-id,secret-access-key}`
  (garnix upstream used one credential pair for both buckets; the fork was
  patched to accept a key per bucket, since B2 keys are all-buckets or one-bucket)
- the cache signing key
- `attic-netrc.age` — a **combined** netrc with a `machine` line for **both** the
  attic domain and the garnix cache domain (nix takes a single `netrc-file`)

Gotchas:

- **Strip trailing newlines.** `jq -r` / editors append `\n`; GitHub and the AWS
  Authorization header reject it (`Header Authorization has newlines`, or "Github
  didn't give us a user token"). Pipe secrets via stdin: `agenix -e x.age < file`.
- **Never `EDITOR=cp agenix -e`** under a non-TTY — it corrupts the file. Use
  stdin redirection or `secret-helper`.

## Access control

Registration is disabled; access is gated by **Authentik application
entitlements** (like the Gitea setup), not raw groups:

- oauth2-proxy authenticates via Authentik OIDC and injects
  `X-Auth-Request-Groups` on every browser request. Because the backend listens
  only on 127.0.0.1 behind the gateway, that header is trusted.
- A scope mapping turns entitlements into a synthesized `groups` claim:
  `garnixadmin → garnix-admins`, `garnixuser → garnix-users`.
- oauth2-proxy's `allowed-group` is the hard gate. Membership of the admin group
  maps to backend `subscription_type = Admin` (self-host mode), which unlocks the
  admin page and admin API.
- Authentik quirks handled in the aspect: `insecure-oidc-allow-unverified-email
  = true` and a `whitelist-domain`, because Authentik may send
  `email_verified=false`.

> **Security invariant:** the cache vhost must strip inbound `X-Auth-Request-*`
> headers and only proxy `/api/cache`. Never proxy the whole backend at the
> cache hostname — that would let anyone forge the group header and become admin.

Admin UI: `<garnixDomain>/garnix-admin` (visible only to admins) — create the
GitHub App, and set **per-repo config** (see below).

## Using garnix to build your repos

Add the GitHub App to a repo, then control what's built with `garnix.yaml`:

```yaml
builds:
  include:
    - "nixosConfigurations.*"     # e.g. dotfiles builds every host closure
```

The default (no `garnix.yaml`) builds `*.x86_64-linux.*`, `defaultPackage`,
`devShell`, `homeConfigurations.*`, `darwinConfigurations.*`,
`nixosConfigurations.*`. Scope it down to avoid impure checks or
`darwinConfigurations` when no darwin builder is registered.

**Binary caches:** machines pull built closures from the garnix cache via the
`binary-caches` aspect (attic + garnix cache, netrc-authenticated). erdtree also
substitutes from attic while building. So a push builds once and every machine
downloads the result.

**Private flake inputs on a public repo:** garnix normally refuses to build a
*public* repo that has *private* flake inputs (its closures would leak to the
unauthenticated public cache). In **self-host mode this is handled
automatically**: `checkAuthorization` allows it and persists `private_cache` for
that repo, so `S3Cache` routes the closures to the **authenticated** bucket. No
per-repo setup is needed on a fresh install. To override manually, use the admin
page's "Per-repo config" (`skip_private_inputs_check` + `private_cache`) or the
`repo_config` table.

**Local `nix build` outside `just`:** the private inputs are `github:` refs that
need a token. `just` recipes inject `gh auth token`; a bare `nix build` does not.
Wire a durable token with an agenix PAT + a `!include` in nix.conf if you need
ad-hoc builds to fetch private inputs.

## Operating & debugging

```
ssh erdtree
sudo journalctl -u garnixServer -f              # backend logs (build lifecycle, eval errors)
sudo -u postgres psql -p 9178 -d garnix         # the garnix DB (superuser via socket)
```

Useful DB queries:

```sql
-- recent builds + status for a repo
SELECT package, status, start_time, end_time FROM builds
WHERE repo_name = '<repo>' ORDER BY start_time DESC LIMIT 40;
-- valid statuses
SELECT unnest(enum_range(NULL::build_status));   -- success | failure | timeout | cancelled
-- cancel builds orphaned by a redeploy
UPDATE builds SET status='cancelled', end_time=now()
WHERE repo_name='<repo>' AND git_commit='<sha>' AND status IS NULL AND end_time IS NULL;
-- per-repo config (private-inputs / private-cache overrides)
SELECT * FROM repo_config WHERE repo_user='<owner>' AND repo_name='<repo>';
```

Common failure signatures:

| Symptom | Cause / fix |
|---|---|
| "Build failed with **no output**" | Eval/authorization failed before any build. `grep <sha>` in `journalctl -u garnixServer`. |
| `Public repository has private dependencies, which is not allowed` | The private-inputs guard. In self-host mode it auto-allows + routes to the private cache; if seen, the deployed backend predates that fix, or `selfHostMode` is off. |
| `Header Authorization has newlines` on `s3-cache-upload` | Trailing `\n` in a B2 secret. Re-save via stdin. |
| Account page shows the plan wrong / usage odd | `getPlan` always returns the synthetic unlimited "Self-Hosted" plan now — there is no `products` table (dropped). If code references it, the deployed backend predates the self-host-only rip-out. |
| Frontend white page / `/_next` 404 | Caddy must serve `/_next/*` from `${frontendPkg}/public`; the standalone server doesn't. |
| Jobs stuck "Pending" | Orphaned by a `garnixServer` restart (deploy) mid-build. Cancel them. |

## Multiple servers & hash subdomains (hosting)

garnix hosting gives **each version of each server its own unique URL**, derived
from the hash of its NixOS configuration (`<hash>.<hosting domain>`). Pushing a
new config spins up the new version at a *new* URL while the old one keeps
serving — zero-downtime deploys, easy rollback, and you can smoke-test the new
version before pointing anything at it.

Consequence: **never reference another garnix-hosted server by a fixed
hostname** — reference it by its hash URL. `garnix-lib` provides
`lib.getHashSubdomain` for exactly this (use the zero-deps fork
`github:joegoldin/garnix-lib`; upstream is `garnix-io/garnix-lib`):

```nix
{
  inputs.garnix-lib.url = "github:joegoldin/garnix-lib";

  outputs = { self, nixpkgs, garnix-lib, ... }: {
    nixosConfigurations.machine1 = nixpkgs.lib.nixosSystem { ... };
    nixosConfigurations.machine2 = nixpkgs.lib.nixosSystem {
      modules = [{
        # machine2 -> machine1, pinned to machine1's exact deployed version:
        myservice.otherServiceURL =
          "http://"
          + garnix-lib.lib.getHashSubdomain self.nixosConfigurations.machine1
          + "/somepath";
      }];
    };
  };
}
```

Because the URL is a function of machine1's config hash, machine2's config
changes (and redeploys) exactly when machine1's does — the reference can never
dangle. A stable "current version" entrypoint (user-facing domain) should be a
CNAME/proxy the operator points at the hash subdomain they consider live.

## Server hosting on erdtree (microVMs)

Upstream deployed servers as Hetzner Cloud VMs; this fork provisions **local
[microvm.nix](https://github.com/microvm-nix/microvm.nix) guests** on erdtree.
The `garnix.local-provisioner` aspect (`modules/hosts/erdtree/garnix.nix`) runs
`garnix-provisionerd` (a root daemon speaking newline-JSON over
`/run/garnix-provisioner/provisioner.sock`), which creates/destroys guests on
the `garnixbr0` bridge (`10.111.0.0/24`, dnsmasq DHCP, NAT out `eno1`). The
backend selects it whenever `services.garnixServer.provisionerSocket` is set;
Traefik (polling `/api/hosts/traefik`) routes app domains to guest IPs and Caddy
issues per-SNI on-demand certs gated by `/api/hosts/on-demand-check`.

- **Routing:** `<pkg>.<branch>.<repo>.<owner>.<appsDomain>` (primary deploys also
  at `<repo>.<owner>.<appsDomain>`). A wildcard `*.<appsDomain>` DNS record
  (DNS-only) points at erdtree.
- **Configurable size:** each `garnix.yaml` `servers[].deployment.machine` picks a
  tier, `i1x1` (default, 1 vCPU / 1 GiB) … `i16x32` — the name encodes
  `<vCPU>x<GiB>` (`i1x1 i1x2 i2x2 i2x3 i2x4 i4x2 i4x4 i4x8 i8x8 i8x16 i16x16
  i16x32`); 20 GiB root + 20 GiB writable-store overlay for every tier.
  `provisionServerPool = true` pre-warms the pool (default one `i1x1`); override
  the pooled set with `GARNIX_SERVER_POOL` (`i1x1:1,i4x4:0`).
- **Guest contract:** every deployed `nixosConfiguration` MUST import
  `microvm.nixosModules.microvm` and `garnix-ci.nixosModules.garnix-guest`, and
  set `garnix.guest.sshPublicKey` to erdtree's hosting pubkey
  (`/var/lib/garnix-provisioner/hosting.pub`) — otherwise a redeploy locks the
  backend out of the guest. See `examples/hello-server/flake.nix` in the fork.

### SSH into deployed guests

`garnix.yaml` `servers[]` networking fields (all optional). Reachability and
login are independent:

```yaml
servers:
  - configuration: myServer
    deployment: { branch: main, machine: i2x2 }
    exposeSSH: true                    # open a public DNAT port -> guest :22
    authorizeDeployerGithubKeys: true  # authorize your github.com/<user>.keys
    authorizedSSHKeys: [ "ssh-ed25519 AAAA... me@laptop" ]
    ports:
      - { name: api, port: 8080, type: http }   # -> <name>.<server-domain>
      - { name: db,  port: 5432, type: tcp }     # -> host:port via DNAT
```

The guest's `garnix` user is **login-closed and password-auth-off by default**
(it's the deploy identity, not a login account); it only becomes loginable when
you set `authorizeDeployerGithubKeys` and/or `authorizedSSHKeys`. `exposeSSH`
only opens network reachability — it grants no login by itself. Or bring your
own login user in the guest config (declare `users.users.<name>` with
`openssh.authorizedKeys.keys`, the [user-module](https://github.com/garnix-io/user-module)
pattern) and use `exposeSSH`/tailscale purely for reach. The **Servers** page
shows copyable `ssh` commands per method (Tailscale / ProxyJump / DNAT);
`services.garnixServer.sshHost` supplies the host for ProxyJump + DNAT.

## Gating a deployed server behind Authentik (guest auth boilerplate)

`garnix-ci.nixosModules.garnix-authentik` locks a deployed server behind an OIDC
login with one import: it runs `oauth2-proxy` + an nginx forward-auth gate on
`:80` (the port Traefik hits), so every request needs a valid session before it
reaches your service on `garnix.authentik.upstream`. Three modes:

- **`mode = "default"` (fastest, dev):** put `authentik: default` on the server's
  `garnix.yaml` entry — garnix drops its **own** OIDC client creds + this
  deploy's redirect URL onto the guest at deploy time
  (`/var/garnix/keys/default-authentik.env`). No provider setup, no secret in the
  repo; whoever can log into garnix can reach the app. Requires
  `services.garnixServer.defaultAuthentik = { issuerUrl, clientId,
  clientSecretFile }` on erdtree (already set in the aspect) and the deploy
  callback URLs allowed on that Authentik provider (use a regex redirect URI).

  ```yaml
  servers:
    - configuration: hello
      deployment: { type: on-branch, branch: main }
      authentik: default
  ```
  ```nix
  garnix.authentik = { enable = true; mode = "default"; upstream = "127.0.0.1:8080"; };
  ```

- **`mode = "dedicated"` (default) / `"shared"`:** the app gets its own Authentik
  provider (or shares one gated by group claims). Deliver the OIDC client secret
  the garnix-native way — encrypt it to the **repo key**
  (`GET /api/keys/<owner>/<repo>/repo-key.public`, or the `authentik-provision`
  helper) and reference the `.age` ciphertext by path (`clientSecretFile`) or
  inline (`clientSecretAge`); the guest decrypts at runtime with the repo private
  key garnix drops at `/var/garnix/keys/repo-key`. No plaintext secret ever
  reaches the world-readable nix store. Full worked recipes (dedicated vs shared,
  the provision helper, regex redirect URIs) are in
  `docs/authentik-cookbook.md` in the fork.

  ```nix
  modules = [
    microvm.nixosModules.microvm
    garnix-ci.nixosModules.garnix-guest
    garnix-ci.nixosModules.garnix-authentik
    {
      garnix.guest.sshPublicKey = "<hosting pubkey>";
      garnix.authentik = {
        enable = true;
        publicUrl = "https://hello.main.<repo>.<owner>.<appsDomain>";
        issuerUrl = "https://<authentik>/application/o/<app>/";
        clientId = "<oidc client id>";
        clientSecretFile = ./client-secret.age;   # committed, repo-key-encrypted
        allowedGroups = [ "app-users" ];           # omit to gate on entitlements
        upstream = "127.0.0.1:8080";               # your service (NOT on :80)
      };
      services.myApp.port = 8080;
    }
  ];
  ```

The public-key endpoints (`/api/keys/*`), status badges (`/api/badges/*`), and
webhooks (`/api/events/*`) bypass the Authentik gate in Caddy — the provision
helper and guests fetch repo public keys unauthenticated (they can encrypt, not
decrypt).

## Monitoring

The self-host **Monitoring** page (`<garnixDomain>/monitoring`, sidebar) reads
`GET /api/monitoring`:

- **Instance** — garnix's own Prometheus at
  `services.garnixServer.metricsScrapeUrl` (default `127.0.0.1:<metricsPort>/` —
  metrics serve at the **root** path, not `/metrics`; scraping `/metrics` 404s).
- **Host** — node-exporter at `nodeExporterUrl` (`127.0.0.1:9100/metrics`); the
  aspect runs `services.prometheus.exporters.node` on loopback.
- **Jobs** — running/pending builds + actions/deploys, recent build durations.
- **Deployments** — live hosted servers (from `/api/hosts`).

## Actions (`garnix.yaml` actions)

Actions run a nix app as a CI step. The backend `nix copy`s the closure to
`action-runner@<GARNIX_ACTION_HOST>` and SSHes in to run it — upstream points
that at its own runner fleet, so **on self-host actions stay Pending forever
unless a local runner is set up**. The `garnix.actionRunner` module
(`nix/modules/action-runner.nix`, enabled in erdtree's `garnix.nix`) creates a
nix-trusted `action-runner` user and runs each action in a bubblewrap +
slirp4netns sandbox; `services.garnixServer.actionHost = "127.0.0.1"` makes the
backend target it locally. The runner authorizes the pubkey derived at boot
from `garnix_action_runner_ssh` (which must be **0400** — OpenSSH rejects a
group-readable key). If actions hang Pending, check
`systemctl status garnix-action-runner-authorized-key` and that
`ssh -i /run/secrets/garnix_action_runner_ssh action-runner@127.0.0.1 true`
works as the garnix user. (A failed action's `/run/<id>` page 404s if it's for
a repo whose GitHub name no longer resolves — e.g. after a repo rename.)

## Artifacts (`garnix.yaml` artifacts)

`artifacts:` publishes a declared package's build output as a downloadable
artifact (file browser + `all.zip` on the build page) — the fork's GitHub
Actions artifacts replacement. Declared packages are auto-included in builds:

```yaml
artifacts:
  - package: web-skills-zips   # packages.<arch>.web-skills-zips
    name: claude-skills        # optional; defaults to the package name
```

- **Stable latest URL** (newest published artifact per repo/branch/name):
  `https://<garnixDomain>/api/artifacts/<owner>/<repo>/<branch>/<name>/latest.zip`
  (also `.../latest/manifest`, `.../latest/files/<path>`; per-build URLs under
  `/api/artifacts/build/<buildId>/...`). Storage is content-addressed in two
  dedicated B2 buckets, routed public/private by the same rules as the cache.
- **Retention/locking** on the Configure page: global default 30 days +
  per-repo overrides; optional keep-latest exemption (default off, global +
  per-repo); per-build locks (never reaped). Unreferenced objects are GC'd.
- **SSO bypass:** downloads authenticate with garnix access tokens (`api`
  scope; `curl -L -u user:<token>`) or anonymously for public repos, so Caddy
  must bypass the Authentik gate for `/api/artifacts/*` (like `/api/badges/*`,
  wired in the erdtree aspect); the backend enforces auth + repo access itself.
- agent-skills' own claude-skills bundle is published this way
  (`web-skills-zips` → `claude-skills`), replacing the old
  `build-web-skills.yml` GitHub workflow.
- **Endpoints** (branch segments URL-encode slashes): downloads
  `GET /api/artifacts/build/<buildId>/<name>/{all.zip,manifest,files/<path>}`
  and `GET /api/artifacts/<owner>/<repo>/<branch>/<name>/latest{.zip,/manifest,/files/<path>}`;
  listings `GET /api/artifacts/{repo/<owner>/<repo>,build/<buildId>}`; admin
  `POST|DELETE /api/artifacts/build/<buildId>/lock`,
  `DELETE /api/artifacts/<artifactId>`. Retention config rides
  `/api/configure` (`artifact_*` fields; `PUT …/artifacts/default`,
  `PUT|DELETE …/artifacts/repo/<owner>/<repo>`). The `garnix.yaml` schema incl.
  `artifacts:` is served at `/api/config-schema` (generated from the codec).

## Backups

Restic → Backblaze B2 (S3 API), defined in the erdtree `backups.nix` aspect
(`services.restic.backups.b2`). First backup infra in the repo — reuse this
shape for other hosts.

**What's backed up** (and what deliberately isn't):

| Data | How | In backup? |
|---|---|---|
| Postgres (`garnix` DB — builds, users, repo_config, cache index) | `services.postgresqlBackup` dumps every 6h to `/var/backup/postgresql` | ✅ (the dumps) |
| Raw build logs | `/var/lib/garnix/logs` | ✅ |
| OpenSearch indices | rebuildable from raw logs | ❌ skipped |
| Cache NARs | already durable in the B2 cache buckets | ❌ (not double-stored) |
| Secrets | agenix `.age` files live in the dotfiles-secrets git repo | ❌ (git is the backup) |

**How it works:**

- Repo: `s3:https://<b2-endpoint>/<backup-bucket>/erdtree`, credentials via an
  agenix env file (B2 key pair) + a separate agenix restic encryption password.
  `initialize = true` — the repo self-creates on first run.
- Nightly at **03:30** (+15m jitter, `Persistent` so missed runs catch up).
- Retention: `--keep-daily 7 --keep-weekly 4 --keep-monthly 6`, pruned by the
  same unit.
- **Weekly integrity check** (Sun 05:00): a second `services.restic.backups`
  entry with `runCheck = true` and `checkOpts = ["--read-data-subset=5%"]` —
  actually re-reads 5% of pack data from B2, not just metadata.

**Operating it** (the NixOS module generates a wrapped CLI with repo/env/password
preloaded):

```bash
ssh erdtree
sudo systemctl start restic-backups-b2.service   # manual backup now
sudo restic-b2 snapshots                          # list snapshots
sudo restic-b2 check                              # integrity check now
# Restore drill (do this periodically — a backup you haven't restored is a hope):
sudo restic-b2 restore latest --target /tmp/restic-drill
sudo zstd -t /tmp/restic-drill/var/backup/postgresql/garnix.sql.zstd  # dumps are zstd
sudo sh -c 'zstdcat /tmp/restic-drill/var/backup/postgresql/garnix.sql.zstd | head'
# Full DB restore path: stop garnixServer, then
#   zstdcat garnix.sql.zstd | sudo -u postgres psql -p 9178 -d garnix
sudo rm -rf /tmp/restic-drill
```

## Reference links

- Re-hosted docs: `<garnixDomain>/docs` (mirror of `garnix.io/docs`)
- Upstream docs: https://garnix.io/docs — CI, caching, hosting, modules, private inputs
- Upstream source: https://github.com/garnix-io/garnix-ci
- The fork: https://github.com/joegoldin/garnix-ci-selfhosted (default branch `main`)
