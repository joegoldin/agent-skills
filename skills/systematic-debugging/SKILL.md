---
name: systematic-debugging
description: Root-cause method for bugs that resist a first fix. Use when a fix has already failed, the cause is unclear, or the failure spans several components.
---

# Systematic Debugging

Find the cause before changing code. A fix for a symptom tends to move the
bug, and each guess that half-works makes the next one harder to read.

## 1. Find where it breaks

- Read the error in full: the stack trace, line numbers, codes. It often names
  the cause.
- Reproduce it reliably, and know the exact steps. If it won't reproduce,
  gather more data rather than guessing.
- Check what changed: recent commits, dependencies, configuration, the
  environment.
- When the failure crosses components (CI to build to signing, API to service
  to database), instrument each boundary once and run it, so the evidence shows
  which layer goes wrong before you look inside any of them:

  ```bash
  # Layer 1: workflow
  echo "IDENTITY: ${IDENTITY:+set}${IDENTITY:-unset}"
  # Layer 2: build script
  env | grep IDENTITY || echo "IDENTITY not in environment"
  # Layer 3: signing script
  security list-keychains
  security find-identity -v
  # Layer 4: the step that fails
  codesign --sign "$IDENTITY" --verbose=4 "$APP"
  ```

- When the bad value surfaces deep in a call stack, trace it backwards to where
  it was first produced and fix it there; root-cause-tracing.md walks through
  this.

## 2. Compare with something that works

Find working code that does something similar, or the reference
implementation of the pattern, and read it whole. List every difference
between working and broken, including the ones that look irrelevant, and the
dependencies and configuration each assumes.

## 3. Test one hypothesis at a time

State it: "X is the cause because Y". Make the smallest change that would
confirm or refute it, one variable at a time. If it is wrong, form a new
hypothesis from what you learned instead of stacking another change on top.
When you don't understand something, say so and find out.

## 4. Fix the cause

Write a failing test that reproduces the bug (test-driven-development covers
this), make one change aimed at the cause, and confirm the test and its
neighbours pass and the original symptom is gone.

If the fix fails, go back to step 1 with what it taught you. After three
failed fixes, stop fixing and question the design: when each fix exposes a new
problem somewhere else, or needs a large refactor to land, the pattern itself
is likely wrong. Raise that with the user before a fourth attempt.

## When there is no root cause in the code

Some failures really are environmental, timing-dependent or external. Say what
you checked, handle the condition (a retry, a timeout, a clear error), and add
the logging that would catch it next time. This is rarer than it looks; most
"no root cause" findings are investigations that stopped early.

## Techniques in this directory

- root-cause-tracing.md: trace a bad value back through the call stack.
- defense-in-depth.md: add validation at several layers once the cause is known.
- condition-based-waiting.md (with condition-based-waiting-example.ts): replace
  arbitrary sleeps in tests with polling for the condition.
- find-polluter.sh: bisect which test leaves state that breaks another.
