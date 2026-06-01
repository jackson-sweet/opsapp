# BOOKS — Condensed Cards + Expand-to-Sheet UX Overhaul (Design Spec)

**Date:** 2026-06-01
**Branch:** `feat/books-ux-overhaul` (off `feat/books-mission-deck`)
**Supersedes (where conflicting):** `2026-05-19-books-tab-mission-deck-rebuild.md` — esp. the carousel pattern (§5).
**Scope:** Presentation / interaction only. **No** changes to `MoneyDashboardViewModel` financial math or RLS.

---

## 0 · Owner-approved decisions (forks resolved 2026-06-01)

1. **Drill actions → move into the expanded sheet.** The condensed face is one tap target that opens the sheet; the wired drills (P&L → Outstanding/Forecast, A/R → Top Chase) live inside the expanded content.
2. **A/R → one merged rich sheet.** Expanding A/R opens a single half-sheet that folds in `ARAgingDetailView`'s content (aging ramp + buckets + top chase + top-outstanding clients). No sheet-over-sheet.
3. **Condensed card density → determined by data-viz analysis** (highest-value glance per card; table below).
4. **Below-picker hierarchy → deeper restructure.** Collapse the nested-ScrollView fight into a single scroll surface with pinned section delineation.

---

## 1 · The six issues

| # | Issue | Fix |
|---|-------|-----|
| 1 | Redundant in-view "+" expense FAB | Scope it off where the global `FloatingActionMenu` is present (Books-embedded). Keep it for Settings-reached screens (global FAB hidden on Settings tab). Broadcast an expense-changed notification on save so the global-FAB create refreshes embedded lists (parity with the old shared-VM instant refresh). |
| 2 | Flat / disjointed below-picker | Single-scroll architecture; pinned `// SECTION` header + hairline + divider rhythm. |
| 3 | Inconsistent spacing | Normalize every literal to the `OPSStyle.Layout` scale (4 / 8 / 12 / 16 / 20 / 24 / 32). |
| 4 | Carousel swipe-bleed | `containerRelativeFrame(.horizontal, count: 1, span: 1, spacing: OPSStyle.Layout.spacing3)` so paging width accounts for the 16pt HStack gap. |
| 5 | Non-uniform card heights | Subsumed by #6 — one fixed condensed height for all 5. |
| 6 | Condensed cards + expand-to-sheet | New L2 condensed card per lens; tap → half-sheet with full content. |

---

## 2 · Condensed card — data-viz analysis

Each lens leads with its single highest-signal number + its signature mini-viz (visuals over numbers). All five share **one** uniform layout and **one** fixed height; only the metric, viz type, and semantic color differ.

| Lens | Caption | Hero number | Mini-viz (uniform band) | Sub-stat | Hero color |
|------|---------|-------------|-------------------------|----------|-----------|
| **P&L** | `NET CASH` | net cash | margin meter (olive fill / tan-soft track) | `+36% MARGIN` | text / rose |
| **CASH FLOW** | `NET CASH · {N}W` | net cash | thin sparkline + rose bad-week dots | `{avg}/WK` | text / rose |
| **A/R** | `TOTAL OUTSTANDING` | outstanding | 4-segment aging ramp | `{open} OPEN · {overdue} OVERDUE` | rose |
| **FORECAST** | `WEIGHTED FORECAST` | weighted value | stacked stage bar (accent tints) | `{n} ACTIVE` | accent |
| **JOBS** | `AVG MARGIN` | avg margin % | win/loss ratio bar (olive vs rose) | `{p} PROFITABLE · {l} LOSING` | olive / rose |

### Uniform layout (L2 tile)

```
┌────────────────────────────────────────┐  ← L2: white@0.04 fill, white@0.08 border, radius 6 (sidebarHoverRadius)
│ {CAPTION}                            ⌃  │  ← JetBrains 9.5 uppercase text-3 · expand chevron text-3
│ {HERO NUMBER}                           │  ← Mohave-Light heroNumberCondensed (38pt), tabular, tracking -1
│ ▓▓▓▓▓▓▓░░░░  {SUB-STAT}                 │  ← viz band (~24pt) left ~58% · sub-stat JetBrains 10 right
└────────────────────────────────────────┘
```

- **Whole card = a `Button`** with the `BooksDrillTile` press chrome (pressed: white@0.08 fill / white@0.18 border, `OPSStyle.Animation.hover`). Light selection haptic on tap.
- **Fixed height:** one value tuned in-preview so the tallest composition (sparkline) fits with no dead space. Target ≈ 150pt; finalized against rendered output.
- **Horizontal padding:** `spacing3_5` (20) to match the carousel header gutter. Internal padding `spacing3` (16) / `spacing2_5` (12) vertical.
- **New token:** `OPSStyle.Typography.heroNumberCondensed = Font.custom("Mohave-Light", size: 38)` (documented additive token; mirrors `heroNumber`).
- Numbers tabular (`monospacedDigit`), formatted, empty = `—`. Reduced-motion: no count-up.

The carousel's shared `inlineHeader` (active label + scope badge + `PeriodPill`) and the dot pagination are **unchanged** — they stay above / below the paging strip and continue to reflect the active condensed card.

---

## 3 · Expand-to-sheet interaction

- **Emotional beat:** Transition — maintain spatial continuity from glance → detail.
- **Mechanism:** tap a condensed card → `@State expandedCard: HeroCarousel.CardID?` → `.sheet(item:)` presenting that lens's **full content** (the existing rich card body) inside the reused half-sheet pattern: `NavigationStack` + Cake-Mono uppercase title + `DONE` + `.presentationDetents([.medium, .large])` + `.presentationDragIndicator(.visible)` (identical to `ARAgingDetailView`).
- **Motion:** native sheet rise (system; OPS curve). No custom spring. `accessibilityReduceMotion` honored by the system; our tap haptic is motion-independent.
- **Haptic:** `.selection` (light) on tap — earned, one per open.
- **Drills inside the sheet:** the full content keeps its drill tiles. Tapping a drill calls the existing closure **and** dismisses the sheet:
  - P&L `OUTSTANDING` → dismiss → `onDrillOutstanding` (segment = Invoices, filter = overdue).
  - P&L `FORECAST` → dismiss → `onDrillForecast` (segment = Estimates, filter = sent).
  - A/R `TOP CHASE` → scrolls within the merged A/R sheet to the top-outstanding list (no second sheet).
- **A/R merged sheet:** a new `ARDetailSheet` view = ARCard full content (hero + ramp + bucket grid) **+** `ARAgingDetailView`'s aging chart + top-outstanding client list, loading invoices/clients via `DataController` (injected into the carousel). `ARAgingDetailView` standalone usage (notification deep link in `BooksTabView`) is retained unchanged.

---

## 4 · Below-picker single-scroll restructure (#2)

**Problem:** `BooksTabView` wraps everything in an outer `ScrollView`; each embedded list (`InvoicesListView`/`EstimatesListView`/`ExpensesListView`/`MyExpensesView`) nests its **own** `ScrollView` → ambiguous heights, no section boundaries.

**Fix:** one scroll surface owns the page. Embedded lists render their rows in a `LazyVStack` **without** an inner `ScrollView` when `embedded == true`; the outer Books scroll owns all scrolling. Section delineation via a pinned header:

- Outer `ScrollView` → `LazyVStack(pinnedViews: [.sectionHeaders])`.
- Content order: carousel · cashflow card · `Section { listRows } header: { picker + drill chip + // SECTION · count }`.
- Section header = the inset-pill segmented control + active drill chip + a `// {SEGMENT} · {count}` line (JetBrains 10, text-3, uppercase) + bottom hairline (`line`, white@0.10). Pins under the collapsing carousel as the list scrolls.
- The existing carousel-collapse (`headerCollapsed` + `CollapsedCarouselStrip`) is preserved; with a single scroll it now behaves deterministically.
- `embedded` already exists on the three List views; add `embedded` to `MyExpensesView`. Standalone (Settings / MainTab) usage keeps its own `ScrollView` + FAB.

---

## 5 · FAB removal + refresh parity (#1)

- `ExpensesListView.addExpenseFAB` and `MyExpensesView.expensesFAB` render only when **not** embedded (global FAB absent). `BooksTabView` passes `embedded: true`; Settings keeps the in-view FAB.
- `ExpenseFormSheet.save` posts `Notification.Name.opsExpensesDidChange` on success (before dismiss). `MyExpensesView` + `ExpensesListView` `.onReceive` → reload. The global FAB's `new-expense` create now refreshes every visible expense list (fixes a latent app-wide gap). No default-project pre-fill exists on either in-view FAB, so nothing unique is lost.

---

## 6 · Verification

- **Visual:** `OPSTests/BooksSnapshotTests` renders carousel + each condensed card + each expanded sheet + the below-picker section to PNGs via `ImageRenderer` (previewStub data). Inspect for uniform heights, framed condensed tiles, clear section boundaries, consistent spacing.
- **Carousel bleed:** verified by swiping all 5 pages in the simulator (cumulative drift is interactive, not visible in a static shot).
- **Build:** `xcodebuild -scheme OPS -destination 'generic/platform=iOS' -derivedDataPath /tmp/ops-ux-dd build` → 0 `error:`, no `BUILD FAILED`, **zero** warnings from any `OPS/Views/Books/*` file.

---

## 7 · Docs to update post-build

- `2026-05-19-books-tab-mission-deck-rebuild.md` — annotate §5 carousel as superseded by this condensed pattern.
- `ops-software-bible/02_USER_EXPERIENCE_AND_WORKFLOWS.md` + `09_FINANCIAL_SYSTEM.md` — Books carousel = condensed glance + expand-to-sheet; single global expense entry.
