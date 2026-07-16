# VINYL ORDERS Board Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use `custom-skills:executing-plans` to implement this plan task-by-task.

**Goal:** Cross-project vinyl procurement board — the Job Board VINYL pill opens a sheet showing every active vinyl job's ordered state, with bulk MARK ORDERED and a per-job ORDER wizard that composes one combined supplier text (cuts per job + tube/bucket consumables) and auto-marks on send.

**Spec (authoritative):** `docs/superpowers/specs/2026-07-16-vinyl-orders-board-design.md` — read it fully before Task 1. Copy strings (§10), decisions (§12), and data semantics (§8) are final; do not re-litigate.

**Architecture:** Pure logic first (aggregator, composer, board model, commit service — all unit-tested, no SwiftUI), then behavior-preserving extractions from `VinylOrderSheet`, then the board sheet + wizard UI on top. Ordered-state truth stays where it lives today: `projects.vinyl_order_*` marker fields (+ two new additive columns `vinyl_color`, `vinyl_po`) and the frozen `DeckMaterialsSnapshot` in each design's drawing JSON, written through the existing `DeckMaterialsOrderService`.

**Tech stack:** SwiftUI + SwiftData (iOS 17.6 target — no iOS-18-only APIs), Supabase via existing repositories/`updateProjectFields`, XCTest.

**Design system:** `ops-design-system/project/DESIGN.md` + `ops-design-system/project/mobile/MOBILE.md`; iOS tokens `OPS/Styles/OPSStyle.swift`. Zero hardcoded values — every color/spacing/radius/font traces to `OPSStyle`. New surfaces reuse shipped patterns: section headers `// TITLE` (`OPSStyle.Typography.metadata` + `secondaryText` + tracking 1.1, see `VinylOrderSheet.section(title:)`), cards `cardBackgroundDark` + `cardBorder` hairline + `cornerRadius`, action bars per `VinylOrderSheet.actionBar`, status dots per `VinylOrderStrip`, ≥44pt targets (`OPSStyle.Layout.touchTargetMin`).

**Required skills for the executing agent:** `ops-design` (read before any view task), `custom-skills:mobile-ux-design` (before Tasks 11–16), `custom-skills:audit-design-system` (Task 16 gate), `superpowers:test-driven-development` (Tasks 2, 6–10), `animation-studio:animation-architect` + `animation-studio:ios-animations` (only if any motion beyond standard transitions is added — spec mandates standard curve + reduced-motion only).

**Working environment:** Dedicated worktree on branch `feat/vinyl-orders-board` (large feature ⇒ branch justified). Recipe:

```bash
cd /Users/jacksonsweet/Projects/OPS/ops-ios
git worktree add .claude/worktrees/vinyl-orders-board -b feat/vinyl-orders-board
cp OPS/Utilities/Secrets.xcconfig .claude/worktrees/vinyl-orders-board/OPS/Utilities/Secrets.xcconfig
```

All `xcodebuild` runs from the worktree MUST pass `-clonedSourcePackagesDirPath .spm-local`. Check `ps aux | grep xcodebuild` before builds (parallel sessions). Preserve CRLF line endings on existing files. Lowercase every generated UUID (`UUID().uuidString.lowercased()`).

**Build/test commands (from worktree root):**

```bash
# Device-target build verification (never simulator for plain build):
xcodebuild -scheme OPS -destination 'generic/platform=iOS' -clonedSourcePackagesDirPath .spm-local build
# Unit tests (simulator):
xcodebuild -scheme OPS -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' -clonedSourcePackagesDirPath .spm-local test -only-testing:OPSTests/<ClassName>
```

**Commits:** atomic per task, conventional messages, no AI attribution. Executors commit their own verified work.

---

## Phase 0 — Schema + sync plumbing

### Task 1: Prod migration — `projects.vinyl_color` / `vinyl_po`

**Files:** none in repo (Supabase MCP migration) + `ops-software-bible` schema section (Task 18 consolidates; note the change now in the working notes).

**Step 1:** Verify columns still absent (they were on 2026-07-16):

```sql
SELECT column_name FROM information_schema.columns
WHERE table_schema='public' AND table_name='projects' AND column_name IN ('vinyl_color','vinyl_po');
```

Expected: 0 rows. If rows exist, STOP and reconcile — another session may have landed it.

**Step 2:** Apply via MCP `apply_migration` (project `ijeekuhbatykdomumfjx`), name `add_projects_vinyl_color_po`:

```sql
ALTER TABLE projects
  ADD COLUMN vinyl_color text NULL,
  ADD COLUMN vinyl_po text NULL;
```

**Step 3:** Re-run the Step 1 query. Expected: 2 rows. Additive + nullable = safe for every shipped build (iOS sync constraint honored).

### Task 2: Marker fields on iOS — model, DTO, processors

**Skills:** `superpowers:test-driven-development`.

**Files:**
- Modify: `OPS/DataModels/Project.swift` (append to `ProjectVinylOrderFields`: `static let color = "vinyl_color"`, `static let po = "vinyl_po"`; add `var vinylColor: String?`, `var vinylPO: String?` to `ProjectVinylOrderMarker` following its existing property style — plain optional `var`s, updated in `init` and any `update(from:)` path).
- Modify: every file `grep -rn "ProjectVinylOrderFields\|vinyl_order_status" OPS --include='*.swift'` surfaces — known set: `OPS/Network/Supabase/DTOs/CoreEntityConverters.swift`, `OPS/Network/Sync/InboundProcessor.swift`, `OPS/Network/Sync/RealtimeProcessor.swift`, `OPS/Utilities/DataController.swift`, `OPS/Utilities/DataActor.swift`. Thread the two new fields everywhere the trio (`status`/`orderedAt`/`orderedBy`) flows: DTO decode, marker upsert, realtime echo.
- Test: extend the existing marker/inbound tests (locate via `grep -rln "ProjectVinylOrderMarker" OPSTests`); if none exist, add `OPSTests/Sync/ProjectVinylOrderMarkerSyncTests.swift` decoding a project DTO payload containing `vinyl_color`/`vinyl_po` and asserting the marker carries them, plus a nil-tolerance case (legacy payload without the keys).

**Steps:** failing test → run (`-only-testing` the test class, expect FAIL) → implement → run (PASS) → device build green → commit `feat(vinyl): sync vinyl_color + vinyl_po on the project order marker`.

---

## Phase 1 — Behavior-preserving extractions

Rules for Tasks 3–5: cut/paste with zero logic edits; change `private` → `internal` only; `VinylOrderSheet` behavior must be byte-identical. Device build green after each. One commit each.

### Task 3: Extract `VinylCutPreview`

**Files:** Create `OPS/DeckBuilder/Views/VinylCutPreview.swift` (move the `VinylCutPreview` struct, its `VinylPreviewEdgeLayout` helper if referenced only by it — check; keep `VinylOrderLayout` constants where they are and reference them). Modify `OPS/DeckBuilder/Views/VinylOrderSheet.swift` (delete moved code). Add the new file to the Xcode project (`OPS.xcodeproj` — coordinate with parallel sessions before touching pbxproj; it is currently modified by a sibling. If `M OPS.xcodeproj/project.pbxproj` WIP persists at execution time, STOP and ask before staging pbxproj hunks — stage only your own additions).

Commit: `refactor(deck): extract VinylCutPreview for reuse`.

### Task 4: Extract `VinylOrderMessageComposeView`

**Files:** Create `OPS/DeckBuilder/Views/VinylOrderMessageComposeView.swift` (struct + Coordinator, internal). Modify `VinylOrderSheet.swift`. Commit: `refactor(deck): extract message compose wrapper`.

### Task 5: Extract catalog color selection helpers

**Files:** Create `OPS/DeckBuilder/Engine/VinylCatalogSelection.swift` — move `restoredCatalogSelection(...)` (it is `static` on the sheet today, `VinylOrderSheet.swift:1425–` call site), `variantDisplayName(_:)`, and the `VinylCatalogProductChoice` tree-building code (locate the builder feeding `catalogProductChoices`). Namespace: `enum VinylCatalogSelection` with pure static functions taking the catalog query results as arrays. Modify `VinylOrderSheet.swift` to call through. If any of these already live engine-side, skip the move for that symbol and just note it.

Commit: `refactor(deck): extract vinyl catalog selection helpers`.

### Task 6: `DeckMaterialsSnapshot.po` + service write-through

**Skills:** `superpowers:test-driven-development`.

**Files:**
- Modify: `OPS/DeckBuilder/Models/DeckMaterials.swift` — add `var po: String?` to `DeckMaterialsSnapshot`. House Codable style EXACTLY: add `case po` to CodingKeys, memberwise init gains `po: String? = nil` **parameter**, custom `init(from:)` gains `self.po = try c.decodeIfPresent(String.self, forKey: .po)`. Never a stored `let po: String? = nil` (drops from init AND decode — documented Swift gotcha).
- Modify: `OPS/DeckBuilder/Services/DeckMaterialsOrderService.swift` — `markOrdered` gains `po: String? = nil` parameter, passes into the snapshot; `clearOrdered` extends its `updateProjectFields` payload with `ProjectVinylOrderFields.color: .null, ProjectVinylOrderFields.po: .null`; `markOrdered`'s marker payload gains `color`/`po` entries (`.string(...)` when non-nil-and-non-empty else `.null`) — **one** `updateProjectFields` call, same atomicity/revert semantics.
- Test: extend `grep -rln "DeckMaterialsOrderService" OPSTests` suite (49 materials tests exist): snapshot round-trips `po`; legacy JSON without `po` decodes nil; `markOrdered` payload contains the five fields; `clearOrdered` nulls all five; revert path unchanged.

**Steps:** failing tests → FAIL → implement → PASS → device build → commit `feat(deck): snapshot + marker carry PO and color through order writes`.

---

## Phase 2 — Pure logic (TDD, no SwiftUI imports)

### Task 7: `VinylConsumablesAggregator`

**Files:** Create `OPS/DeckBuilder/Engine/VinylConsumablesAggregator.swift`, Test `OPSTests/DeckBuilder/VinylConsumablesAggregatorTests.swift`.

**Shape:**

```swift
struct VinylConsumableNeed: Equatable {
    var dripSticks: Int
    var ninetySticks: Int
    var clipSticks: Int
    var glueAreaSqFt: Double
    var glueCoverageSqFt: Double
}

struct VinylConsumablesSuggestion: Equatable {
    var dripTubes: Int
    var ninetyTubes: Int
    var clipTubes: Int
    var glueBuckets: Int
    var totalDripSticks: Int      // support copy "NEED n STICKS"
    var totalNinetySticks: Int
    var totalClipSticks: Int
    var exactGlueBuckets: Double  // support copy, one decimal when fractional
}

enum VinylConsumablesAggregator {
    static func suggest(needs: [VinylConsumableNeed], clipPerTube: Int, flashingPerTube: Int) -> VinylConsumablesSuggestion
}
```

Semantics (spec §7): sticks summed across needs THEN one `ceil` per type (`ceil(Σ/perTube)`, 0 sticks ⇒ 0 tubes); glue `ceil(Σ(area/coverage))` guarding zero/negative coverage (contributes 0); `perTube` clamped ≥1.

**Test cases (write all first, watch them fail):** 4×8 drip sticks @30/tube ⇒ 2 tubes (the batching economics case); exact-boundary 30 ⇒ 1 and 31 ⇒ 2; empty needs ⇒ all zero; mixed glue coverage `(200/400 + 300/400)` ⇒ exact 1.25 ⇒ 1.25 exact / 2 buckets; zero coverage row ignored; clip 50/tube with 50 ⇒ 1, 51 ⇒ 2; perTube 0 input clamps to 1.

Commit: `feat(deck): consumables aggregator — sticks to tubes, glue to buckets`.

### Task 8: `VinylBulkOrderComposer`

**Files:** Create `OPS/DeckBuilder/Engine/VinylBulkOrderComposer.swift`, Test `OPSTests/DeckBuilder/VinylBulkOrderComposerTests.swift`.

**Shape:**

```swift
struct VinylBulkOrderSection: Equatable {
    var po: String
    var color: String                 // "" renders as "FIELD CONFIRM"
    var cutLines: [String]            // pre-rendered via VinylCutListTextTemplate.cutLines, [] for color+PO-only
    var rollsLine: String?            // full-roll jobs: "3 ROLLS @ 75' × 72\"" (mutually exclusive with cutLines)
}

enum VinylBulkOrderComposer {
    static let defaultSectionTemplate = "PO [project]\nColor: [color]\n[cuts]"
    static let sectionTemplateStorageKey = "deckBuilder.vinylOrder.bulkSectionTemplate"
    static let clipPerTubeStorageKey = "deckBuilder.vinylOrder.clipPerTube"
    static let flashingPerTubeStorageKey = "deckBuilder.vinylOrder.flashingPerTube"

    static func compose(
        sections: [VinylBulkOrderSection],
        consumables: VinylConsumablesSuggestion?,   // nil or all-zero ⇒ no tail
        sectionTemplate: String,
        cutSeparator: VinylCutListSeparator
    ) -> String
}
```

Semantics: `[project]` token ⇒ section.po; `[color]` ⇒ color or `FIELD CONFIRM`; `[cuts]` ⇒ rollsLine ?? joined cutLines ?? dropped line entirely (no dangling blank line for color+PO-only sections — trim); reuse `VinylCutListTextTemplate`'s `replacingTokens` conventions (make it internal or mirror it; prefer making the existing one internal). Sections joined by `\n\n`. Consumables tail appended after `\n\n`: lines in order drip/90/clip/glue, `-N tubes drip edge` / `-1 tube 90 flash` / `-N tubes clip` / `-N buckets glue`, singular `tube`/`bucket` at 1, zero lines omitted, no stick lengths (spec §12.6).

**Golden test:** exact Jackson-format output for two cut-list sections + tail (assert the full multiline string verbatim, including `-4 @ 13' 6"` — build cutLines through the real `VinylCutListTextTemplate.cutLines` with a real plan fixture to lock feet-inches formatting). Additional cases: color+PO-only section (no cuts line, no blank artifact); full-roll section uses rollsLine; empty color ⇒ `FIELD CONFIRM`; all-zero consumables ⇒ no tail; singular/plural; custom section template override; `.lines` vs other separators.

Commit: `feat(deck): bulk order message composer`.

### Task 9: `VinylOrdersBoardModel`

**Files:** Create `OPS/Views/JobBoard/VinylOrdersBoardModel.swift`, Test `OPSTests/JobBoard/VinylOrdersBoardModelTests.swift`.

Pure functions over plain inputs (no SwiftData in the core — mirror `VinylTaskFilter`'s testability pattern):

```swift
struct VinylBoardRowInput: Equatable {
    var projectId: String
    var title: String
    var status: Status                      // project status
    var vinylTaskStartDates: [Date?]        // incomplete, non-deleted vinyl tasks only (caller pre-filters by TaskStatus != .completed)
    var hasIncompleteVinylTask: Bool
    var createdAt: Date?
    var ordered: Bool
    var orderedAt: Date?
}

enum VinylOrdersBoardModel {
    static func rows(from inputs: [VinylBoardRowInput]) -> (toOrder: [VinylBoardRowInput], ordered: [VinylBoardRowInput])
}
```

Population rule inside `rows`: keep `status ∈ {.accepted, .inProgress}` AND `hasIncompleteVinylTask`. TO ORDER sort: min non-nil start date ascending, nil-dates after, then `createdAt` descending, then title. ORDERED sort: `orderedAt` descending (nil last).

**Test cases:** every excluded status (rfq/estimated/completed/closed/archived); all-vinyl-tasks-completed drops even when ordered; scheduled-before-unscheduled; unscheduled tie broken by createdAt desc; ordered sorted by date desc.

Commit: `feat(vinyl): board population, grouping and sort model`.

### Task 10: `VinylBulkMarkService`

**Files:** Create `OPS/DeckBuilder/Services/VinylBulkMarkService.swift`, Test `OPSTests/DeckBuilder/VinylBulkMarkServiceTests.swift`.

`@MainActor` struct mirroring `DeckMaterialsOrderService`'s injection style (`userId`, `updateProjectFields` closure). API:

```swift
struct VinylBulkMarkItem {
    var projectId: String
    var design: DeckDesign?               // display candidate, nil when none
    var materials: DeckMaterialsList?     // resolved, nil for degenerate cases
    var settings: DeckMaterialsSettings
    var vinylSettings: VinylOrderSettings
    var color: String?                    // wizard-confirmed or config-restored
    var po: String?                       // wizard-confirmed; nil for plain bulk mark
}

struct VinylBulkMarkOutcome: Equatable {
    var succeeded: [String]               // project ids
    var failed: [String]
}

func markOrdered(items: [VinylBulkMarkItem]) async -> VinylBulkMarkOutcome
```

Per item, serially: design+materials present ⇒ delegate to `DeckMaterialsOrderService.markOrdered(..., po:)` (Task 6 signature); else direct `updateProjectFields` with status/orderedAt/orderedBy(+color/po) — same five-field payload shape. Catch per-item errors into `failed`, continue. No throw.

**Tests (spy `updateProjectFields`):** snapshot path vs marker-only path chosen correctly; color/po land in the same payload as the trio; failure on item 2 of 3 ⇒ outcome `{[1,3],[2]}` and item 2's snapshot reverted (assert via design drawingData); retry of only-failed set works (call again with the failed subset).

Commit: `feat(vinyl): bulk mark service with per-project outcomes`.

---

## Phase 3 — UI

> **Skills for every task below:** `ops-design` (DESIGN.md + MOBILE.md read first), `custom-skills:mobile-ux-design`. Layout reuses shipped patterns only; all tokens `OPSStyle.*`; copy verbatim from spec §10; haptics per spec §11 via the app's existing haptic helpers (`grep -rn "UIImpactFeedbackGenerator\|Haptic" OPS/Utilities` and reuse).

### Task 11: Board sheet skeleton + pill rewiring + inline-mode deletion

**Files:**
- Create: `OPS/Views/JobBoard/VinylOrdersBoardView.swift` — sheet root: title `VINYL ORDERS`, `// TO ORDER` / `// ORDERED` groups from `VinylOrdersBoardModel` (inputs assembled from `@Query` projects/tasks/taskTypes/markers exactly as `JobBoardProjectListView` builds its vinyl dictionaries today — lift that assembly here), glance rows (status dot `successStatus`/`warningStatus` 8pt, title `OPSStyle.Typography` body-bold per JobBoard row convention, right-aligned mono date via `DateHelper.simpleDateString(...).uppercased()`), empty states per spec §10.
- Modify: `OPS/Views/JobBoard/JobBoardView.swift` — VINYL pill action presents the sheet (`.sheet` full-height, `presentationDragIndicator(.visible)`); delete `vinylOrderedFilter` state + the `vinylFilter:` arguments.
- Modify: `OPS/Views/JobBoard/JobBoardProjectListView.swift` — delete `vinylFilter`, `markingVinylProjectIds`, `vinylMarker(for:)`, `canMarkVinyl`, `markVinylOrdered`, the strip rendering, and the vinyl narrowing block; keep `vinylTaskTypeIds` only if the board doesn't subsume it (it should — move, don't duplicate).
- Delete: `VinylOrderStrip` from `OPS/Views/JobBoard/VinylOrderFilter.swift` (KEEP `VinylTaskFilter` in that file).

**Verify:** device build green; sheet opens from pill in simulator; groups populate. Commit: `feat(vinyl): orders board sheet replaces inline job-board filter`.

### Task 12: Expanded row

**Files:** Modify `VinylOrdersBoardView.swift` (+ small `VinylOrderRowDetail` view in the same file or sibling). Tap toggles expansion (standard curve, reduced-motion honored). Content per spec §4: snapshot-first details (resolve design via `DeckDesign.displayCandidate` + decode `orderedMaterials` lazily on expand, memoized in `@State` dictionary keyed by design id + `updatedAt`), fallback marker `vinylColor`/`vinylPO`; `—` for empties; address + client from the project relations the JobBoard cards already read; `OPEN PROJECT` dismisses then calls the `AppState` project-details path (`AppState.swift:210–` — use the existing public entry, do not add a new route); `CLEAR ORDERED` behind confirmation dialog → `DeckMaterialsOrderService.clearOrdered` → row returns to TO ORDER. Light impact haptic on expand.

**Verify:** simulator — expand ordered + unordered rows, clear one, click through to a project. Commit: `feat(vinyl): expandable order record rows with project click-through`.

### Task 13: Selection mode + bulk MARK ORDERED

**Files:** Modify `VinylOrdersBoardView.swift`. `SELECT`/`DONE` header toggle; checkboxes on TO ORDER rows only (44pt targets); bottom action bar per `VinylOrderSheet.actionBar` pattern with `MARK ORDERED (n)` + `ORDER (n)` (ORDER visible only under the wizard gate — `PermissionStore.shared.isFeatureEnabled("deck_builder") && can("deck_builder.view", requiredScope: "assigned") && can("projects.edit")`; MARK ORDERED under `can("projects.edit")`). MARK ORDERED → confirm dialog (spec copy) → assemble `VinylBulkMarkItem`s (display candidate + `DeckMaterialsResolver.resolve` per selected project, config-restored color, nil po) → `VinylBulkMarkService` → result banner `n MARKED · m FAILED` + `RETRY` (failed subset), success/warning haptic.

**Verify:** simulator — mark 2 clean; force a failure (airplane mode) for the partial banner + retry. Commit: `feat(vinyl): multi-select and bulk mark ordered`.

### Task 14: Order wizard — shell + per-job page

**Files:** Create `OPS/DeckBuilder/Views/VinylBulkOrderWizardView.swift` (+ `VinylBulkOrderPageView`). Paged flow (`TabView(.page)` disabled swipe or explicit content switch — pick the simpler that respects reduced motion), header `ORDER · i OF n` + title, `BACK`/`CONFIRM` (medium haptic on confirm). Page state per project: plan recomputed via `VinylCutListEngine` on settings change (mirror `VinylOrderSheet`'s memoized `recomputePlan` discipline); sections `// COLOR` (catalog picker via `VinylCatalogSelection` helpers, free-text fallback, `USE FIELD CONFIRM` secondary; writes through `config` like the sheet's `setVinylCatalogSelection` path — WITHOUT `DeckBuilderViewModel`: mutate `design.drawingData` config directly, matching `DeckMaterialsOrderService`'s accessor discipline), `// PO` (default title), `// CUTS` (cut lines + totals; full-roll rolls line + cutting guide), `VinylCutPreview`, `// LAYOUT` collapsed (direction/pattern/width/seam/wrap session-state; orderMode + roll length write to `materialsSettings`). Degenerate pages per spec §6 copy. CONFIRM requires non-empty color. Cancel-with-confirmation once ≥1 page confirmed.

**Verify:** simulator — 3-job wizard incl. one no-drawing job; direction change recomputes cuts + viz live. Commit: `feat(vinyl): bulk order wizard — per-job review pages`.

### Task 15: Consumables + send page + commit

**Files:** Modify `VinylBulkOrderWizardView.swift` (+ `VinylBulkOrderSendPageView`). `// FLASHING + GLUE` rows (steppers seeded from `VinylConsumablesAggregator.suggest`, support copy, zero ⇒ omitted), `CLIP PER TUBE` / `FLASHING PER TUBE` steppers (@AppStorage keys from Task 8, defaults 50/30, clamp 1–200), `// ORDER MESSAGE` preview (mono, scrollable — recomposed live from confirmed sections + stepper values via `VinylBulkOrderComposer`), section-template editor behind the existing TEMPLATE affordance pattern, `TEXT ORDER` via extracted `VinylOrderMessageComposeView` (COPY ORDER fallback + `COPIED. MARK n ORDERED?` confirm). On `.sent`/copy-confirm: `VinylBulkMarkService.markOrdered` with wizard-confirmed items (color/po/settings/materials from pages), partial-failure banner + retry, ONE summary notification via `NotificationRepository.createNotification` (type `vinyl_bulk_ordered`, title/body per spec §10, `persistent: false`; reuse an existing job-board deep link only if one exists — otherwise omit `actionUrl`), success haptic, dismiss to board.

**Verify:** simulator — full send path (Messages compose appears, cancel leaves nothing marked; send marks all) + copy path. Commit: `feat(vinyl): consumables aggregation, combined supplier text, auto-mark on send`.

### Task 16: Polish gate — design audit + snapshot proofs

**Skills:** `custom-skills:audit-design-system` (mandatory pass), `ops-design`.

**Files:** Create `OPSTests/Views/VinylOrdersBoardSnapshotTests.swift` following the `BooksSnapshotTests` harness (UIHostingController + UIWindow + `drawHierarchy(afterScreenUpdates:)` — never `ImageRenderer`; register fonts in setUp per harness). Render: board with both groups, expanded ordered row, wizard cut page (fixture plan), consumables+send page. PNGs to `docs/artifacts/vinyl-orders/`.

**Steps:** run audit-design-system over the new files (expect zero hardcoded values; fix any) → snapshot tests green → commit `test(vinyl): snapshot proofs + design-system audit fixes`.

---

## Phase 4 — Verification + docs

### Task 17: Full verification

Device build (`generic/platform=iOS`) green; full `OPSTests` sim run green (all pre-existing suites — materials' 49+ included); fix any fallout in place. Commit fixes atomically.

### Task 18: Documentation + handoff

- Bible: update the deck-materials/vinyl section (locate via `grep -rn "vinyl" ops-software-bible/*.md`) — new board, bulk semantics, `projects.vinyl_color`/`vinyl_po`, snapshot `po` field, tube config keys. Same-session rule is non-negotiable.
- End-to-end simulator walkthrough screenshots (board → select → wizard → consumables → Messages → marked board) to `docs/artifacts/vinyl-orders/`.
- Final summary for Jackson: plain-language outcome + proof screenshots. No push/merge without his explicit go.

---

## Execution notes

- Task order is dependency order; Tasks 3–5 and 7–9 are internally parallelizable across agents, but Tasks 6 and 10 depend on 3–5 landing, and Phase 3 depends on all of Phase 2.
- If `VinylOrderSheet` drifted since 2026-07-16 (parallel sessions), re-verify the extraction line ranges before cutting — grep, don't trust the spec's line numbers.
- The spec's §12 decisions are final; if implementation reality contradicts one (e.g., a needed symbol doesn't exist), fix the plan step, not the product decision — and flag it in the handoff summary.
