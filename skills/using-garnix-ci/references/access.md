# Access control

Registration is disabled; access is gated by Authentik application
entitlements (like the Gitea setup), not raw groups:

- oauth2-proxy authenticates via Authentik OIDC and returns
  `X-Auth-Request-Groups` to Caddy. Caddy strips every client-supplied
  `X-Auth-Request-*` / `X-Garnix-Proxy-Auth` header, then injects
  `X-Garnix-Proxy-Auth` from `/run/secrets/garnix_proxy_shared_secret` only on
  the forward-authenticated backend proxy. The backend trusts auth-request
  headers only when that marker matches; loopback source alone is not trusted.
- A scope mapping turns entitlements into a synthesized `groups` claim:
  `garnixadmin → garnix-admins`, `garnixuser → garnix-users`.
- oauth2-proxy's `allowed-group` is the hard gate. Membership of the admin group
  maps to backend `subscription_type = Admin` (self-host mode), which unlocks the
  admin page and admin API.
- Authentik quirks handled in the aspect: `insecure-oidc-allow-unverified-email
  = true` and a `whitelist-domain`, because Authentik may send
  `email_verified=false`.

The security invariant: every vhost strips inbound `X-Auth-Request-*` and
`X-Garnix-Proxy-Auth`. Only the forward-authenticated app API proxy injects the
marker; public bypasses and the cache vhost do not. The cache hostname proxies
only `/api/cache`. Keep this true when adding or changing a vhost.

Paths that bypass the Authentik gate in Caddy, each because the backend or the
caller authenticates another way: the public-key endpoints (`/api/keys/*`),
status badges (`/api/badges/*`), webhooks (`/api/events/*`) and artifact
downloads (`/api/artifacts/*`). `/api/terminal` stays behind the gate (see
hosting.md).

Admin UI: `<garnixDomain>/garnix-admin` (visible only to admins). Create the
GitHub App there and review external-fork private-input requests. Ordinary repos
do not need or show a per-repo exemption form.

For a manual API call against the backend that needs forged auth headers, see
"Manual re-trigger" in operate.md.
