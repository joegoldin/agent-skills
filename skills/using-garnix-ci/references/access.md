# Access control and AuthHero OIDC cutover

## Current deployment and proxy trust

Garnix is still on Authentik pending migration. Registration is disabled; its
current access gate uses application entitlements, not raw groups. The target
provider is AuthHero, but changing these instructions does not switch the service.

- oauth2-proxy authenticates via OIDC and returns `X-Auth-Request-Groups` to
  Caddy. Caddy strips every client-supplied `X-Auth-Request-*` /
  `X-Garnix-Proxy-Auth` header, then injects `X-Garnix-Proxy-Auth` from
  `/run/secrets/garnix_proxy_shared_secret` only on the forward-authenticated
  backend proxy. The backend trusts auth-request headers only when that marker
  matches; loopback source alone is not trusted.
- The current scope mapping synthesizes `groups` from application entitlements:
  `garnixadmin → garnix-admins`, `garnixuser → garnix-users`. Preserve this
  contract in AuthHero rather than forwarding unrelated identity groups.
- oauth2-proxy's `allowed-group` is the hard gate. Membership of the admin group
  maps to backend `subscription_type = Admin` (self-host mode), which unlocks
  the admin page and admin API. This is a garnix role, not AuthHero administration.
- The current Authentik aspect uses `insecure-oidc-allow-unverified-email = true`
  and a `whitelist-domain` because Authentik may send `email_verified=false`.
  Do not assume these provider-specific exceptions are needed by AuthHero or
  synthesize a verified email claim to avoid testing them.

Every vhost strips inbound `X-Auth-Request-*` and `X-Garnix-Proxy-Auth`. Only the
forward-authenticated app API proxy injects the marker; public bypasses and the
cache vhost do not. The cache hostname proxies only `/api/cache`. Preserve this
trust boundary when changing the provider or adding a vhost.

Paths bypassing the OIDC gate in Caddy authenticate another way: public-key
endpoints (`/api/keys/*`), status badges (`/api/badges/*`), webhooks
(`/api/events/*`) and artifact downloads (`/api/artifacts/*`). `/api/terminal`
stays behind the gate (see hosting.md).

Admin UI: `<garnixDomain>/garnix-admin` (visible only to garnix admins). Create
the GitHub App there and review external-fork private-input requests. Ordinary
repos do not need or show a per-repo exemption form. For a manual backend call
that needs forged auth headers, see "Manual re-trigger" in operate.md.

## Provision the target AuthHero integration

1. Identify the tenant, existing client IDs and both consumers: the main garnix
   oauth2-proxy and `services.garnixServer.defaultAuthentik` for hosted guests.
   Inspect `modules/hosts/erdtree/garnix.nix` in the operator's dotfiles and
   `provisioner/authentik-guard.nix` in the fork. Do not read private migration
   snapshots or print credentials. Use the approved secret store/tooling.
2. Discover endpoints at the AuthHero issuer's `/.well-known/openid-configuration`.
   The production issuer is `https://auth.turnin.quest/`, not Authentik's
   per-application `/application/o/<app>/` path. Validate issuer, audience and
   TLS. Read deployed schemas before management writes; Auth0 compatibility
   does not imply every upstream operation is supported.
3. Use `domain-appname` for application names (for example `turnin-garnix`),
   preserving existing client/application IDs. Inspect `/api/v2/clients` and
   `/api/v2/connections` to configure the application type, server-side client
   authentication, enabled connection and required `grant_types`. Use code
   flow and PKCE where supported. Enable refresh only if required; do not add
   password or client-credentials grants as a workaround for interactive MFA.
4. Register the main proxy's exact HTTPS callback (normally
   `https://<garnixDomain>/oauth2/callback`; confirm its actual redirect setting).
   Separately register each default guest's public URL + `/oauth2/callback`,
   including supported custom domains. An Authentik regex redirect allowance
   is not a portable AuthHero callback configuration. Do not copy regexes or
   broaden to wildcard callbacks: if dynamically generated hosts cannot be
   registered safely, keep default guests on Authentik pending a supported
   registration workflow. Record application launch URLs separately.
5. Enable the intended provisioned-user connection for the client without
   removing other enabled clients. Normal accounts are administrator-provisioned;
   Google signup remains disabled, identities link explicitly, email autolinking
   is off, and MFA is required for ordinary users too. Only `joe@joegold.in` is
   currently an AuthHero administrator; source admin membership must not promote
   anyone. Connection enablement alone is not an application access grant.
6. Request `openid profile email` plus the actual scope that emits garnix's
   `groups` claim. Inspect the proxy/guest scope settings rather than inventing
   a scope name. Configure ordered mappings and policy bindings below. If an
   API audience/client grant is needed, inspect `/api/v2/resource-servers` and
   `/api/v2/client-grants`, granting only required audience scopes. Management
   grants, application access bindings and mapped claims are separate controls.
7. Update both consumer configurations deliberately, including the runtime
   `defaultAuthentik` issuer/client/secret delivery for guests. Do not rename
   legacy `authentik` Nix/YAML keys or run the Authentik-specific provisioner
   against AuthHero. Preserve age-encrypted guest secret delivery; never put
   plaintext secrets in Nix expressions or the world-readable store.

## Manage AuthHero access

Live console navigation: **Identity → Users / Groups / Roles / Organizations**;
**Access → Policies / Claim mappings**; **Applications → Access** for bindings,
entitlements and ordered mappings. **Users → Application identity** is for
exceptional migrated identity overrides, not routine access grants. Overrides
apply across applications using identity mappings and do not change credentials.

The typed tenant-scoped graph is `GET /api/v2/authorization` (`read:tenants`)
and `PUT /api/v2/authorization` (`update:tenants`). Read the latest graph, preserve
unrelated entries and submit its revision. HTTP 409 means reload and reconcile,
not blindly retry over another administrator's changes. Embedded graph editors
save separately from their surrounding client/user form.

Set and retain `client_metadata.authorization_model = "managed"`. New managed
applications start denied; configure explicit bindings. Disable an application
rather than remove its config or marker, so it cannot revert to unmanaged login.
Child-group membership implies parent membership; entitlements are application-
local and require explicit assignment. Test inherited access as well as direct
assignments. Policies support `any`/`all`, ordered bindings and negation; missing
policies must not become grants through negation.

Translate source expressions declaratively, not as arbitrary Python. Unsupported
expressions block activation. Preserve `garnix-admins` / `garnix-users` claim
values and array types from explicit application entitlements. Only requested
scopes emit claims, and application mapping IDs determine evaluation order.
Within a mapping assignments replace unless append is selected; arrays from
separate mappings append. Protected identity/verification claims cannot be
mapped over. Compare allow/deny decisions and ordered token/userinfo results.

Reference: `packages/authhero/docs/managed-authorization.md` and management route
schemas under `packages/authhero/src/routes/management-api/` in the AuthHero repo.
Live graph changes affect the next token exchange/userinfo request; existing
bearer tokens and garnix/guest sessions are not retroactively rewritten or
revoked. Test application-local sessions separately.

## Cutover acceptance and rollback

Before switching, record redacted old/new client settings, callbacks and scope
contracts, and have the operator prepare a backup and restoration path. Confirm
how garnix matches a user (subject, email, username or external ID). Preserve the
same local account, repository ownership, roles and grants; do not accept a new
account with a matching email as continuity. For hosted applications also check
application-local ownership and library/folder grants where applicable.

Accept each consumer only after fresh-browser checks of:

- ordinary provisioned non-admin login with required MFA; unprovisioned Google
  signup denied and no implicit email linking;
- allowed user, denied user, garnix admin and non-admin UI/API behavior;
- expected scoped claims and grant revocation on next exchange/userinfo;
- invalid callback rejection, logout/re-login/refresh and existing-session limits;
- spoofed auth headers rejected without the proxy marker; bypasses/cache unchanged;
- main garnix login and a default guest callback/login, plus dedicated/shared
  guest gates where used (see hosting.md).

If a snapshot hook exists, coordinate disabling it only for the managed clients
being activated; retain the bridge for uncut applications. A captured policy
comparison is not production UI acceptance. On failure, restore the affected
consumer's old issuer/client settings and approved previous hook/Worker path;
account/ownership damage may require application backup recovery, not just an
issuer reversal. Keep Authentik running until individual acceptance passes.
Report which consumers passed, which remain pending, and rollback readiness.

Treat **My apps** as a separate deployment and acceptance check, not evidence
that a garnix cutover has passed. Verify ordinary non-admin MFA login, live
per-user policy filtering and explicit launch URLs, not callbacks. Do not use
the management console as a substitute or infer availability from source code.
