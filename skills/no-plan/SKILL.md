# Skip the Plan — Just Do It

User-invoked skill that bypasses the heavy design/spec/plan workflow. Intent: short clarification, then execute.

## When to Use

**Only when the user explicitly invokes `/no-plan` (or `/agent-skills:no-plan`).**

Do NOT auto-trigger from natural-language phrasing like "just do it", "skip the plan", or because the user sounds impatient. Those are too easy to false-positive on, and silently bypassing the planning workflow without an explicit user signal is exactly the failure mode this skill must avoid.

## What `/no-plan` Overrides

Per `using-agent-skills`' priority order (User instructions > Skills > Defaults), `/no-plan` is a user instruction and **overrides the default mandates of**:

- **brainstorming** — no design proposal, no approval gates, no spec doc
- **writing-plans** — no plan doc
- **executing-plans** / **subagent-driven-development** — no plan-driven dispatch
- **test-driven-development** — skip the RED-GREEN-REFACTOR ritual (still write tests if they ARE the task)
- **systematic-debugging** — no formal hypothesis tree
- **requesting-code-review** — don't auto-request
- **finishing-a-development-branch** — don't auto-run the structured cleanup

## The Floor (Non-Negotiable Even Under `/no-plan`)

- **verification-before-completion** — run the verify command, see fresh output, *then* claim done. Skipping verification turns "fast" into "broken".
- **Domain skills as tools** — `nix-helper`, `git-hunk`, `obsidian-cli`, etc. are tools, not ceremony. Use them when they fit.
- **Risk confirmation for destructive actions** — see Escape Hatches below.

## How to Run a `/no-plan` Task

1. **Clarify briefly.** Up to **1-5** quick questions when there's genuine ambiguity. Prefer `AskUserQuestion` for concrete choices.
   - **Hard rule:** never make non-trivial assumptions silently. When in doubt, ask.
   - Don't burn questions on things clearly inferable from the request.

2. **Announce, then execute.** One short sentence describing the action (per the system prompt), brief updates at key moments, straight to implementation.

3. **No spec docs, no plan docs.** Use TodoWrite only if the task itself is genuinely multi-step.

4. **Verify before claiming done.** Run the verification command, see the output, then summarize.

5. **End-of-turn summary: 1-2 sentences.** What changed. What's next, if anything.

## Escape Hatches (Pause Briefly Even Under `/no-plan`)

Flag the risk in one sentence and confirm before proceeding when the request involves:

- **Destructive ops on shared state** — force-push to `main`/`master`, dropping DB tables, `rm -rf` outside cwd, deleting branches, modifying CI/CD secrets, overwriting uncommitted changes.
- **Obviously multi-day scope** — if `/no-plan` lands on a 3-week refactor, surface the mismatch in one sentence; defer to the user if they insist.
- **Security-sensitive changes** — auth flows, crypto, permission models. State the risk; ask before proceeding.

One sentence of friction, not a full design review.

## Red Flags

| Thought | Reality |
|---|---|
| "User said `/no-plan`, so I can skip verification too" | No. Verification is the floor. |
| "I'll just guess what they mean" | No. Ask 1-5 clarifying questions. |
| "I'll skip TDD AND skip writing tests entirely" | No. Skip the ceremony; if tests are part of the task, write them. |
| "I'll auto-trigger this when the user sounds impatient" | No. User-invoked via `/no-plan` only. |
| "Force-pushing main is fine, they said no-plan" | No. See Escape Hatches. |
| "The task is huge but they said `/no-plan`, so I just dive in" | No. Surface the scope mismatch in one sentence first. |
