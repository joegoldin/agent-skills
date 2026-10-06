# Hosting servers

## Hash subdomains and multiple servers

garnix hosting gives each version of each server its own unique URL, derived
from the hash of its NixOS configuration (`<hash>.<hosting domain>`). Pushing a
new config spins up the new version at a new URL while the old one keeps
serving: zero-downtime deploys, easy rollback, and you can smoke-test the new
version before pointing anything at it.

So reference another garnix-hosted server by its hash URL, not a fixed
hostname. `garnix-lib` provides `lib.getHashSubdomain` for exactly this (use the
zero-deps fork `github:joegoldin/garnix-lib`; upstream is
`garnix-io/garnix-lib`):

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
changes (and redeploys) exactly when machine1's does, so the reference can never
dangle. A stable "current version" entrypoint (user-facing domain) should be a
CNAME/proxy the operator points at the hash subdomain they consider live.

## Server hosting on erdtree (microVMs)

Upstream deploys servers as Hetzner Cloud VMs; this fork provisions local
[microvm.nix](https://github.com/microvm-nix/microvm.nix) guests on erdtree.
The `garnix.local-provisioner` aspect (`modules/hosts/erdtree/garnix.nix`) runs
`garnix-provisionerd` (a root daemon speaking newline-JSON over
`/run/garnix-provisioner/provisioner.sock`), which creates/destroys guests on
the `garnixbr0` bridge (`10.111.0.0/24`, dnsmasq DHCP, NAT out `eno1`). The
backend selects it whenever `services.garnixServer.provisionerSocket` is set;
Traefik (polling `/api/hosts/traefik`) routes app domains to guest IPs and Caddy
issues per-SNI on-demand certs gated by `/api/hosts/on-demand-check`.

- **Routing:** `<pkg>.<branch>.<repo>.<owner>.<appsDomain>` (primary deploys also
  at `<repo>.<owner>.<appsDomain>`). A wildcard `*.<appsDomain>` DNS record
  (DNS-only) points at erdtree.
- **Configurable size:** each `garnix.yaml` `servers[].deployment.machine` picks a
  tier, `i1x2` (default, 1 vCPU / 2 GiB) … `i16x32`; the name encodes
  `<vCPU>x<GiB>` (`i1x1 i1x2 i2x2 i2x3 i2x4 i4x2 i4x4 i4x8 i8x8 i8x16 i16x16
  i16x32`); 20 GiB root + 20 GiB writable-store overlay for every tier.
  `provisionServerPool = true` enables pre-warming; configure exact available
  tiers with the typed NixOS option `services.garnixServer.serverPool`, for
  example `{ i2x4 = 1; }`. A deployment can only claim a matching pooled tier.
  Erdtree intentionally keeps one `i2x4` guest warm because a repository NixOS
  activation can exhaust `i1x1` and make virtio-fs return `ENOMEM`.
- **Guest contract:** every deployed `nixosConfiguration` imports only
  `garnix-ci.nixosModules.garnix-guest`; it includes the pinned microvm.nix
  module plus Garnix's volume/share/network/deploy profile. The fork's neutral
  hosting public key is the `garnix.guest.sshPublicKey` default. Operators of a
  different instance override it with their host's
  `/var/lib/garnix-provisioner/hosting.pub`, or the wrong deploy key remains
  trusted. `garnix.guest.terminalCaPublicKey` defaults to `sshPublicKey` for
  compatibility; the local provisioner injects the dedicated terminal-CA
  public key derived from `/run/secrets/garnix_terminal_ca`.
  Existing guests must be recreated after a terminal-CA cutover or the web
  terminal will stop authenticating. See `examples/hello-server/flake.nix` in
  the fork.
- **Guest network boundary:** guest taps are L2-isolated bridge ports; guest
  firewalls permit inbound SSH but deny undeclared ports; guests are IPv4-only
  and refuse router advertisements. The host egress chain blocks other guests,
  RFC1918/LAN, link-local, CGNAT, and any operator-configured internal builder
  CIDRs. A deployed workload can reach the public internet and required gateway
  services, but not the host LAN or remote builders.

## SSH into deployed guests

`garnix.yaml` `servers[]` networking fields (all optional). Reachability and
login are independent:

```yaml
servers:
  - configuration: myServer
    deployment: { branch: main, machine: i2x2 }
    exposeSSH: true                    # open a public DNAT port -> guest :22
    authorizeDeployerGithubKeys: true  # authorize your github.com/<user>.keys
    authorizedSSHKeys: [ "ssh-ed25519 AAAA... me@laptop" ]
    ports:
      - { name: api, port: 8080, type: http }   # -> <name>.<server-domain>
      - { name: db,  port: 5432, type: tcp }     # -> host:port via DNAT
```

Password auth is off. The `garnix` user always authorizes the operator-owned
hosting key so the backend can deploy, redeploy, and discover login users after
activation, but it has no human direct-SSH keys by default; add those with
`authorizeDeployerGithubKeys` and/or `authorizedSSHKeys`. `exposeSSH` only opens
network reachability; it grants no human login by itself. The authenticated
browser terminal is separate and may log in as `garnix` or any real guest user
captured after activation via a short-lived terminal-CA certificate. Or bring
your own login user in the guest config (declare `users.users.<name>` with
`openssh.authorizedKeys.keys`, the [user-module](https://github.com/garnix-io/user-module)
pattern) and use `exposeSSH`/tailscale purely for reach. The **Servers** page
shows copyable `ssh` commands per method (Tailscale / ProxyJump / DNAT);
`services.garnixServer.sshHost` supplies the host for ProxyJump + DNAT.

### Redeploy and the in-browser terminal (Servers page)

- **Redeploy** re-runs the whole pipeline for the server's current commit
  (`POST /api/hosts/<id>/redeploy` with `{onlyThisServer}` →
  `Orchestrator.restartCommit`), rebuilding and redeploying, branch or PR. A
  confirm dialog redeploys all of the repo's deployments by default, or scopes to
  just this one (persisted per-commit as `manual_deploy_target`; getDeployPlan
  restricts the rollout and leaves the others running).
- **Open Terminal** opens an in-app xterm.js shell (`/servers/<id>/terminal`)
  over a websocket PTY (`/api/terminal/<id>`) running `ssh garnix@<guest-ip>`
  (guest IP from the DB, never the client). Auth + ownership-gated like `/stats`,
  `Online`-only, fixed command, no port/agent/X11 forwarding, `Origin`
  allowlist, 10-min idle / 60-min max, per-user cap, no content logging.
  Keep `/api/terminal` behind the auth gate and off the bypass list (unlike
  `/api/artifacts`); the fork's `docs/web-terminal.md` has the gate block. The
  "Login as" picker defaults to `garnix` and suggests the guest's real accounts,
  captured at deploy via `getent passwd` (stored in `servers.ssh_users`);
  free-text is allowed but regex-validated (`^[a-z_][a-z0-9_-]{0,31}$`) and
  access is still enforced by the guest sshd. Repo access is re-checked live
  on each connect (a repo turned private closes the terminal), and each session
  cert is pinned to its server by a `server-<hash>` principal the guest enforces
  via `AuthorizedPrincipalsFile`, so a cert minted for one server cannot log into
  another. Recreate existing guests to pick up the principal file.

### Live application logs (Servers page)

Application logging is disabled by default. Enable it on a server entry; the
optional path defaults to `/var/log/nginx/hello-access.log`:

```yaml
servers:
  - configuration: myServer
    deployment: { branch: main }
    applicationLog:
      enable: true
      path: /var/log/my-service.log
```

The server row's **Logs** modal is split horizontally into immutable deployment
output and the live service log. The backend runs only a fixed `tail -n 10000
-F -- <validated-path>` over its existing private hosting-key SSH channel; it
does not open a guest port or accept a configurable command.
`applicationLog.path` must be absolute and cannot contain `..`, NUL, or newline
path components. The endpoint uses the same owner/installed-organization
visibility check as server stats.

Scrollback is process-local and bounded per server to the newest 10,000 lines
and 10 MiB, with each line capped at 16,384 characters. After a backend restart,
each live configured server reconnects and seeds a fresh buffer from the newest
10,000 file lines. A persistent redeploy replaces the old collector and buffer;
setting `applicationLog.enable` false disables it. Deleting a server stops its
collector while leaving recent bounded scrollback available until the backend
process exits.

The application must create and write the configured file. When nginx is
enabled, the composite guest module orders `logrotate-checkconf` after nginx so
systemd has created and chowned `/var/log/nginx` before logrotate switches to
the nginx UID. For another service, declare equivalent directory ownership and
activation ordering in that service's NixOS module.

## Custom and vanity domains

`garnix.yaml` `servers[].domains:` declares extra hostnames a server answers
on. Each is checked against known hosting bases: the default `appsDomain`,
operator `extraHostingDomains` (`services.garnixServer`, e.g. the wildcard
vanity domains in `dotfiles-secrets/domains.nix`), and any admin-verified
connected domain. Under a base → wildcard-covered, no DNS action needed. Not
under any base → bare custom domain, needs an `A` record (→ erdtree's
`hostingPublicIp`) or a `CNAME` (→ a garnix domain).

- **Operator wildcard bases:** each `extraHostingDomains` entry needs its own
  manual `*.<domain>` → erdtree DNS record, same as `appsDomain`'s.
- **Connected domains** (Configure page, admin-only): add a domain, point its
  DNS at garnix, click **Verify**. This is a DNS-points-here lookup (does it
  resolve to erdtree?), not a TXT token/ownership challenge.
- **Servers page (i) menu:** per-domain DNS records to set (`A`/`CNAME`) with
  a live "resolves here yet?" status, using the same check as Verify.

## Gating a deployed server behind Authentik

`garnix-ci.nixosModules.garnix-authentik` locks a deployed server behind an OIDC
login with one import: it runs `oauth2-proxy` + an nginx forward-auth gate on
`:80` (the port Traefik hits), so every request needs a valid session before it
reaches your service on `garnix.authentik.upstream`. Three modes:

- **`mode = "default"` (fastest, dev):** put `authentik: default` on the server's
  `garnix.yaml` entry. garnix drops its own OIDC client creds + this deploy's
  redirect URL onto the guest at deploy time
  (`/var/garnix/keys/default-authentik.env`). No provider setup, no secret in the
  repo; whoever can log into garnix can reach the app. Requires
  `services.garnixServer.defaultAuthentik = { issuerUrl, clientId,
  clientSecretFile }` on erdtree (already set in the aspect) and the deploy
  callback URLs allowed on that Authentik provider (use a regex redirect URI).

  ```yaml
  servers:
    - configuration: hello
      deployment: { type: on-branch, branch: main }
      authentik: default
  ```
  ```nix
  garnix.authentik = { enable = true; mode = "default"; upstream = "127.0.0.1:8080"; };
  ```

- **`mode = "dedicated"` (default) / `"shared"`:** the app gets its own Authentik
  provider (or shares one gated by group claims). Deliver the OIDC client secret
  the garnix-native way: encrypt it to the repo key
  (`GET /api/keys/<owner>/<repo>/repo-key.public`, or the `authentik-provision`
  helper) and reference the `.age` ciphertext by path (`clientSecretFile`) or
  inline (`clientSecretAge`); the guest decrypts at runtime with the repo private
  key garnix drops at `/var/garnix/keys/repo-key`. No plaintext secret reaches
  the world-readable nix store. Full worked recipes (dedicated vs shared, the
  provision helper, regex redirect URIs) are in `docs/authentik-cookbook.md` in
  the fork.

  ```nix
  modules = [
    garnix-ci.nixosModules.garnix-guest
    garnix-ci.nixosModules.garnix-authentik
    {
      garnix.authentik = {
        enable = true;
        publicUrl = "https://hello.main.<repo>.<owner>.<appsDomain>";
        issuerUrl = "https://<authentik>/application/o/<app>/";
        clientId = "<oidc client id>";
        clientSecretFile = ./client-secret.age;   # committed, repo-key-encrypted
        allowedGroups = [ "app-users" ];           # omit to gate on entitlements
        upstream = "127.0.0.1:8080";               # your service (NOT on :80)
      };
      services.myApp.port = 8080;
    }
  ];
  ```

The public-key endpoints (`/api/keys/*`), status badges (`/api/badges/*`), and
webhooks (`/api/events/*`) bypass the Authentik gate in Caddy: the provision
helper and guests fetch repo public keys unauthenticated (they can encrypt, not
decrypt).

The cookie secret is generated once per guest and persisted at
`/var/lib/garnix-authentik/cookie-secret`. It must be URL-safe unpadded base64
(43 chars, decoding to 32 bytes). oauth2-proxy decodes it with Go's
`base64.RawURLEncoding` and falls back to the literal string on failure, so
standard `base64` output is taken as a 44-byte key and the process refuses to
start. Keep the `tr '+/' '-_' | tr -d '='` in any generator you write, and
validate rather than merely existence-check a persisted secret. Verifying a
gated deploy end to end is one curl; a working gate 302s to `/oauth2/start`
and follows through to the Authentik login flow:

```bash
curl -sSL -o /dev/null -w '%{http_code} %{url_effective}\n' \
  https://<pkg>.<branch>.<repo>.<owner>.<appsDomain>/oauth2/start
```
