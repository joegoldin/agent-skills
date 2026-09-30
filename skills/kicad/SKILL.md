---
name: kicad
description: Use when working on a KiCad project (.kicad_sch, .kicad_pcb, .kicad_pro, Gerbers) — reviewing or changing a schematic or board, simulating analog subcircuits with SPICE, or preparing JLCPCB fabrication and assembly files.
---

# KiCad

## Changing a design

KiCad source files (`.kicad_sch`, `.kicad_pcb`, `.kicad_pro`, `.kicad_sym`,
`.kicad_mod`, `*-lib-table`) are UUID-linked object graphs, and text edits
corrupt them. Make every change through the Konnect MCP tools: `list_toolboxes`
shows the toolsets and `load_toolset("<name>")` exposes one. PCB edits go over
KiCad's IPC API and need KiCad running with the board open; schematic and
library edits are file-based and do not. If the Konnect tools are unavailable,
say so instead of editing the files. Describe each change before making it and
re-query the design afterwards.

`kicad-cli` exports netlists, BOMs, Gerbers, drill and position files, and
runs `kicad-cli sch erc` and `kicad-cli pcb drc` without the GUI.

## Reviewing a design

The kicad-happy analyzers parse KiCad 5–10 files read-only into structured
JSON. Run them before reasoning about a design:

```bash
K=<this skill's directory>/kicad-happy
python3 $K/kicad/scripts/analyze_schematic.py board.kicad_sch --analysis-dir analysis/
python3 $K/kicad/scripts/analyze_pcb.py board.kicad_pcb --analysis-dir analysis/
python3 $K/kicad/scripts/analyze_gerbers.py gerbers/ --analysis-dir analysis/
```

Each writes into a dated run under `analysis/`. Run a script with `--schema`
before extracting fields by hand. `kicad-happy/kicad/guide.md` covers the
review checklist, schematic-to-PCB cross-checks, thermal, what-if, and diff
tools; its `references/` hold the detail.

## Simulating

After the schematic analyzer,
`python3 $K/spice/scripts/simulate_subcircuits.py --analysis-dir analysis/`
builds and runs ngspice testbenches for the detected filters, dividers, op-amp
stages, and crystal circuits, and reports pass/warn/fail against the calculated
values. `kicad-happy/spice/guide.md` covers parasitic extraction and Monte Carlo
runs.

## JLCPCB

`references/jlcpcb.md` covers basic and extended parts, BOM and CPL columns,
rotation offsets, design-rule limits, and ordering.
`python3 $K/bom/scripts/translate_bom_pnp.py {bom,pnp} in.csv -o out.csv`
converts BOM and placement files to JLCPCB's columns.

## Vendored guides

In the guides, `<skill-path>` means `kicad-happy/kicad` or `kicad-happy/spice`,
and `skills/<name>/` paths resolve under `kicad-happy/`. They mention other
kicad-happy skills (bom, emc, datasheets, digikey, mouser, lcsc) that are not
installed here; skip those handoffs.
