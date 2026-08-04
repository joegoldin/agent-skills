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
holds the three styles above plus the nixpkgs-packaged `alex`, `Google`,
`Microsoft`, `proselint`, `Readability`, and `write-good`.

## Styles

**`AvoidAI`** — 37 rules porting the machine-detectable half of the
`avoid-ai-writing` catalog: the tiered word lists, chat artifacts, generation
fingerprints, empty closers, engagement hooks, and the formatting tells. The
rules a regex cannot see (rhythm, paragraph-reshuffle immunity, information
density) stay in the skill as judgment calls.

**`SimpleEnglish`** — 16 rules for the mechanical half of ASD-STE100: sentence
and paragraph limits, approved modals, simple tenses, contractions, semicolons,
condition placement, phrasal verbs, and synonym rotation.

**`Diataxis`** — 12 rules that catch mode blur, three or four per mode. Each
profile enables only its own mode's rules, so a tutorial is checked for choices
and hedged outcomes while reference is checked for instructions and opinion.

## Profiles

`vale-skill --list` prints them. The `ai-writing:*` profiles implement the
context tolerance matrix from the skill — `technical` drops the words with a
legitimate technical sense, `investor` escalates inflation to errors, `casual`
keeps only the credibility killers.

## Using Vale directly

```bash
vale --config="$(vale-skill --config ai-writing)" draft.md
vale-skill --init ai-writing:docs .    # drop the profile into a repo as .vale.ini
```

## Tests

`tests/run-tests.sh` runs in `checkPhase`. It asserts that every config profile
loads, that every rule in each style fires on its fixture (a new rule without
fixture coverage fails the build), and that the clean fixtures stay silent.

Outside Nix:

```bash
VALE_SKILL_CONFIGS=configs VALE_SKILL_STYLES=styles \
VALE_STYLES_PATH=$PWD/styles tests/run-tests.sh
```
