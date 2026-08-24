{ pkgs }:
{
  packages = [ (pkgs.callPackage ../../packages/re-shell { }) ];
}
