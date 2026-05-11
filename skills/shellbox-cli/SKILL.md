# shellbox.dev CLI

## Overview

`shellbox.dev` is "instant Linux boxes via SSH". The product surface is the SSH server itself — every command is `ssh shellbox.dev <command>`, every box is reached at `ssh <name>@shellbox.dev`. No web dashboard, no API key, no signup. Identity = your SSH public key fingerprint.

**Core idioms:**

- `ssh shellbox.dev <command> [args] [--json]` — control plane (account, boxes, billing).
- `ssh <name>@shellbox.dev` — log into a specific box.
- Most subcommands accept `--json` for scripting; errors go to stderr with non-zero exit codes.

## When to use

- User pastes/uses a `ssh shellbox.dev …` command.
- User says "shellbox", "spin up a box", "give me a remote dev box", "I need a Linux VM for X".
- Coding agent is asked to manage its own box (e.g. "stop the box when you're done").
- User wants an ephemeral microVM reachable by URL/email/SSH — not a long-lived server.

## When NOT to use

- User wants a managed PaaS (Fly, Render, Vercel) — shellbox is a microVM, not a container scheduler.
- User wants a persistent production server with backups — shellbox does **no backups**, data loss is on the user.
- User wants Windows/macOS — shellbox is `linux/amd64` only.

## First-time setup

```bash
# 1. Make sure the user has an ed25519 key.
ssh-keygen -t ed25519       # only if ~/.ssh/id_ed25519 doesn't exist

# 2. (Optional but recommended) Skip the host-trust prompt forever using
#    SSHFP/DNSSEC. Add to ~/.ssh/config:
#
#    Host shellbox.dev
#        VerifyHostKeyDNS yes

# 3. First connection auto-creates the account from the key fingerprint.
ssh shellbox.dev help
```

OpenSSH 9.0+ negotiates the post-quantum hybrid KEX `sntrup761x25519-sha512@openssh.com` automatically — nothing to configure.

## Key concepts

| Concept | Detail |
|---------|--------|
| **Account** | Auto-created from your SSH key fingerprint on first connection. No email/password. |
| **Sizes** | `x1`–`x8`. x1 = 2 vCPU / 4 GB RAM / 50 GB SSD. xN scales linearly in CPU/RAM/disk **and price**. Set at create; cannot be resized — delete + recreate (or `duplicate`). |
| **Slot limits** | 16 running slots, 64 total slots per account. An xN box uses N slots. |
| **Backends** | `--fc` Firecracker (default; faster snapshots). `--ch` Cloud Hypervisor (slower snapshots, **nested virtualization** + `/dev/kvm`). Set at create. |
| **Source** | `stock` (Ubuntu 24.04 + Docker pre-installed) or `oci` (rootfs derived from a public Ubuntu/Debian-like image). |
| **State** | `running` / `stopped`. Disconnect pauses to memory snapshot — reconnect resumes processes. |
| **Modes** | `keepalive` (stays up after disconnect), `wakeup` (auto-start on HTTP, idle-stop), `cron` (periodic wake → POST `/cron` → stop). |
| **URL** | Every box gets `https://<name>-<hash>.shellbox.dev` proxied to guest port 80, automatic TLS. |
| **Email** | Every box gets `<name>-<hash>@in.shellbox.dev`. Cloudflare forwards inbound mail to `POST /email` on the box's HTTPS endpoint. |
| **IPv6 (optional)** | When operator-enabled, new boxes get a stable public IPv6 for direct SSH/mosh/raw TCP **while running**. Does NOT wake stopped boxes. |
| **Region** | Helsinki, Finland. (US planned — issue #14.) |
| **Pricing** | Per-minute. x1 ≈ $0.02/hr running, $0.5/month stopped. Boxes auto-stop when balance < $5, deleted at $0. |

## Quick reference

### Account & billing

| Command | Purpose | Notes |
|---------|---------|-------|
| `ssh shellbox.dev help` | List all commands | Add `--json` for schema |
| `ssh shellbox.dev about` | Marketing/about page | |
| `ssh shellbox.dev billing` | Balance + active boxes + burn rate | |
| `ssh shellbox.dev funds <amount>` | Add funds (min $10) | Returns Paddle URL + QR code |
| `ssh shellbox.dev refund <amount>` | Refund unused balance | Within 3 months, min $1 |
| `ssh shellbox.dev payments` | Payment history | |
| `ssh shellbox.dev promocode <code>` | Redeem promo | |

### Box lifecycle

| Command | Purpose | Notes |
|---------|---------|-------|
| `create <name> [xN] [--fc\|--ch]` | New stock box (Ubuntu 24.04 + Docker) | Default `x1`, default `--fc` |
| `create-from-oci <name> <image-ref> [xN] [--fc\|--ch]` | New box from a prepared OCI image | Image must be `image prepare`d first |
| `image prepare <image-ref>` | Convert OCI image into a bootable rootfs (cached) | Public, `linux/amd64`, Ubuntu/Debian-like, `apt-get` available |
| `image status <image-ref>` | Show prep status / digest | |
| `duplicate <src> <name>` | Point-in-time copy of a stopped box | Inherits size; works as a snapshot/backup |
| `rename <name> <new>` | Rename a box | Safe during active SSH; URL/email change to match new name |
| `list` | List all your boxes | `--json` for scripting |
| `show <name>` | Detailed metadata | Includes IPv6 if enabled |
| `stop <name>` | Force-stop, clears `keepalive`, preserves `wakeup`/`cron` | The escape hatch for runaway boxes |
| `delete <name>` | Delete the box | Irreversible |

### Modes

Modes are per-box toggles. Only one of `keepalive` / `wakeup` / `cron` is meaningful at a time, but they're independent commands.

| Command | Purpose |
|---------|---------|
| `keepalive <name>` | Toggle: box stays running after SSH disconnect (otherwise it pauses) |
| `wakeup <name> [min]` | Toggle: HTTP request auto-starts the box; stops after `min` minutes of TCP idle (default 5) |
| `cron <name> <interval_min> [runtime_min]` | Toggle: every `interval_min`, wake the box, POST `http://localhost:80/cron`, run for `runtime_min`, stop |

A live SSH session blocks cron stop until you disconnect.

### Connecting & file transfer

| Command | Purpose |
|---------|---------|
| `ssh <name>@shellbox.dev` | Interactive shell (auto-resumes paused box) |
| `ssh -A <name>@shellbox.dev` | Forward your local SSH agent — clone GitHub without copying keys |
| `ssh -L 8080:localhost:80 <name>@shellbox.dev` | Port-forward guest:80 → localhost:8080 |
| `ssh -R 3000:localhost:3000 <name>@shellbox.dev` | Reverse forward your local 3000 into the box |
| `ssh -D 1080 <name>@shellbox.dev` | SOCKS5 proxy on localhost:1080 |
| `ssh -fN <flags…> <name>@shellbox.dev` | Background tunnel without opening a shell |
| `scp file.txt <name>@shellbox.dev:/root/` | Copy local → box |
| `scp <name>@shellbox.dev:/root/file.txt ./` | Copy box → local |
| `sftp <name>@shellbox.dev` | Interactive SFTP (also enables VS Code Remote SSH, Zed, etc.) |
| `mosh root@<ipv6>` | UDP-based shell, requires direct IPv6 + box already running |

### SSH keys (multi-device)

| Command | Purpose |
|---------|---------|
| `key list` | Show keys linked to your account |
| `key add "<pubkey>"` | Add another key (laptop, phone, deploy key) |
| `key remove <fingerprint>` | Revoke a key |

Each linked key gets full account access.

### Custom domains

| Command | Purpose |
|---------|---------|
| `domain add <box> <hostname>` | Create pending mapping |
| `domain verify <box> <hostname>` | Activate after DNS is in place |
| `domain remove <box> <hostname>` | Detach |
| `domain list` | List all your custom domains |

DNS pointer (CNAME for subdomains; A/AAAA/ALIAS for apex):

```
app.example.com CNAME <box>-<hash>.shellbox.dev
```

DNS must be **DNS-only** (not CDN-proxied) — proxied records resolve to CDN IPs and fail verification. Multiple custom domains per box are fine. Domains survive `rename` (they point to the VM, not the name). v1 = exact hostnames only, no wildcards. Ownership is checked at `verify`, not continuously revalidated.

## Common patterns

### Spin up a quick dev box

```bash
ssh shellbox.dev create dev1 x2
ssh dev1@shellbox.dev          # interactive shell
# work, then disconnect — box pauses to snapshot, billing drops to idle
ssh dev1@shellbox.dev          # resume exactly where you left off
```

### Install Nix on a stock box

```bash
ssh mybox@shellbox.dev
sh <(curl --proto '=https' --tlsv1.2 -L https://nixos.org/nix/install) --daemon
. /etc/profile.d/nix.sh   # or reconnect
```

Upstream multi-user installer (matches the rest of this dotfiles setup). Survives the pause/resume cycle. Flakes aren't on by default — enable in `~/.config/nix/nix.conf` or `/etc/nix/nix.conf`. For the full guide — flake-enable, dev shells, home-manager from a flake, GC, single-user mode, uninstall, troubleshooting — read `nix-install.md` in this skill's base directory.

### Use it as a hosted web service (cheap)

```bash
ssh shellbox.dev create webapp x1
ssh webapp@shellbox.dev        # install / deploy your app on :80
exit
ssh shellbox.dev wakeup webapp 10   # auto-start on HTTP, stop after 10min idle
# Optional: attach a real domain
ssh shellbox.dev domain add webapp app.example.com
# (set DNS) ↓
ssh shellbox.dev domain verify webapp app.example.com
```

### Scheduled job (every hour, run for 5 min)

```bash
ssh shellbox.dev create batch x1
ssh batch@shellbox.dev         # write a service that listens on POST /cron
ssh shellbox.dev cron batch 60 5
```

### Run a coding agent inside a box and let it stop itself

```bash
# Local: enable keepalive, log in
ssh shellbox.dev keepalive mybox
ssh mybox@shellbox.dev

# Inside the box: generate a dedicated key and add it to your account
ssh-keygen -t ed25519 -N "" -f ~/.ssh/id_ed25519
cat ~/.ssh/id_ed25519.pub
# (back on local) ssh shellbox.dev key add "<paste>"

# Inside the box: start tmux, launch the agent, disconnect
tmux
claude    # or codex / aider / etc.

# Tell the agent to run, when finished:
ssh shellbox.dev stop mybox    # clears keepalive, pauses billing
```

`scp ~/.ssh/id_ed25519 mybox@shellbox.dev:/root/.ssh/` works too, but a dedicated key is more revocable.

### OCI image-backed box

```bash
ssh shellbox.dev image prepare docker.io/library/debian:bookworm-slim
ssh shellbox.dev create-from-oci debbox docker.io/library/debian:bookworm-slim
ssh debbox@shellbox.dev
```

OCI images become the **rootfs of a microVM** — Docker semantics (`CMD`, `ENTRYPOINT`, `EXPOSE`, healthchecks) are NOT preserved. You SSH in and run whatever you want.

### IDE remote (VS Code / Zed / JetBrains)

Point the IDE's SSH remote at `<name>@shellbox.dev`. SFTP and SSH agent forwarding both work. For VS Code Remote SSH, an entry in `~/.ssh/config` like:

```
Host mybox
    HostName shellbox.dev
    User mybox
    ForwardAgent yes
```

### GitHub from inside a box

| Approach | When |
|----------|------|
| `ssh -A` agent forwarding | One-off clones; key never leaves your laptop |
| HTTPS + PAT | Long-lived, no SSH keys; cache with `git config --global credential.helper store` |
| `gh auth login` | Interactive device-code flow |
| Generate a key in the box | Dedicated deploy key per box |

### JSON for scripts

```bash
ssh shellbox.dev list --json | jq '.boxes[] | select(.state=="running") | .name'
ssh shellbox.dev show mybox --json
ssh shellbox.dev billing --json
ssh shellbox.dev help --json    # full command schema
```

Fields are only added over time, never removed/renamed — safe to depend on what you see today.

## Common mistakes

| Mistake | Fix |
|---------|-----|
| Calling shellbox a "container service" | It runs **microVMs** (Firecracker / Cloud Hypervisor). Docker semantics from OCI images are NOT preserved. |
| `shutdown -h now` from inside a `keepalive` box and expecting billing to stop | Shellbox honors the keepalive flag on disconnect. Use `ssh shellbox.dev stop <name>` from outside (or from inside, after adding your key — see agent-stop pattern). |
| Trying to resize a box | Sizes are immutable. `duplicate` to a new name with the new size, or `delete` + `create`. |
| Pointing a CDN-proxied DNS record at a custom domain | DNS must be **DNS-only**. Proxied records resolve to CDN IPs and `domain verify` fails. |
| Expecting `mosh` to wake a stopped box | mosh + direct IPv6 are a separate access plane. Box must already be running. Start it via `ssh <name>@shellbox.dev` first (with keepalive on), or use the HTTPS URL to wake it. |
| Using a private/non-amd64/non-Ubuntu OCI image | v1 supports public, `linux/amd64`, Ubuntu/Debian-like images with `apt-get`. Others may fail `image prepare`. |
| Letting balance drop below $5 unnoticed | Boxes auto-stop at <$5, are deleted at $0. Check `ssh shellbox.dev billing` regularly; refunds are bounded to 3 months. |
| Assuming shellbox backs up data | It does not. Use `scp`/`sftp`, or `duplicate` a stopped box for a point-in-time snapshot. |
| Running a coding agent without `keepalive` | Disconnect pauses the box → agent stops mid-task. Toggle keepalive first; have the agent `ssh shellbox.dev stop <name>` when done. |

## Failure modes & diagnostics

- **"Trust this host?" prompt** — set `VerifyHostKeyDNS yes` in `~/.ssh/config` (DNSSEC + SSHFP are published).
- **Box won't wake on HTTP** — confirm `wakeup` is enabled (`show <name>`); check the URL is the canonical `<name>-<hash>.shellbox.dev` or a verified custom domain; first request after a long idle blocks until ready.
- **Custom domain not routing** — re-run `domain verify`; check DNS is DNS-only (not CDN-proxied); first request after verification waits a few seconds for TLS issuance.
- **Image prepare fails** — likely private registry, non-amd64, non-Ubuntu/Debian, or no `apt-get`. Pick a different base image.
- **Balance running out** — `ssh shellbox.dev billing` shows burn rate and runway. Top up with `funds <amount>` (min $10).

## Security model

- Identity is your SSH public key fingerprint. Add multiple keys with `key add`; revoke with `key remove`.
- Linked keys are equivalent — full account access. Treat them like password-equivalents.
- Custom domain ownership is checked once at `verify`; not continuously revalidated in v1.
- Email endpoint goes through Cloudflare → HTTPS POST to your box. Treat `/email` as untrusted input.
- Wakeup mode means **anyone** who can reach your URL can wake the box. If that matters, gate `/` with auth.
