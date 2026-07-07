# Deck Materials — Editable Ordered Record + Full-Roll Ordering (P1-3)

**Date:** 2026-07-07
**Status:** Approved by Jackson (both decisions locked in session; spec not user-reviewed per working contract — coherence guaranteed against code).
**Builds on:** `feat/deck-materials-list` (P1-1/P1-2 shipped: materials list + ordered snapshot + drift). Same branch.
**Surface:** ops-ios — Deck tab materials card + Vinyl Order sheet + materials engine + snapshot model.

## 1. Two additions

**A. Editable ordered record.** MARK ORDERED must capture what was *actually* ordered, not only the calculator's suggestion. Today the snapshot freezes the computed numbers with no way to hand-edit them, so a real-world deviation (bought spare sticks, a full roll, rounded glue up) is not recorded.

**B. Full-roll ordering mode.** A toggle in the vinyl flow to buy whole rolls instead of an exact cut list: the app packs the required cuts into the fewest full rolls (roll = roll width × a full-roll length defaulting to **75'**, editable). The itemized cut list stays visible as the on-site cutting guide.

## 2. Approved decisions

| Decision | Ruling |
|---|---|
| Ordered record editability | At MARK ORDERED, a confirm step pre-fills every line with the calculated value; each line is nudgeable. Confirming freezes those (possibly-edited) values as the ordered truth. Re-editable afterward from the ordered card (no clear+redo needed). |
| Drift independence | The "DESIGN CHANGED SINCE ORDER" signal stays tied to the **design geometry** only (the existing `DeckMaterialsDriftKey`). Human quantity edits never flag drift. |
| Full-roll toggle | `CUT LIST ⇄ FULL ROLLS` in the vinyl flow. Roll mode order line = whole rolls; **cut list stays visible below** as the cutting guide (approved). |
| Full-roll length | Default **75'**, editable (per-design, persisted). Distinct from the inventory `receiveRolls` physical-roll default (150') — different concept, do not merge. |
| Roll-count math | Pack the plan's purchased strip lengths into rolls of `fullRollLengthFeet` via first-fit-decreasing bin-packing (a single strip cannot span two rolls). Rolls ordered = bin count. |
| Toggle + roll-length home | Single source of truth persisted on the design (`DeckMaterialsSettings`); editable from BOTH the materials card presets and the Vinyl Order sheet SETTINGS — both read/write the same persisted fields so they never disagree. |
| Sticks / glue | Unaffected by roll mode — full-roll mode changes only how vinyl membrane is purchased. |

## 3. Data model (all additive JSON inside `DeckDrawingData` — zero DB migration)

### 3.1 `VinylOrderMode` (new)
```swift
enum VinylOrderMode: String, Codable, CaseIterable { case cutList, fullRolls }
```

### 3.2 `DeckMaterialsSettings` — add two fields (house-style Codable; `decodeIfPresent ?? default` for each)
```swift
var orderMode: VinylOrderMode = .cutList
var fullRollLengthFeet: Double = 75   // clamp 25...300, step 5
```

### 3.3 `DeckMaterialsSnapshot` — the frozen record becomes the *ordered* values
Add (all additive, `decodeIfPresent` with the calc-derived value as the legacy fallback so any pre-existing snapshot is byte-behavior-unchanged — none exist in prod):
```swift
var orderMode: VinylOrderMode          // default .cutList
var fullRollLengthFeet: Double         // default 75
var orderedRollCount: Int?             // roll mode only; nil in cut-list mode
var isOrderedEdited: Bool              // true when any confirmed value ≠ its calc value at order time
```
The existing display fields (`vinylOrderedSqFt`, `dripSticks`, `clipSticks`, `ninetySticks`, `glueBuckets`) now hold the **confirmed ordered** values (calc value when unedited). `cutGroups` remain the purchased cut list (the cutting guide, unchanged). The geometry `driftKey` is still recomputed live vs. the design — never derived from these editable fields, so edits never flag drift.

## 4. Engine

### 4.1 `VinylRollPacker` (new, pure)
```swift
enum VinylRollPacker {
    /// Fewest rolls of `rollLengthFeet` needed to yield every strip. Each strip
    /// consumes its own length from ONE roll (no strip spans two rolls).
    /// First-fit-decreasing. A strip longer than a roll returns .overlength.
    static func rollsNeeded(stripLengthsFeet: [Double], rollLengthFeet: Double) -> RollPackResult
}
struct RollPackResult: Equatable { let rollCount: Int; let overlengthStripCount: Int }
```
Strip lengths come from `plan.surfaces.flatMap(\.purchasedCuts).map { $0.lengthInches / 12 }`.

### 4.2 `DeckMaterialsList` — add roll fields
```swift
var rollCount: Int          // packed rolls when settings.orderMode == .fullRolls, else 0
var overlengthStripCount: Int
```
`DeckMaterialsEngine.compute` computes these from the plan + `settings.fullRollLengthFeet` when `orderMode == .fullRolls`. Cut-list mode leaves them 0. The `driftKey` is UNCHANGED (geometry only — order mode is a purchasing choice, not a design change, so switching modes must NOT flag drift on an already-ordered design; verify with a test).

## 5. UI

### 5.1 Materials card (`DeckMaterialsSection`)
- **Vinyl block, cut-list mode:** unchanged (`ORDER 260 SQ FT` + cut lines).
- **Vinyl block, full-roll mode:** order line reads `3 ROLLS @ 75' × 72"` (roll count · roll length · roll width, JetBrains Mono); the cut lines stay below as the cutting guide. If `overlengthStripCount > 0`, a warning banner `CUT LONGER THAN ROLL` (a strip exceeds the roll length — raise roll length or re-run direction).
- **Presets (live state):** add, above the stick/coverage steppers, a `ORDER` segmented control `CUT LIST | FULL ROLLS` (reuse the Vinyl Order sheet's segmented pattern), and — only in roll mode — a `ROLL LENGTH` stepper (75', step 5, 25…300). Writes persist to `materialsSettings` like the other presets (light haptic, syncs company-wide).
- **Ordered state:** shows the confirmed ordered values. Roll mode shows `N ROLLS @ L' × W"`. If `isOrderedEdited`, a subtle `ADJUSTED` tag by the ORDERED stamp (tertiaryText). A row action `EDIT ORDER` re-opens the confirm sheet (§5.2) so a correction never requires CLEAR + re-order.

### 5.2 Order-confirm sheet (`VinylOrderConfirmSheet`, new)
Presented by MARK ORDERED whenever a materials list resolves (both entry points — see §6). A compact sheet, OPS section styling:
- Header `// CONFIRM ORDER`, project + deck subtitle.
- One editable line per orderable quantity, **pre-filled with the calc value**, each a stepper/field:
  - Vinyl: `ORDER SQ FT` (cut-list mode) OR `ROLLS` (roll mode), plus a read-only derived echo (`≈ 312 SQ FT` under a roll count).
  - `DRIP STICKS`, `CLIP STICKS`, `90 STICKS`, `GLUE BUCKETS`.
- A `RESET TO CALCULATED` action.
- Primary `CONFIRM ORDERED` (medium haptic) → writes the confirmed values into the snapshot via the service (§6); `isOrderedEdited` = any line ≠ its calc value.
- Copy through `ops-copywriter` register (terse, UPPERCASE labels, no exclamation).

### 5.3 Vinyl Order sheet (`VinylOrderSheet`)
- SETTINGS section: add the same `CUT LIST | FULL ROLLS` segmented control + `ROLL LENGTH` stepper (roll mode only), read/writing `materialsSettings` (single source of truth with the card).
- The cut PREVIEW, `totalOrderedSqFt` summary, CREATE ORDER + NOTE quantity, and the text-message body reflect the mode: in roll mode the order/notes express whole rolls (`3 ROLLS @ 75'`) while the cut list section still lists the strips. (Text template gains a `[rolls]` token; cut-list token behavior unchanged.)

## 6. Mark-ordered flow (`DeckMaterialsOrderService` + both entry points)
- `markOrdered` gains the confirmed ordered values (vinyl sqft OR roll count, four stick/bucket counts, orderMode, fullRollLengthFeet, isOrderedEdited). It stores them as the snapshot's ordered fields; the geometry `driftKey` is still computed from the live materials (unchanged), so drift stays geometry-only.
- **Both entry points present `VinylOrderConfirmSheet` first** (coherence: MARK ORDERED always means "confirm the actual order"):
  - `VinylOrderSheet.setProjectVinylOrdered(true)` → resolve materials → present confirm sheet pre-filled → on confirm call `markOrdered(...)`.
  - `ProjectDetailsViewModel.setVinylOrdered(true)` (Details tab marker): when a materials list resolves, present the same confirm sheet; when none resolves (non-vinyl / no scale) keep today's plain marker toggle (no sheet).
- `EDIT ORDER` from the ordered card re-presents the confirm sheet pre-filled with the current snapshot values (not the calc) and re-writes on confirm; `clearOrdered` unchanged.
- Compensation/order-of-writes (snapshot local-first, then project marker, revert on marker throw) unchanged from P1-2.

## 7. Verification
- **Engine tests:** `VinylRollPacker` (exact-fit, one-over spills a roll, multiple strips FFD, overlength strip flagged, empty → 0); `DeckMaterialsEngine` roll fields (roll mode packs correctly, cut-list mode leaves 0, driftKey identical across cut-list↔roll toggle → mode change never flags drift).
- **Snapshot/order tests:** confirm-with-edits stores edited values + `isOrderedEdited` true; confirm-unchanged → `isOrderedEdited` false and drift-clean at order instant; roll-mode snapshot round-trips `orderedRollCount`/`fullRollLengthFeet`; legacy snapshot (no new keys) decodes with calc-fallback + `.cutList`; EDIT ORDER path rewrites values without touching driftKey.
- **Codable:** `VinylOrderMode` + the two `DeckMaterialsSettings` fields + the four snapshot fields round-trip; partial JSON fills defaults.
- **Snapshot proofs (BooksSnapshotTests-style):** regenerate the four existing states plus new PNGs — full-roll live, full-roll ordered, ordered-adjusted (ADJUSTED tag), the confirm sheet — to `docs/artifacts/deck-materials/`.
- **Build:** device-target `xcodebuild ... -destination 'generic/platform=iOS'` green; tests on the simulator destination green.
- `custom-skills:audit-design-system` clean (zero hardcoded values) before UI is called done.

## 8. Bible
Update `ops-software-bible/07_SPECIALIZED_FEATURES.md` (Deck Materials section): editable ordered record (confirm step, drift stays geometry-only, re-editable), full-roll mode (toggle, 75' default, roll packing, cut list retained), new JSON fields. Same session, own repo commit.

## 9. Out of scope
- Per-strip manual cut-list editing (only the summary quantities are editable).
- Web surfacing (data readable in `drawing_data`).
- Flashing/glue supplier PO integration.
- Changing the CREATE ORDER + NOTE catalog draft beyond reflecting roll-mode quantity/label.
- Wiring roll-mode order into `VinylOffcutInventoryService` receipt (its 150' physical-roll default is separate; no change).
