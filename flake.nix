{
  description = "Claude Code agent skills, commands, and hooks";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    claude-nix = {
      url = "github:joegoldin/claude-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      nixpkgs,
      claude-nix,
      ...
    }:
    let
      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "aarch64-darwin"
        "x86_64-darwin"
      ];
      forAllSystems =
        f:
        nixpkgs.lib.genAttrs systems (
          system:
          f {
            pkgs = import nixpkgs { inherit system; };
            inherit system;
          }
        );
    in
    {
      packages = forAllSystems (
        { pkgs, ... }:
        let
          lib = pkgs.lib;
          claudeLib = import "${claude-nix}/lib" { inherit pkgs; };
          build = import ./lib/default.nix { inherit pkgs lib claudeLib; };

          # Discover and build all skills
          skills = build.discoverSkills ./skills;

          # Build the complete plugin
          plugin = build.buildPlugin {
            name = "agent-skills";
            description = "Claude Code skills, commands, and agents";
            inherit skills;
            hooksDir = ./hooks;
            attributionFile = ./ATTRIBUTION.md;
          };

          # Per-skill packages (auto-generated)
          perSkillPackages = lib.listToAttrs (
            map (s: {
              name = s.name;
              value = s.drv;
            }) skills
          );
        in
        perSkillPackages // { default = plugin; }
      );
    };
}
