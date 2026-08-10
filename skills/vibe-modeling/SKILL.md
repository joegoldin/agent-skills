---
name: vibe-modeling
description: Use when the user asks for an OpenSCAD 3D model, parametric design, or wants to iterate on `.scad` files with parameter-driven revisions and multi-view PNG previews.
allowed-tools: Bash(vibecad) Bash(vibecad:*)
---

<!--
Methodology distilled from cjtrowbridge/vibe-modeling
(https://github.com/cjtrowbridge/vibe-modeling). The vibecad CLI is original
to this repo. See ATTRIBUTION.md.
-->

# vibe-modeling — iterating on parametric OpenSCAD models

You build a 3D model by editing OpenSCAD source and a JSON parameter file in lockstep, rendering an STL and a turntable of 16 PNG views after every change. Each revision is a numbered checkpoint. The `vibecad` CLI handles scaffolding, rendering, and revision bookkeeping; you decide what to change.

## When to use

- User asks for a 3D printable part, mechanical bracket, enclosure, fixture, joint, gear, or anything they could 3D-print.
- User pastes a `.scad` file or asks you to modify one.
- User says "model a thing in OpenSCAD", "design a 3D part", "iterate on this CAD file".

If the user wants a high-fidelity industrial CAD model (SolidWorks, Fusion 360), tell them OpenSCAD is parametric-script-based and ask whether that suits their need before proceeding.

## Project layout

```
designs/<name>/
  model.scad         # OpenSCAD source. Parameters come in via -D flags.
  rev_0001.json      # First revision. {"params": {"key": value, ...}, "comment": "..."}
  rev_0002.json      # Subsequent revisions inherit from the previous file.
  output/
    rev_0001.stl     # Mesh for revision 1.
    rev_0001/        # 16 PNG views for revision 1.
      view_01.png ... view_16.png
```

`vibecad` resolves the current revision as the highest-numbered `rev_NNNN.json` in the design dir.

## Loop

1. **Scaffold** (once per design):
   ```bash
   vibecad init <design-name>
   ```
   Creates `designs/<name>/model.scad` (a minimal cube) and `designs/<name>/rev_0001.json` with empty `params`.

2. **Edit** `model.scad` and/or the current `rev_NNNN.json`. Parameters in `rev_NNNN.json` are passed to OpenSCAD as `-D key=value` — reference them as top-level variables in the `.scad` file.

3. **Render**:
   ```bash
   vibecad render <design-name>
   vibecad views <design-name>
   ```
   `render` produces the STL. `views` produces 16 PNGs in a turntable rotation (azimuth 0°→360° at 25° elevation).

4. **Inspect**. Use the `Read` tool on each PNG path under `designs/<name>/output/rev_NNNN/view_NN.png` to see the views.

5. **Revise** before making the next set of changes:
   ```bash
   vibecad revise <design-name>
   ```
   Copies the current `rev_NNNN.json` to `rev_NNNN+1.json`. Edit the new one; the old one is the checkpoint.

## Parameter conventions

Keep `params` flat (no nested objects). OpenSCAD's `-D` accepts numbers, strings, booleans, and JSON arrays/objects, but flat is simpler:

```json
{
  "comment": "Wider mounting plate, deeper bolt holes",
  "params": {
    "plate_width": 80,
    "plate_height": 60,
    "plate_thickness": 4,
    "bolt_diameter": 5,
    "bolt_depth": 12,
    "fillet": 2
  }
}
```

In `model.scad`:
```scad
$fn = 64;
plate_width = 80;       // overridden by -D
plate_height = 60;
plate_thickness = 4;
// ...
difference() {
  cube([plate_width, plate_height, plate_thickness], center = true);
  // bolt holes...
}
```

## When to revise vs edit in place

- **Edit in place** while you're still figuring out what the model should look like and the views are obviously wrong.
- **`vibecad revise`** when the current revision is "good enough to compare against". Each revision is a checkpoint you can show the user side-by-side.

## Failure modes

- **`vibecad render` errors** → OpenSCAD syntax error or missing `$fn`. Print the error and fix the `.scad`.
- **Views look the same** → your model probably isn't centered at origin. Wrap in `translate([-w/2, -h/2, -t/2]) {...}` or use `center = true` on primitives.
- **STL is empty/tiny** → an `intersection()` or `difference()` removed everything. Comment out the subtractions and re-render.

## Security & permissions

`vibecad` only reads/writes under `designs/<name>/`. It does not network. Nothing outside the current working directory is touched.
