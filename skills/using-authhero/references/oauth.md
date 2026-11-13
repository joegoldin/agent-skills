# Applications, API resources and MCP OAuth

## Establish the consumer contract

Record the issuer, exact resource/audience, callback, client type, needed scopes,
claim types and existing native-account identifier before provisioning. Keep
browser OIDC, API access tokens and MCP client admission separate.

1. Discover `/.well-known/openid-configuration` and its advertised public JWKS.
   Register a custom API under `/api/v2/resource-servers` with the exact identifier
   the consumer validates, for example `https://service.example/mcp`. Inspect the
   deployed resource-server, client and client-grant schemas before writes.
2. For a registered interactive client, use authorization code + S256 PKCE. A
   native/public client has no client secret; register its exact loopback callback
   and port. A server-side web application has a separate HTTPS callback and
   server-side credentials. Enable refresh and request `offline_access` only when
   needed. Password and client-credentials grants are not substitutes for MFA.
3. Configure application admission, enabled connections, requested scope mappings
   and any required API/client grants separately. The admin application's Access
   wizard/editor supports custom resources and scoped CIMD; review the actual
   graph diff rather than treating a preset as authorization.
4. The API pins issuer, audience, algorithm/signing key and time/subject claims,
   then enforces required scopes/groups and exact subject-to-existing-account
   mapping. An ID token, unrelated-resource token, email match, cookie or proxy
   header is not an API access token.

An application may allow sign-in for more people than a particular API permits.
For example, only a subset may receive the API's required group claim. Compare
admission, emitted claims and the API's final account boundary separately rather
than silently narrowing or broadening the source application's policy.

## Resource-scoped CIMD

CIMD clients identify themselves by an HTTPS metadata URL. This is generic
configuration, not special handling for a vendor or for MCP. In the tenant graph:

| Field | Meaning |
|---|---|
| `cimd` present | Scoped-only admission; `[]` denies all CIMD clients |
| `client_id_patterns` | Trusted metadata URLs, not callback URLs |
| `resource` | One exact HTTPS protected-resource URL, without query or fragment |
| `application_client_id` | An existing registered application's live authorization source |
| `scopes` | Maximum requested scope set admitted by this rule |
| `enabled` | Disable a rule without removing the scoped-only boundary |

Metadata patterns allow an exact HTTPS URL or one complete path-segment wildcard,
for example `https://client.example/oauth/*/client.json`. The wildcard is not a
wildcard host, arbitrary regex or permission for nested paths. Queries, fragments
and untrusted origins must not become alternate admissions. Admission happens
before metadata fetch; fetch success alone is not trust.

The selected source application's live policies, mappings and connections govern
admitted clients. Disabling/removing a rule must deny cached/materialized clients
as well; tombstones prevent an unmanaged fallback. Scoped-only mode cannot be
removed by simply deleting the graph field. Code, refresh and session resolution
remain resource-bound: a grant for one API must not become a grant for another.

Intersect the client's advertised authentication methods with supported modern
methods (`none` for a public client or `private_key_jwt` with valid keys). Do not
fall back to tenant-wide CIMD, dynamic registration or legacy shared-secret auth
to make an unsupported client work. Check the client's current metadata and exact
callback; a vendor preset is only a starting configuration. ChatGPT admission
says nothing about Claude or any other metadata host until separately configured
and exercised.

A separately registered client's copied policy is a snapshot, not automatic
inheritance from the website application. Coordinate membership/revocation across
those clients. Live source policies affect subsequent exchanges; already-issued
access tokens and application sessions retain their own expiry/revocation limits.

## MCP consumer and project-local Pi setup

Publish protected-resource metadata naming the exact MCP resource, authorization
server, scopes and bearer-header method. Unauthenticated MCP requests return 401
with the appropriate discovery challenge. Keep the website behind its browser
proxy gate; bypass only the MCP route and necessary discovery routes, where the
application validates bearer tokens itself.

For a project-only Pi connection, use that project's `.mcp.json` with
`auth: "oauth"`, the registered public `clientId`, exact `redirectUri` and scope string.
Remove static Authorization headers. Preserve other servers, ignore/untrack the
local file if necessary without deleting it, and reload Pi/approve changed-project
trust so its cached server definition is replaced. Secure user-level OAuth
credential storage does not make a server globally registered; do not add it to
global MCP configuration or dotfiles unless the user requests that scope.

Copy authorization URLs intact. Encoded whitespace inside a callback or parameter
name requires a fresh URL, not a broader callback allowlist.

## Acceptance and diagnosis

Exercise each consumer separately:

- trusted metadata/resource/scope combinations admitted; untrusted host, wrong
  resource, excessive scope and nested wildcard paths denied before login;
- actual allowed-user login with MFA, denied-user behavior and exact callback;
- MCP initialize, tool listing and a read-only context call attributed to the
  existing native account, followed by an actual refresh check;
- invalid/old static tokens, ID/other-resource tokens and header/cookie spoofing
  rejected; ordinary website login and native accounts unchanged.

OAuth login can succeed while API token verification fails. A 503 about signing
keys is a JWKS transport/availability failure, not proof of a bad signature or
permission to skip validation. Compare discovery/JWKS status, DNS/TLS, response
shape and public key IDs from the failing runtime when diagnostics are authorized.
Cloudflare error 1010/403 can depend on the HTTP client's User-Agent: Python's
default urllib request failed in a reproduced case while an honest application
User-Agent succeeded. Identify the application (for example `my-mcp-service/1.0`),
add a regression for that request path, and keep TLS/signature checks intact;
do not impersonate a browser or change edge policy as a shortcut.

If a website fails only with stale cookies, a clean-cookie login distinguishes
that from a provider outage. Separately check every redirect hop: an initial HTTP
redirect followed by an HTTPS upgrade is still a failed strict HTTPS-origin check.
