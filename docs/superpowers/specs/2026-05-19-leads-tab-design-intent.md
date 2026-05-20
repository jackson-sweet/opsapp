# LEADS Tab — Design Intent

> **Status:** PRE-DESIGN BRIEF · designer hand-off forthcoming
> **Audience:** Front-end / mobile UX designer producing mocks, then a back-channel handoff document for engineering implementation
> **Author:** Jackson (via Claude session, 2026-05-19)
> **Surface:** OPS iOS app, top-level `LEADS` tab
> **Replaces:** Embedded pipeline segment inside `BooksTabView` (pre-2026-05-11)
> **Current spec:** `docs/superpowers/specs/2026-05-11-pipeline-tab-design.md` (Phase 1 implementation already shipped to main — see §15 below for current-state inventory)

---

## 1 · WHY THIS TAB EXISTS

Pipeline **is** the business for most trade contractors. A roofer's calendar is downstream of which leads they close this week. An electrician's payroll depends on which quotes converted. We promoted pipeline out of `Books` (where it had been a segment between Estimates and Invoices) into its own top-level tab because:

1. The operator opens this surface **multiple times a day**, not weekly like financial review.
2. The actions taken here (advance, win, lose, follow up) determine cash flow 30–90 days out.
3. Pipeline-stage-derived urgency (overdue, stale, untouched) is the single most actionable signal in the app — but it was buried.

**The tab's purpose is to answer one question, fast: *"What do I need to do RIGHT NOW to close more business?"***

Everything else (forecast, velocity, close rate) is secondary context the operator glances at while drinking coffee.

---

## 2 · THE OPERATOR

| | |
|---|---|
| **Who** | Trades business owner — roofer, plumber, electrician, landscaper, GC. Solo or running a crew of 5–20. |
| **Where** | In the truck between job sites. On a roof. In a driveway. In a customer's living room. Rarely at a desk. |
| **When** | Morning coffee, between calls, end-of-day decompress. Each session is 30 seconds to 3 minutes. |
| **Mental state** | Drowning. Phone buzzing. 14 unread texts. Half-remembered names. Has not slept enough. Cannot tell you which lead is at $14K vs $24K without looking. |
| **Mobile context** | Direct sun on screen. Gloved fingers. One bar of signal. Phone might die in 20 min. |
| **What they are NOT** | Salesforce-trained sales operators. They don't think in MQL/SQL/win-loss/forecast confidence intervals. They think in **"who do I need to call back today"** and **"am I about to land that big job."** |
| **What they expect** | To open the app, see ONE thing that matters, act, and put the phone down. Not to "engage with a dashboard." |

**Design test:** if a stressed-out roofer opens this tab in a sunny truck cab and isn't *immediately* clearer about the next 10 minutes of their day, the tab failed.

---

## 3 · THE THREE QUESTIONS, IN ORDER

The tab must answer these three questions in this order of priority. Visual hierarchy follows.

| # | Question | Where to find the answer |
|---|---|---|
| **1** | What do I need to act on RIGHT NOW? | "Ball in your court" surface (overdue / stale / untouched leads assigned to me) |
| **2** | Is the pipeline healthy? | Forecast tile + close rate + velocity + stale-risk tiles |
| **3** | Where is *that specific lead*? | Stage navigation + per-stage list |

The screen is laid out top-down in this priority. Question 1 should be unmissable. Question 3 should be reachable in ≤2 taps.

---

## 4 · MENTAL MODEL — HOW THE OPERATOR THINKS

- **Stages are states, not steps.** A lead can sit in QUALIFYING for 14 days. Or jump from QUALIFYING straight to NEGOTIATION when the customer says "send the contract." Stages are not a linear funnel.
- **Time is the threat.** A `$5K` lead untouched for 1 day is fine. A `$50K` lead untouched for 5 days is bleeding. Time × value = anxiety.
- **Ownership matters.** "My leads" require my action. "The team's leads" are context. The tab is filterable by ownership but defaults to mine.
- **Closed isn't gone.** Won leads are evidence of progress. Lost leads are postmortems. Both are referenced but neither belongs in the main rotation. They live behind a `CLOSED` reveal.
- **Money is mono.** Dollar amounts are JetBrains Mono tabular-lining. Always. No "$1.2k" sloppy formatting — `$1,200` or `$1.2K` (uppercase K, one decimal only when ≥10K).

The operator does NOT think in:
- Win probability percentages (they ignore them)
- Velocity in days (they care about "are we waiting on me or them")
- Conversion funnels
- Lead "scores"
- Pipeline "stages" as a sales-process map

---

## 5 · INFORMATION HIERARCHY (TOP → BOTTOM)

```
┌─────────────────────────────────────┐
│ AppHeader (.leads) — operator id   │  ← persistent, ~52pt
├─────────────────────────────────────┤
│                                     │
│   HEALTH-AT-A-GLANCE                │  ← 5-card horizontal carousel
│   forecast · active · close-rate    │     answers question 2
│   · velocity · stale-risk           │
│                                     │
├─────────────────────────────────────┤
│   ⚠ BALL IN YOUR COURT              │  ← high-severity callout
│   N IN COURT · overdue / stale /…   │     answers question 1
│   tap to filter the list below      │     hidden when count = 0
├─────────────────────────────────────┤
│   STAGE STRIP (scrollable)          │  ← navigation
│   newLead · qualifying · quoting…   │     answers question 3
│   ─────                             │
├─────────────────────────────────────┤
│                                     │
│   LEAD LIST FOR SELECTED STAGE      │  ← per-stage list
│   ⎯ Lupita Garcia $32,000 1D       │     answers question 3 deeper
│   ⎯ Mike Smith    $8,500 0D        │
│   ⎯ Anna Patel    $22,400 9D STALE │
│                                     │
└─────────────────────────────────────┘
```

The designer should challenge this layout if they see a better answer. Specifically:
- Should "ball in your court" be the *first* surface (above the carousel) since it answers question 1?
- Is a horizontal 5-tile carousel the right pattern, or should one hero KPI dominate with the rest as a secondary strip?
- Should `CLOSED` (won/lost) be a sheet rather than a reveal in the stage strip?

**Designer's call. See §14 (open questions).**

---

## 6 · DATA AVAILABLE

The designer can rely on every field below being populated for each lead. No design should require fields the model doesn't have.

### Per-lead (from `Opportunity` model)

| Field | Type | Use in UI |
|---|---|---|
| `title` | String? | Lead headline. Falls back to `contactName` if empty. |
| `contactName` | String | Person or company name. |
| `contactEmail`, `contactPhone` | String? | Tap-to-call / tap-to-email surfaces. |
| `address` | String? | Map jump / distance display. |
| `descriptionText` | String? | Detail-view body. Rarely shown on the list row. |
| `stage` | PipelineStage | One of 8 (see §6 sub-table). |
| `stageEnteredAt` | Date | Drives `daysInStage`. |
| `assignedTo` | String? | User ID. Used by "ball in court" scoping. |
| `priority`, `source`, `tags[]` | metadata | Reserved for future filtering. Not required in v1. |
| `estimatedValue` | Double? | Currency. Drives forecast math. |
| `expectedCloseDate` | Date? | Reserved for future timeline view. |
| `nextFollowUpAt` | Date? | Drives `overdue` urgency tier. |
| `lastActivityAt` | Date? | Drives `untouched` and `stale` derivation. |
| `correspondenceCount`, `outboundCount`, `inboundCount`, `lastInboundAt`, `lastOutboundAt` | Int / Date? | Communication signal. Could surface in detail or as inline icon-counts. |

### The 8 stages and their per-stage characteristics

| Stage | Display | Default win prob | Stale after |
|---|---|---|---|
| `newLead` | NEW LEAD | 10% | 3 days |
| `qualifying` | QUALIFYING | 20% | 7 days |
| `quoting` | QUOTING | 40% | 5 days |
| `quoted` | QUOTED | 60% | 7 days |
| `followUp` | FOLLOW-UP | 50% | 3 days |
| `negotiation` | NEGOTIATION | 75% | 2 days |
| `won` | WON | 100% | n/a |
| `lost` | LOST | 0% | n/a |

### VM-derived (already computed, designer can reference)

- `weightedForecastValue` — sum of (`estimatedValue × winProbability`) across non-terminal leads
- `activeLeadCount` — non-terminal lead count
- `closeRate(periodDays: 90)` — `nil` when fewer than 5 closes in window
- `staleLeadsCount`, `staleLeadsTotalValue`, `oldestStaleDescription`
- `inCourtCount`, `inCourtBuckets {overdue, stale, untouched}`, `inCourtTotalValue`
- Per-stage `count(in:)` and `opportunities(in:)`

**Two fields are currently unprovided and render empty:** `avgVelocityDays` and `weightedForecastDelta`. Designer should plan as if they will be wired up; engineering will add them when this round of design lands.

---

## 7 · WHAT THIS TAB MUST DO WELL

1. **Surface the next action without thinking.** If 3 leads need follow-up today, the operator should know that within 2 seconds of opening the tab.
2. **Allow rapid state commit.** Mark won, mark lost, advance stage, archive — each in ≤2 taps. Swipe gestures preferred.
3. **Preserve context across navigation.** Switching stages should feel like flipping pages in a binder, not loading a new screen.
4. **Behave gracefully offline.** All reads work from local cache. Writes queue and show pending state, never block UI.
5. **Survive mid-sync.** If a lead is being saved from another device, surface the conflict without losing the operator's draft.
6. **Read clearly in direct sunlight.** Contrast ≥ 7:1 for body, 4.5:1 for labels. No mid-grey on dark.
7. **Be operable with gloves.** Every touch target ≥ 44pt. Swipe affordances large enough to grab.

---

## 8 · WHAT THIS TAB MUST NOT DO

- **No "convert your prospects faster" SaaS-tone.** No coaching language, no growth-mindset framing.
- **No accent color leakage.** Steel blue `#6F94B0` is **CTA + focus ring only**. Not on navigation. Not on counts. Not on chrome. Not on indicators.
- **No emoji.** Not in empty states. Not in success messages. Not in confetti animations (no confetti animations).
- **No exclamation points.** Ever.
- **No "Welcome back!" / first-run overlays / coach-marks / illustrated empty states.**
- **No vanity metrics.** Every number on screen answers a real question. No "leads created today" count for the sake of having it.
- **No spring physics, no bounce.** Single easing curve `cubic-bezier(0.22, 1, 0.36, 1)`. Drag-to-reorder is the only allowed exception (and there is no reorder UX on this tab).
- **No charts for vanity.** A mini stacked bar showing per-stage distribution is fine because it answers "where are most of my leads stuck?" — a pie chart of close-rate-by-source is not, until the operator asks.
- **No lead "score" badges.** Win probability is already encoded by stage. We do not display a score.
- **No predictive copy.** "Likely to close" / "high engagement" / "needs attention" framing is forbidden. State the fact (`3 OVERDUE`), don't editorialize.

---

## 9 · VOICE & COPY

Full ruleset: `ops-design-system/project/DESIGN.md` §2, `ops-design-system/project/README.md` § CONTENT FUNDAMENTALS, `ops-design-system/project/mobile/MOBILE.md`. Summary for the designer:

- **Person.** "You" only. Never "we." Never first-person.
- **Casing.** Sentence case for content (`Lupita Garcia`, `Hilltop pool deck`). UPPERCASE for authority (`NEW LEAD`, `STALE`, `WON`, `IN COURT`). Never Title Case.
- **Prefixes.** `//` for section labels. `[brackets]` for instructional micro-text. `SYS ::` for system state. `// OPERATOR :: <NAME>` for identity.
- **Numbers.** Always JetBrains Mono, tabular-lining. Always formatted (`$32,000`, never `32000`). Empty state is `—`, never `N/A`, never `0` (unless zero is meaningful).
- **Errors.** `// ERROR — UPLOAD FAILED`. Name the thing. Offer the next action. No "Oops!" / "Something went wrong."
- **Empty states.** `$0`, `0%`, `—`, or a one-line `// NO LEADS IN QUOTING`. No illustrations. No call-to-action copy beyond the existing FAB.

The designer should commit to the OPS voice for **every** label, chip, and microcopy moment. Sample lines we'd accept:

| Surface | Acceptable |
|---|---|
| Empty stage | `// NO LEADS IN QUALIFYING` |
| Empty pipeline | `// NO ACTIVE LEADS` |
| Empty won | `// NO WINS YET` |
| Sync pending on a lead | `// PENDING SYNC` |
| Sync failed on a lead | `// SYNC FAILED — TAP TO RETRY` |
| Filter applied | `FILTER ON · 7 LEADS` |
| Clear filter | `CLEAR` |
| Stale risk callout | `STALE RISK · 2 LEADS · $100,900` |
| Forecast tile | `WEIGHTED FORECAST` / `$184,240` / `LAST 30D` |

Use the existing `ops-copywriter` skill (or invoke it from this brief) for any new copy.

---

## 10 · VISUAL FOUNDATION — DESIGN SYSTEM CONSTRAINTS

Read these in this order before designing:

1. `ops-design-system/project/SKILL.md` — 1 minute orientation
2. `ops-design-system/project/README.md` — agent brief
3. `ops-design-system/project/DESIGN.md` — full visual system (single file)
4. `ops-design-system/project/mobile/MOBILE.md` — iOS-specific overrides (this is the operative doc for this work)
5. `ops-design-system/project/colors_and_type.css` — tokens (for prototype HTML if you make any)

### Non-negotiables for this tab

| | |
|---|---|
| **Canvas** | Pure `#000000`. No mid-grey background. |
| **Accent** | `#6F94B0` steel blue. Primary CTA fill and focus ring **only**. Anywhere else is a bug. |
| **Earth tones** | `#9DB582` olive (success/won/+delta), `#C4A868` tan (attention/stale), `#B58289` rose (error/overdue/lost), `#93321A` brick (destructive borders only). |
| **Type** | Mohave (body/names/hero numbers), JetBrains Mono (numbers/labels/`//`/`[]`), Cake Mono Light 300 (uppercase display — titles/buttons/badges). |
| **Numbers** | Always mono, `tnum 1, zero 1`. `$32,000` not `32000`. |
| **Surfaces** | L0 canvas → L1 glass section (`rgba(18,18,20,0.58)` + blur 28px + 0.09 hairline + 10pt radius) → L2 nested card (`rgba(255,255,255,0.04)` + 0.08 hairline + 6pt radius, no blur) → L3 inline (tags/badges). Max 2 layers of glass. |
| **Borders** | `--line` `rgba(255,255,255,0.10)`. Hairlines carry depth — never box-shadows. |
| **Radius** | 10 panels, 12 modals, 5 buttons/inputs, 4 chips, 2 progress bars, 6 sidebar hover, 999 only on avatars. |
| **Motion** | One curve: `cubic-bezier(0.22, 1, 0.36, 1)`. Mobile durations from `MOBILE.md` §11. No spring, no bounce. Reduced-motion fallback mandatory. |
| **Icons** | Lucide, 1.5px stroke, `currentColor`. 14pt inline / 16pt button / 20pt empty-state. No emoji. No filled icons. |
| **Touch targets** | 44 × 44pt minimum. Bottom CTAs 52pt minimum. |
| **Type floor** | 11pt minimum (mobile body 15pt, see `MOBILE.md` §1). |
| **Glare bar** | Mobile contrast is *higher* than web. See `MOBILE.md` §1.1 for the deltas. |

### Known drift the designer should resolve

Three current LEADS-tab patterns conflict with the design system. The designer should explicitly accept or reject each:

1. **Stage-color leading rail on the lead card and on the stale-risk KPI tile.** `DESIGN.md` §14 bans "cards with rounded corners + colored left-border accent." Current `LeadCard` and `LeadsHeaderCarousel.staleRiskCard` use this exact pattern. **Decide:** keep (and update the design system to scope this anti-pattern to specific contexts), or replace with a different stage-identity treatment (chip? underline? typography color?).
2. **`primaryAccent` leakage.** Currently used on: stage-strip active underline, stage-strip selected count, hero-carousel page dots, and the `BallInCourtBar` rail's "untouched-only" tier. All of these violate the accent-is-CTA-only rule. **Decide:** what to use instead — likely white (`--text`), `--text-3`, or a graphite hairline tone.
3. **Hero-carousel cards with no border (user request 2026-05-19).** Mobile spec §5 calls for L2 nested treatment (hairline border + 6pt radius). The user has asked for borderless. **Decide:** rescope the spec to "OPS App hero cards are borderless, fill-only," OR scope this divergence to LEADS only, OR revert.

---

## 11 · COLOR SEMANTICS WITHIN LEADS

| Concept | Color | Why |
|---|---|---|
| Overdue (a lead with `nextFollowUpAt ≤ now`) | Rose `#B58289` text + brick `#93321A` border | "You said you'd follow up. You didn't." This is the highest severity. |
| Stale (a lead past stale-threshold in its stage) | Tan `#C4A868` | "Time is starting to bite. Not yet bleeding." |
| Untouched (a `newLead` with no activity) | Neutral / `--text-3` | "Hasn't started the clock yet. Just inert." |
| Won | Olive `#9DB582` | Positive. The only place we celebrate. |
| Lost | Rose `#B58289` text on brick `#93321A` border | Loss. No drama, just acknowledgment. |
| Stage identity (newLead/qualifying/quoting/quoted/followUp/negotiation) | OPS v2 stage palette — see `OPSStyle.Colors.pipelineStageColor(for:)` (cool slate → steel → teal → warm gold → tan → terracotta) | Each stage is globally unique; helps the eye scan a mixed list. |

**Severity hierarchy:** rose > tan > neutral. A lead displays only one urgency chip — the highest applicable.

**Note for designer:** there is an existing bible palette in `PipelineStage+Color.swift` that disagrees with the OPSStyle v2 palette. **Use the OPSStyle v2 palette** — the older bible hexes are being deprecated.

---

## 12 · COMPONENT INVENTORY (existing — open to redesign)

| Component | File | What it does | Designer freedom |
|---|---|---|---|
| `LeadsTabView` | `OPS/Views/Leads/LeadsTabView.swift` | Root composition + nav, sheets, env objects | Layout structure open |
| `LeadsHeaderCarousel` | `OPS/Views/Leads/LeadsHeaderCarousel.swift` | 5-tile KPI carousel | Card composition, tile inventory, pattern (carousel vs strip) open |
| `BallInCourtBar` | `OPS/Views/Leads/BallInCourtBar.swift` | The "right-now" callout | Treatment open — could be hero card, sticky bar, banner, etc. |
| `LeadStageStrip` | `OPS/Views/Leads/Components/LeadStageStrip.swift` | Horizontal stage nav | Open — scrolling tabs is current, but consider 8 stages is at the edge of what a strip handles |
| `LeadListPage` | `OPS/Views/Leads/LeadListPage.swift` | Single-stage paged list | Layout open; empty-state copy open |
| `LeadCard` | `OPS/Views/Leads/Components/LeadCard.swift` | Single lead row | Card composition fully open (subject to anti-patterns above) |
| `ForecastBreakdownSheet` | `OPS/Views/Leads/Components/ForecastBreakdownSheet.swift` | Drill-in from forecast tile | Treatment open — bottom sheet currently |
| `LeadActionSheet` (legacy) | `OPS/Views/Books/Pipeline/LeadActionSheet.swift` | Long-press menu | Open to redesign |
| `LostReasonSheet` (legacy) | `OPS/Views/Books/Pipeline/LostReasonSheet.swift` | Lost-reason capture | Open |

---

## 13 · INTERACTION LANGUAGE

| Gesture | Result | Haptic |
|---|---|---|
| Tap lead card body | Push `LeadDetailView` | Light (transition) |
| Swipe leading on card | Reveal "→ next stage" action; commit on confirm | Medium (commit) |
| Swipe trailing on card | Reveal `WON` (left) + `LOST` (right); commit on tap | Success notification (WON) / medium (LOST) |
| Long-press card | Open `LeadActionSheet` (full action set) | Medium |
| Tap KPI tile | Drill into related sheet/filter (forecast → breakdown, active pipeline → largest stage, stale risk → in-court filter) | Light |
| Tap "ball in court" bar | Toggle in-court filter across the stage list | Light |
| Tap stage strip pill | Change selected stage | Light |
| Horizontal swipe on stage list | Switch to adjacent stage | Light (snap) |
| Tap `CLOSED` chip | Reveal Won + Lost stages in the strip | Light |
| Pull-to-refresh on stage list | Reload data | None |

Designer should add any new gestures with explicit haptic specs.

---

## 14 · STATES TO DESIGN

The designer must produce mocks for each of these. They are not optional.

1. **Rich loaded** — 20+ leads across stages, mixed urgency, current user has multiple in-court.
2. **Sparse loaded** — 1–3 leads total, none in-court.
3. **Empty pipeline** — zero leads ever created. First-run state. Carousel should show zero values gracefully.
4. **Empty per-stage** — most stages populated, one stage empty (e.g., QUOTED has zero).
5. **In-court avalanche** — operator is behind. 12+ overdue, multiple stale. The screen should feel urgent without panic-styling.
6. **All-stale** — nothing overdue, but a lot of dead weight in QUOTING and QUOTED.
7. **First-day operator** — no closes yet, so close rate = `—`, velocity = `—`. KPI tiles should degrade gracefully.
8. **Offline (loaded cache)** — data shows, but writes will queue. Surface offline state without alarm.
9. **Sync failure** — a recent mutation failed. Show on the affected lead, not as a global banner unless catastrophic.
10. **Loading (initial fetch)** — skeleton state. No spinner-on-blank.
11. **Permission-restricted** — operator lacks `pipeline.manage`. Read-only. Swipe actions should disappear, not gray out.
12. **Filter active** — in-court filter toggled on. All non-court leads hidden from the stage list. State should be unmissable but recoverable.
13. **CLOSED revealed** — won + lost stages exposed in the strip at 60% opacity.

---

## 15 · WHAT'S CURRENTLY SHIPPED

For context. The designer should consider this the **starting point, not the constraint**. Everything is open.

- LEADS is a top-level tab (`MainTabView`, gated on `hasLeadsAccess` permission). Released to main on 2026-05-12.
- The 5-card carousel exists in roughly the structure §5 sketches.
- The "ball in your court" bar exists, hidden when count = 0.
- Stage strip with `CLOSED` reveal exists.
- Per-stage paged TabView of `LeadCard` rows exists.
- Swipe actions on cards exist (leading = advance, trailing = won/lost).
- Forecast tile is tappable → opens `ForecastBreakdownSheet`.
- Long-press on a card opens `LeadActionSheet`.
- A small set of UI/UX issues have been raised by the user — including the "make hero cards borderless" request — which is what triggered this re-design effort.

Live preview scaffolding for every Leads view is in place — see `OPS/Views/Leads/LeadsPreviewSupport.swift` and the `#Preview` macros at the bottom of each Leads file. The designer can hand a CSS/HTML or Figma mock and engineering can validate against live SwiftUI previews without rebuilding.

---

## 16 · OPEN DESIGN QUESTIONS — designer's call

The user explicitly wants the designer to take a position on each of these. There are no right answers; we want the designer to commit.

1. **Top-of-screen pattern.** Is a 5-tile horizontal carousel right, or should one hero KPI dominate with secondary tiles below? Or a non-carousel pattern (grid, fold, etc.)?
2. **"Ball in your court" placement.** Should it be above the carousel (as the answer to question 1) or below the carousel (as a callout layered on top of the navigation)? Current = below.
3. **Stage navigation pattern.** 8 stages with a CLOSED reveal is at the edge of what a scrolling tab strip handles. Alternative: 6 active visible + "MORE" sheet. Or grouped (early/mid/late). Or no stage strip at all (single chronological list with stage as visual identity).
4. **Stage identity on cards.** Keep the 3pt leading rail (and accept the design-system anti-pattern), or replace with a stage chip / stage-tinted typography / something else.
5. **Closed leads (won/lost) placement.** Current: revealed in the stage strip at 60% opacity. Alternative: dedicated `// HISTORY` section, or a sheet, or a separate top-level view from the FAB.
6. **Hero-carousel card chrome.** User has asked for borderless; the spec is bordered. Designer decides what the carousel cards look like (and if it propagates to all KPI tiles globally or stays scoped to LEADS).
7. **Forecast breakdown.** Current: bottom sheet listing leads by weighted value desc. Alternative: drill into a dedicated screen with filters and grouping. Or inline expansion.
8. **Filter affordance.** Current: tap the "ball in your court" bar to toggle. Is there a better surface for filters that hints at multi-select (by-stage, by-value, by-priority) in the future?
9. **Empty-state framing.** What does the screen look like when the operator has zero leads? Current: each stage shows a `// NO LEADS IN <STAGE>` line. Carousel zeros out. There may be a better composition.
10. **Add-lead surface.** Currently lives in the FAB MONEY group ("ADD LEAD" surfaces first when on LEADS tab). Is the FAB right, or should LEADS have a primary CTA on the screen itself?

---

## 17 · TECHNICAL CONSTRAINTS THE DESIGNER SHOULD KNOW

- **Platform:** iOS, SwiftUI. iOS 17+. Target devices iPhone 12 mini → iPhone 16 Pro Max.
- **Frame:** 390 × 844pt baseline (iPhone 14/15 Pro). Smaller devices (mini) should not crop critical content.
- **Orientation:** Portrait only.
- **Theme:** **Dark only.** OPS does not ship a light theme.
- **Dynamic Type:** Respected. Body floor 16pt.
- **Offline-first:** All data reads from local SwiftData cache. Writes are optimistic, queued.
- **Token vocabulary:** `OPSStyle.Colors.*`, `OPSStyle.Typography.*`, `OPSStyle.Layout.*`, `OPSStyle.Animation.*`. No hex/spacing/font/radii improvisation in production code.
- **Haptics are mandatory** for meaningful interactions. Light = transition / select. Medium = commit. Success = WON. No haptic spam.
- **Reduced motion:** every transition must have a 150ms opacity fallback.
- **Voice/copy hand-off:** any new copy must be drafted with the `ops-copywriter` skill or pulled from existing OPS voice patterns.

---

## 18 · SUCCESS CRITERIA

In priority order:

1. **A solo operator can open the tab in a sunny truck cab and within 3 seconds know whether they need to act.**
2. The single most important action (the top item in "ball in your court") is reachable in ≤2 taps.
3. The screen feels calmer when nothing's wrong, and louder when something is.
4. Stage navigation feels like flipping pages, not loading.
5. State commits (advance / won / lost) feel decisive — one gesture, one haptic, done.
6. The forecast number, when present, is unmistakably the biggest piece of monospace on the screen.
7. No mocks contain a single design-system anti-pattern that isn't explicitly justified in the decision log (§19).
8. The mocks include every state in §14. No "happy path only."

---

## 19 · DESIGNER DELIVERABLES

We want the designer to return a **handoff document** that contains:

1. **High-fidelity mocks** for each state in §14 — PNG, PDF, or Figma exports. PNG preferred for quick reference in code reviews.
2. **Component-level breakdown** — for each component, the exact tokens used (color, type role, spacing, radius, motion). Reference `OPSStyle` Swift names where possible.
3. **Interaction notes** — what each tap, swipe, long-press, drag does. Haptic specs included.
4. **Animation spec** — every transition with duration + easing + reduced-motion fallback.
5. **Accessibility callouts** — VoiceOver labels, focus order, contrast checks for any non-trivial composition.
6. **Decision log** — every divergence from the current shipped implementation, the current spec (`2026-05-11-pipeline-tab-design.md`), or the design system. One line each: what changed, why, what risk.
7. **Voice audit** — every label, chip, button, empty state listed with the proposed copy. We will run it through `ops-copywriter`; the designer's draft is the starting point.
8. **(Optional but appreciated):** a single HTML mock matching one of the states, importing `ops-design-system/project/colors_and_type.css`, so engineering can validate motion intent before the SwiftUI build.

---

## 20 · DEFINITION OF DONE FOR THE DESIGNER'S HANDOFF

The handoff is "done" when:

- [ ] Every state in §14 has a mock
- [ ] Every component has a token-referenced breakdown
- [ ] The decision log addresses each open question in §16
- [ ] No copy on any mock is generic SaaS-tone (no "Welcome!", "Awesome!", "Oops!")
- [ ] No accent color (`#6F94B0`) appears outside primary CTA fill or focus ring
- [ ] No card on any mock has a rounded corner + colored left-border treatment unless the decision log explicitly accepts that anti-pattern with a stated reason
- [ ] No mock contains an emoji
- [ ] All numbers in mocks are formatted in JetBrains Mono with tabular figures
- [ ] All state copy follows the `//` prefix / UPPERCASE-for-authority pattern
- [ ] Haptic + motion specs are present
- [ ] Accessibility audit complete

Engineering will accept the handoff, draft an implementation plan (`docs/superpowers/plans/2026-xx-xx-leads-tab-rebuild.md`), and execute it against the live preview scaffolding (already in place).

---

## 21 · REFERENCE LINKS

| Doc | Purpose |
|---|---|
| `ops-design-system/project/SKILL.md` | Skill orientation |
| `ops-design-system/project/README.md` | Agent brief |
| `ops-design-system/project/DESIGN.md` | Full visual system (single file) |
| `ops-design-system/project/mobile/MOBILE.md` | iOS overrides — **operative** for this work |
| `ops-design-system/project/colors_and_type.css` | Tokens (for HTML mocks) |
| `OPS/Styles/OPSStyle.swift` | iOS token implementation |
| `docs/superpowers/specs/2026-05-11-pipeline-tab-design.md` | Phase 1 spec (currently shipped) |
| `ops-software-bible/05_DESIGN_SYSTEM.md` | Broader brand context |
| `ops-software-bible/09_FINANCIAL_SYSTEM.md` § Pipeline | Authoritative business logic for stages, win prob, stale thresholds |

---

## 22 · NEXT STEP

Designer reads this brief end-to-end. Designer produces handoff per §19. Engineering picks up the handoff and drafts a plan against the live `#Preview` scaffolding in `OPS/Views/Leads/`. Spec drift documented in this file's "Drift" subsection (to be added) before any code change lands.

---

## 23 · RESOLVED (closed out 2026-05-19, post-implementation)

The designer's handoff (Direction A · TRIAGE) shipped across 7 commits on `feat/leads-tab-rebuild`. Decisions on every open question from § 16 are recorded inline in the implementation plan (`docs/superpowers/plans/2026-05-19-leads-tab-rebuild.md` § 2.1 + § 2.2). Restated here for the historical record:

| # | Open question (§ 16) | Resolution |
|---|---|---|
| 1 | Top-of-screen pattern | Single forecast hero + 3-cell sub-metric row + conditional WonConvert carousel above the chip filter. The 5-tile KPI carousel was dropped. |
| 2 | "Ball in your court" placement | Subsumed into the triage chip filter (chips include OVERDUE / DUE TODAY / REPLY DUE / NEW / WAITING). The standalone bar is gone. |
| 3 | Stage navigation pattern | Replaced with a chip filter for triage + a 6-row pipeline footer at the bottom for drill-by-stage. The 8-tab paged TabView is gone. |
| 4 | Stage identity on cards | Stage-color leading rail dropped (it violated DESIGN.md § 14). Stage identity now reads from a JBM Mono short-label caption in the row's right column (e.g. `QUOTED · 9D`). Earth-tone tag chips are used on the detail hero. |
| 5 | Closed leads placement | Per-stage drill from the pipeline footer can list won/lost. The CLOSED reveal in the stage strip is gone. |
| 6 | Hero card chrome | The card itself is gone (no carousel); the new hero is a single `.glassSurface()` L1 card. |
| 7 | Forecast breakdown | Drill-in deferred — `ForecastBreakdownSheet` deleted. May return as a future tap target on the hero. |
| 8 | Filter affordance | Single-select chip row in place. Multi-filter (source / tag / assignee / value) deferred to a future ticket. The filter icon in the meta row was deleted per Q4. |
| 9 | Empty-state framing | Per bucket: `00` hero + `// — NO <BUCKET MESSAGE>` mono caption. No illustrations. |
| 10 | Add-lead surface | Both kept: FAB MONEY · ADD LEAD remains canonical, with a parallel `+` icon in the triage meta row for one-tap parallel access. |

### Drift register closeout (§ 10 three drifts)

| Drift | Resolution |
|---|---|
| Hero carousel cards borderless vs spec | **Resolved.** The carousel itself was deleted. The single L1 hero card uses the canonical glass + hairline treatment. |
| `primaryAccent` leakage on chrome | **Resolved.** Accent now only appears on (1) the `MARK WON →` sticky button, (2) the WonConvertCarousel's `CONVERT → PROJECT` outline button, (3) the Add/Edit/Convert sheet save CTAs, and (4) `FilterChipRow`'s `waitingOnYou` dot color (semantic — "reply is on you"). All page-indicator dots, tab underlines, stage strips, and pipeline-footer chevrons are now `text-3` / `text-mute`. |
| Card with rounded corners + colored left-border accent | **Resolved.** No stage-color leading rail anywhere in the rebuild. Stage identity in lead cards is captioned, not chrome'd; on the detail view it's a StatusBadge-style tag chip with earth-tone mobile-contrast fills. |

### Phase summary

| Phase | Commit | What landed |
|---|---|---|
| P0 | `a4ebb57` | Mobile-contrast earth-tone variants + glass-surface modifiers (`.glassSurface()` / `.glassDense()` / `.nestedCard()`) |
| P1 | `daa7605` | `FilterChipRow` + `PanelSectionHeader` + `SubMetric` primitives |
| P2 | `1dddb7b` | Triage screen — `LeadsTabView` rewrite, `HeroWidget`, `WonConvertCarousel`, `PipelineFooter`, `LeadActionCard`, `Atmosphere`, VM triage extensions, deletion of all Phase-1 file orphans |
| P3 | `1d420b4` | `LeadDetailView` rebuild — hero, KPI strip, contact card, follow-ups card, activity timeline, stage history, sticky action bar |
| P5 | `38c9256` (iOS) + `6b062c0` (bible) | `LeadConversionService` + `convert_lead_to_project` Postgres RPC + bible doc |
| P4 | `cd4bbaf` | Five sheets (Add, Edit, Lost, Convert, Log) + shared `LeadFormView` + form primitives |
| P6 | (this commit) | VM dead-code removal, doc supersede, drift register closeout, `.derived-data/` to `.gitignore` |

Total: 8 commits on `feat/leads-tab-rebuild` + 1 on the bible repo. xcodebuild verified green at every phase.
