# Field notes (local)

Behavior observed against tscircuit CLI 0.0.2463 (`@tscircuit/capacity-autorouter`
0.0.866) that the upstream references do not cover or get wrong. Each item cost
real time on a board here. Re-check against the installed version before
assuming one still holds.

## Elements and props

- The keepout element is `<keepout>`, not `<pcbkeepout>` (core registers only
  `keepout`). Its `excludeRefs` takes selectors (`".U2"`), not bare refs, and
  without it any pad under the keepout is a placement error.
- `<pcbtrace route>` needs full wire points
  (`{ route_type: "wire", x, y, width, layer }`), not bare `{ x, y }`, and the
  copper carries no net. Prefer `<trace pcbPath>`.
- `<trace pcbPath>` coordinates are relative to the `from` port (pad centre),
  not the component. Getting this wrong lands copper across the chip.
- `<footprint circuitJson={...}>` as a wrapper element silently produced no
  pads. Pass the circuit-json array straight to `footprint={...}` instead.
- Chip ports come from `pinLabels`, not from footprint pads. A chip with a custom
  footprint and no `pinLabels` has no ports, and every trace to it fails. Keys
  must be `pin<N>`; alpha pad names (USB-C `A1`) need a numeric hint added to the
  footprint JSON.
- Two pads sharing a port hint: only one gets the `pcb_port`; the other exports
  to KiCad with no net. Pads that overlap on purpose (same-net copper groups)
  trip the placement check, which then needs `placementDrcChecksDisabled`.
- `<group>` with positioned children still packed them (an "unable to pack"
  error moved parts). A flat board avoided it.
- `doNotPlace` parts still appear in the exported `bom.csv` and
  `pick_and_place.csv`.

## Autorouting

- The local capacity autorouter keeps a fixed gap of roughly 0.115 mm. The
  board's `minTraceToPadEdgeClearance` and friends reach the SimpleRouteJson,
  but the path solver hard-codes `traceMargin` at 0.1 and 0.15.
  `autorouter={{ traceClearance }}` is stored and never read.
  `autorouterEffortLevel` changes search effort, not spacing. Upstream issues on
  DRC clearance in the router pipeline were open as of September 2026.
- `autorouter="auto"` without a platform account resolves to the same local
  solver, not a different engine.
- Pads without a net are not obstacles: the router drops vias on unconnected
  pads. Keepouts fix it.
- `<breakout autorouter="fanout">` aborts on pin-to-`net.X` traces ("does not
  have one component endpoint on every connection"); it wants
  component-to-component traces.
- A trace between a capacitor pin and something else with a manual path
  triggered a "1 mm maximum length" rule and skipped routing for the whole
  board.
- Custom routers go in `tscircuit.config.ts` under
  `platformConfig.autorouterMap` and need `on`, `start`, and `stop` methods;
  core calls `stop()` and discards results if it is missing. Project code that
  imports `@tscircuit/capacity-autorouter` needs a project `node_modules` (a
  symlink to the CLI's tree works offline).

## Exports

- `tsci export -f gerbers` gives gerbers, drills, BOM, and pick-and-place in one
  zip. The pick-and-place rotation is derived per LCSC part from JLCPCB pin-1
  data by the parts engine, which needs network; offline it is the raw rotation.
  Do not bake rotation offsets into footprints on top of it.
- The KiCad export is KiCad 9 format. Polygon pads export as custom pads with an
  anchor that fails KiCad's padstack check. Rect pads are safe.
- KiCad DRC on the export is a good independent gate. `tsci check shorts`
  reports same-net overlapping pads as "U2 <-> U2" shorts and produced one
  2-pixel false positive that KiCad cleared.

## Process

- Routing output changes globally with any parameter or geometry change, so
  treat a DRC-clean result as tied to the exact source and verify after every
  edit.
- JLCPCB's real limit is 0.127 mm clearance. Carrying a 0.15 mm netclass
  preference over from KiCad caused most of the churn.
