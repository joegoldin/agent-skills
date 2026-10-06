---
name: writing-skills
description: Write and revise agent skills so they load when they should and read well to current models. Use when creating or editing a skill, or changing its description.
---

# Writing Skills

A skill is reusable know-how an agent loads on demand: a technique, a pattern,
or a reference for a tool. It is not a record of how one problem was solved.

Write one when the know-how is not obvious, will be needed again, and cannot be
enforced mechanically instead. A rule a lint or a check can enforce belongs in
the lint; project conventions belong in the project's instructions file.

In the agent-skills Nix repository, `agent-skills-nix-config` owns packaging:
frontmatter fields, sidecars, subagents and the build. This skill owns writing.

## The description decides when the skill loads

Every runtime shows the model every skill's name and description, and nothing
else, until it chooses to load one. The description has two jobs: say what the
skill does, and name the narrowest situation that should select it.

```yaml
# Too broad: loads on every task that touches data
description: Create and validate Postgres schema migrations. Use when working with databases, queries, models, or persistence.

# What it does, then the situation that selects it
description: Create and validate Postgres schema migrations. Use when adding or changing a migration, or reviewing its rollout.
```

- One clause for what it does, one for when. Under 300 characters; the lint
  enforces the cap.
- Name the situation, not the domain. "Use when implementing any feature" makes
  a workflow run on everything.
- Leave the procedure to the body. A description that summarises the steps
  invites the model to follow the summary instead of reading the skill.
- Descriptions must not compete: two skills should never both claim the same
  request. Merge them, or give each a trigger the other lacks.
- Write in the third person; the text is injected into a system prompt.

Check a description change with the trigger eval (see testing.md) before and
after: it shows which skills a real session picks for a set of tasks.

## The body is guidance, not law

Current models follow instructions closely and carry ordinary diligence on
their own: they test, verify and stay in scope without being told. Text written
to force compliance out of older models now overconstrains them. So:

- State what to do and why. Leave out imperatives in capitals, "iron laws",
  red-flag lists, rationalisation tables and threats; the lint rejects shouted
  imperatives.
- Don't restate what the shared prompt already says (honesty about results,
  scope, tone, asking before destructive actions).
- Define what finished looks like when the skill drives a long task. A model
  that does not know where the end is stops early.
- Prefer a stated assumption to a stop-and-ask, except where a decision truly
  belongs to the user.
- No "announce that you are using this skill" and no ceremony around the work.

### Match the form to the failure

Before writing guidance, look at what goes wrong without it. The form that fixes
one kind of failure makes another worse.

| Without guidance, the model... | Write | Avoid |
|---|---|---|
| produces the wrong shape (bloated, buried result, restated spec) | a recipe: what the output is, its parts in order | a list of don'ts |
| leaves out a required element | a slot for it in the template it fills in | a reminder near the template |
| should act differently depending on a condition | a conditional on something observable ("if the brief exists, reference it") | an unconditional rule with exemptions |
| skips a step it knows it should take | the step, and the reason it matters | escalating emphasis |

Two rules for whichever form you pick: a nuance clause ("don't X unless it
matters") reopens the negotiation, so express a real exception as its own
conditional; and an exemption clause ("this doesn't apply to code blocks") does
not scope reliably, so restructure so the rule cannot reach what is exempt.

## Structure

- **Short skill:** everything in SKILL.md. Aim well under 500 words; frequently
  loaded skills far less.
- **Several workflows:** SKILL.md is a router. A few lines of overview, then
  pointers keyed to situations: "Deploying a host: references/deploy.md".
  "See references/ for details" gives the model no reason to open anything.
- **Heavy reference** (API docs, command catalogues): a separate file, or point
  at the tool's `--help` instead of copying it.
- **Reusable code:** a script beside SKILL.md, called by name.

Refer to other skills by name. Don't `@`-include files; that loads them into
context immediately.

One good example beats several adequate ones. Write a decision as a numbered
list or a table rather than a flowchart; models follow prose steps more
reliably than graph source.

## Frontmatter

**Portable fields** (the [agentskills.io](https://agentskills.io/specification)
standard; claude.ai uploads and the Skills API accept only these):

| Field | Notes |
|---|---|
| `name` | Required. Equals the directory name. Lowercase letters, digits, single hyphens; max 64 |
| `description` | Required. One line. What it does, then when |
| `license` | Optional |
| `compatibility` | Optional, max 500 characters. Environment requirements |
| `metadata` | Optional string-to-string map |
| `allowed-tools` | Optional, experimental. Pre-approved tools |

**Claude Code extensions** (stripped from web uploads automatically):

| Field | Purpose |
|---|---|
| `when_to_use` | Extra trigger text appended to the description in listings |
| `argument-hint` | Autocomplete hint, e.g. `"[pr-number]"` |
| `arguments` | Named positional arguments for `$name` |
| `disable-model-invocation` | `true`: only the user can invoke it, as `/name` |
| `user-invocable` | `false`: hide it from the `/` menu |
| `allowed-tools` / `disallowed-tools` | Tools for the invoking turn |
| `model`, `effort` | Overrides while the skill is active |
| `context: fork` + `agent`, `background` | Run in a forked subagent |
| `hooks`, `paths`, `shell` | Lifecycle hooks, path-scoped activation, shell for `!` commands |

Every skill is also a command: `/name`, with `$ARGUMENTS` in the body. A
command-style workflow is a skill with `disable-model-invocation: true` and an
`argument-hint`.

## Before it ships

- The trigger eval still passes, and any new or changed skill has a case in it.
- Behaviour-shaping wording has been micro-tested against a no-guidance
  control (testing.md).
- The repository checks pass: lint, budgets, and the target build.

Anthropic's own authoring guide is at
https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices.
