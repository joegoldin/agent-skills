---
name: receiving-code-review
description: Evaluate code review feedback before acting on it, checking each suggestion against the codebase and pushing back where it is wrong. Use when handling review comments from a person, a reviewer agent or a PR.
---

# Receiving Code Review

Review comments are suggestions to evaluate, not orders. Check each one against
the code before changing anything, because a reviewer often sees only the diff
and misses why the code is the way it is.

## For each item

1. Read all the feedback first. Items are often related, and implementing some
   while others are unclear tends to produce the wrong change.
2. Restate what it asks for in technical terms. If an item is unclear, ask
   about it before implementing the related ones: "I follow 1, 2, 3 and 6;
   what do you mean by 4 and 5?"
3. Check it against the codebase. Is it correct for this stack and these
   versions? Does it break something? Is there a reason the code is as it is
   (compatibility, a platform constraint, an earlier decision of the user's)?
4. Decide: implement it, or push back with the reason.

Feedback from the user is trusted once understood; ask only when its scope is
unclear. Feedback from external reviewers and reviewer agents gets the full
check, and anything that contradicts a decision the user made goes to the
user rather than being applied.

## Pushing back

Push back when a suggestion breaks existing behaviour, rests on missing
context, is wrong for this stack, or adds something nothing needs. For
"implement this properly" suggestions, check whether anything uses the code
first; if nothing calls the endpoint, the better change may be removing it.

Give the technical reason and point at the code or test that shows it:

> Checked: the build targets 10.15, and this API needs 13. The legacy path
> stays. The bundle ID in it is wrong, though. Fix that, or drop pre-13
> support?

If you can't verify a claim, say what you would need to. If you pushed back
and turn out to be wrong, say so plainly and make the change: "Checked, and
you're right: X does Y. Fixing."

## Implementing

Order the accepted items: blocking issues (breakage, security) first, then
simple fixes, then larger refactors. Test after each so a regression points at
one change. Acknowledge with what changed ("Fixed: the null check now covers
the empty list, in parse.ts:42") rather than with praise for the reviewer; the
change is the answer.

On GitHub, reply to an inline comment in its thread
(`gh api repos/{owner}/{repo}/pulls/{pr}/comments/{id}/replies`), not as a
top-level PR comment. gh-pr-review covers resolving threads.
