# Operating and debugging

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
-- private-input cache routing (per repo)
SELECT * FROM repo_config WHERE repo_user='<owner>' AND repo_name='<repo>';
-- recorded external-fork approval requests (per fork; approved_at set = allowed)
SELECT * FROM private_input_fork_requests WHERE repo_user='<owner>' AND repo_name='<repo>';
```

## Scheduling and timeouts

- **Queue:** eval/build/upload pools schedule round-robin across repos, FIFO
  within a repo (keyed `(owner, repo)`), so one repo's big fan-out can't
  monopolize the 16 build slots. The `garnix_server_*_queue_len` gauges are the
  waiter count (0 when slots are free).
- **Pre-build nix commands are timeout-capped:** the garnix-config eval, attr
  discovery, and flake-metadata calls honor the Configure-page build/eval
  timeout (per-repo override > global default > 1 h; 0 = no limit). A wedged
  nix-daemon fails the push with a visible `NixCommandTimeout` instead of
  leaving it at "Build starting" forever.
- **Restart recovery:** on startup, first check the commit state. A fully
  evaluated commit has a complete package/action manifest, so its unfinished
  package rows resume in place: pre-checkpoint work repeats attribute evaluation
  and checkpointed work reattaches to or cache-hits Nix. A commit still marked
  `Evaluating` has only a partial manifest; its partial pending rows are
  cancelled and the whole commit setup restarts so omitted attributes are
  recreated. Explicit user cancellation marks the commit terminal and is not
  recovered. Synthetic overall rows and external action/deploy runs that cannot
  be reattached are cancelled.
- **FOD verification** prepares a baseline and then strict-rebuilds the
  original derivation unchanged through erdtree's canonical Nix daemon store.
  Preparation sees paths already hydrated on erdtree and configured
  substituters (including Attic). The daemon may dispatch a matching build to
  farum-azula, whose ordinary `buildMachines[*].maxJobs = 1` setting caps work
  on the 2-core/12-GiB box and copies the result back. Don't target farum with
  `nix --store`, rewrite a FOD builder, or treat cache presence as verification.
  Preparation, source, Nix, and builder errors all fail closed;
  builder-controlled stderr is never trusted as a fetch exemption.
- **Manual re-trigger:** `POST /api/commits/repo/<owner>/<repo>/trigger`.
  Browser requests use the JWT cookie. For an operator curl directly against
  `127.0.0.1:8321`, forged `X-Auth-Request-*` headers are accepted only with the
  proxy marker: add `-H "X-Garnix-Proxy-Auth: $(sudo cat
  /run/secrets/garnix_proxy_shared_secret)"` alongside
  `-H 'X-Auth-Request-User: …' -H 'X-Auth-Request-Groups: garnix-admins'`.
  Keep the marker on erdtree: don't send it over the network or paste its value.

## Failure signatures

| Symptom | Cause / fix |
|---|---|
| "Build failed with **no output**" | Eval/authorization failed before any build. `grep <sha>` in `journalctl -u garnixServer`. |
| `This external fork requested private flake inputs` | Expected first-block behavior. Open `/garnix-admin`, allow **that specific fork** under **External-fork private inputs** (approval is per fork, not per repo), then retry; don't approve an untrusted fork whose code you have not reviewed. |
| `some collaborators … don't have access to a required private dependency` | The private-input collaborator-parity check (runs in self-host too): a base-repo collaborator lacks access to the private input repo. Grant them access on the input repo, or set the repo-wide `skip_private_inputs_check_for_collaborators` opt-in if the parity requirement is intentionally waived. |
| `Public repository has private dependencies, which is not allowed` | Managed-mode policy, or a backend that predates automatic trusted self-host inputs. Confirm `selfHostMode` and the deployed revision. |
| `Header Authorization has newlines` on `s3-cache-upload` | Trailing `\n` in a B2 secret. Re-save via stdin. |
| Account page shows the plan wrong / usage odd | `getPlan` always returns the synthetic unlimited "Self-Hosted" plan; there is no `products` table. If code references it, the deployed backend predates the self-host-only rip-out. |
| Frontend white page / `/_next` 404 | Caddy must serve `/_next/*` from `${frontendPkg}/public`; the standalone server doesn't. |
| Deployment activation fails at `logrotate-checkconf.service` with `stat of /var/log/nginx/*.log failed: Permission denied` | The validator raced nginx's `LogsDirectory` ownership setup. Bump the repository's `garnix-ci` input: the composite guest module orders the check after nginx. For another service, create its log directory with explicit ownership and order its validator after the preparing unit. |
| A hydrated DisplayLink/`requireFile` FOD still fails its strict check | Expected fail-closed behavior: `requireFile`'s original builder prints manual-download instructions and exits unsuccessfully. The cached output satisfies preparation but does not prove builder/hash agreement. |
| A FOD fails on crates.io, a dead source URL, bootstrap seed, or Go vendor generation | This is a failure of the original derivation being checked. Repair/update the source derivation or pinned dependency; don't add a checker-side compatibility derivation. |
| Jobs interrupted by a `garnixServer` restart | Inspect `commits.status`: `evaluated` means the manifest is complete and pending package rows resume in place; `evaluating` means setup was interrupted, so partial pending rows are cancelled and the whole commit restarts. Checkpointed rows in a complete manifest reattach/cache-hit Nix; pre-checkpoint rows repeat attribute evaluation. Explicitly cancelled commits stay terminal. Synthetic overall rows and non-idempotent external action/deploy runs are marked Cancelled. A push sitting at "Build starting" without a restart points to a wedged nix command; it fails with `NixCommandTimeout` at the configured limit. |
| Every eval hangs; `nix` commands block; `grep -c -- '->' /proc/locks` > 0 on erdtree | nix-daemon deadlock. The known cause was min-free auto-GC deadlocking on `gc.lock` against a concurrent `addToStore` path lock; auto-GC is removed from erdtree's config (the `nix-store-maintenance` daily job is the only GC). If it recurs, find the fork holding the `gc.lock` flock in `/proc/locks` and kill it. |
| erdtree load/RAM climbing, dozens of qemu processes | Leaked pool guests. Pool provisioning that fails destroys the guest, not just the DB row; otherwise the refill loop boots a replacement every 15 s, a VM storm. Sweep leftovers with `pkill -f` (comm is `.qemu-system-x8`); production guests run as the `microvm` user, so leave those alone. |
| An `authentik:`-gated deploy fails activation (exit 4) **intermittently**, rolling back the whole generation | `oauth2-proxy` couldn't start. Its cookie secret must be **URL-safe unpadded base64**: oauth2-proxy decodes with Go's `base64.RawURLEncoding` and silently falls back to the literal string, so plain `base64` output is read as a 44-byte key and it exits with `cookie_secret must be 16, 24, or 32 bytes to create an AES cipher, but is 44 bytes`. ~74% of random 32-byte secrets contain a `+` or `/`, which made it look flaky rather than broken. The generator uses `tr '+/' '-_' \| tr -d '='` (→ 43 chars → 32 bytes) and rewrites an already-persisted bad secret, rather than only checking the file is non-empty. |
| A failed deploy's log shows only `Failed with result 'exit-code'` | systemd records a daemon's stdout/stderr at **info**, so a warning-and-above filter drops the actual error. The deploy log carries `systemctl status` plus each failed unit's full journal, with unit names taken from activation's own stderr unioned with `systemctl --failed`. Seeing only the bare exit-code line means the deployed backend predates that capture. |

The last two rows are the same trap: a log filter hid the cause, and the
intermittency was misread as an environmental flake (network, DNS, Authentik
being slow) rather than as a clue. An intermittent failure with a stable success
rate usually means something is randomly generated and only sometimes valid;
chase the generator, not the environment. When a deploy fails with no usable
message, fix the log capture first; guessing costs more than the capture does.

## Monitoring

The self-host **Monitoring** page (`<garnixDomain>/monitoring`, sidebar) reads
`GET /api/monitoring`:

- **Instance:** garnix's own Prometheus at
  `services.garnixServer.metricsScrapeUrl` (default `127.0.0.1:<metricsPort>/`;
  metrics serve at the root path, not `/metrics`, and scraping `/metrics` 404s).
- **Host:** node-exporter at `nodeExporterUrl` (`127.0.0.1:9100/metrics`); the
  aspect runs `services.prometheus.exporters.node` on loopback.
- **Jobs:** running/pending builds + actions/deploys, recent build durations.
- **Deployments:** live hosted servers (from `/api/hosts`).

## Backups

Restic → Backblaze B2 (S3 API), defined in the erdtree `backups.nix` aspect
(`services.restic.backups.b2`). It is the first backup infra in the repo; reuse
this shape for other hosts.

What's backed up, and what deliberately isn't:

| Data | How | In backup? |
|---|---|---|
| Postgres (`garnix` DB — builds, users, repo_config, cache index) | `services.postgresqlBackup` dumps every 6h to `/var/backup/postgresql` | ✅ (the dumps) |
| Raw build logs | `/var/lib/garnix/logs` | ✅ |
| OpenSearch indices | rebuildable from raw logs | ❌ skipped |
| Cache NARs | already durable in the B2 cache buckets | ❌ (not double-stored) |
| Secrets | agenix `.age` files live in the dotfiles-secrets git repo | ❌ (git is the backup) |

How it works:

- Repo: `s3:https://<b2-endpoint>/<backup-bucket>/erdtree`, credentials via an
  agenix env file (B2 key pair) + a separate agenix restic encryption password.
  `initialize = true`, so the repo self-creates on first run.
- Nightly at 03:30 (+15m jitter, `Persistent` so missed runs catch up).
- Retention: `--keep-daily 7 --keep-weekly 4 --keep-monthly 6`, pruned by the
  same unit.
- Weekly integrity check (Sun 05:00): a second `services.restic.backups`
  entry with `runCheck = true` and `checkOpts = ["--read-data-subset=5%"]`,
  which re-reads 5% of pack data from B2, not just metadata.

Operating it (the NixOS module generates a wrapped CLI with repo/env/password
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
