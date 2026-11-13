---
name: using-authhero
description: Operate the AuthHero fork and its OAuth integrations. Use when configuring AuthHero applications, API resources, scoped CIMD or MCP client admission, or deploying its Cloudflare Worker.
---

# Using AuthHero

The fork lives at `~/Development/authhero`. Read its `CLAUDE.md` and, for admin
UI changes, `apps/admin/CLAUDE.md`. Inspect the deployed management schemas before
writes; Auth0-compatible routes do not imply every upstream operation is supported.

| Task | Read |
|---|---|
| Register an application or API, configure scopes/claims, admit MCP clients through scoped CIMD, diagnose OAuth versus MCP failures | [references/oauth.md](references/oauth.md) |
| Build/release the fork, migrate D1, back up production, verify or roll back a Worker deployment | [references/deploy.md](references/deploy.md) |

For Garnix browser gates, guest routing, encrypted guest secrets and in-place
hosting, use `using-garnix-ci`. A Cloudflare AuthHero deployment does not deploy
its consumers or switch their identity providers.

## Access model

Keep these controls distinct:

- **Application admission:** managed policies and bindings decide who can sign in.
- **Token contract:** requested scopes and ordered mappings decide which claims
  are emitted for the selected resource.
- **Consumer authorization:** the API validates the access token and enforces its
  own group/permission and existing-account boundary.

Connection enablement is not an access grant. Preserve provisioned accounts,
explicit identity links, credentials and required MFA; matching email addresses
are not evidence of account continuity.

The tenant authorization graph uses revision-based writes. Read the current
`GET /api/v2/authorization`, preserve unrelated entries and submit that revision
with `PUT`. A conflict requires reconciliation. Keep managed application markers
and disable entries rather than deleting them into an unmanaged fallback.

Finish with separate evidence for saved configuration, deployed code, real
login/MFA, token use at the consumer, native-account attribution and refresh.
Mark deferred consumers and unperformed checks explicitly; a successful policy
simulation or redirect to login proves neither authenticated API access nor
interoperability with a particular MCP client.
