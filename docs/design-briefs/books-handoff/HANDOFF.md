# Books Tab — Engineering Handoff

| | |
|---|---|
| **Surface** | OPS iOS app · Books tab |
| **Frame** | 390 × 844pt (iPhone 14/15 Pro), portrait only |
| **Direction** | **B — Mission Deck** (selected from three explored) |
| **Status** | Design approved, ready to implement against existing Books MVP |
| **Last updated** | 2026-05-19 |
| **Reference files** | `Books — Handoff.html` (live prototype + tokens) · `index.html` (full design exploration) |

---

## 1 · What you're building

A full visual rebuild of the iOS Books tab. The existing implementation (May 2026 carousel-first MVP) was a loose first pass — this redesign tightens every element while keeping the architecture intact.

**The architecture stays:**
- 5-card hero carousel (P&L · Cash flow · A/R aging · Forecast · Jobs)
- Inline header with active-card label + period pill
- 3-segment list below (Invoices · Estimates · Expenses)
- Bottom tab bar with Books as second tab
- Drill-tile interactions inside cards change the active segment + filter
- Hero collapses to single-line strip on vertical scroll

**The visual treatment changes everywhere.** See § 4 for the diff from the current MVP.

---

## 2 · Files to read first

| File | What's in it |
|---|---|
| `Books — Handoff.html` | The live interactive prototype + token sheet on a single page. Open this first. |
| `HANDOFF.md` (this file) | Written brief — locked decisions, open questions, implementation notes |
| `tokens.css` + `src/tokens.js` | Canonical token values. Every CSS variable + JS mirror. |
| `src/seed.js` | Realistic data fixtures used in the prototype |
| `src/direction-b.jsx` | The 5 card components (`BCard_PL`, `BCard_Flow`, `BCard_AR`, `BCard_Forecast`, `BCard_Jobs`) and their building blocks (`BTile`, `BSegments`, `BPill`, `BDots`, etc.) |
| `src/b-prototype.jsx` | The live prototype state machine — carousel ref, scroll-collapse, period menu, drill handlers, A/R sheet |
| `src/frame.jsx` | The iOS chrome (status bar, AppHeader stub, tab bar). The real app already has these — use the spec values |
| `src/states.jsx` | Static mocks for empty, overflow, collapsed, period-menu-open, segment states, drill, A/R sheet, offline, operator role |
| `src/handoff.jsx` | The token sheet shown on `Books — Handoff.html` and at the bottom of `index.html` |
| `index.html` | Full design exploration: A · B · C directions + states + handoff sheet. Useful for "why this and not that" conversations |

---

## 3 · Token reference

**Read this first if you take nothing else from this doc.** All values trace to the OPS Design System (`/projects/<id>/colors_and_type.css` + `mobile/MOBILE.md`).

### Colors

| Role | Token | Value |
|---|---|---|
| Canvas | `--bg` | `#000000` |
| Text primary | `--text` | `#EDEDED` |
| Text secondary | `--text-2` | `#B5B5B5` |
| Text tertiary | `--text-3` | `#8A8A8A` |
| Text decorative (`//` slashes) | `--text-mute` | `#6A6A6A` |
| Accent (CTA + focus + Card 4 bars) | `--ops-accent` | `#6F94B0` |
| Olive (positive, in-bars, profitable) | `--olive` | `#9DB582` |
| Tan (attention, out-bars, expiring) | `--tan` | `#C4A868` |
| Rose (overdue, cost, losers, A/R hero) | `--rose` | `#B58289` |
| Brick (90+ overdue, destructive borders) | `--brick` | `#93321A` |
| Receivables ramp tone (31–60D bucket) | `--fin-receivables` | `#D4A574` |

**Mobile delta:** earth-tone status tags use 0.32 fill, 0.88 border, ~25% brighter text (`#B5C998` / `#DBC07F` / `#C99AA1`), weight 600. See `T.oliveM/tanM/roseM` in `tokens.js`.

**Accent discipline:** steel blue appears on **primary CTA fill + focus ring only**, plus Card 4 (Forecast) bars and the "ACTIVE" scope hint badge. Never on toggles, links, sidebar nav, segmented control, or any other data color.

### Surfaces

| Layer | Background | Border | Radius |
|---|---|---|---|
| L0 — canvas | `#000000` | — | — |
| L1 — section card (lists, sheets) | `rgba(18,18,20,0.58)` + `blur(28px) saturate(1.3)` | `1px solid rgba(255,255,255,0.09)` | 10px |
| L1 dense — modals, popovers (period menu) | `rgba(18,18,20,0.78)` + same blur | same | 10–12px |
| L2 — drill tiles inside cards | `rgba(255,255,255,0.04)` | `1px solid rgba(255,255,255,0.08)` | 6px |
| L3 — tags, badges, dots | inherits | — | 4px |

**Top-edge gradient** on L1 surfaces: `linear-gradient(180deg, rgba(255,255,255,0.04), transparent 40%)` via a `::before` pseudo. The only "lit from above" cue.

**No box-shadows on dark backgrounds.** Depth is glass + hairlines.

**Hairlines:** standard divider `rgba(255,255,255,0.10)` (`--line`). Web uses 0.06 for inside-card dividers; mobile bumps to 0.10 for outdoor-glare contrast. Chart axis gridlines stay at 0.06.

### Typography

Three families, one job each. **11px floor.** Numbers are **always** JetBrains Mono with `font-feature-settings: "tnum" 1, "zero" 1`.

| Role | Family | Size | Notes |
|---|---|---|---|
| Hero number | Mohave 300 | 60px | Net cash, total outstanding, weighted forecast. Tnum. |
| Screen title (`// BOOKS`) | Cake Mono 300 | 28px (22px when scrolled) | AppHeader |
| Card header label | JetBrains Mono | 11px / 0.16em / 600 | `P&L`, `CASH FLOW`, etc. **Not Cake Mono.** |
| Scope hint badge | JetBrains Mono | 9px / 0.16em / 600 | `ALL OPEN` (rose), `ACTIVE` (accent) |
| Tile label | JetBrains Mono | 9.5px / 0.18em / 500 | `OUTSTANDING`, `FORECAST` |
| Tile value | JetBrains Mono | 18px / 500 | Tile numeric values, tnum |
| List row primary | Mohave 500 | 15px | Client names |
| List row meta | JetBrains Mono | 10px / 0.10em | Invoice numbers, dates |
| Status tag | JetBrains Mono | 9.5px / 0.14em / 600 | Mobile-bright contrast (see above) |
| Tab bar label | JetBrains Mono | 9px / 0.14em | |
| Body / margin caption | Mohave 400 | 11px | "36% MARGIN" etc. |

**Cake Mono is always weight 300, always uppercase, never body text.** If it needs to read heavier, increase size, not weight.

### Spacing (8px grid)

| Token | Value | Use |
|---|---|---|
| Canvas padding (horizontal) | 20pt | Both sides, all content |
| L1 card inset | 16pt | Internal padding |
| L2 tile inset | 14pt | Drill tiles |
| Section gap | 24pt | Between major sections |
| Card gap | 8pt | Between L2 tiles |
| Vertical rhythm inside hero | 6 / 22 / 24 / 20 / 22pt | See diagram in token sheet |

### Radii

| Element | Value |
|---|---|
| L1 panel | 10px |
| L2 tile | 6px |
| Period pill | 12px (slightly more rounded — it's a pill) |
| Button / segment | 5px |
| Tag / chip | 4px |
| Progress bar | 2px |

**No 999px pills** except avatars.

### Motion

**Single easing:** `cubic-bezier(0.22, 1, 0.36, 1)`. No spring. No bounce.

| Event | Duration |
|---|---|
| Hover transitions | 150ms |
| Panel enter, card swap | 200ms |
| Page transitions, half-sheet rise | 250ms |
| Half-sheet dismiss | 200ms (snappier exit) |
| Dot pagination width | 200ms |
| Period menu open | 200ms (fade + 8px translateY + 0.96 scale-from-corner) |
| Tile press (in/out) | 100ms / 150ms |
| Hero count-up | 800ms (optional — skip if perf budget is tight) |
| Bar chart grow | 400–600ms + 50ms per bar stagger |

**Reduced motion is required.** Every animation must check `@media (prefers-reduced-motion: reduce)` and fall back to a 150ms opacity crossfade. Bars render fully filled, numbers render at final value, card swap is instant.

### Touch targets

**44 × 44pt minimum.** Even if the visible element is smaller, the tap area must extend. Specifically:
- Period pill: visible ~36pt, extends to 44pt via padding
- Dot pagination: visible 6pt, extends to 44 × 44pt via inset hit-zone
- Segments: 44pt explicit
- Tiles: 80pt (full tile is tappable)
- Menu items: 44pt

---

## 4 · Diff from current MVP

If you have the current Books code open, these are the visible changes:

| Element | Current MVP | New design |
|---|---|---|
| Hero number | Mohave 300, ~30px | **Mohave 300, 60px.** Same family, much bigger. |
| Card header label | Cake Mono uppercase | **JetBrains Mono 11px / 0.16em / 600.** Match the rest of the tactical micro-label system. |
| Period pill | 12px radius, ~32pt tall | **12px radius, 44pt minimum.** Bigger touch target. Chevron rotates 180° on open. |
| Drill tiles | Variable padding/styling | **Uniform L2 cards: `rgba(255,255,255,0.04)` bg, 6px radius, 14px padding, 80pt min-height, → chevron in top-right.** Press state: bg → 0.08, border → 0.18. |
| Segmented control | Underline-style | **Inset-pill style: 3px container padding, 5px radius, active segment is `rgba(255,255,255,0.10)` fill with 0.22 border + 1px inset top-light.** No accent. |
| Dot pagination | Static dots | **Active dot is a 22 × 6 capsule that grows from 6 × 6.** 200ms width animation. |
| Margin meter (Card 1) | Single fill bar | **6pt bar with `--tan-soft` track and `--olive` fill at margin %.** |
| Cash flow chart (Card 2) | Paired weekly bars | **Sparkline of net cash + olive area fill + dots at each point.** A "bad week" gets a rose dot. Spec-flag for review — could revert to paired bars if owners prefer. |
| A/R hero color (Card 3) | Default text | **`--rose` for the hero number** — the only card where the headline is the bad news. |
| Forecast bars (Card 4) | Default | **Steel-blue accent bars on `--ops-accent-muted` tracks.** Stage probability shown as `×62%` next to amount. |
| Jobs chart (Card 5) | Absolute-value bars | **Diverging bars from center axis.** Olive right, rose left. Worst loser is always included even if not in top 5 by abs value. |
| Scroll-collapsed strip | Existing | **Same shape, brighter contrast: active card primary metric left, A/R glance right, capsule + dots, glass-dense bg.** AppHeader title shrinks from 28 → 22px. |
| Status tags | Web alpha (0.14 / 0.34) | **Mobile alpha (0.32 / 0.88), text ~25% brighter, weight 600.** |
| Touch targets | Varied | **44pt minimum everywhere.** |
| Focus ring | Web (1.5px) | **2px accent + 2px offset.** |

---

## 5 · Behavior spec

These rules from the design-intent doc are unchanged — restating them so they're in one place.

| Behavior | Rule |
|---|---|
| Period scope | Pill changes period for Cards 1, 2, 5. Cards 3 (A/R) and 4 (Forecast) ignore the pill — show colored scope hint badge (`ALL OPEN` rose / `ACTIVE` accent). Pill stays visible on all cards. |
| Permission gating | Cards 1/2/3/5 require `finances.view`. Card 4 requires `pipeline.view`. Zero permitted cards (operator) → entire hero hides, user lands on segmented control directly. Crew bypasses Books entirely → MyExpensesView. |
| Drill-downs | Tile taps inside a card change the active segment + filter. Never navigate away from Books. Hero numbers do NOT tap (they're labels). |
| Outstanding drill | Card 1 OUTSTANDING tile → switch to INVOICES segment, apply OVERDUE filter. Filter chip shows below segments with × to clear. |
| Forecast drill | Card 1 FORECAST tile → switch to ESTIMATES segment, apply SENT filter. |
| TopChase drill | Card 3 TOP CHASE tile → open A/R aging detail half-sheet (62% screen height). |
| Header collapse | On vertical scroll past 80pt, hero collapses to single-line strip. Segmented control sticks to top. Scroll up re-expands. |
| Last-viewed persistence | Active carousel card persists across app launches: `@AppStorage("books.lastViewedCard")`. |
| Default segment | INVOICES on first launch: `@AppStorage("books.selectedSegment")`. |
| Reduced motion | Bars render fully filled, numbers render at final value, card swap is instant. All transitions → 150ms opacity. |
| Offline | First paint from cached SwiftData. No spinner before content. Sync banner appears at top when offline: `SYS :: OFFLINE · CACHED HH:MM` with RETRY action. |

---

## 6 · Locked vs open

### Locked (do not change without design review)

- The 5 cards and their 5 questions
- The 3 segments and their order
- All token values (colors, type, spacing, radii, motion)
- Mobile contrast deltas (tag alphas, weight 600, brighter text)
- Touch target floors (44pt)
- Reduced-motion fallbacks
- Voice: terse, UPPERCASE for authority, `//` prefixes, `[brackets]`, no emoji, no exclamation points
- AppHeader visual treatment (existing component, out of scope)
- The list views below the segmented control (existing — out of scope)

### Open — wants designer call

- **Card 2 chart treatment.** Currently a sparkline with bad-week marker (this design). The MVP had paired bars. We could ship either. If you find the sparkline is read as more abstract than the paired bars, flag it and we'll re-evaluate. Both fit the system.
- **Card 5 worst-loser inclusion logic.** Current rule: always include the worst-margin job even if it falls outside top 5 by absolute net. Confirm this matches business intent.
- **Hero count-up animation (800ms).** Optional. Cut if perf budget is tight or if the snap-when-period-changes feels better without it.
- **Card 1 margin caption format.** Currently `"36% MARGIN  ·  +$42,180 ON $118.4K"`. Verify this reads cleanly with real data shapes.

---

## 7 · Implementation notes

- **Don't port the inline-style approach from the prototype.** The prototype uses inline styles for self-contained portability. In production, lift styles into SwiftUI modifiers / view structs that consume the canonical token names.
- **Numbers are always tabular.** Apply `monospacedDigit()` or the equivalent feature flag to every numeric `Text`. Hero numbers in Mohave 300 also use tabular features.
- **Card height is content-driven.** Don't pin a fixed card height — the cards vary slightly. The carousel snaps on full-card width only.
- **Carousel uses `containerRelativeFrame(.horizontal)` with `.scrollTargetBehavior(.paging)`** in SwiftUI. Already in the current code — keep it.
- **Sticky segments.** When the hero collapses, the segmented control should be `position: sticky` to the top of the scroll area, just under the AppHeader. The collapsed strip lives above it.
- **Period menu** is a native iOS `Menu` overlay on `Button` — already in current `PeriodPill.swift`. Just restyle the trigger.
- **A/R sheet** is a `.sheet` presenting `ARAgingDetailView`. Use `.presentationDetents([.medium, .large])` to allow drag-to-expand.
- **The agent provenance token** (`--ops-agent` / lavender `#8A7FB8`) is reserved for future AI-authored content. Not used in Books today. Don't accidentally introduce it.

---

## 8 · Anti-patterns to avoid

These are explicitly banned in the OPS Design System; called out because they're easy to drift into:

- Drop shadows on dark backgrounds
- Accent color on toggles, links, sidebar nav, or segmented control active state
- Emoji anywhere (not even in error states)
- Exclamation points in copy
- "Welcome back!" / "Oops!" / coaching-tone language
- Cake Mono in body copy (always uppercase, display only)
- Mohave for numbers (numbers are always JetBrains Mono)
- Filled icons on active tab
- Spring physics / bounce
- 999px pill buttons (except avatars)
- Default 404 illustration pages

---

## 10 · Accessibility (VoiceOver labels)

Every hero, drill tile, dot, and carousel card must announce correctly. Strings below are tactical-voice and ready to use; localize keys when wired.

### Carousel cards

| Element | VoiceOver label | Hint |
|---|---|---|
| Carousel container | `Books dashboard, 5 cards, swipe with two fingers to navigate` | (rotor: heading) |
| Card 1 active | `P and L. Net cash {fmt$(net)} this {period.label}. {pct}% margin.` | `Double-tap a tile for details` |
| Card 2 active | `Cash flow. Net cash {fmt$(net)} over {weeks} weeks. {fmt$(avg)} per week average.` | — |
| Card 3 active | `Accounts receivable. {fmt$(total)} outstanding across {open} open invoices, {overdue} overdue. Always all-open.` | — |
| Card 4 active | `Forecast. {fmt$(weighted)} weighted across {count} active opportunities. {closeRate}% close rate.` | — |
| Card 5 active | `Jobs. {profitable} profitable, {losers} losing money this {period.label}. Average margin {avgPct}%.` | — |

### Drill tiles

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

### Chrome

| Element | Label | Hint |
|---|---|---|
| Period pill | `Period selector, currently {period.label}` | `Double-tap to change period` |
| Dot pagination dot N | `Card {n+1} of 5` | `Double-tap to jump to card {n+1}` |
| Segmented control segment | `{segment} segment, currently {active ? 'selected' : 'not selected'}` | `Double-tap to view {segment}` |
| Filter chip × | `Clear {filter} filter` | — |
| Half-sheet handle | `Sheet handle` | `Drag down to dismiss` |
| Sync banner RETRY | `Retry sync` | `Double-tap to try again` |

### Dynamic Type

- Hero numbers: scale with `.dynamicTypeSize(...DynamicTypeSize.accessibility3)`. At sizes above `accessibility3`, the hero may overflow; clip with `.minimumScaleFactor(0.7)` rather than truncating.
- Card-header labels (JetBrains Mono 11px / 0.16em): clamp at `accessibility2` — they're already at the floor. Above that, allow wrapping to two lines.
- List row primary: scale with default behavior. Truncate with `…` at `xxxLarge`+.
- Tile values: scale with system. Tile labels stay clamped.

---

## 11 · Loading, error, and refresh states

### First paint (cached)

When the tab opens with cached SwiftData available — which should be the common case — **paint the real numbers immediately**. No spinner before content.

If a sync request is in flight after the first paint, show the **slim sync banner** above the inline header:

```
[●] SYS :: SYNC · 08:42
```

- Bar: `padding: 6px 12px`, `--surface-input` bg, 1px `--line` border, 4px (rChip) radius.
- Pulse dot: 6×6, `--text-3` color, 1.5s ease-in-out pulse to `rgba(255,255,255,0.08)` and back.
- Text: JetBrains Mono 10px, `--text-3`, 0.16em tracking, weight 500.
- Timestamp is the last-successful-sync time, `HH:MM` local.
- Banner fades out (200ms) when sync completes successfully.

See **`states / s-skeleton`** artboard for the visualization.

### Skeleton — no cache available

If the first paint has *no* cached data (fresh install, cleared cache), show a **skeleton hierarchy** that matches the layout slot-for-slot:

- All text blocks → rounded 2px rectangles in `--fill-neutral-dim` (`rgba(255,255,255,0.06)`).
- Pulse: `bg 0.03 → 0.08 → 0.03` over 1.5s, `ease-in-out`, infinite.
- L2 drill tiles render with real background + border but skeleton content inside.
- Segmented control: full 44pt skeleton bar.
- List rows: 3 placeholder rows in the glass L1 wrapper.
- Reduced motion: pulse animation is suppressed; skeleton renders static at the brighter (0.08) value.

Replace skeletons individually as each datum resolves — don't wait for the full payload.

### Card-level error

If a single card's data fetch fails (e.g., the P&L call 500s but A/R succeeds), replace **just that card's body** with the error state. Other cards stay live. Sync banner stays visible.

```
        —              ← Mohave 300, 48px, --rose
// ERROR — LOAD FAILED ← JetBrains Mono 10.5px, --rose, 600
Couldn't fetch this period. Showing cached data above the
fold; tap retry to try again.
                        ← Mohave 13px, --text-2
       [RETRY →]        ← Cake Mono 13px, --rose, rose-soft bg
```

- Em-dash hero in `--rose` Mohave 300 48px (smaller than the success hero — error doesn't get the headline real estate).
- Tactical label `// ERROR — LOAD FAILED` matches the design-system error pattern.
- Body text is sentence case (it's content), Mohave 14px, `--text-2`.
- RETRY button: `--rose-soft` bg, `--rose-line` border, `--rose` text, 44pt min-height.
- Hero numbers and tile values are NOT rendered. Drill tiles disappear.
- The inline header (label + period pill) stays — the user can still change period to retry.

See **`states / s-error`** artboard.

### Pull-to-refresh

Native iOS rubber-band, custom indicator:

```
[OPS mark]  [progress arc]  SYNCING
```

- OPS mark: 16px, `--text-3`, monochrome.
- Progress arc: 18px circle, 1.5px stroke. Track in `--line`, arc in `--text-2`. Rotates 360° in 900ms linear, infinite.
- Label: JetBrains Mono 10px, `--text-3`, 0.18em tracking, weight 500. Reads `SYNCING` while active, fades to `SYNCED · 08:42` for 1.5s after success, then hides.
- Triggered: standard iOS PTR threshold (60–80pt pull).
- On release before threshold: snap-back, no sync.
- On release past threshold: indicator stays visible until sync completes, then fades (200ms).
- Reduced motion: arc rotation is suppressed; show just the OPS mark + static label.

See **`states / s-ptr`** artboard.

---

## 12 · Empty-state copy per card

When a card has no data — fresh install, no business activity yet — render the empty pattern with these exact strings. **Never** "no jobs yet!", **never** illustrations, **never** call-to-action language.

| Card | Hero | Label | Tile copy |
|---|---|---|---|
| **P&L** | `$0` | `// NO ACTIVITY THIS PERIOD` | Both tiles: `$0` / `0 ITEMS`, `--text-3` |
| **Cash flow** | `$0` | `// NO PAYMENTS THIS PERIOD` | SALES `$0` / TRAILING · AVG/WK `$0` / PER WEEK · DAYS `—` / TO PAY |
| **A/R aging** | `$0` | `// NO OPEN INVOICES` | Top chase tile hidden entirely (no chase = no tile) |
| **Forecast** | `$0` | `// NO ACTIVE OPPORTUNITIES` | CLOSE RATE `—` / LAST 90D · STALE `0` / > 14D IDLE |
| **Jobs** | (no hero) | `// NO COMPLETE JOBS THIS PERIOD` | PROFITABLE `0` / AVG MARGIN `—` / LOSERS `0` |

Below the carousel: the segmented control still shows. Each segment that's empty renders its own empty state:

- INVOICES empty: hero `$0`, label `// NO INVOICES`. Optional `NEW INVOICE` CTA below (primary outlined-accent button, 52pt height).
- ESTIMATES empty: hero `$0`, label `// NO ESTIMATES`. Optional `NEW ESTIMATE` CTA.
- EXPENSES empty: hero `$0`, label `// NO EXPENSES`. Optional `NEW EXPENSE` CTA.

The CTA is only shown when the empty state is *resolvable by the user* — for owners/admins. For crew or scope-limited roles, no CTA — just the empty state.

See **`states / s-empty`** artboard for the carousel-level treatment.

---

## 13 · Questions / follow-ups

When you start implementation, ping the design channel for:
- Real localization keys — current prototype uses canonical OPS voice strings; validate against `Localizable.strings`
- Confirmation on the diverging-bar vs absolute-value Jobs chart (the MVP was absolute; we propose diverging)
- Confirmation on the sparkline vs paired bars on Card 2
- Real numbers from product for the cash-flow week-bucket count per period (currently 8 weeks shown regardless)

— design
