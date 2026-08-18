{ lib }:
let
  pl = import ./prompt-lint.nix { inherit lib; };
  skillNames = [
    "brainstorming"
    "sem"
    "writing-plans"
  ];
  hits = text: pl.lint { inherit skillNames text; };
  rules = text: map (v: v.rule) (hits text);
  terms = text: map (v: v.term) (hits text);
in
lib.debug.runTests {
  testEmptyTextPasses = {
    expr = rules "";
    expected = [ ];
  };
  testPolicyProsePasses = {
    # Every ambiguous tool word appears here as ordinary English.
    expr = rules "Read the error before retrying. Write code that reads like the surrounding file. Edit only what was asked.";
    expected = [ ];
  };
  testSkillNameCaught = {
    expr = rules "Start with brainstorming before you write code.";
    expected = [ "skill-name" ];
  };
  testSkillNameCaughtCaseInsensitively = {
    expr = terms "Invoke Writing-Plans first.";
    expected = [ "writing-plans" ];
  };
  testHyphenNeighbourIsNotAFalsePositive = {
    # "sem" is a skill; "semantic" and "sem-diff" are different tokens.
    expr = rules "Prefer semantic naming; sem-diff output is fine.";
    expected = [ ];
  };
  testUnambiguousToolNameCaught = {
    expr = terms "Call WebFetch when the answer is online.";
    expected = [ "WebFetch" ];
  };
  testPiExtensionApiNameCaught = {
    expr = terms "Guidance arrives through promptSnippet.";
    expected = [ "promptSnippet" ];
  };
  testAmbiguousToolPhraseCaught = {
    expr = terms "Use the Read tool rather than shelling out.";
    expected = [ "Read tool" ];
  };
  testAmbiguousToolPhrasePluralCaught = {
    expr = terms "The Bash tools are available.";
    expected = [ "Bash tools" ];
  };
  testLowercaseToolPhraseIsNotAFalsePositive = {
    # "the right tool" is prose, not inventory.
    expr = rules "Reach for the right tool and move on.";
    expected = [ ];
  };
  testIdentityTermCaught = {
    expr = terms "You are Claude, a coding agent.";
    expected = [ "claude" ];
  };
  testModelFamilyCaught = {
    expr = terms "Fall back to sonnet when the primary model is busy.";
    expected = [ "sonnet" ];
  };
  testHarnessNameCaught = {
    expr = terms "This guidance also applies under codex.";
    expected = [ "codex" ];
  };
  testIsoDateCaught = {
    expr = terms "Today is 2026-08-18.";
    expected = [ "2026-08-18" ];
  };
  testHomePathCaught = {
    expr = terms "Skills live under /home/someone/.agents/skills.";
    expected = [ "/home/" ];
  };
  testTildePathCaught = {
    expr = terms "Configuration lives at ~/.config.";
    expected = [ "~/" ];
  };
  testDuplicateTermReportedOnce = {
    expr = terms "Call WebFetch, then call WebFetch again.";
    expected = [ "WebFetch" ];
  };
  testMultipleRulesAllReported = {
    expr = rules "You are Claude; call WebFetch; start with brainstorming.";
    expected = [
      "skill-name"
      "tool-name"
      "identity"
    ];
  };
}
