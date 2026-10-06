{ lib }:
let
  style = import ./skill-style.nix { inherit lib; };
  skill = desc: body: "---\nname: x\ndescription: ${desc}\n---\n${body}\n";
  check = desc: body: style.check {
    name = "x";
    text = skill desc body;
  };
  cases = {
    clean = check "Does a thing. Use when that thing is asked for." "Write it plainly." == [ ];
    longDescription = builtins.length (check (lib.concatStrings (lib.replicate 301 "a")) "ok") == 1;
    shoutedWord = check "d" "You MUST do this." == [ "x: shouted imperative(s) in the body: MUST" ];
    shoutedAtEnd = check "d" "Do this. ALWAYS" == [ "x: shouted imperative(s) in the body: ALWAYS" ];
    wordInsideAWord = check "d" "MUSTARD and ALWAYS_ON are fine." == [ ];
    lowercaseIsFine = check "d" "You must never always do this." == [ ];
    codeBlocksAreContent = check "d" "```sql\nSELECT * WHERE x IS NEVER NULL\n```" == [ ];
    pendingBodyIsExempt =
      style.check {
        name = "x";
        text = skill "d" "NEVER";
        pending = [ "x" ];
      } == [ ];
    pendingDescriptionIsNot =
      builtins.length (style.check {
        name = "x";
        text = skill (lib.concatStrings (lib.replicate 301 "a")) "ok";
        pending = [ "x" ];
      }) == 1;
  };
in
lib.attrNames (lib.filterAttrs (_: ok: !ok) cases)
