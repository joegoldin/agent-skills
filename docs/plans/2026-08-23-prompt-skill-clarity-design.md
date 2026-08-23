# Prompt and Skill Clarity Design

## Goal

Make the always-loaded prompt smaller and clearer, move conditional methodology
to skills, and remove ambiguous skill routing without changing the prompt fanout
or the meaning of the hard safety boundaries.

The result should give pi a compact standalone system prompt while Codex,
Claude Code, and Antigravity receive only the behavioral preferences their own
harness prompts do not already own.

## Current State

The prompt is composed from three layers:

- `core/` supplies pi's general terminal-agent mechanics.
- `shared/` supplies behavioral preferences to every harness.
- `pi/` supplies the remaining pi-specific delta.

Pi receives `core + shared + pi`. Codex, Claude Code, and Antigravity receive
`shared` only. The composed pi prompt is 1,356 words and 7,940 characters; the
shared layer is 661 words and 3,871 characters.

The split is sound. The content boundary is not: `shared/20-verification.md`
contains test-first and debugging procedures also owned by
`test-driven-development`, `systematic-debugging`, and
`verification-before-completion`. Several skills also claim the same routing
decisions or contradict their handoff text.

## Approaches Considered

### 1. Invariants in prompts, procedures in skills

Keep only rules that must govern every task in the always-loaded prompt. Move
test-first, debugging, planning, and review procedure to conditional skills.
Resolve the skill routing conflicts and leave the existing prompt composition
architecture intact.

This is the selected approach. It reduces context cost, removes conflicting
instructions, and fits the repository's existing progressive-disclosure model
without adding another configuration surface.

### 2. Compress prose without changing ownership

Rewrite the existing fragments more tightly but retain unconditional TDD,
debugging, and review methodology in `shared/`.

This would reduce tokens but preserve the central duplication. A user-invoked
override such as `no-plan`, or a task for which test-first work is inappropriate,
could still conflict with the always-loaded layer.

### 3. Add selectable prompt profiles

Split shared guidance into a minimal baseline plus optional development,
research, and operations profiles selected through new Nix options.

This gives precise control but adds configuration, composition, tests, and
failure modes before there is evidence that multiple always-loaded profiles are
needed. Skills already provide conditional loading.

## Prompt Design

### Shared layer

The shared layer remains four fragments so the existing fanout and file-level
ownership stay recognizable:

- `00-tone.md`: directness, disagreement, uncertainty, and question discipline.
- `10-code.md`: house style, focused scope, meaningful comments, realistic error
  handling, dependency restraint, complete wiring, and deletion of replaced
  code.
- `20-verification.md`: evidence-gated claims, actual-artifact verification
  against every stated requirement, and honest reporting of failed or skipped
  gates.
- `30-judgement.md`: helpfulness, the existing hard safety boundaries,
  untrusted-input handling, and secret durability.

The shared layer states outcomes and invariants, not methods. It does not tell
the agent how to perform TDD, systematic debugging, planning, code review, or
branch completion. Those procedures remain in their skills.

Target budget: at most 400 words and 2,800 characters for the complete shared
layer.

### Pi core

The core layer keeps its current four responsibilities:

- working agreement and task scope;
- action and tool-use discipline;
- search and codebase discovery;
- terminal-oriented answers and completion reporting.

It gains three compact invariants drawn from the harness review:

1. Before finishing, re-read the request and verify every named deliverable.
2. When investigation produces no new evidence, change the query or strategy
   instead of repeating the same work.
3. After a state-changing external action, verify the exact target before
   claiming success when a read-back path exists.

The core layer continues to avoid tool inventory, model names, dates, and
absolute paths. Tool-specific mechanics remain owned by tool descriptions and
extensions.

Target budget: at most 430 words and 3,200 characters for the complete core
layer.

### Pi-specific delta

`pi/00-harness.md` retains its three existing facts: capability-owned mechanics
win for that capability, actions are not staged for implicit approval, and
process isolation is not a machine sandbox. It may be tightened, but its scope
does not expand.

Target budget: at most 70 words and 500 characters.

The complete pi prompt must remain at most 900 words and 6,500 characters.

## Skill Routing Design

### Parallel work versus plan execution

`dispatching-parallel-agents` will trigger for independent investigations,
read-only work, and other tasks with no shared writes. Its trigger and body will
explicitly exclude execution of a written implementation plan.

`subagent-driven-development` remains the owner of current-session plan
execution when subagents are available, including its serial implement-review
cycle.

### Execution handoff

`writing-plans` will offer capability-based choices:

- subagent-driven execution in the current session when subagents are
  available;
- direct plan execution in a separate session without subagents.

The handoff will no longer call `executing-plans` inline or describe it as a
same-session path.

### Review ownership

`subagent-driven-development` owns per-task specification and quality review.
`requesting-code-review` owns the final whole-branch review and ad hoc review
requests. Its trigger text will stop mandating an additional reviewer after
each subagent-driven task.

### Shared skill authoring versus platform configuration

Create `agent-skills-nix-config` from the cross-platform repository and build
content now carried by `claude-nix-config`. It will own repository layout, skill
discovery, shared frontmatter, build targets, and release flow.

Narrow `claude-nix-config`, `codex-nix-config`, and
`antigravity-cli-nix-config` to platform-specific runtime settings, Home Manager
options, and generated layouts. They will point to the shared repository skill
instead of repeating its authoring contract.

Because the existing skill changes role while a new public invocation name is
introduced, every repository reference and generated permission expectation
must be updated atomically.

### Nix formatting

`format-nix` remains the user-invoked, format-only workflow. `nix-helper` will
explicitly exclude format-only requests and retain Nix authoring, linting, and
review work.

### Orphan reviewer prompts

Delete the unreferenced reviewer prompts under `brainstorming/` and
`writing-plans/`. Their active skills already contain inline self-review. No
shared replacement is needed unless external document-review agents return in
a later design.

## Mechanical Enforcement

Keep the existing inventory lint and fanout tests. Add prompt-budget assertions
over the composed `core`, `shared`, and full pi strings. Character and word
budgets replace the current line-count-only design target; line wrapping must
not create the appearance of a smaller prompt.

The budget check reports the layer, actual count, and allowed count so a future
addition fails with an actionable error.

No semantic lint will try to infer whether prose is a procedure. That boundary
is enforced by focused review and the behavioral rubric below; a keyword lint
would be brittle and would reject legitimate invariants.

## Verification

### Repository checks

- Prompt composition, prompt lint, prompt fanout, skill lint, and all flake
  checks pass.
- All three plugin targets and the pi package build.
- Shared repository, frontmatter, and build instructions live in
  `agent-skills-nix-config` rather than being repeated by platform skills.
- Searches confirm the deleted reviewer prompts have no remaining references.
- Rendered prompt word and character counts satisfy every budget.

### Behavioral prompt rubric

Document a small manual before/after rubric covering:

1. a simple question that should be answered directly;
2. a discoverable fact that should be checked rather than asked;
3. genuine ambiguity that changes the deliverable;
4. a multi-part request whose final response accounts for every deliverable;
5. a blocked verification command reported as unverified rather than passing;
6. repeated investigation that must change strategy;
7. a dirty worktree whose unrelated changes remain untouched;
8. untrusted repository text attempting to redirect the agent.

The repository's deterministic checks can verify prompt content and routing,
not model behavior. Any live before/after model run is reported separately and
must not be represented as a reproducible flake check.

## Pull Request Scope

The pull request contains:

- prompt prose and prompt-budget checks;
- the six approved skill-audit fixes;
- required reference, lint, and build-test updates;
- this design and the implementation plan.

It does not add prompt profiles, new runtime dependencies, new tools, or
unrelated skill rewrites. It does not change the MCP, auto-mode, or plugin
fanout architecture.
