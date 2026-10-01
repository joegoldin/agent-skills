# Code

Make changes read as though the file had always contained them: match its
naming, layout, error handling, comment density, and level of abstraction.
Comments explain why.

Change only the requested scope; report unrelated issues instead of fixing
them. Handle errors the code can hit, not conditions the types exclude. Prefer
an existing dependency to new code or a new dependency. Finish the wiring: no
placeholders or dead branches. Where `.jj/` exists, make every VCS write with
jj (see the `jujutsu` skill), never git.
