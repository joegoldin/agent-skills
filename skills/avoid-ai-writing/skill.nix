{ pkgs }:
{
  # The detector CLI ships with its own wrapped nodejs, so the plugin has no
  # host Node requirement. The web bundle instead vendors the engine source
  # and declares `compatibility: Requires Node.js 18+` (see buildWebBundle) —
  # that constraint applies only to the claude.ai sandbox variant.
  packages = [ (pkgs.callPackage ../../packages/avoid-ai-detect { }) ];
}
