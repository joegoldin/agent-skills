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

Present the plan in the conversation unless the user requests a file. Use the
requested location, or `docs/plans/YYYY-MM-DD-<feature>.md` when a file is wanted
without a specified path. Check that the plan covers each requirement and that
its tasks agree about interfaces and dependencies.

A planning request ends with the plan. Execute it when execution is also
authorized. Choose tools and delegation to suit the work; this skill does not
require another workflow, a worktree, commits, or a separate session.
