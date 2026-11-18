# Changelog

Changes made to this copy of the InverseDesignToolbox, with the reason for each and how to use it.
Newest entries at the top. Dates are YYYY-MM-DD.

---

## 2026-11-17 - Printability clean-up follows the load path through solid parts (several design parts)

### Why
Every optimizer (GA, SIMP, neural network, static) cleans each layout with `idt_clean_bricks`, by default with
`KeepOnly = 'loadpath'`: a group of face-connected bricks is kept only if **that one group** touches both the
supports and the load. With two design regions separated by a solid part (outer frame | outer design frame |
**fixed frame** | inner design frame | holder) no single group touches both ends:
- inner design frame touches the holder (load) and the fixed frame,
- outer design frame touches the fixed frame and the outer frame (supports).

So the clean-up deleted **both design frames**, and its safety revert did not trigger because the original layout
"failed" the same test. Confirmed on a hand-built case: the old rule kept 0 of 3 groups.

### What it does now
For models with several design parts the clean-up builds a small graph of brick groups and solid pieces
(holder, fixed frame, outer frame, locked bricks):
- `'loadpath'`: a group is kept if it touches two different solid pieces, one of which reaches the supports and the
  other the load through the other groups. A group hanging off a single piece (a dead end) is still removed.
- `'attached'`: a group is kept if it is connected (through pieces and groups) to the supports or the load.
- `'all'`: unchanged.

**Models with one design part use exactly the old rule** (switched by `C.Multi`, set in `idt_clean_setup`).

### Files changed
| File | Change |
|---|---|
| `functions/design/idt_clean_setup.m` | adds `Multi`, `touchPiece` (brick x solid piece), `fixedPiece`, `needPiece` to the setup struct |
| `functions/design/idt_clean_bricks.m` | new local functions `keep_groups_multi` and `reach`; `keep_groups` calls them when `C.Multi` |

### Tested
- Hand-built case (support | g1 | middle | g2 | load, plus a dead-end group g3 on the middle piece):
  old rule kept `[0 0 0]`; new rule keeps `[1 1 0]` with a load path; with g2 removed nothing is kept (no path);
  `'attached'` keeps `[1 1 1]`.
- Three-part assembly with `P.Design.Part = [2 3]` (5 solid pieces): a random layout cleans to a valid design.
- Short GA run (`PopSize` 10, 2 generations): valid result, f1 = 141.7 Hz.
- Short SIMP run + `simp_postprocess` (target 250 Hz): valid result, f1 = 268.1 Hz, 386 of 736 bricks.
- Single-part model: `Multi = 0`, old rule used.

### Check of the other optimizer parts (no change needed)
- Finite-element solves, GA, SIMP, neural-network data and the connectivity test (`nn_validity_setup`) only use
  `model.ElemVar` / `model.VarBricks` and follow paths through solid pieces already.
- Not run: the neural-network optimizer (`CASE_NN_*`), the static optimizers and `idt_polish_bricks`. They use the
  same clean-up and model fields, so they should work.
- SIMP density filter: bricks of the two design frames that lie closer than the filter radius
  (auto: 1.3 x MinWidth x brick edge, about 6.5 mm at 2.5 mm bricks) are smoothed together across the solid frame
  between them. Harmless if the middle frame is wider than that; otherwise set a smaller `H.FilterRadius`.

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
- Only the SIM workflow was run here. (Update, same day: the optimizers' clean-up deleted multi-region designs;
  fixed and GA / SIMP tested, see the entry above.)
- The shape-cutter optimizers (`CASE_GA_Shape_*`, `SIM_ShapeCutters.m`) still take one design part only.
- `export_geometry(..., 'Content', 'design')` uses a single design part and stops with an error for a list;
  `'structure'` and `'bricks'` exports are unaffected.
- Bricks touching supports, the load or output points stay locked solid, as with one design part.
- File order matters: where parts overlap the FIRST part owns the overlap, and face numbers depend on the order.
  Read `P.BC.FixedFaces` again from the step-1 figure for a new assembly.
