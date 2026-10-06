---
name: using-garnix-ci
description: Operate the self-hosted garnix CI on erdtree (deploys, secrets, access, caches, repo builds and failed or stuck builds). Use when working on that garnix instance or a build it runs.
---

# Using garnix CI (self-hosted)

A self-hosted fork of [garnix CI](https://garnix.io) (`garnix-io/garnix-ci`,
open-sourced 2026) runs on the **erdtree** NixOS host. It provides Nix-native
CI and hosting: on every push it evaluates a repo's flake, builds the requested
attributes in a sandbox, and uploads the results to its own S3/B2-backed binary
cache so other machines pull pre-built closures instead of rebuilding.

- **Fork:** `github.com/joegoldin/garnix-ci-selfhosted`, developed directly on
  **`main`**, which the deployed flake input tracks. Checked out locally at
  `~/Development/garnix-ci`.
- **Self-hosting only.** Stripe/billing, product-plan limits/entitlements and
  Hetzner Cloud are removed, not bypassed: the sole provisioner is the local
  microVM daemon, `getPlan` always returns one synthetic unlimited
  "Self-Hosted" plan, and the `products` / `repo_owner_has_product` /
  `repo_owner_usage_limits` tables and all stripe columns are dropped. Usage
  tracking (CI minutes / deploy time / hosts) is kept, uncapped.
- **Deployment:** a set of `den` aspects in the dotfiles repo, built and pushed
  to erdtree with `just build-to-erdtree`.
- **Private values:** real domains, issuer URLs, keys and B2 regions live in the
  private `dotfiles-secrets` repo (`domains.nix`, `garnix.nix`, `attic.nix`).
  Keep them out of public repos (this skill, the fork frontend, the public
  dotfiles repo) and refer to them by their attr names.

This is a reference for operating the instance, not a garnix tutorial; for that,
read the re-hosted docs at `<garnixDomain>/docs` (mirror of `garnix.io/docs`).

## Architecture (on erdtree)

| Service | systemd unit | Port | Notes |
|---|---|---|---|
| Backend (Haskell/Servant) | `garnixServer.service` | 8321 | `GARNIX_SELF_HOST_MODE=1`; listens on 127.0.0.1 behind the gateway |
| Frontend (Next.js standalone) | `frontend.service` | 3000 | Serves the SPA; does not serve `/_next/static`, which Caddy serves from `${frontendPkg}/public` |
| PostgreSQL 18 | `postgresql.service` | 9178 | db `garnix`, user `garnix`, TLS `verify-full` |
| OpenSearch | (opensearch) | 9200 | build-log storage; fluent-bit ships logs into it |
| Caddy | reverse proxy | 443 | vhosts for the web UI, the cache, and `/docs` |
| oauth2-proxy | (oauth2-proxy) | — | Authentik OIDC; Caddy forwards its `X-Auth-Request-*` headers with a private proxy marker |

The dotfiles aspects that define it:

- `modules/hosts/erdtree/garnix.nix`: the main aspect (backend, frontend,
  postgres, opensearch, Caddy vhosts, oauth2-proxy, the cache vhost). Sets
  `modulesOrg`, the cache domain, self-host env, per-bucket B2 secrets.
- `modules/hosts/erdtree/attic-cache.nix`: makes erdtree itself substitute from
  attic so garnix builds skip already-cached derivations.
- `modules/services/binary-caches.nix`: the fleet-wide client aspect. Every
  machine substitutes from both attic and the garnix cache (combined
  `attic-netrc`), and workstations carry the attic-client HM config.

## Where to look

| Task | Read |
|---|---|
| Deploy a dotfiles or fork change, compile-gate the fork, run the backend specs, manage agenix secrets | [references/deploy.md](references/deploy.md) |
| Authentik entitlements, the proxy-auth marker, the admin UI | [references/access.md](references/access.md) |
| Build a repo with `garnix.yaml`, binary caches, private flake inputs, actions, `githubToken`, artifacts | [references/repos.md](references/repos.md) |
| Hosted servers: hash subdomains, microVM guests, SSH and the web terminal, application logs, custom domains, Authentik-gated guests | [references/hosting.md](references/hosting.md) |
| Logs, DB queries, scheduling and timeouts, failure signatures, monitoring, backups | [references/operate.md](references/operate.md) |

## Reference links

- Re-hosted docs: `<garnixDomain>/docs` (mirror of `garnix.io/docs`)
- Upstream docs: https://garnix.io/docs (CI, caching, hosting, modules, private inputs)
- Upstream source: https://github.com/garnix-io/garnix-ci
- The fork: https://github.com/joegoldin/garnix-ci-selfhosted (default branch `main`)
