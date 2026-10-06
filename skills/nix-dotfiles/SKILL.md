---
name: nix-dotfiles
description: Make changes to the NixOS/nix-darwin dotfiles with full repo context pre-loaded
disable-model-invocation: true
argument-hint: "<what to change>"
---

You are working in a multi-platform Nix dotfiles repo organized around
the dendritic pattern with den (github:denful/den): every non-underscore
.nix file under modules/ is auto-loaded as a flake-parts module, features
are den *aspects* (one file per feature, carrying nixos/darwin/homeManager
halves together), and hosts are den *entities* that select aspects via
`includes`. Read the repo's README.md for the architecture; the key rule:
a new file under modules/ is immediately live, so disable one by
underscore-prefixing it rather than commenting out an import.

## Hosts (modules/hosts/<name>/)

README.md holds the host table (name, platform, role); `ls modules/hosts/`
lists every host, and each `default.nix` opens with a comment on what the
machine is for. This machine is `torrent` (aarch64-darwin).

A host dir usually has default.nix (entity, aspect includes, agenix
secrets), system.nix (base system), machine.nix (hardware tuning) and home.nix
(host-specific home config), plus per-concern sibling files; all merge into
den.aspects.<host> by name.

## Key Files — Where to make changes

| What you want to do | File(s) to edit |
|---------------------|-----------------|
| Add a CLI package for every full home | modules/home/packages/default.nix (cli-packages aspect) |
| Add a workstation package | modules/home/packages/workstation.nix (linux-only: linux-workstation.nix) |
| Add a host-specific package | modules/hosts/<host>/home.nix (or its _packages payload) |
| Define a custom package from source | modules/flake/_pkgs/ (register in its default.nix) |
| Add a flake input | flake.nix (inputs; reference it only in the owning aspect) |
| Add an overlay | modules/flake/_overlays/default.nix (see its README) |
| New home-manager feature | modules/home/<feature>.nix as den.aspects.<feature>.homeManager, then add to a host's includes, home-baseline (modules/home/baseline.nix) or modules/users/joe.nix |
| NixOS system config for one host | modules/hosts/<host>/system.nix or a new sibling aspect file |
| Shared system feature | modules/system/<feature>.nix (aspect) |
| macOS homebrew package | modules/hosts/torrent/homebrew.nix |
| macOS system settings | modules/hosts/torrent/mac-system.nix |
| KDE Plasma config | modules/home/plasma.nix (shared) or modules/hosts/<host>/home.nix + _plasma-panels.nix |
| Fish shell config | modules/home/fish/ |
| Git config | modules/home/git.nix |
| AI tooling (claude, codex, antigravity, pi, mcp) | modules/ai/ |
| User scripts (bins) | modules/home/bin/_scripts/<name>.nix |

## Package Patterns (copy these)

**Nixpkgs stable:** `pkgs.packageName`
**Nixpkgs unstable:** `unstable.packageName` (overlay provides `pkgs.unstable.*`)
**Custom package from GitHub (npm/yarn):** See `modules/flake/_pkgs/default.nix`
**Custom package from GitHub (Go):** See `modules/home/_go.nix` — `buildGoModule` examples
**Custom package from GitHub (binary):** See `modules/home/_sprites.nix` — platform-specific binary fetch
**Custom Python package:** See `modules/home/_python/custom-pypi-packages.nix` (or run the `setup-python-packages` bins command)
**Shell wrapper:** See `google-chrome-stable` or `aws-cli` in `modules/flake/_pkgs/default.nix`
**Flake input package:** Add input to `flake.nix`, use via overlay or direct reference

## Overlays (modules/flake/_overlays/default.nix)

- `additions` — custom packages from `modules/flake/_pkgs/`
- `modifications` — patches to existing packages
- `unstable-packages` — makes `pkgs.unstable.*` available
- `llm-agents-packages` — `pkgs.llm-agents.*` (Claude Code, Codex, Antigravity)
- `mcps-packages` — MCP servers

## Conventions

- Formatter: nixfmt (pre-commit hook; `just lint` runs `nix fmt`)
- Secrets scan: gitleaks (pre-commit hook)
- Dual nixpkgs: stable (nixos-26.05) + unstable channel (`pkgs.unstable.*`)
- No URL pins (flake.lock is the pin; update via `just flake-update`)
- Apply: `just switch` (nh; picks NixOS or nix-darwin for the current host),
  or `just build` to build without activating. Remote hosts have
  `just build-to-<host>` recipes.
- Test build: `nix build .#packageName`
- VCS: the repo is a colocated jj repo; commit with
  `jj commit -m "..." <paths>` and move the bookmark with
  `jj bookmark set main -r @-`, never with git

## Your task

$ARGUMENTS

Read the relevant files first, then make the changes. Follow existing patterns in the repo. Format changed .nix files with `nixfmt`.
