{ lib }:
# The writing rules writing-skills teaches, as a build gate, so they hold
# without anyone remembering them.
#
# Descriptions are what every runtime shows the model for every skill on every
# turn, so their length is a standing cost and a long one usually means a
# trigger broader than the skill. Runtimes parse frontmatter as real YAML,
# where an unquoted ": " or " #" breaks the value and the skill silently drops
# out of the listing; the build's own parser is more forgiving and won't
# notice. Shouted imperatives are the style written to
# force compliance out of older models; current ones over-apply it.
let
  fm = import ./frontmatter.nix { inherit lib; };

  maxDescription = 300;
  shouted = [
    "MUST"
    "NEVER"
    "ALWAYS"
    "CRITICAL"
  ];

  # Code blocks quote commands and examples, where capitals are content.
  stripFences =
    text:
    let
      step =
        acc: line:
        if lib.hasPrefix "```" (lib.trim line) then
          acc // { inFence = !acc.inFence; }
        else if acc.inFence then
          acc
        else
          acc // { kept = acc.kept ++ [ line ]; };
    in
    lib.concatStringsSep "\n"
      (builtins.foldl' step {
        inFence = false;
        kept = [ ];
      } (lib.splitString "\n" text)).kept;

  # Whole words only: "MUSTARD" and "ALWAYS_ON" are not shouting.
  shoutedIn =
    text:
    lib.unique (
      lib.concatMap (
        m: if builtins.isList m then [ (builtins.elemAt m 1) ] else [ ]
      ) (builtins.split "(^|[^A-Za-z_])(${lib.concatStringsSep "|" shouted})([^A-Za-z_]|$)" (stripFences text))
    );
  # The description line as written, before any unquoting.
  rawDescription =
    text:
    let
      m = lib.findFirst (l: lib.hasPrefix "description:" l) null (lib.splitString "\n" text);
    in
    if m == null then "" else lib.trim (lib.removePrefix "description:" m);

  brokenPlainScalar =
    raw:
    !(lib.hasPrefix "\"" raw || lib.hasPrefix "'" raw)
    && (lib.hasInfix ": " raw || lib.hasSuffix ":" raw || lib.hasInfix " #" raw);
in
{
  inherit maxDescription shouted;

  # Problems with one skill's SKILL.md text. `pending` lists skills whose
  # rewrite has not landed yet; their bodies are exempt, their descriptions
  # are not.
  check =
    {
      name,
      text,
      pending ? [ ],
    }:
    let
      parsed = fm.parse text;
      desc = parsed.fields.description or "";
      words = if builtins.elem name pending then [ ] else shoutedIn parsed.body;
    in
    lib.optional (
      lib.stringLength desc > maxDescription
    ) "${name}: description is ${toString (lib.stringLength desc)} characters, over ${toString maxDescription}"
    ++ lib.optional (brokenPlainScalar (rawDescription text)) "${name}: unquoted description contains ': ' or ' #', which YAML rejects; reword or quote it"
    ++ lib.optional (words != [ ]) "${name}: shouted imperative(s) in the body: ${toString words}";
}
