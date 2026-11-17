# Changelog

Changes made to this copy of the InverseDesignToolbox, with the reason for each and how to use it.
Newest entries at the top. Dates are YYYY-MM-DD.

---

## 2026-11-17 - Several design parts at once (`P.Design.Part = [2 4]`)

### Why
We want to analyse and redesign an assembly with two separate design regions:
outer frame, outer design frame, fixed frame, inner design frame, center holder.
Before this change `P.Design.Part` had to be ONE part number, so only one frame could be cut into bricks.

### What it does now
`P.Design.Part` can be a list of part numbers. All listed parts are cut into bricks on **one shared grid**;
every other part stays solid. A single number works exactly as before.

```matlab
P.Geometry.Files = {'cad/holder.STEP', 'cad/innerDesign.STEP', 'cad/fixedFrame.STEP', ...
                    'cad/outerDesign.STEP', 'cad/outerFrame.STEP'};
P.Design.Type = 'bricks';
P.Design.Part = [2 4];          % inner AND outer design frame; parts 1, 3, 5 stay solid
```

Step 3 then selects bricks in both frames with one rule (brick-center coordinates, meters), e.g. a square ring
with four bridges in each frame:

```matlab
r    = @(x,y) max(abs(x), abs(y));                                   % "square radius" from the center
ring = @(x,y,a1,a2,w) r(x,y) > a1 & r(x,y) < a2 & abs(x) > w & abs(y) > w;
M = idt_select_bricks(bricks, 'RemoveFcn', @(x,y,z) ring(x,y, 12.5e-3, 17.5e-3, 2.5e-3) ...   % inner design frame
                                                  | ring(x,y, 30e-3,   35e-3,   2.5e-3));     % outer design frame
```

The radii above are examples; use the real frame dimensions. A rule that also covers a non-design part
(e.g. the fixed frame between the two design frames) does nothing there, because that part has no bricks.

### How it works
- The grid covers the bounding box of all design parts together (one brick size everywhere).
- A grid cell becomes a brick if at least `MinFill` of it is design-part material and at most `MaxOverlap`
  of it is material of another part (default 0).
- The bricks are handed to the engine in its existing **box mode** (`core/build_model.m`): mesh elements whose
  centroid lies in a brick become switchable.
- Box mode also caught a few elements of non-design parts at part boundaries (59 holder elements in the test).
  These are now forced solid after the model is built, so only the design parts can change.

### Files changed (nothing in `core/`)
| File | Change |
|---|---|
| `functions/model/idt_make_bricks_multi.m` | **new**: builds the shared brick grid for several parts |
| `functions/model/idt_make_bricks.m` | calls `idt_make_bricks_multi` when `P.Design.Part` has more than one entry |
| `functions/model/idt_validate_params.m` | accepts a list of different, valid part numbers |
| `functions/model/idt_assemble_model.m` | keeps elements of non-design parts solid; damper option uses the first design part's material |
| `docs/01_model_setup.md` | documents the list form of `Part` |

### Tested
On the shipped three-part assembly (`03AccHolder` / `02DesignFrame` / `01FixedFrame`), with
`P.Design.Part = [2 3]` (design frame + fixed frame), `Density = 20`:

- Shared grid: 22 x 22 x 2 bricks of 2.5 mm, 800 bricks; parameter check passes.
- Switchable elements: holder 0, design frame 5872, fixed frame 5461.
- A ring cut in each frame: valid design, no floating elements, f1 = 222 Hz (all bricks present: 302 Hz),
  mass 19.9 g (all present: 23.8 g).
- `plot_design` and `idt_plot_brick_selection` work.
- Single-part mode (`P.Design.Part = 2`) gives the same bricks as before (384).

### Limits / not yet tested
- Only the SIM workflow was run. GA and SIMP read the same element-to-brick map and should work, but have
  not been run with several design parts.
- The shape-cutter optimizers (`CASE_GA_Shape_*`, `SIM_ShapeCutters.m`) still take one design part only.
- `export_geometry(..., 'Content', 'design')` uses a single design part and stops with an error for a list;
  `'structure'` and `'bricks'` exports are unaffected.
- Bricks touching supports, the load or output points stay locked solid, as with one design part.
- File order matters: where parts overlap the FIRST part owns the overlap, and face numbers depend on the order.
  Read `P.BC.FixedFaces` again from the step-1 figure for a new assembly.
