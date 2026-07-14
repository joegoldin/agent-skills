# Using garnix CI (self-hosted)

## Overview

A self-hosted fork of [garnix CI](https://garnix.io) (`garnix-io/garnix-ci`,
open-sourced 2026) runs on the **erdtree** NixOS host. It provides Nix-native
CI + hosting: on every push it evaluates a repo's flake, builds the requested
attributes in a sandbox, and uploads the results to its own S3/B2-backed binary
cache so other machines pull pre-built closures instead of rebuilding.

- **Fork:** `github.com/joegoldin/garnix-ci`, branch **`self-hosting`**. Checked
  out locally at `~/Development/garnix-ci`.
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

1. Edit in `~/Development/garnix-ci` on branch `self-hosting`.
2. **`git add` any NEW files** — a git-repo flake excludes untracked files from
   its source, so nix builds fail with `can't find source for …`. Modified
   tracked files are picked up from the working tree without staging.
3. Compile-gate (see next section).
4. Commit + push the fork; then in dotfiles bump the input and deploy:
   ```
   set -x NIX_CONFIG "access-tokens = github.com=$(gh auth token)"
   nix flake update garnix-ci     # input is github:joegoldin/garnix-ci/self-hosting
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
| Account page 500 / CI builds not persisting | Unseeded `products` table; self-host mode no-ops `addProduct` and returns a synthetic plan. |
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
- The fork: https://github.com/joegoldin/garnix-ci (branch `self-hosting`)
