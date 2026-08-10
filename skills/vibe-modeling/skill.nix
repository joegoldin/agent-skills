{ pkgs }:
{
  packages = [ (pkgs.callPackage ../../packages/vibecad { }) ];
}
