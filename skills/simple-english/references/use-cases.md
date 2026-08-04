# Use cases beyond documentation

STE was built for aircraft maintenance manuals. The properties transfer to any text where a misread has a cost: one meaning per word, short sentences, conditions before commands. By the end of Issue 8, most registered STE users worked outside aerospace and defense.

Each case names the mode, the Vale profile, and the adaptations.

## Error messages and CLI output

Mode: procedural. Command: `vale-skill simple-english:procedural`.

This is the highest-value target. An error message is a 2 a.m. instruction to a stressed reader.

Pattern: state what happened in the simple past, state the cause if you know it, then give the command or the condition that fixes it.

> **Before:** Oops! Something went wrong while attempting to establish a connection. Please ensure your credentials are properly configured and try again.
> **After:** Connection to the database failed. The password for user `app` was not correct. Set `DB_PASSWORD` and connect again.

No apology, no "Please ensure", no filler. The reader wants the fix.

## Runbooks and standard operating procedures

Mode: procedural, leaning strict. Command: `vale-skill simple-english:procedural`.

This is STE's home ground. An on-call runbook is a maintenance manual.

- Every step imperative. One instruction per step. Conditions first.
- Warnings before the step: command first, risk second.
- Hold the 20-word limit. An operator under pager stress reads each sentence once.

## Incident reports and postmortems

Mode: descriptive. Command: `vale-skill simple-english`.

Simple past only. A timeline in the present perfect ("we have identified...") hides when things happened.

> **Before:** We have identified an issue that may have impacted some users' ability to access the service.
> **After:** Between 14:02 and 14:31 UTC, 12% of requests failed. A deploy at 14:00 removed the cache warmup step.

STE bans hedges. The report states what is known and says "unknown" for the rest. That reads as more honest, because it is.

## Commit messages and pull request descriptions

Mode: imperative subject, descriptive body. Command: `vale-skill simple-english`.

The convention already matches STE: an imperative subject line and plain past facts in the body. Apply the slop table and the 25-word limit to the body. Delete "this PR aims to".

## Release notes and API changelogs

Mode: descriptive. Command: `vale-skill simple-english`.

One entry, one change, one sentence where you can. A breaking change follows the warning pattern, command first:

> **Breaking:** Update your calls to `v2/users`. The `name` field is now `first_name` and `last_name`.

## Instructions for AI agents (system prompts, AGENTS.md, skills)

Mode: procedural. Command: `vale-skill simple-english:procedural`.

A system prompt is a procedure for a reader that cannot ask questions. That is the reader STE was designed for.

- One instruction per sentence keeps each rule quotable and hard to half-follow.
- One word, one meaning stops the model from reading "check", "verify", and "validate" as three operations.
- Conditions first. Models drop trailing conditions.
- No "should". A model reads "should" as optional. Write "must", or delete the rule.

## Support macros and status page updates

Mode: descriptive, 25-word limit. Command: `vale-skill simple-english`.

Non-native readers are the majority of many user bases. Cut the apology:

> **Before:** We sincerely apologize for any inconvenience this may have caused.
> **After:** The API was down for 18 minutes. Uploads made in this time were saved. They process today.

## UI copy and empty states

Mode: procedural, with hard length limits. Command: `vale-skill simple-english:procedural`.

Buttons and labels are technical names and are exempt. Body copy follows the rules: "No projects yet. Create a project to start." Nothing longer survives at this size anyway.

## Translation and localization preparation

Mode: strict. Command: `vale-skill simple-english:strict`.

This was STE's original purpose: readable English for non-native maintenance crews. It doubles as pre-editing for machine translation. One meaning per word plus complete grammar (articles, "that") removes most translation ambiguity. If your docs get localized, STE cuts both the error rate and the cost.

## Where STE does not fit

Marketing pages, launch posts, blog voice, brand writing. STE deletes persuasion on purpose. Write those in your own voice, then use STE for the docs the landing page links to.
