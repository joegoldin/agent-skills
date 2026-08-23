---
name: dispatching-parallel-agents
description: Use when two or more independent investigations or read-only tasks can run concurrently without shared writes or sequential dependencies
---

# Dispatching Parallel Agents

## Overview

Parallel agents gather independent evidence at the same time. Give each agent
one bounded question, only the context it needs, and an explicit read-only
scope.

**Core principle:** Parallelize independent inquiry, not shared implementation.

## When to Use

Use this skill when:

- Several unrelated failures need separate root-cause investigations
- Multiple documents, APIs, or subsystems need independent review
- Each result is useful without another agent's result
- Agents will not edit files or mutate shared state

Do not use it when:

- Agents would edit the same checkout or operate on shared resources
- One result determines the next task
- Failures may share a root cause
- A written implementation plan needs execution; use
  `subagent-driven-development` for that workflow

## Pattern

### 1. Split by question

Each task should have one falsifiable outcome, such as:

- Identify the root cause of failures in one test file
- Trace where one configuration value is produced
- Review one independent requirement against the current implementation

### 2. Write self-contained prompts

Include:

- The exact question and scope
- Relevant paths, errors, or requirements
- A read-only constraint
- The evidence and format to return

```text
Investigate the three failures in src/agents/abort.test.ts. Read the test and
implementation, identify the root cause, and cite the relevant symbols. Do not
edit files. Return the mechanism and the smallest justified fix.
```

### 3. Dispatch together

Start all independent agents before waiting for any one result. If a task must
wait for another result, it is not part of the parallel batch.

### 4. Synthesize

When agents return:

1. Check that each answer includes evidence
2. Reconcile conclusions that touch the same code or assumption
3. Decide the implementation order centrally
4. Verify the combined conclusion against the repository

## Common Mistakes

- **Parallel implementers in one checkout:** commits and edits are shared state.
- **One broad prompt:** split by independent question, not by arbitrary file.
- **Inherited session history:** supply the minimum relevant context explicitly.
- **Vague output:** ask for cited evidence, not “look into this.”
- **Blind integration:** an agent's summary is a lead until checked.
