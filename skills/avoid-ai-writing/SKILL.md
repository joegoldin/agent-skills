---
name: avoid-ai-writing
description: Audit and rewrite prose to remove AI writing patterns, with detect-only and edit-in-place modes. Use when asked to remove AI-isms or make writing sound less machine-written.
allowed-tools: Bash(avoid-ai-detect) Bash(avoid-ai-detect:*)
---

# Edit for a human voice

Read the passage for meaning first. Who is speaking, to whom, and about what? Keep facts, uncertainty, and the writer’s distinctive turns of phrase. A detector cannot tell you who wrote a sentence.

- **Detect:** Quote the words that caught your attention and explain their effect. Separate clear mistakes, such as leaked chatbot citations, from matters of taste. Leave the text alone.
- **Rewrite** (default): Return the revised text and a short account of the changes. Replace vague praise with facts already in the draft. Cut empty transitions; leave useful ones. Read the revision once more for lost details and newly repetitive phrasing.
- **Edit a file:** Change only the passages that need work. Leave quotations, code and attributed text intact. Re-read the edited file and report the locations changed rather than printing it back.

For a full audit, use the [pattern catalog](references/patterns.md), including severity and exceptions for examples that *quote* a pattern. For a requested voice or genre, consult the [audience and voice profiles](references/profiles.md). A recurring pattern matters more than an isolated word.

The optional detector catches literal patterns. Run it before editing and compare afterward; don't edit toward a score. Use the technical context for documentation:

```sh
avoid-ai-detect --context technical draft.md
```

Natural language or `--mode detect|rewrite|edit`, `--voice`, `--context`, and `--file` select the same options. If asked to iterate (`--iterate N`), stop after the first clean pass or two passes total.
