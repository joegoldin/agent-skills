---
name: prose-craft
description: Use when drafting or strengthening prose and you want craft rather than merely clean copy. Provides compression (freighting, telescoping, melted-together words), direct metaphor (line-ups), refreshing stale phrases (recyclables), powerful lists (netting), and punctuation rhythm (hieroglyphics). The generative companion to avoid-ai-writing, which strips machine tells while this skill adds craft.
---

# Prose Craft — Techniques for Vivid, Compressed Writing

Generative writing techniques: concrete moves that **add** craft, energy, and precision to prose. This is the companion to `avoid-ai-writing`. That skill is subtractive — it strips the tells that make text read as machine-generated. This one is additive — it gives you specific techniques to make plain prose vivid without tipping into purple.

Use these as seasoning, not the meal. Plain sentences are the baseline; these moves earn their power by being rare. A page with three deliberate techniques reads as craft. A page where every sentence is an elaborate construction reads as a different kind of machine — and trips the exact uniformity `avoid-ai-writing` warns about.

## When to use

- Drafting something that should carry voice: essays, posts, launch announcements, a README with personality, narrative.
- A passage reads flat, verbose, or list-like and you want it tighter or more vivid.
- You've already cleaned a draft with `avoid-ai-writing`, the copy is free of tells, but it's lifeless. Clean is not the same as good.

## When NOT to use

- Reference docs, API parameters, legal or compliance text, safety-critical instructions. Clarity beats flair; leave these plain.
- Writing for translation or for non-native readers.
- All at once. If you apply every technique to every sentence, you've traded one uniformity for another. Aim for a handful of deliberate moves per page and let plain sentences carry the rest.

---

## 1. Compression — say more in less

### Freighting (stacking)

Load related items onto shared sentence parts instead of repeating the frame. Think of subjects, verbs, and objects as freight cars: each car can carry several items, as long as every subject genuinely takes every verb.

**Before:**
```
The scheduler retries failed jobs. The watchdog retries them too. The operator
sometimes retries by hand. They requeue the job. They double the timeout. They
page whoever is on call.
```

**After:**
```
The scheduler, the watchdog, and the occasional bleary operator requeue the job,
double the timeout, and page whoever is on call.
```

**Rules:**
- Every item on the subject car must take every item on the verb car. If one subject doesn't do one of the verbs, you've written a run-on, not a freight.
- Items can be phrases, not just single words.
- Stop before the cars get so long the reader loses the engine. Three or four items per car is usually the ceiling.

### Telescoping (the participial cascade)

Start with one complete sentence, then zoom from general to specific with participle phrases (`-ing`, `-ed`). The trick is that only the first clause gets a finite verb; every zoom rides an incomplete one.

**Before:**
```
We inherited the codebase. It had nine hundred files. The files imported each
other in loops. The loops made a test run take an hour.
```

**After:**
```
We inherited the codebase, nine hundred files importing each other in loops, the
loops dragging a full test run out to an hour, nobody left who remembered why.
```

**Key rule:** exactly one complete verb (`inherited`). If a zoom phrase has its own finite verb (`the files were tangled`), you've made a comma splice. Keep them participial (`the files tangled`, `tangling`).

**Creating closure** so the cascade doesn't trail off — pick one:
1. End on a complete clause: `…nobody left who remembered why.`
2. End with a `which`/`that` clause that resolves it.
3. Compound the final phrase so it lands: `…and the loops were the least of it.`

### Melted-together words (phrasal hyphenates)

Melt a whole phrase into a single hyphenated adjective. It compresses a clause into one word and creates a small, useful pause through its strangeness.

**Process:** take the phrase → hyphenate it whole → hang it on a noun.

**Examples:**
- "her I-already-know-the-answer pause"
- "a we-shipped-it-Friday-afternoon bug"
- "his fourth-standup-of-the-day voice"
- "the it-works-on-my-machine shrug"

**Rules:**
- It has to function as one unit, almost always an adjective before a noun.
- Don't hyphenate it onto the noun it modifies, and don't wrap it in quotation marks.
- Skip prefab phrases that are already compounds ("state-of-the-art", "do-it-yourself"); the move only earns its pause when the phrase is freshly melted.

---

## 2. Metaphor — concrete over abstract

### Line-ups (direct metaphor)

Drop "like" and "as." Instead of comparing, assign the characteristic directly. The comparison words are training wheels; metaphor is stronger when you take them off.

**Animate adjective + inanimate noun:**
- "the impatient build," "a smug green checkmark," "the forgetful cache"

**Inanimate adjective + animate noun:**
- "a granite reviewer," "the fluorescent intern," "a cardboard apology"

**Noun as adjective** (carry the noun's qualities over):
- "he writes vending-machine docs" — everything itemized, nothing warm
- "she gave a fire-drill apology" — loud, brief, instantly forgotten

**The literal-truth test.** A line-up works only when it *can't* be literally true. "slow query" is literally true and dead. "anxious query" can't be — only people get anxious — so it reads as metaphor and comes alive. If the adjective could plausibly apply for real, pick a different one.

### Recyclables (refresh the familiar instead of avoiding it)

Don't flee clichés and stock phrases; remix them. Four moves:

**Simile-reforming** — take a tired simile and either name the actual mechanism or drop the comparison entirely.
- "busy as a bee" → "she answered three threads mid-sentence"
- "the deadline felt impossible" → "the deadline was quicksand; the harder we pushed, the deeper it pulled"

**Antiquing** — graft Greek/Latin bits onto plain words for mock-clinical effect. Keep it pronounceable.
- "standup" + *-itis* → "standup-itis"
- "doomscroll" + *-aholic* → "doomscroll-aholic"
- *hyper-* + "meeting" → "hyper-meeting-ism"

**Soldering** — fuse synonyms into a fresh compound (a thesaurus helps). Aim for the unexpected pairing, not the obvious one.
- people who reply-all to thank everyone: "thread-floods," "inbox-avalanches," "CC-confetti"
- chronic meeting-bookers: "calendar-squatters," "hour-burglars"

**Culturing** — attach a widely known reference plus *-esque* / *-ism* / *-ian*.
- "Kafka-esque expense reports," "Clippy-ism" (volunteering help nobody asked for), "Swanson-ian budget cuts"
- Use references most readers will catch. An obscure one ("Znort-ism") means nothing and dies on the page.

---

## 3. Lists — Netting

A list is architecture, not enumeration. Three concepts turn a flat list into one that accumulates into a single impression (a *gestalt*).

**Specificity** — move from general to particular *within* the list, so it tightens as it goes:
> tools → power tools → the orbital sander → the orbital sander that died mid-cut last March and took the deadline with it

**Sizing** — vary entry length. Mix single words, phrases, and whole sentences so the list has rhythm instead of a metronome beat:
```
What launch day is made of: adrenaline. The third coffee you don't remember
pouring. A dashboard you refresh like it owes you money. The specific silence
right before someone says "uh, prod is down." Going home anyway.
```

**Juxtaposition** — order for effect, and set the enormous next to the trivial so each sharpens the other:
> the migration that could sink the quarter, and whether anyone refilled the printer

Connect with the punctuation the items need: commas for simple items, semicolons when items already contain commas, a colon to introduce, a dash for a dramatic last beat.

---

## 4. Rhythm — Hieroglyphics (punctuation as music)

Punctuation is pacing. Most flat prose uses only the period; these marks give you tempo.

- **Semicolon** — fuse two independent clauses that lean on each other: "The deploy went green; nobody trusted it."
- **Colon** — make a promise, then pay it off: "The outage had one root cause: a comma."
- **Single dash** — a swerve or a hard landing: "We hit the deadline — barely, and never again."
- **Dash skewer** (a matched pair) — drop an aside into the middle of a sentence without losing the thread: "The rollback — there is always a rollback — took four minutes."
- **Very short sentences** — after a long sentence, drop to two to five words. The contrast is the impact: "It held."

**Read-aloud test:** if a passage scans like a metronome — same length, same beat — vary it. Human rhythm resists robotic delivery.

### A note on dashes (reconciling with avoid-ai-writing)

`avoid-ai-writing` targets the em dash hard, because the *reflexive* dash — several per page, dropped wherever a comma would do — is a classic autopilot tell. The dash here is the opposite animal: deliberate, rare, load-bearing. One or two per piece reads as craft; spraying them is the tell. When the two skills disagree about a dash, the tiebreaker is honesty: is this dash doing work a comma couldn't, or is it decoration? Keep the first kind, cut the second.

---

## Composing techniques

Techniques stack. Here freighting carries the subjects and verbs, a line-up colors the object, and a very short sentence lands the beat:

```
The scheduler, the watchdog, and the operator requeued, retried, and re-paged the
same granite job all night. It never moved.
```

But restraint is the governing rule. Three techniques in a paragraph is rich; ten is exhausting. Plain sentences are the contrast that makes a crafted one register — without them, nothing stands out.

## Pairing with avoid-ai-writing

The two skills pull against each other on purpose: one adds, one removes. Good prose is what survives both.

1. **Draft with craft** — use these techniques to get vivid, compressed prose down.
2. **Clean it** — run `avoid-ai-writing`, or `avoid-ai-detect draft.md` for a quick 0–100 score, to strip machine tells (hollow intensifiers, copula avoidance, reflexive transitions, em-dash spray).
3. **Resolve toward restraint** — if the cleanup flags a dash or a metaphor you placed on purpose and it's earning its keep, keep it. If it's just decoration, cut it.

## Quick reference

| Technique | Use when | The move |
|---|---|---|
| **Freighting** | Repeating the same sentence frame | Stack shared subjects/verbs/objects onto one frame |
| **Telescoping** | Flowing general → specific | One finite verb, then participial zoom phrases |
| **Melted-together words** | Compressing a clause into a beat | Hyphenate a whole phrase into one adjective |
| **Line-ups** | A simile feels weak | Drop like/as; assign the trait directly (must be un-literal) |
| **Recyclables** | A cliché is the right idea but stale | Reform / antique / solder / culture it |
| **Netting** | A list reads flat | Vary specificity, size, and order for one accumulated impression |
| **Hieroglyphics** | Prose scans like a metronome | Semicolon, colon, dash, dash skewer, short sentence |

## The one rule that governs all of these

Restraint. Every technique above is an accent on a plain baseline. Apply them sparingly and each one lands; apply them everywhere and you rebuild the uniformity you were trying to escape. If you can't say why a particular sentence needs a particular move, leave it plain.
