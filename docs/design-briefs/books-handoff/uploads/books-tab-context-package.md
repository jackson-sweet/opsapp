# Books Tab — Self-Contained Design Context Package

> This document is the complete context an agent or designer needs to produce mockups for the OPS iOS Books tab. **Nothing else needs to be read.** Every source file, every token, every constraint is inlined below.

---

## 0 · How to use this document

You (the agent or designer reading this) are about to design a fresh visual pass on the Books tab of the OPS iOS app. The tab already exists and ships — you are iterating on the current visual treatment, not designing from scratch.

This document gives you:

1. The project framing (who OPS is for, the design aesthetic, the brand voice).
2. The complete OPS Design System rules (colors, type, motion, anti-patterns).
3. The Books tab specification (what it is, what it answers, behavior rules).
4. The complete source code of every Books-related file as it exists today.
5. The complete data model that drives the tab.
6. The iOS design tokens you must design against.
7. Tab-bar wiring and the screen container conventions.
8. What's locked vs what's open for redesign.
9. What you should deliver back.

**Read the whole document before starting.** Then either produce mockups directly, or ask Jackson clarifying questions if anything in the constraint set is unclear. Do not invent file paths, tokens, or data fields not described here.

---

## 1 · Project framing

**Product.** OPS — operations software for trades businesses. One iOS app that handles scheduling, invoicing, projects, clients, and financials. Built for roofers, plumbers, electricians, auto detailers, window washers, landscapers, and similar trades.

**Persona.** Trade business owner, mid-30s to 60s, runs a 2–25 person crew. Spends most of their day in the truck, on rooftops, at job sites. Checks the app between calls, often one-handed, frequently in bright sunlight, sometimes with gloves on.

**Mindset.** They are checking, not browsing. They are time-pressed. They are anxious about money. The visual register should be calm, confident, and high-signal — never alarming, never marketing-cheerful, never "fun."

**Aesthetic.** Military tactical minimalist. Sharp, refined, quiet authority. Every element earns its place.

**Reference points to inhabit:** xAI · SpaceX mission control · Apple Pro apps (Logic, Final Cut, Xcode dark) · Bloomberg Terminal · military HUD design.

**Never:** playful, elastic, bubbly, 2019 SaaS template, "modern startup" tropes, cute illustrations, mascots, hero photography in product, marketing-cheerful copy.

**The test we use:** *does this make a stressed-out business owner feel like they just found the thing that gives them their life back?* If it feels like a tech demo, it's wrong. If it feels like a lifeline, it's right.

**The vibe:** *"hell. yeah."* — not *"Hell yeah!"*. Understated confidence.

---

## 2 · OPS Design System — the complete rules

The OPS Design System is canonical. Every value in your mockups must trace back to a token here. Where the iOS code drifts from the system (noted later in this document), defer to the system rules.

### 2.1 Voice & copy

OPS copy is **terse and tactical**. Every word earns its place.

| Rule | Detail |
|------|--------|
| Person | **You.** Never "we." No "I" — the app doesn't speak in first person |
| Casing | Sentence case for content. **UPPERCASE for authority** — page titles, section headers, buttons, badges |
| Prefixes | Section headers: `//`. Instructional micro-text: `[brackets]`. System state: `SYS::`. Operator identity: `// OPERATOR :: <NAME>` |
| Numbers | Always mono, tabular-lining, slashed zero. Always formatted. `$12,480` not `12480`. `87%` not `86.5671641`. `—` not `NaN` |
| Tone | Measured, declarative, never marketing-speak. Never exclamation points |
| Emoji | **Never.** Not in product UI, not in error states, not in empty states |
| Errors | `// ERROR — UPLOAD FAILED`, not "Something went wrong" |
| Empty states | `$0`, `0%`, or `—`. No "You don't have any jobs yet!" No illustrations |

#### Voice examples

| Wrong | Right |
|---|---|
| Welcome back, Jackson! | `// OPERATOR :: JACKSON` |
| You have 3 new messages | `3 UNREAD` |
| Oops! Something went wrong. | `SYS :: SYNC FAILED · 08:42` |
| Save Changes | `SAVE` or `COMMIT` |
| Are you sure? | `DESTRUCTIVE. NO UNDO.` |
| Tap here to add your first job | `NEW JOB` (button, always visible) |
| Your invoice was sent! | `SENT · INV-00284 · 08:42` |

### 2.2 Color

Monochrome by default. Color is meaning, never decoration.

**Canvas:** pure `#000000`. No mid-grey, no off-black.

**Text hierarchy (use semantic role, not raw hex):**

| Token | Hex | Contrast on #000 | Use |
|-------|-----|------------------|-----|
| `--text` | `#EDEDED` | 18.8:1 AAA | Primary body, hero numbers, active nav |
| `--text-2` | `#B5B5B5` | 10.3:1 AAA | Secondary, ghost buttons, links, sidebar icons |
| `--text-3` | `#8A8A8A` | 5.4:1 AA | Labels, metadata, subtitles, placeholders |
| `--text-mute` | `#6A6A6A` | 3.4:1 | **Decorative only** — `//` slashes, separators. Never body text |

**Accent — steel blue:**

| Token | Hex | Use |
|-------|-----|-----|
| `--ops-accent` | `#6F94B0` | **Primary CTA button fill + focus rings ONLY.** Nothing else |
| `--ops-accent-hover` | `#7FA3BD` | CTA hover state |
| `--ops-accent-muted` | `rgba(111,148,176,0.15)` | Subtle accent bg |

**Accent does NOT appear on:** ghost buttons, links, toggles, sidebar active state, tags, data bars (except Card 4 in Books), `//` slashes, input focus borders, or any decorative element.

**Earth-tone semantics:**

| Token | Hex | Meaning |
|-------|-----|---------|
| `--olive` | `#9DB582` | Positive: success, completed, +delta |
| `--tan` | `#C4A868` | Attention: warning, site visit, expiring |
| `--rose` | `#B58289` | Negative: error, overdue, cost |
| `--brick` | `#93321A` | Destructive: borders/dots only, never text on black |

Each tone has `-soft` (12% fill) and `-line` (30% border) variants for tags and badges.

**Financial-specific tones:**

| Token | Hex | Use |
|-------|-----|-----|
| `--fin-revenue` | `#C4A868` | Revenue bars, income |
| `--fin-profit` | `#9DB582` | Profit indicators |
| `--fin-cost` | `#B58289` | Expense/cost |
| `--fin-receivables` | `#D4A574` | Outstanding receivables (A/R aging 31-60d bucket) |
| `--fin-overdue` | `#93321A` | Past-due amounts (A/R aging 90+d bucket) |

**Agent / AI provenance tone (new):**

| Token | Hex | Use |
|-------|-----|-----|
| `--ops-agent` | `#8A7FB8` | AI-authored content badges, agent rail bars |
| `--ops-agent-soft` | `rgba(138,127,184,0.10)` | Agent content subtle bg |
| `--ops-agent-line` | `rgba(138,127,184,0.35)` | Agent content border |

Never on body text. Never as button bg. Never on semantic state. **Not used in Books today**, but reserved.

### 2.3 Typography

Three families, each with one job.

| Family | Role | Weights |
|--------|------|---------|
| **Mohave** | Body copy, names, hero numbers | 300 (hero), 400–500 (body) |
| **JetBrains Mono** | All numbers, timestamps, micro labels, `//` prefixes, `[brackets]` | 400, 500 tabular |
| **Cake Mono** | Uppercase display voice — page titles, buttons, badges, section headers | **300 Light only** in product UI |

**Critical rules:**

- Numbers are **always** mono. `font-feature-settings: "tnum" 1, "zero" 1`. Non-negotiable.
- **11px minimum. No exceptions.**
- Cake Mono is always `font-weight: 300`. Never 400/700 in product. If it needs to read heavier, increase size, not weight.
- Cake Mono is always UPPERCASE.
- Mohave carries sentence-case body text and hero numbers.
- JetBrains Mono carries the small tactical labels (11px uppercase, `letter-spacing: 0.16em`).

**Type scale (web defaults — mobile sizes in § 2.10):**

| Role | Family | Size | Use |
|------|--------|------|-----|
| Hero number | Mohave 300 | 76–84px | Dashboard hero, revenue total |
| Page title (TopBar H1) | Cake Mono 300 | 22px | Root-route page heading |
| Display heading | Cake Mono 300 | 28–32px | Auth h1s, wizard titles |
| Section heading | Cake Mono 300 | 15–20px | Admin sections, settings subheads |
| Button label | Cake Mono 300 | 14px | Primary/secondary buttons |
| Badge (Cake) | Cake Mono 300 | 11px | Status badges, role tags |
| Panel title | JetBrains Mono | 11px | Widget/section titles (`// TITLE`) |
| Body / name | Mohave 400 | 14px | Entity names, row primary text |
| Data value (lg) | JetBrains Mono 600 | 20px | Hero metrics in widgets |
| Data value | JetBrains Mono | 13px | Standard data values |
| Category label | JetBrains Mono | 11px | BOOKED, INVOICED, etc. |
| Metadata | JetBrains Mono | 11px | Timestamps, IDs, subtotals |

**Deprecated fonts (do not use):** Bebas Neue, Kosugi. Both removed 2026-04-17.

### 2.4 Surfaces & depth

Glass + hairlines carry all depth. **Zero box-shadows on dark backgrounds.**

Two tiers:

| Surface | Background | Blur | Border | Radius | Use |
|---------|-----------|------|--------|--------|-----|
| `.glass-surface` | `rgba(18,18,20,0.58)` | `blur(28px) saturate(1.3)` | `rgba(255,255,255,0.09)` | 10px | Cards, panels, widgets, sidebar |
| `.glass-dense` | `rgba(18,18,20,0.78)` | `blur(28px) saturate(1.3)` | `rgba(255,255,255,0.09)` | 12px | Modals, popovers, dropdowns, toasts |

Both have a `::before` pseudo-element with a top-edge gradient (the only "lit-from-above" cue):
- glass-surface: `linear-gradient(180deg, rgba(255,255,255,0.04), transparent 40%)`
- glass-dense: `linear-gradient(180deg, rgba(255,255,255,0.03), transparent 35%)`

**Depth rules:**

- No `box-shadow` anywhere on dark backgrounds.
- Never stack three deep. Glass over glass is OK (use `.glass-dense`); glass-on-glass-on-glass is not.
- No accent borders, no accent glows, no "most popular" ribbons.

**Interactive surfaces:**

| State | Background |
|-------|-----------|
| Input | `rgba(255,255,255,0.04)` |
| Hover | `rgba(255,255,255,0.05)` |
| Active / pressed | `rgba(255,255,255,0.08)` |

**Borders:**

| Token | Value | Use |
|-------|-------|-----|
| `--line` | `rgba(255,255,255,0.10)` | Standard hairline — panels, topbar, inputs |
| `--glass-border` | `rgba(255,255,255,0.09)` | Glass panel edge |

**Neutral fills (non-interactive data):**

| Token | Value | Use |
|-------|-------|-----|
| `--fill-neutral` | `rgba(255,255,255,0.14)` | Bar fills, progress tracks |
| `--fill-neutral-dim` | `rgba(255,255,255,0.06)` | Track backgrounds, skeletons |

### 2.5 Border radius

Sharp corners, not rounded pillows.

| Element | Radius |
|---------|--------|
| Panels / cards / widgets | 10px |
| Modals / dialogs / popovers | 12px |
| Buttons / inputs | 5px |
| Tags / chips | 4px |
| Progress bars | 2px |
| Sidebar item hover | 6px |
| Avatars | `50%` (full) |

**No 999px pills** anywhere except avatars.

### 2.6 Spacing & layout

**Base unit: 8px.** All spacing is multiples of 4px or 8px.

| Property | Value |
|----------|-------|
| Canvas padding (web) | `36px 44px` |
| Max content width | `1320px` |
| Panel gap | `24px` |
| Mobile canvas padding | `20px` horizontal, `8px` below nav |
| Mobile section gap | `24px` |
| Mobile card gap | `8px` |
| Mobile card inset | `16px` standard, `12px` compact |

### 2.7 Motion

Strong, confident, purposeful. Things move with conviction and stop with conviction.

**One easing curve everywhere:** `cubic-bezier(0.22, 1, 0.36, 1)`

**No spring physics. No bounce.** Exception: drag-and-drop reorder only.

| Animation | Duration |
|-----------|----------|
| Hover transitions | 150ms |
| Panel enter | 200ms |
| Page transitions | 250ms |
| Row stagger entrance | 300ms + 50ms/item |
| Card flip | 350ms |
| Chart bar grow | 400–600ms + index delay |
| Hero count-up | 800ms |

**Reduced motion is required.** Every animation checks `prefers-reduced-motion` and falls back to a 150ms opacity transition.

### 2.8 Components — quick reference

**Buttons:**

| Variant | Fill | Text | Border |
|---------|------|------|--------|
| Primary | Outlined `--ops-accent` → fills on hover | `--ops-accent` → black on hover | `--ops-accent` |
| Default | `rgba(255,255,255,0.07)` | `--text-2` | `--line` |
| Secondary | transparent | `--text-2` | `--line` |
| Ghost | transparent | `--text-2` | none |
| Destructive | `--rose-soft` | `--rose` | `--rose-line` |

- Cake Mono 300, 14px, uppercase
- `border-radius: 5px`, `min-height: 36px` (web) / 44pt (mobile), `padding: 9px 16px`
- Focus: `1.5px solid --ops-accent, offset 2px`

**Tags / badges:**

| Variant | Text | Background | Border |
|---------|------|-----------|--------|
| Neutral | `--text-2` | `rgba(255,255,255,0.05)` | `--line` |
| Olive | `--olive` | `--olive-soft` | `--olive-line` |
| Tan | `--tan` | `--tan-soft` | `--tan-line` |
| Rose | `--rose` | `--rose-soft` | `--rose-line` |

- JetBrains Mono 500, 11px, `letter-spacing: 0.12em`, uppercase
- `border-radius: 4px`, `padding: 2px 6px`
- Earth tones ONLY when color carries semantic meaning

**Inputs:**

- Background: `rgba(255,255,255,0.04)`
- Border: `1px solid rgba(255,255,255,0.10)`
- Focus: border brightens to `rgba(255,255,255,0.20)` — **no accent**
- Error: border `--rose`
- Radius: 5px, min-height: 36pt (mobile: 44pt)

**Sidebar / nav:**

- Inactive: `--text-3` icon, no bg
- Active: `--text` icon, 2px vertical indicator bar in `--text-2`
- **No accent on navigation** (iOS today violates this — see § 8)

**Toggles / segments:**

- Inactive: `--text-3`, transparent, `--line` border
- Active: `--text`, `rgba(255,255,255,0.08)` bg, `rgba(255,255,255,0.18)` border
- **No accent on toggles**

**Links:**

- Default: `--text-2`
- Hover: `--text` + subtle `--text-3` underline
- **No accent on links**

### 2.9 Iconography

**Web:** Lucide — stroke-based, 1.5px line, square-cap.
**iOS:** SF Symbols (Apple's system set). No migration to Lucide planned.

| Context | Size |
|---------|------|
| Inline in text | 14px |
| Buttons / sidebar | 16px |
| Empty-state hero | 20px |
| Tab bar (mobile) | 28pt |

- Color: inherit `currentColor`. `--text-3` at rest, `--text-2` on hover, `--text` when active.
- Stroke: 1.5px. Never fill.
- No accent on icons. Icons are metadata, not actions.
- Every icon carries meaning. If you can delete it without losing information, delete it.
- **No emoji. Ever.**

### 2.10 Mobile-specific overrides

OPS users review jobs outdoors, in bright sun. Every mobile token clears a higher contrast bar than its web equivalent.

| Property | Web | Mobile |
|----------|-----|--------|
| Status tag bg fill | 0.14 alpha | **0.32 alpha** |
| Status tag border | 0.34 alpha | **0.88 alpha** |
| Status tag text | tone hex | tone hex **shifted ~25% brighter** |
| Status tag weight | 500 | **600** |
| Hairline divider | `rgba(255,255,255,0.06)` | `rgba(255,255,255,0.10)` |
| Inactive text on busy bg | `--text-3` (5.4:1) | `--text-2` (10.3:1) |
| Focus ring | 1.5px accent | 2px accent + 2px offset |
| Touch target | 36pt buttons | **44pt minimum, 48pt preferred** |

**Viewport:**

- Design frame: **390 × 844pt** (iPhone 14/15 Pro)
- Safe areas: top 59pt (status bar + dynamic island), bottom 34pt (home indicator)
- **Portrait only.** No landscape support in v1.

**Mobile surface hierarchy (L0–L3):**

| Level | Background | Border | Use |
|---|---|---|---|
| L0 — Canvas | `#000000` | — | The page itself; borderless content |
| L1 — Section card | `rgba(18,18,20,0.58)` + 28px blur + top-edge gradient | `rgba(255,255,255,0.09)`, 1px | Primary content container |
| L2 — Nested card | `rgba(255,255,255,0.04)` | `rgba(255,255,255,0.08)`, 1px | KPI tiles, sub-cards, drill targets |
| L3 — Inline | inherits parent | — | Tags, badges, dots |

**Rule:** L2 cards can sit on L0 OR inside L1. But **L2 inside L2 is forbidden**. Never nest deeper than L1 → L2.

**Mobile type scale:**

| Role | Family | Size | Delta from web |
|------|--------|------|----------------|
| Screen title | Cake Mono 300 | 28–32px | ↑ from 22px (bigger for thumb-scroll readability) |
| Section header | JetBrains Mono | 10–11px | Same |
| Body / entity name | Mohave 400–500 | 15px | ↑ from 14px |
| Data value (hero) | Mohave 300 | 32–40px | ↓ from 76–84px |
| Data value (card) | JetBrains Mono 500 | 16–20px | Same |
| Metadata / label | JetBrains Mono | 10–11px | Same |
| Tag / badge | JetBrains Mono 500 | 9.5–10px | Slightly smaller for density |
| Button label | Cake Mono 300 | 13–14px | Same |
| Tab bar label | JetBrains Mono | 9px | Compact for 5-tab layout |

### 2.11 Anti-patterns — BANNED

These are explicitly forbidden from OPS interfaces:

- Decorative icons as ornament
- Drop shadows on dark backgrounds
- "Most popular" ribbons
- Checkmark bullet lists
- Numbers in Mohave instead of mono
- Accent on toggles / links / nav active state (iOS today violates this)
- Empty bottom-half-of-page canvas
- Default "404" illustration pages
- Raw unformatted numerical data
- Spring physics / bounce animations
- Bluish-purple gradients
- Cards with rounded corners + colored left-border accent
- Emoji in any context
- Exclamation points in UI copy
- "Welcome back!" / "Oops!" / coaching language
- Illustrations, mascots, scene drawings
- Hero photography in the product
- 999px pill-shaped buttons (avatars excepted)
- Coach marks or first-run tooltips

### 2.12 Accessibility

| Requirement | Standard |
|-------------|----------|
| Text contrast | ≥ 4.5:1 (AA). `--text-mute` (3.4:1) is decorative only |
| Font size floor | 11px minimum |
| Touch targets | 44×44pt minimum |
| Focus ring | `1.5px solid --ops-accent`, 2px offset from `#000` |
| Reduced motion | Every animation checks `prefers-reduced-motion` |
| Color independence | Never convey info by color alone. Tags always include text labels |

---

## 3 · Books tab — what it is

### 3.1 Purpose

Books is OPS's **money command center**. It exists so a trades business owner can answer five questions about their money in less than ten seconds, between job sites, on a phone, often one-handed.

It is **not** a finance app, **not** a reporting suite, **not** a place to do bookkeeping. It is a glance-and-go dashboard backed by drill-throughs into the underlying invoices, estimates, and expenses.

### 3.2 The five questions

The tab's hero carousel is structured around the five questions an owner asks themselves at 7am:

| # | Question | Card | Period-scoped? |
|---|----------|------|----------------|
| 1 | Am I making money this period? | **P&L** | Yes — follows selector |
| 2 | What's my cash rhythm? | **Cash flow** | Yes — follows selector |
| 3 | Who do I need to chase? | **A/R aging** | **No** — always all-open |
| 4 | What's coming if pipeline plays out? | **Forecast** | **No** — always active opportunities |
| 5 | Which jobs made me money? | **Jobs** | Yes — follows selector |

A 6th card (forward cash-flow projection) is planned but out of scope today. Design the carousel to gracefully accommodate a future 6th card without re-architecture.

### 3.3 Information architecture

```
┌─────────────────────────────────────────┐
│ // BOOKS                          ⌕  ⚑  │  ← AppHeader (shared component, not in scope)
├─────────────────────────────────────────┤
│ P&L                       [6 MONTHS ▾]  │  ← Inline header: active card label + period pill
├─────────────────────────────────────────┤
│                                          │
│         [ Active card content ]          │  ← Hero carousel — 5 borderless cards, paginated horizontally
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

**Tab placement:** Books sits second from the left in the bottom tab bar.

```
[ home ]  [ leads ]?  [ BOOKS ]  [ job board ]  [ catalog ]?  [ schedule ]  [ settings ]
```

(Tabs marked `?` are permission-gated and hide for some roles.)

### 3.4 Scroll behavior

When the list scrolls past a threshold, the hero carousel **collapses** into a single-line strip showing:
- Active card's primary metric on the left
- A/R glance (`$value` in rose) on the right
- Dot pagination

The 3-segment control sticks to the top. Pull-to-top or pull-down re-expands the hero.

### 3.5 Card content briefs

#### Card 1 · P&L · *"Am I making money this period?"*

Three-line equation with a margin indicator:

```
PAYMENTS IN                                    +$118,400   ← olive
EXPENSES OUT                                   −$76,220    ← tan
─────────────────────────
NET CASH                                       $42,180     ← Mohave 300, 32–40px, primary text (rose if negative)
[margin bar — green fill on tan track]
38% MARGIN

[OUTSTANDING tile]              [FORECAST tile]
$12,640                          $38,900
4 ITEMS                          7 ITEMS
```

Drill tiles:
- OUTSTANDING → jumps to Invoices segment with `overdue` filter
- FORECAST → jumps to Estimates segment with `sent` filter

#### Card 2 · Cash flow · *"What's my cash rhythm?"*

Weekly paired bars (uses Apple's SwiftUI Charts framework):

```
$42,180  (NET CASH hero, mirrors Card 1)
                                             [● IN  ● OUT  legend]

[paired bar chart: olive up-bars for payments-in, tan down-bars for expenses-out, 8 weekly buckets]

SALES         AVG/WK        DAYS
$142,800      $14,800       18.2
```

DAYS tile is drillable to a cash-flow / days-to-pay report (currently deferred — drill is a no-op but should look tappable).

#### Card 3 · A/R aging · *"Who do I need to chase?"*

Always all-open invoices (ignores the period selector):

```
$17,800  (TOTAL OUTSTANDING hero in rose/error)
5 OPEN · 4 OVERDUE

AGING BUCKETS
0–30d    [█████░░░░░░░░] $4,800     ← olive
31–60d   [████░░░░░░░░░] $3,200     ← receivables amber #D4A574
61–90d   [██████░░░░░░░] $6,400     ← tan/warning
90d+     [███░░░░░░░░░░] $3,400     ← overdue brick #93321A

[TOP CHASE tile — client name + amount, tappable → opens ARAgingDetailView sheet]
```

#### Card 4 · Forecast · *"What's coming if pipeline plays out?"*

Weighted pipeline value, broken down by deal stage. Steel-blue accent allowed here (only card where data uses accent).

```
$84,500  (WEIGHTED FORECAST hero in steel-blue accent)
12 ACTIVE OPPS

BY STAGE
QUALIFYING    [████████░░░░] $18,200   ← all bars in steel-blue accent
QUOTING       [██████░░░░░░] $12,400
QUOTED        [██████████░░] $26,800
FOLLOW-UP     [████░░░░░░░░] $9,500
NEGOTIATION   [████████░░░░] $17,600

[CLOSE RATE tile — olive]    [STALE tile — tan]
64%                           3
```

CLOSE RATE drills to the Pipeline tab (separate top-level tab, not Books) filtered to won/last-90-days. STALE drills to Pipeline filtered to stale.

#### Card 5 · Jobs · *"Which jobs made me money?"*

Top 5 jobs by net (revenue collected minus expenses allocated):

```
PERRY ST RENO       [████████░░░░]     +$19,500   ← olive
OAK GROVE NEW       [██████████░░]     +$19,800
MILL POND ADDN      [████████░░░░]     +$8,200
STATE ST KITCHN     [████░░░░░░░░]     −$2,600    ← rose
RIVERVIEW DECK      [██████░░░░░░]     −$4,400

[PROFITABLE tile]   [AVG MARGIN tile]   [LOSERS tile]
9 (olive)           32% (primary)       2 (rose)
```

Note: current implementation renders absolute-value bars with green/red color. A true diverging chart (positive bars right, negative bars left from a center axis) is an open option.

PROFITABLE and LOSERS tiles drill to a per-job profitability report (currently deferred).

### 3.6 Behavior rules

| Behavior | Rule |
|---|---|
| Period scope | The pill changes period for cards 1, 2, 5. Cards 3 and 4 ignore the pill. Pill stays visible on all cards |
| Permission gating | Cards 1/2/3/5 require `finances.view`. Card 4 requires `pipeline.view`. Zero permitted cards (operator role) → entire hero hides, user lands on segmented control directly. Crew role bypasses Books entirely, routes to single expenses screen |
| Drill-downs | Tile taps inside a card change the active segment + filter. Never navigate away from Books. Hero numbers do not tap |
| Header collapse | On vertical scroll, hero collapses to a single-line strip. The 3-segment control sticks. Scroll up re-expands |
| Last-viewed persistence | The active carousel card persists across app launches via `@AppStorage("books.lastViewedCard")` |
| Default segment | INVOICES on first launch. Persists across sessions via `@AppStorage("books.selectedSegment")` |
| Reduced motion | Every animation must check `prefers-reduced-motion`. Numbers render at final value, bars render fully filled, card swap is instant |
| Offline | First paint comes from cached SwiftData. No spinner before content. Period changes against cache work without network |

### 3.7 Period selector

8 options accessible via single-tap menu:

| Token | Label | Range |
|---|---|---|
| `month` | `30 DAYS` | Trailing 30 days |
| `quarter` | `90 DAYS` | Trailing 90 days |
| `sixMonths` | `6 MONTHS` | Trailing 180 days |
| `year` | `1 YEAR` | Trailing 365 days |
| `thisMonth` | `THIS MONTH` | Calendar MTD |
| `lastMonth` | `LAST MONTH` | Previous calendar month |
| `thisQuarter` | `THIS QUARTER` | Calendar QTD |
| `ytd` | `YEAR TO DATE` | Calendar YTD |

### 3.8 Permission matrix

| Permission | Owner | Admin | Office | Operator | Crew |
|---|---|---|---|---|---|
| `pipeline.view` | ✓ | ✓ | ✓ | — | — |
| `finances.view` | ✓ | ✓ | ✓ | — | — |
| `estimates.view` | ✓ | ✓ | ✓ | ✓ | — |
| `expenses.view` | all | all | all | own | own |
| `expenses.create` | ✓ | ✓ | ✓ | ✓ | ✓ |
| `expenses.approve` | ✓ | ✓ | ✓ | — | — |

What each role sees:

| Role | Hero | Segments visible |
|---|---|---|
| Owner | All 5 cards | INVOICES · ESTIMATES · EXPENSES |
| Admin | All 5 cards | INVOICES · ESTIMATES · EXPENSES |
| Office | All 5 cards | INVOICES · ESTIMATES · EXPENSES |
| Operator | Hidden (no `finances.view`/`pipeline.view`) | ESTIMATES · EXPENSES |
| Crew | n/a — auto-routes to MyExpensesView | n/a |

---

## 4 · Current Books source code (complete)

Every Books-related Swift file as it exists today. The code IS the current visual treatment — your mockup will be evaluated against this output rendered to screen.

### 4.1 `OPS/Views/Books/BooksTabView.swift`

```swift
//
//  BooksTabView.swift
//  OPS
//
//  Books Phase 2 (2026-05-11) — money command center.
//  Top: AppHeader + PeriodPill + swipeable 5-card HeroCarousel.
//  Below: 3-segment underline control (Invoices · Estimates · Expenses).
//  Pipeline has moved to its own top-level tab (see `PIPELINE TAB - P1-1`).
//

import SwiftUI

private struct HeaderBottomKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

struct BooksTabView: View {
    @StateObject private var dashboardVM: MoneyDashboardViewModel
    @StateObject private var estimateVM = EstimateViewModel()
    @StateObject private var invoiceVM = InvoiceViewModel()
    @StateObject private var expenseVM = ExpenseViewModel()
    @StateObject private var cashflowVM = CashflowForecastViewModel()

    init() {
        _dashboardVM = StateObject(wrappedValue: MoneyDashboardViewModel())
    }

    #if DEBUG
    /// Preview-only — injects a pre-seeded dashboard VM so the carousel
    /// renders with realistic data on Xcode's preview canvas. Bypasses the
    /// usual setup() / loadData() chain (which is guarded by `currentUser`).
    init(previewDashboardVM: MoneyDashboardViewModel) {
        _dashboardVM = StateObject(wrappedValue: previewDashboardVM)
    }
    #endif

    @EnvironmentObject private var dataController: DataController
    @EnvironmentObject private var permissionStore: PermissionStore
    @EnvironmentObject var appState: AppState
    @Environment(\.modelContext) private var modelContext

    // Active segment persisted across sessions and visible to FloatingActionMenu.
    @AppStorage("books.selectedSegment") private var selectedSegmentRaw: String = BooksSection.invoices.rawValue
    @AppStorage("books.lastViewedCard") private var lastViewedCardRaw: String = HeroCarousel.CardID.pl.rawValue

    @State private var headerCollapsed = false
    @State private var showARDetail = false
    @State private var showCashflowForecast = false

    private var selectedSegment: BooksSection {
        BooksSection(rawValue: selectedSegmentRaw) ?? .invoices
    }

    private var visibleSegments: [BooksSection] {
        BooksSection.allCases.filter { permissionStore.can($0.requiredPermission) }
    }

    private var hasFinances: Bool { permissionStore.can("finances.view") }

    private var carouselVisible: Bool {
        permissionStore.can("finances.view") || permissionStore.can("pipeline.view")
    }

    private var visibleCarouselCards: [HeroCarousel.CardID] {
        HeroCarousel.CardID.allCases.filter { permissionStore.can($0.permission) }
    }

    private var activeCarouselCard: HeroCarousel.CardID {
        let restored = HeroCarousel.CardID(rawValue: lastViewedCardRaw) ?? .pl
        return visibleCarouselCards.contains(restored) ? restored : (visibleCarouselCards.first ?? .pl)
    }

    private var expensesScopeIsOwn: Bool {
        permissionStore.can("expenses.view") && !permissionStore.hasFullAccess("expenses.view")
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                AppHeader(headerType: .books)
                    .padding(.bottom, 8)

                if headerCollapsed && carouselVisible {
                    CollapsedCarouselStrip(
                        viewModel: dashboardVM,
                        activeCard: activeCarouselCard,
                        visibleCards: visibleCarouselCards
                    )
                    .transition(.opacity)
                }

                if headerCollapsed {
                    underlineSegmentedControl
                        .background(OPSStyle.Colors.background)
                        .transition(.opacity)
                }

                ScrollView {
                    VStack(spacing: 0) {
                        if carouselVisible {
                            HeroCarousel(
                                viewModel: dashboardVM,
                                onDrillOutstanding: {
                                    selectedSegmentRaw = BooksSection.invoices.rawValue
                                    invoiceVM.selectedFilter = .overdue
                                },
                                onDrillForecast: {
                                    selectedSegmentRaw = BooksSection.estimates.rawValue
                                    estimateVM.selectedFilter = .sent
                                },
                                onDrillCashFlowDays: { /* Cash-flow report — deferred per spec §10 */ },
                                onDrillTopChase: { showARDetail = true },
                                onDrillCloseRate: { /* Pipeline tab drill — see PIPELINE TAB - P1-1 */ },
                                onDrillStale: { /* Pipeline tab drill — see PIPELINE TAB - P1-1 */ },
                                onDrillProfitable: { /* Jobs report — deferred per spec §10 */ },
                                onDrillLosers: { /* Jobs report — deferred per spec §10 */ }
                            )
                            .environmentObject(permissionStore)
                            .padding(.bottom, OPSStyle.Layout.spacing2)
                            .background(
                                GeometryReader { geo in
                                    Color.clear.preference(
                                        key: HeaderBottomKey.self,
                                        value: geo.frame(in: .named("scroll")).maxY
                                    )
                                }
                            )
                        }

                        if hasFinances {
                            CashflowForecastCard(viewModel: cashflowVM)
                                .padding(.horizontal, OPSStyle.Layout.spacing3)
                                .padding(.top, OPSStyle.Layout.spacing2)
                        }

                        if !headerCollapsed {
                            underlineSegmentedControl
                        }

                        contentForSegment
                    }
                }
                .coordinateSpace(name: "scroll")
                .onPreferenceChange(HeaderBottomKey.self) { bottomY in
                    let shouldCollapse = bottomY < 0
                    if shouldCollapse != headerCollapsed {
                        withAnimation(OPSStyle.Animation.fast) {
                            headerCollapsed = shouldCollapse
                        }
                    }
                }
            }
            .background(OPSStyle.Colors.background.ignoresSafeArea())
            .sheet(isPresented: $showARDetail) {
                ARAgingDetailView()
                    .environmentObject(dataController)
            }
            .fullScreenCover(isPresented: $showCashflowForecast) {
                CashflowForecastScreen(viewModel: cashflowVM)
            }
        }
        .trackScreen("Books")
        .task {
            setupViewModels()
            await dashboardVM.loadData()
            if !visibleSegments.contains(selectedSegment), let first = visibleSegments.first {
                selectedSegmentRaw = first.rawValue
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("BooksSelectSegment"))) { notification in
            guard let raw = notification.userInfo?["segment"] as? String,
                  let segment = BooksSection(rawValue: raw),
                  visibleSegments.contains(segment) else { return }
            withAnimation(OPSStyle.Animation.fast) {
                selectedSegmentRaw = segment.rawValue
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("OpenCashflowForecast"))) { _ in
            guard hasFinances else { return }
            showCashflowForecast = true
        }
    }

    private var underlineSegmentedControl: some View {
        HStack(spacing: 0) {
            ForEach(visibleSegments) { segment in
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    withAnimation(OPSStyle.Animation.fast) {
                        selectedSegmentRaw = segment.rawValue
                    }
                } label: {
                    VStack(spacing: OPSStyle.Layout.spacing2) {
                        Text(segment.rawValue)
                            .font(OPSStyle.Typography.sectionLabel)
                            .foregroundColor(
                                selectedSegment == segment
                                    ? OPSStyle.Colors.primaryText
                                    : OPSStyle.Colors.secondaryText
                            )
                            .frame(maxWidth: .infinity)
                            .padding(.top, OPSStyle.Layout.spacing2_5)

                        Rectangle()
                            .frame(height: OPSStyle.Layout.Border.thick)
                            .foregroundColor(
                                selectedSegment == segment
                                    ? OPSStyle.Colors.primaryAccent
                                    : Color.clear
                            )
                    }
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
        .padding(.horizontal, OPSStyle.Layout.spacing3)
    }

    @ViewBuilder
    private var contentForSegment: some View {
        Group {
            switch selectedSegment {
            case .invoices:
                InvoicesListView(embedded: true)
            case .estimates:
                EstimatesListView(embedded: true)
            case .expenses:
                if expensesScopeIsOwn {
                    MyExpensesView()
                } else {
                    ExpensesListView(embedded: true)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(OPSStyle.Animation.fast, value: selectedSegment)
    }

    private func setupViewModels() {
        guard let companyId = dataController.currentUser?.companyId, !companyId.isEmpty else { return }
        dashboardVM.setup(companyId: companyId, modelContext: modelContext)
        estimateVM.setup(companyId: companyId, modelContext: modelContext)
        invoiceVM.setup(companyId: companyId, modelContext: modelContext)
        expenseVM.setup(companyId: companyId)
        cashflowVM.setup(companyId: companyId, dashboardVM: dashboardVM)
    }
}
```

### 4.2 `OPS/Views/Books/BooksSection.swift`

```swift
enum BooksSection: String, CaseIterable, Identifiable, Codable {
    case invoices  = "INVOICES"
    case estimates = "ESTIMATES"
    case expenses  = "EXPENSES"

    var id: String { rawValue }

    /// Permission required for this segment to be visible.
    var requiredPermission: String {
        switch self {
        case .invoices:  return "finances.view"
        case .estimates: return "estimates.view"
        case .expenses:  return "expenses.view"
        }
    }

    /// FAB primary action label for this segment.
    var fabActionLabel: String {
        switch self {
        case .invoices:  return "New Invoice"
        case .estimates: return "New Estimate"
        case .expenses:  return "New Expense"
        }
    }
}
```

### 4.3 `OPS/Views/Books/HeroCarousel.swift`

```swift
import SwiftUI

struct HeroCarousel: View {
    @ObservedObject var viewModel: MoneyDashboardViewModel
    @EnvironmentObject private var permissionStore: PermissionStore

    @AppStorage("books.lastViewedCard") private var lastViewedRaw: String = CardID.pl.rawValue
    @State private var scrollPosition: CardID?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var onDrillOutstanding: () -> Void
    var onDrillForecast: () -> Void
    var onDrillCashFlowDays: () -> Void
    var onDrillTopChase: () -> Void
    var onDrillCloseRate: () -> Void
    var onDrillStale: () -> Void
    var onDrillProfitable: () -> Void
    var onDrillLosers: () -> Void

    enum CardID: String, CaseIterable, Identifiable {
        case pl, cashFlow, ar, forecast, jobs
        var id: String { rawValue }

        var permission: String {
            switch self {
            case .pl, .cashFlow, .ar, .jobs: return "finances.view"
            case .forecast:                  return "pipeline.view"
            }
        }
    }

    private var visibleCards: [CardID] {
        CardID.allCases.filter { permissionStore.can($0.permission) }
    }

    var body: some View {
        if visibleCards.isEmpty {
            EmptyView()
        } else {
            VStack(spacing: OPSStyle.Layout.spacing2) {
                inlineHeader

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: OPSStyle.Layout.spacing3) {
                        ForEach(visibleCards) { card in
                            cardView(for: card)
                                .containerRelativeFrame(.horizontal)
                                .id(card)
                        }
                    }
                    .scrollTargetLayout()
                }
                .scrollTargetBehavior(.paging)
                .scrollPosition(id: $scrollPosition)
                .onChange(of: scrollPosition) { _, new in
                    if let new {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        lastViewedRaw = new.rawValue
                    }
                }

                if visibleCards.count > 1 {
                    dots
                }
            }
            .onAppear {
                let restored = CardID(rawValue: lastViewedRaw) ?? .pl
                scrollPosition = visibleCards.contains(restored) ? restored : visibleCards.first
            }
        }
    }

    /// Top line of the hero: active card's label on the left, period pill on the right.
    /// Cards 3 (A/R) and 4 (Forecast) include a colored scope hint (ALL OPEN / ACTIVE)
    /// so the user understands why those cards don't respond to the pill.
    private var inlineHeader: some View {
        let active = scrollPosition ?? visibleCards.first ?? .pl
        let header = headerLabel(for: active)
        return HStack(alignment: .firstTextBaseline, spacing: OPSStyle.Layout.spacing2) {
            Text(header.text)
                .font(OPSStyle.Typography.smallCaption)
                .foregroundColor(header.color)
                .contentTransition(.opacity)
            Spacer()
            PeriodPill(selected: $viewModel.selectedPeriod)
        }
        .padding(.horizontal, OPSStyle.Layout.spacing3)
    }

    private func headerLabel(for card: CardID) -> (text: String, color: Color) {
        switch card {
        case .pl:       return ("P&L",                  OPSStyle.Colors.secondaryText)
        case .cashFlow: return ("CASH FLOW",            OPSStyle.Colors.secondaryText)
        case .ar:       return ("A/R · ALL OPEN",       OPSStyle.Colors.errorStatus)
        case .forecast: return ("FORECAST · ACTIVE",    OPSStyle.Colors.primaryAccent)
        case .jobs:     return ("JOBS · NET BY PROJECT", OPSStyle.Colors.secondaryText)
        }
    }

    @ViewBuilder
    private func cardView(for card: CardID) -> some View {
        switch card {
        case .pl:       PLCard(viewModel: viewModel, onTapOutstanding: onDrillOutstanding, onTapForecast: onDrillForecast)
        case .cashFlow: CashFlowCard(viewModel: viewModel, onTapDays: onDrillCashFlowDays)
        case .ar:       ARCard(viewModel: viewModel, onTapTopChase: onDrillTopChase)
        case .forecast: ForecastCard(viewModel: viewModel, onTapCloseRate: onDrillCloseRate, onTapStale: onDrillStale)
        case .jobs:     JobsCard(viewModel: viewModel, onTapProfitable: onDrillProfitable, onTapLosers: onDrillLosers)
        }
    }

    private var dots: some View {
        HStack(spacing: 5) {
            ForEach(visibleCards) { card in
                let isActive = scrollPosition == card
                Capsule()
                    .fill(isActive ? OPSStyle.Colors.primaryAccent : OPSStyle.Colors.cardBorder)
                    .frame(width: isActive ? 16 : 5, height: 5)
                    .animation(reduceMotion ? .none : OPSStyle.Animation.standard, value: scrollPosition)
                    .onTapGesture {
                        withAnimation(reduceMotion ? .none : OPSStyle.Animation.standard) {
                            scrollPosition = card
                        }
                    }
            }
        }
        .padding(.top, OPSStyle.Layout.spacing1)
    }
}
```

### 4.4 `OPS/Views/Books/Components/PeriodPill.swift`

```swift
import SwiftUI

struct PeriodPill: View {
    @Binding var selected: MoneyDashboardViewModel.Period

    var body: some View {
        Menu {
            ForEach(MoneyDashboardViewModel.Period.allCases, id: \.self) { period in
                Button {
                    UISelectionFeedbackGenerator().selectionChanged()
                    selected = period
                } label: {
                    HStack {
                        Text(period.pillLabel)
                        if selected == period {
                            Spacer()
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                Text(selected.pillLabel)
                    .font(OPSStyle.Typography.captionBold)
                    .foregroundColor(OPSStyle.Colors.primaryText)
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(OPSStyle.Colors.primaryAccent)
            }
            .padding(.horizontal, OPSStyle.Layout.spacing2_5)  // 12pt
            .padding(.vertical, OPSStyle.Layout.spacing2)      // 8pt
            .background(OPSStyle.Colors.cardBackground)        // #191919
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
            )
            .cornerRadius(12)
        }
    }
}

extension MoneyDashboardViewModel.Period {
    var pillLabel: String {
        switch self {
        case .month:       return "30 DAYS"
        case .quarter:     return "90 DAYS"
        case .sixMonths:   return "6 MONTHS"
        case .year:        return "1 YEAR"
        case .thisMonth:   return "THIS MONTH"
        case .lastMonth:   return "LAST MONTH"
        case .thisQuarter: return "THIS QUARTER"
        case .ytd:         return "YEAR TO DATE"
        }
    }

    var shortLabel: String {
        switch self {
        case .month:       return "30D"
        case .quarter:     return "90D"
        case .sixMonths:   return "6M"
        case .year:        return "1Y"
        case .thisMonth:   return "MTD"
        case .lastMonth:   return "LAST"
        case .thisQuarter: return "QTD"
        case .ytd:         return "YTD"
        }
    }
}
```

### 4.5 `OPS/Views/Books/CollapsedCarouselStrip.swift`

```swift
import SwiftUI

struct CollapsedCarouselStrip: View {
    @ObservedObject var viewModel: MoneyDashboardViewModel
    var activeCard: HeroCarousel.CardID
    var visibleCards: [HeroCarousel.CardID]

    private var primaryLabel: String {
        switch activeCard {
        case .pl:        return "NET · \(viewModel.selectedPeriod.shortLabel)"
        case .cashFlow:  return "FLOW · \(viewModel.selectedPeriod.shortLabel)"
        case .ar:        return "A/R OPEN"
        case .forecast:  return "FORECAST"
        case .jobs:      return "JOBS NET"
        }
    }

    private var primaryValue: Double {
        switch activeCard {
        case .pl:        return viewModel.netCash
        case .cashFlow:  return viewModel.netCash
        case .ar:        return viewModel.outstandingInvoiceBreakdown.reduce(0) { $0 + $1.amount }
        case .forecast:  return viewModel.weightedForecastValue
        case .jobs:      return viewModel.topProjectsByNet.reduce(0) { $0 + $1.net }
        }
    }

    var body: some View {
        HStack(spacing: OPSStyle.Layout.spacing3) {
            VStack(alignment: .leading, spacing: 1) {
                Text(primaryLabel)
                    .font(OPSStyle.Typography.smallCaption)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
                Text(primaryValue, format: .currency(code: "USD").precision(.fractionLength(0)))
                    .font(OPSStyle.Typography.bodyBold)
                    .foregroundColor(OPSStyle.Colors.primaryText)
                    .monospacedDigit()
                    .contentTransition(.numericText())
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 1) {
                Text("A/R")
                    .font(OPSStyle.Typography.smallCaption)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
                Text(viewModel.overdueInvoicesValue, format: .currency(code: "USD").precision(.fractionLength(0)))
                    .font(OPSStyle.Typography.bodyBold)
                    .foregroundColor(OPSStyle.Colors.errorStatus)
                    .monospacedDigit()
            }
            HStack(spacing: 4) {
                ForEach(visibleCards) { card in
                    Capsule()
                        .fill(card == activeCard ? OPSStyle.Colors.primaryAccent : OPSStyle.Colors.cardBorder)
                        .frame(width: card == activeCard ? 12 : 4, height: 4)
                }
            }
        }
        .padding(.horizontal, OPSStyle.Layout.spacing3)
        .padding(.vertical, OPSStyle.Layout.spacing2)
        .background(OPSStyle.Colors.background.opacity(0.95))
        .overlay(
            Rectangle()
                .fill(OPSStyle.Colors.cardBorder)
                .frame(height: 0.5),
            alignment: .bottom
        )
    }
}
```

### 4.6 `OPS/Views/Books/Cards/PLCard.swift` — Card 1

```swift
import SwiftUI

struct PLCard: View {
    @ObservedObject var viewModel: MoneyDashboardViewModel
    var onTapOutstanding: () -> Void
    var onTapForecast: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false

    private var marginFraction: Double {
        viewModel.totalPayments > 0
            ? max(0, viewModel.netCash / viewModel.totalPayments)
            : 0
    }

    var body: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
            row(label: "PAYMENTS IN", value: viewModel.totalPayments, color: OPSStyle.Colors.successStatus, sign: "+")
            row(label: "EXPENSES OUT", value: viewModel.totalExpenses, color: OPSStyle.Colors.warningStatus, sign: "−")

            Divider().background(OPSStyle.Colors.cardBorder)

            HStack(alignment: .lastTextBaseline) {
                Text("NET CASH")
                    .font(OPSStyle.Typography.captionBold)
                    .foregroundColor(OPSStyle.Colors.primaryText)
                Spacer()
                Text(viewModel.netCash, format: .currency(code: "USD").precision(.fractionLength(0)))
                    .font(OPSStyle.Typography.title)
                    .foregroundColor(viewModel.netCash >= 0 ? OPSStyle.Colors.primaryText : OPSStyle.Colors.errorStatus)
                    .monospacedDigit()
                    .contentTransition(.numericText())
            }

            marginBar

            HStack(spacing: OPSStyle.Layout.spacing2) {
                tile(label: "OUTSTANDING", value: viewModel.overdueInvoicesValue, count: viewModel.overdueInvoicesCount, valueColor: OPSStyle.Colors.errorStatus, action: onTapOutstanding)
                tile(label: "FORECAST", value: viewModel.pendingEstimatesValue, count: viewModel.pendingEstimatesCount, valueColor: OPSStyle.Colors.primaryAccent, action: onTapForecast)
            }
        }
        .padding(.horizontal, OPSStyle.Layout.spacing3)
        .onAppear {
            withAnimation(reduceMotion ? .none : OPSStyle.Animation.standard) {
                appeared = true
            }
        }
    }

    private func row(label: String, value: Double, color: Color, sign: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(OPSStyle.Typography.smallCaption)
                .foregroundColor(color)
            Spacer()
            Text("\(sign)\(currencyString(value))")
                .font(OPSStyle.Typography.bodyBold)
                .foregroundColor(color)
                .monospacedDigit()
                .contentTransition(.numericText())
        }
    }

    private var marginBar: some View {
        VStack(alignment: .leading, spacing: 4) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(OPSStyle.Colors.warningStatus.opacity(0.3))
                        .frame(height: 4)
                    RoundedRectangle(cornerRadius: 2)
                        .fill(OPSStyle.Colors.successStatus)
                        .frame(width: appeared ? geo.size.width * marginFraction : 0, height: 4)
                        .animation(reduceMotion ? .none : OPSStyle.Animation.standard, value: appeared)
                }
            }
            .frame(height: 4)
            Text("\(Int((marginFraction * 100).rounded()))% MARGIN")
                .font(OPSStyle.Typography.smallCaption)
                .foregroundColor(OPSStyle.Colors.tertiaryText)
        }
    }

    private func tile(label: String, value: Double, count: Int, valueColor: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 2) {
                Text(label).font(OPSStyle.Typography.smallCaption).foregroundColor(OPSStyle.Colors.secondaryText)
                Text(currencyString(value)).font(OPSStyle.Typography.bodyBold).foregroundColor(valueColor).monospacedDigit()
                Text("\(count) \(count == 1 ? "ITEM" : "ITEMS")").font(OPSStyle.Typography.smallCaption).foregroundColor(OPSStyle.Colors.tertiaryText)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(OPSStyle.Layout.spacing2)
            .background(OPSStyle.Colors.cardBackgroundDark)
            .overlay(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.smallCornerRadius)
                    .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
            )
            .cornerRadius(OPSStyle.Layout.smallCornerRadius)
        }
        .buttonStyle(PlainButtonStyle())
        .frame(minHeight: OPSStyle.Layout.touchTargetMin)
    }

    private func currencyString(_ value: Double) -> String {
        value.formatted(.currency(code: "USD").precision(.fractionLength(0)))
    }
}
```

### 4.7 `OPS/Views/Books/Cards/CashFlowCard.swift` — Card 2

```swift
import SwiftUI
import Charts

struct CashFlowCard: View {
    @ObservedObject var viewModel: MoneyDashboardViewModel
    var onTapDays: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private struct WeekRow: Identifiable {
        let id = UUID()
        let weekStart: Date
        let inAmount: Double
        let outAmount: Double
    }

    private var weeks: [WeekRow] {
        let inDict = Dictionary(uniqueKeysWithValues: viewModel.paymentsByWeek.map { ($0.weekStart, $0.amount) })
        let outDict = Dictionary(uniqueKeysWithValues: viewModel.expensesByWeek.map { ($0.weekStart, $0.amount) })
        let allWeeks = Set(inDict.keys).union(outDict.keys).sorted()
        return allWeeks.map { ws in
            WeekRow(weekStart: ws, inAmount: inDict[ws] ?? 0, outAmount: outDict[ws] ?? 0)
        }
    }

    private var avgPerWeek: Double {
        let nonZero = weeks.filter { $0.inAmount > 0 }
        guard !nonZero.isEmpty else { return 0 }
        return nonZero.map { $0.inAmount }.reduce(0, +) / Double(nonZero.count)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
            HStack(alignment: .firstTextBaseline) {
                Text(viewModel.netCash, format: .currency(code: "USD").precision(.fractionLength(0)))
                    .font(OPSStyle.Typography.title)
                    .foregroundColor(OPSStyle.Colors.primaryText)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                Spacer()
                legend
            }

            if weeks.isEmpty {
                emptyState
            } else {
                Chart(weeks) { row in
                    BarMark(
                        x: .value("Week", row.weekStart, unit: .weekOfYear),
                        y: .value("In", row.inAmount),
                        width: .ratio(0.4)
                    )
                    .foregroundStyle(OPSStyle.Colors.successStatus)
                    .position(by: .value("Direction", "In"))

                    BarMark(
                        x: .value("Week", row.weekStart, unit: .weekOfYear),
                        y: .value("Out", row.outAmount),
                        width: .ratio(0.4)
                    )
                    .foregroundStyle(OPSStyle.Colors.warningStatus)
                    .position(by: .value("Direction", "Out"))
                }
                .frame(height: 120)
                .chartXAxis {
                    AxisMarks(values: .stride(by: .weekOfYear)) { _ in
                        AxisValueLabel(format: .dateTime.week(.weekOfMonth))
                            .foregroundStyle(OPSStyle.Colors.tertiaryText)
                    }
                }
                .chartYAxis(.hidden)
            }

            HStack(spacing: OPSStyle.Layout.spacing2) {
                tileContent(label: "SALES", value: currencyString(viewModel.totalSales))
                tileContent(label: "AVG/WK", value: currencyString(avgPerWeek), color: OPSStyle.Colors.successStatus)
                Button(action: onTapDays) {
                    tileContent(label: "DAYS", value: String(format: "%.1f", viewModel.avgDaysToPayment))
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
        .padding(.horizontal, OPSStyle.Layout.spacing3)
    }

    private var legend: some View {
        HStack(spacing: OPSStyle.Layout.spacing2) {
            legendDot(color: OPSStyle.Colors.successStatus, label: "IN")
            legendDot(color: OPSStyle.Colors.warningStatus, label: "OUT")
        }
    }

    private func legendDot(color: Color, label: String) -> some View {
        HStack(spacing: 3) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(label).font(OPSStyle.Typography.smallCaption).foregroundColor(OPSStyle.Colors.tertiaryText)
        }
    }

    private func tileContent(label: String, value: String, color: Color = OPSStyle.Colors.primaryText) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(OPSStyle.Typography.smallCaption).foregroundColor(OPSStyle.Colors.secondaryText)
            Text(value).font(OPSStyle.Typography.bodyBold).foregroundColor(color).monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(OPSStyle.Layout.spacing2)
        .background(OPSStyle.Colors.cardBackgroundDark)
        .overlay(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.smallCornerRadius)
                .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
        )
        .cornerRadius(OPSStyle.Layout.smallCornerRadius)
    }

    private var emptyState: some View {
        HStack {
            Spacer()
            Text("—")
                .font(OPSStyle.Typography.title)
                .foregroundColor(OPSStyle.Colors.tertiaryText)
            Spacer()
        }
        .frame(height: 120)
    }

    private func currencyString(_ value: Double) -> String {
        value.formatted(.currency(code: "USD").precision(.fractionLength(0)))
    }
}
```

### 4.8 `OPS/Views/Books/Cards/ARCard.swift` — Card 3

```swift
import SwiftUI

struct ARCard: View {
    @ObservedObject var viewModel: MoneyDashboardViewModel
    var onTapTopChase: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false

    private struct Bucket: Identifiable {
        let id = UUID()
        let label: String
        let amount: Double
        let color: Color
        let fraction: Double
    }

    private var buckets: [Bucket] {
        let today = Date()
        var b0_30: Double = 0
        var b31_60: Double = 0
        var b61_90: Double = 0
        var b90: Double = 0
        for item in viewModel.outstandingInvoiceBreakdown {
            guard let due = item.date else { continue }
            let days = Int(today.timeIntervalSince(due) / 86400)
            if days < 0 { continue }
            switch days {
            case 0...30:  b0_30  += item.amount
            case 31...60: b31_60 += item.amount
            case 61...90: b61_90 += item.amount
            default:      b90    += item.amount
            }
        }
        let amounts = [b0_30, b31_60, b61_90, b90]
        let maxV = max(amounts.max() ?? 0, 1)
        let labels = ["0–30d", "31–60d", "61–90d", "90d+"]
        let colors = [
            OPSStyle.Colors.successStatus,            // olive
            OPSStyle.Colors.accountingReceivables,    // #D4A574 warm amber
            OPSStyle.Colors.warningStatus,            // tan
            OPSStyle.Colors.accountingOverdue         // brick #93321A
        ]
        return (0..<4).map { i in
            Bucket(label: labels[i], amount: amounts[i], color: colors[i], fraction: amounts[i] / maxV)
        }
    }

    private var totalOutstanding: Double {
        viewModel.outstandingInvoiceBreakdown.reduce(0) { $0 + $1.amount }
    }

    private var topChase: MoneyDashboardViewModel.BreakdownItem? {
        viewModel.outstandingInvoiceBreakdown.max(by: { $0.amount < $1.amount })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
            Text(totalOutstanding, format: .currency(code: "USD").precision(.fractionLength(0)))
                .font(OPSStyle.Typography.title)
                .foregroundColor(OPSStyle.Colors.errorStatus)
                .monospacedDigit()
                .contentTransition(.numericText())

            Text("\(viewModel.outstandingInvoiceBreakdown.count) OPEN · \(viewModel.overdueInvoicesCount) OVERDUE")
                .font(OPSStyle.Typography.smallCaption)
                .foregroundColor(OPSStyle.Colors.secondaryText)

            Text("AGING BUCKETS")
                .font(OPSStyle.Typography.smallCaption)
                .foregroundColor(OPSStyle.Colors.tertiaryText)
                .padding(.top, OPSStyle.Layout.spacing2)

            ForEach(Array(buckets.enumerated()), id: \.element.id) { idx, bucket in
                HStack(spacing: OPSStyle.Layout.spacing2) {
                    Text(bucket.label)
                        .font(OPSStyle.Typography.smallCaption)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                        .frame(width: 56, alignment: .leading)
                    GeometryReader { geo in
                        RoundedRectangle(cornerRadius: 2)
                            .fill(bucket.color)
                            .frame(width: appeared ? geo.size.width * bucket.fraction : 0, height: 8)
                            .animation(reduceMotion ? .none : OPSStyle.Animation.standard.delay(0.05 * Double(idx)), value: appeared)
                    }
                    .frame(height: 8)
                    Text(bucket.amount, format: .currency(code: "USD").precision(.fractionLength(0)))
                        .font(OPSStyle.Typography.smallCaption)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                        .monospacedDigit()
                }
            }

            if let top = topChase {
                Button(action: onTapTopChase) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("TOP CHASE").font(OPSStyle.Typography.smallCaption).foregroundColor(OPSStyle.Colors.secondaryText)
                            Text(top.label).font(OPSStyle.Typography.captionBold).foregroundColor(OPSStyle.Colors.primaryText).lineLimit(1)
                        }
                        Spacer()
                        Text(top.amount, format: .currency(code: "USD").precision(.fractionLength(0)))
                            .font(OPSStyle.Typography.bodyBold)
                            .foregroundColor(OPSStyle.Colors.errorStatus)
                            .monospacedDigit()
                    }
                    .padding(OPSStyle.Layout.spacing2)
                    .background(OPSStyle.Colors.cardBackgroundDark)
                    .overlay(
                        RoundedRectangle(cornerRadius: OPSStyle.Layout.smallCornerRadius)
                            .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
                    )
                    .cornerRadius(OPSStyle.Layout.smallCornerRadius)
                }
                .buttonStyle(PlainButtonStyle())
                .frame(minHeight: OPSStyle.Layout.touchTargetMin)
            }
        }
        .padding(.horizontal, OPSStyle.Layout.spacing3)
        .onAppear {
            withAnimation(reduceMotion ? .none : OPSStyle.Animation.standard) { appeared = true }
        }
    }
}
```

### 4.9 `OPS/Views/Books/Cards/ForecastCard.swift` — Card 4

```swift
import SwiftUI

struct ForecastCard: View {
    @ObservedObject var viewModel: MoneyDashboardViewModel
    var onTapCloseRate: () -> Void
    var onTapStale: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false

    private var maxStageValue: Double {
        max(viewModel.weightedForecastByStage.map { $0.value }.max() ?? 0, 1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
            Text(viewModel.weightedForecastValue, format: .currency(code: "USD").precision(.fractionLength(0)))
                .font(OPSStyle.Typography.title)
                .foregroundColor(OPSStyle.Colors.primaryAccent)   // steel blue allowed here
                .monospacedDigit()
                .contentTransition(.numericText())

            Text("\(viewModel.activeLeadCount) ACTIVE OPPS")
                .font(OPSStyle.Typography.smallCaption)
                .foregroundColor(OPSStyle.Colors.secondaryText)

            Text("BY STAGE")
                .font(OPSStyle.Typography.smallCaption)
                .foregroundColor(OPSStyle.Colors.tertiaryText)
                .padding(.top, OPSStyle.Layout.spacing2)

            if viewModel.weightedForecastByStage.isEmpty {
                Text("—")
                    .font(OPSStyle.Typography.body)
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, OPSStyle.Layout.spacing3)
            } else {
                ForEach(Array(viewModel.weightedForecastByStage.enumerated()), id: \.offset) { idx, row in
                    HStack(spacing: OPSStyle.Layout.spacing2) {
                        Text(row.stage.displayName)
                            .font(OPSStyle.Typography.smallCaption)
                            .foregroundColor(OPSStyle.Colors.secondaryText)
                            .frame(width: 88, alignment: .leading)
                            .lineLimit(1)
                        GeometryReader { geo in
                            RoundedRectangle(cornerRadius: 2)
                                .fill(OPSStyle.Colors.primaryAccent)   // steel blue allowed here
                                .frame(width: appeared ? geo.size.width * (row.value / maxStageValue) : 0, height: 10)
                                .animation(reduceMotion ? .none : OPSStyle.Animation.standard.delay(0.06 * Double(idx)), value: appeared)
                        }
                        .frame(height: 10)
                        Text(row.value, format: .currency(code: "USD").precision(.fractionLength(0)))
                            .font(OPSStyle.Typography.smallCaption)
                            .foregroundColor(OPSStyle.Colors.primaryText)
                            .monospacedDigit()
                    }
                }
            }

            HStack(spacing: OPSStyle.Layout.spacing2) {
                Button(action: onTapCloseRate) {
                    tileContent(label: "CLOSE RATE", value: "\(Int(viewModel.closeRate))%", color: OPSStyle.Colors.successStatus)
                }
                .buttonStyle(PlainButtonStyle())

                Button(action: onTapStale) {
                    tileContent(label: "STALE", value: "\(viewModel.staleLeadsCount)", color: OPSStyle.Colors.warningStatus)
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
        .padding(.horizontal, OPSStyle.Layout.spacing3)
        .onAppear {
            withAnimation(reduceMotion ? .none : OPSStyle.Animation.standard) { appeared = true }
        }
    }

    private func tileContent(label: String, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(OPSStyle.Typography.smallCaption).foregroundColor(OPSStyle.Colors.secondaryText)
            Text(value).font(OPSStyle.Typography.bodyBold).foregroundColor(color).monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(OPSStyle.Layout.spacing2)
        .background(OPSStyle.Colors.cardBackgroundDark)
        .overlay(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.smallCornerRadius)
                .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
        )
        .cornerRadius(OPSStyle.Layout.smallCornerRadius)
    }
}
```

### 4.10 `OPS/Views/Books/Cards/JobsCard.swift` — Card 5

```swift
import SwiftUI

struct JobsCard: View {
    @ObservedObject var viewModel: MoneyDashboardViewModel
    var onTapProfitable: () -> Void
    var onTapLosers: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false

    private var maxAbsNet: Double {
        max(viewModel.topProjectsByNet.map { abs($0.net) }.max() ?? 0, 1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
            if viewModel.topProjectsByNet.isEmpty {
                Text("—")
                    .font(OPSStyle.Typography.title)
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, OPSStyle.Layout.spacing3)
            } else {
                ForEach(Array(viewModel.topProjectsByNet.enumerated()), id: \.element.id) { idx, row in
                    HStack(spacing: OPSStyle.Layout.spacing2) {
                        Text(row.title.uppercased())
                            .font(OPSStyle.Typography.smallCaption)
                            .foregroundColor(OPSStyle.Colors.secondaryText)
                            .frame(width: 88, alignment: .leading)
                            .lineLimit(1)
                        GeometryReader { geo in
                            RoundedRectangle(cornerRadius: 2)
                                .fill(row.net >= 0 ? OPSStyle.Colors.successStatus : OPSStyle.Colors.errorStatus)
                                .frame(width: appeared ? geo.size.width * (abs(row.net) / maxAbsNet) : 0, height: 8)
                                .animation(reduceMotion ? .none : OPSStyle.Animation.standard.delay(0.06 * Double(idx)), value: appeared)
                        }
                        .frame(height: 8)
                        Text((row.net >= 0 ? "+" : "") + currencyString(row.net))
                            .font(OPSStyle.Typography.smallCaption)
                            .foregroundColor(row.net >= 0 ? OPSStyle.Colors.successStatus : OPSStyle.Colors.errorStatus)
                            .monospacedDigit()
                    }
                }
            }

            HStack(spacing: OPSStyle.Layout.spacing2) {
                Button(action: onTapProfitable) {
                    tileContent(label: "PROFITABLE", value: "\(viewModel.profitableProjectCount)", color: OPSStyle.Colors.successStatus)
                }
                .buttonStyle(PlainButtonStyle())

                tileContent(label: "AVG MARGIN", value: "\(Int((viewModel.avgProjectMargin * 100).rounded()))%", color: OPSStyle.Colors.primaryText)

                Button(action: onTapLosers) {
                    tileContent(label: "LOSERS", value: "\(viewModel.losersProjectCount)", color: OPSStyle.Colors.errorStatus)
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
        .padding(.horizontal, OPSStyle.Layout.spacing3)
        .onAppear {
            withAnimation(reduceMotion ? .none : OPSStyle.Animation.standard) { appeared = true }
        }
    }

    private func tileContent(label: String, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(OPSStyle.Typography.smallCaption).foregroundColor(OPSStyle.Colors.secondaryText)
            Text(value).font(OPSStyle.Typography.bodyBold).foregroundColor(color).monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(OPSStyle.Layout.spacing2)
        .background(OPSStyle.Colors.cardBackgroundDark)
        .overlay(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.smallCornerRadius)
                .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
        )
        .cornerRadius(OPSStyle.Layout.smallCornerRadius)
    }

    private func currencyString(_ value: Double) -> String {
        value.formatted(.currency(code: "USD").precision(.fractionLength(0)))
    }
}
```

---

## 5 · Data model (complete)

### 5.1 The dashboard ViewModel — every field the carousel reads

```swift
@MainActor
class MoneyDashboardViewModel: ObservableObject {

    // MARK: - Period selector

    enum Period: String, CaseIterable {
        case month       = "30D"      // Trailing 30 days
        case quarter     = "90D"      // Trailing 90 days
        case sixMonths   = "6M"
        case year        = "1Y"
        case thisMonth   = "MTD"      // Calendar month-to-date
        case lastMonth   = "LAST"     // Previous calendar month
        case thisQuarter = "QTD"
        case ytd         = "YTD"
    }

    // MARK: - Breakdown Item (used for A/R aging + drill-downs)

    struct BreakdownItem: Identifiable {
        let id = UUID()
        let label: String         // client name or invoice ref
        let amount: Double
        let date: Date?           // due date for invoices, paid_at for payments, expense_date for expenses
        let entityId: String
        let type: EntityType      // .payment, .expense, .invoice
    }

    // MARK: - Published properties consumed by the cards

    @Published var selectedPeriod: Period = .month
    @Published var isLoading: Bool = false

    // Top-level metrics (Card 1 P&L)
    @Published var totalSales: Double = 0          // total invoiced in period
    @Published var totalPayments: Double = 0       // payments received in period
    @Published var totalExpenses: Double = 0       // expenses in period
    @Published var netCash: Double = 0             // payments minus expenses

    // Pending / overdue (period-independent — Card 1 tiles)
    @Published var pendingEstimatesCount: Int = 0
    @Published var pendingEstimatesValue: Double = 0
    @Published var overdueInvoicesCount: Int = 0
    @Published var overdueInvoicesValue: Double = 0

    // Stat data (Cards 2, 4)
    @Published var closeRate: Double = 0           // % of estimates approved in period (Card 4)
    @Published var avgDaysToPayment: Double = 0    // avg days from invoice to paid (Card 2)
    @Published var expensesTrend: Double = 0       // % change vs prior period

    // Top unpaid invoices (Card 3 fallback)
    @Published var topUnpaidInvoices: [(clientName: String, amount: Double, daysOverdue: Int)] = []

    // Pipeline stats (Card 4 — only populated when pipeline.view granted)
    @Published var activeLeadCount: Int = 0
    @Published var weightedForecastValue: Double = 0
    @Published var staleLeadsCount: Int = 0
    @Published var nextFollowUpDue: Date? = nil

    // Breakdown arrays
    @Published var paymentBreakdown: [BreakdownItem] = []
    @Published var expenseBreakdown: [BreakdownItem] = []
    @Published var outstandingInvoiceBreakdown: [BreakdownItem] = []   // Card 3 input

    // Card 2 (Cash Flow) — weekly bucketing
    @Published var paymentsByWeek: [(weekStart: Date, amount: Double)] = []
    @Published var expensesByWeek: [(weekStart: Date, amount: Double)] = []

    // Card 4 (Forecast) — per-stage breakdown
    @Published var weightedForecastByStage: [(stage: PipelineStage, value: Double)] = []

    // Card 5 (Jobs) — per-project profitability
    struct JobNet: Identifiable {
        let id: String      // projectId
        let title: String
        let revenue: Double
        let cost: Double
        var net: Double { revenue - cost }
    }
    @Published var topProjectsByNet: [JobNet] = []
    @Published var profitableProjectCount: Int = 0
    @Published var avgProjectMargin: Double = 0
    @Published var losersProjectCount: Int = 0
}
```

### 5.2 PipelineStage enum (used by Card 4)

```swift
enum PipelineStage: String, CaseIterable {
    case newLead      = "new_lead"
    case qualifying   = "qualifying"
    case quoting      = "quoting"
    case quoted       = "quoted"
    case followUp     = "follow_up"
    case negotiation  = "negotiation"
    case won          = "won"
    case lost         = "lost"

    var displayName: String {
        switch self {
        case .newLead:     return "NEW LEAD"
        case .qualifying:  return "QUALIFYING"
        case .quoting:     return "QUOTING"
        case .quoted:      return "QUOTED"
        case .followUp:    return "FOLLOW-UP"
        case .negotiation: return "NEGOTIATION"
        case .won:         return "WON"
        case .lost:        return "LOST"
        }
    }
}
```

### 5.3 Seeded sample data (for designing against realistic numbers)

Use these values in your mockups — they're the same numbers the live preview renders:

```
Period: 6 MONTHS

Card 1 — P&L
  PAYMENTS IN     +$118,400
  EXPENSES OUT    −$76,220
  NET CASH        $42,180
  MARGIN          36%
  OUTSTANDING     $12,640 · 4 items
  FORECAST        $38,900 · 7 items

Card 2 — Cash flow
  NET CASH        $42,180
  Weekly buckets (8 weeks, oldest to newest):
    in:  [8.2k, 14.5k, 11.9k, 18.7k, 9.3k, 22.1k, 16.8k, 17.9k]
    out: [4.1k,  7.2k,  9.8k,  6.5k, 11.4k, 8.9k, 12.3k, 15.0k]
  SALES           $142,800
  AVG/WK          $14,950
  DAYS            18.2

Card 3 — A/R aging (period-independent)
  TOTAL OUTSTANDING  $22,800
  5 OPEN · 4 OVERDUE
  Aging buckets:
    0–30d   $4,800   (ACME ROOFING, 10d)
    31–60d  $3,200   (NORTHWAY HVAC, 22d)
    61–90d  $6,400   (BRIDGEWATER PLBG, 48d) + $2,900 (QUARRY ELECTRIC, 75d)
    90d+    $5,500   (OAKMONT CONTRACT, 110d)
  TOP CHASE: BRIDGEWATER PLBG · $6,400

Card 4 — Forecast (period-independent)
  WEIGHTED FORECAST  $84,500
  12 ACTIVE OPPS
  By stage:
    QUALIFYING    $18,200
    QUOTING       $12,400
    QUOTED        $26,800
    FOLLOW-UP     $9,500
    NEGOTIATION   $17,600
  CLOSE RATE  64%
  STALE       3

Card 5 — Jobs
  Top 5 by net:
    PERRY ST RENO     +$19,500
    OAK GROVE NEW     +$19,800
    MILL POND ADDN    +$8,200
    STATE ST KITCHN   −$2,600
    RIVERVIEW DECK    −$4,400
  PROFITABLE  9
  AVG MARGIN  32%
  LOSERS      2
```

### 5.4 Underlying database tables (Supabase / PostgreSQL)

Read-only consumption. No new schema needed.

| Table | Used by | Key columns |
|---|---|---|
| `invoices` | Cards 1, 2, 3, 5 | `id`, `project_id`, `client_id`, `total`, `amount_paid`, `balance_due`, `status` ∈ {draft, sent, viewed, partial, paid, overdue, void}, `due_date`, `paid_at`, `deleted_at`, `created_at` |
| `payments` | Cards 1, 2 | `id`, `invoice_id`, `amount`, `payment_date`, `is_void` |
| `estimates` | Card 1 forecast tile, Card 4 | `id`, `total`, `status` ∈ {draft, sent, viewed, approved, rejected}, `sent_at`, `viewed_at`, `approved_at`, `deleted_at` |
| `expenses` | Cards 1, 2 | `id`, `amount`, `expense_date`, `status`, `deleted_at` |
| `expense_project_allocations` | Card 5 | `id`, `expense_id`, `project_id` (text), `percentage`, `amount` |
| `opportunities` | Card 4 | `id`, `stage` (matches PipelineStage enum), `estimated_value`, `win_probability`, `archived_at`, `deleted_at` |
| `projects` | Card 5 | `id` (uuid), `title`, `status`, `deleted_at` |

Example invoice JSON:

```json
{
  "id": "8e2c1f6a-e3d4-4b5a-9c7d-1f2e3a4b5c6d",
  "company_id": "07c91234-5678-9abc-def0-123456789abc",
  "project_id": "a31bb567-89ab-cdef-0123-456789abcdef",
  "client_id": "ce4f9876-5432-10fe-dcba-987654321fed",
  "invoice_number": "INV-00284",
  "total": 4800.00,
  "amount_paid": 1200.00,
  "balance_due": 3600.00,
  "status": "sent",
  "due_date": "2026-04-30",
  "paid_at": null,
  "deleted_at": null,
  "created_at": "2026-04-15T12:30:00Z",
  "payments": [
    {
      "id": "p1...",
      "amount": 1200.00,
      "payment_date": "2026-04-22",
      "is_void": false
    }
  ]
}
```

---

## 6 · iOS design tokens (what's actually in the codebase today)

The iOS app uses an enum-based token system at `OPS/Styles/OPSStyle.swift`. These are the values shipping today. Where they differ from the Design System above, design against the Design System and assume engineering will reconcile (notes in § 8).

### 6.1 Color tokens (Swift)

```swift
enum OPSStyle.Colors {
    // Brand
    static let primaryAccent     = Color("AccentPrimary")     // #6F94B0 steel blue
    static let secondaryAccent   = Color("AccentSecondary")   // #C4A868 tan

    // Backgrounds
    static let background        = Color("Background")        // #000000 pure black
    static let cardBackground    = Color("CardBackground")    // #191919 (legacy — design system has moved to glass)
    static let cardBackgroundDark = Color("CardBackgroundDark") // #0D0D0D

    // Borders (hairline-quiet, aligned to design system v2)
    static let cardBorder        = Color.white.opacity(0.09)
    static let cardBorderSubtle  = Color.white.opacity(0.05)
    static let inputFieldBorder  = Color.white.opacity(0.10)
    static let buttonBorder      = Color.white.opacity(0.10)

    // Text
    static let primaryText       = Color("TextPrimary")       // #EDEDED
    static let secondaryText     = Color("TextSecondary")     // #B5B5B5
    static let tertiaryText      = Color("TextTertiary")      // #8A8A8A
    static let inactiveText      = Color("TextInactive")      // #6A6A6A

    // Status (earth tones)
    static let successStatus     = Color("StatusSuccess")     // #9DB582 olive
    static let warningStatus     = Color("StatusWarning")     // #C4A868 tan
    static let errorStatus       = Color("StatusError")       // #93321A brick (also used as text on dark)

    // Accounting (Books-specific)
    static let accountingRevenue     = Color("Accounting/AccountingRevenue")     // #C4A868
    static let accountingProfit      = Color("Accounting/AccountingProfit")      // #9DB582
    static let accountingCost        = Color("Accounting/AccountingCost")        // #B58289
    static let accountingReceivables = Color("Accounting/AccountingReceivables") // #D4A574
    static let accountingOverdue     = Color("Accounting/AccountingOverdue")     // #93321A

    // Separators
    static let separator         = Color.white.opacity(0.10)
}
```

### 6.2 Typography tokens (Swift) — what the cards actually call

The Books cards use these specific font roles. Mapping to the design system:

| OPSStyle.Typography token | Family | Size | Weight | Used by |
|---|---|---|---|---|
| `.title` | Mohave | ~28pt | Light/300 | Hero numbers (NET CASH, TOTAL OUTSTANDING, WEIGHTED FORECAST) |
| `.captionBold` | JetBrains Mono | 14pt | Medium/500 | "NET CASH" label, "TOP CHASE" client name, period pill label |
| `.bodyBold` | JetBrains Mono | 14pt | Medium/500 | Tile values, row IN/OUT amounts, top chase amount |
| `.smallCaption` | JetBrains Mono | 12pt | Regular/400 | Tile labels (OUTSTANDING, AVG/WK), bucket labels, metadata |
| `.body` | Mohave | 15pt | Regular/400 | Empty state em-dash |
| `.sectionLabel` | Cake Mono | 14pt | Light/300 (uppercase) | Segmented control labels |
| `.pageTitle` | Cake Mono | 22pt | Light/300 (uppercase) | AppHeader title |

### 6.3 Layout tokens (Swift)

```swift
enum OPSStyle.Layout {
    static let spacing1   = 4.0
    static let spacing2   = 8.0
    static let spacing2_5: CGFloat = 12.0
    static let spacing3   = 16.0
    static let spacing3_5: CGFloat = 20.0
    static let spacing4   = 24.0
    static let spacing5   = 32.0

    static let touchTargetMin      = 44.0
    static let touchTargetStandard = 56.0
    static let touchTargetLarge    = 64.0

    // Radii
    static let panelRadius        = 10.0
    static let modalRadius        = 12.0
    static let chipRadius         = 4.0
    static let progressBarRadius  = 2.0
    static let sidebarHoverRadius = 6.0

    // Legacy aliases (still used in code)
    static let cornerRadius       = 5.0   // buttons, inputs
    static let buttonRadius       = 5.0
    static let smallCornerRadius  = 4.0   // → chipRadius
    static let cardCornerRadius   = 10.0  // → panelRadius
    static let largeCornerRadius  = 12.0  // → modalRadius

    enum IconSize {
        static let xs: CGFloat = 12.0
        static let sm: CGFloat = 16.0
        static let md: CGFloat = 20.0
        static let lg: CGFloat = 24.0
        static let xl: CGFloat = 32.0
        static let xxl: CGFloat = 48.0
    }

    static let tabBarIconSize: CGFloat = 28.0

    enum Border {
        static let standard: CGFloat = 1.0
        static let thick:    CGFloat = 2.0
    }

    enum Indicator {
        static let dotSM: CGFloat = 6.0
        static let dotMD: CGFloat = 8.0
    }
}
```

### 6.4 Animation tokens (Swift)

```swift
enum OPSStyle.Animation {
    // The single OPS easing curve: cubic-bezier(0.22, 1, 0.36, 1)
    static let hover    = SwiftUI.Animation.timingCurve(0.22, 1, 0.36, 1, duration: 0.150)
    static let panel    = SwiftUI.Animation.timingCurve(0.22, 1, 0.36, 1, duration: 0.200)
    static let page     = SwiftUI.Animation.timingCurve(0.22, 1, 0.36, 1, duration: 0.250)
    static let flip     = SwiftUI.Animation.timingCurve(0.22, 1, 0.36, 1, duration: 0.350)
    static let standard = SwiftUI.Animation.timingCurve(0.22, 1, 0.36, 1, duration: 0.250)  // alias

    // Durations
    static let durationHover:       Double = 0.150
    static let durationPanel:       Double = 0.200
    static let durationPage:        Double = 0.250
    static let durationStagger:     Double = 0.300
    static let durationStaggerStep: Double = 0.050
    static let durationChartBar:    Double = 0.400
    static let durationFlip:        Double = 0.350
    static let durationCountUp:     Double = 0.800

    // DEPRECATED — do NOT spec spring physics for Books
    static let spring     = SwiftUI.Animation.spring(...)  // for legacy compatibility only
    static let springFast = SwiftUI.Animation.spring(...)  // for legacy compatibility only
}
```

---

## 7 · Tab bar & screen-container conventions

### 7.1 Tab bar — `OPS/Views/Components/Common/CustomTabBar.swift`

The bottom tab bar is custom-built (not stock `TabView`). 100pt tall, ultra-thin material blur background with a `#0D0D0D` overlay at 40%.

```swift
struct CustomTabBar: View {
    @Binding var selectedTab: Int
    let tabs: [TabItem]

    @State private var selectedIndicatorOffset: CGFloat = 0
    @State private var tabWidth: CGFloat = 0
    @State private var iconWidth: CGFloat = 28

    var body: some View {
        ZStack(alignment: .top) {
            ZStack {
                BlurView(style: .systemUltraThinMaterialDark)
                OPSStyle.Colors.cardBackgroundDark.opacity(0.4)
            }
            .frame(height: 100)

            VStack(spacing: 0) {
                // Sliding indicator bar — 3pt steel-blue underline
                HStack {
                    Rectangle()
                        .fill(OPSStyle.Colors.primaryAccent)
                        .frame(width: iconWidth, height: 3)
                        .cornerRadius(OPSStyle.Layout.smallCornerRadius)
                        .offset(x: selectedIndicatorOffset)
                        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: selectedIndicatorOffset)
                    Spacer()
                }
                .padding(.horizontal, OPSStyle.Layout.spacing3)

                // Tab items
                HStack(spacing: 0) {
                    ForEach(Array(tabs.enumerated()), id: \.element.id) { index, tab in
                        TabBarItem(tab: tab, isSelected: selectedTab == index, action: { ... })
                            .frame(maxWidth: .infinity)
                    }
                }
                .padding(.horizontal, OPSStyle.Layout.spacing3)
                .padding(.bottom, 16)
            }
            .padding(.top, 16)
        }
    }
}

struct TabBarItem: View {
    let tab: TabItem
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: tab.iconName)
                    .font(.system(size: OPSStyle.Layout.tabBarIconSize, weight: .medium))   // 28pt
                    .foregroundColor(isSelected ? OPSStyle.Colors.primaryAccent : OPSStyle.Colors.secondaryText)

                if let title = tab.title {
                    Text(title)
                        .font(OPSStyle.Typography.smallCaption)
                        .foregroundColor(isSelected ? OPSStyle.Colors.primaryAccent : OPSStyle.Colors.secondaryText)
                }
            }
        }
        .frame(height: 50)
    }
}

struct TabItem: Identifiable {
    let id = UUID()
    let iconName: String     // SF Symbol name
    let title: String?       // currently nil for all tabs (icon-only)
    let wizardStepId: String?
}
```

**Visuals at rest:** icon-only tabs (no labels by default), 28pt SF Symbol icons. Active icon tinted steel-blue `#6F94B0`. Inactive tinted `#B5B5B5`. A 3pt steel-blue underline slides between active tab positions using a spring animation (this is a design-system violation — open for redesign).

### 7.2 Tab declarations — `OPS/Views/MainTabView.swift`

```swift
private var tabs: [TabItem] {
    var baseTabs: [TabItem] = [
        TabItem(iconName: "house.fill", wizardStepId: "welcome_home")
    ]

    // LEADS — permission + feature flag
    if hasLeadsAccess {
        baseTabs.append(TabItem(
            iconName: "point.3.connected.trianglepath.dotted",
            wizardStepId: "welcome_leads"
        ))
    }

    // BOOKS — any of finances.view / estimates.view / expenses.view
    if hasBooksAccess {
        baseTabs.append(TabItem(iconName: "chart.line.uptrend.xyaxis", wizardStepId: "welcome_books"))
    }

    // Job Board — everyone
    baseTabs.append(TabItem(iconName: "briefcase.fill", wizardStepId: "welcome_job_board"))

    // Catalog
    if hasCatalogAccess {
        baseTabs.append(TabItem(iconName: "square.stack.3d.up.fill", wizardStepId: "welcome_catalog"))
    }

    // Schedule + Settings — everyone
    baseTabs.append(contentsOf: [
        TabItem(iconName: "calendar", wizardStepId: "welcome_schedule"),
        TabItem(iconName: "gearshape.fill", wizardStepId: "welcome_settings")
    ])

    return baseTabs
}

private var hasBooksAccess: Bool {
    permissionStore.can("finances.view")
        || permissionStore.can("estimates.view")
        || permissionStore.can("expenses.view")
}
```

### 7.3 Screen container convention

Every tab screen wraps in its own `NavigationStack` and starts with an `AppHeader` (a shared component, not in scope for redesign):

```swift
var body: some View {
    NavigationStack {
        VStack(spacing: 0) {
            AppHeader(headerType: .books)        // header type controls title + right-side icons
                .padding(.bottom, 8)

            // ... screen content
        }
        .background(OPSStyle.Colors.background.ignoresSafeArea())
    }
}
```

`AppHeader.HeaderType` includes cases like `.home`, `.books`, `.schedule`, `.settings` — Books renders the `"// BOOKS"` title.

---

## 8 · What's locked vs what's open

### 8.1 LOCKED — do not redesign

- **The OPS visual system.** Brand voice, three-font system, color tokens, motion rules, anti-patterns. All from § 2.
- **AppHeader, CustomTabBar, FloatingActionMenu** are shared components and out of scope.
- **List views inside the segments** (InvoicesListView, EstimatesListView, ExpensesListView, MyExpensesView) — existing implementations, not in scope.
- **The 5-card lineup.** Cards 1/2/3/4/5 = P&L, Cash Flow, A/R, Forecast, Jobs. The questions they answer are non-negotiable.
- **The 3-segment order.** INVOICES · ESTIMATES · EXPENSES, in that order.
- **Permission gating logic.**
- **The 8 period options.**
- **Bottom-tab placement of Books** (second from left, after Home).
- **SF Symbols for iOS icons** (no migration to Lucide planned).
- **Portrait orientation only.** No iPad split view in v1.
- **Offline-first.** First paint from cached SwiftData, no spinner before content.

### 8.2 OPEN — propose options

- **Books tab icon.** Currently `chart.line.uptrend.xyaxis` (SF Symbol). Alternatives welcome: `chart.bar`, `dollarsign.circle`, `creditcard.fill`, custom mark.
- **Hero card framing.** Today: borderless (flush canvas). Previously: bordered panels. Third option (e.g. ultra-subtle hairline-only frame) is welcome.
- **Period pill placement.** Currently inline with each card's top header. Alternatives: above the carousel, sticky to screen top.
- **Card 4 accent treatment.** Currently steel-blue (the only card where accent appears as data color). Alternative: tan/amber for "future money."
- **Dot pagination styling.** Currently 16pt steel-blue capsule (active) + 5pt circles (inactive). Open to numbered, segmented-bar, or edge-peek variants.
- **Collapsed strip information density.** Currently active card metric + A/R glance + dots. Could carry more or less.
- **Chart styles** (Cash Flow, Forecast, Jobs). Open to alternatives within token constraints — bars must use semantic tones.
- **Empty states per card.** Currently each card shows `—` for zero. Could add a small system label like `// NO PAYMENTS THIS PERIOD`.
- **Scroll collapse transition.** Currently simple opacity fade + height collapse. Open to more sophisticated transitions.
- **Tile drill affordance.** Drill tiles look like all other content. Could have a subtle chevron, opacity treatment, or interaction state.
- **Card 5 (Jobs) bar style.** Currently absolute-value bars colored green/red. A true diverging chart (positive right, negative left from a center axis) is open.
- **Card-swap animation.** Currently no per-card entry animation beyond the dot pagination. Open to staggered fade-in / slide-in for tiles, bars.
- **Sliding tab-bar indicator.** Currently uses spring physics (violation). Open to OPS-canonical easing replacement.

### 8.3 Known drift the designer should be aware of

Two known inconsistencies between the design system canonical files:

1. **Radii.** `DESIGN.md` says panels 10px, modals 12px, buttons 5px, chips 4px. The CSS token file says panels 5px, modals 5px, buttons 2.5px, chips 2.5px (sharper revision in CSS that hasn't propagated). Design against the DESIGN.md values listed in § 2.5.

2. **Glass surfaces.** DESIGN.md says `rgba(18,18,20,0.58)` with 28px blur. CSS says `rgba(10,10,10,0.70)` with 20px blur. Use DESIGN.md values from § 2.4.

iOS-side drift to flag:

- `cardBackground` is still a flat `#191919` panel; design system has moved to `glass-surface` treatment. iOS engineering hasn't migrated yet. If you spec glass for Books, engineering will need to build a glass-surface SwiftUI modifier — feasible but a new build, not just a styling pass.
- The sliding tab-bar indicator uses spring physics, violating the motion rule. Welcome to spec a replacement.

---

## 9 · What to deliver back

When the design is complete, return:

### 9.1 Required

1. **Static mockups** at 390 × 844pt, dark mode, for every state:
   - Each of the 5 cards (active state, seeded numbers from § 5.3)
   - Each card's empty state (em-dash treatment)
   - The collapsed scroll strip (one mockup per active card)
   - The period pill open (menu expanded with all 8 options)
   - The 3-segment control in all three active states
   - Operator role state (no carousel, only ESTIMATES + EXPENSES segments)
2. **Token sheet** — every color, font size, spacing value, border-radius, motion duration used. Every value traces to a token in § 2 or § 6. If a new token is needed, flag it with proposed name + value.
3. **Spacing diagram** — for the hero carousel: padding between cards, padding inside cards, gap between sections, drill-tile spacing, dot pagination spacing.
4. **Motion notes** — for any custom transition beyond the defaults: duration, easing, properties animated.

### 9.2 Optional but valuable

5. **Interaction flow video** — screen recording of prototype showing card swipe, period change, tile drill, scroll collapse, segment switch.
6. **Edge cases** — what each card looks like when all numbers are zero, when one number is extremely large (overflow), when a chart has only 1 data point, when offline.
7. **Accessibility notes** — VoiceOver labels per card, dynamic-type adjustments at larger text sizes.

### 9.3 Format

- Figma file (preferred) with frames labeled by state
- Or Sketch / Adobe XD
- PDF export of all frames + the token sheet
- Reference screenshots from inspiration sources, credited

---

## 10 · Inspiration register

Designs in this lineage we want to inhabit (not copy):

- **xAI / Grok** — dark interfaces, monospace data readouts, minimal chrome, high-contrast hierarchy
- **SpaceX mission control** — tactical UI, data density with clarity, glass-over-black surfaces, monochrome with sparse semantic color
- **Apple Pro apps** (Logic, Final Cut, Xcode dark) — refined dark surfaces, subtle glass, precise typography
- **Bloomberg Terminal** — data-forward, mono typography, every pixel serves a purpose
- **Military HUD / command-deck** — uppercase labels, `//` prefixes, operator identity patterns, terse status language

The trade business owner with OPS open on their phone deserves the same caliber of interface that a SpaceX engineer or a Bloomberg trader gets.

---

## 11 · Project context

OPS is the operating system for trades businesses. The Books tab is one of six tabs in the iOS app, the second most-used tab (after Home). It replaced an earlier 4-segment hub design in May 2026 — the carousel-first shape is intentional and shipped.

We move fast. We pursue perfection. We don't ship "good enough." If something looks compromised, flag it.

Looking forward to the mockups.
