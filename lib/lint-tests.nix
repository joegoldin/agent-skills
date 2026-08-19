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
    (builtins.tryEval (
      lint.validateAgentMd {
        skillName = "s";
        fileName = "a.md";
        inherit parsed;
      }
    )).success;
  # Exactly-at-limit and one-over-limit inputs for the spec caps.
  name64 = lib.concatStrings (lib.genList (_: "a") 64);
  name65 = lib.concatStrings (lib.genList (_: "a") 65);
  desc1024 = lib.concatStrings (lib.genList (_: "d") 1024);
  desc1025 = lib.concatStrings (lib.genList (_: "d") 1025);
  mkParsed = name: desc: fm.parse "---\nname: ${name}\ndescription: ${desc}\n---\nbody";
  piWarn = dirName: parsed: lint.piSkillWarnings { inherit dirName parsed; };
  # Every frontmatter sample that agent-skills accepts must also be clean
  # for pi. This is the containment property, checked as a property rather
  # than restated case by case.
  acceptedSamples = [
    ok
    (mkParsed name64 "y")
    (mkParsed "x" desc1024)
    (fm.parse "---\nname: x\ndescription: y\ndisable-model-invocation: true\n---\nbody")
  ];
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
    expr = tryAgent (
      fm.parse ''
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
      ''
    );
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
  testPiAcceptsValidSkill = {
    expr = piWarn "good-skill" ok;
    expected = [ ];
  };
  testPiRejectsUppercaseName = {
    expr = piWarn "Bad-Name" (fm.parse "---\nname: Bad-Name\ndescription: y\n---\nbody");
    expected = [ "name contains invalid characters (must be lowercase a-z, 0-9, hyphens only)" ];
  };
  testPiRejectsMissingDescription = {
    expr = piWarn "x" (fm.parse "---\nname: x\n---\nbody");
    expected = [ "description is required" ];
  };
  testPiRejectsName65 = {
    expr = piWarn name65 (mkParsed name65 "y");
    expected = [ "name exceeds 64 characters" ];
  };
  testPiRejectsDescription1025 = {
    expr = piWarn "x" (mkParsed "x" desc1025);
    expected = [ "description exceeds 1024 characters" ];
  };
  testPiFallsBackToDirName = {
    # pi uses the parent directory name when frontmatter omits `name`
    # (skills.ts: `const name = frontmatter.name || parentDirName`), so a
    # nameless SKILL.md in a well-named directory is clean for pi even
    # though validateSkillMd rejects it.
    expr = piWarn "good-skill" (fm.parse "---\ndescription: y\n---\nbody");
    expected = [ ];
  };
  testPiIsMorePermissiveThanAgentSkills = {
    # `--leading-hyphen` passes pi's ^[a-z0-9-]+$ but fails agent-skills'
    # stricter [a-z0-9]+(-[a-z0-9]+)* — proof the containment runs one way.
    expr = {
      pi = piWarn "-x" (fm.parse "---\nname: -x\ndescription: y\n---\nbody") == [ ];
      agentSkills = tryValidate {
        dirName = "-x";
        parsed = fm.parse "---\nname: -x\ndescription: y\n---\nbody";
      };
    };
    expected = {
      pi = true;
      agentSkills = false;
    };
  };
  testAgentSkillsAcceptanceImpliesPiClean = {
    expr = lib.all (p: piWarn (p.fields.name or "x") p == [ ]) acceptedSamples;
    expected = true;
  };
}
