# Building repos

## `garnix.yaml` builds

Add the GitHub App to a repo, then control what's built with `garnix.yaml`:

```yaml
builds:
  include:
    - "nixosConfigurations.*"     # e.g. dotfiles builds every host closure
```

The default (no `garnix.yaml`) builds `*.x86_64-linux.*`, `defaultPackage`,
`devShell`, `homeConfigurations.*`, `darwinConfigurations.*`,
`nixosConfigurations.*`. Scope it down to avoid impure checks, or
`darwinConfigurations` when no darwin builder is registered. The `garnix.yaml`
schema is served at `/api/config-schema` (generated from the codec).

## Binary caches

Machines pull built closures from the garnix cache via the `binary-caches`
aspect (attic + garnix cache, netrc-authenticated). erdtree also substitutes
from attic while building. So a push builds once and every machine downloads
the result.

## Private flake inputs

Trusted self-host pushes, branches and same-owner forks may use readable
private `github:` inputs automatically, but only when every collaborator of the
base repo can also access the input repo. This collaborator-parity check blocks
a build with "some collaborators … don't have access to a required private
dependency" otherwise. A repo can waive it with the explicit repo-wide
`skip_private_inputs_check_for_collaborators` opt-in. Garnix sets
`private_cache = true` before upload, so the resulting closure is served only to
a cache-token user who is a GitHub collaborator on the base repo. If the GitHub
App installation cannot fetch an input, the build fails with that real fetch
error.

An external fork is blocked on its first private-input attempt; otherwise fork
code could name any private repo visible to a broadly installed GitHub App and
print its contents. The block is recorded per fork in the
`private_input_fork_requests` table, and that fork appears under
`/garnix-admin` → **External-fork private inputs**. Allow it and retry, or
revoke later. Approving one fork does not trust any other fork of the same repo
(approval sets that fork's `approved_at`, not a repo-wide flag). Repos that never
hit this restriction do not appear in the approval inbox; private-cache routing
stays enabled whether a fork request is allowed or blocked.

**Local `nix build` outside `just`:** the private inputs are `github:` refs that
need a token. `just` recipes inject `gh auth token`; a bare `nix build` does not.
Wire a durable token with an agenix PAT and a `!include` in nix.conf if you need
ad-hoc builds to fetch private inputs.

## Actions (`garnix.yaml` actions)

Actions run a nix app as a CI step. The backend `nix copy`s the closure to
`action-runner@<GARNIX_ACTION_HOST>` and SSHes in to run it. Upstream points
that at its own runner fleet, so on self-host actions stay Pending forever
unless a local runner is set up. The `garnix.actionRunner` module
(`nix/modules/action-runner.nix`, enabled in erdtree's `garnix.nix`) creates a
nix-trusted `action-runner` user and runs each action in a bubblewrap +
slirp4netns sandbox; `services.garnixServer.actionHost = "127.0.0.1"` makes the
backend target it locally. The runner authorizes the pubkey derived at boot
from `garnix_action_runner_ssh`, which must be 0400 (OpenSSH rejects a
group-readable key). If actions hang Pending, check
`systemctl status garnix-action-runner-authorized-key` and that
`ssh -i /run/secrets/garnix_action_runner_ssh action-runner@127.0.0.1 true`
works as the garnix user. A failed action's `/run/<id>` page 404s if it's for a
repo whose GitHub name no longer resolves (e.g. after a repo rename).

Runner behavior worth knowing:

- `withRepoContents: true` actions run inside the repo: the repo is rsynced to
  the runner and bind-mounted at `/tmp/base`, which is also the action's cwd.
  The rsync's ssh skips host-key verification like every other runner
  connection, which fresh runner hosts need.
- Timeouts report properly: the runner wraps every sandbox type in coreutils
  `timeout`; exit 124 maps to "The action took too long to complete and it was
  cancelled." for all sandbox types.
- The sandbox pins `LC_ALL=C.UTF-8` so action output ordering (e.g. `ls`
  collation) doesn't depend on the host locale.

### `githubToken`: ephemeral scoped GitHub token for an action

A per-action opt-in (default off) that mints a short-lived, scoped GitHub App
installation access token per run and injects it into the action as both
`GITHUB_TOKEN` (env, like GitHub Actions) and nix `access-tokens =
github.com=…` (so `nix`/flake-input fetches authenticate). Its main use on
self-host: authenticate `github:` fetches (e.g. `github:NixOS/nixpkgs`) so
fetch-heavy actions don't hit GitHub's 60-req/hr anonymous rate limit. That
limit is why the `backend_specs` action's nixpkgs fetches (FOD-real-nixpkgs, the
`Garnix.Action` suite, incremental, external-input module tests) otherwise fail.
GitHub-only (a no-op for Gitea repos, which have no App installation). The token
is ephemeral (1 h) and never logged (`ghs_` matches `obfuscateGithubToken`).

```yaml
actions:
  backend_specs:
    run: backend_specs
    githubToken: descoped          # ← what backend_specs uses
```

Modes (`Garnix.YamlConfig.GithubTokenMode`, minted in
`GithubInterface._githubInterfaceMintScopedActionToken`):
- `none` (default): no token.
- `descoped`: `permissions:{}`; authenticates public fetches (lifts the anon
  rate limit) with no repo access. Enough for public nixpkgs.
- `repo` / `repo-write`: token scoped to the current repo with
  `contents:read` / `contents:write` (like GHA's `GITHUB_TOKEN`).
- a bare list of repo names (`githubToken: [nixpkgs, my-lib]`) →
  `contents:read` on exactly those.
- an object `{ repositories: [...], permission: read|write }` for full control.

`repo-write`/`permission: write` is a real privilege surface (the action can
push to the repo); enable it only for actions you trust.

## Artifacts (`garnix.yaml` artifacts)

`artifacts:` publishes a declared package's build output as a downloadable
artifact (file browser + `all.zip` on the build page), the fork's replacement
for GitHub Actions artifacts. Declared packages are auto-included in builds:

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
  bypasses the Authentik gate for `/api/artifacts/*` (like `/api/badges/*`,
  wired in the erdtree aspect); the backend enforces auth and repo access itself.
- agent-skills' own claude-skills bundle is published this way
  (`web-skills-zips` → `claude-skills`).
- **Endpoints** (branch segments URL-encode slashes): downloads
  `GET /api/artifacts/build/<buildId>/<name>/{all.zip,manifest,files/<path>}`
  and `GET /api/artifacts/<owner>/<repo>/<branch>/<name>/latest{.zip,/manifest,/files/<path>}`;
  listings `GET /api/artifacts/{repo/<owner>/<repo>,build/<buildId>}`; admin
  `POST|DELETE /api/artifacts/build/<buildId>/lock`,
  `DELETE /api/artifacts/<artifactId>`. Retention config rides
  `/api/configure` (`artifact_*` fields; `PUT …/artifacts/default`,
  `PUT|DELETE …/artifacts/repo/<owner>/<repo>`). The `garnix.yaml` schema incl.
  `artifacts:` is served at `/api/config-schema`.
- **Web UI:** a **View Artifacts** button (left of *Trigger Builds*) opens a
  per-repo artifacts list with sizes/file-counts and one-click zip/manifest/browse
  downloads; build-list rows show an artifact icon+count per commit, and
  commit-page package/check lines get an artifact icon linking to that build's
  downloads. Backed by two commit-scoped endpoints,
  `GET /api/artifacts/repo/<owner>/<repo>/commit-counts` (per-commit publish
  counts) and `GET /api/artifacts/commit/<owner>/<repo>/<commit>`, and hidden
  when the store is unconfigured.
