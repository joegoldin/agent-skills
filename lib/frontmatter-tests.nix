# Eval-time unit tests for lib/frontmatter.nix. Returns the list of failed
# tests from lib.debug.runTests — empty list means all pass.
{ lib }:
let
  fm = import ./frontmatter.nix { inherit lib; };
  sample = ''
    ---
    name: my-skill
    description: Use when testing the parser
    allowed-tools: Bash(git:*) Read
    context: fork
    ---

    # Body

    ---

    More body after a horizontal rule.
  '';
  commaSample = ''
    ---
    name: comma
    description: "Has: a colon"
    allowed-tools: Bash(sem diff:*), Bash(sem impact:*)
    ---
    body
  '';
  blockSample = ''
    ---
    name: block
    description: Block list tools
    allowed-tools:
      - Bash(git:*)
      - Read
    metadata:
      author: joe
    ---
    body
  '';
in
lib.debug.runTests {
  testName = {
    expr = (fm.parse sample).fields.name;
    expected = "my-skill";
  };
  testKeysInOrder = {
    expr = (fm.parse sample).keys;
    expected = [
      "name"
      "description"
      "allowed-tools"
      "context"
    ];
  };
  testSpaceSeparatedTools = {
    expr = fm.parseToolList (fm.parse sample) "allowed-tools";
    expected = [
      "Bash(git:*)"
      "Read"
    ];
  };
  testBodyKeepsHorizontalRule = {
    expr =
      lib.hasInfix "More body after a horizontal rule." (fm.parse sample).body
      && lib.hasInfix "---" (fm.parse sample).body;
    expected = true;
  };
  testCommaSeparatedTools = {
    expr = fm.parseToolList (fm.parse commaSample) "allowed-tools";
    expected = [
      "Bash(sem diff:*)"
      "Bash(sem impact:*)"
    ];
  };
  testQuotedDescriptionUnwrapped = {
    expr = (fm.parse commaSample).fields.description;
    expected = "Has: a colon";
  };
  testBlockListTools = {
    expr = fm.parseToolList (fm.parse blockSample) "allowed-tools";
    expected = [
      "Bash(git:*)"
      "Read"
    ];
  };
  testNestedMapIgnored = {
    # metadata's nested "author: joe" line must not become a top-level key
    expr = builtins.elem "author" (fm.parse blockSample).keys;
    expected = false;
  };
  testMissingToolsIsEmpty = {
    expr = fm.parseToolList (fm.parse "---\nname: x\ndescription: y\n---\nbody") "allowed-tools";
    expected = [ ];
  };
  testMissingFrontmatterThrows = {
    expr = (builtins.tryEval (fm.parse "# no frontmatter here")).success;
    expected = false;
  };
  testUnterminatedFrontmatterThrows = {
    expr = (builtins.tryEval (fm.parse "---\nname: x\nno closing marker")).success;
    expected = false;
  };
}
