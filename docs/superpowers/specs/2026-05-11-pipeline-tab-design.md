# Pipeline Tab Promotion — Design Spec

**Date:** 2026-05-11
**Status:** ⚠️ **BLOCKED** — gated on Books Phase 2 (`2026-05-11-books-tab-phase-2-design.md` + matching plan). See § 0 below before reading further.
**Coordinated with:** Books reconstruction (10:50 spec, bug `1b038315-fb4a-44a1-b118-8e5e67578980`) AND Books Phase 2 (11:09 spec, discovered after this spec was written).
**Implementation strategy:** Books Phase 2 lands first. This spec gets re-verified and rewritten on top of the post-Phase-2 codebase before any tasks execute.
**Bible target:** `ops-software-bible/09_FINANCIAL_SYSTEM.md` § Pipeline / CRM System

---

## 0. ⚠️ BLOCKED — gated on Books Phase 2

This spec was written 2026-05-11 11:01. The Books Phase 2 spec was written 2026-05-11 11:09 (after this one). Neither spec was aware of the other when written.

**Conflict:** Books Phase 2 chunks 2C–2G extend Pipeline DEEPER inside Books — refactoring `PipelineStage` from enum to struct + repository (2C), adding AI lead fields (2D), images + lat/lng (2E), contact import (2G). All chunks modify files under `OPS/Views/Books/Pipeline/` and `PipelineViewModel.swift`.

This spec assumes Pipeline lives as a hardcoded `PipelineStage` enum and Pipeline files live in `Books/Pipeline/`. Both assumptions become **false after Phase 2 lands**.

**User decision (2026-05-11):** Option A — Books Phase 2 lands first. This spec is paused until Phase 2 is merged. When resuming:

1. Verify Phase 2 chunks 2C-2G are in HEAD: look for struct-based `PipelineStage`, AI fields on `Opportunity`, image upload paths, contact import flow.
2. Re-run the verification pass in § 16 against post-Phase-2 code. Most drift items will need updating.
3. Rewrite parts of § 6 and § 10 that reference the enum-based `PipelineStage` and the `PipelineStage+Color` extension (becomes a property of the struct in Phase 2).
4. Update § 11 code touch list — file paths under `Books/Pipeline/` will include Phase 2-added files (AI sheet, image gallery, contact import flow).

**Plan-level issues to fix during resumption:**

- The implementation plan (`2026-05-11-pipeline-tab.md`) contains many `xcodebuild` commands. Per saved feedback "Don't run xcodebuild," these must be removed — user runs builds themselves.
- Plan Task 1 (`PipelineStage+Color.swift` extension) is invalidated by Phase 2's struct refactor.
- Plan Tasks 3-4 (`PipelineViewModel` additions) may overlap with Phase 2 changes.
- Plan Task 13 (`Books/Pipeline/` → `Leads/` move) needs to enumerate Phase 2-added files.

Do NOT resume execution until this section is removed and the spec body has been reconciled against Phase 2's final state.

---

## 1. Purpose

Promote Pipeline (sales / lead management) from a segment inside the Books tab to a **standalone top-level tab** in the OPS iOS app. Pipeline is sales, not money — it does not belong inside Books. This spec covers the new tab's information architecture, primary surface, supporting components, and integration cleanup. The data layer (Opportunity model, repositories, stage transitions) is preserved unchanged.

**Why now:** the user determined Pipeline's placement inside Books is mis-categorized. Books is for money in/out (estimates, invoices, expenses). Pipeline is for leads moving toward close — a different surface, a different mental model, a different daily action.

## 2. Scope

In scope:
- New top-level `LEADS` tab in `MainTabView`
- Redesigned primary surface (carousel of stage pages, redesigned cards, ball-in-court bar)
- New `LeadsHeaderCarousel` (5-card swipeable stat carousel)
- Tab integration: `TabName` enum cleanup, `AppHeader` new case, FAB integration, wizard step ID
- Legacy variable cleanup in `MainTabView` (`pipelineTabIndex` / `isPipelineTab` → renamed to reflect what they actually point to)
- Bible update for the new IA

Explicitly out of scope:
- Data model changes (none — all signals already exist on `Opportunity`)
- Supabase schema changes (additive constraint per saved feedback — none needed)
- The four segment-rebuilds inside Books (parent session owns)
- Web Pipeline (already standalone on web)
- Editing the 8-stage model, win probabilities, or stage-color mapping

---

## 3. Locked decisions

| # | Decision | Choice |
|---|---|---|
| 1 | Tab label | `LEADS` (user-facing). Internal code & bible terminology stays `pipeline`. |
| 2 | Tab icon | SF Symbol `point.3.connected.trianglepath.dotted` (provisional — easy to change later, single string in `MainTabView`). |
| 3 | Tab position | `Home → LEADS → Job Board → Books → Catalog → Schedule → Settings`. Maps to operational flow: hunt → run → bill. |
| 4 | Header | Swipeable 5-card stat carousel (forecast / active / close-rate / velocity / stale-risk). Collapses on scroll, same pattern as `MoneyDashboardHeader`. |
| 5a | Primary view | Horizontal swipeable carousel of stage pages, six active stages by default. Won/Lost expand behind a `CLOSED` chip at the right end of the strip. |
| 5b | Stage strip | Underline indicator + count in JetBrains Mono + 6pt color pip per chip using `PipelineStage.color`. |
| 5c | Ball-in-court bar | Severity-tiered (red/amber/blue rail), breakdown chips (overdue / stale / untouched), $-at-stake. Tap → in-place filter across the carousel. |
| 5d | Lead card redesign | Stage-color leading rail (3pt), Mohave bold title, JetBrains Mono value, urgency marker chip, swipe actions replace inline action chips. |
| 6 | FAB | Universal grouped menu (existing FAB stays). Add Lead surfaces at the top of the MONEY group when the user is on the LEADS tab. |
| 7 | Permission gating | Tab is hidden entirely for users without `pipeline.view`. Matches Catalog's gating pattern. |

---

## 4. Information architecture

### Tab structure

For an admin/office-crew user with all permissions:

```
0   Home               house.fill
1   LEADS              point.3.connected.trianglepath.dotted   ← NEW
2   Job Board          briefcase.fill
3   Books              chart.line.uptrend.xyaxis   (parent session may swap icon)
4   Catalog            square.stack.3d.up.fill    (if catalog.view)
5   Schedule           calendar
6   Settings           gearshape.fill
```

Adaptive ordering:
- Users without `pipeline.view` → LEADS hidden; subsequent indices shift left.
- Users without any Books permission → Books hidden; subsequent indices shift left.
- Field crew typically see: Home / Job Board / Schedule / Settings only.

7 tabs is the maximum supported configuration. `CustomTabBar` distributes icons with `frame(maxWidth: .infinity)` and 28pt icon size. On a 390pt-wide phone with horizontal padding of `OPSStyle.Layout.spacing3` × 2, each tab cell is ~51pt — viable, slightly tight. No new chrome required.

### Permission semantics (verified against codebase 2026-05-11)

- `pipeline.view` → tab visibility AND read access to opportunities (verified in `MainTabView.hasBooksAccess` and bible § 03 data architecture line 1759)
- `pipeline.manage` → stage transitions (advance / mark Won / mark Lost), edit, **AND Add Lead** (verified in `FloatingActionMenu.swift:358`)
- Feature flag `pipeline` (via `permissionStore.isFeatureEnabled("pipeline")`) → master gate for the entire feature, gates Log Activity item in FAB and Add Lead item (verified in `FloatingActionMenu.swift:264` and `:351`)

**There is no `pipeline.create` permission.** A previous draft of this spec referenced one — that was wrong. Add Lead is gated by `pipeline.manage` AND the `pipeline` feature flag.

The new LEADS tab gating becomes: `permissionStore.can("pipeline.view") AND permissionStore.isFeatureEnabled("pipeline")`. If the feature flag is off at the company level, the tab disappears regardless of permission.

Per saved feedback: never filter by role; rely on the permission system exclusively.

### Wizard step ID

New: `welcome_leads` (replaces the legacy `welcome_books`-on-Pipeline expectation). Used by `WizardCurrentTabChanged` notification and `WizardNavigateToTarget` notification handler. Existing `WizardNavigateToTarget`'s "Pipeline" case in `MainTabView` continues to route to the new LEADS tab — semantic name reclaimed.

### Analytics

`TabName` enum at `OPS/Utilities/AnalyticsManager.swift:649`:
- `case pipeline = "pipeline"` already exists. Stops pointing at Books, starts pointing at LEADS (semantic name reclaimed, no event-name change required).
- ADD `case books = "books"` for the actual Books tab analytics.
- Books's `tab_selected` event currently emits `pipeline` (a latent bug). This work fixes that.

---

## 5. Layout spec

### Full-tab anatomy (expanded, before scroll)

```
┌─────────────────────────────────────────────┐
│  AppHeader (.leads)                          │  ~50pt
├─────────────────────────────────────────────┤
│  ┌────────────────────────┐  ← carousel      │
│  │ WEIGHTED FORECAST       │     5 cards,     │
│  │ $42,300                 │     paged        │  ~110pt
│  │ ▲ $4,800 vs LAST 30D    │                  │
│  └────────────────────────┘                  │
│              ● ○ ○ ○ ○                       │
├─────────────────────────────────────────────┤
│  ▌  6 IN COURT · 2 OVERDUE · $42K STAKE      │  44pt (hidden when 0)
├─────────────────────────────────────────────┤
│  ● NEW   ● QUAL   ● QUOT   ● QTD   ● F-UP    │  Stage strip (sticky)
│            ── (selected)                      │  48pt
│  ─────────────────────────────              │
│                                              │
│  ┌─────────────────────────────────┐        │
│  │ ▌ KAREN — KITCHEN REMODEL      │        │
│  │   $14,800 · 4D IN STAGE · STALE │        │  Lead card
│  └─────────────────────────────────┘        │
│  [more cards…]                               │
│                                              │
│  ← swipe between stages →                    │
│                                              │
└─────────────────────────────────────────────┘
                  [FAB]                          ← Universal grouped menu
```

### After scroll (chrome collapsed)

```
┌─────────────────────────────────────────────┐
│  AppHeader (.leads)                          │
├─────────────────────────────────────────────┤
│  ● NEW   ● QUAL   ● QUOT   ● QTD   …         │  Stage strip stays sticky
├─────────────────────────────────────────────┤
│  [lead cards continue scrolling…]            │
└─────────────────────────────────────────────┘
```

Hero carousel + ball-in-court bar collapse together (same `headerCollapsed` preference-key pattern Books uses). Stage strip stays sticky — it's the navigator.

---

## 6. Component specs

### 6.1 `LeadsTabView`

New root view replacing the use of `BooksTabView` for pipeline. Owns the `PipelineViewModel`, the carousel state, and the filter state. **Selected stage lives on the VM** (`PipelineViewModel.selectedStage`, already `@Published`) — not duplicated as local state.

```swift
struct LeadsTabView: View {
    @StateObject private var pipelineVM = PipelineViewModel()
    @State private var headerCollapsed = false
    @State private var inCourtFilterActive = false
    @State private var showClosedStages = false  // controls Won/Lost in carousel rotation

    // body composes:
    //   AppHeader(.leads)
    //   LeadsHeaderCarousel (5 stat cards) — when !headerCollapsed
    //   BallInCourtBar — when count > 0
    //   StageStripView (redesigned, binds to pipelineVM.selectedStage)
    //   TabView(selection: $pipelineVM.selectedStage) — paged
    //       per-stage LeadListPage(pipelineVM, stage:)
}
```

Tracks screen as `Leads` via `trackScreen("Leads")` (was `Books` for the embedded version).

Uses the existing `NavigationStack` wrapper. Deep links to `LeadDetailView` continue to resolve.

### 6.2 `LeadsHeaderCarousel` (new)

Reuses the structural pattern of `SmartStatCarousel` but with Pipeline-specific cards. Two implementation paths:

- **Path A (preferred):** Refactor `SmartStatCarousel` to be config-driven — takes `[StatCard]` array. Both Books and Leads pass their own configs. Reduces duplication, future-proofs for adding more tabs with carousels.
- **Path B (fallback):** Fork into `LeadsStatCarousel` if A turns out to require too much rewiring.

Decision deferred to implementation — measure during planning.

Five cards, in fixed order:

| Card ID | Primary | Sub-line | Tap action |
|---|---|---|---|
| `weightedForecast` | `$42,300` (JetBrains Mono Bold, ~28pt) | `▲ $4,800 vs LAST 30D` colored success/error/tertiary | Open ForecastBreakdownSheet (lists active leads, sorted by weighted value desc) |
| `activePipeline` | `12 LEADS` | Mini stacked horizontal bar — one segment per active stage, width ∝ lead count, fill = `PipelineStage.color` | Jump carousel to the largest-count stage (`selectedStage = largestActiveStage`) |
| `closeRate` | `38%` (or `—` if insufficient data) | `15 WON · 24 LOST · LAST 90D` (or `INSUFFICIENT DATA` if fewer than 5 closed in period) | No-op (future: open period selector) |
| `velocity` | `9D AVG` | `NEW → WON · LAST 90D` + optional `▼ 2D vs PRIOR 90D` | No-op |
| `staleRisk` | `3 LEADS · $18,400` | `OLDEST: 12D IN QUOTING` | Apply stale filter to ball-in-court bar (synthesizes a "stale only" filter equivalent) |

Hidden cards:
- `staleRisk` hides when `staleLeadsCount == 0`.
- `closeRate` shows greyed `INSUFFICIENT DATA` sub-line if `wonCount + lostCount < 5` over the period.
- All other cards always render.

Card chrome:
- 88pt tall, full-width minus `spacing3` horizontal padding.
- `cardBackground` with hairline `cardBorder` stroke, `cardCornerRadius`.
- Page indicator: 5 dots in `secondaryText` (active in `primaryAccent`), 6pt diameter, 8pt apart, centered below carousel, 8pt above ball-in-court bar.
- Paging animation: standard easing, 0.3s. Honors `accessibilityReduceMotion` (fade).
- Light haptic on page-snap commit.

### 6.3 `BallInCourtBar` (new)

In-court definition (all four signals already exist on `Opportunity`):

```
inCourt = opportunities filter {
    $0.assignedTo == currentUserId
    && !$0.stage.isTerminal
    && (
        ($0.nextFollowUpAt != nil && $0.nextFollowUpAt <= now) // overdue
        || $0.isStale                                          // stale
        || $0.stage == .followUp                               // explicit follow-up stage
        || ($0.stage == .newLead && $0.lastActivityAt == nil)  // untouched new
    )
}
```

Bucket assignment (each lead lands in exactly one bucket, highest severity wins):

1. `overdue` if `nextFollowUpAt <= now`
2. `stale` if `isStale` (and not overdue)
3. `untouched` if `stage == .newLead` and `lastActivityAt == nil` (and not stale, not overdue)
4. **Display fallback**: a lead qualifying only via `stage == .followUp` (no overdue / stale / untouched signal) is displayed in the **stale** bucket — the followUp stage itself is the "waiting on you" signal, and amber is the right severity color.

Three breakdown chips ever render: `N OVERDUE`, `N STALE`, `N UNTOUCHED`. The `followUp` fallback rolls into the stale chip's count.

Display rules:

- **Hidden** when `inCourtCount == 0`.
- **Bar** when count > 0: full-width pill, 44pt min height, `cardBackground` + 3pt leading rail.
- **Rail color** (severity tier): `errorStatus` if any overdue; else `warningStatus` if any stale; else `primaryAccent`.
- **Text**: `N IN COURT · [breakdown chips] · $XK STAKE`. Mohave caption UPPERCASE for "IN COURT" / "STAKE"; JetBrains Mono for numerics. `$ STAKE` formatted with `$XXK` ≥10K, `$X,XXX` <10K. Drops `$ STAKE` if total is 0.
- **Breakdown chips**: only non-zero buckets render. Each chip's text is colored to its bucket: overdue → errorStatus, stale → warningStatus, untouched → tertiaryText.

Filter state:

- Tap toggles `inCourtFilterActive`.
- When active, the bar's content changes to: `▌ FILTER ON · N LEADS                CLEAR ✕` (rail color persists).
- While active, each stage page's lead list is filtered through the in-court predicate.
- Empty stage under filter: `NO IN-COURT LEADS IN [STAGE]` centered.
- Filter is **not persisted** across tab exits / app launches. Always cleared on `onAppear`.

Reactivity:

- `PipelineViewModel` exposes:
  - `inCourtCount: Int`
  - `inCourtBuckets: (overdue: Int, stale: Int, untouched: Int)`
  - `inCourtTotalValue: Double`
  - `inCourtOpportunityIds: Set<String>`
- Computed from `opportunities` and `currentUserId`. Updates whenever the published `opportunities` array changes (after stage transitions, marks, etc.).

### 6.4 `StageStripView` redesign

Existing `StageStripView` is preserved structurally but evolves:

- Stage chip layout: `[●color pip] [Stage name] [count]` in a single horizontal row, underline indicator below.
- **Color pip**: 6pt circle, fill = `PipelineStage.color` (from bible, brought into iOS for the first time). 4pt right-margin to the stage name.
- **Count**: switches from `OPSStyle.Typography.smallCaption` (Mohave) to `OPSStyle.Typography.monoCaption` (JetBrains Mono) — assumes a `monoCaption` token exists or is added. **Verify in implementation.** If not, add it.
- **Active stage indicator**: 2pt underline in `primaryAccent`, animated underline-slide on selection change (same `cubic-bezier(0.22, 1, 0.36, 1)` curve as the rest of the app).
- **Active vs terminal**: 6 active stages (NewLead → Negotiation) render at full opacity. After a vertical hairline divider, **`CLOSED` chip** (toggle) — tapping reveals/hides Won + Lost chips. Default: hidden. Persists per-session (not per-app).
- **Bidirectional sync with carousel**: tapping a chip sets `selectedStage`, which triggers the carousel's `TabView(selection:)` to animate. Swiping the carousel updates `selectedStage`, which animates the underline. Single source of truth.
- Light haptic on chip tap (matches existing). No haptic on carousel-driven selection change (avoids haptic spam mid-swipe).

### 6.5 `LeadCardView` redesign

Replaces today's brutal-looking card. Same data contract; new layout.

```
┌────────────────────────────────────────────┐
│▌ KAREN — KITCHEN REMODEL                    │  Title row (Mohave Bold)
│ $14,800     ·   4D IN STAGE   ·   3D OVERDUE│  Metadata row
└────────────────────────────────────────────┘
 ↑                                            ↑
 stage-color rail                          swipe →
                                           (advance / WON / LOST)
```

Specs:

| Element | Token | Notes |
|---|---|---|
| Stage color rail | 3pt wide, leading edge, fill = `opportunity.stage.color` | Bring `PipelineStage.color` into iOS (first use). |
| Card background | `cardBackground` | Hairline stroke `cardBorder`, `cardCornerRadius`. |
| Title | `Typography.bodyBold` | Mohave bold. Fallback: `title` → `contactName` → "UNNAMED LEAD" (UPPERCASE per OPS voice). |
| Value | `Typography.monoBody` (JetBrains Mono) | Tabular-lining, slashed zero. `$14,800` no decimals. Omits if `estimatedValue == nil`. |
| Days-in-stage | `Typography.smallCaption` + `Typography.monoSmallCaption` for the number | `4D IN STAGE` — number in mono, label in Mohave. |
| Urgency chip | `Typography.captionBold` UPPERCASE | One chip max, highest severity: `3D OVERDUE` (errorStatus), `STALE` (warningStatus), `UNTOUCHED` (tertiaryText). Mono number for days in OVERDUE. |
| Padding | `spacing3` all around | 60pt min touch-target height (per ops-ios/CLAUDE.md preference). |

Behavior:

- **Tap card body** → push `LeadDetailView`.
- **Swipe leading → trailing** (left swipe): primary advance action. Reveals one chip: `→ NEXT_STAGE_NAME`. Tap commits `moveToStage(.next)`. Medium haptic on commit.
- **Swipe trailing → leading** (right swipe): reveals two chips in order — `WON` (successStatus background) and `LOST` (no fill, errorStatus border). Tap commits via VM. `LOST` opens `LostReasonSheet` for reason capture. Medium haptic on commit (success notification haptic on WON).
- **Long press** → opens `LeadActionSheet` (same as today's ⋯ button). Provides all actions including advance, mark won, mark lost, move to specific stage, edit, log activity, add follow-up, archive, delete.
- **Inline action chips removed.** Card stays quiet; affordances are revealed contextually.
- Terminal stage cards (Won / Lost) → no swipe actions. Tap → detail only.

Offline state on card:
- **`OpportunityRepository` has no offline queueing** (verified — only `BugReportOfflineQueue` exists in the app). Stage transitions fail with a network error when offline.
- On a failed offline mutation: surface an inline error chip `OFFLINE — TRY AGAIN` on the affected card in `errorStatus`, auto-dismiss after 4s, and revert the optimistic state update. The card stays interactive.
- **No `QUEUED` chip in v1.** A previous draft of this spec specified one — that was wrong; it would require building offline queueing infrastructure as net-new work, out of scope here. Read-side offline still works (cached list renders from `allOpportunities` in memory).
- Future work: building a generic `OpportunityOfflineQueue` analogous to `BugReportOfflineQueue` so transitions queue and replay on reconnect. Out of scope for this spec.

### 6.6 Stage page list

Each page in the `TabView(selection:)` is a `LeadListPage`:

- `ScrollView { LazyVStack(spacing: spacing2) { ForEach … LeadCardView } }`
- `refreshable` triggers `pipelineVM.loadData()`
- Filters: `inCourtFilterActive` is the only active filter for v1. Stage filter is handled by being a per-stage page.
- Padding: `spacing3` horizontal, `spacing3` top, `spacing3` bottom (clears FAB).

Page key = stage rawValue. The carousel renders 6 pages (or 8 when CLOSED is expanded). Off-screen pages use SwiftUI's default lazy rendering.

### 6.7 `AppHeader.leads` case

Add to the `HeaderType` enum in `AppHeader`:

```swift
enum HeaderType {
    case home, settings, schedule, jobBoard, books, catalog
    case leads   // NEW
}
```

Header content for `.leads`:
- Title: `LEADS` (Mohave UPPERCASE)
- Right side: persistent search button (already provided by `MainTabView`'s overlay — no special handling needed).
- No filter / scope / month / review buttons.

### 6.8 FAB integration

`FloatingActionMenu` already keys off `currentTab`. Two changes:

- Replace `@AppStorage("books.selectedSegment")` lookups for "PIPELINE" with a new `isLeadsTab` check passed in from `MainTabView`.
- When `isLeadsTab == true`, the universal grouped menu opens with `Add Lead` ordered first in the existing `MONEY` group. Group name stays `MONEY` (renaming is out of scope and would affect every other tab's FAB).
- When `isLeadsTab == false`, existing ordering rules apply.

The `showingAddLead` state and `AddLeadSheet` presentation already exist — keep as-is.

`FloatingActionMenu` accepts the new flag:

```swift
FloatingActionMenu(
    currentTab: selectedTab,
    hasCatalogAccess: hasCatalogAccess,
    isScheduleTab: selectedTab == scheduleTabIndex,
    isCatalogTab: catalogTabIndex != nil && selectedTab == catalogTabIndex,
    isLeadsTab: leadsTabIndex != nil && selectedTab == leadsTabIndex   // NEW
)
```

### 6.9 `MainTabView` changes

The most central diff. Highlights (full diff produced during implementation planning):

- Add `pipeline.view` to `hasLeadsAccess` (new computed prop). Remove `pipeline.view` from the `hasBooksAccess` disjunction.
- Add `leadsTabIndex: Int?` computed property (after `home`, before `jobBoard`).
- Adjust `jobBoardTabIndex` / `catalogTabIndex` / `scheduleTabIndex` / `settingsTabIndex` to account for the new tab between home and jobBoard.
- **Legacy variable rename**: `pipelineTabIndex` (currently points to Books) → `booksTabIndex`. `isPipelineTab` → `isBooksTab` for the Books-specific branch and `isLeadsTab` for the new tab. This was a latent bug surfaced by this work; the rename clarifies intent.
- Add the new tab to the `tabs` array with `iconName: "point.3.connected.trianglepath.dotted"`, `wizardStepId: "welcome_leads"`.
- Tab content switch: `if selectedTab == leadsTabIndex { LeadsTabView() }` slotted between `HomeView()` and the BOOKS branch.
- `openExpensesObserver`, `openInvoicesObserver` currently use `pipelineTabIndex` (which is Books) for the segment-switch trick. Update those to use `booksTabIndex` instead — semantic fix.
- Tab analytics: `if newValue == leadsTabIndex { return .pipeline }`; for Books: `if newValue == booksTabIndex { return .books }`.
- `booksAutoSkipDestination`: remove the `.pipeline` case (parent session removes `BooksSection.pipeline` entirely; the auto-skip logic for the single-segment case still applies to estimates/invoices/expenses).
- `WizardNavigateToTarget` "Pipeline" case → routes to `leadsTabIndex`.

---

## 7. States

### Tab-level

| State | Display |
|---|---|
| Loading (first run, no cache) | `TacticalLoadingBarAnimated` centered in the lead list area. Header carousel shows skeleton placeholders (`—`). |
| Loading (refresh) | Pull-to-refresh indicator on the active page. Cards stay visible. |
| No leads at all | Header carousel shows zeros (`$0 weighted`, `0 LEADS`). Ball-in-court bar hidden. Stage strip shows zero counts. Active page shows centered: stage icon (Lucide-equivalent SF symbol) + `NO LEADS YET` (bodyBold) + `TAP + TO ADD YOUR FIRST LEAD` (smallCaption secondary, UPPERCASE for the action verb only). |
| Empty stage (others have leads) | `NO LEADS IN [STAGE]` centered. Won: `NO WINS YET — KEEP MOVING`. Lost: `NO LOSSES`. |
| Error loading | Centered: `exclamationmark.triangle` SF symbol (warningStatus) + `COULD NOT LOAD LEADS` (bodyBold) + error detail (smallCaption tertiary) + `TAP TO RETRY` button (primaryAccent). |
| Offline | Cached pages render. Ball-in-court bar shows `OFFLINE` chip appended to the count line. Cards with queued stage transitions show `QUEUED` chip. Stage transitions still attempt and queue via existing `OpportunityRepository` mechanism. |
| Permission lost mid-session | If `pipeline.view` is revoked while on the LEADS tab, `MainTabView`'s existing `onChange(of: permissionStore.permissions)` resets `selectedTab` to 0 (home). Tab disappears from the bar. |

### Filter state (in-court active)

| State | Display |
|---|---|
| Filter on, leads in current stage | Filtered list. Bar shows `▌ FILTER ON · N LEADS    CLEAR ✕`. |
| Filter on, no leads in current stage | `NO IN-COURT LEADS IN [STAGE]` centered. |
| Filter on, no leads anywhere | Bar auto-clears (rare race condition — protect with `inCourtCount == 0 ⇒ filterActive = false`). |

---

## 8. Interactions

### Haptics

| Trigger | Type | Reason |
|---|---|---|
| Tab selection | Light (existing) | Tab switch is transition, not commit. |
| Stage chip tap | Light | Navigation within tab. |
| Stat card swipe (page-snap commit) | Light | Page transition. |
| Stat card tap action | Light | Navigation/action. |
| Ball-in-court bar tap (filter toggle) | Light | State change, not commit. |
| Lead card swipe action commit (advance / WON / LOST) | Medium | Real data commit. |
| Mark WON | Success notification | Major positive milestone. |
| Mark LOST (after reason capture) | Medium | Commit. |
| Long-press card | Medium | Reveal action sheet. |

### Animation

- All state changes use `OPSStyle.Animation.standard` (cubic-bezier 0.22, 1, 0.36, 1) per OPS rules. No spring physics, no bounce.
- Carousel page transition: 0.3s with the standard curve. `TabView` default is close — verify and override if needed.
- Underline indicator slide: same curve, 0.3s.
- Header collapse on scroll: existing pattern from Books (preference key + animated frame).
- Reduce motion: all transitions degrade to fade (opacity-only) when `accessibilityReduceMotion` is true.

### Gestures

- **Horizontal swipe on lead list pages** → carousel page change
- **Vertical scroll on lead list** → list scroll (no conflict — system handles axis priority)
- **Swipe on lead card** → reveal actions (leading: advance; trailing: WON/LOST)
- **Long-press on lead card** → action sheet
- **Tap on card body** → detail
- **Pull-to-refresh** → reload current stage's leads (refreshes whole VM, paginated views update)

---

## 9. Voice / copy

Per OPS voice rules and the `ops-copywriter` skill defaults:

| Surface | Copy |
|---|---|
| Tab label | `LEADS` |
| AppHeader title | `LEADS` |
| Hero card titles | `WEIGHTED FORECAST`, `ACTIVE PIPELINE`, `CLOSE RATE`, `VELOCITY`, `STALE RISK` |
| Ball-in-court bar | `N IN COURT`, `N OVERDUE`, `N STALE`, `N UNTOUCHED`, `$XK STAKE`, `FILTER ON · N LEADS`, `CLEAR ✕` |
| Empty (no leads at all) | bodyBold: `NO LEADS YET` // smallCaption: `TAP + TO ADD YOUR FIRST LEAD` |
| Empty (stage) | `NO LEADS IN QUALIFYING` (etc) |
| Empty (Won) | `NO WINS YET — KEEP MOVING` |
| Empty (Lost) | `NO LOSSES` |
| Empty (filtered) | `NO IN-COURT LEADS IN QUALIFYING` |
| Stale chip | `STALE` |
| Overdue chip | `3D OVERDUE` (number = days, mono) |
| Untouched chip | `UNTOUCHED` |
| Offline chip | `OFFLINE` |
| Queued chip | `QUEUED` |
| Error | `COULD NOT LOAD LEADS` // `TAP TO RETRY` |
| FAB Add Lead label | `ADD LEAD` (already in place) |

Rules respected:
- No emoji. Status uses color + UPPERCASE label.
- No exclamation points. "Hell. yeah." not "Hell yeah!"
- Sentence case for prose content (none here — Pipeline is all authority/labels).
- UPPERCASE for authority labels and chip text.
- Tabular formatting on all numbers (mono font + tabular features).
- `—` for empty numeric state, not "N/A" or "0".

Final copy must pass `ops-copywriter` review before merging.

---

## 10. Design token compliance

All values trace to `OPSStyle.swift`. Zero hardcoded hex / spacing / radius / font.

Token usage map:

| Element | Token |
|---|---|
| Background | `OPSStyle.Colors.background` |
| Card surface | `OPSStyle.Colors.cardBackground` |
| Card stroke | `OPSStyle.Colors.cardBorder` |
| Primary text | `OPSStyle.Colors.primaryText` |
| Secondary text | `OPSStyle.Colors.secondaryText` |
| Tertiary text | `OPSStyle.Colors.tertiaryText` |
| Accent (selected indicator, primary rail) | `OPSStyle.Colors.primaryAccent` |
| Severity: overdue | `OPSStyle.Colors.errorStatus` |
| Severity: stale | `OPSStyle.Colors.warningStatus` |
| Severity: success / WON | `OPSStyle.Colors.successStatus` |
| Stage color (rail, pip, mini-bar) | New: `PipelineStage.color` Swift property mapping bible's hex per stage. First iOS use. |
| Title text | `OPSStyle.Typography.bodyBold` (Mohave) |
| Body text | `OPSStyle.Typography.body` |
| Caption | `OPSStyle.Typography.caption` / `captionBold` / `smallCaption` — **already JetBrains Mono** per the source comments in `OPSStyle.swift:307-310` |
| Mono hero numeric (carousel card primary, e.g. `$42,300`, `38%`) | `OPSStyle.Typography.dataValueLarge` — JetBrains Mono Medium 20pt |
| Mono standard numeric (card values, dollar amounts) | `OPSStyle.Typography.dataValue` — JetBrains Mono 13pt |
| Mono micro (timestamps, deltas, days-in-stage number) | `OPSStyle.Typography.metadata` — JetBrains Mono 11pt |
| Mono category label (`OVERDUE`, `STALE`) | `OPSStyle.Typography.categoryLabel` — JetBrains Mono 11pt |
| Section labels | `OPSStyle.Typography.sectionLabel` |
| Spacing | `OPSStyle.Layout.spacing1..5` |
| Card corner | `OPSStyle.Layout.cardCornerRadius` |
| Touch target min | `OPSStyle.Layout.touchTargetMin` |
| Tab bar icon | `OPSStyle.Layout.tabBarIconSize` (28pt) |
| Animation | `OPSStyle.Animation.standard` |

**Action item for implementation:** the existing `OPSStyle.Typography.caption` / `captionBold` / `smallCaption` are already JetBrains Mono — no new mono tokens needed. Use `dataValueLarge` / `dataValue` / `metadata` / `categoryLabel` for the carousel-card numerics and chip labels per the table above. **A `PipelineStage.color` Swift extension does not exist on iOS** — add one at `OPS/DataModels/Enums/PipelineStage+Color.swift` mapping the bible's hex values (`#BCBCBC` newLead, `#8195B5` qualifying, `#C4A868` quoting, `#B5A381` quoted, `#A182B5` followUp, `#B58289` negotiation, `#9DB582` won, `#6B7280` lost) to a `Color` property. First iOS use of stage colors.

---

## 11. Code touch list

Implementation will touch (not exhaustive; full diff written in implementation plan):

### New files
- `OPS/Views/Leads/LeadsTabView.swift` (root tab view — replaces `BooksTabView` for pipeline)
- `OPS/Views/Leads/LeadsHeaderCarousel.swift` (or `LeadsStatCarousel.swift`)
- `OPS/Views/Leads/BallInCourtBar.swift`
- `OPS/Views/Leads/LeadListPage.swift` (per-stage list inside the TabView)
- `OPS/Views/Leads/Components/LeadCardView.swift` (replaces `Books/Pipeline/LeadCardView.swift`)
- `OPS/Views/Leads/Components/StageStripView.swift` (replaces `Books/Pipeline/StageStripView.swift`)
- `OPS/Views/Leads/Components/ForecastBreakdownSheet.swift` (tap target for forecast stat card)

### Moved files
The `Books/Pipeline/` subdirectory moves wholesale to `Leads/`. Files preserved as-is unless redesigned:
- `AddLeadSheet.swift` → `Leads/AddLeadSheet.swift`
- `EditLeadSheet.swift` → `Leads/EditLeadSheet.swift`
- `LeadDetailView.swift` → `Leads/LeadDetailView.swift`
- `LeadActionSheet.swift` → `Leads/LeadActionSheet.swift`
- `LeadLogActivitySheet.swift` → `Leads/LeadLogActivitySheet.swift`
- `AddFollowUpSheet.swift` → `Leads/AddFollowUpSheet.swift`
- `LostReasonSheet.swift` → `Leads/LostReasonSheet.swift`
- `PipelineSectionView.swift` → **deleted** (replaced by `LeadsTabView` + `LeadListPage`)

### Modified files
- `OPS/Views/MainTabView.swift` — new tab, index recomputation, legacy variable cleanup, analytics fix
- `OPS/Views/Components/Common/AppHeader.swift` — new `.leads` HeaderType case
- `OPS/Views/Components/FloatingActionMenu.swift` — `isLeadsTab` param, Pipeline group ordering when on LEADS tab
- `OPS/Utilities/AnalyticsManager.swift` — add `TabName.books` case; reclaim `.pipeline` semantics
- `OPS/ViewModels/PipelineViewModel.swift` — add `inCourtCount`, `inCourtBuckets`, `inCourtTotalValue`, `inCourtOpportunityIds`, `closeRate`, `avgVelocityDays`, `staleLeadsTotalValue`, `oldestStaleDescription`. Verify what's already there before adding.
- `OPS/ViewModels/MoneyDashboardViewModel.swift` — remove pipeline-specific stats that move to `PipelineViewModel`. Coordinated with parent session.
- `OPS/Views/Books/BooksSection.swift` — `.pipeline` case removed (**parent session owns**).
- `OPS/Views/Books/BooksTabView.swift` — pipeline segment routing removed (**parent session owns**).
- `OPS/Views/Money/Components/MoneyDashboardHeader.swift` and `SmartStatCarousel` — pipeline stats removed (**parent session owns**, or refactored together).
- `OPS/Styles/OPSStyle.swift` — add `monoBody`, `monoCaption`, `monoSmallCaption` if missing.
- New: `OPS/DataModels/Supabase/PipelineStage+Color.swift` extension exposing the bible's stage colors as a Swift `Color` property.

---

## 12. Permission, offline, sync

- **Permission**: `pipeline.view` for tab visibility + view; `pipeline.manage` for FAB Add Lead AND swipe actions (single permission gates both, per `FloatingActionMenu.swift:358`); plus the `pipeline` feature-flag master gate.
- **Offline (read)**: list rendering uses in-memory `allOpportunities` populated by the last successful `fetchAll`. The active stage page and ball-in-court counts render from cache when offline.
- **Offline (write)**: `OpportunityRepository` does NOT queue mutations — confirmed by source inspection. Stage transitions, mark Won, mark Lost, archive, and soft-delete fail with a network error when offline. The card shows a transient `OFFLINE — TRY AGAIN` chip in `errorStatus`, auto-dismissing after 4s. Optimistic UI updates are reverted on failure.
- **Sync**: `OpportunityRepository.fetchAll` is pull-only against `opportunities` table (filters `deleted_at IS NULL` server-side; archived filter happens client-side). No realtime subscription. Pull-to-refresh triggers a fresh fetch.
- **Supabase schema**: verified via MCP — all required columns exist on `public.opportunities` (`assigned_to`, `next_follow_up_at`, `last_activity_at`, `archived_at`, `deleted_at`, `stage`, `company_id`, `estimated_value`, `actual_value`, `win_probability`, `actual_close_date`). **No schema changes required.** Honors the iOS Supabase additive-only constraint.

---

## 13. Integration with parent Books reconstruction

Parent session removes:
- `BooksSection.pipeline` enum case
- The `case .pipeline:` arm in `BooksTabView.contentForSegment`
- Pipeline-related stats from `MoneyDashboardViewModel` / `SmartStatCarousel`

This session adds:
- The new top-level LEADS tab and all surfaces under it
- The legacy variable renames in `MainTabView`
- Analytics enum cleanup

**Coordination contract:**
- Neither session lands changes to `MainTabView.swift` or `BooksSection.swift` unilaterally.
- When both specs are approved and both plans are written, a single coordinated implementation pass produces the diff.
- Acceptance criterion: after both lands, removing the LEADS tab files would not leave dangling references in Books, and removing the Books pipeline-removal would not leave dangling references in MainTabView.

---

## 14. Acceptance criteria

A working implementation must satisfy all of:

### Functional
1. New LEADS tab appears between Home and Job Board for users with `pipeline.view`.
2. Tab is hidden for users without `pipeline.view`. Downstream tab indices shift correctly.
3. Stat carousel shows 5 cards (weighted forecast, active pipeline, close rate, velocity, stale risk). Stale-risk card hides when count is 0.
4. Stage strip shows 6 active stages + CLOSED chip. Tapping CLOSED reveals Won/Lost. Counts and color pips match bible.
5. Carousel swipe between stages works left/right. Underline indicator and selected chip stay in sync (bidirectional).
6. Ball-in-court bar shows when count > 0, hidden when 0. Severity rail color matches highest-severity bucket present. Tap toggles filter; CLEAR clears.
7. Lead cards render with stage-color rail, mono value, single urgency chip per highest severity.
8. Swipe-left on a card reveals `→ NEXT_STAGE` action. Swipe-right reveals `WON` / `LOST`. Long-press opens action sheet.
9. WON commit triggers success haptic; LOST opens reason sheet.
10. Add Lead via FAB still works. AddLeadSheet → success → list refreshes.
11. Deep link to an opportunity from notification rail / push / Spotlight still resolves and pushes `LeadDetailView`.
12. Tab analytics emits `pipeline` for the LEADS tab; emits `books` for the Books tab.
13. Wizard navigation to "Pipeline" target lands on the LEADS tab. `welcome_leads` step ID is reachable.

### Design
1. Every color/spacing/radius/font references an `OPSStyle` token or `PipelineStage.color`. No hardcoded values.
2. All numbers use JetBrains Mono with tabular-lining and slashed zero.
3. No emoji, no exclamation points, no decorative icons.
4. Voice: terse and tactical. All copy passes `ops-copywriter` review.
5. Touch targets ≥ 44pt (prefer 60pt on primary actions per ops-ios/CLAUDE.md).
6. `prefers-reduced-motion` honored — all transitions degrade to fade.
7. Every interactive element has a VoiceOver-readable `accessibilityLabel`. Swipe actions, stage chips, stat carousel cards, and ball-in-court bar all expose their action verbs to assistive tech. Color is never the sole differentiator (severity tiers pair color with UPPERCASE labels).

### Build / test
1. Builds cleanly with `xcodebuild -scheme OPS -destination 'generic/platform=iOS'` (per ops-ios/CLAUDE.md — no simulator).
2. No new compiler warnings.
3. Offline test: load app, kill network, swipe between stages, advance a lead — change is queued, card shows `QUEUED`, syncs on reconnect.
4. Permission test: revoke `pipeline.view` mid-session — tab disappears, selectedTab reset to home.

### Bible
1. `ops-software-bible/09_FINANCIAL_SYSTEM.md` § Pipeline / CRM section is updated to reflect the standalone tab IA, the new view hierarchy, and the new `LeadsTabView` / `BallInCourtBar` / `LeadsHeaderCarousel` components. The "Pipeline iOS Implementation" subsection is rewritten.

---

## 15. Anti-patterns to avoid

- Don't add a Kanban board view toggle. Web is Kanban; phone is carousel-of-lists. Two paradigms, two surfaces.
- Don't put inline action chips back on the card. Quiet cards; swipe actions.
- Don't pulse, shimmer, or animate the ball-in-court bar. Color is the signal.
- Don't show terminal stages (Won/Lost) in the default carousel rotation.
- Don't use emoji glyphs for warnings. Status = color + UPPERCASE chip text.
- Don't show an "ALL CLEAR" zero-state for the ball-in-court bar. Absence IS the signal.
- Don't reuse `MoneyDashboardHeader` verbatim for Pipeline. The metrics differ; the layout shape is what we reuse.
- Don't filter by user role (`user.role ==` or `.in("role", ...)`). Use the permission system exclusively per saved feedback.

---

## 16. Drift catalog (internal review, 2026-05-11)

Per saved feedback "specs are authoritative — verify bible + schema + codebase before commit, state all drift explicitly." This section logs what the first-draft spec got wrong against reality, what was corrected inline, and what the bible needs to absorb.

### Corrected inline (spec body now matches reality)

| Item | First-draft claim | Reality | Status |
|---|---|---|---|
| Add Lead permission | `pipeline.create` | `pipeline.manage` + `pipeline` feature flag (`FloatingActionMenu.swift:358, :351`) | Fixed in §4 and §12 |
| Mono typography tokens | New `monoBody` / `monoCaption` needed | Existing `caption` / `captionBold` / `smallCaption` are already JetBrains Mono per source comments; `dataValueLarge` / `dataValue` / `metadata` / `categoryLabel` exist for hero/standard/micro mono numerics | Fixed in §10 |
| Offline mutation behavior | "Existing OpportunityRepository queueing covers stage transitions"; QUEUED chip on cards | **No offline queueing exists** for opportunities — only `BugReportOfflineQueue` is implemented app-wide. Mutations fail outright when offline | Fixed in §6.5 and §12. QUEUED chip removed; OFFLINE — TRY AGAIN error chip replaces it |
| `LeadsTabView.selectedStage` | Local `@State` | `PipelineViewModel.selectedStage` is already `@Published` — bind to that instead | Fixed in §6.1 |
| `PipelineStage.color` | "Bring it in" (vague) | Concrete hex values from bible documented in §10 action item | Fixed |
| Feature flag layer | Not mentioned | Whole feature is also gated by `permissionStore.isFeatureEnabled("pipeline")` | Added to §4 and §12 |

### Bible drift (separate work — to be fixed when implementation lands)

These are discrepancies between `ops-software-bible/09_FINANCIAL_SYSTEM.md` and the actual iOS code, surfaced during this verification. They are not caused by this spec; they're pre-existing rot. **Pipeline implementation PR should fix them at the same time.**

| Bible section | Bible says | iOS code says | Action |
|---|---|---|---|
| `PipelineViewModel` §1151-1158 | Published: `opportunities`, `searchText`, `error`; computed: `filteredOpportunities`, `weightedPipelineValue`, `activeDealsCount`, `stagesWithCounts`; operations: `loadOpportunities`, `advanceStage`, `createOpportunity`, `updateOpportunity`, `deleteOpportunity` | Actual published: `allOpportunities`, `selectedStage`, `isLoading`, `loadError`; computed: `opportunities(in:)`, `count(in:)`, `activeLeadCount`, `weightedForecastValue`, `staleLeadsCount`, `nextFollowUpDue`, `isPipelineEmpty`; operations: `loadData`, `moveToStage`, `markWon`, `markLost`, `addLead`, `archive`, `softDelete` | Rewrite the `PipelineViewModel` bible subsection during this work's implementation |
| Pipeline stages §66-83 | Stale threshold: "7 days default (configurable per stage in `pipeline_stage_configs`)" | iOS `PipelineStage.staleThresholdDays` hard-codes per-stage values: newLead 3d, qualifying 7d, quoting 5d, quoted 7d, followUp 3d, negotiation 2d | Reconcile: either bring the per-stage thresholds into bible OR move them into `pipeline_stage_configs` (out of scope here — note the drift) |
| Opportunity §85-132 | Doesn't mention `archivedAt` | iOS `Opportunity` model has `archivedAt: Date?` + `isArchived` computed; `OpportunityRepository.archive` writes it | Add `archivedAt` to the bible's Opportunity entity table |
| Tab visibility §1435 | "Tab is visible when the operator has ANY of `pipeline.view` / `finances.view` / `estimates.view` / `expenses.view`" — referring to the Books tab in its current form | Once this spec lands, that disjunction applies ONLY to Books; the new LEADS tab uses `pipeline.view` exclusively (plus the feature flag) | Bible needs rewrite to describe the standalone LEADS tab and the narrower Books gating |
| Pipeline iOS view layer | (No subsection exists today) | New `Leads/` directory with `LeadsTabView`, `LeadsHeaderCarousel`, `BallInCourtBar`, `LeadListPage`, redesigned `LeadCardView` / `StageStripView`, moved sheets | Add new bible subsection during implementation |

### Verification trail

- Codebase reads: `MainTabView.swift`, `BooksTabView.swift`, `PipelineSectionView.swift`, `PipelineViewModel.swift`, `PipelineStage.swift`, `Opportunity.swift`, `OpportunityRepository.swift` (first 50 lines), `LeadCardView.swift`, `StageStripView.swift`, `FloatingActionMenu.swift`, `AppHeader.swift`, `OPSStyle.swift`, `AnalyticsManager.swift`, `SmartStatCarousel.swift`, `CustomTabBar.swift`, `MoneyDashboardHeader.swift`
- Supabase schema: `mcp__supabase__execute_sql` against `public.opportunities` confirmed all required columns and types
- Bible sections: `09_FINANCIAL_SYSTEM.md` §60-200, §1095-1180, §1435; `03_DATA_ARCHITECTURE.md` §1759, §1806, §1994; `02_USER_EXPERIENCE_AND_WORKFLOWS.md` §38, §62, §90

---

## 17. Open questions for future work

- **Stage color migration**: stage colors live in the bible as hex values. Implementation adds them as `Color` extension on `PipelineStage`. Should they also be tokenized in `OPSStyle.Colors` for cross-tab reuse? Defer until a second consumer exists.
- **Period selector**: stat cards have fixed periods (30D / 90D). Future: tappable period selector on the carousel or above it.
- **`SmartStatCarousel` refactor**: config-driven vs forked into `LeadsStatCarousel`. Decision made during implementation.
- **Conversion-to-project flow**: when a lead is marked WON, the conversion-to-project step is currently handled in `LeadDetailView`. Surface it more prominently in the swipe-WON action? Out of scope here.
- **Lead source / priority filters**: not in v1. Search-by-name handled by the universal search button.

---

## 18. References

- Bible: `ops-software-bible/09_FINANCIAL_SYSTEM.md` § Pipeline / CRM System
- Existing data layer: `OPS/DataModels/Supabase/Opportunity.swift`, `OPS/Network/Supabase/Repositories/OpportunityRepository.swift`, `OPS/Network/Supabase/DTOs/OpportunityDTOs.swift`, `OPS/ViewModels/PipelineViewModel.swift`
- Existing scaffold to replace: `OPS/Views/Books/Pipeline/PipelineSectionView.swift`, `OPS/Views/Books/Pipeline/LeadCardView.swift`, `OPS/Views/Books/Pipeline/StageStripView.swift`
- Tab integration target: `OPS/Views/MainTabView.swift`, `OPS/Views/Components/Common/AppHeader.swift`, `OPS/Views/Components/Common/CustomTabBar.swift`, `OPS/Views/Components/FloatingActionMenu.swift`
- Analytics: `OPS/Utilities/AnalyticsManager.swift:649` (TabName enum)
- Design system: `OPS/Styles/OPSStyle.swift` (tokens), `ops-design-system/project/` (cross-platform brand)
- Parent session: Books reconstruction (bug `1b038315-fb4a-44a1-b118-8e5e67578980`) — spec pending
- Saved feedback applied: iOS Supabase schema constraint (additive only), never filter by role, specs are authoritative, invoke matching skills before UI claims
