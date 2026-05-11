# Installing Nix on a shellbox

Companion to `SKILL.md` — read this when the user wants to install Nix inside a shellbox box (stock Ubuntu 24.04 or an OCI-backed Debian/Ubuntu image).

## Why this is short

Stock shellbox boxes are Ubuntu 24.04 + Docker running as `root` with systemd. That's the happy path for the upstream multi-user Nix installer from nixos.org.

## Quick install (upstream multi-user)

```bash
ssh mybox@shellbox.dev
sh <(curl --proto '=https' --tlsv1.2 -L https://nixos.org/nix/install) --daemon
```

Accept the prompts. Then either source the profile script in the current shell or reconnect:

```bash
. /etc/profile.d/nix.sh
# or:
exec bash -l
# or: disconnect + ssh back in
```

Verify:

```bash
nix --version
nix-shell -p hello --run hello
```

## Enable flakes

The upstream installer does **not** enable flakes by default. Add them either per-user or system-wide:

```bash
# Per-user (recommended for a single-user box):
mkdir -p ~/.config/nix
echo 'experimental-features = nix-command flakes' >> ~/.config/nix/nix.conf

# Or system-wide:
echo 'experimental-features = nix-command flakes' >> /etc/nix/nix.conf
systemctl restart nix-daemon
```

Test:

```bash
nix run nixpkgs#hello
```

## What this gets you

- `/nix` store with a multi-user daemon as a systemd service (`nix-daemon.service`).
- A `nixbld` group + build users.
- `/etc/profile.d/nix.sh` sourced by new login shells.
- `/nix/var/nix/profiles/default/bin` on `PATH`.

## After install — common follow-ups

### Ephemeral tool shell
```bash
nix shell nixpkgs#ripgrep nixpkgs#fd nixpkgs#jq
```

### Enter a project's dev shell from GitHub
```bash
nix develop github:owner/repo
```

### Apply the user's own dotfiles (home-manager standalone)
```bash
# Example: this dotfiles repo's home-manager config
nix run home-manager/master -- switch \
  --flake github:joegoldin/dotfiles#<hostname>
```

If they want the whole flake locally for editing:
```bash
git clone https://github.com/joegoldin/dotfiles ~/dotfiles
cd ~/dotfiles
nix develop
```

## Snapshot / resume

When the SSH session disconnects, shellbox pauses the VM to a memory snapshot and resumes it on reconnect. `nix-daemon` is a normal systemd service — it survives pause+resume like any other process. **No extra steps required.**

In-flight builds: a `nix build` mid-download when you disconnect will resume from where it left off when the box wakes. A `nix build` mid-compile keeps compiling (with `keepalive` on) or pauses with the VM (with keepalive off) and resumes on reconnect.

## Disk usage — important

x1 ships with **50 GB** SSD total, shared with the OS. The Nix store eats space fast:

- A single Rust/Go/Node toolchain pull: 1–3 GB.
- Building with several flake inputs: 5–10 GB.
- `nix develop` on a meaty repo: another few GB.

Mitigations:

```bash
nix-collect-garbage -d         # GC user + system profiles
nix store optimise             # hard-link duplicate store paths
df -h /                        # check disk
```

If a box regularly needs >40 GB of Nix store, **create a bigger box** — sizes are immutable. `ssh shellbox.dev duplicate <name> <bigger>` after stopping, then build new boxes from that. (See SKILL.md for size↔resources mapping.)

## Single-user install (no systemd)

Pick single-user only when the box has no systemd — e.g. some `create-from-oci` images. Stock boxes have systemd, so prefer the daemon install above.

```bash
sh <(curl --proto '=https' --tlsv1.2 -L https://nixos.org/nix/install) --no-daemon
. ~/.nix-profile/etc/profile.d/nix.sh
mkdir -p ~/.config/nix
echo 'experimental-features = nix-command flakes' >> ~/.config/nix/nix.conf
```

## Uninstall

Multi-user uninstall on the official installer is a manual procedure (stop daemon, remove systemd unit, remove `/nix`, `/etc/nix`, profile snippets, build users + group). Follow:

<https://nix.dev/manual/nix/stable/installation/uninstall>

Since shellbox boxes are cheap and ephemeral, `ssh shellbox.dev delete <name>` is usually the simplest "uninstall".

## Troubleshooting

| Symptom | Fix |
|---------|-----|
| `nix: command not found` immediately after install | New `PATH` isn't in this shell yet. `. /etc/profile.d/nix.sh`, `exec bash -l`, or reconnect. |
| `error: cannot connect to socket at '/nix/var/nix/daemon-socket/socket'` | `systemctl status nix-daemon` → `systemctl restart nix-daemon`. |
| `error: experimental Nix feature 'nix-command'/'flakes' is disabled` | Flakes aren't enabled by default on the upstream installer — see the "Enable flakes" section above. |
| `error: SQLite database is busy` | Daemon restart usually clears it; rare on fresh installs. |
| Out of disk mid-build | `nix-collect-garbage -d`; then `nix store optimise`; then consider a bigger box. |
| Slow first substituter fetch | Box is in Helsinki — first-fetch latency to `cache.nixos.org` is normal. Subsequent fetches are local. |
| Want Nix preinstalled on every new box | Build a box once, install Nix, stop it, then `ssh shellbox.dev duplicate <name> <new>` for each new box. Shellbox has no first-class image-template flow; duplicate is the workaround. |

## Security notes

- Piping `curl | sh` from any vendor is a trust decision. The upstream Nix install script is open-source; if that matters, download it first, inspect it, then run it.
- The Nix daemon runs as root. Anyone who can `ssh` into the box as root (the only login on a stock shellbox) can use it. Add SSH keys deliberately with `ssh shellbox.dev key add` — each linked key is account-equivalent (see SKILL.md security model).
