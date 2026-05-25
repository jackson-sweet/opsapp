# LEADS Tab Rebuild — Implementation Plan

> **Status:** REVISED 2026-05-19 — six decisions logged in §2.1, scope expanded for richer Convert flow + LOG sheet, one remaining scope question on task materialization (§2.2). Once that's answered, Phase 0 begins.
> **Source design:** `/Users/jacksonsweet/Downloads/design_handoff_leads_tab/` (Direction A · TRIAGE — chosen)
> **Companion docs:**
>   - `docs/superpowers/specs/2026-05-19-leads-tab-design-intent.md` (the brief)
>   - `docs/superpowers/specs/2026-05-19-leads-tab-context-pack.md` (engineering ground truth)
>   - `docs/superpowers/specs/2026-05-11-pipeline-tab-design.md` (Phase 1 spec — being replaced)
> **Author:** Jackson (via engineering session, 2026-05-19)
> **Estimated scope:** 6 phases, ~12 new SwiftUI files, ~5 new tokens, 1 new repo method, ~8 file deletions
> **Estimated cost (AI-assisted at OPS velocity):** 1 session

---

## 1 · SCOPE

### In scope (this plan)

- **Replace** `LeadsTabView`, `LeadsHeaderCarousel`, `BallInCourtBar`, `LeadStageStrip`, `LeadCard`, `LeadListPage`, `ForecastBreakdownSheet` with new triage-queue surface
- **Rebuild** `LeadDetailView` with KPI strip + contact card + follow-ups + activity timeline + stage history + sticky action bar
- **Add** four sheets: `AddLeadSheet`, `EditLeadSheet`, `LostReasonSheet`, `ConvertToProjectSheet`
- **Add** SwiftUI primitives: `.glassSurface()` / `.glassDense()` modifiers, mobile-contrast earth-tone color constants, `FilterChipRow` component
- **Add** `ProjectRepository.createStub(fromLead:actualValue:userId:)` method
- **Add** `PipelineViewModel` derivations: `triageBuckets`, `verbFor(lead:bucket:)`, helper computeds for the hero widget sub-metrics
- **Delete** legacy `OPS/Views/Books/Pipeline/*` (LeadCardView, StageStripView, PipelineSectionView, LeadActionSheet, AddLeadSheet, EditLeadSheet, LostReasonSheet, LeadDetailView, AddFollowUpSheet, LeadLogActivitySheet) — superseded
- **Update** the OPS Software Bible §09 (Pipeline) and §05 (Design System) to reflect the new surface
- **Update** the design system drift register (currently in the design intent doc) — close out the items this rebuild addresses

### Out of scope (deferred)

- `OpenLeadDetails` push notification + handler — context pack §7 gap, defer to a separate ticket
- Per-lead deep links — same
- Velocity tile and forecast-delta data pipelines — engineering will hide the delta line behind a feature flag until wired up (see §2 question 1)
- `LeadLogActivitySheet` (the `LOG` glyph on the lead card) — defer per §2 question 5
- Full stage board view (the destination of `OPEN STAGE BOARD →`) — see §2 question 2
- iPad / landscape layouts — never in scope
- Light theme — never in scope
- Multi-filter (by source / tag / assignee / value range) — see §2 question 4

---

## 2 · OPEN QUESTIONS — resolve before Phase 0

### 2.1 · DECISIONS LOGGED 2026-05-19

| Q | Topic | Chosen | Notes |
|---|---|---|---|
| 1 | Forecast-delta + velocity tile | **(a) Hide delta line entirely** | Defaults to recommended. No fake `↑ 12%`. Data pipeline is a separate ticket. |
| 2 | `OPEN STAGE BOARD →` destination | **(b) Tap a stage row → filtered single-stage list** | Defaults to recommended. Reuses `LeadActionCard` rendering. |
| 3 | `MARK WON →` sticky button + sheet exit semantics | **Modified.** Open `ConvertToProjectSheet`. **Every exit from the sheet marks the lead WON.** CANCEL / × / scrim-tap / drag-down → mark won, no project. CREATE PROJECT → mark won + create project. The intent to "win the lead" was already committed when MARK WON → was tapped. The sheet only asks "do you also want a project?" | Diverges from prototype (prototype had a true cancel). Confirmed by user. |
| 4 | Filter icon (top-right meta row) | **Delete entirely** | No icon, no disabled state. Chip row stays. Multi-filter is a future ticket. |
| 5 | `LOG` quick-glyph | **Keep + design + build `LeadLogActivitySheet`** | Scope added to this rebuild. Half-sheet, captures `ActivityType` + body + optional outcome + duration. See §8.7. |
| 6 | WON · CONVERT prompt | **Horizontal carousel** of all unconverted won leads | Was prototype's single card. Now: paged carousel between hero widget and chip filter. See §6.2 component breakdown. |

### 2.2 · ONE REMAINING SCOPE QUESTION

The backend research surfaced a single non-obvious decision. The user's instruction "if an estimate is attached, pre-fill with the tasks from that estimate" implies **LineItem → ProjectTask materialization**, which is a substantial feature that does not currently exist on iOS (web has it; iOS doesn't). Bible §10:282 documents it as "Task Generation modal opens" on `won`.

**Three scope options:**

- **(a) FULL — build LineItem → ProjectTask materialization now.** Convert sheet fetches estimates linked to the lead, filters their line items to `type == .labor`, materializes each as a `ProjectTask` (with `sourceLineItemId`, `sourceEstimateId`, and the line item's `taskTypeId` driving display). Estimate is also linked to the new project via `Estimate.projectId`. Site visit photos remain deferred to a separate ticket. **+0.5 session of scope. Best parity with the bible.** **(recommended)**
- **(b) PARTIAL — surface estimate context, defer materialization.** Convert sheet shows "N estimates with M line items found" message. Project is created without tasks. Operator goes to the Project to create tasks manually using the existing JobBoard task-creation UX. **Minimal scope. Honest about the gap.**
- **(c) HYBRID — checkbox materialization.** Convert sheet shows the estimate's line items as a checkbox list. User selects which to materialize. Default: all LABOR items checked. **+0.75 session. Best operator control but over-engineered for v1.**

**My recommendation: (a)** — matches the user's stated intent + matches the bible's documented behavior on `won`. Adds ~0.5 session of work; ships parity with what web users already get.

---

### Q1 · Forecast-delta and velocity tile

The hero widget's top-right shows `↑ 12% VS PRIOR` in olive. The data isn't wired — `weightedForecastDelta` and `avgVelocityDays` are nil today. **Decision needed:**

- **(a)** Hide the delta line entirely until the data pipeline is built — show `WEIGHTED FORECAST · 30D` alone on the eyebrow line. **(recommended — ships clean)**
- **(b)** Show a placeholder `—` chip in the delta slot until data lands. **(visible empty slot, but honest)**
- **(c)** Build the data pipeline now as part of this scope. **(expands scope — would add ~half a session)**

### Q2 · `OPEN STAGE BOARD →` link destination

The pipeline footer at the bottom of the triage screen has a `OPEN STAGE BOARD →` link in the top-right. The destination doesn't exist today. **Decision needed:**

- **(a)** Build it as a new full-screen `StageBoardView` showing each of the 6 active stages as a column with their leads. **(expands scope by ~1/3 session — biggest add)**
- **(b)** Tapping a stage row in the footer navigates to a filtered list (single stage, list of leads). Reuses existing `LeadListPage`-style layout. **(small add — recommended)**
- **(c)** Defer — render the link disabled (non-interactive) and flag it as a P2 work item. **(simplest — but the link will look broken)**

### Q3 · Sticky action bar's "MARK WON →" button

In `LeadDetailView`, the sticky bottom bar has `× LOST` / `EDIT` / `MARK WON →`. The MARK WON button opens `ConvertToProjectSheet`. **There is no path to "just mark won" without going through the convert sheet.** **Decision needed:**

- **(a)** Keep as designed — every WON commit goes through the convert sheet. The convert sheet captures actual value + notes and creates a project stub. The "skip project creation" affordance does not exist. **(matches the design — recommended)**
- **(b)** Add a "MARK WON · NO PROJECT" secondary action (long-press, action sheet, or chip inside the convert sheet) that wins the lead without creating a project. **(diverges from design — opens drift)**
- **(c)** Split the action — `MARK WON →` wins immediately (no sheet); a separate `CONVERT → PROJECT` button or banner triggers conversion. **(diverges from design)**

### Q4 · Filter icon (top-right meta row)

The meta row has search / filter / `+` icons. The search icon → universal search (existing JobBoard sheet). The `+` icon → AddLeadSheet. **The filter icon's destination is unspecified.** **Decision needed:**

- **(a)** Reveal the chip filter row (currently always shown below the queue header). Toggle it open/closed. **(minor — reduces UI density on initial load)**
- **(b)** Open a more elaborate filter sheet (source / tag / assignee / value range / priority). **(net-new component — adds ~1/4 session of scope)**
- **(c)** Defer — disable the filter icon for v1. **(simplest)**

### Q5 · `LOG` quick-glyph on the lead card

The third glyph on the card row (left of MORE, ADVANCE) is `LOG` (note icon). Designer notes: "future LeadLogActivitySheet — confirm scope before adding." **Decision needed:**

- **(a)** Build `LeadLogActivitySheet` now (form-style sheet, single-select activity type + free-text body + optional outcome + duration). Uses `OpportunityRepository.logActivity(dto:)`. **(adds ~1/4 session)**
- **(b)** Defer — render the LOG glyph as visually present but non-interactive (greyed). **(visible but inert — feels incomplete)**
- **(c)** Drop the LOG glyph from v1. Render only MORE and ADVANCE in the card row. **(cleanest if deferring)**

### Q6 · WON · CONVERT prompt — single or stacked?

The triage screen surfaces a `WonConvertCard` between the hero widget and the chip filter when there's a won lead without a `projectId`. The prototype shows just the first (`buckets.won[0]`). **Decision needed:**

- **(a)** Single card — show only the most-recently-won unconverted lead. The operator dismisses it (LATER) or converts. **(matches prototype — recommended)**
- **(b)** Stack — show all unconverted won leads as a vertical list of WonConvertCards. **(could be tall if multiple wins land between sessions)**
- **(c)** Compact strip — single card with `N WON · CONVERT →` count, taps to a sheet listing all unconverted wins. **(more complex but tidier when there's a backlog)**

---

## 3 · PRE-CODING SETUP

Run before Phase 0:

1. **Decisions from §2 captured** in this doc's "Decision log" section (added inline when each is made).
2. **`git status --short` clean** — no parallel-session WIP on `OPS/Views/Leads/`, `OPS/Styles/`, `OPS/ViewModels/PipelineViewModel.swift`, or `OPS/DataModels/Supabase/Opportunity.swift`.
3. **Branch decision** — work directly on `main` (per CLAUDE.md, atomic commits as work lands). No feature branch needed unless the user wants one for parallel review.
4. **Holding commits** from the prior session (borderless cards, preview scaffolding, design-intent + context-pack docs) — decide whether to ship those first or fold them into Phase 6 cleanup.

---

## 4 · PHASE 0 — Tokens, glass modifiers, mobile-contrast earth-tone uplift

> Everything below depends on Phase 0 landing first.

### 4.1 New color constants in `OPSStyle.Colors`

Add mobile-contrast variants per `mobile/MOBILE.md` §1 (outdoor-glare uplift). All three earth tones get a `-fillM` / `-lineM` / `-textM` triplet.

```swift
// OPS/Styles/OPSStyle.swift

// Mobile outdoor-glare uplift per MOBILE.md §1 — earth-tones at higher fill,
// border, and text contrast than their desktop variants. Use these in any
// mobile UI; desktop continues to use the standard variants.
static let oliveFillM = Color("StatusSuccess").opacity(0.20)
static let oliveLineM = Color("StatusSuccess").opacity(0.55)
static let oliveTextM = Color(red: 0.71, green: 0.79, blue: 0.63)   // #B5C9A0 ~25% brighter than #9DB582
static let tanFillM   = Color("AccentSecondary").opacity(0.20)
static let tanLineM   = Color("AccentSecondary").opacity(0.55)
static let tanTextM   = Color(red: 0.84, green: 0.74, blue: 0.51)   // #D6BC82
static let roseFillM  = Color("Rose").opacity(0.20)
static let roseLineM  = Color("Rose").opacity(0.55)
static let roseTextM  = Color(red: 0.79, green: 0.61, blue: 0.64)   // #C99CA3
```

**Verification:** these hex values are taken verbatim from `prototypes/app/tokens.css` lines 63–71. Confirmed in the designer's README §6 ("Mobile contrast lift").

### 4.2 Glass surface SwiftUI modifiers

The unified `.glassSurface()` / `.glassDense()` modifiers do not exist (context pack §7 gap). Build them now.

**File:** `OPS/Styles/Components/GlassSurface.swift` (NEW)

```swift
import SwiftUI

/// L1 section card — glass + hairline + top-edge gradient. Per MOBILE.md §3.
struct GlassSurface: ViewModifier {
    var cornerRadius: CGFloat = OPSStyle.Layout.panelRadius
    func body(content: Content) -> some View {
        content
            .background(.ultraThinMaterial.opacity(0.58), in: RoundedRectangle(cornerRadius: cornerRadius))
            .background(Color(red: 18/255, green: 18/255, blue: 20/255).opacity(0.58), in: RoundedRectangle(cornerRadius: cornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(Color.white.opacity(0.09), lineWidth: 1)
            )
            .overlay(
                LinearGradient(
                    colors: [Color.white.opacity(0.04), .clear],
                    startPoint: .top, endPoint: .bottom
                )
                .frame(maxHeight: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
                .allowsHitTesting(false)
            )
    }
}

/// L1 dense surface — for sheets, popovers, dropdowns (higher opacity).
struct GlassDense: ViewModifier { /* same shape, 0.78 opacity, no top gradient */ }

/// L2 nested card — no blur, 0.04 white fill + 0.08 hairline. 6pt radius.
struct NestedCard: ViewModifier {
    var cornerRadius: CGFloat = 6
    func body(content: Content) -> some View {
        content
            .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: cornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
            )
    }
}

extension View {
    func glassSurface(cornerRadius: CGFloat = OPSStyle.Layout.panelRadius) -> some View {
        modifier(GlassSurface(cornerRadius: cornerRadius))
    }
    func glassDense(cornerRadius: CGFloat = OPSStyle.Layout.modalRadius) -> some View {
        modifier(GlassDense(cornerRadius: cornerRadius))
    }
    func nestedCard(cornerRadius: CGFloat = 6) -> some View {
        modifier(NestedCard(cornerRadius: cornerRadius))
    }
}
```

**Migration:** existing call sites of `OPSStyle.Colors.cardBackground` should be reviewed but **not touched in this rebuild** — they're out of scope. The Books tab `HeroCarousel`, `JobBoardView` cards, etc. continue to use flat `cardBackground` until they're separately rebuilt. New LEADS code uses `.glassSurface()` / `.nestedCard()` from day one.

### 4.3 New layout constants

Add to `OPSStyle.Layout`:

```swift
static let cardRadius: CGFloat = 6   // L2 nested cards — 6pt (currently no exact match)
```

### 4.4 Drop deprecated tokens from new code (not removed yet)

New LEADS files do **not** reference:
- `cardBackground`, `cardBackgroundDark`, `darkBackground` (legacy flat surfaces)
- `Animation.spring`, `Animation.springFast` (banned outside drag-to-reorder)
- `Layout.Shadow.{card,elevated,floating}` (banned on dark)

These remain in `OPSStyle.swift` for legacy callers but are not used by anything written in this rebuild.

### Phase 0 deliverable

- 1 new file: `GlassSurface.swift` (~80 LoC)
- 9 new color constants in `OPSStyle.Colors`
- 1 new layout constant
- 1 commit: `feat(style): mobile-contrast earth-tone variants + glass surface modifiers`

---

## 5 · PHASE 1 — Shared primitives

### 5.1 `FilterChipRow` component

**File:** `OPS/Styles/Components/FilterChipRow.swift` (NEW)

Single-select horizontal scroll of urgency-bucket chips. Reusable for any list-filter surface.

```swift
struct FilterChip: Identifiable, Equatable {
    let id: String           // bucket key — "overdue", "dueToday", etc.
    let label: String        // "OVERDUE"
    let dotColor: Color      // semantic dot, never accent unless `id == "waitingOnYou"`
    let count: Int           // shown after the label
    var disabled: Bool { count == 0 }
}

struct FilterChipRow: View {
    @Binding var selected: String
    let chips: [FilterChip]
    var onSelect: ((String) -> Void)? = nil
    // Renders: 8/12/8 padding chip-by-chip, 5pt dot, 10pt mono caps label,
    // 4pt chip radius, inactive 0.04 bg / 0.10 border, active 0.10 bg / 0.20 border,
    // disabled 35% opacity. Light haptic on select.
}
```

**Verification source:** `prototypes/app/direction-triage.jsx` lines 178–246 (`BucketChips`).

### 5.2 `SubMetric` view

**File:** `OPS/Views/Leads/Components/SubMetric.swift` (NEW)

The three sub-metric cells inside the hero widget. Takes a label, value, hint, and tone. **Tone tints the label only — never the value.**

### 5.3 Reusable section header

**File:** `OPS/Styles/Components/PanelSectionHeader.swift` (NEW)

`// LABEL` mono left, optional hint mono right, optional 4pt dot before the label. Used across LEADS surfaces (`// QUEUE`, `// BY STAGE`, `// RECENT ACTIVITY`, `// STAGE HISTORY`, `// NEXT FOLLOW-UP`, `// FROM WON LEAD`, `// DANGER ZONE`).

### Phase 1 deliverable

- 3 new files (~250 LoC total)
- 1 commit: `feat(style): filter-chip-row + sub-metric + panel-section-header primitives`

---

## 6 · PHASE 2 — Triage screen (replace LeadsTabView)

### 6.1 PipelineViewModel additions

**File:** `OPS/ViewModels/PipelineViewModel.swift` (EXTEND)

Add the triage bucketize logic. Mirrors `prototypes/app/shared.jsx::bucketize()`.

```swift
struct TriageBuckets: Equatable {
    var overdue: [Opportunity]
    var dueToday: [Opportunity]
    var waitingOnYou: [Opportunity]
    var fresh: [Opportunity]
    var waitingOnThem: [Opportunity]
    var won: [Opportunity]              // for the convert prompt
    // ALL = overdue + dueToday + waitingOnYou + fresh + waitingOnThem
    var all: [Opportunity] { overdue + dueToday + waitingOnYou + fresh + waitingOnThem }
}

enum TriageBucket: String, CaseIterable {
    case all, overdue, dueToday, waitingOnYou, fresh, waitingOnThem
    var label: String { ... }           // "ALL", "OVERDUE", "DUE TODAY", "REPLY DUE", "NEW", "WAITING"
    var dotColor: Color { ... }         // text, rose, tan, opsAccent, text2, textMute (in order above)
}

var triageBuckets: TriageBuckets {
    // ... bucketize logic ...
    // Uses `lastMessageDirection == "in"` to detect "waiting on you"
    // (per context pack §6 — denormalized field, no Activity fetch needed)
}

func verbFor(_ lead: Opportunity, bucket: TriageBucket) -> String {
    // Per direction-triage.jsx lines 478–494
    // Returns: CHASE QUOTE / CLOSE / FOLLOW UP / CONFIRM / CALL / QUALIFY / REPLY / TRIAGE / CHECK IN
    // For .all bucket, computes effective bucket per-lead via bucketOf
}

func bucketOf(_ lead: Opportunity) -> TriageBucket {
    // overdue → dueToday → fresh (.newLead) → waitingOnYou (.lastMessageDirection == "in")
    // → waitingOnThem (default)
}

func toneFor(_ bucket: TriageBucket, lead: Opportunity?) -> UrgencyTone {
    // rose / tan / steel / neutral
}

enum UrgencyTone { case rose, tan, steel, neutral
    var labelColor: Color { ... }       // returns rose-text-M / tan-text-M / opsAccent / text-2
}

/// Default bucket for app open: highest-urgency-with-leads, falling back to overdue.
var defaultBucket: TriageBucket {
    let order: [TriageBucket] = [.overdue, .dueToday, .waitingOnYou, .fresh, .waitingOnThem]
    return order.first { !(triageBuckets[keyPath: keyPath(for: $0)].isEmpty) } ?? .overdue
}

/// Hero widget computeds
var openLeadCount: Int { allOpportunities.filter { !$0.stage.isTerminal && !$0.isDeleted && !$0.isArchived }.count }
var waitingCount: Int { triageBuckets.waitingOnYou.count + triageBuckets.waitingOnThem.count }
```

### 6.2 New `LeadsTabView`

**File:** `OPS/Views/Leads/LeadsTabView.swift` (REPLACE existing content)

Structure (top-to-bottom, all inside one `NavigationStack` + outer `ZStack` with `Atmosphere`):

```
ZStack {
  Atmosphere(tone: .rose)              // radial glow per MOBILE.md §3
  ScrollView {
    VStack {
      TriageMetaRow(...)               // date + search/filter/+ icons
      TitleRow(...)                    // "LEADS" + "// OPERATOR :: JACKSON"
      HeroWidget(...)                  // .glassSurface() — forecast hero + 3 SubMetric
      WonConvertCard(...)              // conditional
      PanelSectionHeader("QUEUE", "SORTED — STALE FIRST")
      FilterChipRow(selected: $bucket, chips: chips)
      ForEach(currentLeads) { LeadActionCard(...) }   // each .glassSurface() card
      PipelineFooter(...)              // .glassSurface() panel with 6 stage rows
    }
  }
}
.navigationDestination(item: $detailLead) { LeadDetailView(...) }
.sheet(item: $activeSheet) { sheet in ... }   // routes to Add / Edit / Lost / Convert
```

**Component breakdown:**

| New SwiftUI struct | File | Purpose |
|---|---|---|
| `TriageMetaRow` | `LeadsTabView.swift` (private) | Date left, action icons right |
| `LeadsTitleRow` | `LeadsTabView.swift` (private) | Page title + operator id |
| `HeroWidget` | `OPS/Views/Leads/HeroWidget.swift` (NEW) | Forecast + 3 SubMetric — `.glassSurface()` card |
| `LeadActionCard` | `OPS/Views/Leads/Components/LeadActionCard.swift` (NEW) | Per-lead card (verb / name / value / title / due chip / quick glyphs) — `.glassSurface()` |
| `QuickGlyph` | `LeadActionCard.swift` (private) | 34×34pt button, optional emphasis |
| `WonConvertCard` | `OPS/Views/Leads/WonConvertCard.swift` (NEW) | Conditional convert prompt |
| `PipelineFooter` | `OPS/Views/Leads/PipelineFooter.swift` (NEW) | 6-stage drill-down panel |
| `Atmosphere` | `OPS/Styles/Components/Atmosphere.swift` (NEW) | Radial glow background; max one per screen |

### 6.3 Token mapping

| Prototype CSS | Swift |
|---|---|
| `.t-page` (Cake Mono Light 30) | `OPSStyle.Typography.display` |
| `.t-display` (Cake Mono Light 22) | `OPSStyle.Typography.pageTitle` |
| `.t-section` (Cake Mono Light 16) | `OPSStyle.Typography.section` (will be 18; designer specced 16 — see drift) |
| `.t-meta` (mono 10, text-3) | `OPSStyle.Typography.metadata` (11pt — close) |
| `.t-data` (mono 13) | `OPSStyle.Typography.dataValue` |
| `.t-data-lg` (mono 20) | `OPSStyle.Typography.dataValueLg` |
| `.t-name` (Mohave 500 15) | `OPSStyle.Typography.bodyBold` at 15 — extend `Fonts.swift` with `nameMobile` if needed (15pt vs default body's 16pt) |
| `.t-body-2` (Mohave 14, text-2) | `OPSStyle.Typography.smallBody` |
| Mohave Light 38 (hero) | custom inline — `Font.custom("Mohave-Light", size: 38)`. **Or** add `Typography.heroMobile = Font.custom("Mohave-Light", size: 38)` |
| Mohave Light 32 (empty zero) | `Font.custom("Mohave-Light", size: 32)` |
| Mohave Light 22 (SubMetric value) | `Font.custom("Mohave-Light", size: 22)` — or `Typography.subValueMobile` |
| Mohave Light 18 (KvCell value) | `Font.custom("Mohave-Light", size: 18)` — or `Typography.kvValueMobile` |
| Mono 9 / 9.5 / 10 / 10.5 / 11 (various labels) | mostly `Typography.metadata` (11pt) or custom-size variants |

**Recommendation:** add a small `Typography.Mobile` enum with `hero`, `heroSmall`, `subValue`, `kvValue`, `bodyName` to keep call sites legible. The designer's prototype uses ~7 distinct Mohave sizes; reflecting those into named tokens prevents `Font.custom(...)` from leaking into view files.

### 6.4 Sticky chip filter — defer

The designer noted: "Sticky-feel chip filter row. Scrolls with content; could be made position:sticky if engineering wants the chip row to pin under the hero on scroll. Keeping inline for now — simpler iOS impl."

I'll **keep inline for v1** matching the prototype. Sticky pinning would require a `GeometryReader` + offset-tracking pattern that's worth its own measurement. Out of scope.

### Phase 2 deliverable

- 1 file rewritten (`LeadsTabView.swift`)
- 5 new files (Atmosphere, HeroWidget, WonConvertCard, PipelineFooter, LeadActionCard)
- 1 VM extension (~120 LoC of bucketize + helpers)
- 1 commit: `feat(leads): triage queue + hero widget + per-lead action card (replaces phase 1)`

---

## 7 · PHASE 3 — Lead detail view

### 7.1 New `LeadDetailView`

**File:** `OPS/Views/Leads/LeadDetailView.swift` (NEW — replaces legacy `OPS/Views/Books/Pipeline/LeadDetailView.swift`)

Structure:

```
ZStack {
  Atmosphere(tone: deriveFromStage)    // olive / rose / steel
  VStack {
    DetailNavBar(onBack: ...)          // back chevron + LEADS label, archive + ··· right
    ScrollView {
      DetailHero(...)                  // id, days-in-stage, stage tag, name, title, KPI strip
      ContactCard(...)                 // avatar + name + 4-up CTA (CALL TEXT EMAIL MAP)
      WonNotConvertedCard(...)         // conditional — when stage == .won && projectId == nil
      FollowUpsCard(...)               // next follow-up — auto-derived from VM
      ActivityTimeline(...)            // last 4-5 activities — from LeadDetailViewModel.activities
      StageTimeline(...)               // stage history — from LeadDetailViewModel.stageTransitions
    }
    .padding(.bottom, 200)              // clear space under the sticky action bar
  }
  StickyActionBar(...)                  // bottom: × LOST / EDIT / MARK WON →
}
```

**Component breakdown:**

| New SwiftUI struct | File |
|---|---|
| `DetailNavBar` | `LeadDetailView.swift` (private) |
| `DetailHero` | `OPS/Views/Leads/Components/DetailHero.swift` (NEW) |
| `KvCell` | `DetailHero.swift` (private) |
| `ContactCard` | `OPS/Views/Leads/Components/ContactCard.swift` (NEW) |
| `WonNotConvertedCard` | inline in `LeadDetailView.swift` |
| `FollowUpsCard` | `OPS/Views/Leads/Components/FollowUpsCard.swift` (NEW) |
| `ActivityTimeline` | `OPS/Views/Leads/Components/ActivityTimeline.swift` (NEW) |
| `StageTimeline` | `OPS/Views/Leads/Components/StageTimeline.swift` (NEW) |
| `StickyActionBar` | `OPS/Views/Leads/Components/StickyActionBar.swift` (NEW) |

### 7.2 Data sources

| UI block | Source |
|---|---|
| Hero (id, daysInStage, stage tag, name, title) | `Opportunity` (passed in) |
| KPI strip — value | `Opportunity.estimatedValue` |
| KPI strip — weighted | `Opportunity.weightedValue` |
| KPI strip — source | `Opportunity.source` |
| Contact card | `Opportunity.contactName / phone / address` |
| Follow-ups card | `LeadDetailViewModel.followUps.first { $0.status != .completed }` sorted by `dueAt` asc |
| Activity timeline | `LeadDetailViewModel.activities.sorted { $0.createdAt > $1.createdAt }.prefix(5)` |
| Stage timeline | `LeadDetailViewModel.stageTransitions.sorted { $0.transitionedAt < $1.transitionedAt }` |

### 7.3 Sticky action bar — behavior

| Button | Action |
|---|---|
| `× LOST` (rose-soft 52×48pt) | Opens `LostReasonSheet(opportunity: lead)` |
| `EDIT` (line-default flex:1 48pt) | Opens `EditLeadSheet(opportunity: lead)` |
| `MARK WON →` (accent flex:1.5 48pt) | Opens `ConvertToProjectSheet(opportunity: lead)` per Q3 decision |

Bar is hidden when `lead.stage.isTerminal` (already won or lost).

### Phase 3 deliverable

- 1 new file (`LeadDetailView.swift`) replacing legacy
- 8 new component files
- 1 commit: `feat(leads): lead detail view rebuild — hero, KPI, contact, timeline, sticky actions`

---

## 8 · PHASE 4 — Sheets

### 8.1 Sheet shell

SwiftUI's native `.sheet(item:)` handles dismiss + scrim. For half-sheets, use `.presentationDetents([.medium])` + `.presentationDragIndicator(.visible)`. For full sheets, the default behavior is fine (drag-to-dismiss). The custom JS sheet shell in `prototypes/app/sheets.jsx` is React-only — we use SwiftUI native.

| Sheet | Detent |
|---|---|
| `AddLeadSheet` | `.large` (full) — `.presentationDragIndicator(.hidden)` + custom close button top-left |
| `EditLeadSheet` | `.large` (full) — same |
| `LostReasonSheet` | `.medium` (half) — `.presentationDragIndicator(.visible)` |
| `ConvertToProjectSheet` | `.large` (full) — same as Add |

### 8.2 `LeadFormView` (shared)

**File:** `OPS/Views/Leads/Sheets/LeadFormView.swift` (NEW)

Shared form view consumed by both Add and Edit sheets. Fields (matching `prototypes/app/sheets.jsx` lines 240–331):

1. CONTACT NAME (text, required)
2. PHONE + EMAIL (side-by-side, text/tel/email, optional)
3. SITE ADDRESS (text, optional)
4. JOB DESCRIPTION (text, optional, maps to `Opportunity.title`)
5. ESTIMATED VALUE (text with `$` leading, optional)
6. SOURCE (chip group, single-select: MANUAL / WEB FORM / REFERRAL / INBOUND CALL / EMAIL)
7. STAGE (chip group, single-select: 6 open stages, default `newLead`, hidden in EditLeadSheet?)
8. PRIORITY (chip group: LOW / MEDIUM / HIGH, default MEDIUM)
9. NOTES (textarea, 3 rows, optional)
10. Danger zone (Edit only) — ARCHIVE + DELETE buttons

**Note for Edit:** the stage chip group is shown so the operator can manually correct stage. This is intentional — leads sometimes get mis-categorized.

### 8.3 `AddLeadSheet`

**File:** `OPS/Views/Leads/Sheets/AddLeadSheet.swift` (NEW — replaces legacy `OPS/Views/Books/Pipeline/AddLeadSheet.swift`)

```swift
struct AddLeadSheet: View {
    @EnvironmentObject var dataController: DataController
    @StateObject private var vm = AddLeadSheetVM()
    var onSaved: (Opportunity) -> Void
    // ...
}
```

Title: `// NEW LEAD`. Footer: `CANCEL` ghost (flex:1) + `SAVE LEAD` accent (flex:2, check icon).

**Save logic:**
```swift
func save() async throws -> Opportunity {
    let dto = CreateOpportunityDTO(
        companyId: dataController.currentUser?.companyId ?? "",
        title: form.title.isEmpty ? nil : form.title,
        contactName: form.name,
        contactEmail: form.email.isEmpty ? nil : form.email,
        contactPhone: form.phone.isEmpty ? nil : form.phone,
        description: nil,
        address: form.address.isEmpty ? nil : form.address,
        estimatedValue: Double(form.value),
        source: form.source.rawValue,
        priority: form.priority.rawValue,
        assignedTo: dataController.currentUser?.id,
        expectedCloseDate: nil,
        quoteDeliveryMethod: nil,
        clientId: nil
    )
    let dto2 = try await repository.create(dto)
    let lead = dto2.toModel()
    // Insert into SwiftData context, post LeadCreatedSuccess notification (existing pattern)
    return lead
}
```

### 8.4 `EditLeadSheet`

**File:** `OPS/Views/Leads/Sheets/EditLeadSheet.swift` (NEW)

Title: `// EDIT · {lead.id_short}`. Footer: `CANCEL` + `SAVE`. Body: prefilled `LeadFormView` + danger-zone block.

**Save logic:** `repository.update(lead.id, fields: UpdateOpportunityDTO(...))`. Archive/Delete call `repository.archive` / `repository.softDelete`.

### 8.5 `LostReasonSheet`

**File:** `OPS/Views/Leads/Sheets/LostReasonSheet.swift` (NEW — replaces legacy)

Half-sheet. Body: read-only summary L2 card + REASON chip group (mapped to `LossReason` enum) + NOTES textarea. Footer: `CANCEL` + `CONFIRM LOST` rose-destructive.

**Save logic:** `repository.markLost(id, reason: selected, notes: notes ?: nil, userId: ...)`. Optimistic update — write to local SwiftData, dismiss, queue sync.

### 8.6 `ConvertToProjectSheet` — RICH VERSION (revised 2026-05-19)

**File:** `OPS/Views/Leads/Sheets/ConvertToProjectSheet.swift` (NEW)

Full sheet. Drives a pre-flight check on open and pre-fills heavily from existing data.

**On open (before render):**

1. **Duplicate check.** Query SwiftData for `Project` where `opportunityId == lead.id`. If found → render the sheet in **"PROJECT ALREADY EXISTS"** mode: olive-warning banner with the project's title + start date + `OPEN PROJECT →` link. Footer becomes `CANCEL` (still marks won, no new project) + `OPEN PROJECT →`. No CREATE button.
2. **Client-has-projects check.** If `lead.clientId != nil`, query for projects where `clientId == lead.clientId` AND `id != duplicate.id`. If count > 0 → tan-warning banner at the top: `// THIS CLIENT HAS N OTHER PROJECTS · REVIEW BEFORE CREATING` with a chip-list of project titles + status + date. Tap a chip → push that project's detail. Operator can ignore and still proceed.
3. **Estimate lookup.** Fetch via `EstimateRepository` all estimates where `opportunityId == lead.id`. Surface count + line-item count + most-recent estimate's value as the pre-fill for ACTUAL VALUE (falls back to `lead.estimatedValue` when no estimates). If estimates exist, render a `// ATTACHED ESTIMATES · N` L2 row listing each estimate by number / status / total.

**Body (default render — no duplicate found):**

| Block | Source |
|---|---|
| L1 summary card — FROM WON LEAD | `lead.contactName`, `lead.id`, `lead.phone`, `lead.address`. Olive-tinted eyebrow. |
| Client-has-other-projects banner (conditional) | Per step 2 above. |
| Attached estimates section (conditional) | Per step 3 above. |
| TITLE input | Pre-filled `lead.title ?? lead.contactName`. Required. |
| ADDRESS input | Pre-filled `lead.address`. Optional. |
| ACTUAL VALUE input | Pre-filled from most-recent estimate total OR `lead.estimatedValue`. Leading `$`. |
| CLOSING NOTES textarea | 3 rows. |
| **TASKS section** (conditional on Q-2.2 = (a)) | If estimates have LABOR line items: list each as a row with `Mohave 500` task title + mono task-type label + duration. Default-all-included; no per-task toggle in v1 (per scope (a)). Sub-line: `N TASKS WILL BE CREATED FROM N ESTIMATES`. |
| Provenance footer | `// Marks the lead WON and creates a Project (status: ACCEPTED) linked back to this lead. Finish project setup from the PROJECTS tab.` |

**Footer:** `CANCEL` (flex: 1, secondary) + `CREATE PROJECT →` (flex: 2, accent primary).

**Save semantics:**

The convert sheet has two exit-with-side-effect paths and they both mark the lead won:

| Exit | Action |
|---|---|
| Tap `× ` close button (top-left) | `markWon(lead.id, actualValue: form.value, projectId: nil, userId: me)`. No project created. Lead → WON. Dismiss. |
| Tap `CANCEL` button (footer) | Same as `× `. Mark won, no project. Dismiss. |
| Drag-down dismiss | Same as `× `. Mark won, no project. Dismiss. |
| Scrim tap | Same as `× `. Mark won, no project. Dismiss. |
| Tap `CREATE PROJECT →` | `LeadConversionService.convertLeadToProject(lead: lead, form: form)` — see Phase 5. Mark won + create project + materialize tasks. Dismiss. Toast `// LEAD WON · PROJECT P-XXXX CREATED`. |
| Tap `OPEN PROJECT →` (duplicate mode) | `markWon` still fires (in case the existing project pre-dates a stage-tracking gap). Then navigate to that project. Dismiss. |

**Open question for ops-copywriter pass:** the toast copy. Draft above is a starting point.

### 8.7 `LeadLogActivitySheet` — NEW (added per Q5 decision)

**File:** `OPS/Views/Leads/Sheets/LeadLogActivitySheet.swift` (NEW)

Half-sheet. Triggered by tapping the `LOG` quick-glyph on a `LeadActionCard`, or by a `// LOG ACTIVITY` button on `LeadDetailView`. Captures an Activity record against the lead.

**Header:** Drag handle (36×5pt at 0.30 white). `// LOG ACTIVITY` mono title left-aligned below.

**Body:**

| Field | Type | Required | Notes |
|---|---|---|---|
| TYPE | chip group, single-select | yes | Options: `CALL` / `EMAIL` / `SMS` / `VISIT` / `NOTE` / `MEETING`. Maps to `ActivityType` enum. |
| DIRECTION | chip group, single-select | conditional | `INBOUND` / `OUTBOUND`. Hidden when TYPE is `NOTE` or `VISIT`. Maps to `Activity.direction`. |
| SUBJECT | text | optional | Pre-filled with the verb of the chosen type (`Call with {lead.name}` etc.). Editable. |
| BODY | textarea | optional | 4 rows. Free text. |
| OUTCOME | chip group, single-select | optional | `LEFT VOICEMAIL` / `SPOKE` / `NO ANSWER` / `REPLIED` / `BOOKED VISIT` / `OTHER`. Hidden when TYPE is `NOTE`. Maps to `Activity.outcome`. |
| DURATION | numeric input + minutes label | optional | Hidden when TYPE is `NOTE` or `EMAIL`. Maps to `Activity.durationMinutes`. |

**Footer:** `CANCEL` ghost (flex: 1) + `LOG` accent primary (flex: 2, check icon).

**Save semantics:** `LeadDetailViewModel.logActivity(...)` — already exists at line 61 of that VM, just needs to be wired to the new sheet. Optimistic — write to local SwiftData, dismiss, queue Supabase sync. On success, the lead's `lastActivityAt` updates locally → triage bucket reclassifies if the lead was overdue/waiting/etc.

**Stage auto-advance:** Per bible §10:205, a first Activity logged on a `newLead` auto-advances it to `qualifying`. The web does this server-side via a trigger; iOS depends on the same trigger to fire. **Verify with a manual test before claiming the rebuild ships clean.** Document if absent.

### Phase 4 deliverable

- 1 shared form view (`LeadFormView.swift`)
- 4 new sheet files
- 4 legacy sheet files deleted (`OPS/Views/Books/Pipeline/{AddLeadSheet,EditLeadSheet,LostReasonSheet,LeadActionSheet}.swift`)
- 1 commit: `feat(leads): four sheets — add, edit, lost-reason, convert-to-project`

---

## 9 · PHASE 5 — Project conversion pipeline (revised 2026-05-19 with backend research)

### 9.1 Backend grounding (verified)

| Fact | Source |
|---|---|
| `SupabaseProjectDTO` has `opportunityId: String?` | `OPS/Network/Supabase/DTOs/CoreEntityDTOs.swift:214` |
| `Project` SwiftData model has `opportunityId: String?` | `OPS/DataModels/Project.swift:28` |
| `Project.status` enum default for won-lead-converted projects is `.accepted` | Bible `10_JOB_LIFECYCLE.md:288` ("`project.status = Accepted`") + user confirmation |
| `Estimate.opportunityId` links estimates back to the lead | `OPS/DataModels/Supabase/Estimate.swift:19` |
| `Estimate.projectId` links the estimate forward to the project once promoted | `Estimate.swift:18` |
| `EstimateLineItem.type` (`.labor / .material / .other`) — only LABOR items materialize as tasks | `EstimateLineItem.swift:18` |
| `EstimateLineItem.taskTypeId` drives task display (name, color, default duration) | `EstimateLineItem.swift:27` |
| `ProjectTask.sourceLineItemId` + `sourceEstimateId` are the back-links from a generated task to its source | `ProjectTask.swift:128–129` |
| Site visit photo auto-attach on won is documented in the bible but **not built on iOS** | `10_JOB_LIFECYCLE.md:289` — flagged as gap |
| Task generation modal is documented in the bible but **not built on iOS** | `10_JOB_LIFECYCLE.md:290` — flagged as gap |
| `OpportunityRepository.markWon(id, actualValue, projectId, userId)` exists | `OpportunityRepository.swift:133` |
| `ProjectRepository.create(SupabaseProjectDTO)` exists | `ProjectRepository.swift:107` |

### 9.2 New service — `LeadConversionService`

**File:** `OPS/Services/LeadConversionService.swift` (NEW)

Single-purpose service that orchestrates the multi-step conversion atomically (with explicit rollback semantics).

```swift
@MainActor
final class LeadConversionService {
    private let opportunityRepo: OpportunityRepository
    private let projectRepo: ProjectRepository
    private let estimateRepo: EstimateRepository
    // ...

    /// Pre-flight check called when ConvertToProjectSheet opens.
    /// Returns the existing project if `Project.opportunityId == lead.id`.
    func existingProject(for lead: Opportunity) -> Project? { ... }

    /// Returns count + summary of OTHER projects under the same client (excluding the lead's own).
    func clientProjectsSummary(for lead: Opportunity) -> [Project] { ... }

    /// Returns the estimates linked to this lead (from local SwiftData; sync-first if stale).
    func estimates(for lead: Opportunity) async throws -> [Estimate] { ... }

    /// THE CONVERT TRANSACTION.
    /// 1. Insert Project row (status = .accepted, opportunityId = lead.id, clientId = lead.clientId,
    ///    address = lead.address, title = form.title)
    /// 2. For each estimate linked to the lead: update estimate.projectId to point at new project
    /// 3. For each LABOR line item across those estimates: insert a ProjectTask row
    ///    (projectId = new, sourceLineItemId = item.id, sourceEstimateId = item.estimateId,
    ///    taskTypeId = item.taskTypeId, status = .pending, displayOrder = item.displayOrder)
    /// 4. markWon(lead.id, actualValue: form.value, projectId: newProject.id, userId: me)
    /// Returns the new Project on success.
    /// If any step fails after step 1, surface a partial-failure state on the lead so the operator
    /// can retry from LeadDetailView.
    func convertLeadToProject(lead: Opportunity, form: ConvertForm) async throws -> Project { ... }

    /// CALLED ON SHEET DISMISS WITHOUT CONVERT.
    /// Marks the lead won with no project. Used by every non-CREATE exit from ConvertToProjectSheet.
    func markWonNoProject(lead: Opportunity, actualValue: Double?) async throws { ... }
}

struct ConvertForm {
    var title: String
    var address: String?
    var actualValue: Double?
    var notes: String?
    // Tasks list is implicit — derived from estimates. v1 has no per-task toggle.
}
```

### 9.3 Step-by-step convert transaction

```
1. INSERT INTO projects
     id = UUID()
     company_id = lead.companyId
     opportunity_id = lead.id              ← bible-required back-link
     client_id = lead.clientId
     title = form.title
     address = form.address
     status = 'accepted'                   ← bible default
     created_by = currentUser.id
   → returns project row P

2. FOR EACH estimate WHERE estimate.opportunityId = lead.id:
     UPDATE estimates SET project_id = P.id WHERE id = estimate.id

3. FOR EACH line_item WHERE line_item.estimateId IN (estimates above) AND type = 'labor':
     INSERT INTO project_tasks
       id = UUID()
       project_id = P.id
       company_id = lead.companyId
       task_type_id = line_item.taskTypeId
       custom_title = line_item.name (if no taskTypeId or name diverges)
       source_line_item_id = line_item.id
       source_estimate_id = line_item.estimateId
       status = 'pending'
       display_order = line_item.displayOrder
       duration = taskType.defaultDuration ?? 1
     (skip when line_item.taskTypeId is nil AND line_item.name is empty)

4. RPC move_opportunity_stage
     p_opportunity_id = lead.id
     p_to_stage = 'won'
   → also writes stage_transitions row (existing iOS pattern)

5. UPDATE opportunities SET
     actual_value = form.actualValue
     actual_close_date = now()
     project_id = P.id
   WHERE id = lead.id
```

Steps 2–3 are wrapped in a single Supabase RPC if we add one (`convert_lead_to_project` — recommended for atomicity); otherwise sequential client-side calls with explicit rollback on failure. **Recommendation: add the RPC** — partial-failure recovery in client code is fragile.

### 9.4 Bible-documented but DEFERRED in this rebuild

| Feature | Bible reference | Status |
|---|---|---|
| Site visit photo auto-attach on win | §10:289 | **Deferred** — separate ticket. Would require a `ProjectPhoto` insert per `SiteVisit.photos` with `source = 'site_visit'`. |
| Task Generation modal (the UI for adding/removing pre-materialization) | §10:290 | **Deferred** — v1 materializes all LABOR line items silently. Modal is a v2 affordance. |
| Inbound activity auto-advance (`quoted` → `negotiation` on inbound) | §10:260 | **Server-side trigger** — should fire from any Activity insert regardless of source. Verify with manual test. |
| First-activity auto-advance (`newLead` → `qualifying`) | §10:205 | **Server-side trigger** — same. Verify. |

### 9.5 Pre-flight UI states

Three render modes for `ConvertToProjectSheet`:

| State | Trigger | Render |
|---|---|---|
| **NORMAL** | No existing project found for `lead.opportunityId` | Standard form (§8.6 RICH VERSION) |
| **DUPLICATE EXISTS** | `existingProject(for: lead) != nil` | Replace form body with single olive-warning card showing existing project + `OPEN PROJECT →` button. Footer: `CANCEL` (won, no new project) + `OPEN PROJECT →` (won + push detail). |
| **CLIENT HAS OTHERS** | `clientProjectsSummary(for: lead).count > 0` AND no duplicate | Standard form **plus** a tan-warning banner at the top listing other projects for the same client. Operator can still proceed. |

### 9.6 New API surface

```swift
// LeadConversionService.swift — public surface
func existingProject(for lead: Opportunity) -> Project?
func clientProjectsSummary(for lead: Opportunity) -> [Project]
func estimates(for lead: Opportunity) async throws -> [Estimate]
func convertLeadToProject(lead: Opportunity, form: ConvertForm) async throws -> Project
func markWonNoProject(lead: Opportunity, actualValue: Double?) async throws

// EstimateRepository.swift — EXTEND (one new method)
func fetchLineItems(estimateId: String) async throws -> [EstimateLineItemDTO]
// (also fetch line items for ALL of a lead's estimates in one batch call if performance matters —
//  measure and decide during build)

// ProjectRepository.swift — EXTEND (one new helper, may go via RPC instead)
func batchInsertTasks(_ dtos: [SupabaseProjectTaskDTO]) async throws
```

### 9.7 Optional Supabase RPC (recommended)

**Path:** new migration `2026-05-XX-convert-lead-to-project-rpc.sql` (mirror into `ops-software-bible/migrations/`).

```sql
CREATE OR REPLACE FUNCTION convert_lead_to_project(
  p_opportunity_id uuid,
  p_actual_value numeric,
  p_title text,
  p_address text,
  p_user_id uuid
) RETURNS uuid AS $$
DECLARE
  v_project_id uuid;
  v_company_id uuid;
  v_client_id uuid;
BEGIN
  -- Look up the opportunity's company + client
  SELECT company_id, client_id INTO v_company_id, v_client_id
  FROM opportunities WHERE id = p_opportunity_id;

  -- Insert the project (status = accepted, opportunityId back-link)
  INSERT INTO projects (id, company_id, opportunity_id, client_id, title, address, status, created_by, created_at, updated_at)
  VALUES (gen_random_uuid(), v_company_id, p_opportunity_id, v_client_id, p_title, p_address, 'accepted', p_user_id, now(), now())
  RETURNING id INTO v_project_id;

  -- Forward-link any estimates attached to this opportunity
  UPDATE estimates SET project_id = v_project_id, updated_at = now()
  WHERE opportunity_id = p_opportunity_id AND project_id IS NULL;

  -- Materialize LABOR line items as project tasks
  INSERT INTO project_tasks (id, company_id, project_id, task_type_id, custom_title, source_line_item_id, source_estimate_id, status, display_order, duration, created_at)
  SELECT gen_random_uuid(), v_company_id, v_project_id, li.task_type_id,
         CASE WHEN li.task_type_id IS NULL THEN li.name ELSE NULL END,
         li.id, li.estimate_id, 'pending', li.display_order, 1, now()
  FROM line_items li
  WHERE li.estimate_id IN (SELECT id FROM estimates WHERE project_id = v_project_id)
    AND li.type = 'labor'
    AND li.task_type_id IS NOT NULL OR li.name IS NOT NULL;

  -- Mark the lead won (sets stage + actual_value + actual_close_date + project_id)
  UPDATE opportunities
  SET stage = 'won', actual_value = p_actual_value, actual_close_date = now(),
      project_id = v_project_id, updated_at = now()
  WHERE id = p_opportunity_id;

  -- Insert stage_transitions row (existing pattern)
  INSERT INTO stage_transitions (id, company_id, opportunity_id, from_stage, to_stage, transitioned_at, transitioned_by, created_at)
  SELECT gen_random_uuid(), v_company_id, p_opportunity_id, stage, 'won', now(), p_user_id, now()
  FROM opportunities WHERE id = p_opportunity_id;

  RETURN v_project_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION convert_lead_to_project TO authenticated;
```

**Why an RPC over client-side orchestration:** atomicity. Five separate Supabase calls with no transaction wrapper means partial failure leaves the lead in an inconsistent state (e.g. project created but tasks not, or tasks created but lead still in `quoted`). The RPC runs in a single Postgres transaction.

**Cost:** zero additional Supabase cost (RPC is just SQL). Migration adds ~3KB.

### Phase 5 deliverable

- 1 new service (`LeadConversionService.swift` — ~200 LoC)
- 1 new repository method extension (`EstimateRepository.fetchLineItems`) — ~20 LoC
- 1 new Supabase migration (`convert_lead_to_project` RPC) — ~50 LoC SQL
- 1 mirror into `ops-software-bible/migrations/`
- 1 bible update — `09_FINANCIAL_SYSTEM.md` § "Opportunity Helpers" gains a `convertLeadToProject` row in the iOS-parity table
- 1 commit: `feat(leads): lead → project conversion with estimate-task materialization (RPC-backed)`

---

## 10 · PHASE 6 — Cleanup + drift register update

### 10.1 Delete legacy files

```
rm OPS/Views/Books/Pipeline/AddFollowUpSheet.swift
rm OPS/Views/Books/Pipeline/AddLeadSheet.swift
rm OPS/Views/Books/Pipeline/EditLeadSheet.swift
rm OPS/Views/Books/Pipeline/LeadActionSheet.swift
rm OPS/Views/Books/Pipeline/LeadCardView.swift
rm OPS/Views/Books/Pipeline/LeadDetailView.swift
rm OPS/Views/Books/Pipeline/LeadLogActivitySheet.swift
rm OPS/Views/Books/Pipeline/LostReasonSheet.swift
rm OPS/Views/Books/Pipeline/PipelineSectionView.swift
rm OPS/Views/Books/Pipeline/StageStripView.swift
rmdir OPS/Views/Books/Pipeline
```

Plus delete from the new Leads dir:
```
rm OPS/Views/Leads/LeadsHeaderCarousel.swift
rm OPS/Views/Leads/BallInCourtBar.swift
rm OPS/Views/Leads/LeadListPage.swift
rm OPS/Views/Leads/Components/LeadCard.swift
rm OPS/Views/Leads/Components/LeadStageStrip.swift
rm OPS/Views/Leads/Components/ForecastBreakdownSheet.swift
```

`LeadsPreviewSupport.swift` is kept — it's still useful scaffolding for the new files. Update the `#Preview` blocks at the bottom of each new file.

### 10.2 Update VM

Remove from `PipelineViewModel`:
- `weightedForecastDelta`, `avgVelocityDays`, `avgVelocityDelta` (unless Q1 = (c))
- `closeRate(periodDays:)`, `closeRateWonCount`, `closeRateLostCount` (no longer surfaced anywhere)
- `oldestStaleDescription` (no longer surfaced)
- `inCourtCount`, `inCourtBuckets`, `inCourtTotalValue`, `inCourtOpportunityIds` (replaced by triage buckets)

Keep:
- `allOpportunities`, `selectedStage`, `currentUserId`, `setup`, `loadData`
- `opportunities(in:)`, `count(in:)` — used by `PipelineFooter`
- `weightedForecastValue`, `activeLeadCount`, `staleLeadsCount`, `staleLeadsTotalValue`
- `moveToStage`, `markWon`, `markLost`, `addLead`, `archive`, `softDelete`
- New triage helpers (Phase 2)

### 10.3 Documentation updates

- `ops-software-bible/09_FINANCIAL_SYSTEM.md` § Pipeline — describe the new triage queue surface, the bucket model, the convert-to-project flow
- `ops-software-bible/05_DESIGN_SYSTEM.md` — note the glass-modifier landing and the mobile-contrast earth-tone tokens
- `docs/superpowers/specs/2026-05-19-leads-tab-design-intent.md` — add a "Resolved" section closing out the open questions from §16 with this plan's decisions
- `docs/superpowers/specs/2026-05-11-pipeline-tab-design.md` — add a header banner: "SUPERSEDED 2026-05-19 by `2026-05-19-leads-tab-rebuild.md`"

### 10.4 Drift register

The design-intent doc §10 listed three known drifts. This rebuild addresses all three:

| Drift | Resolution |
|---|---|
| Hero carousel cards borderless vs spec | **Resolved.** Triage surface drops the carousel entirely — single L1 hero widget with hairline (per `.glassSurface()` modifier). |
| `primaryAccent` leakage on chrome | **Resolved.** No accent on filter chips, page indicators (no carousel), stage strip (no longer exists), or in-court rail. Accent stays on primary CTA + focus only. The `OPEN STAGE BOARD →` icon and pipeline footer chevrons are `text-mute`. |
| Card with rounded corners + colored left-border accent | **Resolved.** No stage-color leading rail anywhere. Stage identity comes from the earth-tone tag chip + the urgency-tinted verb on the action row. |

### Phase 6 deliverable

- ~10 file deletions
- VM cleanup
- 4 doc updates
- 1 commit: `refactor(leads): delete legacy pipeline views + clean up VM + close out drift`

---

## 11 · FILE INVENTORY — what lands

### Created (~16 files)

```
OPS/Styles/Components/
├── GlassSurface.swift                        [Phase 0]
├── FilterChipRow.swift                       [Phase 1]
├── PanelSectionHeader.swift                  [Phase 1]
└── Atmosphere.swift                          [Phase 2]

OPS/Views/Leads/
├── HeroWidget.swift                          [Phase 2]
├── WonConvertCard.swift                      [Phase 2]
├── PipelineFooter.swift                      [Phase 2]
├── LeadDetailView.swift                      [Phase 3 — replaces legacy]
├── LeadsTabView.swift                        [Phase 2 — REPLACED content]
├── Components/
│   ├── SubMetric.swift                       [Phase 1]
│   ├── LeadActionCard.swift                  [Phase 2]
│   ├── DetailHero.swift                      [Phase 3]
│   ├── ContactCard.swift                     [Phase 3]
│   ├── FollowUpsCard.swift                   [Phase 3]
│   ├── ActivityTimeline.swift                [Phase 3]
│   ├── StageTimeline.swift                   [Phase 3]
│   └── StickyActionBar.swift                 [Phase 3]
└── Sheets/
    ├── LeadFormView.swift                    [Phase 4 — shared by Add + Edit]
    ├── AddLeadSheet.swift                    [Phase 4]
    ├── EditLeadSheet.swift                   [Phase 4]
    ├── LostReasonSheet.swift                 [Phase 4]
    └── ConvertToProjectSheet.swift           [Phase 4]
```

### Modified

```
OPS/Styles/
├── OPSStyle.swift                            [Phase 0 — 9 new color constants + 1 layout constant]
└── Fonts.swift                               [Phase 2 — optional: add Mobile typography sub-namespace]

OPS/ViewModels/
└── PipelineViewModel.swift                   [Phase 2 — add triage bucketize + helpers; Phase 6 — remove unused]

OPS/Network/Supabase/Repositories/
└── ProjectRepository.swift                   [Phase 5 — add createStub(fromLead:)]

OPS/Views/Leads/
└── LeadsPreviewSupport.swift                 [Phase 2+3 — update for new views]

docs/superpowers/specs/
├── 2026-05-11-pipeline-tab-design.md         [Phase 6 — mark superseded]
└── 2026-05-19-leads-tab-design-intent.md     [Phase 6 — add Resolved section]

ops-software-bible/
├── 05_DESIGN_SYSTEM.md                       [Phase 6]
└── 09_FINANCIAL_SYSTEM.md                    [Phase 6]
```

### Deleted (~16 files)

```
OPS/Views/Books/Pipeline/*  (whole directory)
OPS/Views/Leads/LeadsHeaderCarousel.swift
OPS/Views/Leads/BallInCourtBar.swift
OPS/Views/Leads/LeadListPage.swift
OPS/Views/Leads/Components/LeadCard.swift
OPS/Views/Leads/Components/LeadStageStrip.swift
OPS/Views/Leads/Components/ForecastBreakdownSheet.swift
```

---

## 12 · COMMIT GRAPH

| # | Commit message | Files | Phase |
|---|---|---|---|
| 1 | `feat(style): mobile-contrast earth-tone variants + glass surface modifiers` | `OPSStyle.swift`, `GlassSurface.swift` | 0 |
| 2 | `feat(style): filter-chip-row + sub-metric + panel-section-header primitives` | `FilterChipRow.swift`, `PanelSectionHeader.swift`, `Components/SubMetric.swift` | 1 |
| 3 | `feat(leads): triage queue + hero widget + per-lead action card` | LeadsTabView rewrite + 5 new component files + VM extension | 2 |
| 4 | `feat(leads): lead detail view rebuild` | LeadDetailView + 8 detail-component files | 3 |
| 5 | `feat(leads): four sheets — add, edit, lost-reason, convert-to-project` | 5 sheet files, 4 legacy sheet deletes | 4 |
| 6 | `feat(leads): project-stub creation for won-lead conversion` | `ProjectRepository.swift` + service | 5 |
| 7 | `refactor(leads): delete legacy pipeline views + close out drift register` | ~10 file deletions, VM cleanup, doc updates | 6 |

Plus three commits **held from the prior session** (decide before Phase 0):

- A. `feat(leads): remove borders from hero carousel cards` — **drop** (the cards are gone anyway in Phase 2)
- B. `chore(leads): add live-preview scaffolding for all LEADS views` — **ship now** (the scaffolding still works for the new files, will be updated by Phase 2+3)
- C. `docs(leads): comprehensive design intent + engineering context pack for LEADS tab redesign` — **ship now** (independent of code)

---

## 13 · SF SYMBOL ICON MAPPING

Taken from the handoff README §"Assets" — keep this as the canonical map:

| Prototype | SF Symbol |
|---|---|
| home | `house.fill` |
| leads | `point.3.connected.trianglepath.dotted` |
| books | `chart.line.uptrend.xyaxis` |
| jobs | `briefcase.fill` |
| schedule | `calendar` |
| settings | `gearshape.fill` |
| search | `magnifyingglass` |
| filter | `line.3.horizontal.decrease` |
| sort | `arrow.up.arrow.down` |
| plus | `plus` |
| chevR / chevL / chevD / chevU | `chevron.right` / `.left` / `.down` / `.up` |
| arrowR | `arrow.right` |
| phone | `phone` |
| mail | `envelope` |
| message | `bubble.left` |
| pin | `mappin.and.ellipse` |
| clock | `clock` |
| note | `note.text` |
| check | `checkmark` |
| x | `xmark` |
| moreH | `ellipsis` |
| edit | `pencil` |
| archive | `archivebox` |
| trash | `trash` |
| inbox | `tray` |

---

## 14 · DEFINITION OF DONE

A phase is "done" when each of:

- [ ] All files in the phase's deliverable list exist with their specified components.
- [ ] All tokens used trace to `OPSStyle.*` or `Fonts.*` — zero hardcoded hex / spacing / radii / font names.
- [ ] No anti-pattern present (see design-intent §10): no rounded-card-with-colored-left-border, no accent on chrome, no springs, no emoji, no exclamation marks in copy.
- [ ] Touch targets ≥ 44pt for every interactive element.
- [ ] Empty states use the `00` / `—` + mono `// LABEL` pattern.
- [ ] Haptics fire on: tap-card (light), advance-stage (medium), won (success), lost (medium), bucket-chip-select (light), card-long-press (medium).
- [ ] Voice/copy follows OPS rules — UPPERCASE for authority, sentence case for content, `//` prefixes for system labels, numbers always mono and formatted, error states name the thing and offer next action.
- [ ] All new files include a `#Preview` block. The `LeadsPreviewSupport.swift` mock data continues to populate the previews.
- [ ] `xcodebuild -scheme OPS -destination 'generic/platform=iOS'` passes clean. **Coordinate with parallel xcodebuild sessions before kicking off.**
- [ ] Manual smoke test in the simulator: load triage → tap row → see detail → swipe back → tap each filter chip → tap WON-CONVERT card → fill convert sheet → confirm → see project in Projects tab → mark a lead lost → confirm reason → see it move out of the queue → mark a lead won via the detail sticky bar → confirm convert → return → archive a lead from Edit sheet → confirm it disappears.
- [ ] Offline smoke test: airplane mode → mark a lead won → see optimistic update → see "OFFLINE" indicator on the card → re-enable network → see sync resolve.

---

## 15 · TEST PLAN

### Manual smoke (every phase)

- Open LEADS tab → triage screen renders without console errors
- Hero widget shows correct forecast for seed data
- Each filter chip shows correct count
- Tapping a chip filters the list correctly
- Tapping a lead card pushes detail view
- Swipe back returns to triage with selection preserved
- Each sheet opens, dismisses (drag-down for half, x-button for full), and persists on save

### Edge cases

- Empty pipeline (0 leads) — every chip shows `00`, list shows empty-state hero
- All-stale state (every active lead past stale threshold) — buckets balance correctly
- Won lead with no `projectId` → WonConvertCard appears
- Won lead with `projectId` → WonConvertCard does NOT appear
- Lost lead → does not appear in any active bucket
- Lead with `nextFollowUpAt = nil` → does not appear in overdue/dueToday buckets
- Lead with `lastMessageDirection = "in"` → appears in waitingOnYou bucket
- Permission-restricted user (no `pipeline.manage`) — swipe actions hidden, sticky action bar shows EDIT only (or hidden entirely — TBD)
- Operator on iPhone 12 mini (smallest target device) — hero widget + chip row + 3+ lead cards visible without scroll
- Dynamic Type at XL — every label still readable, no truncation of critical numbers

### Build verification

- `xcodebuild` clean — per CLAUDE.md, `generic/platform=iOS` destination, **after checking** for parallel `xcodebuild` in worktrees
- No SwiftUI runtime warnings on launch
- `#Preview` blocks all render in Xcode canvas

---

## 16 · RISKS

| Risk | Mitigation |
|---|---|
| `.glassSurface()` modifier is wrong on the first attempt — too transparent, too opaque, gradient looks bad over an image background | Build a `Preview` host that shows the modifier over each of: pure black canvas, an image, a busy gradient. Tune the opacity stops there first before applying to LEADS. |
| Mobile-contrast tag colors don't match the prototype hex exactly | The README gives literal hexes (`#B5C9A0`, `#D6BC82`, `#C99CA3`). Use those directly. **Do not** improvise opacity adjustments. |
| `lastMessageDirection` denormalized field is sometimes nil even when activities exist | Fall back to `activities.first?.direction == .inbound` when the denormalized field is nil. Note: this requires loading activities, which is fine on detail but expensive on the triage list. **For the triage list, treat nil as "no inbound signal" and put the lead in `waitingOnThem`.** Document this. |
| The forecast number (`$184,240`) overflows the hero card on smaller screens | The hero font is Mohave Light 38 — for amounts > $1M, switch to `compact: true` formatting (`$1.2M`). Match the prototype's `fmtMoney` helper. |
| Parallel xcodebuild collision when verifying | Per memory rule: check `ps aux | grep xcodebuild` before running. If a sibling worktree is mid-build, wait. |
| Convert sheet → markWon → project creation is a 2-step async chain that could partially fail | Wrap in a single async function with rollback semantics. If project creation succeeds but markWon fails, the operator sees the project in Projects but the lead still says "won + no projectId" — surface this as a follow-up retry banner on the lead detail. |
| Deleting legacy Books/Pipeline files breaks anything still importing them | Run `grep -r "LeadCardView\|StageStripView\|PipelineSectionView" OPS --include="*.swift"` before deletion. Replace any survivors with the new symbols. |
| The Books tab `HeroCarousel` still uses the old flat `cardBackground` — the LEADS rebuild's glass modifier landing makes them look out-of-sync | Acceptable for v1. The Books tab is on the upgrade list but out of scope here. Document the drift. |
| Reduced motion users miss the slide transitions | Use `withAnimation(reduceMotion ? .none : OPSStyle.Animation.standard)` everywhere. SwiftUI's `accessibilityReduceMotion` environment value handles this. |

---

## 17 · ROLLBACK

If a phase ships and an issue surfaces, the rollback is `git revert <commit>` for the relevant commit. Each phase is one atomic commit; phases later than the broken one can be re-run on top of the reverted state.

Legacy files in `OPS/Views/Books/Pipeline/` are deleted in Phase 6 only — so if the new triage view breaks, we can re-route the LEADS tab back to the old surface by reverting Phase 2's `tabContent` change in `MainTabView.swift`. That's the panic button until Phase 6 lands.

---

## 18 · NEXT STEP

1. **User reviews this plan + answers the six questions in §2.**
2. Decisions get logged inline (a §2 sub-block per question with the chosen option + one-line reason).
3. The three held commits from the prior session get either shipped (B + C) or dropped (A).
4. Phase 0 begins.
