# Pure-Nix parser for the SKILL.md / agents/*.md frontmatter subset the
# build system consumes (name, description, allowed-tools, tools). All other
# frontmatter fields pass through in the shipped file untouched — this
# parser only reads, it never rewrites.
#
# Supported value forms (single-line only):
#   key: plain scalar
#   key: "double-quoted scalar"   (\" and \\ escapes)
#   key: 'single-quoted scalar'
#   key: a b c                    (space-separated tool list)
#   key: a, b, c                  (comma-separated tool list)
#   key:                          (block list)
#     - a
#     - b
# Nested maps (e.g. metadata:) are tolerated and ignored: their indented
# lines are neither top-level keys nor list items of a consumed field.
{ lib }:
rec {
  # Strip surrounding quotes from a scalar and trim whitespace.
  unquote =
    raw:
    let
      s = lib.trim raw;
      dq = builtins.match "\"(.*)\"" s;
      sq = builtins.match "'(.*)'" s;
    in
    if dq != null then
      builtins.replaceStrings [ "\\\"" "\\\\" ] [ "\"" "\\" ] (builtins.head dq)
    else if sq != null then
      builtins.head sq
    else
      s;

  # parse :: string -> { fields; items; keys; body; }
  parse =
    text:
    let
      lines = lib.splitString "\n" text;
      hasFm = lines != [ ] && builtins.head lines == "---";
      rest = if hasFm then builtins.tail lines else [ ];
      endIdx = lib.lists.findFirstIndex (l: l == "---") null rest;
      fmLines = lib.sublist 0 endIdx rest;
      bodyLines = lib.drop (endIdx + 1) rest;
      keyMatch = l: builtins.match "([A-Za-z0-9_-]+):[[:space:]]*(.*)" l;
      itemMatch = l: builtins.match "[[:space:]]+-[[:space:]]+(.*)" l;
      folded =
        builtins.foldl'
          (
            acc: line:
            let
              m = keyMatch line;
              item = itemMatch line;
              key = builtins.head m;
            in
            if m != null then
              {
                fields = acc.fields // {
                  ${key} = unquote (lib.last m);
                };
                items = acc.items // {
                  ${key} = [ ];
                };
                current = key;
                keys = acc.keys ++ [ key ];
              }
            else if item != null && acc.current != null then
              acc
              // {
                items = acc.items // {
                  ${acc.current} = acc.items.${acc.current} ++ [ (unquote (builtins.head item)) ];
                };
              }
            else
              # Anything else (nested map lines, blank lines) ends any open
              # block list and is otherwise ignored.
              acc // { current = null; }
          )
          {
            fields = { };
            items = { };
            current = null;
            keys = [ ];
          }
          fmLines;
    in
    if !hasFm || endIdx == null then
      throw "agent-skills: file must start with a '---'-delimited YAML frontmatter block"
    else
      {
        inherit (folded) fields items keys;
        body = lib.concatStringsSep "\n" bodyLines;
      };

  parseFile = path: parse (builtins.readFile path);

  # Tool lists: block-list form wins, then comma-separated, then
  # space-separated. Entries containing spaces MUST use the comma or block
  # form (lint enforces this).
  parseToolList =
    parsed: key:
    let
      inline = parsed.fields.${key} or "";
      block = parsed.items.${key} or [ ];
    in
    if block != [ ] then
      block
    else if inline == "" then
      [ ]
    else if lib.hasInfix "," inline then
      map lib.trim (lib.splitString "," inline)
    else
      builtins.filter (t: t != "") (lib.splitString " " inline);
}
