{ pkgs }:
{
  packages = [ (pkgs.callPackage ../../packages/checklist-view { }) ];
}
