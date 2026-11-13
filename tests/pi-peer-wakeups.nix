{
  pkgs,
  lib,
  piModule,
  coreModule,
}:
let
  evaluate =
    module: extra:
    (lib.evalModules {
      specialArgs = {
        inherit pkgs;
        osConfig = { };
      };
      modules = [
        module
        {
          options.home = lib.mkOption {
            type = lib.types.attrs;
            default = { };
          };
          options.xdg = lib.mkOption {
            type = lib.types.attrs;
            default = { };
          };
          config.home.homeDirectory = "/tmp/pi-peer-test-home";
          config.programs.pi.coding-agent.enable = true;
        }
        extra
      ];
    }).config.programs.pi.coding-agent;
  profile = evaluate piModule { };
  overridden =
    policy:
    evaluate piModule {
      programs.pi.coding-agent.messaging.inboundTrigger = policy;
    };
  core = evaluate coreModule { };
in
{
  inherit (profile.messaging) inboundTrigger;
  failures = lib.debug.runTests {
    testPeerProfileStartsNewAssignments = {
      expr = profile.messaging.inboundTrigger;
      expected = "always";
    };
    testExplicitReplyOnlyPolicyIsPreserved = {
      expr = (overridden "replies").messaging.inboundTrigger;
      expected = "replies";
    };
    testExplicitNoWakePolicyIsPreserved = {
      expr = (overridden "never").messaging.inboundTrigger;
      expected = "never";
    };
    testLibraryDefaultRemainsConservative = {
      expr = core.messaging.inboundTrigger;
      expected = "replies";
    };
    testMessagingAndPermissionsRemainEnabled = {
      expr = profile.messaging.enable && profile.autoMode.enable;
      expected = true;
    };
  };
}
