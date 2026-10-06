# Testing a skill

Three checks, from cheapest to most thorough. Use the ones the change needs.

## Does it load when it should?

`tests/skill-triggers/` in the agent-skills repo asks a real pi session which
skills it would load for each task in `cases.json`, given only the names and
descriptions it sees, and checks the picks against what each case expects and
forbids.

```sh
PI=<pi built from the change>/bin/pi tests/skill-triggers/run.py --compare tests/skill-triggers/baseline.json
```

Add a case for every new skill: one task that should select it, and one nearby
task that should not. When a description change is meant to narrow a trigger,
add the task it should stop matching to that case's `forbid`.

## Does the wording do what you meant?

For guidance that shapes behaviour, test the wording itself before running a
whole task:

1. One fresh-context sample per call: a raw API call, or a single-shot
   subagent. The system prompt is the realistic context the guidance lives in
   (the whole skill, not the sentence alone); the user message is a task that
   invites the failure.
2. Include a no-guidance control. If the control does not show the failure,
   there is nothing to fix; don't write the guidance.
3. Five or more samples per variant. One sample says little.
4. Read every flagged result yourself. Quoted examples and template echoes
   look like hits to a script.
5. Watch the spread. Guidance that works makes the samples converge; five
   different readings in five samples means the wording is not binding yet.

## Does it work on a real task?

Give a subagent a realistic task the skill is for, with the skill available,
and read what it does. Then give it a task the skill is not for, and check it
stays out of the way. Variation matters more than repetition: an edge case the
skill doesn't cover teaches more than the happy path run twice.
