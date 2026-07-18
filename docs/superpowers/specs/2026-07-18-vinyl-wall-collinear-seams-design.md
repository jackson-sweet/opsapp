# Vinyl Wall-Collinear Seams Design

## Goal

Make every multi-direction vinyl plan physically buildable. When directional changes are unlocked, the planner may change run direction only across a seam that lies on the infinite supporting line of an edge classified as `houseEdge`. Automatic planning, manual LENGTH/WIDTH selection, preview, cut-list output, and order persistence all consume the same validated geometry.

## Operator intent

- **Human:** A deck installer ordering membrane in the field, often in glare and under time pressure.
- **Task:** Unlock turned runs to reduce waste without accepting a transition that cannot be laid against the house.
- **Feel:** Inspection-grade, tactical, and unmistakable.
- **Signature:** Every visible run transition is a continuation of a real house wall.
- **Default:** A single run direction remains valid. Unlocking directions does not force a turn.

## Non-negotiable invariant

For every surface containing more than one run direction:

1. The plan exposes explicit direction regions and explicit transition segments.
2. Each transition segment separates two direction regions.
3. Each transition segment is collinear, within geometry tolerance, with the supporting line of an actual `houseEdge` from that same surface.
4. A plan that needs a turned run to achieve its selected layout but has no legal wall-derived transition is not orderable.
5. No invalid mixed candidate reaches preview, copied text, catalog order creation, project notes, materials snapshots, or MARK ORDERED.

## Geometry architecture

`VinylOrderSurfaceInput.edges` remains the source of wall truth. The planner must never infer a house wall from the outline alone.

For each eligible house edge, the engine:

1. Uses the edge's infinite supporting line with `PolygonSplitter` to divide the original surface polygon.
2. Rejects non-splits and degenerate sides.
3. Filters the returned chord segments by probing both sides of each segment midpoint; only chords with deck interior on both sides are transitions. This removes the actual exterior house boundary while retaining the wall-line extension through the deck.
4. Builds two direction regions in original canvas coordinates.
5. Generates cuts independently inside each region, preserving region identity on every cut.
6. Evaluates legal direction assignments and chooses by purchased cut area, then strip count, while honoring the selected AUTO/LENGTH/WIDTH policy.

The former free rectilinear decomposition may be retained only as a detector that a lower-waste turned layout was requested. It must never emit orderable cuts. If that detector beats the best single-direction plan and no legal house-wall split can produce a turned plan, the plan carries a blocking geometry issue.

## Plan model

- `VinylDirectionRegion`: stable id, polygon, and run angle.
- `VinylDirectionTransition`: stable id, source house-edge id, one or more interior seam segments, and the two adjacent region ids.
- `VinylCutPiece.directionRegionId`: associates cut geometry with the region that produced it.
- `VinylSurfaceCutPlan.directionRegions` and `.directionTransitions`: authoritative preview and validation geometry.
- `VinylPlanIssue.mixedRunMissingHouseAlignedTransition(surfaceId:)`: explicit blocker.
- `VinylCutPlan.issues` and `isOrderable`: one readiness source used by every downstream action.

A single-direction surface has one region, no transition, and no geometry issue.

## Manual and automatic behavior

- **AUTO + unlocked:** Compare the best single-direction candidate with legal wall-split candidates. A legal lower-cost turned candidate may win.
- **LENGTH/WIDTH + unlocked:** Preserve the operator's selected axis policy while evaluating each legal wall-derived region. Unlocking must no longer be silently ignored.
- **Locked:** Preserve current single-direction behavior.
- **LINEAR pattern:** Preserve the existing one-direction visual continuity rule; directional changes remain disabled.

## Preview and interaction

The existing sheet layout stays intact. Mixed cuts are clipped to their explicit region polygons. Transition segments are drawn from plan geometry and visually align with the house-wall supporting line; the UI does not reconstruct or guess them.

If an unlocked turned layout cannot be made legal, the existing validation area displays the OPS product-copy blocker:

`NO HOUSE-WALL SPLIT · LOCK RUN OR MARK WALL`

The create/copy/text/mark actions are disabled or defensively rejected from `plan.isOrderable`. House-wall and transition rendering uses existing OPSStyle semantic tokens, typography, hairlines, and spacing. No new palette, radius, font, or decorative region colors are introduced.

## Data flow and persistence

`DeckBuilderViewModel.vinylOrderSurfaceInputs` already supplies classified edges. `VinylCutListEngine` owns geometry generation and validation. `VinylOrderSheet`, `DeckMaterialsResolver`, and `DeckMaterialsOrderService` may consume only an orderable plan for outbound artifacts or snapshots. The order fingerprint/drift input must include transition geometry and region directions so a seam change invalidates a stale confirmation.

## Verification

Tests must prove:

- A cheaper arbitrary mixed split is rejected in favor of a wall-collinear split.
- Vertical, horizontal, and rotated wall supporting lines produce collinear transitions.
- Exterior wall boundary chords are not mislabeled as transitions.
- A requested turned layout with no legal wall split is blocked.
- AUTO, LENGTH, and WIDTH cannot emit an unmodeled mixed plan.
- Preview consumes explicit region/transition geometry.
- Copy, create, materials snapshot, and MARK ORDERED cannot consume a blocked plan.
- Existing single-direction, angled, offcut, concave, and full-roll behavior remains green.

## Scope exclusions

- No freehand seam placement.
- No new edge classification workflow.
- No database schema change.
- No decorative redesign of Vinyl Order.
- No optimizer-generated seam that lacks a source `houseEdge`.
