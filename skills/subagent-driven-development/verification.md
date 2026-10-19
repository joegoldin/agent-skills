# Reusing verification evidence

A test result covers a source state and an environment, not a task number or a
branch name. Record it once, then let later reviewers and finishing steps use it
when those inputs still match. This is a portable record, not a test cache.

Keep one record per check and attempt with its task report:

```text
Check: classifier integration
Source: repo/workspace; immutable commit or saved working-tree snapshot
Inputs: tracked, staged and untracked task files; dependency lock/config state
Environment: relevant runtime/toolchain versions and non-secret settings
Command: exact command, flags and cwd
Timing: start/end; source unchanged throughout the run
Result: exit status; passed/failed/skipped counts or the tool's actual summary
Evidence: log path and relevant output
Coverage: requirements checked; omissions and remaining gates
```

A clean Git commit or immutable jj commit ID identifies versioned content. For
Git work with pending edits, retain the base revision, binary diff including staged
and unstaged changes, and a content manifest or snapshot of untracked inputs.
For jj, resolve `@` to its immutable commit ID after snapshotting; a change ID or
bookmark alone can later name different content. Ignored inputs that affect the
check, such as local configuration or generated dependencies, also need identity.
Never put credentials or secret environment values in a record.

Stop concurrent source writes during verification. Confirm source and relevant
inputs are unchanged at the end. If a dirty snapshot or environment cannot be
identified reliably, report that the check ran but do not reuse it as evidence for
a later source state. A log path or worker's claim without the actual result is
not enough. Missing logs, timeouts, blocked checks and skipped required tests are
unverified, not passing.

Reuse an existing successful result only when its source, inputs, environment
and coverage match the current gate. Do not rerun merely because a different agent
is now reviewing or finishing the work. If code, dependencies, configuration or
integration changes, rerun affected checks; if the affected scope is uncertain,
run the required broader gate. Reusing a component result never substitutes for
checking its real integration with another component.

The implementer runs focused checks while iterating. The integration owner runs
the required broad suite on the combined result. Fixes get new records; retain
failed attempts for diagnosis rather than overwriting them. Reviewers inspect
valid evidence, then request or run checks for specific uncovered risks. After a
merge or rebase, compare inputs again before claiming earlier results still apply.
