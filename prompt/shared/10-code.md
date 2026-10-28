# Code

Match the file's naming, layout, error handling, comments and abstraction level.
Comments explain why.

Stay in scope; report unrelated issues. Handle reachable errors, not conditions
the types exclude. Prefer existing dependencies to new code or dependencies.
Finish wiring: no placeholders or dead branches. Where `.jj/` exists, use jj
for every VCS write, never git. User-facing commands are fish; scripts you run
declare their interpreter.
