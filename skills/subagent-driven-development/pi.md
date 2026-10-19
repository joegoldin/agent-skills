# Executing a plan on Pi

Load the installed pi-subagents skill when delegation is authorized. Its current
API, topology preflight, isolation and acceptance rules govern dispatch; do not
copy a second scheduler into this skill or enable delegation just to inspect it.

Use a bounded direct subagent call for one task. For coordinated lanes, use one
native workflow script: `runs.all` for independent work and `runs.run` for
prerequisite stages. Follow pi-subagents' required workflow launch syntax. Avoid
an all-tasks barrier when an unrelated lane can proceed on its own prerequisites.

Before writers start, record the native lane board: decision, repo/cwd, exclusive
files or contract, isolation path, authority, next gate, handoff and why the lane
is independent. Multiple independently testable components need component owners
and a later integration-only owner. One tightly coupled component can stay one
writer; record why splitting would create overlap rather than useful parallelism.

Use managed worktree isolation where the runtime supports the repository. For jj,
use a jj workspace with an explicit cwd when managed Git worktrees are unsuitable;
consult using-git-worktrees and jujutsu before launch. Resolve this before starting
a writer, not as an unapproved fallback after an isolation failure. Keep Pi
extension workspaces outside auto-discovered extension directories.

Each task packet carries its contract, allowed actions, stop conditions, focused
validation and required fresh read-only review. Use native artifact output for
large reports and keep paths and run IDs in `.agent-skills/sdd/`. A native receipt
is evidence, not acceptance; the parent checks it. A review may satisfy both the
native gate and the skill's task review when it covers both spec and quality.

Keep the parent's native todos current. While children run, do safe independent
work. If none remains, yield: ordinary async children notify the session when they
finish or need attention. Do not poll or call `bg_wait` merely to wait for them.
Use the background-task tools for long checks that the parent owns; their native
completion notifications carry the result. Do not run tests in a workspace while
another writer changes the source being verified.

Resume the known writer for accepted fixes when supported; keep the reviewer
fresh and read-only. Before retrying or replacing a run, establish who still owns
its workspace. Preserve infrastructure failures, partial diffs and run state, and
follow pi-subagents' recovery protocol rather than launching a competing writer.

Model and tool selection belong to the runtime profile and bounded launch. The
role templates are task content, not Claude-shaped calls to paste into Pi.
