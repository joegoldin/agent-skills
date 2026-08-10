{ pkgs }:
{
  packages = [ (pkgs.callPackage ../../packages/figr { }) ];
}
