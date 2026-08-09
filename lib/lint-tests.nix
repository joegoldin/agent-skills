{ lib }:
let
  fm = import ./frontmatter.nix { inherit lib; };
  lint = import ./lint.nix { inherit lib; };
  ok = fm.parse ''
    ---
    name: good-skill
    description: Use when testing lint
    allowed-tools: Bash(git:*) Read
    context: fork
    ---
    body
  '';
  tryValidate = args: (builtins.tryEval (lint.validateSkillMd args)).success;
in
lib.debug.runTests {
  testValidSkill = {
    expr = tryValidate {
      dirName = "good-skill";
      parsed = ok;
    };
    expected = true;
  };
  testNameDirMismatch = {
    expr = tryValidate {
      dirName = "other-dir";
      parsed = ok;
    };
    expected = false;
  };
  testUppercaseName = {
    expr = tryValidate {
      dirName = "Bad-Name";
      parsed = fm.parse "---\nname: Bad-Name\ndescription: y\n---\nbody";
    };
    expected = false;
  };
  testMissingDescription = {
    expr = tryValidate {
      dirName = "x";
      parsed = fm.parse "---\nname: x\n---\nbody";
    };
    expected = false;
  };
  testUnknownKey = {
    expr = tryValidate {
      dirName = "x";
      parsed = fm.parse "---\nname: x\ndescription: y\nfrobnicate: z\n---\nbody";
    };
    expected = false;
  };
  testClaudeCodeFieldAllowed = {
    expr = tryValidate {
      dirName = "x";
      parsed = fm.parse "---\nname: x\ndescription: y\ndisable-model-invocation: true\n---\nbody";
    };
    expected = true;
  };
  testSpaceFormWithInternalSpacesRejected = {
    # Bash(sem diff:*) space-split would shear mid-entry; must use commas.
    expr = tryValidate {
      dirName = "x";
      parsed = fm.parse "---\nname: x\ndescription: y\nallowed-tools: Bash(sem diff:*) Bash(sem impact:*)\n---\nbody";
    };
    expected = false;
  };
  testMultilineDescriptionMarkerRejected = {
    expr = tryValidate {
      dirName = "x";
      parsed = fm.parse "---\nname: x\ndescription: >\n---\nbody";
    };
    expected = false;
  };
  testSidecarGood = {
    expr =
      (builtins.tryEval (
        lint.validateSidecar "x" {
          packages = [ ];
          mcpServers = { };
          lspServers = { };
        }
      )).success;
    expected = true;
  };
  testSidecarRejectsLegacyKeys = {
    expr = (builtins.tryEval (lint.validateSidecar "x" { description = "nope"; })).success;
    expected = false;
  };
}
