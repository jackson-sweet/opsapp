# OPS iOS — Major Version Design Spec
**Date:** 2026-02-18
**Scope:** iOS app major version update — Supabase integration, Pipeline CRM, Estimates, Invoices, Accounting
**Author:** Design session (mobile-ux-design + wireframe skills)
**Status:** Approved — ready for writing-plans handoff

---

## Context

The web app (ops-web) has received significant updates in the past week:
- Full Supabase-backed Pipeline CRM (8-stage Kanban, opportunities, activities, follow-ups)
- Estimates with line items, optional items, deposits, versioning
- Invoices with payment tracking, DB-trigger-maintained balance
- Products/services catalog
- Accounting dashboard with AR aging + QuickBooks/Sage OAuth
- Project Notes (threaded, @mentions)
- Site Visits lifecycle entity

The iOS app is purely Bubble-backed with none of these features. This document specifies the full major version update to bring iOS to parity.

---

## Design System Reference

**File:** `OPS/Styles/OPSStyle.swift` + `Styles/Components/`
**Aesthetic:** Apple precision × Defense Tech (Anduril, Palantir, xAI feel)
**Theme:** Dark only. No light mode in this release.

### Token Quick Reference

| Token | Value | Use |
|---|---|---|
| `OPSStyle.Colors.background` | #000000 | App-wide background |
| `OPSStyle.Colors.cardBackgroundDark` | #1F293D | Card surfaces (at 0.6 opacity) |
| `OPSStyle.Colors.primaryAccent` | #59779F (steel blue) | ONE element per screen max |
| `OPSStyle.Colors.primaryText` | #E5E5E5 | Body text, primary labels |
| `OPSStyle.Colors.secondaryText` | #AAAAAA | Supporting text, subtitles |
| `OPSStyle.Colors.tertiaryText` | #777777 | Metadata, captions |
| `OPSStyle.Colors.successStatus` | #A5B368 | Success only |
| `OPSStyle.Colors.warningStatus` | #C4A868 | Warning/stale indicators only |
| `OPSStyle.Colors.errorStatus` | #931A32 | Errors, destructive only |
| `OPSStyle.Colors.cardBorder` | white 20% | Standard card border |
| `OPSStyle.Colors.separator` | white 15% | Divider lines |
| `OPSStyle.Layout.cornerRadius` | 5pt | Standard |
| `OPSStyle.Layout.cardCornerRadius` | 8pt | Larger cards |
| `OPSStyle.Layout.largeCornerRadius` | 12pt | Modals, sheets |
| `OPSStyle.Layout.touchTargetStandard` | 56pt | All interactive elements |
| `OPSStyle.Layout.touchTargetLarge` | 64pt | FAB |

### Component Quick Reference

| Component | Usage |
|---|---|
| `.opsCardStyle()` | Standard card — `cardBackgroundDark.opacity(0.6)`, 5pt radius |
| `.opsInteractiveCardStyle(action:)` | Tappable card with press feedback |
| `.opsAccentCardStyle(accentColor:)` | Card with accent-color border (active/selected) |
| `.opsPrimaryButtonStyle()` | White fill, black text — ONE per screen |
| `.opsSecondaryButtonStyle()` | Accent border + accent text |
| `.opsDestructiveButtonStyle()` | Error fill, white text |
| `OPSButtonStyle.Icon` | Circular icon button, 44pt |

### Typography Rules
- **Mohave** — structured, scannable content (titles, labels, data fields, buttons)
- **Kosugi** — narrative, readable content (notes, descriptions, activity text)
- **All titles and section headers: UPPERCASE**
- **Captions and metadata: [wrapped in square brackets]**
- **No system font (SF Pro) anywhere in UI**

---

## Architecture Changes

### 1. Tab Bar — Role-Gated

**Field Crew** (unchanged):
```
Home  |  Job Board  |  Schedule  |  Settings
```

**Admin / Office Crew** (new 5-tab set):
```
Home  |  Pipeline  |  Job Board  |  Schedule  |  Settings
```

Pipeline tab injected at position 2. Field crew have zero awareness it exists — role check at `AppState` level before rendering `MainTabView`.

### 2. Dual Networking Layer

```
BubbleAPIService (existing)        SupabaseService (new)
        │                                  │
  BubbleSyncManager              SupabaseSyncManager
        │                                  │
SwiftData (Bubble entities)    SwiftData (Supabase entities)
```

`SupabaseService` — `supabase-swift` package. Firebase JWT passed as auth token (same bridge pattern as ops-web). No separate Supabase login for the user.

**New package:** `github.com/supabase/supabase-swift`

### 3. Bubble Data Model Updates

Existing SwiftData entities need new optional fields from Bubble:

| Entity | New Field | Type |
|---|---|---|
| `Project` | `opportunityId` | `String?` |
| `ProjectTask` | `sourceLineItemId` | `String?` |
| `ProjectTask` | `sourceEstimateId` | `String?` |
| `CalendarEvent` | `eventType` | `CalendarEventType` enum |
| `CalendarEvent` | `opportunityId` | `String?` |
| `CalendarEvent` | `siteVisitId` | `String?` |
| `TaskType` | `defaultTeamMemberIds` | `[String]` |

New `CalendarEventType` enum: `.task` / `.siteVisit` / `.other` (default `.task`)

New Bubble entity: `TaskTemplate` (admin settings, task auto-generation config)

### 4. New SwiftData Models (Supabase-backed)

| Model | Purpose |
|---|---|
| `Opportunity` | Pipeline deal — 8 stages |
| `Activity` | Timeline event per opportunity |
| `FollowUp` | Scheduled reminder |
| `StageTransition` | Immutable stage history |
| `Estimate` | Quote document |
| `EstimateLineItem` | Line items on estimates |
| `Invoice` | Billing document |
| `InvoiceLineItem` | Line items on invoices |
| `Payment` | Payment records (insert-only) |
| `Product` | Service/product catalog item |
| `SiteVisit` | Scope assessment visit |
| `SupabaseCompanySettings` | Task gen flags, Gmail config, etc. |

### 5. New OPSStyle.Icons (add to OPSStyle.swift)

```swift
// Pipeline & Financial
static let opportunity     = "arrow.up.right.circle.fill"
static let pipeline        = "chart.bar.doc.horizontal.fill"
static let estimate        = "doc.text.fill"
static let invoice         = "receipt"
static let payment         = "dollarsign.circle.fill"
static let siteVisit       = "mappin.circle.fill"
static let activity        = "bubble.left.and.text.bubble.right.fill"
static let followUp        = "alarm.fill"
static let stageAdvance    = "arrow.forward.circle.fill"
static let won             = "checkmark.seal.fill"
static let lost            = "xmark.seal.fill"
static let accounting      = "chart.bar.fill"
static let products        = "tag.fill"        // reuse existing tagFill concept
static let stale           = "exclamationmark.triangle.fill"  // reuse existing
```

### 6. New Pipeline Status Colors (add to OPSStyle.Colors)

```swift
static func pipelineStageColor(for stage: PipelineStage) -> Color {
    switch stage {
    case .newLead:      return Color(hex: "#BCBCBC")   // neutral gray
    case .qualifying:   return Color(hex: "#B5A381")   // warm tan
    case .quoting:      return Color(hex: "#8195B5")   // steel blue-gray
    case .quoted:       return Color(hex: "#9DB582")   // muted green
    case .followUp:     return Color(hex: "#C4A868")   // amber (warning)
    case .negotiation:  return Color(hex: "#B58289")   // muted rose
    case .won:          return Color(hex: "#A5B368")   // success green
    case .lost:         return Color(hex: "#931A32")   // error red
    }
}
```

---

## Pipeline Tab — Internal Navigation

The Pipeline tab uses a segmented control (underline style) at the top:

```
PIPELINE  |  ESTIMATES  |  INVOICES  |  ACCOUNTING
```

Each section is a full-screen view within the tab. No nested tab bars — one segmented control replaces them all.

---

## Screen 1: PipelineView (Kanban)

**Winning variant:** Hybrid (Variant 4)
**Purpose:** At-a-glance pipeline health + quick stage navigation
**User:** Admin / Office Crew
**Entry:** Pipeline tab tap
**Primary action:** Create new opportunity (FAB)

### Layout

```
┌─────────────────────────────────┐
│ PIPELINE                        │  Mohave, UPPERCASE, primaryText
│ $82,400 WEIGHTED · 14 DEALS     │  Mohave, secondaryText — weighted = Σ(value × winProb)
├─────────────────────────────────┤
│ ┌──────────────────────────────┐│
│ │← NEW·2  QUAL·1  QUOT·3  ···→││  horizontal scroll, Mohave 11sp UPPERCASE
│ │              ─────           ││  primaryAccent underline on active stage
│ └──────────────────────────────┘│
├─────────────────────────────────┤
│                                 │  scroll view, cards fill body
│ ┌─────────────────────────────┐ │
│ │ Sarah Chen          $4,200  │ │  .opsInteractiveCardStyle()
│ │ Riverside Kitchen Reno      │ │  Kosugi 13sp, secondaryText
│ │ ● QUOTING          [day 3]  │ │  status badge left, caption right in brackets
│ └─────────────────────────────┘ │
│                                 │
│ ┌─────────────────────────────┐ │
│ │ ⚠ Marcus Webb       $8,500  │ │  warningStatus icon left of name
│ │ HVAC Replacement            │ │
│ │ ● QUOTING          [day 9]  │ │
│ └─────────────────────────────┘ │
│                                 │
│                      ╔═════╗    │
│                      ║  +  ║    │  FAB: primaryAccent fill, 64pt
│                      ╚═════╝    │  expands: New Lead / Log Activity / Site Visit
└─────────────────────────────────┘
```

### States

| State | Treatment |
|---|---|
| Loading | Tactical bar animation (existing TacticalLoadingBar) |
| Empty (no deals ever) | Icon (`pipeline`) + "NO LEADS YET" (Mohave UPPERCASE) + "Create your first lead" (Kosugi) + primary button "NEW LEAD" |
| Empty (stage filter active) | "NO DEALS IN THIS STAGE" — text only, no illustration |
| Offline | Top banner: warningStatus background, "WORKING OFFLINE — changes will sync" — reads from cache, FAB disabled |
| Error | Top toast: errorStatus left border, "SYNC FAILED" + retry action |

### Components

| Component | Token / Style | Notes |
|---|---|---|
| Screen title | Mohave, UPPERCASE, primaryText | "PIPELINE" |
| Metrics strip | Mohave, secondaryText, 14sp | Weighted pipeline value + active count |
| Stage strip | Horizontal scroll, Mohave 11sp UPPERCASE | `cardBackgroundDark.opacity(0.4)` bg |
| Stage underline | `primaryAccent`, 2pt height | Active stage indicator |
| Deal card | `.opsInteractiveCardStyle()` | `cardBackgroundDark.opacity(0.6)`, 8pt radius |
| Card name | Mohave 16sp, primaryText | Contact or company name |
| Card value | Mohave 16sp, primaryText, trailing | Dollar amount |
| Card description | Kosugi 13sp, secondaryText | Job/project description |
| Stage badge | Status pill — `pipelineStageColor(for:)` | Mohave 11sp UPPERCASE, radiusPill |
| Days in stage | `[day N]` — Kosugi 12sp, tertiaryText | Always in square brackets |
| Stale icon | `warningStatus` triangle icon, 16pt | Shown if no activity > 7 days |
| FAB | `primaryAccent` fill, 64pt, trailing-bottom | Expands 3 options radially |

### Interactions

| Gesture | Action |
|---|---|
| Tap stage in strip | Filter cards to that stage |
| Swipe card right | Advance to next stage (ghost confirm strip slides from top: "ADVANCED TO QUOTED ✓") |
| Swipe card left | Flag menu: Lost / Stale / Archive |
| Tap card | Push to `OpportunityDetailView` |
| Tap FAB | Expand: [New Lead] [Log Activity] [Site Visit] |
| Long press card | Context menu: Edit / Duplicate / Delete |

### Typography

- Title "PIPELINE": Mohave Display, UPPERCASE
- Section label (stage name): Mohave 13sp, UPPERCASE, secondaryText when inactive, primaryText when active
- Card name: Mohave, body weight, primaryText — data-oriented, scannable
- Card description: Kosugi — narrative, softer read
- Caption metadata `[day 3]`: Kosugi 12sp, tertiaryText, brackets always

---

## Screen 2: OpportunityDetailView

**Winning variant:** Hybrid (Variant 4)
**Purpose:** Full context on one deal — activity, estimates, invoices
**User:** Admin / Office Crew
**Entry:** Tap card in PipelineView (push navigation)
**Primary action:** Log activity (most common repeat action)

### Layout

```
┌─────────────────────────────────┐
│ ←                          ···  │  back chevron, overflow menu (···)
│ SARAH CHEN                      │  Mohave 24sp UPPERCASE, primaryText
│ Riverside Kitchen Reno          │  Kosugi 14sp, secondaryText
│ $4,200  ● QUOTING  [day 3]  ⚠  │  value / stage badge / bracket caption / stale icon
│ ─────────────────────────────── │  separator (white 15%)
│ [📞 CALL] [✉ EMAIL] [→ ADVANCE] │  3 ghost buttons, equal width, 56pt touch target
│                                 │  ADVANCE: secondaryText, no accent — ghost only
├─────────────────────────────────┤
│ ACTIVITY  │  ESTIMATES  │ INVOICES │  underline segmented control
│─────────────────────────────────│
│                                 │
│  ┌─────────────────────────────┐│
│  │ ✓ NOTE           [2hr ago] ││  activity type icon + type label + bracket time
│  │   Called client re scope   ││  Kosugi body, secondaryText
│  ├─────────────────────────────┤│
│  │ ✉ EMAIL        [yesterday] ││
│  │   Sent initial estimate    ││
│  ├─────────────────────────────┤│
│  │ ⬆ STAGE CHANGE [3 days ago]││
│  │   new_lead → qualifying    ││  Kosugi, tertiaryText (system event)
│  ├─────────────────────────────┤│
│  │     [VIEW ALL 12 EVENTS]   ││  text button, secondaryText
│  └─────────────────────────────┘│
│                                 │
│  FOLLOW-UPS             [+ ADD] │  section title + inline add
│  ┌─────────────────────────────┐│
│  │ 📞 Call re deposit  [tmrw] ││
│  └─────────────────────────────┘│
│                                 │
│                      ╔═════╗    │
│                      ║  +  ║    │  FAB: Log Activity / New Estimate / Site Visit
│                      ╚═════╝    │
└─────────────────────────────────┘
```

**ESTIMATES tab:**
```
│ EST-0042    DRAFT     $4,200    [2 days ago]  │
│ [swipe right = send, swipe left = void]       │
│                                               │
│ [+ NEW ESTIMATE]  (text button, bottom)       │
```

**INVOICES tab:**
```
│ INV-0018  AWAITING   $4,200    [due in 14d]   │
│ [swipe right = record payment, swipe left = void] │
│                                               │
│ [+ CREATE FROM ESTIMATE]  (text button)       │
```

### States

| State | Treatment |
|---|---|
| Loading | Skeleton rows in activity list |
| Empty (no activity yet) | "NO ACTIVITY YET" text + "Log the first note" primary button |
| Empty (estimates tab) | "NO ESTIMATES" + "Create estimate" primary button |
| Offline | Banner at top, all write actions disabled, reads from cache |

### Components

| Component | Token / Style | Notes |
|---|---|---|
| Name | Mohave 24sp UPPERCASE, primaryText | Contact or company |
| Description | Kosugi 14sp, secondaryText | Project/job description |
| Stage badge | `pipelineStageColor(for:)` pill | Mohave 11sp UPPERCASE |
| Days caption | `[day N]` Kosugi 12sp, tertiaryText, brackets | |
| Stale icon | `warningStatus`, 16pt | Only if stale |
| Quick actions | `.opsSecondaryButtonStyle()` — 3 equal-width | Accent border + text |
| Segmented control | Underline style, Mohave 13sp UPPERCASE | Existing pattern |
| Activity row | `.opsCardStyle()` with divider | Card groups all items |
| Activity icon | SF Symbol, 16pt, type-matched | ✓ ✉ ⬆ 📞 etc |
| Activity type | Mohave 12sp UPPERCASE, secondaryText | "NOTE" "EMAIL" "STAGE CHANGE" |
| Activity time | Kosugi 12sp, tertiaryText, `[brackets]` | "[2hr ago]" |
| Activity body | Kosugi 14sp, secondaryText, 1.5 line height | Narrative — Kosugi justified |
| System events | Kosugi 14sp, tertiaryText | Lighter than user-created |
| Follow-up row | `.opsInteractiveCardStyle()` | Tap to complete/edit |
| Overflow menu (···) | Icon button, 44pt | Edit deal / Won / Lost / Delete |

### Interactions

| Gesture | Action |
|---|---|
| Tap ← | Pop to PipelineView |
| Tap ··· | Sheet: Edit / Mark Won / Mark Lost / Delete |
| Tap CALL | Opens phone dialer with client phone |
| Tap EMAIL | Opens mail compose |
| Tap ADVANCE | Stage advance confirmation sheet (shows new stage name) |
| Swipe tab | Switch between Activity / Estimates / Invoices |
| Swipe estimate right | "SEND ESTIMATE" action + send flow sheet |
| Swipe estimate left | Void confirmation |
| Swipe invoice right | PaymentRecordSheet |
| Tap FAB | Expand: Log Activity / New Estimate / Site Visit |
| Long press activity | "DELETE ACTIVITY" context option (with confirmation) |

### Mark Won / Lost Sheet

Bottom sheet, `largeCornerRadius`, drag handle:
- **Won:** "MARK AS WON" title + "This will advance the deal to Won and can trigger project creation." body + "CONFIRM WIN" primary button (white fill)
- **Lost:** Required loss reason field (Kosugi textarea) + "MARK AS LOST" destructive button

---

## Screen 3: OpportunityFormSheet (New Lead)

**Purpose:** Create a new pipeline opportunity
**Presentation:** `.sheet` from FAB
**Primary action:** Save

### Layout

```
┌─────────────────────────────────┐
│ Cancel    NEW LEAD        Save  │  StandardSheetToolbar pattern
├─────────────────────────────────┤
│ CONTACT                         │
│ ┌─────────────────────────────┐ │
│ │ Name            [required]  │ │
│ ├─────────────────────────────┤ │
│ │ Phone           [optional]  │ │
│ ├─────────────────────────────┤ │
│ │ Email           [optional]  │ │
│ └─────────────────────────────┘ │
│                                 │
│ DEAL DETAILS                    │
│ ┌─────────────────────────────┐ │
│ │ Job Description [optional]  │ │
│ ├─────────────────────────────┤ │
│ │ Estimated Value $           │ │
│ ├─────────────────────────────┤ │
│ │ Source               ›      │ │  dropdown: Referral/Website/Email/etc
│ └─────────────────────────────┘ │
│                                 │
│ ► ASSIGN & NOTES                │  collapsed by default
│                                 │
└─────────────────────────────────┘
```

Save disabled until Name is filled. Save enabled = accent-text label (not white fill — that's reserved for the most impactful action; here Cancel/Save in toolbar use text buttons per StandardSheetToolbar pattern).

---

## Screen 4: EstimateFormSheet

**Winning variant:** Hybrid (Variant 4)
**Purpose:** Build a quote with line items
**User:** Admin / Office Crew
**Entry:** FAB on OpportunityDetailView, or Estimates list "+" button
**Primary action:** Send Estimate

### Layout

```
┌─────────────────────────────────┐
│ Cancel    NEW ESTIMATE    Save  │  StandardSheetToolbar
├─────────────────────────────────┤
│                                 │
│ ▼ CLIENT & PROJECT              │  collapsible, expanded by default
│ ┌─────────────────────────────┐ │
│ │ Client            Sarah ›   │ │  dropdown, 56dp
│ ├─────────────────────────────┤ │
│ │ Project     Riverside Reno ›│ │  dropdown, links to Bubble project
│ └─────────────────────────────┘ │
│                                 │
│ ▼ LINE ITEMS                    │  always expanded
│ ┌─────────────────────────────┐ │
│ │ Deck framing        $1,200  │ │  tap to edit, swipe left to delete
│ │ LABOR  [16hr · $75/hr]      │ │  Kosugi 12sp, tertiaryText, brackets
│ ├─────────────────────────────┤ │
│ │ Composite Decking   $2,400  │ │
│ │ MATERIAL  [120sqft · $20/u] │ │
│ ├─────────────────────────────┤ │
│ │ [+ ADD FROM CATALOG]        │ │  opens product picker bottom sheet
│ │ [+ CUSTOM LINE ITEM]        │ │  text buttons, secondaryText
│ └─────────────────────────────┘ │
│                                 │
│ ► PAYMENT & TERMS               │  collapsed
│ ► NOTES & ATTACHMENTS           │  collapsed
│                                 │
├─────────────────────────────────┤  sticky footer
│ Subtotal $3,600   Tax $468      │  Mohave 13sp, secondaryText
│ TOTAL  $4,068     [SEND EST →]  │  TOTAL: Mohave 16sp primaryText; button: .opsPrimaryButtonStyle()
└─────────────────────────────────┘
```

### Line Item Edit Bottom Sheet

```
┌─────────────────────────────────┐
│ ▬▬▬   EDIT LINE ITEM            │  drag handle + Mohave UPPERCASE title
│ Description  [Deck framing    ] │
│ Type         LABOR  ›           │  dropdown: LABOR / MATERIAL / OTHER
│ Qty    16    Unit   hr          │  side-by-side fields
│ Unit Price   [75.00           ] │
│ Optional?    ○──● (toggle)      │
│ Taxable?     ●──○ (toggle)      │
│ LINE TOTAL   $1,200             │  computed, Mohave 16sp, primaryText — never editable
│ ┌───────────────────────────── ┐│
│ │       SAVE CHANGES           ││  .opsPrimaryButtonStyle() — white fill
│ └──────────────────────────────┘│
│     [DELETE LINE ITEM]          │  .opsDestructiveButtonStyle(), text only, centered
└─────────────────────────────────┘
```

### Product Picker Bottom Sheet

```
┌─────────────────────────────────┐
│ ▬▬▬   SELECT FROM CATALOG       │
│ [🔍 Search products...        ] │  OPS SearchField
├─────────────────────────────────┤
│ Deck Framing                    │  56dp row
│ LABOR · $75/hr    [tap to add]  │  tap row = add line item + dismiss
├─────────────────────────────────┤
│ Composite Decking               │
│ MATERIAL · $20/sqft             │
├─────────────────────────────────┤
│ [+ NEW PRODUCT]                 │  text button — create and add
└─────────────────────────────────┘
```

### States

| State | Treatment |
|---|---|
| No line items | "ADD LINE ITEMS ABOVE" placeholder text in line items card |
| Saving | Save button shows spinner, disabled |
| Send success | Toast: "ESTIMATE SENT" successStatus left border |
| Offline | Save Draft available; Send disabled with "CONNECT TO SEND" tooltip |

### Components

| Component | Token | Notes |
|---|---|---|
| Collapsible section header | Mohave 13sp UPPERCASE, secondaryText | ▼ open, ► closed |
| Line item name | Mohave 16sp, primaryText | |
| Line item value | Mohave 16sp, primaryText, trailing | |
| Line item detail row | Kosugi 12sp, tertiaryText, `[brackets]` | Type · qty · unit price |
| Running total label | Mohave 13sp, secondaryText | Sticky footer subtotal/tax |
| Total amount | Mohave 18sp, primaryText | Prominent in sticky footer |
| Send button | `.opsPrimaryButtonStyle()` | White fill — primary action |
| Save (toolbar) | Mohave text button, accent color | StandardSheetToolbar pattern |

### Interactions

| Gesture | Action |
|---|---|
| Tap line item | Open line item edit bottom sheet |
| Swipe line item left | Delete with confirmation |
| Tap + ADD FROM CATALOG | Product picker bottom sheet |
| Tap + CUSTOM LINE ITEM | Blank line item edit sheet |
| Tap SEND ESTIMATE | Two-step send flow (client confirm → project confirm) |
| Tap SAVE (toolbar) | Save as Draft, dismiss sheet |
| Tap ► section header | Expand / collapse section |

---

## Screen 5: EstimatesListView

**Purpose:** All estimates across the company
**Entry:** Pipeline tab → ESTIMATES segment
**Primary action:** Create new estimate

### Layout

```
┌─────────────────────────────────┐
│ PIPELINE │ ESTIMATES │ INVOICES │ ACCOUNTING  (segmented)
│──────────────────────────────── │
│ [🔍 Search...]     [Filter ▼]  │
│ ALL  DRAFT  SENT  APPROVED      │  sub-filter chips
├─────────────────────────────────┤
│ ┌─────────────────────────────┐ │
│ │ EST-0042            $4,200  │ │
│ │ Sarah Chen                  │ │  Kosugi, secondaryText
│ │ ● DRAFT            [2d ago] │ │
│ └─────────────────────────────┘ │
│ ┌─────────────────────────────┐ │
│ │ EST-0041           $12,800  │ │
│ │ Brightfield Co.             │ │
│ │ ● SENT             [5d ago] │ │
│ └─────────────────────────────┘ │
│                        ╔═════╗  │
│                        ║  +  ║  │
│                        ╚═════╝  │
└─────────────────────────────────┘
```

Card swipe right = Send (if Draft) or "Convert to Invoice" (if Approved).
Card swipe left = Void/Delete.
Tap card = push to EstimateDetailView.

---

## Screen 6: EstimateDetailView

**Purpose:** Full view of one estimate + status actions
**Entry:** Tap estimate card
**Primary action:** Context-dependent (Send if Draft, Convert if Approved)

```
┌─────────────────────────────────┐
│ ←  EST-0042                ···  │
│ SARAH CHEN  —  Riverside Reno   │  Kosugi, secondaryText
│ $4,200          ● DRAFT         │
│ [created 2 days ago]            │  bracket caption, tertiaryText
├─────────────────────────────────┤
│ LINE ITEMS                      │
│ ┌─────────────────────────────┐ │
│ │ Deck Framing        $1,200  │ │
│ │ LABOR [16hr · $75/hr]       │ │
│ ├─────────────────────────────┤ │
│ │ Composite Decking   $2,400  │ │
│ │ MATERIAL [120sqft · $20/u]  │ │
│ ├─────────────────────────────┤ │
│ │ SUBTOTAL            $3,600  │ │
│ │ TAX (13%)             $468  │ │
│ │ TOTAL               $4,068  │ │  Mohave 16sp, primaryText
│ └─────────────────────────────┘ │
├─────────────────────────────────┤  sticky footer
│      [EDIT]        [SEND →]     │  secondary button left, primary button right
└─────────────────────────────────┘
```

For Approved estimates: footer shows `[CONVERT TO INVOICE →]` primary button.
For Sent estimates: footer shows `[RESEND]` secondary + `[MARK APPROVED]` primary.

---

## Screen 7: InvoicesListView + InvoiceDetailView

Mirrors Estimates screens in structure. Key differences:

**List card shows:**
- INV-0018  |  $4,200  |  ● AWAITING  |  [due in 14 days]
- Overdue: `errorStatus` badge + date in `errorStatus` color
- Swipe right = PaymentRecordSheet
- Swipe left = Void (with confirmation)

**Detail view sticky footer:**
- Unpaid: `BALANCE DUE: $4,200` (Mohave 18sp, primaryText) + `[RECORD PAYMENT]` primary button
- Partially paid: `BALANCE DUE: $2,100` + `[RECORD PAYMENT]` primary button
- Paid: `PAID IN FULL` (successStatus) — no action button

### PaymentRecordSheet (Bottom Sheet)

```
┌─────────────────────────────────┐
│ ▬▬▬   RECORD PAYMENT            │
│ Amount     [$4,200.00         ] │  pre-filled with balance due
│ Date       [Today, Feb 18    ] │
│ Method     Cash  ›             │  dropdown
│ Notes      [optional note...  ] │
│ ┌──────────────────────────────┐│
│ │        RECORD PAYMENT        ││  .opsPrimaryButtonStyle()
│ └──────────────────────────────┘│
└─────────────────────────────────┘
```

---

## Screen 8: ProductsListView + ProductFormSheet

**Entry:** Settings tab → "PRODUCTS & SERVICES" row (new Settings section for Admin)
**Alternative access:** Estimate Form → "Add from Catalog" → "New Product" button

**List view:** Standard card list, filter chips: ALL / LABOR / MATERIAL / OTHER
**Card shows:** Product name / Type badge / Default price / Margin if configured

**Form sheet:** Name / Description / Type (LABOR/MATERIAL/OTHER) / Default price / Unit cost (for margin) / Unit / Taxable toggle / Active toggle

---

## Screen 9: AccountingDashboard

**Entry:** Pipeline tab → ACCOUNTING segment
**Purpose:** Financial health overview — AR aging, invoice status, top balances

```
┌─────────────────────────────────┐
│ PIPELINE │ ESTIMATES │ INVOICES │ ACCOUNTING  (segmented)
├─────────────────────────────────┤
│ AR AGING                        │  section title Mohave UPPERCASE
│ ┌─────────────────────────────┐ │
│ │ ████████░░░░  0-30d  $8,200 │ │  horizontal bar chart
│ │ █████░░░░░░░  31-60d $3,400 │ │  bars: primaryAccent fill
│ │ ██░░░░░░░░░░  61-90d $1,200 │ │  warningStatus for 61-90d
│ │ █░░░░░░░░░░░  90d+     $800 │ │  errorStatus for 90d+
│ └─────────────────────────────┘ │
│                                 │
│ INVOICE STATUS                  │
│ ┌──────────┐  ┌──────────┐     │
│ │    3     │  │    2     │     │  2x2 stat tiles
│ │ AWAITING │  │ OVERDUE  │     │  warningStatus / errorStatus
│ └──────────┘  └──────────┘     │
│ ┌──────────┐  ┌──────────┐     │
│ │    8     │  │  $13,600 │     │
│ │   PAID   │  │ OUTSTAND.│     │
│ └──────────┘  └──────────┘     │
│                                 │
│ TOP OUTSTANDING                 │
│ ┌─────────────────────────────┐ │
│ │ Brightfield Co.    $6,800   │ │  tap → client detail / invoice list
│ ├─────────────────────────────┤ │
│ │ Marcus Webb        $3,400   │ │
│ ├─────────────────────────────┤ │
│ │ Ryan Torres        $3,400   │ │
│ └─────────────────────────────┘ │
│                                 │
│ INTEGRATIONS            [→]     │  taps to Settings → Integrations
│ QuickBooks   ● CONNECTED        │
└─────────────────────────────────┘
```

Read-only screen. No FAB. All data from Supabase, local cache first.

---

## Screen 10: Settings — New Sections (Admin only)

### Integrations (new section in SettingsView)

```
INTEGRATIONS                        ← new section title

QuickBooks Online        [CONNECT]  ← if not connected: secondary button
QuickBooks Online        ● CONNECTED [DISCONNECT]  ← if connected
Sage                     [CONNECT]
```

OAuth flow opens in-app `WKWebView` sheet. On redirect: token stored to Supabase `accounting_connections`.

### Products & Services (new row in SettingsView)

```
Products & Services   ›    ← navigates to ProductsListView
```

Visible to Admin only.

---

## Updated Existing Screens

### ProjectDetailView — New Elements

**Opportunity badge** (if `project.opportunityId` is set):
```
┌──────────────────────────────┐
│ ↑ LINKED OPPORTUNITY         │  Mohave 12sp UPPERCASE, accent border card
│   Sarah Chen — QUOTED        │  Kosugi 13sp — tap to push OpportunityDetailView
└──────────────────────────────┘
```

**Estimate/Invoice summary strip** (if linked):
```
EST-0042  DRAFT  $4,200    [view →]
```
Shown as a compact row inside existing project detail, secondaryText, tap navigates to EstimateDetailView.

### TaskDetailView — Source Attribution

If `task.sourceEstimateId` is set, show attribution row:
```
┌─────────────────────────────┐
│ 📄 EST-0042   [auto-generated from estimate]  │
└─────────────────────────────┘
```
Kosugi 13sp, tertiaryText. Tap navigates to EstimateDetailView. Read-only — field crew see this too.

### CalendarView — Site Visit Event Type

`CalendarEvent.eventType == .siteVisit` renders with:
- `pipelineStageColor(.qualifying)` as event color (instead of task color)
- `siteVisit` icon (mappin.circle.fill) instead of task icon
- Tapping does NOT open TaskDetailsView — opens read-only SiteVisitDetailView (or push to OpportunityDetailView on iOS)

---

## Sprint Plan

### Sprint 1 — Foundation (parallel with all others)
- Add `supabase-swift` package
- `SupabaseService` with Firebase JWT bridge
- `SupabaseSyncManager` skeleton
- Update Bubble SwiftData models with new optional fields
- `CalendarEventType` enum
- `TaskTemplate` model + fetch endpoint
- New `OPSStyle.Icons` additions
- `pipelineStageColor(for:)` status color function
- Role-gated tab bar (inject Pipeline tab for Admin/Office)

### Sprint 2 — Pipeline CRM
- `Opportunity` SwiftData model + DTO + SupabaseService CRUD
- `Activity`, `FollowUp`, `StageTransition` models + service
- `PipelineView` (Kanban — Variant 4)
- `OpportunityDetailView` (Variant 4 — Activity/Estimates/Invoices tabs)
- `OpportunityFormSheet` (new lead creation)
- `ActivityFormSheet` (log call/note/email/meeting)
- `FollowUpSheet`
- Stage advance / Won / Lost flows

### Sprint 3 — Estimates
- `Estimate`, `EstimateLineItem` models + DTO + service
- `EstimatesListView`
- `EstimateDetailView`
- `EstimateFormSheet` (Variant 4 — collapsible sections + sticky footer)
- Line item edit bottom sheet
- Product picker bottom sheet
- Send estimate flow (client confirm + project confirm)

### Sprint 4 — Invoices & Payments
- `Invoice`, `InvoiceLineItem`, `Payment` models + DTO + service
- `InvoicesListView`
- `InvoiceDetailView`
- `PaymentRecordSheet`
- Estimate → Invoice conversion (calls Supabase `convert_estimate_to_invoice` RPC)

### Sprint 5 — Products, Accounting, Site Visits
- `Product` model + service
- `ProductsListView` + `ProductFormSheet`
- `AccountingDashboard` (read-only Supabase query)
- `SiteVisit` model + service
- Calendar: `siteVisit` event type rendering
- Project detail: opportunity badge + estimate/invoice strip
- Task detail: source attribution row

### Sprint 6 — Settings, Polish, Tutorial Extensions
- Settings → Integrations (QuickBooks/Sage OAuth WKWebView flow)
- Settings → Products & Services row
- Tutorial system: new phases for Pipeline, Estimate, Invoice (extend existing 25-phase system)
- `TacticalLoadingBar` for all Supabase loading states
- Offline banner component (reusable)
- Full accessibility pass (VoiceOver labels on all new screens)
- Debug dashboard: Supabase connection status

---

## Pre-Implementation Checklist

### Design System Compliance
- [ ] All colors use `OPSStyle.Colors` tokens — no hardcoded hex values
- [ ] `primaryAccent` used on ONE element per screen (FAB or primary button — not both)
- [ ] `warningStatus` and `errorStatus` used only for semantic meaning
- [ ] `pipelineStageColor(for:)` used for all pipeline stage indicators
- [ ] White primary button used for the single most important action per screen

### Typography
- [ ] All titles and section headers UPPERCASE
- [ ] All captions and metadata `[in square brackets]`
- [ ] Mohave for structured/scannable content, Kosugi for narrative
- [ ] No SF Pro anywhere in new views

### Layout & Interaction
- [ ] All touch targets 56pt minimum (FAB 64pt)
- [ ] Primary actions at bottom of screen (sticky footer or FAB)
- [ ] Tab bar not overlapped by scrollable content (bottom safe area padding)
- [ ] Swipe-right/left actions match existing OPS gesture patterns (Job Board)
- [ ] Collapsible sections match existing `ProjectFormSheet` pattern

### Data & Sync
- [ ] All new Supabase reads load from local SwiftData cache first
- [ ] Never show blank screen while syncing — show cached data immediately
- [ ] Offline state: disable write actions only, reads still work
- [ ] All Bubble field additions handled gracefully (optional fields, nil-safe)

### Accessibility
- [ ] All interactive elements have `.accessibilityLabel` descriptions
- [ ] Color is never the only differentiator for state
- [ ] Text contrast meets 7:1 minimum (primaryText on background)
- [ ] Icon-only buttons have accessibility labels

### Role Gating
- [ ] Pipeline tab only renders for Admin / Office Crew roles
- [ ] Products & Services settings row only renders for Admin
- [ ] Integrations settings section only renders for Admin
- [ ] Field crew: zero new UI changes (task attribution badge is the only exception)
