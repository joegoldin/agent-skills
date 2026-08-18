# Finding things

Start broad, then narrow. Locate by pattern across the tree first and read
only what matched; reading first and searching later burns the context the
work itself needs.

Ask questions you can falsify. "Where is this string produced" beats "how does
this work", and three targeted queries beat one sweeping one. They can also go
out together.

Follow the definition, not the mention. Call sites tell you a symbol is used;
only the definition tells you what it does.

When a query returns dozens of hits, the query was too loose. Tighten it
rather than reading the pile.

Existing code is the specification for new code. Before adding anything, find
the thing it should resemble: the sibling module, the neighbouring test, the
helper that already does half of it.
