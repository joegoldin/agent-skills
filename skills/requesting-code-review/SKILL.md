---
name: requesting-code-review
description: Use when a feature or branch is ready for independent review, before integration, or when an ad-hoc change needs a fresh technical assessment
---

# Requesting Code Review

Dispatch a reviewer with the requirements and exact change range, not the
authoring session's history.

## When to Request Review

Request review:

- When a feature or branch is complete
- Before integration or merge
- When an ad-hoc change needs an independent assessment
- When stuck and a fresh technical reading would help

`subagent-driven-development` owns its task-scoped spec and quality gates. Do
not add another general review after each task; use this skill for that
workflow's final whole-branch review.

## How to Request

1. Resolve the base and head commits for the review range.
2. Dispatch a reviewer using [code-reviewer.md](code-reviewer.md).
3. Provide:
   - A concise description of the change
   - The plan or requirements it must satisfy
   - The base and head commit IDs
4. Evaluate the findings against the code and tests.

Fix critical issues immediately and important issues before integration. If a
finding is wrong, push back with technical evidence.

## Red Flags

- Omitting requirements and asking for a generic review
- Reviewing an arbitrary diff range
- Ignoring critical or important findings
- Accepting feedback without checking its premise
- Treating the final branch review as a replacement for task-scoped gates

See [code-reviewer.md](code-reviewer.md) for the reviewer prompt.
