# Mode checklists

One authoring checklist and one review checklist per mode, plus recipes for splitting a page that is doing two jobs.

Run the matching Vale profile first — `vale-skill diataxis:tutorial FILE`, `vale-skill diataxis:how-to FILE`, `vale-skill diataxis:reference FILE`, or `vale-skill diataxis:explanation FILE`. These lists are what Vale cannot see.

---

## Tutorial

### Before you write

- [ ] Name the concrete thing the learner will build. Not a topic, a **thing**.
- [ ] List what they will actually acquire along the way — names, tools, commands, workflows. This is different from what they build, and it is the real curriculum.
- [ ] Check the exercise is meaningful (a sense of achievement), successful (they can finish), logical (the path makes sense), and usefully complete (they meet everything they need to meet).
- [ ] Decide every choice for them. Write the decisions down; they become the fixed path.

### While writing

- [ ] Open by saying what *we* will do. Never "you will learn".
- [ ] Every step produces a visible result.
- [ ] Show the expected output, verbatim where you can.
- [ ] Warn about surprises before they happen ("this prints several hundred lines").
- [ ] Point out what to notice — the prompt change, the new file.
- [ ] Explanation is one clause, then a link.
- [ ] No options, no "alternatively", no "depending on".
- [ ] Close by naming what they built.

### Review

- [ ] Follow it yourself, from a clean state, exactly as written. Anything that fails is a defect, not a caveat.
- [ ] Any sentence that teaches instead of directing → cut or link.
- [ ] Any hedge about the outcome ("should be able to", "usually", "in most cases") → make it certain or fix the step.
- [ ] Any choice offered to the learner → make it for them.
- [ ] Would a beginner know they succeeded at every step? If not, add the expected result.

---

## How-to guide

### Before you write

- [ ] State the goal as a human project: "how to *X*", where X is something someone wants done.
- [ ] If the title names a tool, a flag, or a screen, you are writing reference. Reframe or move it.
- [ ] Confirm the reader's assumed competence. Write that down; it is what lets you omit things.

### While writing

- [ ] Steps are actions, in a sequence that has a reason.
- [ ] Cover the forks a real user hits. Say what to do when the situation differs.
- [ ] No teaching, no theory, no completeness-for-its-own-sake. Link out.
- [ ] Skip anything a competent user already knows.
- [ ] Start and end somewhere reasonable; the reader joins it to their own work.

### Review

- [ ] Does the title answer "How do I…?" — if it answers "What is…?" or "Why…?", it is in the wrong quadrant.
- [ ] Any "in this tutorial", "you will learn", "don't worry if" → this drifted into a tutorial. Split or rewrite.
- [ ] Any paragraph explaining *why* → link to explanation.
- [ ] Is it adaptable, or does it work only for the exact case you had in mind?

---

## Reference

### Before you write

- [ ] Take the structure from the product, not from a narrative. The docs should map the machinery.
- [ ] Pick the pattern for each entry — name, signature, parameters, defaults, errors, example — and use it everywhere.

### While writing

- [ ] Describe. Do not instruct, explain, recommend, or apologise.
- [ ] State defaults, limits, units, and error conditions explicitly.
- [ ] Add examples for illustration, never as procedure.
- [ ] Warnings are allowed and belong here: "You must not apply b unless c."
- [ ] Consider generating what can be generated from the code.

### Review

- [ ] Any second-person directive ("you should", "first, run") → move to a how-to.
- [ ] Any opinion or softener ("simply", "obviously", "unfortunately", "the best way") → cut.
- [ ] Any "why" paragraph → move to explanation.
- [ ] Is every entry in the same shape? Inconsistency is the main way reference fails.
- [ ] Could someone consult one entry in isolation and trust it?

---

## Explanation

### Before you write

- [ ] Write the *why* question this answers. That question is the boundary.
- [ ] Check the title takes an implicit "About": *About connection pooling*.

### While writing

- [ ] Give background: design decisions, history, constraints.
- [ ] Make connections to neighbouring topics, including outside the product.
- [ ] Weigh alternatives and name the trade-offs. Say what other people do and why.
- [ ] Opinion is welcome — mark it as opinion.
- [ ] No steps, no commands to run, no parameter tables.

### Review

- [ ] Any procedure → move to a how-to.
- [ ] Any exhaustive list of options → move to reference.
- [ ] Has it absorbed material that lives elsewhere? Explanation expands until stopped.
- [ ] Would this still hold a reader's attention away from the keyboard?

---

## Splitting a blurred page

Diagnose by asking the compass about each **section**, not the page. When two answers come back, you have two documents.

### Tutorial + how-to (the common one)

The page teaches and also serves someone who just wants the result.

1. Fork the file in two.
2. The tutorial keeps: the narrative, the fixed choices, the expected output, the guarantee. Strip every option.
3. The how-to keeps: the goal in the title, the adaptable steps, the forks. Strip every "we" and every piece of teaching.
4. Link them: the tutorial ends by pointing at the how-to; the how-to assumes the tutorial's competence.

### Reference + how-to

A parameter table grew a procedure, or a procedure grew an exhaustive option list.

1. The table goes to reference, in the standard entry shape.
2. The procedure goes to a how-to, named for the goal.
3. The how-to links to the reference entry instead of repeating it.

### Reference + explanation

A description grew a "why we did it this way" section.

1. Cut the rationale into an explanation page titled *About X*.
2. Leave one sentence and a link where it was.

### Tutorial + explanation

The lesson keeps stopping to explain.

1. Move each explanatory passage to an explanation page.
2. Replace each with at most one clause plus a link.
3. Re-read the tutorial start to finish; the flow usually improves more than you expect.

---

## The four questions, for quick classification

Read the page and answer:

1. Does it inform **action** or **cognition**?
2. Does it serve **acquisition** (study) or **application** (work)?
3. What question does its title answer: *Can you teach me to…? / How do I…? / What is…? / Why…?*
4. Does its language match? ("we" and expected output → tutorial; "to achieve x, do y" → how-to; flat statements of fact → reference; "the reason is" and "however" → explanation.)

If 1 and 2 disagree with 3, the title is wrong. If 3 disagrees with 4, the writing is wrong. If sections disagree with each other, split the page.
