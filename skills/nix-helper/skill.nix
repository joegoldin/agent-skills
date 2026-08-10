{ pkgs, lib }:
{
  packages = [
    pkgs.statix
    pkgs.nixfmt
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
