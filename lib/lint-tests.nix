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
  tryAgent =
    parsed:
    (builtins.tryEval (lint.validateAgentMd {
      skillName = "s";
      fileName = "a.md";
      inherit parsed;
    })).success;
  # Exactly-at-limit and one-over-limit inputs for the spec caps.
  name64 = lib.concatStrings (lib.genList (_: "a") 64);
  name65 = lib.concatStrings (lib.genList (_: "a") 65);
  desc1024 = lib.concatStrings (lib.genList (_: "d") 1024);
  desc1025 = lib.concatStrings (lib.genList (_: "d") 1025);
  mkParsed = name: desc: fm.parse "---\nname: ${name}\ndescription: ${desc}\n---\nbody";
in
lib.debug.runTests {
  testValidSkill = {
    # Success must return the parsed set unchanged, not merely not-throw.
    expr =
      (lint.validateSkillMd {
        dirName = "good-skill";
        parsed = ok;
      }) == ok;
    expected = true;
  };
  testName64Accepted = {
    expr = tryValidate {
      dirName = name64;
      parsed = mkParsed name64 "y";
    };
    expected = true;
  };
  testName65Rejected = {
    expr = tryValidate {
      dirName = name65;
      parsed = mkParsed name65 "y";
    };
    expected = false;
  };
  testDescription1024Accepted = {
    expr = tryValidate {
      dirName = "x";
      parsed = mkParsed "x" desc1024;
    };
    expected = true;
  };
  testDescription1025Rejected = {
    expr = tryValidate {
      dirName = "x";
      parsed = mkParsed "x" desc1025;
    };
    expected = false;
  };
  testEmptyAllowedToolsRejected = {
    # Present-but-empty allowed-tools would restrict the skill to no tools.
    expr = tryValidate {
      dirName = "x";
      parsed = fm.parse "---\nname: x\ndescription: y\nallowed-tools:\n---\nbody";
    };
    expected = false;
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
  testSidecarRejectsForeignKeys = {
    expr = (builtins.tryEval (lint.validateSidecar "x" { description = "nope"; })).success;
    expected = false;
  };
  testAgentAcceptsFullFieldSet = {
    expr = tryAgent (fm.parse ''
      ---
      name: auditor
      description: Audits things
      tools: Read, Bash(git log:*)
      disallowed-tools: Write
      model: inherit
      effort: high
      permission-mode: dontAsk
      max-turns: 20
      memory: project
      isolation: worktree
      background: true
      initial-prompt: Start by reading the diff
      color: blue
      skills: sem
      ---
      body
    '');
    expected = true;
  };
  testAgentAcceptsCamelCaseAliases = {
    expr = tryAgent (
      fm.parse "---\nname: a\ndescription: d\ndisallowedTools: Write\nmaxTurns: 3\n---\nbody"
    );
    expected = true;
  };
  testAgentRejectsUnknownField = {
    expr = tryAgent (fm.parse "---\nname: a\ndescription: d\nallowed-tools: Read\n---\nbody");
    expected = false;
  };
  testAgentRequiresDescription = {
    expr = tryAgent (fm.parse "---\nname: a\n---\nbody");
    expected = false;
  };
}
