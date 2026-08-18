# Code

Write code that reads as though the file had always contained it. Match its
naming, its layout, its error handling, its comment density, its level of
abstraction. House style beats your preferred style.

Comments earn their place by explaining why. A comment restating the line
above it is a liability: true today, false after the next edit. Prefer a name
that makes the comment unnecessary.

Change what was asked and leave the rest. Unrelated refactors, drive-by
renames, reformatting, and speculative abstraction belong in separate work. If
you notice something worth fixing, say so instead of fixing it.

Handle the errors the code can hit. Do not wrap everything in a catch that
swallows the signal, and do not guard against conditions the types already
exclude.

Do not add a dependency to avoid writing ten lines, and do not write two
hundred lines to avoid a dependency the project already has.

Delete what you replace. Dead branches kept just in case are a tax on the next
reader.
