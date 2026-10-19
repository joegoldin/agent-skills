---
name: writing-plans
description: Use only when the user asks for a written implementation plan or explicitly invokes this skill.
disable-model-invocation: true
argument-hint: "<task to plan>"
---

# Writing implementation plans

Planning is opt-in. Multiple steps or complete requirements do not trigger
this workflow. Use an existing plan directly when asked to execute it.

Inspect the code and requirements before proposing tasks. Follow existing
architecture and identify dependencies, open decisions, and material risks.
Ask only for missing information that changes the result.

A useful plan contains:

- The intended result and scope.
- The approach and any important tradeoffs.
- Tasks in dependency order, each naming the affected files, behavior to
  change, and how to verify it.
- Constraints and unresolved decisions that affect execution.

Size tasks around independently verifiable outcomes. Include exact commands
and interfaces where known. Include code only when needed to explain a tricky
change; do not prewrite the implementation or invent line numbers. Mark
uncertainty explicitly rather than disguising it as a concrete step.

For work that will be split between workers, give each task a compact contract:
exclusive files, prerequisites, the interface it produces, focused verification,
and the owner/check for integration. Include representative inputs and outcomes
where they settle an interface. Keep genuinely dependent tasks ordered; a stub
can enable local testing but does not remove the real integration gate.

```text
Task 2: Parse retry hints
Owns: retry-hints.ts, retry-hints.test.ts
Needs: agreed parseRetryHint(value, now) interface
Produces: delay in milliseconds, or no usable hint
Verify: seconds, HTTP date, malformed value, excessive delay
Integration: classifier owner checks cancellation and retry budget
```

These fields help execution partition ownership; they do not authorize delegation
or require parallel work. Small serial tasks need no extra contract ceremony.

Present the plan in the conversation unless the user requests a file. Use the
requested location, or `docs/plans/YYYY-MM-DD-<feature>.md` when a file is wanted
without a specified path. Check that the plan covers each requirement and that
its tasks agree about interfaces and dependencies.

A planning request ends with the plan. Execute it when execution is also
authorized. Choose tools and delegation to suit the work; this skill does not
require another workflow, a worktree, commits, or a separate session.
