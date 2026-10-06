# Deploying and secrets

## Config / aspect changes (dotfiles)

```
just build-to-erdtree           # build on erdtree (default; it's beefy)
just build-to-erdtree --local   # build on this workstation, copy the closure over
```

Use `--local` when you have already built the exact garnix store paths locally
(e.g. right after gating a fork change) so erdtree doesn't recompile the Haskell
backend. The recipe injects `NIX_CONFIG="access-tokens = github.com=$(gh auth
token)"` so the private flake inputs fetch.

Deploying restarts `garnixServer`. Startup recovers every unfinished package
row: pre-checkpoint rows repeat evaluation, while checkpointed rows reattach to
or cache-hit the surviving Nix daemon. The commit then continues its idempotent
artifact/module/deploy tail. Synthetic overall rows and non-idempotent external
action/deployment processes that cannot be reattached are marked Cancelled
instead of hanging. Any cancellation (recovery, an explicit user cancel, or
cancelling a commit/build/run) is reported to the forge (GitHub check-run →
`cancelled`, Gitea commit status → error), so cancelled work does not hang
`in_progress`/pending on the forge. Avoid deploying during important actions or
deployments; ordinary package builds are restart-safe.

## Fork (backend/frontend) code changes

1. Edit in `~/Development/garnix-ci` on branch `main`.
2. `git add` any new files: a git-repo flake excludes untracked files from its
   source, so nix builds fail with `can't find source for …`. Modified tracked
   files are picked up from the working tree without staging.
3. Compile-gate (next section).
4. Commit and push the fork; then in dotfiles bump the input and deploy:
   ```
   set -x NIX_CONFIG "access-tokens = github.com=$(gh auth token)"
   nix flake update garnix-ci     # input is github:joegoldin/garnix-ci-selfhosted (main)
   just build-to-erdtree --local
   ```

## Compile gates (before deploying fork changes)

The backend uses `postgresql-typed`, whose `pgSQL` quasi-quoter connects to a
live Postgres at compile time to typecheck SQL. Bare `cabal build` therefore
fails with `Network.Socket.connect: does not exist`. Build the nix package
instead; its sandbox spins up a temporary Postgres:

```
nix build .#backend_garnixHaskellPackage --no-link --print-out-paths   # backend
nix build .#frontend_default            --no-link                       # frontend (runs next build → typechecks TS)
```

Check the exit status directly rather than piping through `tail`, which masks
nix's non-zero exit. On failure, read the real error with
`nix log /nix/store/<hash>-garnix-0.1.0.0.drv`.

For a faster inner loop (seconds, not a full nix build), point
`postgresql-typed` at an already-running dev Postgres and run
`cabal build lib:garnix` inside the dev shell. The dev-shell Postgres socket lives under
`/tmp/garnix-specs.*/pg-tmp/test` (session-random suffix; migrations must be
applied to it):

```
nix develop -c bash -c '
  export TPG_HOST=/tmp/garnix-specs.XXXX/pg-tmp/test \
         TPG_SOCK=/tmp/garnix-specs.XXXX/pg-tmp/test/.s.PGSQL.9178 \
         TPG_PORT=9178 TPG_USER=garnix TPG_PASS=garnix TPG_DB=garnix
  cd backend && cabal build lib:garnix'          # or: cabal build test:spec
```

Use this while iterating; run the authoritative `nix build` gate before deploying.

## Running the backend spec suite

`backend_specs` (the `garnix.yaml` action on the fork) runs the full backend
suite on every push, ~35–40 min end to end (≈25 min `-O0` compile, the rest
tests). It passes, so treat a red run as a real regression. The real terminal
websocket close path runs in CI. The remaining `@skip-ci` group is the live
`Integration.FlakesSpec`, which mutates known Nix store paths and uses external
GitHub/private-input fixtures; run it deliberately, not as a hermetic action
test.

To iterate on specs locally (on erdtree or any linux checkout), give each run a
hermetic throwaway DB dir. Reusing the shellHook's `<repo>/pg-tmp` across runs
leaves zombie postgreses that break the next run:

```
nix develop --command bash -c '
  set -e
  DB_DIR=$(mktemp -d /tmp/specdb.XXXXXX)
  export DB_DIR PGDATA=$DB_DIR/test PGHOST=$DB_DIR/test \
         TPG_HOST=$DB_DIR/test TPG_SOCK=$DB_DIR/test/.s.PGSQL.9178
  db new
  cd backend
  cabal run spec -- --match "<test or describe substring>" --skip @skip-ci
  db clear; rm -rf $DB_DIR'
```

Facts that bite:

- Every hspec failure prints its exact `--match` rerun line; use those to run
  only the failed tests. Multiple `--match` flags union. Order is randomized
  per run (`--seed` reprints it).
- `SpecHook` chmods `dev-action-runner-ssh-key` and `ssh-key-for-tests` to
  0600 at suite start. Git can't store file modes, so fresh checkouts are 0644
  and ssh refuses them; without the chmod every deploy spec times out.
- The deploy specs boot real qemu VMs via the provisioner mock (pool config
  `TestHelpers.ServerPool.testPoolConfig`, `[(I1x2, 2)]`; I1x2 because that's
  the default `deployment.machine` tier and `claimServerDB` matches tiers
  exactly). The Action specs boot `nixosConfigurations.action-runner2`
  (`nix/tests/action-runner-vm.nix`), a headless VM running the self-host
  runner module with the dev key authorized.
- `pgrep`/`pkill` on qemu: the wrapped binary's comm is `.qemu-system-x8`
  (leading dot, 15-char truncation), so match with `-f`, and beware `-f`
  self-matching your own compound command line.

## Secrets and agenix

Two tiers, deliberately separated:

1. **Private non-secret config** → the `dotfiles-secrets` repo as plain `.nix`
   data (`domains.nix`, `garnix.nix`, `attic.nix`): domains, issuer/client IDs,
   cache public keys, B2 region, group names. Imported by the aspects. Kept out
   of the public dotfiles repo but not encrypted.
2. **Real secrets** → agenix `.age` files, decrypted by the host key at runtime
   into `/run/agenix/…`, never in the Nix store. Managed with the
   `secret-helper` util (or `agenix -e`).

Secrets this instance needs (in `dotfiles-secrets/*.age`):

- oauth2-proxy cookie secret and OIDC client secret
- per-bucket B2 keys: `s3-cache-{public,private}-{access-key-id,secret-access-key}`
  (upstream garnix takes one credential pair for both buckets; the fork accepts
  a key per bucket, since B2 keys are all-buckets or one-bucket)
- the cache signing key
- `attic-netrc.age`: a combined netrc with a `machine` line for both the attic
  domain and the garnix cache domain (nix takes a single `netrc-file`)

Gotchas:

- Strip trailing newlines. `jq -r` and editors append `\n`; GitHub and the AWS
  Authorization header reject it (`Header Authorization has newlines`, or "Github
  didn't give us a user token"). Pipe secrets via stdin: `agenix -e x.age < file`.
- `EDITOR=cp agenix -e` under a non-TTY corrupts the file. Use stdin
  redirection or `secret-helper`.
