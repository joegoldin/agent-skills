{
  pkgs,
  lib,
  claudeLib,
}:
{
  name = "nix-helper";
  description = "Helps with Nix development and formatting";
  allowed-tools = [
    "Bash(${pkgs.statix}/bin/statix)"
    "Bash(${pkgs.nixfmt}/bin/nixfmt)"
  ];

  commands = [
    (claudeLib.mkCommand
      {
        name = "format-nix";
        description = "Format all Nix files in the project";
        allowed-tools = [
          "Bash(${pkgs.nixfmt}/bin/nixfmt)"
          "Bash(${pkgs.fd}/bin/fd)"
        ];
        argument-hint = "[directory]";
      }
      ''
        Format all Nix files using nixfmt.

        If an argument is provided, format files in that directory.
        Otherwise, format all .nix files in the current directory.

        Use: ${pkgs.fd}/bin/fd -e nix -x ${pkgs.nixfmt}/bin/nixfmt

        $ARGUMENTS
      ''
    )
    (claudeLib.mkCommand
      {
        name = "nix-dotfiles";
        description = "Make changes to the NixOS/nix-darwin dotfiles with full repo context pre-loaded";
        argument-hint = "<what to change>";
      }
      ''
        You are working in a multi-platform Nix dotfiles repo organized around
        the dendritic pattern with den (github:denful/den): every non-underscore
        .nix file under modules/ is auto-loaded as a flake-parts module, features
        are den *aspects* (one file per feature, carrying nixos/darwin/homeManager
        halves together), and hosts are den *entities* that select aspects via
        `includes`. Read the repo's README.md for the architecture; the key rule:
        a NEW file under modules/ is immediately live — disable by underscore-
        prefixing, never by commenting an import.

        ## Hosts (modules/hosts/<dir>/)

        | Host | Platform | Config dir |
        |------|----------|------------|
        | joe-desktop | NixOS (x86_64-linux), KDE Plasma 6 | modules/hosts/joe-desktop/ |
        | office-pc | NixOS (x86_64-linux), compute/training, AMD GPU | modules/hosts/office-pc/ |
        | joe-steamdeck | NixOS (x86_64-linux), Jovian/Steam Deck | modules/hosts/joe-steamdeck/ |
        | Joes-MacBook-Pro | macOS (aarch64-darwin) | modules/hosts/macbook/ |
        | cloud-proxy | NixOS VPS (caddy reverse proxy) | modules/hosts/cloud-proxy/ |
        | oracle-cloud-bastion | NixOS server (hostName "bastion") | modules/hosts/oracle-cloud-bastion/ |
        | racknerd-cloud-agent | NixOS server (attic cache) | modules/hosts/racknerd-cloud-agent/ |

        Each host dir: default.nix (entity + aspect includes + agenix secrets),
        system.nix (base system), machine.nix (hardware tuning), home.nix
        (host-specific home config), plus per-concern sibling files — all merge
        into den.aspects.<host> by name.

        ## Key Files — Where to make changes

        | What you want to do | File(s) to edit |
        |---------------------|-----------------|
        | Add a CLI package for every full home | modules/home/packages/default.nix (cli-packages aspect) |
        | Add a workstation package | modules/home/packages/workstation.nix (linux-only: linux-workstation.nix) |
        | Add a host-specific package | modules/hosts/<host>/home.nix (or its _packages payload) |
        | Define a custom package from source | modules/flake/_pkgs/ (register in its default.nix) |
        | Add a flake input | flake.nix (inputs; reference it only in the owning aspect) |
        | Add an overlay | modules/flake/_overlays/default.nix (see its README) |
        | New home-manager feature | modules/home/<feature>.nix as den.aspects.<feature>.homeManager, then add to a host's includes / home-baseline / users/joe.nix |
        | NixOS system config for one host | modules/hosts/<host>/system.nix or a new sibling aspect file |
        | Shared system feature | modules/system/<feature>.nix (aspect) |
        | macOS homebrew package | modules/hosts/macbook/homebrew.nix |
        | macOS system settings | modules/hosts/macbook/mac-system.nix |
        | KDE Plasma config | modules/home/plasma.nix (shared) or modules/hosts/<host>/home.nix + _plasma-panels.nix |
        | Fish shell config | modules/home/fish/ |
        | Git config | modules/home/git.nix |
        | AI tooling (claude/codex/antigravity/mcp) | modules/ai/ |
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
        - `llm-agents-packages` — Claude Code, Codex, Gemini CLI
        - `mcps-packages` — MCP servers

        ## Conventions

        - Formatter: nixfmt (pre-commit hook enforced)
        - Lint: statix, gitleaks
        - Dual nixpkgs: stable (nixos-26.05) + unstable channel (`pkgs.unstable.*`)
        - No URL pins (flake.lock is the pin; update via `just flake-update`)
        - Apply NixOS: `just switch` (nh) or `sudo nixos-rebuild switch --flake .`
        - Apply macOS: `darwin-rebuild switch --flake .`
        - Test build: `nix build .#packageName`

        ## Your task

        $ARGUMENTS

        Read the relevant files first, then make the changes. Follow existing patterns in the repo. Format changed .nix files with `${pkgs.nixfmt}/bin/nixfmt`.
      ''
    )
  ];

  agents = [
    (claudeLib.mkAgent
      {
        name = "nix-analyzer";
        description = "Specialized agent for analyzing Nix code";
        tools = [
          "Read"
          "Glob"
          "Grep"
          "Bash(${pkgs.statix}/bin/statix)"
        ];
      }
      ''
        You are an expert Nix code analyzer. When asked to analyze Nix code:

        1. Search for all .nix files in the project
        2. Run statix to identify anti-patterns
        3. Analyze the flake structure and dependencies
        4. Provide recommendations for improvements
        5. Explain any complex Nix patterns found

        Be thorough and educational in your analysis.
      ''
    )
  ];

  mcpServers = {
    nixos = {
      command = "${pkgs.mcp-nixos}/bin/mcp-nixos";
    };
  };

  lspServers = {
    nix = {
      command = lib.getExe pkgs.nixd;
      extensionToLanguage = {
        ".nix" = "nix";
      };
    };
  };
}
