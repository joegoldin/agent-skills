# Build, deploy and recover AuthHero

## Release inputs and gates

Read the fork's project instructions and package scripts. The root `pnpm test`
has been a no-op; run the affected package suites and the release's required
cumulative gates. Use the lockfile/CI Node and Playwright browser versions rather
than an unrelated host runtime. Build the admin/widget assets, typecheck/lint the
relevant packages and dry-run Wrangler against the same tracked inputs that will
ship. Avoid edits to vendored UI components.

For a native feature stack, preserve review boundaries, PR identities and
historical release heads. Use the repository's configured stack publisher
(`stakk` for the existing AuthHero stack), not a different stack tool. Keep release
artifacts in their owning release change rather than mixing them into features.
Use jj for writes in jj workspaces; inspect and preserve unrelated changes.

A release record should name the exact source commit, runtime/package versions,
asset/input reconciliation, test results and hosted checks. Distinguish baseline
warnings/skips from new regressions. For browser transition regressions, test the
actual supported browser and reduced-motion behavior at transition creation;
catching a skipped-transition error is not evidence that participation works.

## D1 backup and migration

Before authorized production changes, verify a restorable encrypted backup and a
known rollback Worker/source. Record authenticated decryption, SQLite integrity
and foreign-key results without exposing plaintext records or keys. Record key
custody separately: a backup readable only with a key on the same host has not
proven independent recovery. Remove temporary plaintext after the verification.

Reconcile production's applied migration identities and contents with the target
release before applying only missing migrations. Local/private migration names
may overlap upstream sequence numbers; do not rename already-applied identities
or force bookkeeping flags to fit upstream. Preserve users, credentials, links,
MFA/replay counters, roles, connections, clients and the authorization graph.

TOTP replay checks must consume a step/counter atomically across adapters. A
compatibility adapter can call an available upstream atomic method, but cannot
substitute unconditional success. Adding a nullable upstream column does not
replace the private adapter's existing replay boundary.

## Cloudflare deployment and acceptance

Use the approved production tooling and secret store. Keep decrypted environment
files, tokens, subject maps and backup keys out of source, command output and
release records. Do not infer permission for a new production action merely from
filesystem access or the ability to read a credential.

After deployment, record the actual Worker version, deployment/traffic assignment
and source commit. Verify public discovery and RSA JWKS, then read back preserved
configuration/account invariants. A successful dry-run, source push or registration
read-back is not evidence that a Worker is serving the release.

Consumer acceptance is separate: prove login/MFA, required scoped claims, native
account continuity, real API/MCP access and refresh for each requested consumer.
Retain the previous Worker/source and backup for rollback; issuer reversal alone
cannot repair account or ownership damage.

AuthHero's Worker ships through Cloudflare; a Garnix-hosted consumer ships through
its own Nix/Garnix pipeline. A non-Nix repository's erroneous Garnix deployment
planner check is not the same gate as a consumer's legitimate Nix build and
redeployment. Preserve the gates or obtain the user's explicit waiver for the
named check and action; an earlier waiver is not reusable deployment authority.
