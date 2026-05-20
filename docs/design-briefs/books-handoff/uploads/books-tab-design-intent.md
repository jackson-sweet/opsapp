# Books Tab — Design Intent

| | |
|---|---|
| **Surface** | OPS iOS app — Books tab |
| **Frame** | 390 × 844pt (iPhone 14/15 Pro), portrait only |
| **Owner** | Engineering will implement against the designer's handoff |
| **Last refreshed** | 2026-05-19 |
| **Companion docs** | `ops-design-system/project/DESIGN.md` (visual system) · `ops-design-system/project/mobile/MOBILE.md` (iOS overrides) · `ops-ios/docs/superpowers/specs/2026-05-11-books-ui-reconstruction-design.md` (current architecture spec) |

---

## 1 · Purpose

The Books tab is OPS's **money command center**. It exists so a trades business owner — typically a stressed-out roofer, plumber, electrician, or landscaper — can answer five questions about their money in less than ten seconds, between job sites, on a phone, often with one hand.

It is **not** a finance app. It is **not** a reporting suite. It is **not** a place to do bookkeeping. It is a glance-and-go dashboard backed by drill-throughs into the underlying invoices, estimates, and expenses.

The test we use: *does this make a stressed-out business owner feel like they just found the thing that gives them their life back?* If it feels like a tech demo, it's wrong. If it feels like a lifeline, it's right.

---

## 2 · User context

**Persona.** Trade business owner, mid-30s to 60s, runs a 2–25 person crew. Spends most of their day in the truck, on rooftops, at job sites. Checks the app between calls, often while standing outside.

**Environment.**
- One-handed thumb use, frequently.
- Bright daylight is the common viewing condition. Indoor office use is the exception.
- Connectivity is unreliable — cached data needs to render fully before any network call resolves.
- Glove use is common in cold seasons (less critical for Books than for field-crew screens, but still a constraint).

**Mindset.**
- They are checking, not browsing. Information should be the first thing they see.
- They are time-pressed. The five questions need to be answerable at a glance.
- They are anxious about money. The visual register should be calm and confident, never alarming, never marketing-cheerful.

---

## 3 · Brand & aesthetic

OPS is **military tactical minimalist**. Sharp, refined, quiet authority. Every element earns its place.

**Reference points:** xAI · SpaceX mission control · Apple Pro apps (Logic, Final Cut, Xcode dark) · Bloomberg Terminal · military HUD aesthetics.

**Never:** playful, elastic, bubbly, 2019 SaaS template, "modern startup," cute illustrations, marketing-cheerful copy.

The vibe is *"hell. yeah."* not *"Hell yeah!"*. Understated confidence.

**Voice rules** (non-negotiable, apply to every label, button, empty state, tooltip):
- Terse and tactical. No marketing-speak. No exclamation points. No emoji ever.
- Sentence case for content (entity names, addresses, notes). **UPPERCASE for authority** — page titles, section headers, buttons, badges, status.
- `//` prefix for section headers (e.g. `// BOOKS`). `[brackets]` for instructional micro-text. `SYS::` for system state.
- Numbers always formatted (`$12,480`, `87%`, never raw or unrounded). Empty state is `—` (em-dash), never `N/A`, never `0` if the state is genuinely empty rather than zero.

**Voice examples relevant to Books:**

| Wrong | Right |
|---|---|
| Your net profit this month | `NET CASH` |
| You have 4 overdue invoices | `OUTSTANDING · 4 ITEMS` |
| No payments yet! | `—` |
| Click to view all | `VIEW ALL →` or footer-only chevron |
| Looking great! | (no copy — the number speaks) |

---

## 4 · The mental model — five questions

The carousel is structured around the five questions an owner asks themselves at 7am:

| # | Question | Card | Period-scoped? |
|---|----------|------|----------------|
| 1 | Am I making money this period? | **P&L** | Yes — follows selector |
| 2 | What's my cash rhythm? | **Cash flow** | Yes — follows selector |
| 3 | Who do I need to chase? | **A/R aging** | **No** — always all-open |
| 4 | What's coming if pipeline plays out? | **Forecast** | **No** — always active opportunities |
| 5 | Which jobs made me money? | **Jobs** | Yes — follows selector |

A 6th card (forward cash-flow projection) is planned but out of scope for this design. Design the carousel to gracefully accommodate a future 6th card without re-architecture.

---

## 5 · Information architecture

### Vertical structure (top to bottom)

```
┌─────────────────────────────────────────┐
│ // BOOKS                          ⌕  ⚑  │  ← AppHeader (existing component)
├─────────────────────────────────────────┤
│ P&L                       [6 MONTHS ▾]  │  ← Inline header (active card label + period pill)
├─────────────────────────────────────────┤
│                                          │
│         [ Active card content ]          │  ← Hero carousel (5 cards, paginated horizontally)
│                                          │
│              ● ○ ○ ○ ○                   │  ← Dot pagination
├─────────────────────────────────────────┤
│ INVOICES · ESTIMATES · EXPENSES         │  ← 3-segment underline control
├─────────────────────────────────────────┤
│ [Active segment list]                    │  ← Embedded list view (existing — do not redesign)
│   row · row · row · row                  │
└─────────────────────────────────────────┘

  ⊕  Floating action button (global, not Books-specific)
```

### On vertical scroll

When the list scrolls past a threshold, the hero carousel **collapses** into a single-line strip showing:
- Active card's primary metric on the left
- A/R glance ($value · red) on the right
- Dot pagination

The 3-segment control sticks to the top. Pull-to-top or pull-down re-expands the hero.

This is the existing pattern — designer should refine the collapse transition, the strip's typography rhythm, and any micro-interaction details.

### Tab placement

Books sits second from the left in the bottom tab bar:

```
[ home ]  [ BOOKS ]  [ pipeline ]  [ jobs ]  [ schedule ]  [ settings ]
```

Pipeline is its own tab and is **not in scope** for this design.

---

## 6 · The hero carousel

### Pattern

- 5 cards, horizontally paginated, one card visible per page
- Swipe to advance with a light haptic on each swap
- Dot indicator at the base (active dot is a 16pt capsule in steel-blue accent, inactive dots are 5pt circles in `cardBorder`)
- Last-viewed card persists across app launches
- Reduced-motion: numbers render at final value, no count-up; bars render fully drawn, no fill animation; card swap is instant

### Card framing — borderless, top-level data

Cards do **not** have a card panel, border, or rounded background. The data reads as first-class canvas content — flush against the dark `#000000` canvas, separated only by horizontal padding.

The reasoning: when the carousel is the primary content of the tab, framing it inside a card creates a "card inside a card" feel and demotes the data. By going borderless we make the data the surface.

**Inner sub-tiles** (drill targets within a card — Outstanding, Forecast, TopChase, Profitable, Losers, etc.) **do** keep a subtle hairline border + slightly lifted background. They're tap targets, and the user needs to see they're tappable.

### The inline card header

The top line of each card is a shared header row (rendered by the carousel container, not the card itself):

```
[ACTIVE CARD LABEL]                              [PERIOD PILL ▾]
```

- Active card label is on the left in JetBrains Mono 11px, uppercase, tracking `0.16em`.
- For cards 3 and 4 (period-independent), the label includes a colored scope hint — `A/R · ALL OPEN` (rose), `FORECAST · ACTIVE` (steel blue) — so the user understands why those cards don't respond to the period selector.
- Period pill is on the right. Single-tap opens a menu with 8 period options: `30 DAYS · 90 DAYS · 6 MONTHS · 1 YEAR · THIS MONTH · LAST MONTH · THIS QUARTER · YEAR TO DATE`.
- The pill is the **only** persistent control. There is no "edit dashboard" gear, no view-options menu, no export button anywhere in the carousel. The carousel is fixed shape.

### Card content briefs

Each card has its own purpose and visual register. The designer should treat these as anchors, not constraints — the rhythm, hierarchy, and typographic tension within each card is the design work.

#### Card 1 · P&L · *"Am I making money this period?"*

Three-line equation with a margin indicator:

```
PAYMENTS IN                                    +$118,400
EXPENSES OUT                                   −$76,220
─────────────────────────
NET CASH                                       $42,180
[margin bar — green fill on warning track]
38% MARGIN

[OUTSTANDING tile]              [FORECAST tile]
$12,640                          $38,900
4 ITEMS                          7 ITEMS
```

- Net cash uses Mohave 300, 32–40px. The rest is JetBrains Mono.
- Margin bar is a 4px horizontal bar with warning-tone background (track) and success-tone fill (margin %).
- The two tiles at the bottom are drill targets — tap Outstanding to jump into Invoices filtered to overdue, tap Forecast to jump to Estimates filtered to sent.

#### Card 2 · Cash flow · *"What's my cash rhythm?"*

Weekly paired bars over a multi-week window (count determined by period selector):

```
$42,180  (NET CASH hero, mirroring P&L)
                                             [● IN  ● OUT  legend]

[paired bar chart: green up-bars for payments-in, tan down-bars for expenses-out, weekly buckets]

SALES         AVG/WK        DAYS
$142,800      $14,800       18.2
```

- Bars use the success and warning tones, not steel blue. Steel blue stays reserved for the primary CTA + focus ring.
- The "DAYS" tile is tappable — drills to a cash-flow / days-to-pay report (currently deferred, designer can show the tile as drillable).

#### Card 3 · A/R aging · *"Who do I need to chase?"*

Always all-open invoices (ignores the period selector by design):

```
$17,800  (TOTAL OUTSTANDING hero in error/rose)
5 OPEN · 4 OVERDUE

AGING BUCKETS
0–30d    [█████░░░░░░░░] $4,800
31–60d   [████░░░░░░░░░] $3,200
61–90d   [██████░░░░░░░] $6,400
90d+     [███░░░░░░░░░░] $3,400

[TOP CHASE tile — name + amount, tappable]
```

- Hero uses error/rose color. This is the only card where the hero number reads as "bad news visible."
- Aging buckets use four tones in a deliberate ramp: 0–30 (success/olive), 31–60 (receivables/amber), 61–90 (warning/tan), 90+ (overdue/brick).
- Top chase tile shows the largest outstanding invoice. Tap → opens the A/R aging detail view (existing screen, `ARAgingDetailView`).

#### Card 4 · Forecast · *"What's coming if pipeline plays out?"*

Weighted pipeline value, broken down by deal stage:

```
$84,500  (WEIGHTED FORECAST hero in steel-blue accent)
12 ACTIVE OPPS

BY STAGE
QUALIFYING    [████████░░░░] $18,200
QUOTING       [██████░░░░░░] $12,400
QUOTED        [██████████░░] $26,800
FOLLOW-UP     [████░░░░░░░░] $9,500
NEGOTIATION   [████████░░░░] $17,600

[CLOSE RATE tile]    [STALE tile]
64%                   3
```

- Steel-blue accent is allowed here because forecast is forward-looking sales — distinct from financial reality.
- Stage breakdown bars use steel-blue accent fill. This is the **only** card where steel-blue appears as data color.
- Two drill tiles at the bottom — Close Rate (drills to Pipeline tab filtered to won, last 90 days), Stale (drills to Pipeline tab filtered to stale).

#### Card 5 · Jobs · *"Which jobs made me money?"*

Top 5 jobs by net (revenue collected minus expenses allocated), diverging bars centered on zero:

```
PERRY ST RENO       [████████░░░░]     +$19,500
OAK GROVE NEW       [██████████░░]     +$19,800
MILL POND ADDN      [████████░░░░]     +$8,200
STATE ST KITCHN     [████░░░░░░░░]     −$2,600
RIVERVIEW DECK      [██████░░░░░░]     −$4,400

[PROFITABLE tile]   [AVG MARGIN tile]   [LOSERS tile]
9                    32%                 2
```

- Positive bars in success/olive, negative bars in error/rose.
- Worst loser is always included even if it's not in the top 5 by absolute value (so the user sees their bleeders).
- Three KPI tiles at the bottom — Profitable count, Avg margin %, Losers count. Profitable and Losers are drillable to a per-job profitability report (currently deferred).

---

## 7 · The 3-segment list (below carousel)

The segmented control switches between three list surfaces:

```
INVOICES  ·  ESTIMATES  ·  EXPENSES
```

- Underline-style segments. Inactive label is secondary text, active label is primary text + a 2px steel-blue underline.
- Each segment renders an existing list view (`InvoicesListView`, `EstimatesListView`, `ExpensesListView` / `MyExpensesView` for crew-scoped). **Do not redesign the list rows themselves** — that's outside this scope. Just style the segmented control.
- Default active segment is `INVOICES` (the most-trafficked surface). The active segment persists across sessions.
- Carousel tile drill-downs (Outstanding, Forecast, TopChase, etc.) change the active segment + apply a filter — e.g. tapping Outstanding switches to Invoices with the overdue filter applied.

---

## 8 · Behavior rules

| Behavior | Rule |
|---|---|
| Period scope | The pill changes period for cards 1, 2, 5. Cards 3 and 4 ignore the pill — their data is always all-open / always-active. The pill remains visible on all cards so the user can change period without swiping back. |
| Permission gating | Each card is permission-gated. If the user lacks `finances.view`, cards 1/2/3/5 hide. If they lack `pipeline.view`, card 4 hides. If they have zero permitted cards (operator role), the entire carousel + period pill row hides — the user lands directly on the segmented control. Crew role doesn't see the tab at all; they route to a single expenses screen. |
| Drill-downs | Tile taps inside a card change the active segment + filter. They never navigate away from Books. Hero numbers do not tap (they're labels). |
| Header collapse | On vertical scroll into the list, the hero collapses to a single-line strip showing the active card's metric, an A/R glance, and the dot pagination. The 3-segment control sticks. Scroll up re-expands. |
| Last-viewed persistence | The active carousel card persists across app launches (e.g., if the user left on A/R, the next launch opens on A/R). |
| Reduced motion | Every animation must check `prefers-reduced-motion`. With it on: numbers render at final value, bars render fully filled, card swap is instant snap. |
| Offline | First paint must come from cached data (SwiftData). No spinner before content. Period changes against the cache work without network. |

---

## 9 · Design system constraints

The designer **must** design against these tokens. Pixel values that don't trace to a token will be sent back.

### Colors

| Role | Token | Hex / Value |
|---|---|---|
| Canvas | `--bg` | `#000000` — pure black |
| Primary text | `--text` | `#EDEDED` |
| Secondary text | `--text-2` | `#B5B5B5` |
| Tertiary text | `--text-3` | `#8A8A8A` |
| Decorative-only text | `--text-mute` | `#6A6A6A` (used for `//` slashes — never body text) |
| Accent (steel blue) | `--ops-accent` | `#6F94B0` — **primary CTA + focus ring ONLY**, plus card 4 forecast bars |
| Positive / profit | `--olive` | `#9DB582` |
| Attention / pending | `--tan` | `#C4A868` |
| Negative / overdue / cost | `--rose` | `#B58289` |
| Destructive / 90+ overdue | `--brick` | `#93321A` |
| Receivables ramp tone | `--fin-receivables` | `#D4A574` |

Each semantic tone has `-soft` (12% fill) and `-line` (30% border) variants for tags and badges.

**Color discipline.** Monochrome by default. Color is meaning, never decoration. Steel blue does **not** appear on toggles, links, segmented controls, sidebar active states, or chart bars (except card 4). Earth tones appear only when the color carries semantic information.

### Typography

| Role | Family | Size | Use |
|---|---|---|---|
| Hero number | Mohave 300 | 32–40px (mobile) | Net cash, total outstanding, weighted forecast |
| Screen title (`// BOOKS`) | Cake Mono 300 | 28px | AppHeader |
| Card header label | JetBrains Mono | 11px, tracking `0.16em` | `P&L`, `CASH FLOW`, `A/R · ALL OPEN`, etc. |
| Tile labels (`OUTSTANDING`, `FORECAST`) | JetBrains Mono 500 | 11px | Drill tile labels |
| Tile values | JetBrains Mono 500–600 | 13–16px | Tile numeric values |
| Body / row primary | Mohave 400 | 15px | List rows |
| Metadata / small caption | JetBrains Mono | 10–11px | Counts, week labels, axis ticks |
| Button label | Cake Mono 300 | 13–14px | Buttons |

**Rules.** Numbers are always JetBrains Mono with tabular-lining and slashed zero (`font-feature-settings: "tnum" 1, "zero" 1`). Cake Mono is always weight 300, always uppercase, never body copy. Minimum font size 11px. No exceptions.

### Surfaces & depth

Two-layer system. **No box-shadows on dark backgrounds — depth is glass + hairlines.**

| Layer | Background | Border | Use in Books |
|---|---|---|---|
| L0 canvas | `#000000` | — | The page itself, and the borderless hero carousel cards |
| L1 section card | `rgba(18,18,20,0.58)` + 28px blur + top-edge gradient | `rgba(255,255,255,0.09)`, 1px | Future enclosing surfaces if needed; not currently used in Books |
| L2 nested card | `rgba(255,255,255,0.04)` | `rgba(255,255,255,0.08)`, 1px | The drill tiles inside each carousel card |
| L3 inline | inherits parent | — | Tags, status dots, avatars |

Note: there is current drift between `DESIGN.md` and `colors_and_type.css` regarding glass values and corner radii — see § 12. The designer should design against **DESIGN.md** values until that drift is reconciled.

### Border radius

Sharp corners, not rounded pillows.

| Element | Radius |
|---|---|
| Carousel cards | n/a — borderless |
| Drill tiles (inside cards) | 4–6px |
| Period pill | 12px (slightly more rounded because it's a pill) |
| Tags / chips | 4px |
| Progress / aging bars | 2px |
| Buttons | 5px |

**No 999px pills** anywhere. Period pill is a soft rectangle, not a true pill.

### Motion

- One easing curve everywhere: `cubic-bezier(0.22, 1, 0.36, 1)`.
- **No spring physics. No bounce.** The only exception in the entire app is drag-and-drop reorder, which doesn't appear in Books.
- Durations: 150ms hover/transition, 200ms panel enter, 250ms page transition, 300ms staggered row entrance (+50ms/item), 400–600ms chart bar grow, 800ms hero count-up.
- Reduced motion is required on every animation.

### Mobile-specific deltas

These are the differences between web and iOS (per `mobile/MOBILE.md`):

| Property | Web | iOS |
|---|---|---|
| Status tag fill opacity | 0.14 | **0.32** (brighter for outdoor viewing) |
| Status tag border opacity | 0.34 | **0.88** |
| Status tag text | tone hex | tone hex shifted ~25% brighter |
| Status tag weight | 500 | 600 |
| Touch target | 36pt buttons | **44pt minimum**, 48pt preferred |
| Focus ring | 1.5px accent | 2px accent + 2px offset |
| Inactive text on busy bg | `--text-3` (5.4:1) | `--text-2` (10.3:1) |

**Touch targets.** 44×44pt minimum. Even if the visible element is smaller, the tappable area must extend. The period pill, dot pagination, drill tiles, and segmented control all need to clear this.

---

## 10 · Anti-patterns — banned

Do **not** design any of these into the Books tab:

- Drop shadows on the dark canvas
- "Most popular" ribbons or banners
- Decorative icons that don't carry information
- Hero photography or illustrations
- Mascots or characters
- Bluish-purple gradients
- Cards with rounded corners + colored left-border accent
- Emoji in any context
- Exclamation points in any copy
- "Welcome back!" / "Oops!" / coaching-tone language
- Numbers in Mohave instead of JetBrains Mono
- Steel-blue accent on toggles, links, segmented control underlines, or nav
- 999px pill-shaped buttons
- Spring physics / bounce animation
- Empty bottom-half-of-page canvas
- Default "404" illustration pages
- Raw unformatted numerical data
- Coach marks or first-run tooltips

---

## 11 · Reference artifacts

What's already in code (the designer can ignore the implementation, but the visual outcome is what we'll be comparing mockups against):

| File | What's there |
|---|---|
| `OPS/Views/Books/BooksTabView.swift` | Top-level layout — AppHeader, hero, segmented control, segment list |
| `OPS/Views/Books/HeroCarousel.swift` | The 5-card paginated carousel + inline header row + dot pagination |
| `OPS/Views/Books/Cards/PLCard.swift` | Card 1 |
| `OPS/Views/Books/Cards/CashFlowCard.swift` | Card 2 |
| `OPS/Views/Books/Cards/ARCard.swift` | Card 3 |
| `OPS/Views/Books/Cards/ForecastCard.swift` | Card 4 |
| `OPS/Views/Books/Cards/JobsCard.swift` | Card 5 |
| `OPS/Views/Books/Components/PeriodPill.swift` | Period selector pill |
| `OPS/Views/Books/CollapsedCarouselStrip.swift` | Single-line strip when hero collapses on scroll |

The designer can open Xcode → run any of these files in canvas (`⌥⌘P`) to see the current visual state with seeded data. Each card has a `#Preview` block.

### The full architecture spec

For technical detail (data model, permission gating, drill-down routing), the design intent here is a summary. The full spec lives at:

`ops-ios/docs/superpowers/specs/2026-05-11-books-ui-reconstruction-design.md`

Designer can reference but doesn't need to read.

---

## 12 · Known drift the designer should be aware of

Two known inconsistencies between the design system files. The designer should default to `DESIGN.md` values:

1. **Radii** — `DESIGN.md` says panels 10px, modals 12px, buttons 5px, chips 4px. `colors_and_type.css` says panels 5px, modals 5px, buttons 2.5px, chips 2.5px (a sharper revision in the CSS that hasn't propagated to `DESIGN.md`). Until reconciled, design against the **DESIGN.md** values.

2. **Glass surfaces** — `DESIGN.md` says glass-surface bg is `rgba(18,18,20,0.58)` with 28px blur. CSS says `rgba(10,10,10,0.70)` with 20px blur. Use **DESIGN.md** values.

Once you've returned the handoff, engineering will reconcile this drift before implementation.

---

## 13 · What we need back from you (handoff expectations)

When the design is complete, please return:

### Required

1. **Static mockups** of every state, at 390 × 844pt:
   - Each of the 5 cards (active state, with realistic seeded numbers)
   - Each card's empty state (zero data — em-dash treatment)
   - The collapsed scroll strip
   - The period pill open (menu expanded with all 8 options)
   - The 3-segment control in all three active states
   - Operator role state (no carousel, only ESTIMATES + EXPENSES segments)

2. **Token sheet** — every color, font size, spacing value, border-radius, and motion duration you used. Every value must trace to a token in the design system. If you need a new token, flag it explicitly with the proposed name and value.

3. **Spacing diagram** — for the hero carousel: padding between cards, padding inside cards, gap between sections, gap between drill tiles, dot pagination spacing.

4. **Motion notes** — for any custom transition or micro-interaction beyond the defaults (card swap, dot transition, period menu open, segment change, scroll collapse): duration, easing, properties animated.

### Optional but valuable

5. **Interaction flow video** — a screen recording of the prototype (Figma play mode or similar) showing card swipe, period change, tile drill-down, scroll collapse, segment switch.

6. **Annotated edge cases** — what does each card look like when:
   - All numbers are zero
   - One number is extremely large (overflow handling)
   - The chart has only 1 data point (cash flow, forecast, jobs)
   - The user is offline (no spinner — cached data renders)

7. **Accessibility notes** — VoiceOver labels you'd recommend for each card, any dynamic-type adjustments needed at large text sizes.

### File format

- Figma file (preferred) with frames labeled by state, or
- Sketch / Adobe XD if Figma isn't available
- PDF export of all frames + the token sheet
- Reference screenshots from any inspiration sources (with credit)

---

## 14 · Hard constraints (cannot be redesigned)

These are fixed and **not** open for redesign:

- The five cards and their questions
- The three segments and their order (Invoices · Estimates · Expenses)
- The permission gating logic
- The period selector's eight options
- The bottom-tab placement of Books
- The AppHeader component (used app-wide)
- The list views below the segmented control (existing components — out of scope)
- The brand voice, typography system, color tokens, motion system

### What IS open for redesign

- The visual rhythm and hierarchy within each card
- The card's specific element sizing, padding, and arrangement
- The chart visualization style (within token constraints — bars must use semantic tones)
- The dot pagination styling
- The period pill's specific shape and interaction
- The segmented control's underline / divider treatment
- The collapsed strip layout and information density
- The scroll-collapse transition animation
- Micro-interactions on card swap, tile tap, segment change

---

## 15 · Inspiration register

Designs in this lineage we like — the goal is NOT to copy any of these but to inhabit the same design space (tools for serious operators who need information density without visual noise):

- **xAI / Grok** — dark interfaces, monospace readouts, minimal chrome, high-contrast hierarchy
- **SpaceX mission control** — tactical UI, data density with clarity, glass-over-black surfaces
- **Apple Pro apps** (Logic, Final Cut, Xcode dark) — refined dark surfaces, subtle glass, quiet authority
- **Bloomberg Terminal** — data-forward, mono typography, every pixel earns its place
- **Military HUD / command-deck** — uppercase labels, `//` prefixes, terse status language

The trade business owner deserves the same caliber of interface that a SpaceX engineer or a Bloomberg trader gets.

---

## 16 · Project context (in case it helps)

OPS is the operating system for trades businesses. The Books tab is one of six tabs in the iOS app, and it's the second most-used tab (after Home). It replaced an earlier 4-segment hub design in May 2026 — the carousel-first shape is intentional and shipped.

We move fast. We pursue perfection. We don't ship "good enough." If something looks compromised, flag it.

Looking forward to the mockups.
