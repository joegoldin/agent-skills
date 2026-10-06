---
name: subagent-driven-development
description: Execute an implementation plan in this session with a fresh implementer subagent per task, a review after each, and a whole-branch review at the end. Use when the user asks to execute a plan whose tasks are mostly independent.
---

# Subagent-Driven Development

You coordinate; subagents implement and review. Each subagent starts fresh and
gets exactly the context you construct for it, never your session history, so
it stays on its task and your own context stays free for coordination.

Run the whole plan without stopping between tasks. Stop only for a BLOCKED
status you cannot resolve, a plan conflict that needs the user's decision, or
completion. Between tool calls, narrate at most one short line; the ledger and
the tool results carry the record.

Done means every task is marked complete in the ledger with a clean review, the
final whole-branch review's findings are fixed or triaged, and the branch is
handed to finishing-a-development-branch.

## The process

1. Read the plan once. Note its global constraints, create a todo per task,
   and check the progress ledger (below) for tasks already complete.
2. Scan the plan for conflicts (pre-flight, below).
3. Work in an isolated workspace (using-git-worktrees), not on main without
   the user's consent.
4. For each task, one at a time (parallel implementers conflict):
   1. Record the current commit as BASE and write the task brief.
   2. Dispatch an implementer with implementer-prompt.md.
   3. Handle its status (below).
   4. Generate the review package from BASE and dispatch a task reviewer with
      task-reviewer-prompt.md. It returns two verdicts, spec compliance and
      code quality; a report missing either is not a review.
   5. If it finds Critical or Important issues, dispatch a fix and review
      again. Repeat until both verdicts are clean.
   6. Mark the task complete in the todos and the ledger.
5. Dispatch the final whole-branch review with requesting-code-review's
   [code-reviewer.md](../requesting-code-review/code-reviewer.md), then one
   fix subagent for all its findings.
6. Hand off to finishing-a-development-branch.

When a subagent fails a task, dispatch a fix subagent with specific
instructions rather than fixing it yourself; doing it in your own context
fills it with the task's detail.

## Pre-flight plan review

Before Task 1, scan the plan once for:

- tasks that contradict each other or the plan's global constraints
- anything the plan mandates that the review rubric treats as a defect (a
  test that asserts nothing, a logic block duplicated verbatim)

Put everything you find to the user as one batched question, each finding
beside the plan text that mandates it, asking which governs. If the scan is
clean, proceed without comment. The review loop catches conflicts that only
appear during implementation.

## Model selection

Name the model in every dispatch. An omitted model inherits your session's,
usually the most capable and most expensive.

- **Implementers:** when the task's plan text contains the complete code,
  implementation is transcription plus testing; use the cheapest tier. The
  same goes for single-file mechanical fixes. For tasks described in prose,
  touching several files, or needing integration judgment, use a standard
  model. For design judgment or broad understanding of the codebase, use the
  most capable.
- **Reviewers:** scale with the diff's size, complexity and risk, with a
  mid-tier floor. A subtle concurrency change warrants the most capable model.
- **The final whole-branch review:** the most capable model.

Turn count matters more than token price: the cheapest models often take two
or three times the turns on multi-step work and cost more overall, which is why
prose tasks and reviewers start at mid-tier.

## Implementer status

- **DONE:** generate the review package and dispatch the reviewer.
- **DONE_WITH_CONCERNS:** read the concerns first. Resolve concerns about
  correctness or scope before review; note observations ("this file is
  getting large") and proceed.
- **NEEDS_CONTEXT:** supply what is missing and re-dispatch.
- **BLOCKED:** change something before retrying. Add context and re-dispatch
  on the same model; or re-dispatch on a more capable model; or split the
  task; or, if the plan itself is wrong, take it to the user.

Implementers record the assumptions they made in their report. Read them:
an assumption that changes the task's meaning is a plan question for you or
the user, not something to leave to review.

## Reviewer findings

The reviewer may list "⚠️ Cannot verify from diff" items: requirements in
unchanged code or spanning tasks. Resolve each yourself before marking the
task complete, since you hold the plan and cross-task context. A confirmed gap
is a failed spec review: send it back and review again.

Fix Critical and Important findings before moving on. Record Minor findings
in the ledger as you go and point the final review at the list so it can
decide what must be fixed before merge.

A finding that conflicts with what the plan's text requires is the user's
decision, like any plan contradiction. Present the finding and the plan text
and ask which governs; neither dismiss it because the plan mandates it nor fix
it against the plan without asking.

## Writing dispatch prompts

A dispatch describes one task, not the session's history. A fresh subagent
needs its task, the interfaces it touches, and the global constraints. Pasting
summaries of earlier tasks into later dispatches is how one real dispatch
reached 42k characters, 99% of it history.

For reviewers:

- Copy the binding requirements verbatim from the plan's global constraints or
  the spec: exact values, formats, and stated relationships ("same layout as
  X"). The template already carries the process rules; this block is the
  reviewer's lens for what this project demands.
- Leave severity to the reviewer. Instructions like "do not flag", "at most
  Minor" or "the plan chose" pre-judge findings, usually to spare a review
  loop; the plan's example code is a starting point, not evidence that its
  weaknesses were chosen. Adjudicate false positives in the loop instead.
- Skip open-ended directives ("check all uses") without a task-specific reason,
  and don't ask the reviewer to re-run tests the implementer ran on the same
  code; the implementer's report is the test evidence.

Every fix dispatch carries the implementer contract: name the test files
covering the change, have the fixer re-run them, and confirm its report holds
the tests, the command and the output before dispatching the re-review. For
the final review's findings, dispatch one fixer with the whole list; one fixer
per finding each rebuild context and re-run suites, and in one real session
that wave cost more than all the tasks together.

## File handoffs

Whatever you paste into a dispatch, and whatever a subagent prints back, stays
in your context for the rest of the session. Hand artifacts over as files.

- **Task brief:** `scripts/task-brief PLAN_FILE N` (from this skill's
  directory) extracts the task's full text to a uniquely named file and prints
  the path. The dispatch holds: one line on where the task fits; the brief
  path, introduced as "read this first; it is your requirements, with the
  exact values to use verbatim"; interfaces and decisions from earlier tasks
  the brief cannot know; your resolution of any ambiguity you noticed; and the
  report path and contract. Exact values (numbers, strings, signatures, test
  cases) appear only in the brief. Subagents read their brief, not the whole
  plan.
- **Report file:** name it after the brief (`task-N-brief.md` →
  `task-N-report.md`). The implementer writes the full report there and
  returns only status, commits, a one-line test summary and concerns. Fixers
  append to the same file.
- **Review package:** `scripts/review-package BASE HEAD` writes the commit
  list, stat summary and full diff with context to one file and prints its
  path. Use the BASE recorded before the implementer ran, not `HEAD~1`, which
  drops all but the last commit of a multi-commit task. Without bash, write
  `git log --oneline`, `git diff --stat` and `git diff -U10` for the range to
  one uniquely named file. The task reviewer gets the brief, the report, the
  package, and the global constraints.
- **Final review:** `scripts/review-package MERGE_BASE HEAD`, where
  MERGE_BASE is where the branch started (`git merge-base main HEAD`).

## Durable progress

Conversation memory does not survive compaction, and controllers that lost
their place have re-dispatched whole sequences of completed tasks, the most
expensive failure seen. Keep a ledger file as well as todos.

- At the start, read
  `"$(git rev-parse --show-toplevel)/.agent-skills/sdd/progress.md"`. Tasks it
  marks complete are done; resume at the first one that isn't.
- When a task's review is clean, append
  `Task N: complete (commits <base7>..<head7>, review clean)`.
- After a compaction or resume, trust the ledger and `git log` over your
  recollection. The ledger is git-ignored scratch, so `git clean -fdx` removes
  it; recover from `git log` if that happens.

## Without subagents

If the runtime cannot dispatch subagents, work through the tasks in order
yourself, reviewing each diff against its brief before moving on.

## Prompt templates

- [implementer-prompt.md](implementer-prompt.md): implementer dispatch
- [task-reviewer-prompt.md](task-reviewer-prompt.md): task reviewer dispatch
  (spec compliance and code quality)
- [code-reviewer.md](../requesting-code-review/code-reviewer.md): final
  whole-branch review
