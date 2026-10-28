---
name: subagent-driven-development
description: Coordinate implementation and review of an existing plan. Use when the user asks to execute a plan whose tasks are mostly independent.
---

# Subagent-Driven Development

Keep the plan's decisions and acceptance with the parent. Give each worker a
bounded task and enough context to finish it without the session history.
Delegation needs authorization from the user or applicable project instructions;
an implementation plan alone does not grant it. Without that authorization,
work directly. For small serial tasks, keep a short progress note and the
commands and results needed to explain the handoff.

On Pi, read [pi.md](pi.md) before dispatching. On other harnesses, use their
native agent and isolation facilities; the templates below describe roles,
not tool-call syntax. A skill does not authorize commits or publication.

## Small serial tasks

Implement the existing plan directly, review the diff, and run the focused
checks the change needs. Keep progress and results in the session. If the
project requires independent review or other gates, satisfy those before
integration. The contracts and file-based handoffs below are for delegated or
resumable work.

## Delegated or resumable work

1. Read the plan and existing progress. Check for contradictory requirements
   and shared interfaces that do not agree. Resolve routine details yourself;
   ask about a decision that changes the intended result.
2. Identify independently testable components and actual dependencies. Record
   each task's contract (below), workspace, owner, next gate and handoff path.
   Keep tightly coupled work together rather than manufacturing parallelism.
3. Run ready tasks. Concurrent writers get distinct isolated workspaces and
   exclusive file ownership. Overlapping work is serial; tests that generate
   files are writers too. Never put concurrent writers in one checkout, even
   with disjoint files.
4. Handle each result as it arrives. Validate its evidence, review it against
   the brief, and resolve blocking findings. Unrelated tasks can keep moving;
   a dependent task starts only when its prerequisite contract and required
   review are satisfied.
5. Once component handoffs are ready, give one integration owner the combined
   result. Check the real component interfaces and run the required integration
   gates. Passing against stubs is not integration evidence.
6. For delegated work, obtain a fresh whole-change review. For direct work,
   review the integrated diff yourself and state that independent review was
   not performed. Fix or explicitly disposition findings, verify the resulting
   source state, and record the final handoff.
   Use finishing-a-development-branch when integration or publication is wanted;
   otherwise leave the verified work in place.

Done means every task has accepted evidence and the required review, the
integrated result passes its gates, and remaining concerns have an explicit
resolution. A child reporting DONE is a candidate, not acceptance. A blocked
lane need not stop independent work; record what will unblock it.

## Task contracts

For each delegated task, include:

- **Owns:** files it may change, exact workspace, and allowed actions.
- **Needs:** prerequisite tasks and interfaces, including exact types, formats,
  values and representative examples where they matter.
- **Produces:** independently testable outcome and interface promised to consumers.
- **Verify:** focused commands, relevant edge cases and required review.
- **Integration:** who checks the real connection between components and how.
- **Handoff:** report path, source state, unresolved decisions and stop conditions.

Copy binding requirements verbatim. Describe interface behavior, not a prewritten
implementation. If a task discovers a necessary edit outside its ownership, it
reports the needed change; the parent reallocates ownership before work proceeds.
Record the task contracts alongside the existing plan or briefs, not in a second
planning system. Small serial tasks need only the fields that affect execution.

## Models and reviews

Choose models by task complexity and risk using the runtime's configured roles
or explicit overrides. Mechanical changes can use a cheaper model; integration
and subtle concurrency changes need stronger reasoning. Keep provider names and
model IDs out of portable task contracts.

A task review checks both spec compliance and code quality. Related mechanical
changes can share a review unit when the harness's acceptance rules permit it.
Review risky interfaces before consumers rely on them. Do not add a duplicate
review when a native acceptance gate already covers the same scope and evidence.
The final review checks the integrated result, not merely the sum of task reports.

Use requesting-code-review for the final review and receiving-code-review when
adjudicating findings. Critical and Important findings block acceptance of the
affected work when they identify a concrete failure or unmet requirement.
Optional coverage, cleanup and design preferences remain advisory. Record Minor
findings for the final review. A plan-mandated defect is still a finding; ask
about a conflict that requires changing the user's intent.

A review package is a starting point, not a restriction on investigation. Give
reviewers the exact workspace and source state. They may inspect surrounding code
for concrete risks and request missing evidence. Leave severity to the reviewer;
do not pre-grade findings to avoid a fix cycle.

## Results and fixes

- **DONE:** check the report and start the required review.
- **DONE_WITH_CONCERNS:** resolve correctness and scope concerns before acceptance.
- **NEEDS_CONTEXT:** supply the missing information and resume the worker if supported.
- **BLOCKED:** record the cause, evidence and next action before retrying.

Read the worker's assumptions. An assumption that changes the task's meaning
needs a decision, not an automatic pass to review. Keep fixes with the lane's
sole writer where possible. The parent can own small integration fixes after
other writers have stopped; it must not compete with an active writer.

After repeated failure of the same gate, preserve the attempted fixes and logs
and diagnose the cause before another attempt. A tooling failure remains a
blocker; do not silently change execution protocols to get around it.

## Artifacts and verification

The contracts and artifacts below support delegated or resumable work. Small
serial tasks need only relevant progress, decisions, and check results.

Use [verification.md](verification.md) to record test evidence and decide whether
an earlier run still covers the current code. Focused tests belong with each
component; broad tests belong at the integration gate unless the task's risk
requires them sooner. A fix invalidates evidence for the affected source state.

Keep handoffs as files rather than pasting reports through the parent context:

- `scripts/task-brief PLAN_FILE N [OUTFILE]` extracts a task's full text. Dispatch
  its path, the ownership contract, relevant interfaces, constraints and report
  path. The worker reads the brief rather than the entire plan.
- Name reports after tasks and attempts. Include changed files, source state,
  validation, assumptions, concerns and the next action. Return a short status
  and artifact paths to the parent.
- `scripts/review-package BASE HEAD [OUTFILE]` writes the net diff and history.
  Record BASE before implementation, not `HEAD~1`. In jj, pass immutable commit
  IDs or `@` for the current working copy; the package resolves endpoints to
  commit IDs. In Git, both endpoints are commits. For uncommitted Git work,
  include the base-to-working-tree diff and all untracked task files in a manual
  package; do not create a commit merely to use this helper.
- The final package starts at the recorded whole-change base, not the last
  task's base. Review the actual integrated result.

`scripts/sdd-workspace` resolves the local Git or jj workspace and creates its
ignored `.agent-skills/sdd/` directory. Put a run's briefs, reports, verification
records and `progress.md` under a distinct run subdirectory there; pass explicit
output paths to the helpers. The parent owns the progress file. Workers write
only their assigned reports, in their own workspace or native artifact storage.

Record run/task IDs, workspace and ownership, native child IDs, immutable source
IDs or dirty snapshots, gates, evidence paths and next action. On resume, reconcile
this record with the actual source and native run state before redispatching.
Do not trust an old task number or a clean review of a different revision.
Native task state drives execution; this ledger is the portable handoff, not a
second scheduler. Preserve artifacts and workspaces while a live run or unresolved
gate still needs them.

## Templates

- [implementer-prompt.md](implementer-prompt.md): component writer
- [task-reviewer-prompt.md](task-reviewer-prompt.md): spec and quality reviewer
- [code-reviewer.md](../requesting-code-review/code-reviewer.md): whole-change review

Without native subagents, work directly with records sized to the task.
Report that independent review was unavailable; a self-review does not satisfy a
required fresh reviewer gate.
