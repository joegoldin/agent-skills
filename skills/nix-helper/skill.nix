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
        You are working in a multi-platform Nix dotfiles repo. Use this context to make changes efficiently.

        ## Hosts

        | Host | Platform | Config dir |
        |------|----------|------------|
        | joe-desktop | NixOS (x86_64-linux), KDE Plasma 6 | hosts/nixos/ |
        | office-pc | NixOS (x86_64-linux), compute/training, AMD GPU | hosts/office-pc/ |
        | joe-steamdeck | NixOS (x86_64-linux), Jovian/Steam Deck | hosts/steamdeck/ |
        | Joes-MacBook-Pro | macOS (aarch64-darwin) | hosts/darwin/ |
        | joe-wsl | NixOS on WSL | hosts/wsl/ |
        | oracle-cloud-bastion | NixOS server | hosts/oracle-cloud/ |
        | racknerd-cloud-agent | NixOS server | hosts/racknerd-cloud/ |

        ## Key Files — Where to make changes

        | What you want to do | File(s) to edit |
        |---------------------|-----------------|
        | Add a NixOS desktop package | hosts/nixos/packages.nix |
        | Add a common CLI package | hosts/common/home/packages.nix |
        | Define a custom package from source | hosts/common/system/pkgs/default.nix (or new .nix file there) |
        | Add a flake input | flake.nix (inputs section) |
        | Add an overlay | hosts/common/system/overlays/default.nix |
        | Configure a home-manager program | hosts/common/home/<program>.nix |
        | NixOS system config (services, boot, etc.) | hosts/nixos/joe-desktop.nix or hosts/nixos/configuration.nix |
        | macOS homebrew package | hosts/darwin/homebrew.nix |
        | macOS system settings | hosts/darwin/defaults.nix |
        | KDE Plasma config | hosts/nixos/plasma.nix |
        | Fish shell config | hosts/common/home/fish/ |
        | Git config | hosts/common/home/git.nix |

        ## Package Patterns (copy these)

        **Nixpkgs stable:** `pkgs.packageName`
        **Nixpkgs unstable:** `unstable.packageName` (overlay provides `pkgs.unstable.*`)
        **Custom package from GitHub (npm/yarn):** See `hosts/common/system/pkgs/default.nix`
        **Custom package from GitHub (Go):** See `hosts/common/home/go.nix` — `claude-squad` using `buildGoModule`
        **Custom package from GitHub (binary):** See `hosts/common/home/sprites.nix` — platform-specific binary fetch
        **Custom Python package:** See `hosts/common/home/python/custom-pypi-packages.nix`
        **Shell wrapper:** See `google-chrome-stable` or `aws-cli` in `hosts/common/system/pkgs/default.nix`
        **Flake input package:** Add input to `flake.nix`, use via overlay or direct reference

        ## Overlays (hosts/common/system/overlays/default.nix)

        - `additions` — custom packages from `hosts/common/system/pkgs/`
        - `modifications` — patches to existing packages
        - `unstable-packages` — makes `pkgs.unstable.*` available
        - `llm-agents-packages` — Claude Code, Codex, Gemini CLI
        - `mcps-packages` — MCP servers

        ## Conventions

        - Formatter: nixfmt (pre-commit hook enforced)
        - Lint: statix, gitleaks
        - Dual nixpkgs: stable (nixos-25.11) + unstable channel
        - Apply NixOS: `sudo nixos-rebuild switch --flake .`
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
