---
name: tscircuit
description: Use when building, modifying, or debugging a tscircuit PCB design — React/TypeScript circuit source (`*.circuit.tsx`, `tscircuit.config.json`, `@tsci/*` imports) or the `tsci` CLI (init, build, check, search, add, import, export, snapshot, push). Triggers on choosing footprints, placing parts, wiring nets and traces, tscircuit builtin elements such as `<board />`, `<chip />`, `<trace />`, `<schematicsection />`, or exporting Gerbers, BOM, pick-and-place, or KiCad files from a tscircuit project.
# Local, read-only, or project-scoped tsci commands. `tsci push`, `tsci login`,
# and `tsci dev` (a long-running server) intentionally prompt.
allowed-tools: Bash(tsci --help), Bash(tsci build:*), Bash(tsci check:*), Bash(tsci export:*), Bash(tsci snapshot:*), Bash(tsci search:*), Bash(tsci doctor:*), Bash(tsci init:*), Bash(tsci add:*), Bash(tsci import:*)
---

# tscircuit

You are helping the user design electronics using tscircuit (React/TypeScript) and the `tsci` CLI.

When this Skill is active:

- Prefer tscircuit’s documented primitives and CLI behavior. If something is unclear, confirm by:
  - Reading local files in the repo (e.g., `tscircuit.config.json`, `index.circuit.tsx`, `package.json`)
  - Running `tsci --help` or the specific subcommand’s `--help`
- Avoid “inventing” JSX props or CLI flags.

## This setup

- `tsci` is installed by the dotfiles kicad module (`modules/home/kicad.nix`,
  package in `modules/home/_pkgs/tscircuit/`) and runs under bun. Do not run
  `tsci upgrade` or `tsci agent`: the install is Nix-managed, so bump the
  version and `npmDepsHash` in that package instead.
- tscircuit is one front end for the KiCAD toolchain on this machine. To hand a
  design to KiCAD, run `tsci export <file> -f kicad_pcb` (also `kicad_sch`,
  `kicad_zip`, `kicad-library`), then follow the `konnect` skill for any edits
  to the resulting `.kicad_*` files.
- Read `references/field-notes.md` before placing keepouts, writing manual
  trace paths, building custom footprints, tuning autorouter clearance, or
  exporting to KiCad. It records where the CLI diverges from these references.

## Default workflow

1) Clarify requirements (if not already given)
- Board form factor / size constraints
- Power sources and voltage rails
- I/O: connectors, headers, mounting holes, mechanical constraints
- Target manufacturer constraints (trace/space, assembly, supplier)

2) Choose a starting point
- If the repo is not a tscircuit project, run `tsci init` to bootstrap one.
- If a form-factor template is appropriate (Arduino Shield, Raspberry Pi HAT, etc.), prefer `@tscircuit/common` templates.

3) Find and install components
- Use `tsci search "<query>"` to discover footprints and tscircuit registry packages.
- Use `tsci search --digikey "<query>"` or `tsci search --mouser "<query>"` when distributor stock and supplier part numbers matter. Both flags can be combined, and `--json` provides machine-readable results.
- For USB-C receptacles/connectors, prefer builtin syntax with `<connector standard="usb_c" />` instead of importing from JLCPCB.
- Use one of:
  - `tsci add <author/pkg>` for registry packages (installs `@tsci/*` packages)
  - `tsci import <query>` when you need to import a component from JLCPCB or the registry.
- DigiKey and Mouser search results are for part discovery; `tsci import` does not directly import from those distributors.

4) Write/modify TSX circuit code
- Keep circuits as a default-exported function that returns JSX.
- Read `references/footprints.md` before writing custom footprint TSX; prefer a footprinter string when one matches the package.
- Use layout props intentionally:
  - PCB: `pcbX`, `pcbY`, `pcbRotation`, `layer`
  - Schematic: `schX`, `schY`, `schRotation`, `schOrientation`
- On large projects (5+ components), use `<schematicsection />` to group components by function (e.g. "Power", "MCU", "IO"). This is one of the most important things for schematic readability. Assign each component a `schSectionName` and manually position all members of a section in close proximity using `schX`/`schY`.
- When one large chip needs to appear on multiple schematic sheets, declare the `<chip />` once before the sheets, then use one `<schematicbox chipRef=".U1" />` per sheet. Either nest each box inside its `<schematicsheet />`, or keep the elements as siblings and assign the box with `schSheetName`. Pass only that sheet's labels to the box and keep connections addressed to the original chip, such as `U1.VCC`. See the [`<schematicbox />` reference](./references/elements/schematicbox.md#split-one-chip-across-multiple-schematic-sheets).
- Use `<antenna />` for a placed, open-ended PCB antenna. Give it a one-pad footprint, define its local copper geometry with `pcbPath`, and connect the circuit to its `.feed` port with a separate `<trace />`. See the [`<antenna />` reference](./references/elements/antenna.md).
- Use `<trace />` for connectivity; prefer net connections (`net.GND`, `net.VCC`, etc.) for power/ground.

5) Build and iterate
- Run `tsci check netlist` before `tsci check schematic-placement`, `tsci check placement`, and `tsci build` to catch connectivity issues early.
- Use `tsci check schematic-placement` to validate schematic-side placement before checking PCB placement.
- Do not finalize unless both `tsci check schematic-placement` and `tsci check placement` pass with no actionable placement violations; if violations exist, fix layout and rerun until clean.
- Use `tsci check trace-length` to check for long straight line distances (before routing) or long routes (after routing)
- Run `tsci build --pcb-png [file]` to inspect placement before checking routing.
- Run `tsci check routing-difficulty` after placement to identify potential areas of congestion.
- Run `tsci build` to compile and validate the circuit.
- When routing looks suspicious, run
  `tsci build [file] --autorouter-debug --autorouter-debug-dir dist/autorouter-debug`
  and inspect `placement-unrouted.png` plus each cumulative
  `phase-N-routed.png`. Add `--autorouter-dump-srj all` when the
  SimpleRouteJson input and output for every stage is also needed.
- After routing, run `tsci check shorts [file]` to detect unintended shorts between separate PCB copper groups. Omit `[file]` to use the project entrypoint; a prebuilt `*.circuit.json` file is also accepted.
- A detected short makes `tsci check shorts` exit nonzero. Inspect `checks/check-shorts/bitmap.png` and `checks/check-shorts/pcb.svg`, fix the implicated copper, then rerun the check. Do not dismiss this failure as a generic DRC warning.
- The default check analyzes Gerber-derived copper on both layers. Use `--mode pcb` for PCB geometry, `--layer top` or `--layer bottom` to narrow the scope, and `--pixels-per-mm <number>` only when a different bitmap resolution is needed.
- DRC (Design Rule Check) errors can often be ignored during development—focus on getting the circuit correct first.
- If routing struggles, reduce density, use `<group />` for sub-layouts, or change autorouter settings.
- Use `tsci dev` only when you need interactive visual feedback (not typical for AI-driven iteration).

6) Validate and export
- Run `tsci check netlist` before `tsci check schematic-placement`, `tsci check placement`, and `tsci build` when preparing to share/publish.
- Run `tsci check shorts` after routing and before sharing, publishing, or producing fabrication outputs. Resolve every reported short before proceeding.
- Run `tsci build` (and optionally `tsci snapshot`) before sharing/publishing.
- Use `tsci export` for SVG/netlist/DSN/3D/KiCad/library outputs.
- For manufacturing, `tsci export <file> -f gerbers` writes the Gerber set; the export UI after `tsci dev` also bundles BOM and pick-and-place.

## Safety and non-goals

- Treat electrical safety, regulatory compliance, and manufacturability as user-owned responsibilities.
- Do not publish (`tsci push`) or place orders unless the user explicitly requests it.

## Local references bundled with this Skill

- CLI primer: `references/cli.md`
- Syntax primer: `references/syntax.md`
- Footprinter strings: `references/footprints.md`
- Workflow patterns: `references/workflow.md`
- Pre-export checklist: `references/checklist.md`
- Local field notes (CLI vs docs divergences): `references/field-notes.md`
- Ready-to-copy templates: `templates/`
- Helper scripts: `scripts/` (`smoke_test.sh` builds the enclosing project, `export_svgs.sh` writes schematic and PCB SVGs, `fetch_ai_txt.sh` downloads upstream's `ai.txt` primer)

## Builtin Elements

- [`<analogsimulation />`](./references/elements/analogsimulation.md)
- [`<antenna />`](./references/elements/antenna.md)
- [`<assembly.device />`](./references/elements/assemblydevice.md)
- [`<battery />`](./references/elements/battery.md)
- [`<board />`](./references/elements/board.md)
- [`<breakout />`](./references/elements/breakout.md)
- [`<breakoutpoint />`](./references/elements/breakoutpoint.md)
- [`<cadassembly />`](./references/elements/cadassembly.md)
- [`<cadmodel />`](./references/elements/cadmodel.md)
- [`<capacitor />`](./references/elements/capacitor.md)
- [`<chip />`](./references/elements/chip.md)
- [`<connector />`](./references/elements/connector.md)
- [`<constraint />`](./references/elements/constraint.md)
- [`<copperpour />`](./references/elements/copperpour.md)
- [`<coppertext />`](./references/elements/coppertext.md)
- [`<courtyardcircle />`](./references/elements/courtyardcircle.md)
- [`<courtyardoutline />`](./references/elements/courtyardoutline.md)
- [`<courtyardpill />`](./references/elements/courtyardpill.md)
- [`<courtyardrect />`](./references/elements/courtyardrect.md)
- [`<crystal />`](./references/elements/crystal.md)
- [`<currentsource />`](./references/elements/currentsource.md)
- [`<cutout />`](./references/elements/cutout.md)
- [`<diode />`](./references/elements/diode.md)
- [`<enclosure.cutoutaperture />`](./references/elements/enclosurecutoutaperture.md)
- [`<enclosure.fdm.box />`](./references/elements/enclosurefdmbox.md)
- [`<fabricationnotedimension />`](./references/elements/fabricationnotedimension.md)
- [`<fabricationnotepath />`](./references/elements/fabricationnotepath.md)
- [`<fabricationnoterect />`](./references/elements/fabricationnoterect.md)
- [`<fabricationnotetext />`](./references/elements/fabricationnotetext.md)
- [`<fiducial />`](./references/elements/fiducial.md)
- [`<footprint />`](./references/elements/footprint.md)
- [`<fuse />`](./references/elements/fuse.md)
- [`<group />`](./references/elements/group.md)
- [`<hole />`](./references/elements/hole.md)
- [`<inductor />`](./references/elements/inductor.md)
- [`<jumper />`](./references/elements/jumper.md)
- [`<led />`](./references/elements/led.md)
- [`<mosfet />`](./references/elements/mosfet.md)
- [`<mountedboard />`](./references/elements/mountedboard.md)
- [`<net />`](./references/elements/net.md)
- [`<netalias />`](./references/elements/netalias.md)
- [`<netlabel />`](./references/elements/netlabel.md)
- [`<opamp />`](./references/elements/opamp.md)
- [`<panel />`](./references/elements/panel.md)
- [`<pcbkeepout />`](./references/elements/pcbkeepout.md)
- [`<pcbnotedimension />`](./references/elements/pcbnotedimension.md)
- [`<pcbnoteline />`](./references/elements/pcbnoteline.md)
- [`<pcbnotepath />`](./references/elements/pcbnotepath.md)
- [`<pcbnoterect />`](./references/elements/pcbnoterect.md)
- [`<pcbnotetext />`](./references/elements/pcbnotetext.md)
- [`<pcbtrace />`](./references/elements/pcbtrace.md)
- [`<pinheader />`](./references/elements/pinheader.md)
- [`<pinout />`](./references/elements/pinout.md)
- [`<platedhole />`](./references/elements/platedhole.md)
- [`<port />`](./references/elements/port.md)
- [`<potentiometer />`](./references/elements/potentiometer.md)
- [`<pushbutton />`](./references/elements/pushbutton.md)
- [`<resistor />`](./references/elements/resistor.md)
- [`<resonator />`](./references/elements/resonator.md)
- [`<schematicarc />`](./references/elements/schematicarc.md)
- [`<schematicbox />`](./references/elements/schematicbox.md)
- [`<schematiccell />`](./references/elements/schematiccell.md)
- [`<schematiccircle />`](./references/elements/schematiccircle.md)
- [`<schematicline />`](./references/elements/schematicline.md)
- [`<schematicpath />`](./references/elements/schematicpath.md)
- [`<schematicrect />`](./references/elements/schematicrect.md)
- [`<schematicrow />`](./references/elements/schematicrow.md)
- [`<schematicsection />`](./references/elements/schematicsection.md)
- [`<schematictable />`](./references/elements/schematictable.md)
- [`<schematictext />`](./references/elements/schematictext.md)
- [`<silkscreencircle />`](./references/elements/silkscreencircle.md)
- [`<silkscreenline />`](./references/elements/silkscreenline.md)
- [`<silkscreenpath />`](./references/elements/silkscreenpath.md)
- [`<silkscreenrect />`](./references/elements/silkscreenrect.md)
- [`<silkscreentext />`](./references/elements/silkscreentext.md)
- [`<smtpad />`](./references/elements/smtpad.md)
- [`<solderjumper />`](./references/elements/solderjumper.md)
- [`<subcircuit />`](./references/elements/subcircuit.md)
- [`<subpanel />`](./references/elements/subpanel.md)
- [`<switch />`](./references/elements/switch.md)
- [`<symbol />`](./references/elements/symbol.md)
- [`<testpoint />`](./references/elements/testpoint.md)
- [`<trace />`](./references/elements/trace.md)
- [`<tracehint />`](./references/elements/tracehint.md)
- [`<transistor />`](./references/elements/transistor.md)
- [`<via />`](./references/elements/via.md)
- [`<voltageprobe />`](./references/elements/voltageprobe.md)
- [`<voltagesource />`](./references/elements/voltagesource.md)
