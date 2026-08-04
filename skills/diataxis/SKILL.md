# Diátaxis — the four modes of documentation

[Diátaxis](https://diataxis.fr) says there are exactly four kinds of documentation, because there are exactly two dimensions of craft: a practitioner both **acts** and **thinks**, and they are alternately **at study** and **at work**. Cross those and you get four quadrants, and four needs:

| Need | Mode | The user | The documentation |
|---|---|---|---|
| learning | **tutorial** | acquires the craft | informs action |
| goals | **how-to guide** | applies the craft | informs action |
| information | **reference** | applies the craft | informs cognition |
| understanding | **explanation** | acquires the craft | informs cognition |

Almost every documentation problem is one of these four doing another one's job.

## Use this skill when

- Writing a new doc and you need to decide what kind it is before writing a word.
- A page feels wrong and you can't say why — it is usually two modes fighting.
- Auditing or restructuring a docs tree.
- Someone asks for "docs" without saying which kind. Ask the compass, not the user.

## The compass

Two questions. They always resolve.

| If the content… | …and serves the user's… | …then it is |
|---|---|---|
| informs action | acquisition of skill | a tutorial |
| informs action | application of skill | a how-to guide |
| informs cognition | application of skill | reference |
| informs cognition | acquisition of skill | explanation |

- **action** — practical steps, doing. **cognition** — propositional knowledge, thinking.
- **acquisition** — study. **application** — work.

Use it flexibly and at any zoom level: on a whole document, on a section, on a single sentence you are unsure about. The compass is most useful exactly when intuition has already answered and you doubt the answer.

## The four modes

### Tutorial — a lesson

Answers *"Can you teach me to…?"*. Oriented to **learning**. Analogy: teaching a child to cook.

The learner learns by doing, under your guidance. What they *do* is not what they *learn* — they do one concrete task and acquire familiarity, names, workflows, and the feeling of doing it.

**The contract is one-sided.** You are responsible for what they learn, what they do to learn it, and whether they succeed. Their only job is to follow along. So:

- **Do not try to teach.** Give them things to do and trust the learning. Explanation breaks the spell.
- **Say where they are going**, at the start: "In this tutorial we will build and deploy a small web service." Not "In this tutorial you will learn…" — that is presumptuous and a poor pattern.
- **Visible results early and often.** Every step produces something the learner can see.
- **Narrate the expected.** "After a few seconds the server responds with…". Show real output. Flag the likely failure: "If you don't see X, you probably skipped Y."
- **Point out what to notice.** The prompt changing, the new file, the log line.
- **Permit repetition.** Learners repeat a step just to see it work again. Make that possible.
- **Ruthlessly minimise explanation.** "We use HTTPS because it is more secure" is enough. Link to the rest.
- **Ignore options and alternatives.** Choices are cognitive load the learner cannot yet carry. Pick for them.
- **Aspire to perfect reliability.** A learner who follows your steps and does not get your result loses confidence in the tutorial, in you, and in themselves. You cannot be there to rescue them.

**Language:** "We…", "In this tutorial, we will…", "First, do x. Now do y.", "The output should look something like…", "Notice that…", "You have now built…".

**Not a tutorial:** a page of options; a page that explains the architecture first; anything that says "depending on your setup".

### How-to guide — a recipe

Answers *"How do I…?"*. Oriented to **goals**. Analogy: a recipe in a cookery book.

Serves a competent user at work. They know what they want; they need directions to get there.

- **Written from the user's problem, not the machinery's features.** "How to configure reconnection back-off" is a how-to. "How to use the `--retry` flag" is reference wearing a how-to costume. If the title names a tool rather than a goal, you probably have the wrong mode.
- **Action and only action.** No teaching, no digression, no reference-for-completeness. Link instead.
- **Address real-world complexity.** A guide useful only for exactly your narrow case is rarely useful. Leave room for the reader to adapt it.
- **Omit the unnecessary.** Unlike a tutorial, a how-to need not be end-to-end. Start and end somewhere reasonable; let the reader join it to their work.
- **A sequence, but not necessarily linear.** Real problems fork, overlap, and need judgement. Address how the user thinks as well as what they do.
- **Do not state the obvious.** "To deploy, select the options and press Deploy" tells a competent user nothing.

**Language:** "This guide shows you how to…", "If you want x, do y.", "To achieve w, do z.", "Refer to the reference for…".

**Not a how-to:** "Getting started"; "Introduction to X"; anything that opens by explaining why the feature exists.

### Reference — a map

Answers *"What is…?"*. Oriented to **information**. Analogy: the information on the back of a food packet.

Users consult reference; they do not read it. They need truth and certainty — firm ground to stand on while working.

- **Describe, and only describe.** Neutral description is unnatural and hard. The pull toward explaining, instructing, and opining is constant. Resist it and link out.
- **Adopt standard patterns.** Reference is useful because it is consistent. Put each thing where the reader expects it, in the format they expect. This is not the place for range of style.
- **Mirror the structure of the product.** The docs map the machinery; the reader works through both at once.
- **Provide examples.** An example illustrates without becoming instruction or explanation.
- **Austere, objective, complete.** Auto-generation is legitimate here and helps keep it faithful to the code.

**Language:** "Sub-commands are: a, b, c.", "The default is 30 seconds.", "You must use a. You must not apply b unless c."

**Not reference:** anything with "we recommend", "unfortunately", "simply", or a numbered procedure.

### Explanation — a discussion

Answers *"Why…?"*. Oriented to **understanding**. Analogy: an article on culinary history.

Read away from the product, for reflection. Its perspective is wider than the others — not the user's eye-level view, not a close-up of the machinery, but a topic.

- **Make connections**, even outside the immediate subject.
- **Provide context**: design decisions, history, technical constraints, implications.
- **Talk *about* the subject.** You should be able to put an implicit "About" in front of the title: *About database connection policies*.
- **Admit opinion and perspective.** Weigh alternatives, counter-examples, other people's approaches. Explanation is discussion, and discussion can consider contrary opinions.
- **Keep it bounded.** Explanation absorbs everything if you let it. Use a real or imagined *why* question as the boundary.

**Language:** "The reason for x is that historically y…", "W is better than z because…", "An x in system y is analogous to a w in system z. However…", "Some users prefer w. That can work, but…".

**Not explanation:** step 1, step 2; installation instructions; a parameter table.

## Blur — how the modes collapse

Each mode has a natural affinity with its neighbours, and that is where the blur happens:

| They share | So these two blur |
|---|---|
| guiding action | tutorials and how-to guides |
| serving the application of skill | reference and how-to guides |
| propositional knowledge | reference and explanation |
| serving the acquisition of skill | tutorials and explanation |

**The worst and most common collapse is tutorial into how-to.** They both give steps, so they look alike — but a tutorial exists so the learner *learns*, and a how-to exists so the worker *finishes*. A page that tries to be both serves neither: the learner drowns in options, the worker wades through teaching. When you find one, split it. The tutorial keeps the narrative and the guarantee; the how-to keeps the goal and the adaptability.

## The linter: Vale with the `Diataxis` style

Twelve rules that catch mode blur, in four per-mode profiles. Each profile checks only its own mode, because a phrase that is wrong in one mode is right in another — "you should" is fine in a how-to and wrong in reference.

```bash
vale-skill diataxis:tutorial     docs/tutorials/*.md
vale-skill diataxis:how-to       docs/how-to/*.md
vale-skill diataxis:reference    docs/reference/*.md
vale-skill diataxis:explanation  docs/explanation/*.md
vale-skill docs                  docs/          # general quality: Google, write-good, alex
```

What each profile looks for:

| Profile | Catches |
|---|---|
| `tutorial` | choices and options, leaked explanation, hedged outcomes, non-lesson titles |
| `how-to` | teaching voice, leaked explanation, lesson or essay titles |
| `reference` | instructions, second-person directives, opinion and apology, non-reference titles |
| `explanation` | procedures, steps, clicks, how-to titles |

**Run the profile that matches the mode you decided on** — running the wrong one produces confident nonsense. If a file trips a rule from a *different* mode's profile, that is the signal it is in the wrong quadrant.

Vale cannot tell you which mode a page *should* be. That is the compass, and it is yours.

## Workflow: guide, not plan

Diátaxis is a map to check you are heading the right way, not a plan to execute. It runs counter to the usual documentation wisdom: it discourages top-down planning in favour of small, responsive iterations.

**Do not build empty structure.** Creating four empty folders named tutorials / how-to / reference / explanation and leaving them there is the classic failed start. Structure emerges from improved content, not the other way round.

The loop:

1. **Choose something.** Any page, section, paragraph. If nothing is bothering you, pick at random. Do not go hunting for problems.
2. **Assess it.** What user need does this represent? How well does it serve that need? Do its language and logic match the mode it belongs to? What can be added, moved, removed, or changed?
3. **Decide.** What single next action produces an immediate improvement here?
4. **Do it** — and consider it done. Commit it. You do not owe anyone a bigger change.

Then start again. Small steps in the right direction beat a plan you never finish.

**Complete, not finished.** A plant is never finished and always complete. Documentation is the same: at every stage it can be useful, coherent, and ready for the next stage. Publish the step.

## Quality

**Functional quality** — accuracy, completeness, consistency, precision, usefulness. Independent of each other, objectively measurable, and every failure is obvious to the reader. Diátaxis helps here by telling you what each page is supposed to contain.

**Deep quality** — flow, fitting human needs, anticipating the reader, feeling good to use. Not measurable; only judged. It is *conditional* on functional quality: nobody experiences inaccurate docs as beautiful. Diátaxis helps here too, because a page that serves one need cleanly is the precondition for flow.

When you review, do both passes: does this page do its job, and does it feel like it was written for a person?

## Working a request

**"Write docs for X."** Ask the compass first. Say which mode you chose and why, then write in that mode only. If X needs more than one, write them as separate documents and link them.

**"This page is bad."** Classify it. Nine times out of ten it is two modes in one file. Name the two, propose the split, then split it.

**"Restructure our docs."** Do not start with folders. Run the loop over individual pages until the material starts demanding a heading; let the top-level structure form from what you moved.

**"Review this."** Run the matching Vale profile, then check the mode-specific list in `references/mode-checklists.md`, then judge flow.

## Pairing with other skills

- `simple-english` — how to write each sentence once you know what the page is. Especially strong for tutorials and how-to guides.
- `avoid-ai-writing` — strips machine tells. Run `vale-skill ai-writing:docs` on prose that reads as generated.
- `prose-craft` — for explanation, which is the one mode with room for voice. Keep it out of reference.

## References

- `references/mode-checklists.md` — per-mode authoring and review checklists, with the language patterns and the split recipes for blurred pages

## Attribution

Diátaxis is the work of [Daniele Procida](https://diataxis.fr), published under [CC BY-SA 4.0](https://creativecommons.org/licenses/by-sa/4.0/). This skill is adapted material and carries the same license. The framework, the compass, the four modes and their principles are his; the checklists, the split recipes, and the Vale rules are this repo's.
