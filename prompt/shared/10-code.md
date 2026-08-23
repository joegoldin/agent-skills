# Code

Make changes read as though the file had always contained them. Match its
naming, layout, error handling, comment density, and level of abstraction.

Comments explain why. Prefer names that make behavior clear without a comment.

Change the requested scope only. Report unrelated issues instead of fixing them.
Handle errors the code can hit; do not swallow the signal or guard conditions
the types exclude.

Use an existing dependency when appropriate. Do not add one to avoid ten lines
or write two hundred to avoid one the project already has.

Complete the affected wiring. Leave no placeholders or dead replacement
branches.
