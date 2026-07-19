# VINYL ORDERS BOARD — Design Spec

**Date:** 2026-07-16
**Surface:** ops-ios (main app), DeckBuilder package + Job Board
**Status:** Approved by Jackson (this session). Spec is authoritative; he reviews outcomes, not documents.
**Initiative name for spawned tasks:** `VINYL ORDERS`

---

## 1. Summary

A cross-project vinyl procurement board. The existing VINYL pill on the Job Board stops being an inline filter and instead opens a dedicated sheet listing every active job that carries vinyl work, each showing ordered / not-ordered state and the order date at a glance. Rows expand to show the full order record (color, cuts/rolls, PO), address, client, and a click-through to the project. Multi-select supports two bulk actions:

- **MARK ORDERED** — for vinyl ordered outside the app: stamps status + date on all selected jobs (freezing each job's materials snapshot where a deck drawing exists, same as every other mark-ordered entry point).
- **ORDER** — a one-job-at-a-time review wizard (color, PO, cut lines, roll visualization, layout settings), followed by an aggregated consumables step (drip edge / 90 flash / clip in **tubes**, glue in **buckets**), producing one combined supplier text message. On send, every job in the order is marked ordered automatically with color + PO recorded.

## 2. Verified grounding (2026-07-16, against live code + prod DB)

Everything below was read from source or queried live. File paths relative to `ops-ios/`.

| Fact | Source |
|---|---|
| Vinyl-task detection: task-type display contains "vinyl" (case-insensitive substring); `hasVinylTask(taskTypeIds:vinylTaskTypeIds:)` | `OPS/Views/JobBoard/VinylOrderFilter.swift` (`VinylTaskFilter`) |
| VINYL pill: shown when `(selectedSection == .projects || .myProjects) && companyHasVinylWork`; toggles `vinylOrderedFilter` inline mode | `OPS/Views/JobBoard/JobBoardView.swift:312,393` |
| Inline mode renders `VinylOrderStrip` per card + one-tap mark (marker-fields-only write; no snapshot) | `OPS/Views/JobBoard/JobBoardProjectListView.swift`, `VinylOrderFilter.swift` |
| `projects.vinyl_order_status text NULL`, `vinyl_ordered_at timestamptz NULL`, `vinyl_ordered_by uuid NULL` exist in prod; **no** `vinyl_color` / `vinyl_po` yet | live `information_schema` query, project `ijeekuhbatykdomumfjx` |
| `ProjectVinylOrderFields` / `ProjectVinylOrderStatus` (`ordered` / `notOrdered`) / local `ProjectVinylOrderMarker` @Model | `OPS/DataModels/Project.swift:538–` |
| `deck_designs`: `id uuid`, `project_id uuid NULL`, `company_id uuid`, `drawing_data jsonb`, `deleted_at`, `updated_at` | live query |
| Display design per project: `DeckDesign.displayCandidate(in:forProjectId:)` (non-deleted, attached, prefers renderable geometry, most recently updated) | `OPS/DataModels/DeckDesign.swift:97` |
| Pure materials pipeline: `DeckMaterialsResolver.resolve(data:settings:vinylSettings:taskTypeDisplays:vinylHintByProductId:)` → `Resolved{scale, vinylInputs, materials}`; strict-scale nil ⇒ CONFIRM ONE EDGE LENGTH (no materials); vinyl hints via `DeckVinylHintBuilder` | `OPS/DeckBuilder/Engine/DeckMaterialsResolver.swift` |
| `DeckMaterialsSettings` (per-design, in drawing JSON): glue coverage 400 sq ft/bucket, drip stick 8', 90 stick 8', clip stick 10', `orderMode` (.cutList/.fullRolls), `fullRollLengthFeet` 75 | `OPS/DeckBuilder/Models/DeckMaterials.swift` |
| `VinylOrderSettings`: color, catalogItemId/VariantId, roll width 72", seam 1.5", wrap 6", direction (.automatic/.lengthwise/.widthwise), patternMode (.solid/.linear), allowsDirectionalChanges, offcutMinWidth. **Not persisted as a node** — only color + catalog ids restore from `config.vinylColor/vinylCatalogItemId/vinylCatalogVariantId`; direction/width/seam are session-transient (order sheet opens at defaults every time) | `OPS/DeckBuilder/Engine/VinylCutListEngine.swift:36,104`; restore path `VinylOrderSheet.swift:1425–1449` |
| `DeckMaterialsSnapshot` frozen at MARK ORDERED: orderedAt (required), orderedBy, settings, vinylSettings, vinylColor, vinylOrderedSqFt, cutGroups (purchased), driftCutGroups (all), stick/bucket counts, vinylSurfaceCount, orderMode, fullRollLengthFeet, orderedRollCount, isOrderedEdited. Codable house style: explicit CodingKeys + `decodeIfPresent ?? default` per field; never `let x: T? = nil` | `OPS/DeckBuilder/Models/DeckMaterials.swift:85–281` |
| `DeckMaterialsOrderService.markOrdered` writes snapshot local-first, then marker fields via injected `updateProjectFields`; reverts snapshot if the remote write throws. `vinyl_ordered_by` intentionally NULL (FKs `auth.users`, app carries Firebase ids). `editOrder` (quantities only), `clearOrdered` (snapshot + marker, with revert) | `OPS/DeckBuilder/Services/DeckMaterialsOrderService.swift` |
| Supplier text templates: `VinylCutListTextTemplate.render`, defaults `"Color: [color]\n[cuts]"` + `"-[quantity] @ [length]"`, `[project]` token supported, feet-and-inches via `vinylFormatFeetAndInches` (`-4 @ 13' 6"`), separators enum; @AppStorage keys `deckBuilder.vinylOrder.cutListTemplate/cutTemplate/cutSeparator` | `VinylCutListEngine.swift:296–423` |
| Message send: `VinylOrderMessageComposeView` (MFMessageComposeViewController wrapper, completion callback), `UIPasteboard` copy fallback; action label `TEXT CUTS` / `COPY CUTS` | `VinylOrderSheet.swift:1049–,2204–2237` |
| Roll visualization: `VinylCutPreview` (Canvas, input = `VinylCutPlan`), currently `private` in the order sheet | `VinylOrderSheet.swift:1711` |
| Catalog color: `VinylCatalogProductChoice` tree built from CatalogItem/Variant/OptionValue/StockUnit @Query sets; `variantDisplayName`; free-text fallback (`FIELD CONFIRM` placeholder) | `VinylOrderSheet.swift` |
| `CREATE ORDER + NOTE` (single-project): drafts a `catalog_orders` row + order item + project note + notification `catalog_order_drafted` ("// VINYL ORDER DRAFTED", deep link `ops://catalog/orders?tab=draft`); roll-receipt prompt for stock-tracked companies. Gated: deck_builder feature + `deck_builder.view` (assigned) + `projects.edit` + resolved catalog color | `VinylOrderSheet.swift:238–247,1451–1570` |
| Project statuses: `rfq, estimated, accepted, in_progress, completed, closed, archived` | `OPS/DataModels/Status.swift` |
| Project click-through: `AppState` project-details presentation (`showProjectDetails*` path with sheet-reset handling) | `OPS/AppState.swift:210–240` |
| Uppercase-UUID gotcha: lowercase ids at generation; Supabase schema changes additive-only between iOS releases | root + ops-ios CLAUDE.md |

## 3. Entry point & gating

- The VINYL pill (same visibility rule as today: projects/my-projects section + `companyHasVinylWork`) now **presents the board sheet** instead of toggling the inline filter.
- The inline filter mode is **deleted**: `vinylFilter` plumbing in `JobBoardProjectListView`, `VinylOrderStrip`, and the `vinylOrderedFilter` state. `VinylTaskFilter` (pure detection) **stays** — the board uses it. No dead code remains.
- **Viewing** the board: anyone who can see the pill. **MARK ORDERED / CLEAR ORDERED:** `projects.edit` (parity with today's strip and Details-tab marker). **ORDER wizard:** deck_builder feature enabled + `deck_builder.view` (assigned scope) + `projects.edit` (parity with the single-project order sheet's gate). Users lacking the wizard gate still see the ORDER button's absence, not a dead button; MARK ORDERED remains available with `projects.edit` alone.

## 4. The board sheet

**Presentation:** full-height sheet over the Job Board (standard sheet chrome, grabber, title `VINYL ORDERS`).

**Population:** projects in the user's company with `status ∈ {accepted, in_progress}`, non-deleted, carrying ≥ 1 vinyl task that is non-deleted and not `TaskStatus.completed` (`VinylTaskFilter` detection joined with task status; `ProjectTask.status` verified). Quotes (`rfq`, `estimated`) are excluded — you don't buy membrane for a job you haven't won; finished jobs (`completed`, `closed`, `archived`) are history, not procurement. A job whose vinyl tasks are all completed drops off too — the vinyl phase is done, ordered or not. The board is a live procurement console, not an archive.

**Glance data comes from markers only** (`ProjectVinylOrderMarker` + the two new project fields) — zero geometry work at list render. Materials/details resolve lazily on expand and inside the wizard.

**Groups (one scrolling list, no tabs):**
- `// TO ORDER` — not-ordered jobs. Sort: earliest incomplete vinyl task `start_date` ascending; unscheduled after scheduled, then most recently created. The soonest crew-need surfaces first.
- `// ORDERED` — ordered jobs, `vinyl_ordered_at` descending.

**Row (glance):** status dot (`successStatus` green / `warningStatus`), project title, right-aligned `ORDERED JUN 14` (JetBrains Mono date, existing `DateHelper.simpleDateString` uppercased) or `NOT ORDERED`. Rows are scan surfaces — no verbs on them.

**Row (expanded, tap to toggle):**
- Order details when ordered: `COLOR`, `PO`, quantity line (`412 SQ FT` + cut-group lines, or `3 ROLLS @ 75'` in full-roll mode), flashing/glue counts — all from the design's `DeckMaterialsSnapshot` when one exists, else from `projects.vinyl_color` / `vinyl_po` (color/PO only). Empty values render `—`.
- Always: address, client name.
- Actions: `OPEN PROJECT` (dismiss sheet → `AppState` project-details presentation), and on ordered rows `CLEAR ORDERED` (confirmation dialog; runs `DeckMaterialsOrderService.clearOrdered`, which also nulls `vinyl_color`/`vinyl_po` — see §8).
- Haptic: light impact on expand.

**Empty states:** no vinyl jobs at all → `NO ACTIVE VINYL WORK` with one supporting line (`JOBS WITH A VINYL TASK LAND HERE.`). TO ORDER empty while ORDERED has rows → the TO ORDER group shows `ALL VINYL ORDERED`.

**Selection:** `SELECT` in the header enters selection mode (`DONE` exits). Checkboxes appear on **TO ORDER rows only** — ordered rows are not selectable (re-ordering requires CLEAR ORDERED first; double-ordering is structurally impossible). Bottom action bar appears with `MARK ORDERED (n)` and `ORDER (n)`, both ≥ 44 pt targets. ORDER hidden entirely when the wizard gate (§3) fails.

## 5. Bulk MARK ORDERED

For "I already ordered these outside the app."

1. Confirmation dialog: `MARK n ORDERED?` / body `STAMPS TODAY'S DATE ON EVERY SELECTED JOB.` / confirm `MARK ORDERED`, cancel.
2. Serially per project (order = list order):
   - Resolve display design; if one exists, resolve materials via `DeckMaterialsResolver` (design's `materialsSettings`, vinyl settings = defaults + restored color/catalog from config, task-type displays, hint blob).
   - Materials resolved → `DeckMaterialsOrderService.markOrdered(confirmed: nil)` — full snapshot freeze, identical to the Details-tab path. This **upgrades** the old strip behavior (marker-only) to the service's "written the same way regardless of where the tap came from" discipline.
   - No design → marker-fields-only write (status + orderedAt + null orderedBy). Design present but no vinyl set / unconfirmed scale → marker-fields write plus `vinyl_color` when the design config carries a color.
3. Failures are collected, not fatal: successes stay marked. Result banner: `n MARKED · m FAILED` with `RETRY` (retries only the failed set). Success haptic on clean completion, warning haptic on partial.

## 6. ORDER wizard

Entered with the selected TO ORDER jobs, in list order. Paged navigation: `BACK` / `CONFIRM`, header `ORDER · i OF n` + project title. Cancel (swipe-down with confirmation once any step is confirmed) sends nothing and marks nothing; color/settings edits already written to designs persist — identical semantics to fiddling in the order sheet then closing it.

**Per-job page** (extracted review core, not the 2,237-line sheet):
- `// COLOR` — catalog variant picker when the company's vinyl catalog product resolves (`VinylCatalogProductChoice`), else free-text field (`FIELD CONFIRM` placeholder). Pre-filled from design config. CONFIRM requires a non-empty color; a secondary `USE FIELD CONFIRM` affordance sets the literal `FIELD CONFIRM` for order-now-confirm-color-later jobs. Selection writes through to design config (catalog ids + color) exactly like the order sheet does.
- `// PO` — text field, default = project title, editable. Held in wizard state; persisted at send (§8).
- `// CUTS` — cut-group lines (`-9 @ 9'`), total sq ft; in full-roll mode the rolls line (`3 ROLLS @ 75' × 72"`) with the cut list beneath as the cutting guide (existing presentation rules).
- Roll visualization — extracted `VinylCutPreview` fed by the page's live `VinylCutPlan`.
- `// LAYOUT` (collapsed by default) — direction AUTO/LENGTH/WIDTH, pattern SOLID/LINEAR + directional-changes flag, roll width, seam overlap, edge wrap; order mode CUT LIST ⇄ FULL ROLLS + roll length (mode + length write to `materialsSettings` like today; the rest is session state, frozen into the snapshot at send). Edits recompute the plan + viz live.
- **Degenerate pages:** no design / no vinyl surfaces → color + PO only, labeled `NO DECK DRAWING — ORDERS COLOR + PO ONLY.` Unconfirmed scale → color + PO only, labeled `SCALE UNCONFIRMED — CUTS UNAVAILABLE. CONFIRM AN EDGE LENGTH ON THE DECK TAB TO ORDER CUTS.` Both remain orderable (their message section is PO + color).
- Haptic: medium impact on CONFIRM.

## 7. Consumables + send page

**Aggregation (pure, unit-tested):** across all confirmed jobs with resolved materials —
- Drip: `ceil(Σ dripSticks / flashingPerTube)` tubes. 90 flash: `ceil(Σ ninetySticks / flashingPerTube)` tubes. Clip: `ceil(Σ clipSticks / clipPerTube)` tubes. Sticks are summed **before** the single ceil — that is the economics of batching (4 jobs × 8 drip sticks = 32 sticks = 2 tubes of 30, not 4 over-ordered singles).
- Glue: `ceil(Σⱼ (glueAreaSqFtⱼ / glueCoverageⱼ))` buckets — per-job coverage respected, one final round-up.

**Tube configuration:** `CLIP PER TUBE` default **50**, `FLASHING PER TUBE` default **30** (covers drip edge and 90/angle). Steppers inline on the page (clamped 1–200), persisted device-level via @AppStorage (`deckBuilder.vinylOrder.clipPerTube` / `flashingPerTube`) — same persistence class as the message templates. Jackson's numbers are the defaults.

**Rows:** `DRIP EDGE`, `90 FLASH`, `CLIP` (tube steppers, support text `NEED 14 STICKS`), `GLUE` (bucket stepper, support `NEED 6.2 BUCKETS` → formatted per number rules). Any line stepped to 0 is omitted from the message. Suggested counts are starting values — the operator owns the final numbers.

**Message assembly (pure composer, unit-tested):** per-job sections in wizard order, blank line between, consumables tail. Section template default `"PO [project]\nColor: [color]\n[cuts]"` where `[project]` = the job's PO field; cut lines via the user's existing cut template + separator preferences. Full-roll jobs emit their rolls line in place of cut lines. No-cuts jobs emit PO + Color only. Consumables lines: `-2 tubes drip edge`, `-1 tube 90 flash`, `-1 tube clip`, `-7 buckets glue` — singular/plural correct, **no stick lengths on tube lines** (Jackson, 2026-07-16). Zero lines omitted. Template editable via the same editor pattern as the order sheet (new @AppStorage key for the section template; reuses cut template + separator).

Example output (matches Jackson's provided format verbatim):

```
PO 6836 Mark Ln
Color: 68mil Cobblestone
-9 @ 9'
-2 @ 13'

PO 303 Stevens
Color: 68mil Hansberry
-2 @ 26'
-4 @ 13' 6"

-2 tubes drip edge
-1 tube 90 flash
-1 tube clip
-7 buckets glue
```

**Preview:** the assembled text, monospaced, scrollable, above the actions.

**Actions:** `TEXT ORDER` (Messages compose, recipient chosen by the user — no supplier management in this feature) with `COPY ORDER` fallback when the device can't text. On compose result `.sent` → commit (below). `.cancelled`/`.failed` → nothing committed, wizard stays. After COPY → confirmation `COPIED. MARK n ORDERED?` → commit on confirm.

**Commit (serial, per job):**
- Design + materials jobs: `DeckMaterialsOrderService.markOrdered` with a calc-based confirmation from the page's confirmed plan/settings; snapshot carries the page's color and (new field) PO.
- Degenerate jobs: marker-fields write.
- Both: `vinyl_color` + `vinyl_po` written in the **same** `updateProjectFields` call as the status trio (one atomic remote write per job; service revert semantics preserved).
- Partial failures: same collect-and-retry banner as §5.
- One summary notification (not n): type `vinyl_bulk_ordered`, title `// VINYL ORDERED`, body `n PROJECTS · <date>`, non-persistent. Deep link to the Job Board if an existing route supports it; otherwise none (do not invent a routing scheme for this).
- Success notification haptic; wizard dismisses to the board showing the new state.

## 8. Data changes

**Prod migration (additive-only, iOS-release-safe):**

```sql
ALTER TABLE projects
  ADD COLUMN vinyl_color text NULL,
  ADD COLUMN vinyl_po text NULL;
```

Verified absent today. Rides existing RLS/update paths (`updateProjectFields`). Written on every mark/order that knows them; `clearOrdered` nulls them alongside the trio so a cleared job carries no stale record.

**iOS model surface:**
- `ProjectVinylOrderFields` += `color = "vinyl_color"`, `po = "vinyl_po"`.
- `ProjectVinylOrderMarker` += optional `vinylColor: String?`, `vinylPO: String?` (SwiftData lightweight-compatible optionals with the existing model's conventions).
- Sync touchpoints updated wherever the marker trio flows today: `CoreEntityConverters`, `InboundProcessor`, `RealtimeProcessor`, `DataController`/`DataActor` field paths (grep `ProjectVinylOrderFields` for the exhaustive set).
- `DeckMaterialsSnapshot` += `po: String?` — additive, house Codable style (explicit CodingKeys entry, memberwise param with `= nil` default **in the init signature**, `decodeIfPresent`; never a stored `let x: T? = nil`).

**Bible:** update the deck-materials / vinyl-order sections (schema, new board, bulk semantics) in the same implementation session. Non-negotiable.

## 9. Component map

**Extract from `VinylOrderSheet` (behavior-preserving, no logic edits):**
- `VinylCutPreview` → `OPS/DeckBuilder/Views/VinylCutPreview.swift`, internal.
- `VinylOrderMessageComposeView` → own file, internal.
- Catalog choice building + `restoredCatalogSelection` + `variantDisplayName` → shared helper (`VinylCatalogSelection` namespace) consumed by both the order sheet and wizard pages.

**New (DeckBuilder package unless noted):**
- `VinylOrdersBoardView` — the sheet (list, groups, expansion, selection, action bar). Lives with Job Board views since it's presented there; model logic separated.
- `VinylOrdersBoardModel` — pure list building: vinyl-project set, marker join, grouping, sorting, selection eligibility. Unit-tested.
- `VinylBulkMarkService` — orchestrates §5/§7 commits over `DeckMaterialsOrderService` (injected `updateProjectFields` spy-able), collects per-project outcomes. Unit-tested.
- `VinylBulkOrderWizardView` + per-page view — paged review flow.
- `VinylConsumablesAggregator` — pure stick/tube/bucket math. Unit-tested.
- `VinylBulkOrderComposer` — pure message assembly (sections + tail). Unit-tested against Jackson's exact format.

**Deleted:** `VinylOrderStrip`, `vinylFilter` mode plumbing in `JobBoardProjectListView`, `vinylOrderedFilter` state in `JobBoardView` (pill action becomes sheet presentation).

## 10. Copy (product register: terse, tactical, no exclamation points; numbers in mono)

| Context | String |
|---|---|
| Sheet title | `VINYL ORDERS` |
| Groups | `// TO ORDER` · `// ORDERED` |
| Row status | `ORDERED JUN 14` / `NOT ORDERED` |
| Expanded labels | `COLOR` `PO` `ORDERED` `CUTS` `ROLLS` `FLASHING + GLUE` `CLIENT` `ADDRESS` |
| Row actions | `OPEN PROJECT` · `CLEAR ORDERED` |
| Clear confirm | `CLEAR ORDERED?` / `REMOVES THE ORDER RECORD. THE DESIGN IS UNTOUCHED.` |
| Selection | `SELECT` / `DONE` · `MARK ORDERED (3)` · `ORDER (3)` |
| Mark confirm | `MARK 3 ORDERED?` / `STAMPS TODAY'S DATE ON EVERY SELECTED JOB.` |
| Partial failure | `2 MARKED · 1 FAILED` + `RETRY` |
| Empty board | `NO ACTIVE VINYL WORK` / `JOBS WITH A VINYL TASK LAND HERE.` |
| TO ORDER empty | `ALL VINYL ORDERED` |
| Wizard header | `ORDER · 2 OF 4` |
| Wizard actions | `BACK` · `CONFIRM` · `USE FIELD CONFIRM` |
| No-drawing page | `NO DECK DRAWING — ORDERS COLOR + PO ONLY.` |
| No-scale page | `SCALE UNCONFIRMED — CUTS UNAVAILABLE. CONFIRM AN EDGE LENGTH ON THE DECK TAB TO ORDER CUTS.` |
| Consumables | `// FLASHING + GLUE` · rows `DRIP EDGE` `90 FLASH` `CLIP` `GLUE` · support `NEED 14 STICKS` / `NEED 6.2 BUCKETS` (one decimal when fractional) · settings `CLIP PER TUBE` `FLASHING PER TUBE` |
| Message preview | `// ORDER MESSAGE` |
| Send actions | `TEXT ORDER` / `COPY ORDER` |
| Post-copy confirm | `COPIED. MARK 4 ORDERED?` |
| Result | `ORDER SENT · 4 MARKED` |
| Notification | `// VINYL ORDERED` / `4 PROJECTS · JUL 16` |

## 11. Non-functional requirements

- **Perf:** list render is marker-driven, O(projects), zero geometry. Materials resolve lazily (expanded row, wizard page) and memoize per design id + drawing revision. The wizard recomputes one job's plan at a time.
- **Offline:** board reads fully offline (markers are local SwiftData). Mark/order commits require remote success (existing service semantics — local snapshot reverts if the marker write throws); failures surface the retry banner with honest copy, never silent loss.
- **Haptics:** light on expand, medium on CONFIRM / mark commit, success notification on order-sent, warning on partial failure. No spam.
- **Styling:** every value from `OPSStyle` tokens; dates/quantities JetBrains Mono tabular; `—` for empty; 44 pt minimum targets; passes `custom-skills:audit-design-system` before done.
- **Motion:** standard curve only; honors reduced motion.

## 12. Decisions & exclusions (recorded, deliberate)

1. Inline Job Board vinyl filter mode is replaced by the board; its code is deleted, not shadowed.
2. Quotes (`rfq`/`estimated`) never appear — the board is procurement for won work.
3. Ordered rows are not selectable; re-order = CLEAR ORDERED first. Double-ordering impossible by construction.
4. `CREATE ORDER + NOTE` (catalog_orders drafts) and roll receipts remain single-project affordances; the bulk send does **not** fan out draft rows/receipts invisibly. Revisit only on explicit ask.
5. Direction and layout knobs stay session-transient (exact parity with the order sheet today); what's live at send freezes into each snapshot.
6. Consumables aggregate: sticks summed across jobs, then one ceil per type; glue by summed area ratio, one ceil. Message tube lines carry no stick lengths.
7. Bulk send auto-marks on `.sent` (per Jackson); COPY path requires the explicit one-tap confirm.
8. No supplier entity/contact management — recipient picked in Messages, parity with TEXT CUTS.
9. One summary notification for a bulk order, never n.
10. `vinyl_ordered_by` stays NULL on sync (auth.users FK vs Firebase ids — existing constraint); `orderedBy` in the snapshot carries local attribution.

## 13. Testing

- **Unit:** `VinylConsumablesAggregator` (mixed per-design presets, zero/omitted lines, exact ceil boundaries, mixed glue coverage); `VinylBulkOrderComposer` (Jackson-format golden test incl. `13' 6"`, blank-line separation, no-cuts sections, full-roll line, singular/plural, zero-line omission, template overrides); `VinylOrdersBoardModel` (population statuses, vinyl detection join, grouping/sort incl. unscheduled, selection eligibility); `VinylBulkMarkService` (spy `updateProjectFields`: snapshot freeze vs marker-only, color/po in the same write, partial-failure collection, retry set, clear nulls color/po).
- **Snapshot proofs** (existing `UIHostingController` + `drawHierarchy` harness): board glance both groups, expanded ordered row, wizard cut page with viz, consumables page, message preview.
- **Simulator walkthrough:** end-to-end flow screenshots for Jackson's review (board → select → wizard → text → marked board).

## 14. Rollout

Single initiative, phased plan to follow (`custom-skills:writing-plans`). No feature flag: the surface replaces an existing mode behind the same pill, degrades to read-only without permissions, and touches no other flows. Schema migration lands with the feature (additive, safe for shipped builds).
