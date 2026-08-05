# vale-agent-skills

[Vale](https://vale.sh) plus the styles and config profiles that back three
skills in this plugin: `avoid-ai-writing`, `simple-english`, and `diataxis`.

Vale does all the linting. This package adds three custom styles, fourteen
ready-made `.vale.ini` profiles, and `vale-skill`, a launcher that picks the
right profile so a skill can invoke one command instead of assembling a config.

## What it installs

| Path | Contents |
|---|---|
| `bin/vale-skill` | profile launcher (`vale-skill ai-writing draft.md`) |
| `bin/vale` | plain Vale, with every style already on its StylesPath |
| `share/vale-agent-skills/styles` | the `AvoidAI`, `SimpleEnglish`, and `Diataxis` styles |
| `share/vale-agent-skills/configs` | the profile `.vale.ini` files |

The Vale binary is wrapped with `VALE_STYLES_PATH` pointing at a StylesPath that
holds exactly the three styles above. None of the third-party styles nixpkgs
packages are pulled in.

## Styles

**`AvoidAI`** — 62 rules porting the `avoid-ai-writing` catalog. Pattern rules
cover the tiered word lists, chat artifacts, sycophancy, reasoning scaffolding,
cutoff disclaimers, generation fingerprints, empty closers, engagement hooks,
inflation, and the formatting tells. Vale `script` rules (Tengo) cover the
document-level signals a regex cannot express: sentence and paragraph
uniformity, cross-paragraph rhythm, punctuation-density distribution,
function-word trigram entropy, type-token ratio, synonym cycling, the
smart-punctuation signature, the em-dash budget, bare-noun-phrase bullet lists,
boilerplate clustering, structural excess, and missing first-person voice.

Only two catalog entries have no rule, because both are writer-side diagnostics
rather than measurements: paragraph-reshuffle immunity and the treadmill
effect.

**`SimpleEnglish`** — 16 rules for the mechanical half of ASD-STE100: sentence
and paragraph limits, approved modals, simple tenses, contractions, semicolons,
condition placement, phrasal verbs, and synonym rotation.

**`Diataxis`** — 12 rules that catch mode blur, three or four per mode. Each
profile enables only its own mode's rules, so a tutorial is checked for choices
and hedged outcomes while reference is checked for instructions and opinion.

## Profiles

`vale-skill --list` prints them.

`ai-writing` is one config at full strength, matching how the skill is
structured: the linter reports every hit and the context tolerance matrix in
`SKILL.md` is the writer's judgment about which to act on. Its one gate,
`--context technical`, drops Title Case headings and the technical word
carve-out via a Vale filter.

`simple-english` and `diataxis` do have several profiles, because there the
modes are different rule sets rather than different tolerances: a procedure
stops at 20 words and a description at 25, and a tutorial is checked for
different things than reference.

## Scoring

```bash
vale-skill score draft.md                   # 0-100 with a per-rule breakdown
vale-skill score ai-writing:docs README.md  # scored under a different profile
```

Vale does the detecting; `score` only weights and totals what Vale found, so the
number can never disagree with the alert list. The weights, the
`log2(words/50)` length normalization, and the classification bands come from
the avoid-ai-detect scoring model this package replaced.

## Using Vale directly

```bash
vale --config="$(vale-skill --config ai-writing)" draft.md
vale-skill --init ai-writing:docs .    # drop the profile into a repo as .vale.ini
```

## Tests

`tests/run-tests.sh` runs in `checkPhase`. It asserts that every config profile
loads, that every rule in each style fires on a fixture (a new rule without
fixture coverage fails the build), that the clean fixtures stay silent, that
phrases split across a hard line wrap are still caught, and that the score comes
out above zero on the AI fixture and at zero on the human one.

Outside Nix:

```bash
VALE_SKILL_CONFIGS=configs VALE_SKILL_STYLES=styles \
VALE_STYLES_PATH=$PWD/styles tests/run-tests.sh
```
