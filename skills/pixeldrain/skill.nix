{ pkgs }:
{
  packages = [ (pkgs.callPackage ../../packages/pxd { }) ];
}
