# iOS Bug Batch — 2026-08-06 Design

## Status

Approved for implementation by Jackson on 2026-08-06. This document records the internal product and engineering decisions; it is not an execution gate.

## Reports in scope

1. `026891c5` — keyboard DONE accessory needs bottom breathing room.
2. `3f5bca5f` — Trash count contrast and recovery-ledger redesign.
3. `f71113a3` — Pending Work swipe discard and 30-day handling.
4. `fe497fb9` — Charles Krusekopf site visit is locally saved but cloud sync is blocked.
5. `886f1a02` — lead summary is missing above the site-visit checklist.
6. `887722e1` — discard reason cannot be deliberately selected.
7. `967bd985` — Rose Vlaar's matching project is not suggested on conversion.
8. `b5e15fc1` — both volume buttons requested as a bug-report shortcut.
9. `f6bf6b38` — header geometry and actions are inconsistent.
10. Direct report — the Project Details site-visit record overflows, reads like a plain-text comment, and defers photo presentation until the record sheet closes.
11. Direct report — the standalone Project Details status row is oversized; status belongs inside DETAILS.
12. Direct report — the Deck Designer canvas stops above the bottom toolbar instead of continuing to the screen edge.
13. Direct report — Deck Designer length and surface area continue to show whole-design totals while geometry is selected.
14. Direct report — the Lead Details action bar uses a full-height gradient with a visible cutoff instead of reading as floating controls.
15. Direct report — the Lead Details document omits the lead's site address.
16. Direct report — the pinned Lead Details identity header needs a gradient fill while it floats above scrolling content.
17. Direct report — the Lead Details page canvas must use the same pure-black base as its sticky header.

## Product outcome

This batch makes the app more trustworthy under field pressure: locally saved work remains recoverable, destructive actions are deliberate, lead conversion uses information OPS already has, recovery and visit records become fast to scan, project details lose unnecessary acreage, Deck Designer responds to the operator's current selection, and navigation chrome stops shifting between screens.

## Evidence and root causes

### Site-visit sync

Production has one Charles visit shell, not two completed visits. It is still `in_progress`; VISIT failed and COMPLETION is correctly waiting. The exact server rejection was lost because `SiteVisitRepositoryError` does not implement `LocalizedError`. The strongest code- and data-supported cause is a parent-first sync race: a visit parent becomes visible before its checklist children, capture seeds new random-ID rows for the same logical fields, and the server's active `(site_visit_id, field_id)` uniqueness rejects the duplicate.

The repair therefore has two independent requirements:

- preserve the complete typed server detail in Pending Work;
- reconcile checklist rows by their logical identity before retrying, while preserving unsent answers and their durable queue operations.

No automatic discard, server tombstone, or customer-data repair is part of this code change.

### Lead conversion

The Rose lead has no opportunity address, while its linked client and an existing active project both have `2691 Galleon Way`. The sheet performs authoritative conversion preflight before it hydrates the linked-client address; the server therefore returns `address_required` and the existing project remains review-only. The linked-client resolver also promises a repository fallback but only checks SwiftData.

The sheet will resolve the linked client locally, fall back to the tenant-scoped repository, prefill the address, and automatically run the existing address write-back plus authoritative recheck. The server remains the source of truth for which project is matchable.

### Lead discard

A reason row is currently an immediate submit button. Any failed request clears the transient spinner, which looks exactly like the reason could not be selected. The corrected interaction is selection first, then one explicit `APPLY REASON` commitment. Failure keeps the selection, note, sheet, and an inline retryable error visible.

### Site-visit summary

The capture view already owns the bound `Opportunity` and its `aiSummary`; it simply omits that information. A compact summary band will appear after visit identity and immediately before `2 · CHECKLIST`. Empty summaries render nothing.

### Keyboard accessory

The global toolbar is exactly 44pt tall, leaving no visual separation under DONE. The accessory gains a tokenized 52pt band while preserving a minimum 44pt target, one global instance per responder, and the existing dismissal behavior.

### Trash

The selected segment's count currently uses the same ink as its background. Trash becomes a recovery ledger: neutral segmented counts, divider-separated compact rows, a real project/client thumbnail where available, two useful metadata lines, inline RESTORE, and a half-sheet quick view. Restore success is shown only after local persistence succeeds. If a deleted child requires a deleted parent, the quick view names the dependency and offers one explicit combined restore instead of producing an orphan.

### Pending Work

Swipe discard is appropriate only when the item exposes a real, safe discard path. Rows receive explicit capabilities (`canDiscard`, reason, and confirmation requirement) and reuse the established OPS row-action system. Destructive full swipe is forbidden. A partially synced site-visit bundle remains a data deletion, not queue cleanup, so it keeps confirmation and clear scope.

Unsent work is never automatically deleted at 30 days. Age is presented as `STALE · 30D` to prompt review. Automatic cleanup remains limited to independently server-acknowledged temporary artifacts outside the recovery inventory.

### Bug-report trigger

Public iOS APIs do not provide a reliable, App Store-safe global chord for both volume buttons. Private volume observation would change system volume, fail at volume limits/routes, and risk review rejection. The supported design retains shake and routes a visible Settings `REPORT A BUG` action through the same guarded coordinator. The hardware chord itself is not implemented.

### Headers

The inconsistency comes from four independent header families. `OPSScreenHeader` is the canonical base: 52pt nominal content band, left-aligned Cake Mono title, 44pt controls, 20pt icons, and no more than two trailing actions. Root-tab context moves into the first content strip rather than increasing the navigation band. Settings receives a compatibility wrapper first; root tabs, settings/detail screens, and custom sheet headers then migrate in bounded groups. Native navigation bars remain native but use the same title/action semantics.

### Project Details site-visit record

The activity feed already routes site-visit packets into a dedicated `SiteVisitRecordView`, but the packet collapses checklist answers into legacy strings such as `CHECKLIST :: Gate code: 4812`. The record then renders each string as one body paragraph. The photo viewer is presented by the activity-feed parent while the record itself is a child sheet, so iOS queues the full-screen cover until that sheet dismisses.

The record becomes a responsive field document, not a large comment:

- keep a maximum readable content width inside the sheet and place every visit photo in a bounded horizontal evidence rail with a visible next-item peek, so nothing bleeds past compact screens or large Dynamic Type;
- retain every visit photo URL for browsing instead of handing the viewer only the first four previews;
- carry additive structured checklist items (`field_id`, `label`, `value`, `kind`, `artifact_count`) in packet metadata while preserving the existing `checklist` strings and plain-text packet for older clients and OPS-Web;
- parse legacy checklist strings into the same structured row model so old visits improve too;
- render identity, checklist, and notes as one cohesive field document with hairline-separated label/value rows, with long answers wrapping below their labels instead of forcing a wide line;
- keep visit photos as real buttons and present `PhotoCommentViewer` from inside the active record-sheet hierarchy, so the viewer opens immediately above the sheet.

No packet migration is required. Decoding remains tolerant and additive; no captured answer or legacy rendering path is removed.

### Project Details status

Status is one field in the project's identity document, not a standalone section. It becomes the first row inside the existing DETAILS card, using the canonical job-status badge and the existing change-status sheet when editable. Removing the separate block reduces top-of-screen acreage without hiding the control or changing permissions.

### Deck Designer canvas

The 2D toolbar is currently a sibling below the canvas, which shortens the actual drawing viewport. The canvas will own the full available screen and continue beneath the home-indicator region; the contained toolbar becomes a safe-area-aware bottom overlay above it. The toolbar remains fully tappable and visually separated, while the drawing/grid reaches the physical bottom edge. Other bottom canvas overlays reserve the toolbar's interaction zone so controls never stack or steal touches.

### Deck Designer selection metrics

The existing `DeckSelectionReadout` already computes selected surface area and selected edge length from authoritative deck geometry. The top metrics pill will recompute synchronously from `viewModel.selection`: any non-empty selection is selection context, with `—` for a measurement type the selection does not contain (including `—` / `—` for vertex-only selection); only an empty selection shows whole-design area and perimeter. The pill identifies selection context without adding a chart—the selected geometry on the canvas is the primary visualization. Selection changes, multi-select, deselection, edits, undo, and unit-system changes all update the readout without a second cache.

### Lead Details sticky chrome and address

The bottom action pair is already the screen's single floating CTA cluster, but
`StickyActionBar` paints a clear-to-black floor across the whole footer. The
outer 49pt tab-bar clearance is outside that paint, creating the reported hard
cutoff and transparent-looking strip. Remove the floor entirely and lift the
actual button cluster with the one sanctioned mobile floating-CTA elevation
token (`OPSStyle.Layout.floatingElevation`). The controls remain in the same
thumb position, keep their 48pt targets, and float directly over the scrolling
document; form and sheet footers outside Lead Details are unchanged.

The pinned identity header keeps its current content and accessibility grouping
but replaces the solid rectangle with the canonical black-to-clear
`headerFade`. The screen itself removes its stage-colored `Atmosphere` layer and
uses `OPSStyle.Colors.background` as the uninterrupted L0 canvas, so the fade
always resolves into the exact same pure black instead of a differently tinted
page.

The DETAILS document adds one fixed `ADDRESS` row between CLIENT and PROJECT.
It displays the trimmed `Opportunity.address`, wraps long addresses, and shows
the canonical `—` empty value. A populated row is one minimum-44pt button that
opens the existing Apple Maps directions path; it does not introduce another
address store, edit flow, or network lookup.

## Interaction and motion

- All spacing, color, typography, radius, and size values come from `OPSStyle` and the mobile design system.
- Swipe rows reuse the existing gesture implementation; no second gesture engine is introduced.
- The OPS easing token is used; destructive full-swipe is disabled; reduced-motion behavior is preserved.
- Haptics occur only on deliberate selection, restore, discard confirmation, and successful commitment.
- New copy is terse, tactical, sentence-case for explanatory content, and uppercase for authority labels.

## Safety boundaries

- No production customer rows are mutated while implementing or testing this batch.
- Pending Work never silently deletes the only local copy.
- A failed restore cannot show success.
- A server-backed conversion match is never inferred solely from local cache state.
- Site-visit packet metadata changes are additive and legacy packet content remains intact.
- A photo tap is never routed through a presenter hidden behind an active sheet.
- Selected deck measurements come from the same geometry reducer used by the full-screen deck viewer; no independent arithmetic or stale state is introduced.
- Existing active work in the site-visit-checklist-settings and sync-pill/header worktrees must be reconciled before overlapping view/header edits are integrated.
- App Store/device distribution is a separate proof step; a local build does not establish customer-live behavior.

## Verification standard

Each fix starts with a failing test, lands in an atomic commit, and passes its focused suite. The completed batch must also pass a clean generic-device build, focused simulator regression suites, narrow-width and Dynamic Type presentation checks, design-token audit, accessibility checks for 44pt targets and VoiceOver ordering, and production readback of bug metadata after any status update.
