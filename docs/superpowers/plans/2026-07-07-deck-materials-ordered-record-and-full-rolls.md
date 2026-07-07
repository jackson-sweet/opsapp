# Deck Materials — Ordered Record + Full Rolls (P1-3) Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: `custom-skills:executing-plans` (OPS-tuned). NOT `superpowers:executing-plans`.

**Goal:** (A) Make MARK ORDERED capture the actual ordered quantities (editable, calc pre-filled) as the frozen record; (B) add a `CUT LIST ⇄ FULL ROLLS` ordering mode (roll length default 75', editable) that packs cuts into whole rolls while keeping the cut list as the on-site guide.

**Spec (read first, fully):** `docs/superpowers/specs/2026-07-07-deck-materials-ordered-record-and-full-rolls-design.md`
**Prior context:** `docs/superpowers/specs/2026-07-06-deck-materials-list-design.md` (P1-1/P1-2 — the feature this extends).

**Branch:** work ON `feat/deck-materials-list` (worktree `.claude/worktrees/sleepy-volhard-54fd4b`; if gone, fresh worktree of that branch). Do NOT branch anew. Do NOT push/merge.

**Working rules (binding — identical to P1):**
- Worktree build: ensure `OPS/Utilities/Secrets.xcconfig` present (copy from primary checkout if missing); every xcodebuild gets `-clonedSourcePackagesDirPath .spm-local -derivedDataPath .build-dd`; check `ps aux | grep xcodebuild` first.
- Device build: `-destination 'generic/platform=iOS'` (never simulator for plain build). Tests: `-destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5'`.
- Preserve each file's existing line endings. Codable house style (explicit CodingKeys + `decodeIfPresent ?? default` per field; never `let x: T? = nil`).
- UI work: load `ops-design` + `custom-skills:mobile-ux-design`; any new/changed copy through `ops-copywriter`; run `custom-skills:audit-design-system` before UI is done. Every value an OPSStyle token.
- Commit per task, conventional commits, no AI attribution, stage by name.

Test command template (swap the class):
```bash
xcodebuild test -scheme OPS -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' \
  -clonedSourcePackagesDirPath .spm-local -derivedDataPath .build-dd \
  -only-testing:OPSTests/VinylRollPackerTests 2>&1 | tail -20
```
Expected `** TEST SUCCEEDED **`.

---

## Task 1: `VinylOrderMode` + settings fields + Codable

**Files:** `OPS/DeckBuilder/Models/DeckMaterials.swift`; test `OPSTests/DeckBuilder/DeckMaterialsCodableTests.swift` (extend).

TDD: tests first —
- `DeckMaterialsSettings` defaults: `orderMode == .cutList`, `fullRollLengthFeet == 75`.
- Partial JSON (`{"orderMode":"fullRolls"}`) → mode set, `fullRollLengthFeet` defaults 75, stick/glue defaults intact.
- `VinylOrderMode` raw round-trip.

Implement: add `enum VinylOrderMode: String, Codable, CaseIterable { case cutList, fullRolls }` (own file `OPS/DeckBuilder/Models/VinylOrderMode.swift` or top of DeckMaterials.swift). Add `orderMode`/`fullRollLengthFeet` to `DeckMaterialsSettings` (memberwise init params + CodingKeys + `decodeIfPresent ?? default`). Commit `feat(deck): vinyl order mode + full-roll length setting`.

## Task 2: `VinylRollPacker` (pure engine)

**Files:** create `OPS/DeckBuilder/Engine/VinylRollPacker.swift`; test `OPSTests/DeckBuilder/VinylRollPackerTests.swift`.

Spec §4.1. First-fit-decreasing bin-packing; a strip never spans two rolls.
```swift
struct RollPackResult: Equatable { let rollCount: Int; let overlengthStripCount: Int }
enum VinylRollPacker {
    static func rollsNeeded(stripLengthsFeet: [Double], rollLengthFeet: Double) -> RollPackResult
}
```
Tests (exact): `[]` → (0,0); `[70]` @75 → (1,0); `[40,40]` @75 → (2,0) (can't co-fit 80>75); `[40,30,30]` @75 → (2,0) (40+30, 30); `[70,70,70]` @75 → (3,0); `[80]` @75 → (0,1) overlength; guard `rollLengthFeet<=0` → (0, count). Commit `feat(deck): full-roll bin-packing (VinylRollPacker)`.

## Task 3: engine roll fields + drift invariance

**Files:** `OPS/DeckBuilder/Engine/DeckMaterialsEngine.swift`; test `OPSTests/DeckBuilder/DeckMaterialsEngineTests.swift` (extend).

Add `rollCount: Int` + `overlengthStripCount: Int` to `DeckMaterialsList`. In `compute`, when `settings.orderMode == .fullRolls` pack `plan.surfaces.flatMap(\.purchasedCuts).map { $0.lengthInches/12 }` via `VinylRollPacker` with `settings.fullRollLengthFeet`; else leave 0. **`driftKey` UNCHANGED.**
Tests: roll mode packs expected count for a known rect; cut-list mode → 0; **`compute(...).driftKey` is identical whether `orderMode` is `.cutList` or `.fullRolls`** (mode change must never flag drift). Commit `feat(deck): materials engine emits roll count, drift stays geometry-only`.

## Task 4: snapshot becomes the ordered record

**Files:** `OPS/DeckBuilder/Models/DeckMaterials.swift`; `OPS/DeckBuilder/Services/DeckMaterialsOrderService.swift`; tests `DeckMaterialsCodableTests`, `DeckMaterialsOrderServiceTests`.

Add to `DeckMaterialsSnapshot` (spec §3.3): `orderMode`, `fullRollLengthFeet`, `orderedRollCount: Int?`, `isOrderedEdited: Bool` — memberwise + CodingKeys + `decodeIfPresent` with calc-fallback defaults (`orderMode` → `.cutList`, `fullRollLengthFeet` → 75, `orderedRollCount` → nil, `isOrderedEdited` → false). The existing quantity fields now carry CONFIRMED values.

`DeckMaterialsOrderService.markOrdered` gains a `confirmed:` struct (vinyl sqft OR roll count, drip/clip/90 stick counts, glue buckets, orderMode, fullRollLengthFeet). Build the snapshot from `confirmed` for the display fields; `isOrderedEdited` = any confirmed value ≠ the corresponding `materials` calc value; geometry `driftKey` still from `materials` (unchanged). Keep the P1-2 write order + revert-on-throw.
Tests: confirm-with-edits → edited values stored + `isOrderedEdited` true, drift-clean at order instant; confirm-unchanged → `isOrderedEdited` false; roll-mode round-trips `orderedRollCount`/`fullRollLengthFeet`; legacy snapshot decode (no new keys) → calc-fallback + `.cutList`. Commit `feat(deck): ordered snapshot stores confirmed order + mode`.

## Task 5: `VinylOrderConfirmSheet`

**Files:** create `OPS/DeckBuilder/Views/VinylOrderConfirmSheet.swift`; test `OPSTests/Views/DeckMaterialsSnapshotTests.swift` (add a confirm-sheet snapshot).

**Skills:** `ops-design`, `custom-skills:mobile-ux-design`, `ops-copywriter`; `audit-design-system` before done.
Spec §5.2. Section-styled sheet; header `// CONFIRM ORDER`; one stepper/field per orderable quantity pre-filled with calc; roll mode swaps vinyl line to `ROLLS` with a derived `≈ N SQ FT` echo; `RESET TO CALCULATED`; primary `CONFIRM ORDERED` (medium haptic) returns the confirmed struct. Tokens only. Commit `feat(deck): order-confirm sheet (editable ordered record)`.

## Task 6: materials card — mode display, presets, ordered edits

**Files:** `OPS/Views/Components/Project/Tabs/DeckMaterialsSection.swift`; snapshot tests extend.

**Skills:** `ops-design`, `mobile-ux-design`, `audit-design-system`.
Spec §5.1. Vinyl block roll-mode line `N ROLLS @ L' × W"` + cut lines retained; `CUT LONGER THAN ROLL` banner when `overlengthStripCount>0`. Live presets: add `ORDER` segmented `CUT LIST | FULL ROLLS` + roll-mode `ROLL LENGTH` stepper (writes `materialsSettings`). Ordered state: `ADJUSTED` tag when `isOrderedEdited`; `EDIT ORDER` action re-presents the confirm sheet pre-filled with current snapshot values → rewrites via service (driftKey untouched). Regenerate PNGs: full-roll live, full-roll ordered, ordered-adjusted. Commit `feat(deck): materials card — roll mode, order presets, editable ordered record`.

## Task 7: wire both MARK ORDERED entry points through the confirm sheet

**Files:** `OPS/DeckBuilder/Views/VinylOrderSheet.swift`; `OPS/Views/Components/Project/ProjectDetailsViewModel.swift` (+ its Details-tab view host for sheet presentation).

Spec §6. Both entry points present `VinylOrderConfirmSheet` pre-filled when a materials list resolves; on confirm call `markOrdered(confirmed:...)`. Details-tab: no materials list resolved → keep today's plain marker toggle. Preserve every existing gate/status/haptic. Commit `feat(deck): mark-ordered routes through order-confirm on both entry points`.

## Task 8: Vinyl Order sheet — mode control + roll-aware order/preview/text

**Files:** `OPS/DeckBuilder/Views/VinylOrderSheet.swift`; `OPS/DeckBuilder/Engine/VinylCutListEngine.swift` (text template `[rolls]` token only — additive).

**Skills:** `ops-design`, `audit-design-system`.
Spec §5.3. SETTINGS: add `CUT LIST | FULL ROLLS` segmented + roll-mode `ROLL LENGTH` stepper (read/write `materialsSettings` — single source of truth with the card). Summary/preview/CREATE-ORDER quantity/text body express whole rolls in roll mode (cut list section still lists strips). Add `[rolls]` template token; existing tokens unchanged. Commit `feat(deck): vinyl order sheet — full-roll mode control + roll-aware order`.

## Task 9: full verification + bible

1. Full materials suite green (all classes incl. new: `VinylRollPackerTests`) on simulator → `** TEST SUCCEEDED **`.
2. Device-target build green.
3. Snapshot proofs regenerated (cut-list live/ordered/drift/confirm-dims + full-roll live/ordered + ordered-adjusted + confirm sheet) in `docs/artifacts/deck-materials/`; open them to visually confirm.
4. Bible: update `ops-software-bible/07_SPECIALIZED_FEATURES.md` (editable ordered record, full-roll mode, new JSON fields); commit in that repo.
5. Final plain-language report: what shipped, test/build tails, PNG paths, audit result. Do NOT push/merge.

## Notes for the parent session
- Single executor (files overlap; no parallel fan-out). Spawn title `DECK MATERIALS - P1-3`.
- Out of scope (spec §9): per-strip cut editing, web, flashing/glue PO, inventory roll-receipt wiring, CREATE ORDER + NOTE beyond roll-quantity reflection.
- After it lands: re-run the P1 adversarial-review harness over the new engine/model/order surfaces before reporting done.
