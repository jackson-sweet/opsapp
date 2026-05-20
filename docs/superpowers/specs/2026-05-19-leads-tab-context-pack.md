# LEADS Tab — Engineering Context Pack for Designer

> **Audience:** Front-end designer producing mocks + handoff doc for the OPS iOS LEADS tab.
> **Companion to:** `2026-05-19-leads-tab-design-intent.md` (the design brief itself)
> **Author:** Jackson (via engineering session, 2026-05-19)
> **Honesty rule:** anything not in the codebase is marked `(doesn't exist)`. No invented patterns.

---

## 1 · IOS APP STRUCTURE

### 1.1 Tab bar definition

**File:** `OPS/Views/MainTabView.swift`

The tab bar is **custom**, not Apple's `TabView`. It is rendered by `CustomTabBar` (in `OPS/Views/Components/Common/CustomTabBar.swift`) and overlaid on a `ZStack` that contains the per-tab content. Tab content slides horizontally between tabs (asymmetric `.move` transitions, `spring(response: 0.3, dampingFraction: 0.85)`).

### 1.2 Tab order and icons (all SF Symbols)

Tabs are computed dynamically based on user permissions + feature flags. **Tab 0 is always Home; the last tab is always Settings.** Other tabs may be hidden.

| Index (typical admin) | Tab | SF Symbol icon | Wizard step ID | Gate |
|---|---|---|---|---|
| 0 | HOME | `house.fill` | `welcome_home` | always |
| 1 | LEADS | `point.3.connected.trianglepath.dotted` | `welcome_leads` | `pipeline.view` AND `pipeline` feature flag |
| 2 | BOOKS | `chart.line.uptrend.xyaxis` | `welcome_books` | `finances.view` OR `estimates.view` OR `expenses.view` |
| 3 | JOB BOARD | `briefcase.fill` | `welcome_job_board` | always |
| 4 | CATALOG | `square.stack.3d.up.fill` | `welcome_catalog` | `catalog.view` scope=`all` |
| 5 | SCHEDULE | `calendar` | `welcome_schedule` | always |
| 6 | SETTINGS | `gearshape.fill` | `welcome_settings` | always |

Field crew typically see: HOME / JOB BOARD / SCHEDULE / SETTINGS. Admin see all.

### 1.3 Where a new tab gets registered

In `MainTabView`:

1. **Add a permission gate** (`hasLeadsAccess` is the LEADS example, lines 61–63).
2. **Add a computed tab index** that adapts based on whether prior optional tabs are visible (`leadsTabIndex`, lines 190; `booksTabIndex` lines 191–194; etc.).
3. **Append a `TabItem(iconName:wizardStepId:)`** to the `tabs` computed array (lines 215–248) — order in this array determines tab order.
4. **Extend `tabContent` `@ViewBuilder`** if/else (lines 356–378) to route the new index to the new view.
5. **Extend `analyticsTabName(for:)`** (lines 1021–1030) — maps index → `TabName` analytics enum (in `OPS/Analytics/`).
6. **Extend `wizardTabName(for:)`** (lines 1036–1048) — maps index → wizard-context string. The LEADS tab returns `"Pipeline"` here for backwards-compat with existing wizard scripts.
7. **Extend `WizardNavigateToTarget` switch** (lines 858–883) if the tab is targeted by wizard deep-nav.
8. **Add a permission check** in `MainTabView.onChange(of: permissionStore.permissions)` (lines 994–1002) — reset `selectedTab = 0` if the new tab count contracts below the current selection.

### 1.4 Naming conventions

| Convention | Pattern |
|---|---|
| Tab root view | `<TabName>TabView.swift` (e.g. `LeadsTabView`, `BooksTabView`) or `<TabName>View.swift` (e.g. `JobBoardView`, `ScheduleView`, `HomeView`) |
| Per-section list view | `<Entity>ListView.swift` (e.g. `InvoicesListView`, `EstimatesListView`, `ClientListView`) |
| Detail view | `<Entity>DetailView.swift` (e.g. `LeadDetailView`, `ContactDetailView`) |
| Sheet | `<Verb><Entity>Sheet.swift` (e.g. `AddLeadSheet`, `EditLeadSheet`, `LeadActionSheet`, `LostReasonSheet`) |
| ViewModel | `<Entity>ViewModel.swift` (e.g. `PipelineViewModel`, `LeadDetailViewModel`) |
| Repository (data layer) | `<Entity>Repository.swift` (e.g. `OpportunityRepository`) |
| DTO | `<Entity>DTOs.swift` containing `<Entity>DTO`, `Create<Entity>DTO`, `Update<Entity>DTO` |

### 1.5 Navigation patterns

| Pattern | Use | Example |
|---|---|---|
| `NavigationStack` per tab | Standard push navigation | `LeadsTabView` wraps content in a `NavigationStack`; tap card → push `LeadDetailView` via `.navigationDestination(item:)` |
| `.sheet(isPresented:)` / `.sheet(item:)` | Action menus, forms, contextual content | `LeadActionSheet`, `LostReasonSheet`, `AddLeadSheet`, `ForecastBreakdownSheet` |
| `.fullScreenCover` | Rare — used for camera, immersive flows | Photo capture, scanner |
| `NavigationLink` (push from within stack) | Drill-down from row | Job Board → Project detail |
| Custom paged TabView | Stage carousels, segmented sections | `LeadsTabView` uses `TabView(selection:)` with `.page(indexDisplayMode: .never)` for per-stage paging |
| Split view / sidebar | **(doesn't exist)** — not used on iOS. Phone-only app, portrait only |

### 1.6 Platform

| Property | Value |
|---|---|
| **Min iOS** | **18.2** (release config; debug 18.2). One legacy config has 17.6 for a niche framework target. |
| **UI framework** | **100% SwiftUI** for new screens. UIKit only for narrow integrations (camera, haptics via `UIImpactFeedbackGenerator`, keyboard observers). |
| **Preferred for new screens** | **SwiftUI exclusively.** Including the LEADS tab redesign. |
| **Orientation** | Portrait only. Landscape not supported. |
| **Theme** | **Dark only** — `.preferredColorScheme(.dark)` is forced at the app root. No light theme ships. |
| **Persistence** | **SwiftData `@Model`** classes. Offline-first cache; mutations queue and sync. |
| **Backend** | Supabase (Postgres + Auth + Storage + Realtime). |

---

## 2 · CLOSEST EXISTING TABS TO REFERENCE

### 2.1 BOOKS — the closest structural sibling

LEADS was a segment inside Books until 2026-05-12. The Books tab still uses the **hero carousel + segmented + paged list** pattern that LEADS now uses standalone. Highest-value reference.

**Files:**

| File | Purpose |
|---|---|
| `OPS/Views/Books/BooksTabView.swift` | Root composition |
| `OPS/Views/Books/HeroCarousel.swift` | KPI carousel (sibling of `LeadsHeaderCarousel`) |
| `OPS/Views/Books/CollapsedCarouselStrip.swift` | Sticky strip when carousel scrolls off — same pattern as LEADS' `headerCollapsed` |
| `OPS/Views/Books/BooksSection.swift` | Section enum (estimates / invoices / expenses) — analog to `PipelineStage` |
| `OPS/Views/Books/ARAgingDetailView.swift` | Drill-in from a KPI tile — analog to `ForecastBreakdownSheet` |
| `OPS/Views/Books/Pipeline/*` | **Legacy — being deleted in P1-3.** Pre-promotion pipeline lives here. Don't reference. |

**No empty-state component is shared** — each list view defines its own. Books uses inline `Text` empty states matching the LEADS pattern.

### 2.2 JOB BOARD — multi-section tab with filters

Job Board is a multi-section tab (Projects / Tasks / Clients) with search + filter sheets. Useful reference for filter UI and the per-row card vocabulary.

| File | Purpose |
|---|---|
| `OPS/Views/JobBoard/JobBoardView.swift` | Root — handles section switching |
| `OPS/Views/JobBoard/JobBoardProjectListView.swift` | Project list page |
| `OPS/Views/JobBoard/JobBoardMyTasksView.swift` | Tasks list page |
| `OPS/Views/JobBoard/ClientListView.swift` | Clients list page |
| `OPS/Views/JobBoard/JobBoardKanbanView.swift` | Kanban variant — Projects shown as columns by status |
| `OPS/Views/JobBoard/UniversalJobBoardCard.swift` | Universal row component — used across sections |
| `OPS/Views/JobBoard/UniversalSearchBar.swift` | Search input |
| `OPS/Views/JobBoard/UniversalSearchSheet.swift` | Full search sheet (cross-entity) |
| `OPS/Views/JobBoard/ProjectListFilterSheet.swift` | Filter sheet — Projects |
| `OPS/Views/JobBoard/TaskListFilterSheet.swift` | Filter sheet — Tasks |
| `OPS/Views/JobBoard/SortOptions.swift` | Sort option enum + UI |
| `OPS/Views/JobBoard/ClientSheet.swift` | Client edit modal |

### 2.3 ESTIMATES / INVOICES list — single-entity list pattern

Single-entity, single-list, status-tagged rows. Useful for the per-stage `LeadListPage` row composition.

| File | Purpose |
|---|---|
| `OPS/Views/Estimates/EstimatesListView.swift` | Estimates list |
| `OPS/Views/Invoices/InvoicesListView.swift` | Invoices list |

---

## 3 · SHARED COMPONENTS & TOKENS

### 3.1 Token files (single source of truth)

| File | Contains | Verbatim attached |
|---|---|---|
| `OPS/Styles/OPSStyle.swift` | All colors, spacing, radii, layout, animation, opacity, icon sizes, border widths | YES — §6 below |
| `OPS/Styles/Fonts.swift` | All `Font` role definitions (semantic + legacy aliases) | YES — §6 below |
| `OPS/Styles/Animation+OPS.swift` | Animation curves and durations | Token names: `OPSStyle.Animation.standard`, `.fast`, `.faster`, `.spring`, `.springFast`. Standard curve is `cubic-bezier(0.22, 1, 0.36, 1)` at 250ms. **Spring tokens exist but should not be used outside drag-to-reorder per the design system.** |

**Wiring:** Colors are loaded from the asset catalog (`OPS/Assets.xcassets/Colors/`) via `Color("AccentPrimary")`, `Color("TextPrimary")`, etc. Fonts are loaded by name (`Font.custom("CakeMono-Light", size: 22)`) — no codegen. Tokens are referenced in production code only via `OPSStyle.Colors.*`, `OPSStyle.Typography.*`, `OPSStyle.Layout.*`, `OPSStyle.Animation.*`. **Hardcoded hex / spacing / font names are forbidden in new code.**

### 3.2 Shared component files

**Directory:** `OPS/Styles/Components/`

| File | Components | Use for LEADS |
|---|---|---|
| `ButtonStyles.swift` | `OPSButtonStyle` (struct), `.opsButton(...)` view modifier | Primary / secondary / destructive button styling |
| `OPSComponents.swift` | `OPSPrimaryButton`, `OPSSecondaryButton`, `OPSDestructiveButton` | Pre-composed buttons |
| `StatusBadge.swift` | `StatusBadge(status:color:size:)` — JetBrains Mono 11pt + 15% fill + 30% border + 4pt radius | Stage tags, status chips, urgency chips |
| `CardStyles.swift` | Card view modifiers | Card chrome |
| `SectionCard.swift` | `SectionCard` | L1 section container |
| `IconBadge.swift` | `IconBadge` | Small icon-only badges |
| `ListItems.swift` | List row patterns | Reference for `LeadCard` row layout |
| `InlineTaskRow.swift` | Task row composition | Reference for compact row layout |
| `FormInputs.swift` / `FormTextField.swift` | Text input components | `AddLeadSheet` / `EditLeadSheet` reuse these |
| `SegmentedControl.swift` | OPS segmented control (white-on-white spec, no accent) | Time range / view-mode pickers |
| `OPSActionBar.swift` | Top action bar pattern | Standard sheet header |
| `OPSFloatingButtonBar.swift` | Floating bottom CTA bar | Bottom-anchored primary action |
| `SheetPresentation.swift` / `StandardSheetToolbar.swift` | Sheet styling and toolbar | Sheet chrome conventions |
| `CategoryCard.swift`, `ProfileCard.swift`, `ExpandableSection.swift`, `NotesDisplayField.swift`, `SettingsHeader.swift`, `TaskLineItem.swift` | Other specialized patterns | Reference as needed |

### 3.3 Glass surfaces

| | |
|---|---|
| Spec calls for | `.glass-surface` (L1) — `rgba(18,18,20,0.58)` + `blur(28px) saturate(1.3)` + 0.09 hairline + 10pt radius + top-edge gradient |
| iOS approximation | `OPSStyle.Colors.glassApprox` (flat color) + manual `.background(.ultraThinMaterial)` modifier |
| **Status** | **A unified `.glassSurface()` / `.glassDense()` view modifier was scoped for Phase 4 of the design-system rollout but does not yet exist** (`OPSStyle.swift:186–190` notes it as planned). Designer should treat glass as an aspiration the engineering pass will implement; the current shipping cards use a flat `cardBackground` asset (#191919). |

### 3.4 Fonts in bundle

All three families are **loaded and shipping**. Registered in `OPS/Info.plist` under `UIAppFonts`. Files in `OPS/Styles/Fonts/`:

| Family | Weights present |
|---|---|
| **Mohave** | Light, LightItalic, Regular, Italic, Medium, MediumItalic, SemiBold, SemiBoldItalic, Bold, BoldItalic |
| **JetBrains Mono** | Regular, Medium, Bold |
| **Cake Mono** | Light, Regular, Bold (only Light is used in product UI per spec) |

Kosugi and Bebas Neue were deprecated 2026-04-17 and **removed from the bundle**. Any leftover reference to those families is dead code.

### 3.5 Icon library

| | |
|---|---|
| **iOS** | **SF Symbols.** Used everywhere — tab icons, in-line indicators, buttons, navigation chevrons. Convention: `Image(systemName: "magnifyingglass")` etc. |
| **Web design system** | Lucide (spec'd at `DESIGN.md` §11). |
| **Cross-platform agreement** | Symbol names overlap where possible (e.g. tab icons map roughly to Lucide equivalents) — but iOS is SF Symbols, not Lucide. The designer should pick SF Symbol names for iOS mocks. |
| **No emoji.** Anywhere. Per the design system. | |

---

## 4 · LEADS — DOMAIN MODEL

### 4.1 The model — `Opportunity`

**A `Lead` is an `Opportunity`.** The name `Opportunity` is the canonical entity (matches the Supabase `opportunities` table, the OPS Web app, and the bible). `Lead` is the user-facing label only.

**File:** `OPS/DataModels/Supabase/Opportunity.swift` (SwiftData `@Model`, 47 fields, full schema parity with Postgres). Already exists in production. Schema:

```swift
@Model class Opportunity: Identifiable {
    @Attribute(.unique) var id: String
    var companyId: String

    // Deal identity
    var title: String?
    var contactName: String
    var contactEmail: String?
    var contactPhone: String?
    var descriptionText: String?
    var address: String?

    // Pipeline tracking
    var stage: PipelineStage
    var stageEnteredAt: Date
    var stageManuallySet: Bool
    var assignedTo: String?           // user UUID
    var priority: String?
    var source: String?
    var quoteDeliveryMethod: QuoteDeliveryMethod?

    // Financial
    var estimatedValue: Double?
    var actualValue: Double?
    var winProbabilityOverride: Int?  // server override; falls back to stage default

    // Dates
    var expectedCloseDate: Date?
    var actualCloseDate: Date?
    var nextFollowUpAt: Date?
    var lastActivityAt: Date?

    // Conversion / linking
    var projectId: String?            // populated when WON → converted to project
    var clientId: String?             // populated when associated with an existing client
    var lostReason: String?
    var lostNotes: String?

    // Soft-delete + archive
    var deletedAt: Date?
    var archivedAt: Date?

    // Tags + email source
    var tags: [String]
    var sourceEmailId: String?

    // Message-thread counters (denormalized, written by web only)
    var correspondenceCount: Int
    var outboundCount: Int
    var inboundCount: Int
    var lastInboundAt: Date?
    var lastOutboundAt: Date?
    var lastMessageDirection: String?

    // Timestamps
    var createdAt: Date
    var updatedAt: Date

    // Computed
    var weightedValue: Double         // estimatedValue × winProb / 100
    var daysInStage: Int
    var isStale: Bool                 // daysInStage > stage.staleThresholdDays
    var isDeleted: Bool
    var isArchived: Bool
}
```

### 4.2 Lifecycle / states

**File:** `OPS/DataModels/Enums/PipelineStage.swift`. 8 states:

| Stage | Display | Default win prob | Stale threshold (days) |
|---|---|---|---|
| `newLead` | NEW LEAD | 10% | 3 |
| `qualifying` | QUALIFYING | 20% | 7 |
| `quoting` | QUOTING | 40% | 5 |
| `quoted` | QUOTED | 60% | 7 |
| `followUp` | FOLLOW-UP | 50% | 3 |
| `negotiation` | NEGOTIATION | 75% | 2 |
| `won` | WON | 100% | ∞ |
| `lost` | LOST | 0% | ∞ |

Stages are **states, not steps.** Leads can advance, regress, or jump non-sequentially. The "next stage" arrow exists (`PipelineStage.next`) but is just a UX convenience for swipe-to-advance.

### 4.3 Stage transitions

**Model:** `OPS/DataModels/Supabase/StageTransition.swift` — append-only history.

```swift
@Model class StageTransition {
    var companyId: String
    var opportunityId: String
    var fromStage: PipelineStage?
    var toStage: PipelineStage
    var transitionedAt: Date
    var transitionedBy: String?       // user UUID
    var durationInStage: TimeInterval?
    var createdAt: Date
}
```

Written automatically by `OpportunityRepository.moveToStage` server-side. Read for the detail-view timeline.

### 4.4 Sources

`Opportunity.source: String?` is **free text** — no enum. Conventional values per the bible and existing usage: `"manual"`, `"web_form"`, `"referral"`, `"inbound_call"`, `"email"`. **No iOS UI currently exposes source selection** beyond a free text field in `AddLeadSheet`. The designer can propose an enumerated source picker if useful.

### 4.5 Relationship to `Client` and `Project`

- A `Lead` can optionally reference an existing `Client` via `clientId`. When linked, the lead inherits the client's contact info — but `contactName` / `contactEmail` / `contactPhone` on the opportunity are still required as a frozen snapshot.
- When a lead is **WON**, `markWon` does **NOT** auto-create a `Project`. The `projectId` field is populated by a separate "convert to project" flow which is a stub today (`(doesn't exist as a polished UX)`). Currently `markWon` just sets stage = `.won`, `actualValue`, `actualCloseDate`. Engineering will wire up the project-conversion path when the designer specifies the UX.
- When marked **LOST**, `markLost` sets stage = `.lost`, `lostReason` (enum), `lostNotes` (free text).

**`LossReason` enum** (`OPS/DataModels/Enums/FinancialEnums.swift`): `price`, `timing`, `competition`, `scope`, `noResponse`, `other`. Captured via `LostReasonSheet`.

### 4.6 Child entities

Three child models relate 1:N to `Opportunity`. The current LEADS tab does not surface them on the list view — only in `LeadDetailView`. Designer can decide whether any of these belong on the main tab:

| Model | File | Fields of note |
|---|---|---|
| `Activity` | `OPS/DataModels/Supabase/Activity.swift` | `type: ActivityType` (call / email / sms / visit / note / meeting), `subject`, `bodyText`, `direction` (inbound/outbound), `outcome`, `durationMinutes`, `isRead`, `hasAttachments` |
| `FollowUp` | `OPS/DataModels/Supabase/FollowUp.swift` | `title` (REQUIRED), `type: FollowUpType`, `status: FollowUpStatus`, `dueAt`, `reminderAt`, `assignedTo`, `isOverdue`, `isDueToday`, `completedAt`, `isAutoGenerated`, `triggerSource` |
| `StageTransition` | `OPS/DataModels/Supabase/StageTransition.swift` | (see §4.3) |

### 4.7 API endpoints (Supabase, via repository)

**File:** `OPS/Network/Supabase/Repositories/OpportunityRepository.swift`. All methods are `async throws`, return DTOs, scoped to a `companyId` provided at init.

| Method | Signature | Endpoint |
|---|---|---|
| `fetchAll()` | `async throws -> [OpportunityDTO]` | `SELECT * FROM opportunities WHERE company_id = ? ORDER BY created_at DESC` |
| `fetchOne(id)` | `async throws -> OpportunityDTO` | `SELECT * FROM opportunities WHERE id = ?` |
| `fetchActivities(for: id)` | `async throws -> [ActivityDTO]` | `SELECT * FROM activities WHERE opportunity_id = ?` |
| `fetchFollowUps(for: id)` | `async throws -> [FollowUpDTO]` | `SELECT * FROM follow_ups WHERE opportunity_id = ?` |
| `fetchStageTransitions(for: id)` | `async throws -> [StageTransitionDTO]` | `SELECT * FROM stage_transitions WHERE opportunity_id = ?` |
| `create(dto: CreateOpportunityDTO)` | `async throws -> OpportunityDTO` | `INSERT INTO opportunities ...` |
| `logActivity(dto: CreateActivityDTO)` | `async throws -> ActivityDTO` | `INSERT INTO activities ...` |
| `createFollowUp(dto: CreateFollowUpDTO)` | `async throws -> FollowUpDTO` | `INSERT INTO follow_ups ...` |
| `moveToStage(id, to:, userId:)` | `async throws -> OpportunityDTO` | `UPDATE opportunities SET stage = ?, stage_entered_at = now()` + side-effect `INSERT INTO stage_transitions` |
| `markWon(id, actualValue, projectId, userId)` | `async throws -> OpportunityDTO` | `moveToStage(...won)` + sets `actualValue`, `actualCloseDate` |
| `markLost(id, reason: LossReason, notes, userId)` | `async throws -> OpportunityDTO` | `moveToStage(...lost)` + sets `lostReason`, `lostNotes` |
| `update(id, fields: UpdateOpportunityDTO)` | `async throws -> OpportunityDTO` | partial patch |
| `softDelete(id)` | `async throws` | sets `deleted_at = now()` |
| `archive(id)` | `async throws` | sets `archived_at = now()` |
| `unarchive(id)` | `async throws` | clears `archived_at` |

**Sync behavior:** mutations are optimistic — the UI updates the local SwiftData store immediately, then enqueues the change in the sync engine. Failures surface on the affected row, not as a global banner. Pending writes show an inline `// OFFLINE — TRY AGAIN` marker.

### 4.8 ViewModels

| ViewModel | File | Use |
|---|---|---|
| `PipelineViewModel` | `OPS/ViewModels/PipelineViewModel.swift` | Tab-level. Loads opportunities, derives per-stage counts, "ball in court" buckets, forecast, close rate, stale risk |
| `LeadDetailViewModel` | `OPS/ViewModels/LeadDetailViewModel.swift` | Detail-view. Loads activities + follow-ups + stage transitions for a single opportunity |

---

## 5 · PRODUCT INTENT

### 5.1 Authoritative docs

| Doc | Status |
|---|---|
| `docs/superpowers/specs/2026-05-11-pipeline-tab-design.md` | Phase 1 design spec. **Already shipped to main** (2026-05-12, commit range `0c684c3..ce2c3ca` + tab wiring). Describes the current implementation in detail. |
| `docs/superpowers/specs/2026-05-19-leads-tab-design-intent.md` | **The design brief.** Read this first — it is the operative intent doc for your work. |
| `docs/superpowers/plans/2026-05-11-pipeline-tab.md` | Implementation plan for Phase 1 — historical reference only. |
| `ops-software-bible/09_FINANCIAL_SYSTEM.md` § Pipeline Stages | Authoritative business logic (stage definitions, win prob, stale thresholds) — synced to PipelineStage enum |

**(No Linear / Jira / Notion ticket exists)** — OPS uses spec docs as the system of record. The driver is Jackson (CEO / sole developer) via paired sessions with Claude.

### 5.2 Why this redesign

The LEADS tab shipped Phase 1 on 2026-05-12 to main. A redesign is being commissioned now because:

1. **UX issues observed in the field** — see open issues in the design intent doc (§16).
2. **Design system drift** — the shipped LEADS tab uses several patterns now explicitly banned in `mobile/MOBILE.md` (released today) — see design-intent §10.
3. **The user wants a designer-led rethink** before further investment.

### 5.3 Day-1 actions the tab must support

| Action | Currently shipped? | Notes |
|---|---|---|
| Triage at a glance — see what needs my attention today | ✓ Yes (BallInCourtBar) | Designer can rework |
| See forecast / close rate / pipeline health | ✓ Yes (LeadsHeaderCarousel) | Designer can rework |
| Navigate to a specific stage | ✓ Yes (LeadStageStrip + paged TabView) | Designer can rework |
| Advance a lead one stage | ✓ Yes (leading swipe) | Keep or replace |
| Mark won / lost | ✓ Yes (trailing swipe) | Keep or replace |
| Open lead detail | ✓ Yes (tap row → push) | |
| Tap-to-call a lead | ✓ Yes (in LeadDetailView, not on the list) | Could surface on the list |
| Tap-to-email a lead | ✓ Yes (in LeadDetailView) | |
| Tap-to-message a lead | ✓ Yes (in LeadDetailView) | |
| Log an activity (call / email / visit / note) | ✓ Yes (in LeadDetailView via `LeadLogActivitySheet`) | |
| Schedule a follow-up | ✓ Yes (in LeadDetailView via `AddFollowUpSheet`) | |
| Convert WON lead → Project | **Partial** — `projectId` field exists but no polished conversion flow on iOS | Designer should propose the UX |
| Assign lead to a teammate | ✓ Yes (`assignedTo`, in `EditLeadSheet`) | |
| Archive / soft-delete a lead | ✓ Yes (long-press → `LeadActionSheet`) | |
| Add a new lead | ✓ Yes (FAB MONEY group → "ADD LEAD" → `AddLeadSheet`) | Designer can propose alternative entry point |
| Search across leads | **(doesn't exist as a dedicated LEADS-tab search)** — universal search sheet exists in `JobBoard/UniversalSearchSheet.swift` but is cross-entity. Designer can decide if LEADS needs its own. | |
| Sort / filter the list | **Partial** — only in-court filter exists. No multi-filter (by source, by tag, by assignee, etc.). Designer can propose. | |

### 5.4 Constraints

| | |
|---|---|
| **Offline** | Full read from SwiftData cache. Writes queue. Critical for a contractor in spotty signal. |
| **Push notifications** | Existing push types: `OpenProjectDetails`, `OpenTaskDetails`, `OpenClientDetails`, `OpenInvoiceDetails`, `OpenEstimateDetails`. **No `OpenLeadDetails` push exists yet** — would be added when the designer/engineering specs the trigger conditions (e.g. assigned-lead, overdue-follow-up). |
| **Deep links** | Universal links / push / Spotlight all route through `MainTabView` `.onReceive` listeners. The LEADS tab can be deep-linked-to by posting `WizardNavigateToTarget` with `tabTarget: "Pipeline"`. Per-lead deep links would need a new notification name. |
| **Permissions** | Tab gated on `pipeline.view` + `pipeline` feature flag. Within the tab: `pipeline.manage` gates state mutations (advance / won / lost / edit / delete). Read-only operators see no swipe actions. |
| **Roles** | `admin`, `office_crew`, `operator`, `crew`, `unassigned`. LEADS access typically: admin + office_crew + operator. Crew (field workers) usually don't see LEADS. |
| **Localization** | English only. `LOCALIZATION_PREFERS_STRING_CATALOGS = YES` is set in build config but no other languages ship. |
| **Dynamic Type** | Respected. Minimum body 16pt. The designer should ensure all key copy survives ≥ XL accessibility size. |

### 5.5 Existing FAB integration

The Floating Action Menu (`OPS/Views/Components/FloatingActionMenu.swift`) has 4 groups: MONEY / JOBS / SCHEDULE / CATALOG. When the user is on the LEADS tab (`isLeadsTab`), the MONEY group reorders so **"ADD LEAD" surfaces first**. This is the current "new lead" entry point. The designer can propose an alternative (in-screen primary CTA, header button) if useful.

---

## 6 · DESIGN SYSTEM STATUS

### 6.1 Last design system version referenced in iOS code

| Reference in iOS code | Version stamp |
|---|---|
| `OPS/Styles/OPSStyle.swift:12` | `spec v2 (2026-04-17)` |
| `OPS/Styles/Fonts.swift:5` | `spec v2 (2026-04-17)` |

**iOS is referenced against v2 (2026-04-17).** That matches the `README.md` and `DESIGN.md` version stamp in `ops-design-system/project/`.

**However**, `ops-design-system/project/mobile/MOBILE.md` (28KB, iOS-specific overrides) was freshly added — every file in the design-system directory is timestamped `2026-05-19 12:30`. `MOBILE.md` introduces mobile-specific tokens, surface hierarchy (L0/L1/L2/L3), hero carousel spec, scrolling-tabs spec, and several other patterns that **iOS code has not yet adopted**. The design intent doc §10 enumerates current iOS drift against `MOBILE.md`.

### 6.2 Current iOS token files — verbatim

**Attached as files, not pasted here, because they are 700+ lines combined:**

| File | Path | What's in it |
|---|---|---|
| Colors / layout / animation | `OPS/Styles/OPSStyle.swift` | Full token enum tree |
| Typography | `OPS/Styles/Fonts.swift` | All font roles |

**Both files are on `main` as of 2026-05-19.** The designer should fetch the current versions and diff against `ops-design-system/project/colors_and_type.css` + `mobile/MOBILE.md`. Known drifts highlighted in the design intent doc §10.

### 6.3 Asset catalog color names

iOS colors are loaded via `Color("AssetName")`. The names in use on the LEADS tab and adjacent code:

| Asset name | Hex |
|---|---|
| `AccentPrimary` | `#6F94B0` steel blue |
| `AccentSecondary` | `#C4A868` tan |
| `Background` | `#000000` |
| `CardBackground` | `#191919` (flat — pre-glass approximation) |
| `CardBackgroundDark` | `#0D0D0D` (deprecated) |
| `DarkBackground` | `#090C15` (deprecated) |
| `StatusBackground` | `#1D1D1D` (deprecated) |
| `TextPrimary` | `#EDEDED` |
| `TextSecondary` | `#B5B5B5` |
| `TextTertiary` | `#8A8A8A` |
| `TextInactive` | `#6A6A6A` (decorative only) |
| `StatusSuccess` | `#9DB582` olive |
| `StatusWarning` | `#C4A868` tan |
| `StatusError` | `#93321A` brick |
| `StatusInactive` | `#8E8E93` |
| `Rose` | `#B58289` |
| `FinReceivables` | `#D4A574` |

Asset catalog at: `OPS/Assets.xcassets/`.

### 6.4 Specific token name to reach for in mocks

For mocks that label tokens, use these Swift names so engineering can implement 1:1 without translation:

```swift
// COLORS
OPSStyle.Colors.opsAccent       // steel blue, CTA + focus only
OPSStyle.Colors.text            // #EDEDED primary
OPSStyle.Colors.text2           // #B5B5B5 secondary
OPSStyle.Colors.text3           // #8A8A8A metadata
OPSStyle.Colors.textMute        // #6A6A6A decorative // and separators only
OPSStyle.Colors.olive           // #9DB582 success
OPSStyle.Colors.tan             // #C4A868 attention
OPSStyle.Colors.rose            // #B58289 negative (foreground)
OPSStyle.Colors.brick           // #93321A destructive border/dot only
OPSStyle.Colors.background      // pure black canvas
OPSStyle.Colors.cardBackground  // flat dark card (legacy — should migrate to glass)
OPSStyle.Colors.line            // 0.10 white hairline
OPSStyle.Colors.glassBorder     // 0.09 white glass edge
OPSStyle.Colors.surfaceInput    // 0.04 white input fill
OPSStyle.Colors.surfaceHover    // 0.05 white interactive hover
OPSStyle.Colors.surfaceActive   // 0.08 white pressed/active

// Pipeline stage colors (NEW v2 — six-step earth-tone gradient + olive/rose terminal)
OPSStyle.Colors.pipelineStageColor(for: stage)  // canonical entry point

// TYPOGRAPHY (new spec-v2 names)
OPSStyle.Typography.hero        // Mohave Light 80
OPSStyle.Typography.pageTitle   // Cake Mono Light 22
OPSStyle.Typography.display     // Cake Mono Light 30
OPSStyle.Typography.section     // Cake Mono Light 18
OPSStyle.Typography.buttonLabel // Cake Mono Light 14
OPSStyle.Typography.badgeCake   // Cake Mono Light 11
OPSStyle.Typography.panelTitle  // JetBrains Mono 11
OPSStyle.Typography.dataValueLg // JetBrains Mono Medium 20
OPSStyle.Typography.dataValue   // JetBrains Mono 13
OPSStyle.Typography.category    // JetBrains Mono 11
OPSStyle.Typography.metadata    // JetBrains Mono 11
OPSStyle.Typography.body        // Mohave Regular 16
OPSStyle.Typography.bodyBold    // Mohave Medium 16

// SPACING (8pt base)
OPSStyle.Layout.spacing1   // 4
OPSStyle.Layout.spacing2   // 8
OPSStyle.Layout.spacing2_5 // 12
OPSStyle.Layout.spacing3   // 16
OPSStyle.Layout.spacing3_5 // 20
OPSStyle.Layout.spacing4   // 24
OPSStyle.Layout.spacing5   // 32

// RADIUS
OPSStyle.Layout.panelRadius        // 10 — cards, widgets
OPSStyle.Layout.modalRadius        // 12 — sheets, popovers
OPSStyle.Layout.chipRadius         // 4 — tags, badges
OPSStyle.Layout.progressBarRadius  // 2

// TOUCH TARGETS
OPSStyle.Layout.touchTargetMin       // 44
OPSStyle.Layout.touchTargetStandard  // 56
OPSStyle.Layout.touchTargetLarge     // 64

// MOTION
OPSStyle.Animation.standard  // timingCurve(0.22, 1, 0.36, 1) duration 250
OPSStyle.Animation.fast      // easeInOut 200
OPSStyle.Animation.faster    // easeOut 150
// NOTE: spring / springFast exist but are forbidden per spec (drag-to-reorder exception only)
```

---

## 7 · GAPS — what doesn't exist yet

The designer asked us to be explicit about gaps. These are real and the designer should design around them or include them in the deliverable:

| Gap | Status | Implications |
|---|---|---|
| Universal LEADS search (in-tab) | **(doesn't exist)** — only cross-entity universal search via JobBoard | Designer can add a per-tab search affordance or rely on universal |
| Multi-filter for the list (by source / tag / assignee / value range) | **(doesn't exist)** — only "in-court" filter | Designer can spec a filter sheet pattern; engineering will implement |
| Sort options for the list | **(doesn't exist)** — current sort is hardcoded (stale first, then lastActivityAt desc) | Designer can spec a sort sheet |
| "Convert lead to project" polished UX | **(doesn't exist)** — `projectId` field exists but no user flow | Critical when designing the WON commit moment |
| Per-lead push notifications | **(doesn't exist)** — pushes exist for project / task / client / invoice / estimate, not for lead | If the design uses pushes (overdue follow-up reminders, etc.), engineering will add the push types |
| Lead-specific deep links | **(doesn't exist)** — only tab-level (`Pipeline`) deep link | Per-lead deep links would need a new notification name + handler |
| Unified `.glassSurface()` / `.glassDense()` SwiftUI modifier | **(scoped, not built)** — flat `cardBackground` color used in shipping code | Glass treatment is an aspiration; engineering will implement when the designer commits to it |
| `avgVelocityDays` + `weightedForecastDelta` providers | **VM has the slots, no data pipeline** | The VELOCITY tile and FORECAST delta render empty today. Designer should plan as if they will exist; engineering will wire up |
| Custom carousel page indicators (per spec — 6pt active in text-3, 4pt inactive) | **(doesn't match spec — current uses primaryAccent)** | Designer should re-spec |
| Scrolling-tabs underline in white (per spec — current uses primaryAccent) | **(doesn't match spec)** | Designer should re-spec |
| Stage color identity that doesn't violate "rounded-card + colored-rail" anti-pattern | **(currently violates)** | Designer should propose a replacement or accept the anti-pattern with a written reason |
| iOS Lucide icon set | **(doesn't exist)** — SF Symbols used instead | Designer should use SF Symbols for iOS mocks |
| Light theme | **(doesn't exist — and never will)** | Dark only |
| iPad / landscape layouts | **(doesn't exist)** | Portrait phone only |

---

## 8 · FILE TREE — at-a-glance map

```
OPS/
├── Views/
│   ├── Leads/                                  ← LEADS surface (what you're designing)
│   │   ├── LeadsTabView.swift
│   │   ├── LeadsHeaderCarousel.swift
│   │   ├── BallInCourtBar.swift
│   │   ├── LeadListPage.swift
│   │   ├── LeadsPreviewSupport.swift           ← Xcode Previews scaffolding (DEBUG)
│   │   └── Components/
│   │       ├── LeadCard.swift
│   │       ├── LeadStageStrip.swift
│   │       └── ForecastBreakdownSheet.swift
│   ├── Books/
│   │   ├── BooksTabView.swift                  ← closest structural sibling
│   │   ├── HeroCarousel.swift
│   │   ├── CollapsedCarouselStrip.swift
│   │   ├── BooksSection.swift
│   │   └── Pipeline/                           ← LEGACY (being deleted P1-3)
│   ├── JobBoard/                               ← reference for filter/search/list patterns
│   ├── Estimates/EstimatesListView.swift
│   ├── Invoices/InvoicesListView.swift
│   ├── MainTabView.swift                       ← tab registration
│   └── Components/
│       └── Common/
│           ├── AppHeader.swift                 ← persistent header (case .leads exists)
│           └── CustomTabBar.swift              ← bottom tab bar
├── Styles/
│   ├── OPSStyle.swift                          ← tokens
│   ├── Fonts.swift                             ← typography
│   ├── Animation+OPS.swift
│   ├── Fonts/                                  ← Mohave / JBM / Cake Mono .ttf
│   └── Components/                             ← shared components (see §3.2)
├── DataModels/
│   ├── Supabase/
│   │   ├── Opportunity.swift                   ← LEAD model
│   │   ├── Activity.swift
│   │   ├── FollowUp.swift
│   │   ├── StageTransition.swift
│   │   └── SiteVisit.swift
│   └── Enums/
│       ├── PipelineStage.swift                 ← 8 stages
│       ├── PipelineStage+Color.swift           ← bible palette (drift vs OPSStyle v2 — see design intent §10)
│       └── FinancialEnums.swift                ← LossReason
├── ViewModels/
│   ├── PipelineViewModel.swift                 ← tab VM
│   └── LeadDetailViewModel.swift               ← detail VM
└── Network/
    └── Supabase/
        ├── Repositories/OpportunityRepository.swift
        └── DTOs/OpportunityDTOs.swift

ops-design-system/project/                       ← the design system
├── SKILL.md
├── README.md
├── DESIGN.md
├── colors_and_type.css
└── mobile/
    ├── MOBILE.md                                ← iOS-specific overrides (operative for you)
    └── OPS Mobile System.html

docs/superpowers/specs/
├── 2026-05-11-pipeline-tab-design.md            ← shipped Phase 1 spec
├── 2026-05-19-leads-tab-design-intent.md        ← your brief
└── 2026-05-19-leads-tab-context-pack.md         ← this file
```

---

## 9 · WHAT TO ATTACH WITH THIS RESPONSE

For the designer, alongside this doc, share:

1. `OPS/Styles/OPSStyle.swift` (~590 lines) — full token enum
2. `OPS/Styles/Fonts.swift` (~235 lines) — typography roles
3. `OPS/DataModels/Supabase/Opportunity.swift` — model schema
4. `OPS/DataModels/Enums/PipelineStage.swift` — stage enum with helpers
5. `OPS/ViewModels/PipelineViewModel.swift` — all derived signals
6. `OPS/Network/Supabase/Repositories/OpportunityRepository.swift` — API surface
7. `OPS/Network/Supabase/DTOs/OpportunityDTOs.swift` — wire format
8. The full design intent doc: `docs/superpowers/specs/2026-05-19-leads-tab-design-intent.md`
9. The current LEADS view files (in `OPS/Views/Leads/`) for reference of the shipped Phase 1
10. `ops-design-system/project/DESIGN.md` and `ops-design-system/project/mobile/MOBILE.md`
