{ lib }:
let
  prompt = import ./prompt.nix { inherit lib; };
  fixtures = ./prompt-test-fixtures;
in
lib.debug.runTests {
  testFragmentNamesSortedAndFiltered = {
    expr = prompt.fragmentNames (fixtures + "/layer-a");
    expected = [
      "00-first.md"
      "10-second.md"
    ];
  };
  testEmptyLayerIsEmptyString = {
    expr = prompt.readLayer (fixtures + "/layer-empty");
    expected = "";
  };
  testReadFragmentStripsExactlyOneTrailingNewline = {
    expr = prompt.readFragment (fixtures + "/layer-a") "00-first.md";
    expected = "# First\n\nAlpha.";
  };
  testReadLayerJoinsWithABlankLine = {
    expr = prompt.readLayer (fixtures + "/layer-a");
    expected = "# First\n\nAlpha.\n\n# Second\n\nBeta.";
  };
  testMkPromptKeepsLayerOrder = {
    expr = prompt.mkPrompt {
      layers = [
        (fixtures + "/layer-b")
        (fixtures + "/layer-a")
      ];
    };
    expected = "# Third\n\nGamma.\n\n# First\n\nAlpha.\n\n# Second\n\nBeta.\n";
  };
  testMkPromptSkipsEmptyLayers = {
    expr = prompt.mkPrompt {
      layers = [
        (fixtures + "/layer-empty")
        (fixtures + "/layer-b")
      ];
    };
    expected = "# Third\n\nGamma.\n";
  };
  testMkPromptAppendsExtraLast = {
    expr = prompt.mkPrompt {
      layers = [ (fixtures + "/layer-b") ];
      extra = "Extra line.\n";
    };
    expected = "# Third\n\nGamma.\n\nExtra line.\n";
  };
  testMkPromptOfNothingIsEmpty = {
    expr = prompt.mkPrompt { layers = [ (fixtures + "/layer-empty") ]; };
    expected = "";
  };
  testValidFragmentName = {
    expr = prompt.validateFragmentName "00-tone.md";
    expected = true;
  };
  testUnpaddedFragmentNameRejected = {
    # "9-x.md" would sort after "10-y.md" lexicographically — silently wrong.
    expr = prompt.validateFragmentName "9-tone.md";
    expected = false;
  };
  testUppercaseFragmentNameRejected = {
    expr = prompt.validateFragmentName "00-Tone.md";
    expected = false;
  };
  testNonMarkdownFragmentNameRejected = {
    expr = prompt.validateFragmentName "00-tone.txt";
    expected = false;
  };
}
