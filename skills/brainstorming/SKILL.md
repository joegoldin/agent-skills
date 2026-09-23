---
name: brainstorming
description: Use only when the user asks to brainstorm, explore design alternatives, or explicitly invokes this skill.
disable-model-invocation: true
argument-hint: "<idea or design question>"
---

# Brainstorming

This is an opt-in design conversation. Ordinary feature requests and config
changes do not trigger it.

Inspect the relevant project context, then identify the decisions that remain
open. Ask one question at a time when the answer changes the design and cannot
be discovered. State reasonable assumptions.

Compare a few viable approaches, explaining their concrete costs and benefits.
Recommend one and describe the resulting behavior, boundaries, and validation
at a level of detail appropriate to the work.

Finish with the recommendation and any unresolved decisions. Write a design
document, create an implementation plan, or begin implementation only when
the user requests it. Existing authorization to implement still applies; this
skill adds no separate approval ceremony or commit requirement.

If a visual would clarify a design choice and the user wants one, see
`visual-companion.md` for the optional browser companion.
