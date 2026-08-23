# Layered system-prompt composition.
#
# A *layer* is a directory of numbered markdown fragments. A *prompt* is an
# ordered list of layers, concatenated with one blank line between fragments
# and exactly one trailing newline.
#
# Ordering is plain lexicographic over file names. That is only unambiguous
# because validateFragmentName forces a zero-padded two-digit prefix — without
# it "9-x.md" would sort after "10-y.md" and the prompt would silently
# reorder itself the tenth time someone added a fragment.
{ lib }:
let
  inherit (lib)
    concatStringsSep
    filterAttrs
    hasSuffix
    removeSuffix
    ;
in
rec {
  # NN-kebab-case.md. Enforced by checks.prompt-inventory over the real tree.
  validateFragmentName = name: builtins.match "[0-9][0-9]-[a-z][a-z0-9-]*\\.md" name != null;

  fragmentNames =
    dir:
    builtins.sort (a: b: a < b) (
      builtins.attrNames (filterAttrs (n: t: t == "regular" && hasSuffix ".md" n) (builtins.readDir dir))
    );

  # One trailing newline is stripped so joining never produces a triple
  # newline. Fragments are written with a trailing newline like every other
  # text file, so this is a normalisation, not a content decision.
  readFragment = dir: name: removeSuffix "\n" (builtins.readFile (dir + "/${name}"));

  readLayer = dir: concatStringsSep "\n\n" (map (readFragment dir) (fragmentNames dir));

  wordCount =
    text:
    builtins.length (
      builtins.filter (part: builtins.isString part && part != "") (builtins.split "[ \n\r\t]+" text)
    );

  # `extra` is user-supplied text appended after every layer. It goes last so
  # a local override reads as an amendment to the policy above it.
  mkPrompt =
    {
      layers,
      extra ? "",
    }:
    let
      parts = builtins.filter (s: s != "") ((map readLayer layers) ++ [ (removeSuffix "\n" extra) ]);
    in
    if parts == [ ] then "" else concatStringsSep "\n\n" parts + "\n";
}
