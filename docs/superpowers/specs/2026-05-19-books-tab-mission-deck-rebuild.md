# BOOKS — Mission Deck Visual Rebuild Implementation Spec

|   |   |
|---|---|
| **Date** | 2026-05-19 |
| **Status** | Approved design (Mission Deck handoff received). Ready for implementation. |
| **Scope** | iOS app (`ops-ios/`) — Books tab visual rebuild against existing carousel architecture |
| **Branch** | `feat/books-mission-deck` |
| **Design source** | `docs/design-briefs/books-handoff/HANDOFF.md` (414 lines) + companion JSX prototype |
| **Architecture spec it supersedes (visually)** | [`2026-05-11-books-ui-reconstruction-design.md`](2026-05-11-books-ui-reconstruction-design.md) — the 5-card carousel architecture is unchanged; every visual treatment changes |
| **Bug record** | None — proactive visual rebuild, not bug-driven |
| **Related spawns** | `CASHFLOW FORECAST - P1-1` (CashflowForecastCard currently mounted below hero — leave untouched in this scope), `PIPELINE TAB - P1-1` (separate top-level tab — out of scope) |

---

## 0 · Four open-question decisions (recorded for future agents)

The handoff flagged four questions for engineering. Decisions made 2026-05-19 with the lens *"presents data meaningfully, intuitively, usefully, without overwhelming, while adhering to design system"*:

| # | Question | Decision | Reasoning |
|---|---|---|---|
| 1 | Card 2 chart treatment — sparkline vs paired bars | **Sparkline**, with bad-week marker rule expanded to *every* week where out > in (not just the worst) | Sparkline reads at-a-glance on 390pt; paired bars get cramped at 8×2 bars. Card 1 already shows the in/out breakdown numerically — Card 2 should be trajectory + anomaly, not a second numerical breakdown. Expanded marker rule keeps the expense-creep honesty without re-introducing density |
| 2 | Card 5 worst-loser inclusion | **Always include worst loser**, with `-$500` floor guard | "Which jobs made me money?" implies the inverse: if the card shows only winners on a great month, the early-warning surface is lost. `-$500` floor prevents noise (refunds, rounding) from displacing a genuine top-5 |
| 3 | Hero count-up animation (800ms) | **Cut.** Keep `.contentTransition(.numericText())` for period-change morph only. First paint renders at final value | 800ms violates "confident, fast, snap" motion principle. Cosmetic — uses 8–16% of the operator's attention budget on a tab they spend 5–10s on |
| 4 | Card 1 margin caption | **Simplify to `36% MARGIN` alone**, color-keyed to sign (olive +, rose −, text-3 zero) | Designer proposal `"36% MARGIN · +$42,180 ON $118.4K"` repeats the 60pt hero net cash four lines above, AND uses K-notation while the rest of the system uses full thousands separators. Single tactical micro-label is cleaner |

---

## 1 · Summary

Rebuild every visual element of the Books tab against the Mission Deck design. Architecture is unchanged:

- 5-card hero carousel (P&L · Cash flow · A/R aging · Forecast · Jobs)
- Inline header with active-card label + period pill
- 3-segment list below (Invoices · Estimates · Expenses)
- Drill-tile interactions inside cards change the active segment + filter
- Hero collapses to single-line strip on vertical scroll
- Permission gating unchanged (Cards 1/2/3/5 = `finances.view`, Card 4 = `pipeline.view`)

What changes: typography hierarchy, hero scale, chart treatments, drill-tile structure, segmented control, dot pagination, status tag contrast, touch target floors, focus ring, plus entire new states (sync banner, skeleton, card-level error, PTR, drill filter chip, empty-state copy per card).

## 2 · Drift register

Deviations between handoff and current code / OPS Design System. Each will be reconciled.

| # | Source of truth | Current state | Action |
|---|---|---|---|
| D1 | Handoff: status tag mobile alphas (`0.32` fill, `0.88` border) + brighter text (`#B5C998` / `#DBC07F` / `#C99AA1`) + weight 600 | iOS uses single tone hex for status text/border on both web and mobile | Add new `oliveMobile` / `tanMobile` / `roseMobile` Color tokens in `OPSStyle.Colors` (asset catalog). Add helper modifier or use directly in tag components |
| D2 | Handoff: card header label is **JetBrains Mono 11px / 0.16em / weight 600** | Current cards have title text removed from the body; HeroCarousel's `inlineHeader` uses `OPSStyle.Typography.smallCaption` (JBM 12pt) for header label | Update `HeroCarousel.inlineHeader` typography to match: JBM 11pt, `.tracking(0.16em equivalent)`, weight 600 |
| D3 | Handoff: hero number is **Mohave 300, 60px** | Cards use `OPSStyle.Typography.title` (~28pt) | Add new `OPSStyle.Typography.heroNumber` token = Mohave Light 60pt with `-0.025em` letter-spacing equivalent, lineHeight 0.95. Update every hero `Text` in cards |
| D4 | Handoff: scope hint badge for Cards 3 + 4 (`ALL OPEN` rose / `ACTIVE` accent) is a separate badge component beside the card label | Current code renders the scope hint as inline text concatenated with the label (`"A/R · ALL OPEN"`) | Refactor `HeroCarousel.headerLabel` to return `(text, scopeHint?, scopeColor?)`. Render scope hint as a small colored badge — JBM 9pt / 0.16em / 600, mobile-bright tag treatment (0.32 fill, 0.88 border, brighter text) |
| D5 | Handoff: drill tiles are **uniform L2 cards** — `rgba(255,255,255,0.04)` bg, 6px radius, 14pt padding, 80pt min-height, → chevron in top-right | Cards 1/2/4/5 each have their own `tile` / `tileContent` helper with slightly different padding (`spacing2 = 8pt`) and no chevron. Card 3's TOP CHASE is a full-width button | Build a shared `BooksDrillTile.swift` component. Refactor all 5 cards to use it. Card 3's TOP CHASE keeps custom layout (taller, single full-width) but uses the same chrome conventions |
| D6 | Handoff: dot pagination — active dot is a `22 × 6` capsule growing from `6 × 6` with 200ms width animation | Current `HeroCarousel.dots` uses active width 16, inactive width 5, height 5 | Update active capsule to 22×6, inactive to 6×6, animate width over `OPSStyle.Animation.panel` (200ms) |
| D7 | Handoff: segmented control is **inset-pill style** — 3pt container padding, 5pt radius, active fill `rgba(255,255,255,0.10)` + border `0.22` + 1pt inset top-light. No accent. | Current is **underline-style** with steel-blue 2pt underline on active segment | Rebuild `BooksTabView.underlineSegmentedControl` → `BooksTabView.insetPillSegmentedControl`. Active state has no accent — uses neutral fill + inset top-light only |
| D8 | Handoff: A/R aging chart is **single continuous ramp bar + bucket markers in a 4-column grid below** | Current `ARCard` uses 4 horizontal bars stacked vertically | Rebuild `ARCard.body` aging section to render: (a) one horizontal flex-row of 4 colored segments sized proportionally to bucket amount, (b) 4-column grid below with `range / amount` per bucket |
| D9 | Handoff: Card 5 Jobs chart is **true diverging from center axis** — olive right, rose left | Current `JobsCard` renders absolute-value bars colored green/red | Rebuild `JobsCard` bar rendering. Each row: name (Mohave 500 14pt left), margin% (JBM 9.5pt small) + net (JBM 14pt 500), then below: 5pt bar with center axis line and bar extending left or right from 50% |
| D10 | Handoff: cash flow chart is **sparkline of net + olive area fill + dots**, bad week marked rose | Current `CashFlowCard` uses SwiftUI `Charts` paired BarMarks | Rebuild with `Canvas` or `SwiftUI Charts` `LineMark` + `AreaMark` + `PointMark`. My expanded rule: any week where outAmount > inAmount gets a rose point (not just the worst); regular weeks get olive points with bg-colored fill |
| D11 | Handoff: period pill 44pt minimum, chevron rotates 180° on open | Current `PeriodPill` has minHeight from internal padding only (~36pt), no rotation | Add `.frame(minHeight: 44)`. Chevron rotation is hard with native `Menu` (no open-state callback). **Compromise:** track menu open state via a tap-side gesture that wraps the Menu, OR accept native Menu without rotation. Recommendation: accept native Menu, skip rotation — system Menu UX is more native and rotation is decorative |
| D12 | Handoff: focus ring 2px accent + 2px offset | iOS default focus rings are system-driven (rarely visible — designed for keyboard nav which is uncommon on iOS) | Implement focus-visible via `.focusable()` modifier with `.focused` env binding for any explicitly keyboard-navigable element (none in Books today). Document the spec but don't add focus chrome to existing tap targets — iOS convention is to use system focus, not custom rings |
| D13 | Handoff: new states — sync banner, skeleton, card-level error, PTR, drill filter chip | None exist today | Build as net-new components in Phase B |
| D14 | Handoff: AR drill opens half-sheet with `.presentationDetents([.medium, .large])` | Current code uses plain `.sheet` on `ARAgingDetailView` (defaults to large detent only) | Add `.presentationDetents([.medium, .large])` and `.presentationDragIndicator(.visible)` to the existing `.sheet(isPresented: $showARDetail)` |
| D15 | Handoff: AppHeader title shrinks 28 → 22 when scrolled | Current AppHeader title size is fixed | AppHeader is out of scope (shared component). **Defer** — file as a follow-up spawn. If quick, can address in this rebuild but coordinate with other tabs first |
| D16 | Handoff: tab-bar sliding indicator animation uses spring physics | Current `CustomTabBar` uses `.spring(response: 0.4, dampingFraction: 0.8)` | CustomTabBar is shared. **Replace spring with `OPSStyle.Animation.panel` (200ms cubic-bezier)** in a separate atomic commit since it affects all tabs. This is overdue cleanup regardless |
| D17 | Handoff: empty-state copy strings per card differ from any current empty state | Cards render `—` as the empty hero with no contextual label | Add per-card empty-state rendering with exact strings from `HANDOFF.md` § 12 |
| D18 | Handoff: bug-id-less `feat/...` branch naming for this work | n/a | Working on `feat/books-mission-deck` |

---

## 3 · Token additions to OPSStyle.swift

All additions are additive (no rename, no remove). Files: `OPS/Styles/OPSStyle.swift`, `OPS/Assets.xcassets/...`

### 3.1 Colors — mobile-bright status tag tones

Asset catalog additions (`OPS/Assets.xcassets/`):

| Asset name | Hex | RGB | Use |
|---|---|---|---|
| `StatusSuccessMobile` | `#B5C998` | `(0.71, 0.79, 0.60)` | Olive text on mobile status tags |
| `StatusWarningMobile` | `#DBC07F` | `(0.86, 0.75, 0.50)` | Tan text on mobile status tags |
| `StatusErrorMobile` | `#C99AA1` | `(0.79, 0.60, 0.63)` | Rose text on mobile status tags |
| `FinReceivables` | `#D4A574` | (already exists as `accountingReceivables`) | Use alias — no new asset |

Swift token additions in `OPSStyle.Colors`:

```swift
// Mobile-bright status tag variants (outdoor glare set, per MOBILE.md)
// Use on tags/badges that need to read in direct sunlight.
static let oliveMobile = Color("StatusSuccessMobile")  // #B5C998
static let tanMobile   = Color("StatusWarningMobile")  // #DBC07F
static let roseMobile  = Color("StatusErrorMobile")    // #C99AA1
```

### 3.2 Colors — line-soft

```swift
// Web parity: 0.06 alpha for subtle dividers inside cards.
// Mobile bumps standard `--line` to 0.10 but keeps 0.06 for chart axis gridlines.
static let lineSoft = Color.white.opacity(0.06)
```

### 3.3 Typography — hero number role

```swift
// Books Phase 3 (Mission Deck) — hero numbers on carousel cards.
// Mohave Light 60pt, tabular, tightened tracking, line-height 0.95.
static let heroNumber = Font.custom("Mohave-Light", size: 60)
    .leading(.tight)   // approximates lineHeight 0.95 — verify visually
// Letter-spacing -0.025em applied via .tracking(-1.5) at call site
```

Add a comment note: this is for the carousel hero numbers (NET CASH, TOTAL OUTSTANDING, WEIGHTED FORECAST). Not for any other surface.

### 3.4 Spacing — no new tokens needed

The handoff's 14pt tile inset is between existing `spacing2` (8) and `spacing2_5` (12). Round to `spacing2_5` (12pt) — close enough, avoids token proliferation. The 16pt L1 inset is `spacing3`. 20pt canvas padding is `spacing3_5`. All existing.

### 3.5 Animation — no new tokens needed

All durations covered by existing `OPSStyle.Animation.hover/panel/page/flip/standard`.

---

## 4 · New shared components

### 4.1 `OPS/Views/Books/Components/BooksDrillTile.swift` (new)

Shared L2 drill tile used by all 5 cards. Replaces ad-hoc `tile` / `tileContent` helpers.

API:
```swift
struct BooksDrillTile: View {
    let label: String           // JBM 9.5pt / 0.18em / 500 — uppercase
    let value: String           // pre-formatted (callers handle currency / percent / count)
    let sub: String?            // JBM 9.5pt / 0.14em / textMute — optional, e.g. "4 ITEMS"
    var valueColor: Color = OPSStyle.Colors.primaryText
    var accent: Bool = false    // if true: accentMuted bg, accent border
    var onTap: (() -> Void)? = nil

    var body: some View
}
```

Chrome:
- bg: `accent ? Color("AccentPrimary").opacity(0.15) : Color.white.opacity(0.04)`
- border: `1px white.opacity(accent ? 0.25 : 0.08)`, radius 6pt
- padding: 12pt (uses `spacing2_5`)
- minHeight: 80pt
- → chevron top-right in `textMute` (`Lucide arrow-right` analog — use SF Symbol `arrow.right` at 9pt or custom path)
- Press state: bg → `Color.white.opacity(0.08)`, border → `Color.white.opacity(0.18)` — 100ms in / 150ms out
- `.frame(minHeight: 44)` for touch-target compliance is already covered by 80pt min-height
- VoiceOver: `accessibilityElement(children: .combine)`, label format defined in § 8

### 4.2 `OPS/Views/Books/Components/BooksSyncBanner.swift` (new)

Slim banner shown above the inline header when a sync request is in flight.

Visual:
```
[●] SYS :: SYNC · 08:42
```

Spec from `HANDOFF.md` § 11:
- padding: `6pt 12pt`
- bg: `Color.white.opacity(0.04)` (surface-input)
- border: 1pt `Color.white.opacity(0.10)` (line)
- radius: 4pt (chipRadius)
- Pulse dot: 6×6, `OPSStyle.Colors.tertiaryText`, animation: opacity 1.0 → 0.3 → 1.0 over 1.5s, ease-in-out, infinite. Reduced motion: static at full opacity
- Text: JBM 10pt / 0.16em tracking / weight 500, `OPSStyle.Colors.tertiaryText`
- Timestamp format: `"HH:mm"` local (24-hour)
- Show: when `MoneyDashboardViewModel.isLoading == true`
- Hide: 200ms opacity fade when sync completes successfully

API:
```swift
struct BooksSyncBanner: View {
    let lastSyncedAt: Date?
    let state: State    // .syncing | .offline | .error
    var onRetry: (() -> Void)? = nil
}
```

The offline variant per `HANDOFF.md` § 5 ("offline" row): `SYS :: OFFLINE · CACHED HH:MM` with RETRY action button on the right (Cake Mono 11pt, rose).

### 4.3 `OPS/Views/Books/Components/BooksSkeleton.swift` (new)

Skeleton primitive for the no-cache cold-paint case.

Variants:
- `BooksSkeleton.text(width:)` — 2pt rounded rect, height matches typography line-height
- `BooksSkeleton.tile()` — full L2 drill tile shape with skeleton internals
- `BooksSkeleton.bar(width:height:)` — generic bar (for charts)

Visual:
- fill: `Color.white.opacity(0.06)` (`fillNeutralDim`)
- pulse: bg 0.03 → 0.08 → 0.03 over 1.5s, ease-in-out, infinite
- reduced motion: suppress pulse, static at 0.08

Each card has a `skeletonView` computed property that mirrors its real layout slot-for-slot.

### 4.4 `OPS/Views/Books/Components/BooksCardError.swift` (new)

Card-level error state. Replaces just one card's body while siblings stay live.

Visual:
```
        —              ← Mohave 300, 48pt, rose
// ERROR — LOAD FAILED ← JBM 10.5pt, rose, 600
Couldn't fetch this period. Showing cached
data above the fold; tap retry to try again.
                        ← Mohave 13pt, text2
       [RETRY →]        ← Cake Mono 13pt, rose, rose-soft bg
```

API:
```swift
struct BooksCardError: View {
    let onRetry: () -> Void
}
```

Used by each card's body via:
```swift
if viewModel.cardError(.pl) {
    BooksCardError(onRetry: { Task { await viewModel.retry(.pl) } })
}
```

(VM needs new `cardError(_:)` + `retry(_:)` API — see § 6 below.)

### 4.5 `OPS/Views/Books/Components/BooksDrillFilterChip.swift` (new)

Chip shown below the segmented control when a drill applied a filter. Tap × to clear.

Visual per `HANDOFF.md` § 5 ("Outstanding drill"):
- Pill: padding `4pt 10pt`, radius 4pt (chip), bg `Color.white.opacity(0.08)` (surfaceActive), border 1pt `--line`
- Label: JBM 10pt / 0.14em / 500, `OPSStyle.Colors.primaryText`, uppercase (e.g. `OVERDUE`)
- × dismiss: 12pt SF Symbol `xmark`, `textMute` color
- Tap × → calls back to clear the filter

API:
```swift
struct BooksDrillFilterChip: View {
    let label: String
    let onClear: () -> Void
}
```

### 4.6 `OPS/Views/Books/Components/BooksScopeHintBadge.swift` (new)

Small tag rendered beside the card header label for cards 3 + 4.

Visual per handoff `BHeader`:
- padding: `3pt 7pt`, radius 4pt (chip)
- bg: mobile-bright tone at 0.32 alpha (rose for AR / accent for forecast)
- border: 1pt mobile-bright tone at 0.88 alpha (rose) / 0.45 alpha (accent-muted variant)
- Text: JBM 9pt / 0.16em / 600 uppercase
- Color: `roseMobile` for AR / `primaryAccent` for forecast

API:
```swift
struct BooksScopeHintBadge: View {
    enum Variant { case allOpen, active }
    let variant: Variant
}
```

### 4.7 `OPS/Views/Books/Components/BooksPTRIndicator.swift` (new)

Custom pull-to-refresh indicator. Wraps native `.refreshable` with a custom `ProgressViewStyle`.

Visual per `HANDOFF.md` § 11 ("Pull-to-refresh"):
```
[OPS mark]  [progress arc]  SYNCING
```

- OPS mark: 16pt, `textTertiary`, monochrome (use existing OPS mark from `OPS/Assets.xcassets`)
- Arc: 18pt circle, 1.5pt stroke, track `--line`, arc `text2`, rotates 360° in 900ms linear infinite
- Label: JBM 10pt / 0.18em / 500, `textTertiary` — `SYNCING` while active, `SYNCED · 08:42` for 1.5s after success, then hide
- Reduced motion: suppress arc rotation; static OPS mark + static label

### 4.8 Empty-state component per card

Not a new file — implemented inline within each card as a `@ViewBuilder` `emptyState` computed property. Strings from `HANDOFF.md` § 12:

| Card | Hero | Label | Tiles |
|---|---|---|---|
| PLCard | `$0` | `// NO ACTIVITY THIS PERIOD` | Both tiles: `$0` / `0 ITEMS`, color `text3` |
| CashFlowCard | `$0` | `// NO PAYMENTS THIS PERIOD` | SALES `$0` / TRAILING · AVG/WK `$0` / PER WEEK · DAYS `—` / TO PAY |
| ARCard | `$0` | `// NO OPEN INVOICES` | Top chase tile hidden entirely |
| ForecastCard | `$0` | `// NO ACTIVE OPPORTUNITIES` | CLOSE RATE `—` / LAST 90D · STALE `0` / > 14D IDLE |
| JobsCard | (no hero) | `// NO COMPLETE JOBS THIS PERIOD` | PROFITABLE `0` / AVG MARGIN `—` / LOSERS `0` |

The empty-state hero font is `Mohave Light 60pt` (same `heroNumber` token) but rendered in `textTertiary`. The `//` label uses JBM 11pt / 0.16em / 500 in `textMute`.

---

## 5 · Card-by-card implementation

Every card body is rewritten. Below is the implementation plan per card, mapped to the handoff JSX in `docs/design-briefs/books-handoff/src/direction-b.jsx`.

### 5.1 `OPS/Views/Books/Cards/PLCard.swift`

```
Hero block:
  Label "NET CASH"      JBM 10pt / 0.20em / 500 / text3
  Net cash hero         Mohave Light 60pt / -0.025em / lineHeight 0.95 / tnum
                        Color: text if net ≥ 0, rose if net < 0
  Margin caption        "36% MARGIN" only (per decision Q4)
                        JBM 11pt / 0.04em / 500 / olive (≥0), rose (<0), text3 (0)

Margin meter:           6pt bar, radius 2pt
                        Track: tan-soft fill
                        Fill: olive at marginPct% (left-aligned)

IN/OUT row (below meter, marginTop: 10pt):
  Left:
    Label  "PAYMENTS IN"   JBM 9.5pt / 0.18em / 500 / text3
    Value  +$118,400       JBM 14pt / 500 / oliveMobile / tnum
  Right (alignment: trailing):
    Label  "EXPENSES OUT"  JBM 9.5pt / 0.18em / 500 / text3
    Value  −$76,220        JBM 14pt / 500 / tanMobile / tnum

Drill tiles (HStack, gap 8pt, marginTop: 24pt):
  BooksDrillTile(label: "OUTSTANDING", value: $12,640, sub: "4 ITEMS", valueColor: rose, onTap: drillOutstanding)
  BooksDrillTile(label: "FORECAST",    value: $38,900, sub: "7 ITEMS", valueColor: accent, onTap: drillForecast)
```

Outer container: `.padding(.horizontal, OPSStyle.Layout.spacing3_5)` (20pt).

Empty-state branch: when `viewModel.totalPayments == 0 && viewModel.totalExpenses == 0`, render empty hero + label + 0-tiles per § 4.8 table.

Remove `marginBar` GeometryReader-based animation (no more fill-draw) — per decision Q3 (no count-up).

### 5.2 `OPS/Views/Books/Cards/CashFlowCard.swift`

```
Hero block:
  Label "NET CASH · {N}W TRAILING"  JBM 10pt / 0.20em / 500 / text3
  Net cash hero                      heroNumber token / text / tnum

Sparkline (height 84pt, marginTop 22pt):
  SVG-equivalent in SwiftUI:
    - Zero axis line (horizontal, mid-height): 1pt, lineSoft color
    - Area fill below line: olive-soft (#9DB582 at 12% alpha)
    - Line: 1.5pt olive, round-cap, round-join, smoothed via Catmull-Rom or linear
    - Dots at each data point: 2.5pt radius, fill bg (#000), stroke 1.2pt olive
    - BAD-WEEK MARKERS (my expansion): for every week where outAmount > inAmount,
      replace the olive dot with a 3pt rose dot (filled, no stroke)
  X-axis labels: first and last week date, JBM 8.5pt / 0.10em / textMute

Drill tiles (HStack, gap 8pt, marginTop 24pt):
  BooksDrillTile(label: "SALES",   value: $142.8K, sub: "TRAILING")
  BooksDrillTile(label: "AVG/WK",  value: $14.8K,  sub: "PER WEEK")
  BooksDrillTile(label: "DAYS",    value: 18.2,    sub: "TO PAY", onTap: drillDays)
```

Implementation note: build with SwiftUI `Path` over `GeometryReader` rather than `Charts` framework — gives finer control over the dot rendering and the bad-week-marker rule. The `Charts` library's flexibility is overkill for a 3-element render and adds animation complexity.

Bad-week marker logic:
```swift
let isBadWeek = week.outAmount > week.inAmount
let dotColor = isBadWeek ? OPSStyle.Colors.errorStatus : OPSStyle.Colors.successStatus
let dotRadius: CGFloat = isBadWeek ? 3 : 2.5
let dotStroke: CGFloat = isBadWeek ? 0 : 1.2
```

Empty-state: when `viewModel.paymentsByWeek.isEmpty && viewModel.expensesByWeek.isEmpty`, replace sparkline with empty hero + `// NO PAYMENTS THIS PERIOD` label.

### 5.3 `OPS/Views/Books/Cards/ARCard.swift`

```
Hero block:
  Label "TOTAL OUTSTANDING"          JBM 10pt / 0.20em / 500 / rose
  Total outstanding hero              heroNumber token / rose / tnum
  Subline                             JBM 11pt / 0.12em / text2 / tnum
                                     "5 OPEN · 4 OVERDUE" — the OVERDUE count in rose, separator (·) in textMute

Aging ramp (height 10pt, marginTop 24pt):
  HStack with 4 colored segments, gap 2pt, radius 2pt, overflow hidden:
    0–30d  bucket: olive       (flex = bucket.amount / total)
    31–60d bucket: receivables (#D4A574)
    61–90d bucket: tan
    90d+   bucket: brick

  Bucket markers (grid 4-col, gap 6pt, marginTop 14pt):
    For each bucket:
      Range label    JBM 9.5pt / 0.16em / 600 / colorOfBucket / uppercase
      Amount         JBM 13pt / 500 / text / -0.01em tracking / tnum

TOP CHASE tile (single full-width, marginTop 24pt):
  Bigger tile — 80pt min-height, 16pt padding internal
  Top row: "TOP CHASE" label (JBM 9.5pt / 0.20em / 500 / text3) + → chevron (text3)
  Bottom row:
    Left column:
      Client name   Mohave Medium 15pt / text
      Meta          JBM 10pt / 0.12em / text3 / tnum
                    "INV-00284 · 110D OVERDUE"
    Right value     JBM 20pt / 500 / rose / -0.01em / tnum
                    "$5,500"
  Tappable — calls onTapTopChase
```

Empty-state: when `viewModel.outstandingInvoiceBreakdown.isEmpty`, render empty hero `$0` + label `// NO OPEN INVOICES`. Aging ramp + TOP CHASE tile both hidden.

### 5.4 `OPS/Views/Books/Cards/ForecastCard.swift`

```
Hero block:
  Label "WEIGHTED FORECAST"          JBM 10pt / 0.20em / 500 / accent
  Weighted forecast hero              heroNumber token / accent / tnum
  Subline                             JBM 11pt / 0.12em / text2 / tnum
                                     "12 ACTIVE OPPORTUNITIES"

Stage bars (VStack, gap 12pt, marginTop 24pt):
  For each stage in weightedForecastByStage:
    Header row (HStack, baseline alignment):
      Stage name    JBM 10pt / 0.16em / 500 / text2 / uppercase
      Right side (HStack baseline, gap 6pt):
        Weight %    JBM 9pt / 0.10em / textMute / tnum    "×62%"  (rounded from stage probability)
        Amount      JBM 13pt / 500 / text / tnum          "$26,800"
    Bar (height 5pt, marginTop 6pt):
      Track: accent-muted (rgba(111,148,176,0.15))
      Fill: accent #6F94B0 at width = (stage.amount / maxStageAmount) * 100%
      radius 2pt

Drill tiles (HStack, gap 8pt, marginTop 22pt):
  BooksDrillTile(label: "CLOSE RATE", value: "64%", sub: "LAST 90D",  valueColor: olive,   onTap: drillCloseRate)
  BooksDrillTile(label: "STALE",      value: "3",   sub: "> 14D IDLE", valueColor: tan,    onTap: drillStale)
```

**Important:** the stage weight `×62%` needs to come from the opportunity-level data (each opportunity has `win_probability`). The current `weightedForecastByStage` ViewModel field is `[(stage: PipelineStage, value: Double)]` — value is already weighted. We need to add per-stage average probability OR derive it differently.

Spec resolution: add a new VM field `weightedForecastByStageDetailed: [(stage: PipelineStage, value: Double, avgProbability: Double)]` where `avgProbability` is the unweighted-mean win probability of opportunities in that stage. Keep the existing simple tuple for backwards compat OR migrate.

**Decision:** migrate the tuple to include `avgProbability`. The card needs it; no other consumer exists.

Empty-state: when `viewModel.weightedForecastByStage.isEmpty`, render empty hero `$0` + label `// NO ACTIVE OPPORTUNITIES`. Stage bars hidden. Drill tiles show `—` / `0`.

### 5.5 `OPS/Views/Books/Cards/JobsCard.swift`

```
Top label "TOP 5 JOBS BY NET"        JBM 10pt / 0.20em / 500 / text3

Diverging bar chart (VStack, gap 14pt, marginTop 18pt):
  For each job in topProjectsByNet:
    Header row (HStack, baseline alignment):
      Job name      Mohave Medium 14pt / text / 0.04em tracking
      Right side (HStack baseline, gap 8pt):
        Margin %    JBM 9.5pt / 0.10em / text3 / tnum         "+82%" / "-32%"
        Net $       JBM 14pt / 500 / oliveMobile (pos) or roseMobile (neg) / -0.01em / tnum
                    "+$19,500" / "-$2,600"
    Diverging bar (height 5pt, marginTop 6pt, ZStack):
      Center axis: 1pt vertical line at 50% width, line color
      Fill bar:
        if positive: left = 50%, width = (|net| / maxAbsNet) * 50%, fill olive
        if negative: left = 50% - widthPct%, width = (|net| / maxAbsNet) * 50%, fill rose
      Radius 2pt (rBar)

KPI tiles (HStack, gap 8pt, marginTop 22pt):
  BooksDrillTile(label: "PROFITABLE", value: "9",  sub: "JOBS", valueColor: olive, onTap: drillProfitable)
  BooksDrillTile(label: "AVG MARGIN", value: "32%", sub: "MEAN", valueColor: text)  (no onTap — read-only)
  BooksDrillTile(label: "LOSERS",     value: "2",  sub: "JOBS", valueColor: rose,  onTap: drillLosers)
```

**Worst-loser-always-include logic (decision Q2):**

The ViewModel currently exposes `topProjectsByNet: [JobNet]` — top 5 by absolute net. Change the rollup logic in `MoneyDashboardViewModel.computeJobNets` to:

```swift
let allNets = computeAllJobNets(...)              // every project
let top5 = allNets.sorted { $0.net > $1.net }.prefix(5)
let worstLoser = allNets.filter { $0.net < -500 }
    .min(by: { $0.net < $1.net })

var result = Array(top5)
if let worst = worstLoser, !result.contains(where: { $0.id == worst.id }) {
    result.removeLast()
    result.append(worst)
}
```

The `-$500` floor is the noise guard. Variable name suggestion: `worstLossFloor = -500.0`.

Empty-state: when `viewModel.topProjectsByNet.isEmpty`, render label `// NO COMPLETE JOBS THIS PERIOD` (no hero on this card — it has no hero number in the design). KPI tiles render with 0/—/0.

---

## 6 · ViewModel additions

`OPS/ViewModels/MoneyDashboardViewModel.swift`:

### 6.1 Per-stage average probability (for Card 4)

Replace `weightedForecastByStage: [(stage: PipelineStage, value: Double)]` with:

```swift
struct StageForecast: Identifiable {
    let id: PipelineStage
    let value: Double           // weighted (estimatedValue * probability)
    let avgProbability: Double  // unweighted mean of probabilities in this stage
    let count: Int              // num opportunities in this stage
}
@Published var weightedForecastByStage: [StageForecast] = []
```

Update the computation in `loadData` / `recalculate` to populate `avgProbability` = `mean(opportunities-in-stage.win_probability)`.

### 6.2 Worst-loser-always-include (for Card 5)

In `computeJobNets`, after building the standard top-5-by-net list, apply the always-include-worst-loser logic with `-$500` floor (see § 5.5).

### 6.3 Per-card error tracking

New API for card-level errors:
```swift
enum BooksCard: Hashable { case pl, cashFlow, ar, forecast, jobs }
@Published private(set) var failedCards: Set<BooksCard> = []

func cardError(_ card: BooksCard) -> Bool { failedCards.contains(card) }
func retry(_ card: BooksCard) async { /* clear failure for that card, re-fetch */ }
```

In `loadData`, when a specific repository fetch throws, add the affected card(s) to `failedCards` instead of failing the whole load. Granular fail-soft.

### 6.4 Sync state

```swift
enum SyncState { case syncing, synced, offline, error }
@Published private(set) var syncState: SyncState = .synced
@Published private(set) var lastSyncedAt: Date?
```

Set `.syncing` at the start of `loadData()`, `.synced` on success with `lastSyncedAt = Date()`. Set `.offline` when the network layer reports unreachable, `.error` on hard failure.

### 6.5 Skeleton coordination

```swift
@Published private(set) var hasEverLoaded: Bool = false  // false until first successful loadData

// In loadData, on first successful load:
hasEverLoaded = true
```

Cards render the skeleton path when `!viewModel.hasEverLoaded && viewModel.isLoading`. Once `hasEverLoaded` becomes true, cards render either real data or empty-state, never skeleton again — subsequent loads happen in-place behind the sync banner.

---

## 7 · BooksTabView wiring changes

`OPS/Views/Books/BooksTabView.swift`:

### 7.1 Mount sync banner above inline header

When `dashboardVM.syncState != .synced`, render `BooksSyncBanner` above the `HeroCarousel`. The banner sits inside the `VStack(spacing: 0)` between `AppHeader` and `ScrollView`. Pulled into a private `@ViewBuilder` for clarity.

### 7.2 Mount filter chip below segmented control

When `selectedSegment == .invoices && invoiceVM.selectedFilter == .overdue` (or analogous for other drill applications), render `BooksDrillFilterChip(label: "OVERDUE", onClear: { invoiceVM.selectedFilter = .all })` between the segmented control and `contentForSegment`.

Same for `selectedSegment == .estimates && estimateVM.selectedFilter == .sent`. Each segment knows its own "is filtered by drill?" predicate.

### 7.3 Replace underline segmented control with inset-pill

Replace `underlineSegmentedControl` body with the inset-pill spec from § 2 / D7. Use new helper `insetPillSegmentedControl`.

### 7.4 Half-sheet detents on AR sheet

```swift
.sheet(isPresented: $showARDetail) {
    ARAgingDetailView()
        .environmentObject(dataController)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
}
```

### 7.5 PTR

Add `.refreshable { await dashboardVM.loadData() }` to the outer `ScrollView`. The custom indicator (`BooksPTRIndicator`) wraps via a custom `ProgressViewStyle` set on the `ScrollView`.

### 7.6 Skeleton vs empty vs error coordination

Per-card body renders one of:
- `skeletonView` when `!viewModel.hasEverLoaded && viewModel.isLoading`
- `errorView` when `viewModel.cardError(.pl)` (or applicable enum)
- `emptyView` when data is zero AND `viewModel.hasEverLoaded`
- normal body otherwise

This is a per-card concern, not BooksTabView's. Each card file implements the switch.

### 7.7 Coordination with CashflowForecastCard

The current `BooksTabView` mounts `CashflowForecastCard` below the hero (guarded by `hasFinances`). The Mission Deck handoff doesn't address this card — it's owned by the `CASHFLOW FORECAST - P1-1` spawn.

**Action: leave it untouched.** Don't restyle. Future scope: integrate as Card 6 in the carousel.

### 7.8 Tab-bar spring → OPS easing (D16)

`OPS/Views/Components/Common/CustomTabBar.swift`:
- Line 61, 74: replace `.spring(response: 0.4, dampingFraction: 0.8)` with `OPSStyle.Animation.panel` (200ms cubic-bezier)
- This benefits every tab. Atomic commit separate from Books changes.

---

## 8 · Accessibility (VoiceOver labels)

From `HANDOFF.md` § 10. Implemented per element via `.accessibilityLabel(...)` + `.accessibilityHint(...)` modifiers.

### 8.1 Carousel cards

| Card | Label | Hint |
|---|---|---|
| Container | `Books dashboard, 5 cards, swipe with two fingers to navigate` | (rotor: heading) |
| Card 1 | `P and L. Net cash {fmt$(net)} this {period.label}. {pct}% margin.` | `Double-tap a tile for details` |
| Card 2 | `Cash flow. Net cash {fmt$(net)} over {weeks} weeks. {fmt$(avg)} per week average.` | — |
| Card 3 | `Accounts receivable. {fmt$(total)} outstanding across {open} open invoices, {overdue} overdue. Always all-open.` | — |
| Card 4 | `Forecast. {fmt$(weighted)} weighted across {count} active opportunities. {closeRate}% close rate.` | — |
| Card 5 | `Jobs. {profitable} profitable, {losers} losing money this {period.label}. Average margin {avgPct}%.` | — |

### 8.2 Drill tiles

| Tile | Label | Hint |
|---|---|---|
| OUTSTANDING | `Outstanding receivables, {fmt$(amount)}, {count} items` | `Double-tap to view overdue invoices` |
| FORECAST (Card 1) | `Forecast revenue, {fmt$(amount)}, {count} estimates sent` | `Double-tap to view sent estimates` |
| DAYS | `Days to pay, {days} days mean` | `Double-tap for cash flow detail` |
| TOP CHASE | `Top chase, {client}, {fmt$(amount)}, {days} days overdue` | `Double-tap to open chase list` |
| CLOSE RATE | `Close rate, {pct}%, last 90 days` | `Double-tap for pipeline detail` |
| STALE | `Stale opportunities, {count}, over 14 days idle` | `Double-tap to view stale opps` |
| PROFITABLE | `Profitable jobs, {count}` | `Double-tap for profitability report` |
| LOSERS | `Loss-making jobs, {count}` | `Double-tap to view losers` |

### 8.3 Chrome

| Element | Label | Hint |
|---|---|---|
| Period pill | `Period selector, currently {period.label}` | `Double-tap to change period` |
| Dot pagination | `Card {n+1} of 5` | `Double-tap to jump to card {n+1}` |
| Segmented control | `{segment} segment, currently {active ? 'selected' : 'not selected'}` | `Double-tap to view {segment}` |
| Filter chip × | `Clear {filter} filter` | — |
| Half-sheet handle | `Sheet handle` | `Drag down to dismiss` |
| Sync banner RETRY | `Retry sync` | `Double-tap to try again` |

### 8.4 Dynamic Type behavior

- Hero numbers: `.dynamicTypeSize(...DynamicTypeSize.accessibility3)`. Above `accessibility3` use `.minimumScaleFactor(0.7)` rather than truncating.
- Card-header labels (JBM 11pt / 0.16em): clamp at `accessibility2` — already at floor. Above that, allow wrapping to two lines.
- List row primary: scale with default behavior. Truncate with `…` at `xxxLarge`+.
- Tile values: scale with system. Tile labels stay clamped.

---

## 9 · Implementation phase ordering

Each phase ends in a build (`xcodebuild -scheme OPS -destination 'generic/platform=iOS' -quiet build`) and one or more atomic commits. Sequential ordering — each phase depends on the one before.

### Phase A — Token additions
1. Add 3 mobile-bright Color assets to `Assets.xcassets`
2. Add `oliveMobile`, `tanMobile`, `roseMobile`, `lineSoft` tokens to `OPSStyle.Colors`
3. Add `heroNumber` typography token
4. **Build + commit** — `feat(books): add mobile-bright status tokens + hero-number typography`

### Phase B — Shared components
5. Build `BooksDrillTile.swift`
6. Build `BooksSyncBanner.swift`
7. Build `BooksSkeleton.swift`
8. Build `BooksCardError.swift`
9. Build `BooksDrillFilterChip.swift`
10. Build `BooksScopeHintBadge.swift`
11. Build `BooksPTRIndicator.swift`
12. **Build + commit** — `feat(books): shared components for Mission Deck (drill tile, sync banner, skeleton, error, filter chip, scope hint, PTR)`

### Phase C — ViewModel additions
13. Migrate `weightedForecastByStage` to `[StageForecast]` (with avgProbability + count)
14. Add `failedCards`, `cardError(_:)`, `retry(_:)`
15. Add `syncState`, `lastSyncedAt`, `hasEverLoaded`
16. Apply worst-loser-always-include logic in `computeJobNets`
17. **Build + commit** — `feat(books-vm): per-stage probability, per-card error tracking, sync state, worst-loser floor`

### Phase D — Carousel chrome
18. Update `HeroCarousel.inlineHeader` — new typography (JBM 11pt / 0.16em / 600), scope-hint badge
19. Update `HeroCarousel.dots` — 22×6 capsule grow, 6×6 inactive, 200ms width animation
20. Update `PeriodPill` — 44pt minimum (no chevron rotation per D11)
21. **Build + commit** — `refactor(books): mission-deck inline header + dot pagination + period pill`

### Phase E — Cards (5 commits, one per card)
22. Rewrite `PLCard.swift`. Build + commit `feat(books): PLCard mission-deck — 60pt hero, simplified margin caption`
23. Rewrite `CashFlowCard.swift`. Build + commit `feat(books): CashFlowCard mission-deck — sparkline with bad-week markers`
24. Rewrite `ARCard.swift`. Build + commit `feat(books): ARCard mission-deck — ramp meter + bucket grid + bigger TOP CHASE`
25. Rewrite `ForecastCard.swift`. Build + commit `feat(books): ForecastCard mission-deck — stage bars with probability indicator`
26. Rewrite `JobsCard.swift`. Build + commit `feat(books): JobsCard mission-deck — diverging bar chart`

### Phase F — BooksTabView wiring
27. Replace `underlineSegmentedControl` with `insetPillSegmentedControl`
28. Mount `BooksSyncBanner` above hero (state-driven)
29. Mount `BooksDrillFilterChip` below segments (state-driven)
30. Add `.presentationDetents([.medium, .large])` to AR sheet
31. Add `.refreshable` with custom PTR indicator
32. Wire per-card skeleton / error / empty state branching
33. **Build + commit** — `feat(books): BooksTabView mission-deck wiring (sync banner, filter chip, inset segments, half-sheet, PTR)`

### Phase G — Tab bar polish
34. Replace `CustomTabBar` spring animation with `OPSStyle.Animation.panel`
35. **Build + commit** — `refactor(tabbar): replace spring physics with OPS canonical easing`

### Phase H — VoiceOver labels
36. Add `.accessibilityLabel()` + `.accessibilityHint()` to every relevant element per § 8
37. **Build + commit** — `a11y(books): VoiceOver labels for carousel, tiles, chrome`

### Phase I — Verification
38. Build clean. All warnings inventoried (no new warnings added).
39. Run app on physical iPhone. Walk every flow in § 10 below.
40. Update bible — `ops-software-bible/09_FINANCIAL_SYSTEM.md` § 1424 (Books Phase 3 rewrite) and `ops-software-bible/02_USER_EXPERIENCE_AND_WORKFLOWS.md` (Books flow). **Commit** — `docs(bible): books phase 3 mission-deck visual rebuild`

---

## 10 · Verification plan

### 10.1 Build
- `xcodebuild -scheme OPS -destination 'generic/platform=iOS' -quiet build` succeeds after every phase
- Zero new warnings vs main baseline

### 10.2 SwiftUI Previews
Every card file has working `#Preview` blocks that render against `MoneyDashboardViewModel.previewStub()` / `previewEmpty()`. Tap Resume in canvas and verify:
- Seeded state matches the design's seeded data (numbers in § 5.3 of the context-package doc)
- Empty state shows the correct `//` label and `$0` / `0` / `—` per the table in § 4.8
- Error state mounts when `cardError(.X)` returns true (new preview stub variant: `previewWithCardError(_:)`)
- Skeleton state mounts when `!hasEverLoaded && isLoading` (new preview stub: `previewSkeleton()`)

Add the new preview stub variants to `BooksPreviewSupport.swift`.

### 10.3 On-device manual flows

| # | Flow | Pass criteria |
|---|---|---|
| 1 | Owner role, cold launch | All 5 cards visible. Default Card 1. Hero number 60pt Mohave. Margin caption `36% MARGIN` in olive |
| 2 | Swipe between cards | Light haptic on each swap. Inline header label changes. Dot pagination active capsule slides 6→22pt over 200ms |
| 3 | Period menu | Pill 44pt tall. Tap opens native menu. 8 options listed. Selecting MTD morphs Cards 1/2/5 numbers, leaves Cards 3/4 unchanged. Card 3 + 4 show colored scope hint badge (rose `ALL OPEN`, accent `ACTIVE`) |
| 4 | Card 1 drill — OUTSTANDING tile | Drill applies to Invoices/overdue. Filter chip `OVERDUE ×` appears below segments. Tap × clears |
| 5 | Card 1 drill — FORECAST tile | Switches to Estimates/sent. Filter chip `SENT ×` appears |
| 6 | Card 3 drill — TOP CHASE tile | Opens half-sheet at `.medium` detent. Drag handle visible. Drag up to `.large`. Swipe down dismisses |
| 7 | Card 2 sparkline | Net cash line in olive with area fill. Dots at each point. Any week where out > in has a rose dot. X-axis labels visible at edges |
| 8 | Card 5 diverging chart | Positive jobs extend right of center, negative extend left. Worst loser visible even if not top-5 by absolute (use seed data with a `-$3,000` loss when top 5 are all positive) |
| 9 | Segmented control | Inset-pill style. Active segment has neutral fill + inset top-light, no accent. Tap switches segment with light haptic |
| 10 | Scroll collapse | Scroll down — hero collapses to single-line strip in glass-dense bg. Segmented control sticks below. Scroll up re-expands |
| 11 | Operator role | Hero hidden entirely. Only `ESTIMATES` + `EXPENSES` segments visible. Lists render |
| 12 | Crew role | Books routes directly to `MyExpensesView`. No carousel, no hub |
| 13 | Reduced motion ON | Numbers render at final value, bar fills static, sparkline static, capsule transitions instant. PTR arc doesn't rotate |
| 14 | Offline (Airplane mode + cold open) | Cached data renders immediately. Sync banner shows `SYS :: OFFLINE · CACHED HH:MM` with RETRY. Tap RETRY → attempts re-sync, returns to offline state with refreshed timestamp |
| 15 | Cold install (no cache) | Skeleton system renders for ~1s, then real data replaces individual cards as each datum resolves. No global spinner |
| 16 | Card-level error | (Simulate by failing a single repo fetch in debug.) That single card renders `BooksCardError`. Other cards stay live. RETRY button works |
| 17 | PTR | Pull to refresh — custom OPS-mark + arc + `SYNCING` indicator. On complete, shows `SYNCED · HH:MM` for 1.5s then fades |
| 18 | VoiceOver | Enable VoiceOver. Each card announces per § 8.1. Each tile announces per § 8.2. Chrome announces per § 8.3 |
| 19 | Dynamic Type | Set to `accessibility3` — hero numbers scale. Set to `accessibility5` — hero scales to floor via `minimumScaleFactor(0.7)`. Card-header labels wrap to 2 lines at `xxxLarge`+ |

### 10.4 Bible update verification
- `09_FINANCIAL_SYSTEM.md` § 1424 reflects Phase 3 / Mission Deck
- `02_USER_EXPERIENCE_AND_WORKFLOWS.md` Books section updated

---

## 11 · Out of scope

Explicitly excluded — do not touch in this rebuild. Each has its own track:

| Out-of-scope | Reason |
|---|---|
| Pipeline tab itself | `PIPELINE TAB - P1-1` spawn owns it |
| `CashflowForecastCard` mounted below hero | `CASHFLOW FORECAST - P1-1` spawn owns it. Stays as-is during this rebuild |
| `AppHeader` visual (title shrink on scroll — D15) | Shared component used by every tab. Defer to a separate spawn |
| `CustomTabBar` icon design or layout | Shared. Spring → OPS easing is in scope; visual redesign isn't |
| The list views below segments (`InvoicesListView`, `EstimatesListView`, `ExpensesListView`, `MyExpensesView`) | Existing implementations, out of scope per handoff § 6 |
| `FloatingActionMenu` | Global, not Books-specific |
| New SwiftData migrations or Supabase schema changes | None needed — VM additions are computed, not stored |
| The 6th card (forward cashflow) | Future scope per handoff § 12 |

---

## 12 · Coordination notes

- **Parallel sessions:** the `LeadsTabView` work in another agent's session mirrors Books patterns. If their work introduces a `LeadsDrillTile` analog to my `BooksDrillTile`, we may want to consolidate to a shared `OPSDrillTile` in a follow-up. Not blocking this work.
- **Bible updates:** I'll write Phase 3 sections fresh in the bible after Phase I verification passes. Don't write speculatively before manual flows pass on-device.
- **Branch:** all work on `feat/books-mission-deck`. Merge back to main with `--no-ff` to preserve the rebuild as a coherent shape in history.
- **Commit cadence:** atomic per phase step. Don't bulk-stage. Stage by name. No Claude co-author.

---

## 13 · Verified facts log

Recorded so the implementation can rely on these without re-verifying:

| Fact | Source | Verified |
|---|---|---|
| Mission Deck is the approved direction | `docs/design-briefs/books-handoff/HANDOFF.md` § 1 | 2026-05-19 |
| Existing Books card architecture: 5-card carousel + 3-segment list | `OPS/Views/Books/BooksTabView.swift:83-198` | 2026-05-19 |
| `MoneyDashboardViewModel.weightedForecastByStage` currently `[(stage: PipelineStage, value: Double)]` | `OPS/ViewModels/MoneyDashboardViewModel.swift:147` | 2026-05-19 |
| `MoneyDashboardViewModel.topProjectsByNet: [JobNet]` exists, populated by `computeJobNets` | `OPS/ViewModels/MoneyDashboardViewModel.swift:157` | 2026-05-19 |
| `OPSStyle.Animation.standard` resolves to `cubic-bezier(0.22, 1, 0.36, 1)` 250ms | `OPS/Styles/OPSStyle.swift:551` | 2026-05-19 |
| `OPSStyle.Layout.touchTargetMin = 44.0` | `OPS/Styles/OPSStyle.swift:370` | 2026-05-19 |
| `Color("AccentPrimary")` = `#6F94B0` | `OPS/Styles/OPSStyle.swift:51` | 2026-05-19 |
| `CustomTabBar` spring animation lives at lines 61 and 74 | `OPS/Views/Components/Common/CustomTabBar.swift` | 2026-05-19 |
| `CashflowForecastCard` mounted in BooksTabView (separate spawn — leave alone) | `OPS/Views/Books/BooksTabView.swift:142-145` | 2026-05-19 |
| Pre-existing Leads WIP is on main and not mine to touch | Saved feedback `feedback_ask_before_staging.md` | 2026-05-19 |
| Mobile-bright tag spec (0.32 fill / 0.88 border / weight 600 / brighter text) | `HANDOFF.md` § 3.Colors, `tokens.css` lines 64-66 | 2026-05-19 |
| Empty-state copy per card | `HANDOFF.md` § 12 | 2026-05-19 |
| Sync banner / skeleton / error / PTR specs | `HANDOFF.md` § 11 | 2026-05-19 |
| VoiceOver labels per element | `HANDOFF.md` § 10 | 2026-05-19 |
