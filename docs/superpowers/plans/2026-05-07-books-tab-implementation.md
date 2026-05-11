# BOOKS Tab — Phase 1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the mislabeled "Pipeline" tab with a `BOOKS` hub tab containing a financial dashboard at top + a 4-segment underline control (Pipeline · Estimates · Invoices · Expenses). Pipeline section is built from scratch using a Stage-Pager pattern. Reuses existing list views for the other three segments.

**Architecture:** Single tab containing one composable hub. Pipeline section is a new SwiftUI surface backed by a fully-rebuilt `OpportunityRepository` and an extended `Opportunity`/`StageTransition`/`Activity`/`FollowUp` SwiftData layer. Atomic stage moves go through a new Postgres RPC (`move_opportunity_stage`). Permission gating uses existing keys (`pipeline.view`/`manage`, `finances.view`, `estimates.view`, `expenses.view`). Adaptive routing skips the hub when the user has only one segment permission.

**Tech Stack:** SwiftUI · SwiftData · Supabase Swift client · Combine · XCTest. iOS-only. Per CLAUDE.md, build with `xcodebuild -scheme OPS -destination 'generic/platform=iOS'` (never simulator).

**Spec:** [`docs/superpowers/specs/2026-05-07-books-tab-design.md`](../specs/2026-05-07-books-tab-design.md)

**Phase 1 scope:** BOOKS shell + Pipeline section + dashboard extensions + AR aging drilldown + FAB integration. **Phase 2** (separate plan): build `InvoiceFormSheet` and `RecordPaymentSheet` to wire the still-broken FAB items.

---

## File Structure

### New files

| Path | Responsibility |
|---|---|
| `OPS/Views/Books/BooksTabView.swift` | Hub container — AppHeader, MoneyDashboardHeader, segmented control, segment routing. Replaces `MoneyTabView`. |
| `OPS/Views/Books/BooksSection.swift` | `enum BooksSection { pipeline, estimates, invoices, expenses }` + segment metadata. |
| `OPS/Views/Books/Pipeline/PipelineSectionView.swift` | Pipeline segment root — composes StageStripView + lead list + empty/loading/error states. |
| `OPS/Views/Books/Pipeline/StageStripView.swift` | Horizontal pinned stage strip with terminal-stage divider. |
| `OPS/Views/Books/Pipeline/LeadCardView.swift` | Per-lead card with title, value, days-in-stage, stale indicator, inline action chips. |
| `OPS/Views/Books/Pipeline/LeadActionSheet.swift` | Bottom sheet for `⋯` actions (move-to, edit, log activity, add follow-up, archive, delete). |
| `OPS/Views/Books/Pipeline/AddLeadSheet.swift` | Modal for creating a new opportunity. |
| `OPS/Views/Books/Pipeline/LostReasonSheet.swift` | Modal that captures `lost_reason` + optional `lost_notes`. |
| `OPS/Views/Books/Pipeline/LeadDetailView.swift` | Full-screen NavigationLink push: header, quick actions, stage actions, activity log, follow-ups, stage history. |
| `OPS/Views/Books/Pipeline/EditLeadSheet.swift` | Modal for editing a lead (same field set as Add Lead + force-stage picker). |
| `OPS/Views/Books/Pipeline/LogActivitySheet.swift` | Modal for adding an activity to a lead (note / call / email / meeting / site visit). |
| `OPS/Views/Books/Pipeline/AddFollowUpSheet.swift` | Modal for adding a follow-up to a lead. |
| `OPS/Views/Books/ARAgingDetailView.swift` | Replaces orphan AccountingDashboard — AR aging chart + top outstanding clients. Tapped from SmartStatCarousel "OVERDUE" stat. |
| `OPS/ViewModels/PipelineViewModel.swift` | Loads opportunities for a company, filters by stage, sorts by stale-first then last-activity desc. |
| `OPS/ViewModels/LeadDetailViewModel.swift` | Loads activities, follow-ups, stage transitions for one opportunity. |
| (no new files — additions to existing `OPS/DataModels/Enums/FinancialEnums.swift`) | Add `OpportunitySource` + `LossReason` enums alongside existing `FollowUpType`, `FollowUpStatus`, `QuoteDeliveryMethod`. |
| `OPSTests/Pipeline/OpportunityDTOTests.swift` | Unit tests for new DTO encode/decode. |
| `OPSTests/Pipeline/PipelineViewModelTests.swift` | Unit tests for stale/sort logic. |

### Modified files

| Path | Change |
|---|---|
| `OPS/Views/MainTabView.swift:226` | Render `BooksTabView()` instead of `MoneyTabView()`. |
| `OPS/Views/Components/Common/AppHeader.swift` | Add `case books` to `HeaderType` enum + title "BOOKS". |
| `OPS/DataModels/Supabase/Opportunity.swift` | Additive: `title`, `assignedTo`, `priority`, `actualValue`, `winProbabilityOverride`, `expectedCloseDate`, `actualCloseDate`, `stageEnteredAt`, `lostNotes`, `address`, `nextFollowUpAt`, `tags`, `deletedAt`, `archivedAt`, `stageManuallySet`, `sourceEmailId`, `correspondenceCount`, `outboundCount`, `inboundCount`, `lastInboundAt`, `lastOutboundAt`, `lastMessageDirection`. |
| `OPS/DataModels/Supabase/StageTransition.swift` | Additive: `companyId`, `transitionedAt`, `durationInStage`. |
| `OPS/DataModels/Supabase/Activity.swift` | Additive: `subject`, `bodyText`, `direction`, `outcome`, `durationMinutes`, `isRead`, `hasAttachments`, `attachmentCount`. (Defer email/classification fields.) |
| `OPS/DataModels/Supabase/FollowUp.swift` | **Bug fix:** rename `notes` → `description`. Additive: `title` (required), `completedAt`, `completionNotes`, `createdBy`, `isAutoGenerated`, `reminderAt`, `triggerSource`. |
| `OPS/Network/Supabase/DTOs/OpportunityDTOs.swift` | Full rewrite: `OpportunityDTO`, `CreateOpportunityDTO`, `UpdateOpportunityDTO`, `ActivityDTO`, `CreateActivityDTO`, `FollowUpDTO`, `CreateFollowUpDTO` (BUG FIX), `StageTransitionDTO` (new). |
| `OPS/Network/Supabase/Repositories/OpportunityRepository.swift` | Replace `delete()` with soft-delete. Add `moveToStage()` via RPC. Add `archive()`. Add `fetchStageTransitions(for:)`. Filter `fetchAll()` to exclude soft-deleted. Fix `createFollowUp` to send `title`. |
| `OPS/ViewModels/MoneyDashboardViewModel.swift` | Add opportunity load + pipeline metrics (`activeLeadCount`, `weightedForecastValue`, `staleLeadsCount`, `nextFollowUpDue`). Gate pipeline load on `pipeline.view`. Gate financial metrics on `finances.view`. |
| `OPS/Views/Money/Components/SmartStatCarousel.swift` | Add 3 new `StatType` cases (`activeLeads`, `staleLeads`, `nextFollowUp`) + 3 optional init params. Update `orderedCards` priority logic. |
| `OPS/Views/Money/Components/MoneyDashboardHeader.swift` | Pass new pipeline data + onStatTap routes for `activeLeads`/`staleLeads`/`nextFollowUp`/`overdue` (the latter opens `ARAgingDetailView`). |
| `OPS/Views/Components/FloatingActionMenu.swift` | Add `@AppStorage("books.selectedSegment")`. Add "Add Lead" item under MONEY group (gated by `pipeline.manage`). Reorder MONEY group items based on active BOOKS segment. Wire `showingAddLead` sheet. |
| `OPS/DataModels/Supabase/Activity.swift` | Replace iOS `body` field with `bodyText` (matching DB primary `body_text`). |

### Deleted files

| Path | Why |
|---|---|
| `OPS/Views/Accounting/AccountingDashboard.swift` | Orphan. Replaced by `ARAgingDetailView` (smaller, drill-down only). |
| `OPS/Views/Money/MoneyTabView.swift` | Replaced by `BooksTabView`. |
| `OPS/Views/Money/` directory itself stays (still hosts `MoneyDashboardHeader.swift` + components). |

### Database / RPC

| Object | Change |
|---|---|
| `move_opportunity_stage(opportunity_id uuid, to_stage text, user_id uuid)` | New Postgres function (transactional): UPDATE opportunities set stage + stage_entered_at + stage_manually_set, INSERT stage_transitions row with computed duration_in_stage. Returns the updated opportunity. |

---

## Conventions

- **Build verification:** Always `xcodebuild -scheme OPS -destination 'generic/platform=iOS' build` (never simulator). Per CLAUDE.md.
- **Tests:** XCTest. Test files under `OPSTests/Pipeline/`. Unit tests focus on DTO codecs and ViewModel logic. SwiftUI views are structurally verified by build + manual test plan (no snapshot/UI test suite exists in this project).
- **Commits:** Atomic, descriptive, never include Claude as co-author. Per `ops-ios/CLAUDE.md`.
- **Tokens:** Every color/spacing/typography/animation must use `OPSStyle.*`. No hardcoded values.
- **Dates:** Use `SupabaseDate.parse()` / `SupabaseDate.format()` (existing utility).

---

## Phase 1A — Data Layer Foundation

### Task 1: Add OpportunitySource + LossReason enums

**Files:**
- Modify: `OPS/DataModels/Enums/FinancialEnums.swift` (append at end of file)

- [x] **Step 1: Open the file and verify current contents end with `QuoteDeliveryMethod`**

Run: `tail -20 OPS/DataModels/Enums/FinancialEnums.swift`
Expected: shows `enum QuoteDeliveryMethod` declaration.

(Drift: file actually ends with `AccountingSyncStatus`, not `QuoteDeliveryMethod`. Appended new enums at end of file regardless.)

- [x] **Step 2: Append the two new enums**

Add at end of file:

```swift
// MARK: - Opportunity Source

/// Where a pipeline opportunity came from. Mirrors bible §9.85 source enum.
enum OpportunitySource: String, Codable, CaseIterable, Identifiable {
    case referral     = "referral"
    case website      = "website"
    case email        = "email"
    case phone        = "phone"
    case walkIn       = "walk_in"
    case socialMedia  = "social_media"
    case repeatClient = "repeat_client"
    case other        = "other"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .referral:     return "REFERRAL"
        case .website:      return "WEBSITE"
        case .email:        return "EMAIL"
        case .phone:        return "PHONE"
        case .walkIn:       return "WALK-IN"
        case .socialMedia:  return "SOCIAL MEDIA"
        case .repeatClient: return "REPEAT CLIENT"
        case .other:        return "OTHER"
        }
    }
}

// MARK: - Loss Reason

/// Why a pipeline opportunity was marked Lost. Used by LostReasonSheet.
enum LossReason: String, Codable, CaseIterable, Identifiable {
    case price       = "price"
    case timing      = "timing"
    case competition = "competition"
    case scope       = "scope"
    case noResponse  = "no_response"
    case other       = "other"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .price:       return "PRICE"
        case .timing:      return "TIMING"
        case .competition: return "COMPETITION"
        case .scope:       return "SCOPE"
        case .noResponse:  return "NO RESPONSE"
        case .other:       return "OTHER"
        }
    }
}
```

- [x] **Step 3: Build to verify**

Run: `xcodebuild -scheme OPS -destination 'generic/platform=iOS' build 2>&1 | tail -20`
Expected: BUILD SUCCEEDED.

- [x] **Step 4: Commit**

```bash
git add OPS/DataModels/Enums/FinancialEnums.swift
git commit -m "Add OpportunitySource and LossReason enums for pipeline forms"
```

---

### Task 2: Create Postgres RPC `move_opportunity_stage`

**Files:**
- Create migration: `ops-software-bible/migrations/2026-05-07-01-move-opportunity-stage-rpc.sql`
- Apply via Supabase MCP `apply_migration` against project `ijeekuhbatykdomumfjx` (ops-app)

- [ ] **Step 1: Write the migration SQL**

Create `ops-software-bible/migrations/2026-05-07-01-move-opportunity-stage-rpc.sql`:

```sql
-- Atomic stage move for pipeline opportunities.
-- Updates stage / stage_entered_at / stage_manually_set on opportunities,
-- AND inserts a stage_transitions row capturing duration_in_stage.
-- Returns the updated opportunity row.

CREATE OR REPLACE FUNCTION public.move_opportunity_stage(
  p_opportunity_id uuid,
  p_to_stage text,
  p_user_id uuid
)
RETURNS opportunities
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public
AS $$
DECLARE
  v_company_id uuid;
  v_from_stage text;
  v_prior_entered_at timestamptz;
  v_now timestamptz := now();
  v_updated opportunities;
BEGIN
  -- Read current state. RLS will reject if caller can't see this row.
  SELECT company_id, stage, stage_entered_at
    INTO v_company_id, v_from_stage, v_prior_entered_at
    FROM opportunities
   WHERE id = p_opportunity_id
     AND deleted_at IS NULL;

  IF v_company_id IS NULL THEN
    RAISE EXCEPTION 'opportunity_not_found' USING ERRCODE = 'P0002';
  END IF;

  -- No-op if already in the target stage; still return the row.
  IF v_from_stage = p_to_stage THEN
    SELECT * INTO v_updated FROM opportunities WHERE id = p_opportunity_id;
    RETURN v_updated;
  END IF;

  -- Update opportunity: stage + stage_entered_at + manually_set flag.
  UPDATE opportunities
     SET stage              = p_to_stage,
         stage_entered_at   = v_now,
         stage_manually_set = true,
         updated_at         = v_now
   WHERE id = p_opportunity_id
   RETURNING * INTO v_updated;

  -- Insert immutable transition row.
  INSERT INTO stage_transitions (
    company_id, opportunity_id, from_stage, to_stage,
    transitioned_at, transitioned_by, duration_in_stage
  ) VALUES (
    v_company_id, p_opportunity_id, v_from_stage, p_to_stage,
    v_now, p_user_id, v_now - v_prior_entered_at
  );

  RETURN v_updated;
END;
$$;

GRANT EXECUTE ON FUNCTION public.move_opportunity_stage(uuid, text, uuid) TO authenticated;
```

- [ ] **Step 2: Apply the migration via Supabase MCP**

Use the Supabase MCP `apply_migration` tool with:
- `project_id`: `ijeekuhbatykdomumfjx`
- `name`: `move_opportunity_stage_rpc`
- `query`: the SQL above

Expected: success response.

- [ ] **Step 3: Smoke-test the RPC manually**

Use Supabase MCP `execute_sql` to verify the function exists:

```sql
SELECT proname, pronargs FROM pg_proc WHERE proname = 'move_opportunity_stage';
```
Expected: one row, pronargs = 3.

- [ ] **Step 4: Commit migration file**

```bash
git add ops-software-bible/migrations/2026-05-07-01-move-opportunity-stage-rpc.sql
git commit -m "Add move_opportunity_stage RPC for atomic pipeline stage transitions"
```

---

### Task 3: Extend `Opportunity` SwiftData model (additive)

**Files:**
- Modify: `OPS/DataModels/Supabase/Opportunity.swift`

- [ ] **Step 1: Read current model**

Run: `cat OPS/DataModels/Supabase/Opportunity.swift`
Expected: 58 lines with the 16 existing fields.

- [ ] **Step 2: Replace file contents**

Replace the entire file with:

```swift
//
//  Opportunity.swift
//  OPS
//
//  Pipeline deal — Supabase-backed.
//  Schema parity with public.opportunities (47 cols). Phase 1 defers AI/location/images.
//

import SwiftData
import Foundation

@Model
class Opportunity: Identifiable {
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
    var assignedTo: String?
    var priority: String?
    var source: String?
    var quoteDeliveryMethod: QuoteDeliveryMethod?

    // Financial
    var estimatedValue: Double?
    var actualValue: Double?
    var winProbabilityOverride: Int?       // optional server override; falls back to stage default

    // Dates
    var expectedCloseDate: Date?
    var actualCloseDate: Date?
    var nextFollowUpAt: Date?
    var lastActivityAt: Date?

    // Conversion / linking
    var projectId: String?
    var clientId: String?
    var lostReason: String?
    var lostNotes: String?

    // Soft-delete + archive
    var deletedAt: Date?
    var archivedAt: Date?

    // Tags + email source
    var tags: [String]
    var sourceEmailId: String?

    // Message-thread denormalized counters (populated by web; iOS reads but doesn't write)
    var correspondenceCount: Int
    var outboundCount: Int
    var inboundCount: Int
    var lastInboundAt: Date?
    var lastOutboundAt: Date?
    var lastMessageDirection: String?

    // Timestamps
    var createdAt: Date
    var updatedAt: Date

    // MARK: - Computed

    var weightedValue: Double {
        let pct = winProbabilityOverride ?? stage.winProbability
        return (estimatedValue ?? 0) * Double(pct) / 100.0
    }

    var daysInStage: Int {
        Calendar.current.dateComponents([.day], from: stageEnteredAt, to: Date()).day ?? 0
    }

    var isStale: Bool {
        daysInStage > stage.staleThresholdDays
    }

    var isDeleted: Bool { deletedAt != nil }
    var isArchived: Bool { archivedAt != nil }

    // MARK: - Init

    init(
        id: String = UUID().uuidString,
        companyId: String,
        contactName: String,
        stage: PipelineStage = .newLead,
        stageEnteredAt: Date = Date(),
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.companyId = companyId
        self.contactName = contactName
        self.stage = stage
        self.stageEnteredAt = stageEnteredAt
        self.stageManuallySet = false
        self.tags = []
        self.correspondenceCount = 0
        self.outboundCount = 0
        self.inboundCount = 0
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
```

- [ ] **Step 3: Build to verify migration safety**

Run: `xcodebuild -scheme OPS -destination 'generic/platform=iOS' build 2>&1 | tail -30`
Expected: BUILD SUCCEEDED. SwiftData auto-migrates: all new properties are optional or have defaults — existing rows remain valid.

- [ ] **Step 4: Verify all consumers still compile**

Run: `grep -rn "Opportunity(" OPS/ --include='*.swift' | head -20`
Expected: any callsite using the old initializer signature still works (we kept `init(id:, companyId:, contactName:, stage:, createdAt:, updatedAt:)` compatible by adding `stageEnteredAt` with a default).

- [ ] **Step 5: Commit**

```bash
git add OPS/DataModels/Supabase/Opportunity.swift
git commit -m "Extend Opportunity SwiftData model to full schema parity (additive)"
```

---

### Task 4: Extend `StageTransition` SwiftData model

**Files:**
- Modify: `OPS/DataModels/Supabase/StageTransition.swift`

- [x] **Step 1: Replace file contents**

```swift
//
//  StageTransition.swift
//  OPS
//
//  Immutable stage history record — Supabase-backed.
//  Schema parity with public.stage_transitions.
//

import SwiftData
import Foundation

@Model
class StageTransition: Identifiable {
    @Attribute(.unique) var id: String
    var companyId: String
    var opportunityId: String
    var fromStage: PipelineStage?    // nullable — first transition from "no prior stage"
    var toStage: PipelineStage
    var transitionedAt: Date
    var transitionedBy: String?      // user UUID
    var durationInStage: TimeInterval?  // decoded from Postgres `interval` type
    var createdAt: Date              // local cache timestamp (not in DB)

    init(
        id: String = UUID().uuidString,
        companyId: String,
        opportunityId: String,
        fromStage: PipelineStage?,
        toStage: PipelineStage,
        transitionedAt: Date = Date(),
        transitionedBy: String? = nil,
        durationInStage: TimeInterval? = nil
    ) {
        self.id = id
        self.companyId = companyId
        self.opportunityId = opportunityId
        self.fromStage = fromStage
        self.toStage = toStage
        self.transitionedAt = transitionedAt
        self.transitionedBy = transitionedBy
        self.durationInStage = durationInStage
        self.createdAt = Date()
    }
}
```

- [x] **Step 2: Build**

Run: `xcodebuild -scheme OPS -destination 'generic/platform=iOS' build 2>&1 | tail -20`
Expected: BUILD SUCCEEDED.

- [x] **Step 3: Commit**

```bash
git add OPS/DataModels/Supabase/StageTransition.swift
git commit -m "Extend StageTransition model with companyId, transitionedAt, durationInStage"
```

---

### Task 5: Extend `Activity` SwiftData model + rename body→bodyText

**Files:**
- Modify: `OPS/DataModels/Supabase/Activity.swift`

- [x] **Step 1: Replace file contents**

```swift
//
//  Activity.swift
//  OPS
//
//  Timeline event per opportunity — Supabase-backed.
//  Phase 1 fields cover note/call/email/stage_change. Defers email-thread
//  metadata (cc_emails, email_message_id, etc.) and classifier fields.
//

import SwiftData
import Foundation

@Model
class Activity: Identifiable {
    @Attribute(.unique) var id: String
    var opportunityId: String
    var companyId: String
    var type: ActivityType
    var subject: String?              // backfilled by trg_activities_default_subject when omitted
    var bodyText: String?             // primary body field (DB: body_text)
    var content: String?              // legacy fallback (DB: content)
    var direction: String?            // "inbound" | "outbound" | nil
    var outcome: String?
    var durationMinutes: Int?
    var isRead: Bool
    var hasAttachments: Bool
    var attachmentCount: Int
    var createdBy: String?
    var createdAt: Date

    /// Display body — prefers bodyText, falls back to content (for legacy rows).
    var displayBody: String? {
        if let bodyText, !bodyText.isEmpty { return bodyText }
        return content
    }

    init(
        id: String = UUID().uuidString,
        opportunityId: String,
        companyId: String,
        type: ActivityType,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.opportunityId = opportunityId
        self.companyId = companyId
        self.type = type
        self.isRead = false
        self.hasAttachments = false
        self.attachmentCount = 0
        self.createdAt = createdAt
    }
}
```

- [x] **Step 2: Build — expect compile error in old DTO mapping**

Run: `xcodebuild -scheme OPS -destination 'generic/platform=iOS' build 2>&1 | grep -E "error:" | head -10`
Expected: error referencing `act.body = ...` in `OpportunityDTOs.swift` (old field renamed). Will be fixed in Task 7.

- [x] **Step 3: Do NOT commit yet — wait until DTO is updated**

Move to Task 6 (FollowUp) and Task 7 (DTO rewrite) before committing.

---

### Task 6: Extend `FollowUp` SwiftData model + rename notes→description

**Files:**
- Modify: `OPS/DataModels/Supabase/FollowUp.swift`

- [x] **Step 1: Replace file contents**

```swift
//
//  FollowUp.swift
//  OPS
//
//  Scheduled reminder — Supabase-backed.
//  Schema parity with public.follow_ups. `title` is REQUIRED (NOT NULL on DB,
//  no backfill trigger — iOS must always send it).
//

import SwiftData
import Foundation

@Model
class FollowUp: Identifiable {
    @Attribute(.unique) var id: String
    var companyId: String
    var opportunityId: String?       // nullable — follow-ups can attach to client without opportunity
    var clientId: String?
    var title: String                // REQUIRED — NOT NULL on DB, no trigger fallback
    var descriptionText: String?     // DB column: `description`
    var type: FollowUpType
    var status: FollowUpStatus
    var dueAt: Date
    var reminderAt: Date?
    var assignedTo: String?
    var createdBy: String?
    var completedAt: Date?
    var completionNotes: String?
    var isAutoGenerated: Bool
    var triggerSource: String?
    var createdAt: Date

    var isOverdue: Bool {
        status == .pending && dueAt < Date()
    }

    var isDueToday: Bool {
        status == .pending && Calendar.current.isDateInToday(dueAt)
    }

    init(
        id: String = UUID().uuidString,
        companyId: String,
        opportunityId: String?,
        title: String,
        type: FollowUpType,
        dueAt: Date,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.companyId = companyId
        self.opportunityId = opportunityId
        self.title = title
        self.type = type
        self.status = .pending
        self.dueAt = dueAt
        self.isAutoGenerated = false
        self.createdAt = createdAt
    }
}
```

- [x] **Step 2: Continue to Task 7 (DTO rewrite needed before build can pass)**

---

### Task 7: Rewrite `OpportunityDTOs.swift` (full schema + bug fixes)

**Files:**
- Modify: `OPS/Network/Supabase/DTOs/OpportunityDTOs.swift`

- [x] **Step 1: Replace file contents**

```swift
//
//  OpportunityDTOs.swift
//  OPS
//
//  Data Transfer Objects for Pipeline/Opportunity Supabase tables.
//  Schema parity verified 2026-05-07 against public.opportunities, activities,
//  follow_ups, stage_transitions.
//

import Foundation

// MARK: - Opportunity

struct OpportunityDTO: Codable, Identifiable {
    let id: String
    let companyId: String
    let title: String?
    let contactName: String?
    let contactEmail: String?
    let contactPhone: String?
    let description: String?
    let address: String?

    let stage: String
    let stageEnteredAt: String
    let stageManuallySet: Bool?
    let assignedTo: String?
    let priority: String?
    let source: String?
    let quoteDeliveryMethod: String?

    let estimatedValue: Double?
    let actualValue: Double?
    let winProbability: Int?

    let expectedCloseDate: String?
    let actualCloseDate: String?
    let nextFollowUpAt: String?
    let lastActivityAt: String?

    let projectId: String?
    let clientId: String?
    let lostReason: String?
    let lostNotes: String?

    let deletedAt: String?
    let archivedAt: String?

    let tags: [String]?
    let sourceEmailId: String?

    let correspondenceCount: Int?
    let outboundCount: Int?
    let inboundCount: Int?
    let lastInboundAt: String?
    let lastOutboundAt: String?
    let lastMessageDirection: String?

    let createdAt: String
    let updatedAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case companyId            = "company_id"
        case title
        case contactName          = "contact_name"
        case contactEmail         = "contact_email"
        case contactPhone         = "contact_phone"
        case description
        case address
        case stage
        case stageEnteredAt       = "stage_entered_at"
        case stageManuallySet     = "stage_manually_set"
        case assignedTo           = "assigned_to"
        case priority
        case source
        case quoteDeliveryMethod  = "quote_delivery_method"
        case estimatedValue       = "estimated_value"
        case actualValue          = "actual_value"
        case winProbability       = "win_probability"
        case expectedCloseDate    = "expected_close_date"
        case actualCloseDate      = "actual_close_date"
        case nextFollowUpAt       = "next_follow_up_at"
        case lastActivityAt       = "last_activity_at"
        case projectId            = "project_id"
        case clientId             = "client_id"
        case lostReason           = "lost_reason"
        case lostNotes            = "lost_notes"
        case deletedAt            = "deleted_at"
        case archivedAt           = "archived_at"
        case tags
        case sourceEmailId        = "source_email_id"
        case correspondenceCount  = "correspondence_count"
        case outboundCount        = "outbound_count"
        case inboundCount         = "inbound_count"
        case lastInboundAt        = "last_inbound_at"
        case lastOutboundAt       = "last_outbound_at"
        case lastMessageDirection = "last_message_direction"
        case createdAt            = "created_at"
        case updatedAt            = "updated_at"
    }

    func toModel() -> Opportunity {
        let opp = Opportunity(
            id: id,
            companyId: companyId,
            contactName: contactName ?? "",
            stage: PipelineStage(rawValue: stage) ?? .newLead,
            stageEnteredAt: SupabaseDate.parse(stageEnteredAt) ?? Date(),
            createdAt: SupabaseDate.parse(createdAt) ?? Date(),
            updatedAt: SupabaseDate.parse(updatedAt) ?? Date()
        )
        opp.title = title
        opp.contactEmail = contactEmail
        opp.contactPhone = contactPhone
        opp.descriptionText = description
        opp.address = address
        opp.stageManuallySet = stageManuallySet ?? false
        opp.assignedTo = assignedTo
        opp.priority = priority
        opp.source = source
        if let m = quoteDeliveryMethod { opp.quoteDeliveryMethod = QuoteDeliveryMethod(rawValue: m) }
        opp.estimatedValue = estimatedValue
        opp.actualValue = actualValue
        opp.winProbabilityOverride = winProbability
        opp.expectedCloseDate = expectedCloseDate.flatMap { SupabaseDate.parse($0) }
        opp.actualCloseDate = actualCloseDate.flatMap { SupabaseDate.parse($0) }
        opp.nextFollowUpAt = nextFollowUpAt.flatMap { SupabaseDate.parse($0) }
        opp.lastActivityAt = lastActivityAt.flatMap { SupabaseDate.parse($0) }
        opp.projectId = projectId
        opp.clientId = clientId
        opp.lostReason = lostReason
        opp.lostNotes = lostNotes
        opp.deletedAt = deletedAt.flatMap { SupabaseDate.parse($0) }
        opp.archivedAt = archivedAt.flatMap { SupabaseDate.parse($0) }
        opp.tags = tags ?? []
        opp.sourceEmailId = sourceEmailId
        opp.correspondenceCount = correspondenceCount ?? 0
        opp.outboundCount = outboundCount ?? 0
        opp.inboundCount = inboundCount ?? 0
        opp.lastInboundAt = lastInboundAt.flatMap { SupabaseDate.parse($0) }
        opp.lastOutboundAt = lastOutboundAt.flatMap { SupabaseDate.parse($0) }
        opp.lastMessageDirection = lastMessageDirection
        return opp
    }
}

struct CreateOpportunityDTO: Codable {
    let companyId: String
    let title: String?               // optional — DB trigger backfills from contact_name
    let contactName: String
    let contactEmail: String?
    let contactPhone: String?
    let description: String?
    let address: String?
    let estimatedValue: Double?
    let source: String?
    let priority: String?
    let assignedTo: String?
    let expectedCloseDate: String?
    let quoteDeliveryMethod: String?
    let clientId: String?

    init(
        companyId: String,
        title: String? = nil,
        contactName: String,
        contactEmail: String? = nil,
        contactPhone: String? = nil,
        description: String? = nil,
        address: String? = nil,
        estimatedValue: Double? = nil,
        source: String? = nil,
        priority: String? = nil,
        assignedTo: String? = nil,
        expectedCloseDate: Date? = nil,
        quoteDeliveryMethod: String? = nil,
        clientId: String? = nil
    ) {
        self.companyId = companyId
        self.title = title
        self.contactName = contactName
        self.contactEmail = contactEmail
        self.contactPhone = contactPhone
        self.description = description
        self.address = address
        self.estimatedValue = estimatedValue
        self.source = source
        self.priority = priority
        self.assignedTo = assignedTo
        self.expectedCloseDate = expectedCloseDate.map { SupabaseDate.formatDate($0) }
        self.quoteDeliveryMethod = quoteDeliveryMethod
        self.clientId = clientId
    }

    enum CodingKeys: String, CodingKey {
        case companyId            = "company_id"
        case title
        case contactName          = "contact_name"
        case contactEmail         = "contact_email"
        case contactPhone         = "contact_phone"
        case description
        case address
        case estimatedValue       = "estimated_value"
        case source
        case priority
        case assignedTo           = "assigned_to"
        case expectedCloseDate    = "expected_close_date"
        case quoteDeliveryMethod  = "quote_delivery_method"
        case clientId             = "client_id"
    }
}

struct UpdateOpportunityDTO: Codable {
    var title: String?
    var contactName: String?
    var contactEmail: String?
    var contactPhone: String?
    var description: String?
    var address: String?
    var estimatedValue: Double?
    var actualValue: Double?
    var source: String?
    var priority: String?
    var assignedTo: String?
    var expectedCloseDate: String?
    var actualCloseDate: String?
    var clientId: String?
    var projectId: String?
    var lostReason: String?
    var lostNotes: String?
    var quoteDeliveryMethod: String?
    var archivedAt: String?
    var deletedAt: String?

    enum CodingKeys: String, CodingKey {
        case title
        case contactName          = "contact_name"
        case contactEmail         = "contact_email"
        case contactPhone         = "contact_phone"
        case description
        case address
        case estimatedValue       = "estimated_value"
        case actualValue          = "actual_value"
        case source
        case priority
        case assignedTo           = "assigned_to"
        case expectedCloseDate    = "expected_close_date"
        case actualCloseDate      = "actual_close_date"
        case clientId             = "client_id"
        case projectId            = "project_id"
        case lostReason           = "lost_reason"
        case lostNotes            = "lost_notes"
        case quoteDeliveryMethod  = "quote_delivery_method"
        case archivedAt           = "archived_at"
        case deletedAt            = "deleted_at"
    }
}

// MARK: - Activity

struct ActivityDTO: Codable, Identifiable {
    let id: String
    let opportunityId: String?
    let companyId: String
    let type: String
    let subject: String?
    let bodyText: String?
    let content: String?
    let direction: String?
    let outcome: String?
    let durationMinutes: Int?
    let isRead: Bool?
    let hasAttachments: Bool?
    let attachmentCount: Int?
    let createdBy: String?
    let createdAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case opportunityId   = "opportunity_id"
        case companyId       = "company_id"
        case type
        case subject
        case bodyText        = "body_text"
        case content
        case direction
        case outcome
        case durationMinutes = "duration_minutes"
        case isRead          = "is_read"
        case hasAttachments  = "has_attachments"
        case attachmentCount = "attachment_count"
        case createdBy       = "created_by"
        case createdAt       = "created_at"
    }

    func toModel() -> Activity {
        let act = Activity(
            id: id,
            opportunityId: opportunityId ?? "",
            companyId: companyId,
            type: ActivityType(rawValue: type) ?? .note,
            createdAt: SupabaseDate.parse(createdAt) ?? Date()
        )
        act.subject = subject
        act.bodyText = bodyText
        act.content = content
        act.direction = direction
        act.outcome = outcome
        act.durationMinutes = durationMinutes
        act.isRead = isRead ?? false
        act.hasAttachments = hasAttachments ?? false
        act.attachmentCount = attachmentCount ?? 0
        act.createdBy = createdBy
        return act
    }
}

struct CreateActivityDTO: Codable {
    let opportunityId: String
    let companyId: String
    let type: String
    let subject: String?    // optional — trg_activities_default_subject backfills
    let bodyText: String?
    let direction: String?
    let outcome: String?
    let durationMinutes: Int?

    enum CodingKeys: String, CodingKey {
        case opportunityId   = "opportunity_id"
        case companyId       = "company_id"
        case type
        case subject
        case bodyText        = "body_text"
        case direction
        case outcome
        case durationMinutes = "duration_minutes"
    }
}

// MARK: - Follow-Up (BUG FIX: notes→description, add required title)

struct FollowUpDTO: Codable, Identifiable {
    let id: String
    let companyId: String
    let opportunityId: String?
    let clientId: String?
    let title: String
    let description: String?
    let type: String
    let status: String
    let dueAt: String
    let reminderAt: String?
    let assignedTo: String?
    let createdBy: String?
    let completedAt: String?
    let completionNotes: String?
    let isAutoGenerated: Bool?
    let triggerSource: String?
    let createdAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case companyId       = "company_id"
        case opportunityId   = "opportunity_id"
        case clientId        = "client_id"
        case title
        case description
        case type
        case status
        case dueAt           = "due_at"
        case reminderAt      = "reminder_at"
        case assignedTo      = "assigned_to"
        case createdBy       = "created_by"
        case completedAt     = "completed_at"
        case completionNotes = "completion_notes"
        case isAutoGenerated = "is_auto_generated"
        case triggerSource   = "trigger_source"
        case createdAt       = "created_at"
    }

    func toModel() -> FollowUp {
        let fu = FollowUp(
            id: id,
            companyId: companyId,
            opportunityId: opportunityId,
            title: title,
            type: FollowUpType(rawValue: type) ?? .custom,
            dueAt: SupabaseDate.parse(dueAt) ?? Date(),
            createdAt: SupabaseDate.parse(createdAt) ?? Date()
        )
        fu.clientId = clientId
        fu.descriptionText = description
        fu.status = FollowUpStatus(rawValue: status) ?? .pending
        fu.reminderAt = reminderAt.flatMap { SupabaseDate.parse($0) }
        fu.assignedTo = assignedTo
        fu.createdBy = createdBy
        fu.completedAt = completedAt.flatMap { SupabaseDate.parse($0) }
        fu.completionNotes = completionNotes
        fu.isAutoGenerated = isAutoGenerated ?? false
        fu.triggerSource = triggerSource
        return fu
    }
}

struct CreateFollowUpDTO: Codable {
    let companyId: String
    let opportunityId: String?
    let title: String                // REQUIRED — NOT NULL on DB, no backfill trigger
    let description: String?
    let type: String
    let dueAt: String
    let reminderAt: String?
    let assignedTo: String?

    enum CodingKeys: String, CodingKey {
        case companyId     = "company_id"
        case opportunityId = "opportunity_id"
        case title
        case description
        case type
        case dueAt         = "due_at"
        case reminderAt    = "reminder_at"
        case assignedTo    = "assigned_to"
    }
}

// MARK: - Stage Transition

struct StageTransitionDTO: Codable, Identifiable {
    let id: String
    let companyId: String
    let opportunityId: String
    let fromStage: String?
    let toStage: String
    let transitionedAt: String
    let transitionedBy: String?
    let durationInStage: String?     // Postgres `interval` arrives as ISO 8601 string

    enum CodingKeys: String, CodingKey {
        case id
        case companyId        = "company_id"
        case opportunityId    = "opportunity_id"
        case fromStage        = "from_stage"
        case toStage          = "to_stage"
        case transitionedAt   = "transitioned_at"
        case transitionedBy   = "transitioned_by"
        case durationInStage  = "duration_in_stage"
    }

    func toModel() -> StageTransition {
        StageTransition(
            id: id,
            companyId: companyId,
            opportunityId: opportunityId,
            fromStage: fromStage.flatMap { PipelineStage(rawValue: $0) },
            toStage: PipelineStage(rawValue: toStage) ?? .newLead,
            transitionedAt: SupabaseDate.parse(transitionedAt) ?? Date(),
            transitionedBy: transitionedBy,
            durationInStage: durationInStage.flatMap { ISO8601DurationParser.parse($0) }
        )
    }
}

// MARK: - ISO 8601 Duration Parser

/// Minimal parser for Postgres `interval` text format (e.g. "P0Y0M0DT2H30M0S" or "2 days 03:00:00").
/// Returns seconds as TimeInterval.
enum ISO8601DurationParser {
    static func parse(_ raw: String) -> TimeInterval? {
        // Postgres default format is "[N years] [N mons] [N days] HH:MM:SS"
        // ISO 8601 format is "PnYnMnDTnHnMnS"
        let trimmed = raw.trimmingCharacters(in: .whitespaces)

        if trimmed.hasPrefix("P") {
            return parseISO8601(trimmed)
        }
        return parsePostgresInterval(trimmed)
    }

    private static func parseISO8601(_ s: String) -> TimeInterval? {
        let formatter = ISO8601DateFormatter()
        // ISO8601DateFormatter doesn't parse durations directly — fall through
        // to a manual regex parse for the date+time components we care about.
        var total: TimeInterval = 0
        let pattern = #"(\d+)([YMWDHS])"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let nsRange = NSRange(s.startIndex..<s.endIndex, in: s)
        var afterT = false
        var idx = s.startIndex
        while idx < s.endIndex {
            if s[idx] == "T" { afterT = true }
            idx = s.index(after: idx)
        }
        regex.enumerateMatches(in: s, range: nsRange) { match, _, _ in
            guard let match = match,
                  let valRange = Range(match.range(at: 1), in: s),
                  let unitRange = Range(match.range(at: 2), in: s) else { return }
            guard let val = Double(s[valRange]) else { return }
            let unit = s[unitRange]
            let isAfterT = afterT && match.range.location > (s.distance(from: s.startIndex, to: s.firstIndex(of: "T") ?? s.startIndex))
            switch unit {
            case "Y": total += val * 365 * 86400
            case "M": total += isAfterT ? val * 60 : val * 30 * 86400
            case "W": total += val * 7 * 86400
            case "D": total += val * 86400
            case "H": total += val * 3600
            case "S": total += val
            default:  break
            }
        }
        _ = formatter // suppress unused
        return total > 0 ? total : nil
    }

    private static func parsePostgresInterval(_ s: String) -> TimeInterval? {
        // Examples: "2 days 03:00:00", "03:00:00", "1 year 2 mons 3 days 04:05:06"
        var total: TimeInterval = 0
        let parts = s.split(separator: " ")
        var i = 0
        while i < parts.count {
            let token = parts[i]
            if let val = Double(token), i + 1 < parts.count {
                let unit = parts[i + 1].lowercased()
                if unit.hasPrefix("year")  { total += val * 365 * 86400 }
                if unit.hasPrefix("mon")   { total += val * 30 * 86400 }
                if unit.hasPrefix("day")   { total += val * 86400 }
                if unit.hasPrefix("hour")  { total += val * 3600 }
                if unit.hasPrefix("min")   { total += val * 60 }
                if unit.hasPrefix("sec")   { total += val }
                i += 2
            } else if token.contains(":") {
                let timeParts = token.split(separator: ":")
                if timeParts.count == 3,
                   let h = Double(timeParts[0]),
                   let m = Double(timeParts[1]),
                   let sec = Double(timeParts[2]) {
                    total += h * 3600 + m * 60 + sec
                }
                i += 1
            } else {
                i += 1
            }
        }
        return total > 0 ? total : nil
    }
}
```

- [x] **Step 2: Build — should succeed now that DTO matches model**

Run: `xcodebuild -scheme OPS -destination 'generic/platform=iOS' build 2>&1 | tail -30`
Expected: BUILD SUCCEEDED. If errors mention old field names in `OpportunityRepository.swift` or other consumers, those get fixed in Task 8 / Task 9.

- [x] **Step 3: Commit Tasks 5–7 together**

```bash
git add OPS/DataModels/Supabase/Activity.swift \
        OPS/DataModels/Supabase/FollowUp.swift \
        OPS/Network/Supabase/DTOs/OpportunityDTOs.swift
git commit -m "Rebuild Opportunity/Activity/FollowUp DTOs to match Supabase schema; fix FollowUp notes/title bugs"
```

---

### Task 8: Fix existing consumers of FollowUp/Activity old field names

**Files:**
- Modify: `OPS/ViewModels/LogActivityViewModel.swift` (uses `CreateOpportunityDTO`)
- Modify: `OPS/Views/JobBoard/ClientSheet.swift` (uses `CreateOpportunityDTO`)
- Possibly: any other call site — discover via grep.

- [x] **Step 1: Find all consumers**

Run:
```bash
grep -rn "CreateOpportunityDTO\|CreateFollowUpDTO\|CreateActivityDTO" OPS/ --include='*.swift' | grep -v "DTOs/Opportunity"
```
Expected: list of call sites (LogActivityViewModel, ClientSheet, others).

- [x] **Step 2: For each call site, verify the new initializer signature works**

The new `CreateOpportunityDTO` keeps the old required field (`contactName`) and adds optional ones. Existing call sites should compile unchanged because all new params have defaults.

For `CreateActivityDTO` and `CreateFollowUpDTO` — these are new shapes; consumers must adapt.

- [x] **Step 3: Update LogActivityViewModel.swift**

Run: `grep -n "CreateActivityDTO\|CreateOpportunityDTO" OPS/ViewModels/LogActivityViewModel.swift`

Read the surrounding code to understand the existing call. The new `CreateActivityDTO` requires `subject` to be optional (trigger backfills) — old code used `content`, new uses `bodyText`. Update the construction:

OLD:
```swift
let dto = CreateActivityDTO(
    opportunityId: ...,
    companyId: ...,
    type: ...,
    content: someText
)
```

NEW:
```swift
let dto = CreateActivityDTO(
    opportunityId: ...,
    companyId: ...,
    type: ...,
    subject: nil,                     // trigger backfills from type
    bodyText: someText,
    direction: nil,
    outcome: nil,
    durationMinutes: nil
)
```

(If LogActivityViewModel passes a different shape, adapt accordingly. Read the actual file first.)

- [x] **Step 4: Update ClientSheet.swift opportunity-create call site**

Run: `grep -n "CreateOpportunityDTO" OPS/Views/JobBoard/ClientSheet.swift`

Read the surrounding code. Bug 321e65c8 (referenced in ContentView.swift) is the auto-create-lead path — it constructs `CreateOpportunityDTO` from a freshly-created client. With the new DTO signature this call site should still compile (existing args still satisfy new init), but the new optional `title` field should be set: `title: "\(clientName) — lead"`.

- [x] **Step 5: Build and fix any remaining compile errors**

Run: `xcodebuild -scheme OPS -destination 'generic/platform=iOS' build 2>&1 | grep -E "error:" | head -20`
Expected: empty (no errors). Fix any field-rename errors (`fu.notes` → `fu.descriptionText`, `act.body` → `act.bodyText`, etc.).

- [x] **Step 6: Commit**

```bash
git add OPS/ViewModels/LogActivityViewModel.swift OPS/Views/JobBoard/ClientSheet.swift
git commit -m "Update existing consumers for renamed Activity/FollowUp/Opportunity fields"
```

---

### Task 9: Rebuild `OpportunityRepository`

**Files:**
- Modify: `OPS/Network/Supabase/Repositories/OpportunityRepository.swift`

- [x] **Step 1: Replace file contents**

```swift
//
//  OpportunityRepository.swift
//  OPS
//
//  Repository for Pipeline CRM operations via Supabase.
//  - Soft-delete via deleted_at (no hard deletes)
//  - Atomic stage moves via move_opportunity_stage RPC
//  - Schema parity with public.opportunities
//

import Foundation
import Supabase

class OpportunityRepository {
    private let client: SupabaseClient
    private let companyId: String

    init(companyId: String) {
        self.client = SupabaseService.shared.client
        self.companyId = companyId
    }

    // MARK: - Fetch

    func fetchAll() async throws -> [OpportunityDTO] {
        try await client
            .from("opportunities")
            .select()
            .eq("company_id", value: companyId)
            .is("deleted_at", value: nil)
            .order("created_at", ascending: false)
            .execute()
            .value
    }

    func fetchOne(_ opportunityId: String) async throws -> OpportunityDTO {
        try await client
            .from("opportunities")
            .select()
            .eq("id", value: opportunityId)
            .single()
            .execute()
            .value
    }

    func fetchActivities(for opportunityId: String) async throws -> [ActivityDTO] {
        try await client
            .from("activities")
            .select()
            .eq("opportunity_id", value: opportunityId)
            .order("created_at", ascending: false)
            .execute()
            .value
    }

    func fetchFollowUps(for opportunityId: String) async throws -> [FollowUpDTO] {
        try await client
            .from("follow_ups")
            .select()
            .eq("opportunity_id", value: opportunityId)
            .order("due_at", ascending: true)
            .execute()
            .value
    }

    func fetchStageTransitions(for opportunityId: String) async throws -> [StageTransitionDTO] {
        try await client
            .from("stage_transitions")
            .select()
            .eq("opportunity_id", value: opportunityId)
            .order("transitioned_at", ascending: false)
            .execute()
            .value
    }

    // MARK: - Create

    func create(_ dto: CreateOpportunityDTO) async throws -> OpportunityDTO {
        try await client
            .from("opportunities")
            .insert(dto)
            .select()
            .single()
            .execute()
            .value
    }

    func logActivity(_ dto: CreateActivityDTO) async throws -> ActivityDTO {
        try await client
            .from("activities")
            .insert(dto)
            .select()
            .single()
            .execute()
            .value
    }

    func createFollowUp(_ dto: CreateFollowUpDTO) async throws -> FollowUpDTO {
        try await client
            .from("follow_ups")
            .insert(dto)
            .select()
            .single()
            .execute()
            .value
    }

    // MARK: - Update

    /// Atomic stage move via Postgres RPC.
    /// Updates stage + stage_entered_at + stage_manually_set AND inserts a
    /// stage_transitions row in one transaction. Returns the updated opportunity.
    func moveToStage(opportunityId: String, to stage: PipelineStage, userId: String?) async throws -> OpportunityDTO {
        struct RpcParams: Codable {
            let p_opportunity_id: String
            let p_to_stage: String
            let p_user_id: String?
        }
        let params = RpcParams(
            p_opportunity_id: opportunityId,
            p_to_stage: stage.rawValue,
            p_user_id: userId
        )
        return try await client
            .rpc("move_opportunity_stage", params: params)
            .single()
            .execute()
            .value
    }

    /// Mark won. Sets stage to .won, stores actualValue + actualCloseDate,
    /// and writes the stage_transitions row via moveToStage.
    func markWon(opportunityId: String, actualValue: Double?, projectId: String?, userId: String?) async throws -> OpportunityDTO {
        // First the stage move (writes transition row)
        _ = try await moveToStage(opportunityId: opportunityId, to: .won, userId: userId)

        // Then patch the won-specific fields
        var fields = UpdateOpportunityDTO()
        fields.actualValue = actualValue
        fields.actualCloseDate = SupabaseDate.formatDate(Date())
        if let projectId { fields.projectId = projectId }
        return try await update(opportunityId, fields: fields)
    }

    /// Mark lost. Sets stage to .lost, stores lost_reason + lost_notes + actualCloseDate,
    /// and writes the stage_transitions row via moveToStage.
    func markLost(opportunityId: String, reason: LossReason, notes: String?, userId: String?) async throws -> OpportunityDTO {
        _ = try await moveToStage(opportunityId: opportunityId, to: .lost, userId: userId)

        var fields = UpdateOpportunityDTO()
        fields.lostReason = reason.rawValue
        fields.lostNotes = notes
        fields.actualCloseDate = SupabaseDate.formatDate(Date())
        return try await update(opportunityId, fields: fields)
    }

    func update(_ opportunityId: String, fields: UpdateOpportunityDTO) async throws -> OpportunityDTO {
        try await client
            .from("opportunities")
            .update(fields)
            .eq("id", value: opportunityId)
            .select()
            .single()
            .execute()
            .value
    }

    // MARK: - Soft Delete + Archive

    /// Soft-delete via deleted_at. Replaces the prior HARD delete.
    func softDelete(_ opportunityId: String) async throws {
        var fields = UpdateOpportunityDTO()
        fields.deletedAt = SupabaseDate.format(Date())
        _ = try await update(opportunityId, fields: fields)
    }

    /// Archive without deleting — used for "long-dormant but maybe-revisit" leads.
    func archive(_ opportunityId: String) async throws {
        var fields = UpdateOpportunityDTO()
        fields.archivedAt = SupabaseDate.format(Date())
        _ = try await update(opportunityId, fields: fields)
    }

    /// Restore from archive.
    func unarchive(_ opportunityId: String) async throws {
        struct UnarchivePatch: Codable {
            let archived_at: String? = nil
        }
        try await client
            .from("opportunities")
            .update(UnarchivePatch())
            .eq("id", value: opportunityId)
            .execute()
    }

    // MARK: - Deprecated

    /// Kept for backward compatibility. Forwards to moveToStage; does NOT
    /// write actualValue or actualCloseDate. Prefer markWon / markLost.
    @available(*, deprecated, message: "Use moveToStage / markWon / markLost")
    func advanceStage(opportunityId: String, to stage: PipelineStage, lostReason: String? = nil) async throws -> OpportunityDTO {
        try await moveToStage(opportunityId: opportunityId, to: stage, userId: nil)
    }
}
```

- [x] **Step 2: Build**

Run: `xcodebuild -scheme OPS -destination 'generic/platform=iOS' build 2>&1 | grep -E "error:" | head -10`
Expected: empty.

- [x] **Step 3: Verify SupabaseDate has `formatDate` and `format`**

Run: `grep -n "static func format\|static func formatDate" OPS/ -r --include='*.swift'`
Expected: methods exist on SupabaseDate utility. If `formatDate` doesn't exist (only `format`), use `format` everywhere and adjust the DTO to send full ISO-8601 timestamps. (Postgres `date` columns accept ISO-8601 by date-component prefix.)

- [x] **Step 4: Commit**

```bash
git add OPS/Network/Supabase/Repositories/OpportunityRepository.swift
git commit -m "Rebuild OpportunityRepository: soft-delete, atomic moveToStage RPC, markWon/markLost"
```

---

### Task 10: Add unit tests for DTO codecs and `ISO8601DurationParser`

**Files:**
- Create: `OPSTests/Pipeline/OpportunityDTOTests.swift`

- [x] **Step 1: Verify the test target exists and how it's referenced**

Run: `ls OPSTests/ && cat OPSTests/OPSTests.swift | head -30`
Expected: shows existing test pattern (likely `XCTestCase` subclass with `@testable import OPS`).

- [x] **Step 2: Create the test file**

```swift
//
//  OpportunityDTOTests.swift
//  OPSTests
//

import XCTest
@testable import OPS

final class OpportunityDTOTests: XCTestCase {

    // MARK: - OpportunityDTO

    func test_OpportunityDTO_decodesFullSchema() throws {
        let json = """
        {
          "id": "11111111-1111-1111-1111-111111111111",
          "company_id": "22222222-2222-2222-2222-222222222222",
          "title": "Devlin roof replacement",
          "contact_name": "Eric Devlin",
          "contact_email": "eric@devlin.com",
          "contact_phone": "555-1234",
          "description": "Full roof tear-off",
          "address": "123 Main St",
          "stage": "quoting",
          "stage_entered_at": "2026-05-01T12:00:00Z",
          "stage_manually_set": true,
          "assigned_to": "33333333-3333-3333-3333-333333333333",
          "priority": "high",
          "source": "referral",
          "quote_delivery_method": "email",
          "estimated_value": 24000,
          "actual_value": null,
          "win_probability": 60,
          "expected_close_date": "2026-06-15",
          "actual_close_date": null,
          "next_follow_up_at": "2026-05-10T09:00:00Z",
          "last_activity_at": "2026-05-05T15:30:00Z",
          "project_id": null,
          "client_id": "44444444-4444-4444-4444-444444444444",
          "lost_reason": null,
          "lost_notes": null,
          "deleted_at": null,
          "archived_at": null,
          "tags": ["urgent", "referral"],
          "source_email_id": null,
          "correspondence_count": 4,
          "outbound_count": 2,
          "inbound_count": 2,
          "last_inbound_at": "2026-05-05T15:30:00Z",
          "last_outbound_at": "2026-05-04T10:00:00Z",
          "last_message_direction": "inbound",
          "created_at": "2026-04-25T08:00:00Z",
          "updated_at": "2026-05-05T15:30:00Z"
        }
        """
        let data = json.data(using: .utf8)!
        let dto = try JSONDecoder().decode(OpportunityDTO.self, from: data)
        XCTAssertEqual(dto.id, "11111111-1111-1111-1111-111111111111")
        XCTAssertEqual(dto.title, "Devlin roof replacement")
        XCTAssertEqual(dto.stage, "quoting")
        XCTAssertEqual(dto.estimatedValue, 24000)
        XCTAssertEqual(dto.winProbability, 60)
        XCTAssertEqual(dto.tags, ["urgent", "referral"])
        XCTAssertEqual(dto.correspondenceCount, 4)
        XCTAssertEqual(dto.lastMessageDirection, "inbound")

        let opp = dto.toModel()
        XCTAssertEqual(opp.contactName, "Eric Devlin")
        XCTAssertEqual(opp.stage, .quoting)
        XCTAssertEqual(opp.weightedValue, 24000 * 0.6, accuracy: 0.01)
        XCTAssertTrue(opp.stageManuallySet)
    }

    func test_OpportunityDTO_decodesMinimalRow() throws {
        let json = """
        {
          "id": "abc",
          "company_id": "co",
          "title": null,
          "contact_name": null,
          "contact_email": null, "contact_phone": null, "description": null, "address": null,
          "stage": "new_lead",
          "stage_entered_at": "2026-05-07T00:00:00Z",
          "stage_manually_set": null,
          "assigned_to": null, "priority": null, "source": null, "quote_delivery_method": null,
          "estimated_value": null, "actual_value": null, "win_probability": null,
          "expected_close_date": null, "actual_close_date": null,
          "next_follow_up_at": null, "last_activity_at": null,
          "project_id": null, "client_id": null,
          "lost_reason": null, "lost_notes": null,
          "deleted_at": null, "archived_at": null,
          "tags": null, "source_email_id": null,
          "correspondence_count": null, "outbound_count": null, "inbound_count": null,
          "last_inbound_at": null, "last_outbound_at": null, "last_message_direction": null,
          "created_at": "2026-05-07T00:00:00Z",
          "updated_at": "2026-05-07T00:00:00Z"
        }
        """
        let data = json.data(using: .utf8)!
        let dto = try JSONDecoder().decode(OpportunityDTO.self, from: data)
        let opp = dto.toModel()
        XCTAssertEqual(opp.contactName, "")
        XCTAssertEqual(opp.tags, [])
        XCTAssertEqual(opp.correspondenceCount, 0)
        XCTAssertFalse(opp.stageManuallySet)
    }

    // MARK: - CreateFollowUpDTO bug fix

    func test_CreateFollowUpDTO_includesRequiredTitleAndDescription() throws {
        let dto = CreateFollowUpDTO(
            companyId: "co",
            opportunityId: "opp",
            title: "Follow up with Devlin re quote",
            description: "He asked about timeline",
            type: "call",
            dueAt: "2026-05-10T09:00:00Z",
            reminderAt: nil,
            assignedTo: nil
        )
        let data = try JSONEncoder().encode(dto)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        XCTAssertEqual(json["title"] as? String, "Follow up with Devlin re quote")
        XCTAssertEqual(json["description"] as? String, "He asked about timeline")
        XCTAssertNil(json["notes"], "FollowUp DB column is `description`, not `notes` (bug fix)")
    }

    // MARK: - StageTransitionDTO

    func test_StageTransitionDTO_decodesPostgresInterval() throws {
        let json = """
        {
          "id": "t1",
          "company_id": "co",
          "opportunity_id": "opp",
          "from_stage": "quoting",
          "to_stage": "quoted",
          "transitioned_at": "2026-05-07T12:00:00Z",
          "transitioned_by": "user-uuid",
          "duration_in_stage": "2 days 03:00:00"
        }
        """
        let data = json.data(using: .utf8)!
        let dto = try JSONDecoder().decode(StageTransitionDTO.self, from: data)
        let model = dto.toModel()
        XCTAssertEqual(model.fromStage, .quoting)
        XCTAssertEqual(model.toStage, .quoted)
        // NOTE: model.durationInStage is TimeInterval? — XCTAssertEqual's
        // FloatingPoint `accuracy:` overload requires non-optional, so unwrap first.
        let duration = try XCTUnwrap(model.durationInStage)
        XCTAssertEqual(duration, 2 * 86400 + 3 * 3600, accuracy: 0.01)
    }

    func test_ISO8601DurationParser_postgresFormats() {
        XCTAssertEqual(ISO8601DurationParser.parse("03:00:00"), 3 * 3600)
        XCTAssertEqual(ISO8601DurationParser.parse("1 day 12:00:00"), 86400 + 12 * 3600)
        XCTAssertEqual(ISO8601DurationParser.parse("2 days"), 2 * 86400)
        XCTAssertEqual(ISO8601DurationParser.parse("01:30:45"), 3600 + 30 * 60 + 45)
    }
}
```

- [x] **Step 3: Add the test file to the OPSTests Xcode target**

Run: `xed OPSTests/Pipeline/OpportunityDTOTests.swift` (opens in Xcode if interactive). For headless: edit `OPS.xcodeproj/project.pbxproj` to register the file under the OPSTests target. Or use `xcodebuild` and verify the file is auto-discovered (modern Xcode projects with synchronized groups auto-add files in source-group folders — verify behavior).

If `xcodebuild test` fails to find the test, manually add the file to the test target via Xcode's "Add Files…" or by editing `project.pbxproj`.

- [x] **Step 4: Run the tests**

Run: `xcodebuild test -scheme OPS -destination 'generic/platform=iOS' -only-testing:OPSTests/OpportunityDTOTests 2>&1 | tail -20`

(Note: per CLAUDE.md "Never use the simulator." `xcodebuild test` typically requires a simulator destination. For unit tests that don't depend on UI, the build verification in earlier tasks is sufficient. If `xcodebuild test` cannot run on `generic/platform=iOS`, document that the tests must be run from Xcode manually as part of dev verification, not CI.)

Expected: 5 tests pass.

- [x] **Step 5: Commit**

```bash
git add OPSTests/Pipeline/OpportunityDTOTests.swift
git commit -m "Add unit tests for OpportunityDTO codec, FollowUp bug fix, and Postgres interval parser"
```

---

## Phase 1B — Pipeline UI

### Task 11: Create `PipelineViewModel`

**Files:**
- Create: `OPS/ViewModels/PipelineViewModel.swift`

- [x] **Step 1: Create the file**

```swift
//
//  PipelineViewModel.swift
//  OPS
//
//  Loads opportunities for a company, groups by stage, sorts within each
//  stage (stale first, then lastActivityAt desc).
//

import SwiftUI
import SwiftData

@MainActor
class PipelineViewModel: ObservableObject {

    @Published var allOpportunities: [Opportunity] = []
    @Published var isLoading: Bool = false
    @Published var loadError: String? = nil
    @Published var selectedStage: PipelineStage = .newLead

    private var repository: OpportunityRepository?
    private var companyId: String?

    // MARK: - Setup

    func setup(companyId: String) {
        self.companyId = companyId
        self.repository = OpportunityRepository(companyId: companyId)
    }

    // MARK: - Load

    func loadData() async {
        guard let repo = repository else { return }
        isLoading = true
        loadError = nil
        defer { isLoading = false }

        do {
            let dtos = try await repo.fetchAll()
            allOpportunities = dtos.map { $0.toModel() }
        } catch {
            if !error.isCancellation {
                print("[Pipeline] Load failed: \(error)")
                loadError = error.localizedDescription
            }
        }
    }

    // MARK: - Derivations

    /// Opportunities in the given stage, sorted: stale first, then lastActivityAt desc, then createdAt desc.
    func opportunities(in stage: PipelineStage) -> [Opportunity] {
        allOpportunities
            .filter { $0.stage == stage && !$0.isDeleted && !$0.isArchived }
            .sorted { lhs, rhs in
                if lhs.isStale != rhs.isStale { return lhs.isStale }
                let lDate = lhs.lastActivityAt ?? lhs.createdAt
                let rDate = rhs.lastActivityAt ?? rhs.createdAt
                if lDate != rDate { return lDate > rDate }
                return lhs.createdAt > rhs.createdAt
            }
    }

    /// Count per stage for the strip.
    func count(in stage: PipelineStage) -> Int {
        allOpportunities.filter { $0.stage == stage && !$0.isDeleted && !$0.isArchived }.count
    }

    /// Pipeline-wide counts for dashboard carousel.
    var activeLeadCount: Int {
        allOpportunities.filter { !$0.stage.isTerminal && !$0.isDeleted && !$0.isArchived }.count
    }

    var weightedForecastValue: Double {
        allOpportunities
            .filter { !$0.stage.isTerminal && !$0.isDeleted && !$0.isArchived }
            .reduce(0) { $0 + $1.weightedValue }
    }

    var staleLeadsCount: Int {
        allOpportunities.filter { !$0.stage.isTerminal && !$0.isDeleted && !$0.isArchived && $0.isStale }.count
    }

    var nextFollowUpDue: Date? {
        allOpportunities
            .compactMap { $0.nextFollowUpAt }
            .filter { $0 >= Date() }
            .min()
    }

    /// True when no opportunities exist at all (any stage).
    var isPipelineEmpty: Bool {
        allOpportunities.allSatisfy { $0.isDeleted || $0.isArchived }
    }

    // MARK: - Mutations

    func moveToStage(opportunityId: String, to stage: PipelineStage, userId: String?) async throws {
        guard let repo = repository else { return }
        let updatedDTO = try await repo.moveToStage(opportunityId: opportunityId, to: stage, userId: userId)
        if let idx = allOpportunities.firstIndex(where: { $0.id == opportunityId }) {
            let updated = updatedDTO.toModel()
            allOpportunities[idx] = updated
        }
    }

    func markWon(opportunityId: String, actualValue: Double?, projectId: String?, userId: String?) async throws {
        guard let repo = repository else { return }
        let updatedDTO = try await repo.markWon(opportunityId: opportunityId, actualValue: actualValue, projectId: projectId, userId: userId)
        if let idx = allOpportunities.firstIndex(where: { $0.id == opportunityId }) {
            allOpportunities[idx] = updatedDTO.toModel()
        }
    }

    func markLost(opportunityId: String, reason: LossReason, notes: String?, userId: String?) async throws {
        guard let repo = repository else { return }
        let updatedDTO = try await repo.markLost(opportunityId: opportunityId, reason: reason, notes: notes, userId: userId)
        if let idx = allOpportunities.firstIndex(where: { $0.id == opportunityId }) {
            allOpportunities[idx] = updatedDTO.toModel()
        }
    }

    func addLead(_ dto: CreateOpportunityDTO) async throws -> Opportunity {
        guard let repo = repository else { throw NSError(domain: "Pipeline", code: 0) }
        let resultDTO = try await repo.create(dto)
        let model = resultDTO.toModel()
        allOpportunities.append(model)
        return model
    }

    func archive(opportunityId: String) async throws {
        guard let repo = repository else { return }
        try await repo.archive(opportunityId)
        if let idx = allOpportunities.firstIndex(where: { $0.id == opportunityId }) {
            allOpportunities[idx].archivedAt = Date()
        }
    }

    func softDelete(opportunityId: String) async throws {
        guard let repo = repository else { return }
        try await repo.softDelete(opportunityId)
        if let idx = allOpportunities.firstIndex(where: { $0.id == opportunityId }) {
            allOpportunities[idx].deletedAt = Date()
        }
    }
}
```

- [x] **Step 2: Build**

Run: `xcodebuild -scheme OPS -destination 'generic/platform=iOS' build 2>&1 | tail -10`
Expected: BUILD SUCCEEDED.

- [x] **Step 3: Commit**

```bash
git add OPS/ViewModels/PipelineViewModel.swift
git commit -m "Add PipelineViewModel with stage filtering, sorting, and mutation API"
```

---

### Task 12: Add `PipelineViewModel` unit tests

**Files:**
- Create: `OPSTests/Pipeline/PipelineViewModelTests.swift`

- [x] **Step 1: Create the file**

```swift
//
//  PipelineViewModelTests.swift
//  OPSTests
//

import XCTest
@testable import OPS

@MainActor
final class PipelineViewModelTests: XCTestCase {

    func makeOpportunity(
        id: String = UUID().uuidString,
        stage: PipelineStage = .newLead,
        stageEnteredAt: Date = Date(),
        lastActivityAt: Date? = nil,
        deletedAt: Date? = nil,
        archivedAt: Date? = nil,
        estimatedValue: Double? = nil
    ) -> Opportunity {
        let opp = Opportunity(
            id: id,
            companyId: "co",
            contactName: "Test",
            stage: stage,
            stageEnteredAt: stageEnteredAt
        )
        opp.lastActivityAt = lastActivityAt
        opp.deletedAt = deletedAt
        opp.archivedAt = archivedAt
        opp.estimatedValue = estimatedValue
        return opp
    }

    // MARK: - Filtering

    func test_opportunitiesInStage_excludesDeletedAndArchived() {
        let vm = PipelineViewModel()
        let active = makeOpportunity(stage: .newLead)
        let deleted = makeOpportunity(stage: .newLead, deletedAt: Date())
        let archived = makeOpportunity(stage: .newLead, archivedAt: Date())
        vm.allOpportunities = [active, deleted, archived]

        let result = vm.opportunities(in: .newLead)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.id, active.id)
    }

    // MARK: - Sorting

    func test_opportunitiesInStage_staleSortsFirst() {
        let vm = PipelineViewModel()
        let nowMinus10d = Calendar.current.date(byAdding: .day, value: -10, to: Date())!  // stale (newLead threshold = 3d)
        let now = Date()
        let stale = makeOpportunity(id: "stale", stage: .newLead, stageEnteredAt: nowMinus10d)
        let fresh = makeOpportunity(id: "fresh", stage: .newLead, stageEnteredAt: now)
        vm.allOpportunities = [fresh, stale]

        let result = vm.opportunities(in: .newLead)
        XCTAssertEqual(result.first?.id, "stale")
        XCTAssertEqual(result.last?.id, "fresh")
    }

    func test_opportunitiesInStage_recentActivitySortsBeforeOlder() {
        let vm = PipelineViewModel()
        let recent = Date()
        let old = Calendar.current.date(byAdding: .day, value: -2, to: Date())!
        let oppRecent = makeOpportunity(id: "recent", stage: .quoting, stageEnteredAt: recent, lastActivityAt: recent)
        let oppOld = makeOpportunity(id: "old", stage: .quoting, stageEnteredAt: recent, lastActivityAt: old)
        vm.allOpportunities = [oppOld, oppRecent]

        let result = vm.opportunities(in: .quoting)
        XCTAssertEqual(result.first?.id, "recent")
    }

    // MARK: - Aggregates

    func test_activeLeadCount_excludesTerminalStages() {
        let vm = PipelineViewModel()
        vm.allOpportunities = [
            makeOpportunity(stage: .newLead),
            makeOpportunity(stage: .quoting),
            makeOpportunity(stage: .won),
            makeOpportunity(stage: .lost)
        ]
        XCTAssertEqual(vm.activeLeadCount, 2)
    }

    func test_weightedForecastValue_appliesStageProbability() {
        let vm = PipelineViewModel()
        // newLead = 10%, quoting = 40%
        vm.allOpportunities = [
            makeOpportunity(stage: .newLead, estimatedValue: 1000),    // 100
            makeOpportunity(stage: .quoting, estimatedValue: 5000),    // 2000
            makeOpportunity(stage: .won, estimatedValue: 10000)        // excluded (terminal)
        ]
        XCTAssertEqual(vm.weightedForecastValue, 100 + 2000, accuracy: 0.01)
    }

    func test_staleLeadsCount_respectsPerStageThreshold() {
        let vm = PipelineViewModel()
        let nowMinus10d = Calendar.current.date(byAdding: .day, value: -10, to: Date())!
        // newLead threshold = 3d, quoting threshold = 5d
        vm.allOpportunities = [
            makeOpportunity(stage: .newLead, stageEnteredAt: nowMinus10d),  // stale
            makeOpportunity(stage: .quoting, stageEnteredAt: nowMinus10d),  // stale
            makeOpportunity(stage: .negotiation, stageEnteredAt: Date())    // fresh
        ]
        XCTAssertEqual(vm.staleLeadsCount, 2)
    }

    func test_isPipelineEmpty_whenAllDeletedOrArchived() {
        let vm = PipelineViewModel()
        vm.allOpportunities = [
            makeOpportunity(stage: .newLead, deletedAt: Date()),
            makeOpportunity(stage: .quoting, archivedAt: Date())
        ]
        XCTAssertTrue(vm.isPipelineEmpty)
    }
}
```

- [x] **Step 2: Add file to test target (see Task 10 Step 3 for procedure)**

- [x] **Step 3: Run tests via Xcode (per Task 10 Step 4 caveat)**

Expected: all 7 tests pass.

- [x] **Step 4: Commit**

```bash
git add OPSTests/Pipeline/PipelineViewModelTests.swift
git commit -m "Add PipelineViewModel tests for filter/sort/aggregate logic"
```

---

### Task 13: Build `LeadCardView`

**Files:**
- Create: `OPS/Views/Books/Pipeline/LeadCardView.swift`

- [x] **Step 1: Create the file (and parent directories)**

```bash
mkdir -p OPS/Views/Books/Pipeline
```

- [x] **Step 2: Write the view**

```swift
//
//  LeadCardView.swift
//  OPS
//
//  Per-lead card with title, value, days-in-stage, stale indicator,
//  and inline action chips (advance/won/lost/⋯). Tap card body → detail.
//

import SwiftUI

struct LeadCardView: View {
    let opportunity: Opportunity
    let canManage: Bool
    var onTap: () -> Void
    var onAdvance: () -> Void       // → opportunity.stage.next
    var onWon: () -> Void
    var onLost: () -> Void
    var onMore: () -> Void          // opens LeadActionSheet

    private var displayTitle: String {
        if let t = opportunity.title, !t.isEmpty { return t }
        return opportunity.contactName.isEmpty ? "(no name)" : opportunity.contactName
    }

    private var valueText: String? {
        guard let v = opportunity.estimatedValue else { return nil }
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: v))
    }

    private var daysInStageText: String {
        let d = opportunity.daysInStage
        return d == 1 ? "1d in stage" : "\(d)d in stage"
    }

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
                // Title row
                Text(displayTitle)
                    .font(OPSStyle.Typography.bodyBold)
                    .foregroundColor(OPSStyle.Colors.primaryText)
                    .lineLimit(1)
                    .truncationMode(.tail)

                // Metadata row
                HStack(spacing: OPSStyle.Layout.spacing2) {
                    if let valueText {
                        Text(valueText)
                            .font(OPSStyle.Typography.body)
                            .foregroundColor(OPSStyle.Colors.primaryText)
                    }
                    Text("·")
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                    Text(daysInStageText)
                        .font(OPSStyle.Typography.smallCaption)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                    if opportunity.isStale {
                        Text("⚠ STALE")
                            .font(OPSStyle.Typography.smallCaption)
                            .foregroundColor(OPSStyle.Colors.errorStatus)
                    }
                    Spacer()
                }

                // Inline action chips (only if canManage AND not terminal)
                if canManage && !opportunity.stage.isTerminal {
                    HStack(spacing: OPSStyle.Layout.spacing2) {
                        if let next = opportunity.stage.next {
                            ChipButton(
                                label: "→ \(next.displayName)",
                                tint: OPSStyle.Colors.primaryAccent,
                                inverted: true,
                                action: onAdvance
                            )
                        }
                        ChipButton(
                            label: "WON",
                            tint: OPSStyle.Colors.successStatus,
                            inverted: true,
                            action: onWon
                        )
                        ChipButton(
                            label: "LOST",
                            tint: OPSStyle.Colors.tertiaryText,
                            inverted: false,
                            action: onLost
                        )
                        Spacer()
                        Button(action: onMore) {
                            Image(systemName: "ellipsis")
                                .font(.system(size: OPSStyle.Layout.IconSize.md, weight: .semibold))
                                .foregroundColor(OPSStyle.Colors.secondaryText)
                                .frame(width: OPSStyle.Layout.touchTargetMin, height: OPSStyle.Layout.touchTargetMin)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
            }
            .padding(OPSStyle.Layout.spacing3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(OPSStyle.Colors.cardBackground)
            .overlay(alignment: .leading) {
                if opportunity.isStale {
                    Rectangle()
                        .fill(OPSStyle.Colors.errorStatus.opacity(0.6))
                        .frame(width: 3)
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius)
                    .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
            )
            .clipShape(RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius))
        }
        .buttonStyle(PlainButtonStyle())
    }
}

private struct ChipButton: View {
    let label: String
    let tint: Color
    let inverted: Bool         // when true, fill = tint, text = invertedText
    let action: () -> Void

    var body: some View {
        Button(action: {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            action()
        }) {
            Text(label)
                .font(OPSStyle.Typography.captionBold)
                .foregroundColor(inverted ? OPSStyle.Colors.invertedText : tint)
                .padding(.horizontal, OPSStyle.Layout.spacing2_5)
                .padding(.vertical, OPSStyle.Layout.spacing2)
                .background(inverted ? tint : Color.clear)
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(inverted ? Color.clear : tint, lineWidth: OPSStyle.Layout.Border.standard)
                )
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .frame(minHeight: OPSStyle.Layout.touchTargetMin)
        }
        .buttonStyle(PlainButtonStyle())
    }
}
```

- [x] **Step 3: Build**

Run: `xcodebuild -scheme OPS -destination 'generic/platform=iOS' build 2>&1 | tail -10`
Expected: BUILD SUCCEEDED.

- [x] **Step 4: Commit**

```bash
git add OPS/Views/Books/Pipeline/LeadCardView.swift
git commit -m "Add LeadCardView with action chips and stale-edge accent"
```

---

### Task 14: Build `StageStripView`

**Files:**
- Create: `OPS/Views/Books/Pipeline/StageStripView.swift`

- [x] **Step 1: Write the view**

```swift
//
//  StageStripView.swift
//  OPS
//
//  Horizontal pinned strip of pipeline stages. Active stage highlighted with
//  underline accent + bold label. Vertical divider separates active from
//  terminal stages (Won/Lost). Tap a pill to focus that stage.
//

import SwiftUI

struct StageStripView: View {
    @Binding var selectedStage: PipelineStage
    let countProvider: (PipelineStage) -> Int

    private let activeStages: [PipelineStage] = [
        .newLead, .qualifying, .quoting, .quoted, .followUp, .negotiation
    ]
    private let terminalStages: [PipelineStage] = [.won, .lost]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
                ForEach(activeStages) { stage in
                    pill(for: stage)
                }
                divider
                ForEach(terminalStages) { stage in
                    pill(for: stage, terminal: true)
                }
            }
            .padding(.horizontal, OPSStyle.Layout.spacing3)
        }
        .frame(minHeight: 48)
        .background(OPSStyle.Colors.background)
    }

    @ViewBuilder
    private func pill(for stage: PipelineStage, terminal: Bool = false) -> some View {
        let isSelected = selectedStage == stage
        let count = countProvider(stage)

        Button(action: {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            withAnimation(OPSStyle.Animation.standard) {
                selectedStage = stage
            }
        }) {
            VStack(spacing: OPSStyle.Layout.spacing1) {
                HStack(spacing: 6) {
                    Text(stage.displayName)
                        .font(isSelected ? OPSStyle.Typography.captionBold : OPSStyle.Typography.caption)
                        .foregroundColor(
                            isSelected
                                ? OPSStyle.Colors.primaryText
                                : OPSStyle.Colors.secondaryText
                        )
                    if count > 0 {
                        Text("\(count)")
                            .font(OPSStyle.Typography.smallCaption)
                            .foregroundColor(
                                isSelected
                                    ? OPSStyle.Colors.primaryAccent
                                    : OPSStyle.Colors.tertiaryText
                            )
                    }
                }
                .padding(.horizontal, OPSStyle.Layout.spacing2_5)
                .frame(minHeight: OPSStyle.Layout.touchTargetMin)

                Rectangle()
                    .fill(isSelected ? OPSStyle.Colors.primaryAccent : Color.clear)
                    .frame(height: OPSStyle.Layout.Border.thick)
            }
            .opacity(terminal ? 0.6 : 1.0)
        }
        .buttonStyle(PlainButtonStyle())
    }

    private var divider: some View {
        Rectangle()
            .fill(OPSStyle.Colors.cardBorder)
            .frame(width: OPSStyle.Layout.Border.standard, height: 24)
            .padding(.horizontal, OPSStyle.Layout.spacing2)
    }
}
```

- [x] **Step 2: Build**

Run: `xcodebuild -scheme OPS -destination 'generic/platform=iOS' build 2>&1 | tail -10`
Expected: BUILD SUCCEEDED.

- [x] **Step 3: Commit**

```bash
git add OPS/Views/Books/Pipeline/StageStripView.swift
git commit -m "Add StageStripView with active/terminal divider and per-stage counts"
```

---

### Task 15: Build `LostReasonSheet`

**Files:**
- Create: `OPS/Views/Books/Pipeline/LostReasonSheet.swift`

- [x] **Step 1: Write the view**

```swift
//
//  LostReasonSheet.swift
//  OPS
//
//  Modal sheet that captures lost_reason + optional lost_notes when a lead is
//  marked Lost. Required field: reason (LossReason picker). Optional: notes.
//

import SwiftUI

struct LostReasonSheet: View {
    @Environment(\.dismiss) private var dismiss

    let opportunityTitle: String
    var onConfirm: (LossReason, String?) -> Void

    @State private var selectedReason: LossReason = .price
    @State private var notes: String = ""

    var body: some View {
        NavigationStack {
            ZStack {
                OPSStyle.Colors.background.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing4) {
                        Text("MARK LOST")
                            .font(OPSStyle.Typography.subtitle)
                            .foregroundColor(OPSStyle.Colors.primaryText)

                        Text(opportunityTitle.uppercased())
                            .font(OPSStyle.Typography.caption)
                            .foregroundColor(OPSStyle.Colors.secondaryText)

                        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
                            Text("REASON")
                                .font(OPSStyle.Typography.captionBold)
                                .foregroundColor(OPSStyle.Colors.tertiaryText)

                            VStack(spacing: 0) {
                                ForEach(LossReason.allCases) { reason in
                                    Button(action: {
                                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                        selectedReason = reason
                                    }) {
                                        HStack {
                                            Text(reason.displayName)
                                                .font(OPSStyle.Typography.body)
                                                .foregroundColor(OPSStyle.Colors.primaryText)
                                            Spacer()
                                            if selectedReason == reason {
                                                Image(systemName: "checkmark")
                                                    .foregroundColor(OPSStyle.Colors.primaryAccent)
                                            }
                                        }
                                        .padding(.horizontal, OPSStyle.Layout.spacing3)
                                        .frame(minHeight: OPSStyle.Layout.touchTargetStandard)
                                    }
                                    .buttonStyle(PlainButtonStyle())

                                    if reason != LossReason.allCases.last {
                                        Divider().background(OPSStyle.Colors.cardBorder)
                                    }
                                }
                            }
                            .background(OPSStyle.Colors.cardBackground)
                            .overlay(
                                RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius)
                                    .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
                            )
                            .clipShape(RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius))
                        }

                        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
                            Text("NOTES (OPTIONAL)")
                                .font(OPSStyle.Typography.captionBold)
                                .foregroundColor(OPSStyle.Colors.tertiaryText)

                            TextEditor(text: $notes)
                                .font(OPSStyle.Typography.body)
                                .foregroundColor(OPSStyle.Colors.primaryText)
                                .scrollContentBackground(.hidden)
                                .padding(OPSStyle.Layout.spacing2)
                                .frame(minHeight: 120)
                                .background(OPSStyle.Colors.cardBackground)
                                .overlay(
                                    RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius)
                                        .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
                                )
                                .clipShape(RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius))
                        }
                    }
                    .padding(OPSStyle.Layout.spacing3)
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("CANCEL") { dismiss() }
                        .font(OPSStyle.Typography.captionBold)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("CONFIRM") {
                        UINotificationFeedbackGenerator().notificationOccurred(.warning)
                        onConfirm(selectedReason, notes.isEmpty ? nil : notes)
                        dismiss()
                    }
                    .font(OPSStyle.Typography.captionBold)
                    .foregroundColor(OPSStyle.Colors.errorStatus)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
```

- [x] **Step 2: Build & commit**

```bash
xcodebuild -scheme OPS -destination 'generic/platform=iOS' build 2>&1 | tail -5
git add OPS/Views/Books/Pipeline/LostReasonSheet.swift
git commit -m "Add LostReasonSheet for capturing loss reason and notes"
```

---

### Task 16: Build `AddLeadSheet`

**Files:**
- Create: `OPS/Views/Books/Pipeline/AddLeadSheet.swift`

- [x] **Step 1: Write the view**

```swift
//
//  AddLeadSheet.swift
//  OPS
//
//  Modal for creating a new pipeline opportunity. Fields per spec §6.6.
//  Title is optional (DB trigger backfills); contactName is required.
//

import SwiftUI

struct AddLeadSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var dataController: DataController

    var onCreated: (Opportunity) -> Void

    @State private var title: String = ""
    @State private var contactName: String = ""
    @State private var contactEmail: String = ""
    @State private var contactPhone: String = ""
    @State private var estimatedValueText: String = ""
    @State private var source: OpportunitySource? = nil
    @State private var description: String = ""

    @State private var isSaving = false
    @State private var saveError: String? = nil

    private var canSave: Bool {
        !contactName.trimmingCharacters(in: .whitespaces).isEmpty && !isSaving
    }

    var body: some View {
        NavigationStack {
            ZStack {
                OPSStyle.Colors.background.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing4) {
                        sectionHeader("DEAL")
                        labeledField("TITLE (OPTIONAL)", text: $title, placeholder: "e.g. Devlin roof replacement")

                        sectionHeader("CONTACT")
                        labeledField("NAME *", text: $contactName, placeholder: "Eric Devlin")
                        labeledField("EMAIL", text: $contactEmail, placeholder: "eric@example.com", keyboard: .emailAddress)
                        labeledField("PHONE", text: $contactPhone, placeholder: "555-1234", keyboard: .phonePad)

                        sectionHeader("DETAILS")
                        labeledField("ESTIMATED VALUE", text: $estimatedValueText, placeholder: "0", keyboard: .decimalPad)
                        sourcePicker
                        labeledTextEditor("DESCRIPTION", text: $description)

                        if let saveError {
                            Text(saveError)
                                .font(OPSStyle.Typography.smallCaption)
                                .foregroundColor(OPSStyle.Colors.errorStatus)
                        }
                    }
                    .padding(OPSStyle.Layout.spacing3)
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("CANCEL") { dismiss() }
                        .font(OPSStyle.Typography.captionBold)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("ADD") { Task { await save() } }
                        .font(OPSStyle.Typography.captionBold)
                        .foregroundColor(canSave ? OPSStyle.Colors.primaryAccent : OPSStyle.Colors.tertiaryText)
                        .disabled(!canSave)
                }
            }
        }
        .presentationDetents([.large])
    }

    // MARK: - Save

    private func save() async {
        guard let companyId = dataController.currentUser?.companyId else { return }
        isSaving = true
        saveError = nil
        defer { isSaving = false }

        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let estimatedValue: Double? = {
            let cleaned = estimatedValueText.replacingOccurrences(of: ",", with: "").replacingOccurrences(of: "$", with: "")
            return Double(cleaned)
        }()

        let dto = CreateOpportunityDTO(
            companyId: companyId,
            title: trimmedTitle.isEmpty ? nil : trimmedTitle,
            contactName: contactName.trimmingCharacters(in: .whitespacesAndNewlines),
            contactEmail: contactEmail.isEmpty ? nil : contactEmail,
            contactPhone: contactPhone.isEmpty ? nil : contactPhone,
            description: description.isEmpty ? nil : description,
            address: nil,
            estimatedValue: estimatedValue,
            source: source?.rawValue,
            priority: nil,
            assignedTo: nil,
            expectedCloseDate: nil,
            quoteDeliveryMethod: nil,
            clientId: nil
        )

        let repo = OpportunityRepository(companyId: companyId)
        do {
            let resultDTO = try await repo.create(dto)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            onCreated(resultDTO.toModel())
            dismiss()
        } catch {
            saveError = error.localizedDescription
        }
    }

    // MARK: - Subviews

    @ViewBuilder
    private func sectionHeader(_ text: String) -> some View {
        Text(text)
            .font(OPSStyle.Typography.captionBold)
            .foregroundColor(OPSStyle.Colors.tertiaryText)
            .padding(.top, OPSStyle.Layout.spacing2)
    }

    @ViewBuilder
    private func labeledField(_ label: String, text: Binding<String>, placeholder: String = "", keyboard: UIKeyboardType = .default) -> some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing1) {
            Text(label)
                .font(OPSStyle.Typography.smallCaption)
                .foregroundColor(OPSStyle.Colors.secondaryText)
            TextField(placeholder, text: text)
                .font(OPSStyle.Typography.body)
                .foregroundColor(OPSStyle.Colors.primaryText)
                .keyboardType(keyboard)
                .padding(OPSStyle.Layout.spacing2_5)
                .background(OPSStyle.Colors.cardBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                        .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
                )
                .clipShape(RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius))
                .frame(minHeight: OPSStyle.Layout.touchTargetMin)
        }
    }

    @ViewBuilder
    private func labeledTextEditor(_ label: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing1) {
            Text(label)
                .font(OPSStyle.Typography.smallCaption)
                .foregroundColor(OPSStyle.Colors.secondaryText)
            TextEditor(text: text)
                .font(OPSStyle.Typography.body)
                .foregroundColor(OPSStyle.Colors.primaryText)
                .scrollContentBackground(.hidden)
                .padding(OPSStyle.Layout.spacing2)
                .frame(minHeight: 100)
                .background(OPSStyle.Colors.cardBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                        .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
                )
                .clipShape(RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius))
        }
    }

    private var sourcePicker: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing1) {
            Text("SOURCE")
                .font(OPSStyle.Typography.smallCaption)
                .foregroundColor(OPSStyle.Colors.secondaryText)
            Menu {
                Button("NONE") { source = nil }
                ForEach(OpportunitySource.allCases) { src in
                    Button(src.displayName) { source = src }
                }
            } label: {
                HStack {
                    Text(source?.displayName ?? "SELECT…")
                        .font(OPSStyle.Typography.body)
                        .foregroundColor(source != nil ? OPSStyle.Colors.primaryText : OPSStyle.Colors.tertiaryText)
                    Spacer()
                    Image(systemName: "chevron.down")
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                }
                .padding(OPSStyle.Layout.spacing2_5)
                .frame(minHeight: OPSStyle.Layout.touchTargetMin)
                .background(OPSStyle.Colors.cardBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                        .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
                )
                .clipShape(RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius))
            }
        }
    }
}
```

- [x] **Step 2: Build & commit**

```bash
xcodebuild -scheme OPS -destination 'generic/platform=iOS' build 2>&1 | tail -5
git add OPS/Views/Books/Pipeline/AddLeadSheet.swift
git commit -m "Add AddLeadSheet for creating new pipeline opportunities"
```

---

### Task 17: Build `LeadActionSheet` (⋯ menu)

**Files:**
- Create: `OPS/Views/Books/Pipeline/LeadActionSheet.swift`

- [x] **Step 1: Write the view**

```swift
//
//  LeadActionSheet.swift
//  OPS
//
//  Bottom sheet of less-common actions for a lead. Triggered by ⋯ on LeadCardView.
//

import SwiftUI

struct LeadActionSheet: View {
    @Environment(\.dismiss) private var dismiss

    let opportunity: Opportunity
    let canManage: Bool
    var onMoveToStage: (PipelineStage) -> Void
    var onEdit: () -> Void
    var onLogActivity: () -> Void
    var onAddFollowUp: () -> Void
    var onOpenDetail: () -> Void
    var onArchive: () -> Void
    var onDelete: () -> Void

    var body: some View {
        NavigationStack {
            ZStack {
                OPSStyle.Colors.background.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: OPSStyle.Layout.spacing3) {
                        if canManage {
                            section(title: "MOVE TO STAGE") {
                                ForEach(PipelineStage.allCases) { stage in
                                    if stage != opportunity.stage {
                                        actionRow(label: stage.displayName, icon: "arrow.forward.circle") {
                                            onMoveToStage(stage); dismiss()
                                        }
                                    }
                                }
                            }
                        }

                        section(title: "ACTIONS") {
                            actionRow(label: "OPEN DETAIL", icon: "doc.text") { onOpenDetail(); dismiss() }
                            if canManage {
                                actionRow(label: "EDIT", icon: "pencil") { onEdit(); dismiss() }
                                actionRow(label: "LOG ACTIVITY", icon: "text.bubble") { onLogActivity(); dismiss() }
                                actionRow(label: "ADD FOLLOW-UP", icon: "calendar.badge.plus") { onAddFollowUp(); dismiss() }
                            }
                        }

                        if canManage {
                            section(title: "ARCHIVE") {
                                actionRow(label: "ARCHIVE", icon: "archivebox", tint: OPSStyle.Colors.warningStatus) {
                                    onArchive(); dismiss()
                                }
                                actionRow(label: "DELETE", icon: "trash", tint: OPSStyle.Colors.errorStatus) {
                                    onDelete(); dismiss()
                                }
                            }
                        }
                    }
                    .padding(OPSStyle.Layout.spacing3)
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("DONE") { dismiss() }
                        .font(OPSStyle.Typography.captionBold)
                        .foregroundColor(OPSStyle.Colors.primaryAccent)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    @ViewBuilder
    private func section<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
            Text(title)
                .font(OPSStyle.Typography.captionBold)
                .foregroundColor(OPSStyle.Colors.tertiaryText)
            VStack(spacing: 0) { content() }
                .background(OPSStyle.Colors.cardBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius)
                        .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
                )
                .clipShape(RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius))
        }
    }

    @ViewBuilder
    private func actionRow(label: String, icon: String, tint: Color = OPSStyle.Colors.primaryText, action: @escaping () -> Void) -> some View {
        Button(action: {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            action()
        }) {
            HStack(spacing: OPSStyle.Layout.spacing3) {
                Image(systemName: icon)
                    .font(.system(size: OPSStyle.Layout.IconSize.md))
                    .foregroundColor(tint)
                    .frame(width: 28)
                Text(label)
                    .font(OPSStyle.Typography.body)
                    .foregroundColor(tint)
                Spacer()
            }
            .padding(.horizontal, OPSStyle.Layout.spacing3)
            .frame(minHeight: OPSStyle.Layout.touchTargetStandard)
        }
        .buttonStyle(PlainButtonStyle())
    }
}
```

- [x] **Step 2: Build & commit**

```bash
xcodebuild -scheme OPS -destination 'generic/platform=iOS' build 2>&1 | tail -5
git add OPS/Views/Books/Pipeline/LeadActionSheet.swift
git commit -m "Add LeadActionSheet bottom-sheet menu for lead actions"
```

---

### Task 18: Build `LeadDetailViewModel`

**Files:**
- Create: `OPS/ViewModels/LeadDetailViewModel.swift`

- [x] **Step 1: Write the ViewModel**

```swift
//
//  LeadDetailViewModel.swift
//  OPS
//
//  Loads activities, follow-ups, and stage transitions for one opportunity.
//

import SwiftUI

@MainActor
class LeadDetailViewModel: ObservableObject {
    @Published var activities: [Activity] = []
    @Published var followUps: [FollowUp] = []
    @Published var stageTransitions: [StageTransition] = []
    @Published var isLoading = false
    @Published var loadError: String? = nil

    private let opportunityId: String
    private let companyId: String
    private let repository: OpportunityRepository

    init(opportunityId: String, companyId: String) {
        self.opportunityId = opportunityId
        self.companyId = companyId
        self.repository = OpportunityRepository(companyId: companyId)
    }

    func loadAll() async {
        isLoading = true
        loadError = nil
        defer { isLoading = false }

        async let actsTask = loadActivities()
        async let fusTask = loadFollowUps()
        async let stsTask = loadStageTransitions()
        _ = await (actsTask, fusTask, stsTask)
    }

    private func loadActivities() async {
        do {
            let dtos = try await repository.fetchActivities(for: opportunityId)
            activities = dtos.map { $0.toModel() }
        } catch { print("[LeadDetail] activities failed: \(error)") }
    }

    private func loadFollowUps() async {
        do {
            let dtos = try await repository.fetchFollowUps(for: opportunityId)
            followUps = dtos.map { $0.toModel() }
        } catch { print("[LeadDetail] follow-ups failed: \(error)") }
    }

    private func loadStageTransitions() async {
        do {
            let dtos = try await repository.fetchStageTransitions(for: opportunityId)
            stageTransitions = dtos.map { $0.toModel() }
        } catch { print("[LeadDetail] transitions failed: \(error)") }
    }

    func logActivity(type: ActivityType, subject: String?, body: String?, direction: String? = nil, outcome: String? = nil, durationMinutes: Int? = nil) async throws {
        let dto = CreateActivityDTO(
            opportunityId: opportunityId,
            companyId: companyId,
            type: type.rawValue,
            subject: subject,
            bodyText: body,
            direction: direction,
            outcome: outcome,
            durationMinutes: durationMinutes
        )
        let resultDTO = try await repository.logActivity(dto)
        activities.insert(resultDTO.toModel(), at: 0)
    }

    func addFollowUp(title: String, description: String?, type: FollowUpType, dueAt: Date, reminderAt: Date?, assignedTo: String?) async throws {
        let dto = CreateFollowUpDTO(
            companyId: companyId,
            opportunityId: opportunityId,
            title: title,
            description: description,
            type: type.rawValue,
            dueAt: SupabaseDate.format(dueAt),
            reminderAt: reminderAt.map { SupabaseDate.format($0) },
            assignedTo: assignedTo
        )
        let resultDTO = try await repository.createFollowUp(dto)
        followUps.append(resultDTO.toModel())
        followUps.sort { $0.dueAt < $1.dueAt }
    }
}
```

- [x] **Step 2: Build & commit**

```bash
xcodebuild -scheme OPS -destination 'generic/platform=iOS' build 2>&1 | tail -5
git add OPS/ViewModels/LeadDetailViewModel.swift
git commit -m "Add LeadDetailViewModel for activity/follow-up/transition loading"
```

---

### Task 19: Build `LogActivitySheet`

**Files:**
- Create: `OPS/Views/Books/Pipeline/LogActivitySheet.swift`

- [x] **Step 1: Write the view**

```swift
//
//  LogActivitySheet.swift
//  OPS
//
//  Modal for adding a manual activity entry to a lead. Used from LeadDetailView.
//

import SwiftUI

struct LogActivitySheet: View {
    @Environment(\.dismiss) private var dismiss

    var onSave: (ActivityType, String?, String?) -> Void

    @State private var type: ActivityType = .note
    @State private var subject: String = ""
    @State private var body: String = ""

    private let userPickableTypes: [ActivityType] = [.note, .call, .email, .meeting, .siteVisit]

    var body: some View {
        NavigationStack {
            ZStack {
                OPSStyle.Colors.background.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing3) {
                        Text("LOG ACTIVITY")
                            .font(OPSStyle.Typography.subtitle)
                            .foregroundColor(OPSStyle.Colors.primaryText)

                        Text("TYPE")
                            .font(OPSStyle.Typography.captionBold)
                            .foregroundColor(OPSStyle.Colors.tertiaryText)
                        Picker("TYPE", selection: $type) {
                            ForEach(userPickableTypes, id: \.self) { t in
                                Text(t.rawValue.uppercased()).tag(t)
                            }
                        }
                        .pickerStyle(.segmented)

                        Text("SUBJECT (OPTIONAL — TRIGGER BACKFILLS)")
                            .font(OPSStyle.Typography.smallCaption)
                            .foregroundColor(OPSStyle.Colors.secondaryText)
                        TextField("e.g. Discussed pricing", text: $subject)
                            .font(OPSStyle.Typography.body)
                            .foregroundColor(OPSStyle.Colors.primaryText)
                            .padding(OPSStyle.Layout.spacing2_5)
                            .background(OPSStyle.Colors.cardBackground)
                            .overlay(RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                                .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard))
                            .clipShape(RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius))

                        Text("BODY")
                            .font(OPSStyle.Typography.smallCaption)
                            .foregroundColor(OPSStyle.Colors.secondaryText)
                        TextEditor(text: $body)
                            .font(OPSStyle.Typography.body)
                            .foregroundColor(OPSStyle.Colors.primaryText)
                            .scrollContentBackground(.hidden)
                            .padding(OPSStyle.Layout.spacing2)
                            .frame(minHeight: 160)
                            .background(OPSStyle.Colors.cardBackground)
                            .overlay(RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                                .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard))
                            .clipShape(RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius))
                    }
                    .padding(OPSStyle.Layout.spacing3)
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("CANCEL") { dismiss() }
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("SAVE") {
                        onSave(type,
                               subject.isEmpty ? nil : subject,
                               body.isEmpty ? nil : body)
                        dismiss()
                    }
                    .foregroundColor(OPSStyle.Colors.primaryAccent)
                    .disabled(subject.isEmpty && body.isEmpty)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
```

- [x] **Step 2: Build & commit**

```bash
xcodebuild -scheme OPS -destination 'generic/platform=iOS' build 2>&1 | tail -5
git add OPS/Views/Books/Pipeline/LogActivitySheet.swift
git commit -m "Add LogActivitySheet for manual lead activity entries"
```

> **Drift note (impl):** A pre-existing `OPS/Views/Pipeline/LogActivitySheet.swift` (voice-first quick logger consumed by `FloatingActionMenu`) already owned this struct name. The new manual-entry sheet was renamed `LeadLogActivitySheet` and saved to `OPS/Views/Books/Pipeline/LeadLogActivitySheet.swift` to avoid the duplicate-output-file conflict. The plan's `body` field also clashed with `View.body` and was renamed to `bodyText`.

---

### Task 20: Build `AddFollowUpSheet`

**Files:**
- Create: `OPS/Views/Books/Pipeline/AddFollowUpSheet.swift`

- [x] **Step 1: Write the view**

```swift
//
//  AddFollowUpSheet.swift
//  OPS
//
//  Modal for adding a scheduled follow-up to a lead. `title` is required
//  (DB NOT NULL with no backfill trigger — bug fix #12 in spec).
//

import SwiftUI

struct AddFollowUpSheet: View {
    @Environment(\.dismiss) private var dismiss

    var onSave: (String, String?, FollowUpType, Date, Date?) -> Void

    @State private var title: String = ""
    @State private var description: String = ""
    @State private var type: FollowUpType = .call
    @State private var dueAt: Date = Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date()
    @State private var reminderEnabled: Bool = false
    @State private var reminderAt: Date = Date()

    private var canSave: Bool { !title.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        NavigationStack {
            ZStack {
                OPSStyle.Colors.background.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing3) {
                        Text("ADD FOLLOW-UP")
                            .font(OPSStyle.Typography.subtitle)
                            .foregroundColor(OPSStyle.Colors.primaryText)

                        Text("TITLE *")
                            .font(OPSStyle.Typography.smallCaption)
                            .foregroundColor(OPSStyle.Colors.secondaryText)
                        TextField("e.g. Follow up re quote", text: $title)
                            .font(OPSStyle.Typography.body)
                            .foregroundColor(OPSStyle.Colors.primaryText)
                            .padding(OPSStyle.Layout.spacing2_5)
                            .background(OPSStyle.Colors.cardBackground)
                            .overlay(RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                                .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard))
                            .clipShape(RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius))

                        Text("TYPE")
                            .font(OPSStyle.Typography.smallCaption)
                            .foregroundColor(OPSStyle.Colors.secondaryText)
                        Picker("TYPE", selection: $type) {
                            ForEach(FollowUpType.allCases, id: \.self) { t in
                                Text(t.rawValue.uppercased()).tag(t)
                            }
                        }
                        .pickerStyle(.segmented)

                        Text("DUE")
                            .font(OPSStyle.Typography.smallCaption)
                            .foregroundColor(OPSStyle.Colors.secondaryText)
                        DatePicker("", selection: $dueAt, in: Date()..., displayedComponents: [.date, .hourAndMinute])
                            .labelsHidden()
                            .colorScheme(.dark)

                        Toggle("REMINDER", isOn: $reminderEnabled)
                            .font(OPSStyle.Typography.captionBold)
                            .foregroundColor(OPSStyle.Colors.primaryText)
                            .tint(OPSStyle.Colors.primaryAccent)

                        if reminderEnabled {
                            DatePicker("", selection: $reminderAt, in: Date()...dueAt, displayedComponents: [.date, .hourAndMinute])
                                .labelsHidden()
                                .colorScheme(.dark)
                        }

                        Text("DESCRIPTION (OPTIONAL)")
                            .font(OPSStyle.Typography.smallCaption)
                            .foregroundColor(OPSStyle.Colors.secondaryText)
                        TextEditor(text: $description)
                            .font(OPSStyle.Typography.body)
                            .foregroundColor(OPSStyle.Colors.primaryText)
                            .scrollContentBackground(.hidden)
                            .padding(OPSStyle.Layout.spacing2)
                            .frame(minHeight: 100)
                            .background(OPSStyle.Colors.cardBackground)
                            .overlay(RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                                .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard))
                            .clipShape(RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius))
                    }
                    .padding(OPSStyle.Layout.spacing3)
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("CANCEL") { dismiss() }
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("ADD") {
                        onSave(
                            title.trimmingCharacters(in: .whitespacesAndNewlines),
                            description.isEmpty ? nil : description,
                            type,
                            dueAt,
                            reminderEnabled ? reminderAt : nil
                        )
                        dismiss()
                    }
                    .foregroundColor(canSave ? OPSStyle.Colors.primaryAccent : OPSStyle.Colors.tertiaryText)
                    .disabled(!canSave)
                }
            }
        }
        .presentationDetents([.large])
    }
}
```

- [x] **Step 2: Build & commit**

```bash
xcodebuild -scheme OPS -destination 'generic/platform=iOS' build 2>&1 | tail -5
git add OPS/Views/Books/Pipeline/AddFollowUpSheet.swift
git commit -m "Add AddFollowUpSheet (with required title field per bug fix)"
```

---

### Task 21: Build `LeadDetailView`

**Files:**
- Create: `OPS/Views/Books/Pipeline/LeadDetailView.swift`

- [x] **Step 1: Write the view**

```swift
//
//  LeadDetailView.swift
//  OPS
//
//  Full-screen lead detail (NavigationLink push). Header + quick actions +
//  stage actions + activity log + follow-ups + stage history.
//

import SwiftUI

struct LeadDetailView: View {
    @StateObject private var viewModel: LeadDetailViewModel
    @EnvironmentObject private var dataController: DataController
    @EnvironmentObject private var permissionStore: PermissionStore

    @ObservedObject var pipelineVM: PipelineViewModel
    let opportunity: Opportunity

    @State private var showLogActivity = false
    @State private var showAddFollowUp = false
    @State private var showLostReason = false
    @State private var showEditSheet = false

    private var canManage: Bool { permissionStore.can("pipeline.manage") }
    private var userId: String? { dataController.currentUser?.id }

    init(opportunity: Opportunity, pipelineVM: PipelineViewModel) {
        self.opportunity = opportunity
        self.pipelineVM = pipelineVM
        _viewModel = StateObject(wrappedValue: LeadDetailViewModel(
            opportunityId: opportunity.id,
            companyId: opportunity.companyId
        ))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing4) {
                header
                if canManage { quickActions }
                if canManage && !opportunity.stage.isTerminal { stageActions }
                activitySection
                followUpsSection
                stageHistorySection
            }
            .padding(OPSStyle.Layout.spacing3)
        }
        .background(OPSStyle.Colors.background.ignoresSafeArea())
        .navigationTitle("LEAD")
        .navigationBarTitleDisplayMode(.inline)
        .task { await viewModel.loadAll() }
        .sheet(isPresented: $showLogActivity) {
            LogActivitySheet { type, subject, body in
                Task {
                    try? await viewModel.logActivity(type: type, subject: subject, body: body)
                }
            }
        }
        .sheet(isPresented: $showAddFollowUp) {
            AddFollowUpSheet { title, desc, type, dueAt, reminderAt in
                Task {
                    try? await viewModel.addFollowUp(
                        title: title, description: desc, type: type,
                        dueAt: dueAt, reminderAt: reminderAt, assignedTo: userId
                    )
                }
            }
        }
        .sheet(isPresented: $showLostReason) {
            LostReasonSheet(opportunityTitle: opportunity.title ?? opportunity.contactName) { reason, notes in
                Task {
                    try? await pipelineVM.markLost(opportunityId: opportunity.id, reason: reason, notes: notes, userId: userId)
                }
            }
        }
        .sheet(isPresented: $showEditSheet) {
            // EditLeadSheet — stub for Phase 1 (full implementation may slip to Phase 1.5)
            Text("Edit sheet placeholder — see Task 22")
                .font(OPSStyle.Typography.body)
                .foregroundColor(OPSStyle.Colors.primaryText)
        }
    }

    // MARK: - Sections

    private var header: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
            Text(opportunity.title ?? opportunity.contactName)
                .font(OPSStyle.Typography.title)
                .foregroundColor(OPSStyle.Colors.primaryText)
            Text(opportunity.contactName.uppercased())
                .font(OPSStyle.Typography.caption)
                .foregroundColor(OPSStyle.Colors.secondaryText)
            HStack(spacing: OPSStyle.Layout.spacing2) {
                stagePill
                if let v = opportunity.estimatedValue {
                    Text(formatCurrency(v))
                        .font(OPSStyle.Typography.bodyBold)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                }
                if opportunity.isStale {
                    Text("⚠ STALE")
                        .font(OPSStyle.Typography.smallCaption)
                        .foregroundColor(OPSStyle.Colors.errorStatus)
                }
            }
        }
    }

    private var stagePill: some View {
        Text(opportunity.stage.displayName)
            .font(OPSStyle.Typography.smallCaption)
            .foregroundColor(OPSStyle.Colors.invertedText)
            .padding(.horizontal, OPSStyle.Layout.spacing2)
            .padding(.vertical, 4)
            .background(OPSStyle.Colors.primaryAccent)
            .clipShape(Capsule())
    }

    private var quickActions: some View {
        HStack(spacing: OPSStyle.Layout.spacing3) {
            if let phone = opportunity.contactPhone, let url = URL(string: "tel:\(phone)") {
                quickAction(icon: "phone.fill", label: "CALL") { UIApplication.shared.open(url) }
                quickAction(icon: "message.fill", label: "TEXT") {
                    if let smsURL = URL(string: "sms:\(phone)") { UIApplication.shared.open(smsURL) }
                }
            }
            if let email = opportunity.contactEmail, let url = URL(string: "mailto:\(email)") {
                quickAction(icon: "envelope.fill", label: "EMAIL") { UIApplication.shared.open(url) }
            }
        }
    }

    @ViewBuilder
    private func quickAction(icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: OPSStyle.Layout.IconSize.md))
                    .foregroundColor(OPSStyle.Colors.primaryAccent)
                Text(label)
                    .font(OPSStyle.Typography.smallCaption)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
            }
            .frame(maxWidth: .infinity, minHeight: OPSStyle.Layout.touchTargetStandard)
            .background(OPSStyle.Colors.cardBackground)
            .overlay(RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius)
                .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard))
            .clipShape(RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius))
        }
    }

    private var stageActions: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
            Text("STAGE ACTIONS")
                .font(OPSStyle.Typography.captionBold)
                .foregroundColor(OPSStyle.Colors.tertiaryText)
            HStack(spacing: OPSStyle.Layout.spacing2) {
                if let next = opportunity.stage.next {
                    actionButton("→ \(next.displayName)", tint: OPSStyle.Colors.primaryAccent, fill: true) {
                        Task { try? await pipelineVM.moveToStage(opportunityId: opportunity.id, to: next, userId: userId) }
                    }
                }
                actionButton("WON", tint: OPSStyle.Colors.successStatus, fill: true) {
                    Task { try? await pipelineVM.markWon(opportunityId: opportunity.id, actualValue: opportunity.estimatedValue, projectId: nil, userId: userId) }
                }
                actionButton("LOST", tint: OPSStyle.Colors.tertiaryText, fill: false) {
                    showLostReason = true
                }
            }
        }
    }

    @ViewBuilder
    private func actionButton(_ label: String, tint: Color, fill: Bool, action: @escaping () -> Void) -> some View {
        Button(action: {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            action()
        }) {
            Text(label)
                .font(OPSStyle.Typography.captionBold)
                .foregroundColor(fill ? OPSStyle.Colors.invertedText : tint)
                .frame(maxWidth: .infinity, minHeight: OPSStyle.Layout.touchTargetStandard)
                .background(fill ? tint : Color.clear)
                .overlay(RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                    .stroke(fill ? Color.clear : tint, lineWidth: OPSStyle.Layout.Border.standard))
                .clipShape(RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius))
        }
    }

    private var activitySection: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
            HStack {
                Text("ACTIVITY")
                    .font(OPSStyle.Typography.captionBold)
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
                Spacer()
                if canManage {
                    Button("+ LOG") { showLogActivity = true }
                        .font(OPSStyle.Typography.captionBold)
                        .foregroundColor(OPSStyle.Colors.primaryAccent)
                }
            }
            if viewModel.activities.isEmpty {
                Text("No activity yet")
                    .font(OPSStyle.Typography.body)
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
            } else {
                ForEach(viewModel.activities) { act in
                    activityRow(act)
                }
            }
        }
    }

    @ViewBuilder
    private func activityRow(_ act: Activity) -> some View {
        HStack(alignment: .top, spacing: OPSStyle.Layout.spacing2) {
            Image(systemName: act.type.icon)
                .font(.system(size: OPSStyle.Layout.IconSize.md))
                .foregroundColor(OPSStyle.Colors.secondaryText)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                if let s = act.subject, !s.isEmpty {
                    Text(s).font(OPSStyle.Typography.bodyBold).foregroundColor(OPSStyle.Colors.primaryText)
                }
                if let body = act.displayBody {
                    Text(body).font(OPSStyle.Typography.body).foregroundColor(OPSStyle.Colors.secondaryText).lineLimit(3)
                }
                Text(formatDate(act.createdAt))
                    .font(OPSStyle.Typography.smallCaption)
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
            }
            Spacer()
        }
        .padding(OPSStyle.Layout.spacing2)
        .background(OPSStyle.Colors.cardBackground)
        .overlay(RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius)
            .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard))
        .clipShape(RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius))
    }

    private var followUpsSection: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
            HStack {
                Text("FOLLOW-UPS")
                    .font(OPSStyle.Typography.captionBold)
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
                Spacer()
                if canManage {
                    Button("+ ADD") { showAddFollowUp = true }
                        .font(OPSStyle.Typography.captionBold)
                        .foregroundColor(OPSStyle.Colors.primaryAccent)
                }
            }
            if viewModel.followUps.isEmpty {
                Text("No follow-ups").font(OPSStyle.Typography.body).foregroundColor(OPSStyle.Colors.tertiaryText)
            } else {
                ForEach(viewModel.followUps) { fu in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(fu.title).font(OPSStyle.Typography.bodyBold).foregroundColor(OPSStyle.Colors.primaryText)
                            Text(formatDate(fu.dueAt)).font(OPSStyle.Typography.smallCaption)
                                .foregroundColor(fu.isOverdue ? OPSStyle.Colors.errorStatus : OPSStyle.Colors.secondaryText)
                        }
                        Spacer()
                        Text(fu.status.rawValue.uppercased())
                            .font(OPSStyle.Typography.smallCaption)
                            .foregroundColor(OPSStyle.Colors.tertiaryText)
                    }
                    .padding(OPSStyle.Layout.spacing2)
                    .background(OPSStyle.Colors.cardBackground)
                    .overlay(RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius)
                        .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard))
                    .clipShape(RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius))
                }
            }
        }
    }

    private var stageHistorySection: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
            Text("STAGE HISTORY")
                .font(OPSStyle.Typography.captionBold)
                .foregroundColor(OPSStyle.Colors.tertiaryText)
            if viewModel.stageTransitions.isEmpty {
                Text("No transitions").font(OPSStyle.Typography.body).foregroundColor(OPSStyle.Colors.tertiaryText)
            } else {
                ForEach(viewModel.stageTransitions) { st in
                    HStack {
                        Text("\(st.fromStage?.displayName ?? "—") → \(st.toStage.displayName)")
                            .font(OPSStyle.Typography.body)
                            .foregroundColor(OPSStyle.Colors.primaryText)
                        Spacer()
                        Text(formatDate(st.transitionedAt))
                            .font(OPSStyle.Typography.smallCaption)
                            .foregroundColor(OPSStyle.Colors.tertiaryText)
                    }
                    .padding(OPSStyle.Layout.spacing2)
                }
            }
        }
    }

    // MARK: - Helpers

    private func formatCurrency(_ v: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "USD"
        f.maximumFractionDigits = 0
        return f.string(from: NSNumber(value: v)) ?? "$\(Int(v))"
    }

    private func formatDate(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "MMM d, h:mma"
        return f.string(from: d)
    }
}
```

- [x] **Step 2: Build & commit**

```bash
xcodebuild -scheme OPS -destination 'generic/platform=iOS' build 2>&1 | tail -5
git add OPS/Views/Books/Pipeline/LeadDetailView.swift
git commit -m "Add LeadDetailView with quick actions, stage actions, activity, follow-ups, stage history"
```

---

### Task 22: Build `EditLeadSheet`

**Files:**
- Create: `OPS/Views/Books/Pipeline/EditLeadSheet.swift`

- [x] **Step 1: Write the view**

Same field set as `AddLeadSheet` plus a stage picker (force-move). On save, calls `pipelineVM.update(opportunityId:fields:)` (a thin wrapper around repo's `update`). Same form chrome — copy the structure from `AddLeadSheet` and adapt:
- Init takes `opportunity: Opportunity`; pre-fills all fields.
- Save constructs `UpdateOpportunityDTO` and calls `repo.update(opportunity.id, fields:)`.
- Adds a stage `Picker` showing all `PipelineStage.allCases` — on commit, also call `moveToStage` if stage changed (so transition row is recorded).

Code template (abbreviated for plan brevity — implementation should follow AddLeadSheet exactly):

```swift
import SwiftUI

struct EditLeadSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var dataController: DataController

    let opportunity: Opportunity
    @ObservedObject var pipelineVM: PipelineViewModel

    @State private var title: String
    @State private var contactName: String
    // ... same fields as AddLeadSheet pre-filled from `opportunity` ...
    @State private var stage: PipelineStage

    init(opportunity: Opportunity, pipelineVM: PipelineViewModel) {
        self.opportunity = opportunity
        self.pipelineVM = pipelineVM
        _title = State(initialValue: opportunity.title ?? "")
        _contactName = State(initialValue: opportunity.contactName)
        _stage = State(initialValue: opportunity.stage)
        // ... pre-fill remaining fields ...
    }

    var body: some View {
        // Same NavigationStack + form chrome as AddLeadSheet
        // PLUS a Stage Picker section
        // Save action:
        //   1. If stage changed → call pipelineVM.moveToStage(...)
        //   2. PATCH other fields via repo.update(opp.id, UpdateOpportunityDTO(...))
        EmptyView() // Replace with full form
    }
}
```

- [x] **Step 2: Build & commit**

```bash
xcodebuild -scheme OPS -destination 'generic/platform=iOS' build 2>&1 | tail -5
git add OPS/Views/Books/Pipeline/EditLeadSheet.swift
git commit -m "Add EditLeadSheet with field edit + stage force-move"
```

> **Drift note (impl):** Built EditLeadSheet as the full form mirroring `AddLeadSheet` (T16) field set + a stage `Picker`. Pre-fills from `Opportunity` (note: model field is `descriptionText`, not the plan's `opportunityDescription`). On save, diffs old vs new — calls `pipelineVM.moveToStage` first if stage changed (records a `stage_transitions` row), then PATCHes only the changed non-stage fields via `repo.update(opp.id, fields: UpdateOpportunityDTO(...))`. Updates the in-memory `pipelineVM.allOpportunities` to reflect the change. Wired directly into `LeadDetailView` (Step 3) — no placeholder.

- [x] **Step 3: Wire EditLeadSheet into LeadDetailView**

Replace the `Text("Edit sheet placeholder — see Task 22")` body in LeadDetailView's `.sheet(isPresented: $showEditSheet)` with:

```swift
EditLeadSheet(opportunity: opportunity, pipelineVM: pipelineVM)
    .environmentObject(dataController)
```

Run: `xcodebuild -scheme OPS -destination 'generic/platform=iOS' build 2>&1 | tail -5`. Commit.

---

### Task 23: Build `BooksSection` enum + `PipelineSectionView`

**Files:**
- Create: `OPS/Views/Books/BooksSection.swift`
- Create: `OPS/Views/Books/Pipeline/PipelineSectionView.swift`

- [x] **Step 1: Create BooksSection enum**

`OPS/Views/Books/BooksSection.swift`:

```swift
//
//  BooksSection.swift
//  OPS
//

import Foundation

enum BooksSection: String, CaseIterable, Identifiable, Codable {
    case pipeline  = "PIPELINE"
    case estimates = "ESTIMATES"
    case invoices  = "INVOICES"
    case expenses  = "EXPENSES"

    var id: String { rawValue }

    /// Permission required for this segment to be visible.
    var requiredPermission: String {
        switch self {
        case .pipeline:  return "pipeline.view"
        case .estimates: return "estimates.view"
        case .invoices:  return "finances.view"
        case .expenses:  return "expenses.view"
        }
    }

    /// FAB primary action label for this segment.
    var fabActionLabel: String {
        switch self {
        case .pipeline:  return "Add Lead"
        case .estimates: return "New Estimate"
        case .invoices:  return "New Invoice"
        case .expenses:  return "New Expense"
        }
    }
}
```

- [x] **Step 2: Create PipelineSectionView**

`OPS/Views/Books/Pipeline/PipelineSectionView.swift`:

```swift
//
//  PipelineSectionView.swift
//  OPS
//
//  Pipeline segment root — composes StageStripView + lead list +
//  empty/loading/error states.
//

import SwiftUI

struct PipelineSectionView: View {
    @StateObject private var viewModel = PipelineViewModel()
    @EnvironmentObject private var dataController: DataController
    @EnvironmentObject private var permissionStore: PermissionStore

    @State private var actionSheetOpportunity: Opportunity?
    @State private var lostReasonOpportunity: Opportunity?
    @State private var detailDestination: Opportunity?

    private var canManage: Bool { permissionStore.can("pipeline.manage") }
    private var userId: String? { dataController.currentUser?.id }

    var body: some View {
        VStack(spacing: 0) {
            StageStripView(
                selectedStage: $viewModel.selectedStage,
                countProvider: { viewModel.count(in: $0) }
            )

            if viewModel.isLoading {
                Spacer()
                TacticalLoadingBarAnimated()
                Spacer()
            } else if let error = viewModel.loadError {
                errorState(error)
            } else if viewModel.isPipelineEmpty {
                pipelineEmptyState
            } else {
                let leads = viewModel.opportunities(in: viewModel.selectedStage)
                if leads.isEmpty {
                    stageEmptyState
                } else {
                    ScrollView {
                        LazyVStack(spacing: OPSStyle.Layout.spacing2) {
                            ForEach(leads) { lead in
                                LeadCardView(
                                    opportunity: lead,
                                    canManage: canManage,
                                    onTap: { detailDestination = lead },
                                    onAdvance: {
                                        guard let next = lead.stage.next else { return }
                                        Task { try? await viewModel.moveToStage(opportunityId: lead.id, to: next, userId: userId) }
                                    },
                                    onWon: {
                                        Task { try? await viewModel.markWon(opportunityId: lead.id, actualValue: lead.estimatedValue, projectId: nil, userId: userId) }
                                    },
                                    onLost: { lostReasonOpportunity = lead },
                                    onMore: { actionSheetOpportunity = lead }
                                )
                            }
                        }
                        .padding(.horizontal, OPSStyle.Layout.spacing3)
                        .padding(.vertical, OPSStyle.Layout.spacing3)
                    }
                    .refreshable { await viewModel.loadData() }
                }
            }
        }
        .background(OPSStyle.Colors.background)
        .task {
            if let companyId = dataController.currentUser?.companyId {
                viewModel.setup(companyId: companyId)
                await viewModel.loadData()
            }
        }
        .navigationDestination(item: $detailDestination) { lead in
            LeadDetailView(opportunity: lead, pipelineVM: viewModel)
                .environmentObject(dataController)
                .environmentObject(permissionStore)
        }
        .sheet(item: $actionSheetOpportunity) { lead in
            LeadActionSheet(
                opportunity: lead,
                canManage: canManage,
                onMoveToStage: { stage in
                    Task { try? await viewModel.moveToStage(opportunityId: lead.id, to: stage, userId: userId) }
                },
                onEdit: { detailDestination = lead /* opens detail; user taps edit there */ },
                onLogActivity: { detailDestination = lead },
                onAddFollowUp: { detailDestination = lead },
                onOpenDetail: { detailDestination = lead },
                onArchive: { Task { try? await viewModel.archive(opportunityId: lead.id) } },
                onDelete: { Task { try? await viewModel.softDelete(opportunityId: lead.id) } }
            )
        }
        .sheet(item: $lostReasonOpportunity) { lead in
            LostReasonSheet(opportunityTitle: lead.title ?? lead.contactName) { reason, notes in
                Task { try? await viewModel.markLost(opportunityId: lead.id, reason: reason, notes: notes, userId: userId) }
            }
        }
    }

    // MARK: - States

    private var pipelineEmptyState: some View {
        VStack(spacing: OPSStyle.Layout.spacing3) {
            Spacer()
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.system(size: OPSStyle.Layout.IconSize.xl))
                .foregroundColor(OPSStyle.Colors.tertiaryText)
            Text("NO LEADS YET")
                .font(OPSStyle.Typography.bodyBold)
                .foregroundColor(OPSStyle.Colors.primaryText)
            Text("Tap + to add your first lead")
                .font(OPSStyle.Typography.smallCaption)
                .foregroundColor(OPSStyle.Colors.tertiaryText)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var stageEmptyState: some View {
        VStack(spacing: OPSStyle.Layout.spacing3) {
            Spacer()
            Text(emptyCopy(for: viewModel.selectedStage))
                .font(OPSStyle.Typography.bodyBold)
                .foregroundColor(OPSStyle.Colors.tertiaryText)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func emptyCopy(for stage: PipelineStage) -> String {
        switch stage {
        case .won:  return "NO WINS YET — KEEP MOVING"
        case .lost: return "NO LOSSES"
        default:    return "NO LEADS IN \(stage.displayName)"
        }
    }

    private func errorState(_ error: String) -> some View {
        VStack(spacing: OPSStyle.Layout.spacing3) {
            Spacer()
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: OPSStyle.Layout.IconSize.xl))
                .foregroundColor(OPSStyle.Colors.warningStatus)
            Text("COULD NOT LOAD LEADS")
                .font(OPSStyle.Typography.bodyBold)
                .foregroundColor(OPSStyle.Colors.primaryText)
            Text(error)
                .font(OPSStyle.Typography.smallCaption)
                .foregroundColor(OPSStyle.Colors.tertiaryText)
                .multilineTextAlignment(.center)
            Button("TAP TO RETRY") { Task { await viewModel.loadData() } }
                .font(OPSStyle.Typography.bodyBold)
                .foregroundColor(OPSStyle.Colors.primaryAccent)
            Spacer()
        }
        .padding(.horizontal, OPSStyle.Layout.spacing4)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
```

- [x] **Step 3: Build & commit**

```bash
xcodebuild -scheme OPS -destination 'generic/platform=iOS' build 2>&1 | tail -10
git add OPS/Views/Books/BooksSection.swift OPS/Views/Books/Pipeline/PipelineSectionView.swift
git commit -m "Add BooksSection enum and PipelineSectionView (Stage-Pager root)"
```

---

## Phase 1C — Hub Shell

### Task 24: Add `.books` case to `AppHeader.HeaderType`

**Files:**
- Modify: `OPS/Views/Components/Common/AppHeader.swift`

- [x] **Step 1: Add the case**

Open `AppHeader.swift`. In the `HeaderType` enum (around line 58), add `case books` after `case pipeline`. In the `title` computed var (around line 110), add:

```swift
case .books:
    return "BOOKS"
```

Leave `.pipeline` in place (still used by old MoneyTabView until Task 25 swaps it).

- [x] **Step 2: Build & commit**

```bash
xcodebuild -scheme OPS -destination 'generic/platform=iOS' build 2>&1 | tail -5
git add OPS/Views/Components/Common/AppHeader.swift
git commit -m "Add HeaderType.books case to AppHeader with BOOKS title"
```

---

### Task 25: Build `BooksTabView`

**Files:**
- Create: `OPS/Views/Books/BooksTabView.swift`

- [ ] **Step 1: Write the view**

```swift
//
//  BooksTabView.swift
//  OPS
//
//  Hub container for BOOKS tab. Replaces MoneyTabView.
//  Top: AppHeader + MoneyDashboardHeader (collapsible).
//  Below: 4-segment underline control (Pipeline · Estimates · Invoices · Expenses).
//  Routes to existing list views for the latter three; new PipelineSectionView for the first.
//

import SwiftUI

private struct HeaderBottomKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

struct BooksTabView: View {
    @StateObject private var dashboardVM = MoneyDashboardViewModel()
    @StateObject private var estimateVM = EstimateViewModel()
    @StateObject private var invoiceVM = InvoiceViewModel()
    @StateObject private var expenseVM = ExpenseViewModel()

    @EnvironmentObject private var dataController: DataController
    @EnvironmentObject private var permissionStore: PermissionStore
    @EnvironmentObject var appState: AppState
    @Environment(\.modelContext) private var modelContext

    // Active segment persisted across sessions and visible to FloatingActionMenu.
    @AppStorage("books.selectedSegment") private var selectedSegmentRaw: String = BooksSection.pipeline.rawValue

    @State private var headerCollapsed = false
    @State private var showARDetail = false

    private var selectedSegment: BooksSection {
        get { BooksSection(rawValue: selectedSegmentRaw) ?? .pipeline }
    }

    private var visibleSegments: [BooksSection] {
        BooksSection.allCases.filter { permissionStore.can($0.requiredPermission) }
    }

    private var hasFinances: Bool { permissionStore.can("finances.view") }
    private var hasPipelineView: Bool { permissionStore.can("pipeline.view") }
    private var expensesScopeIsOwn: Bool {
        // If user has expenses.view but not at "all" scope, treat as own.
        permissionStore.can("expenses.view") && !permissionStore.hasFullAccess("expenses.view")
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                AppHeader(headerType: .books)
                    .padding(.bottom, 8)

                if headerCollapsed {
                    underlineSegmentedControl
                        .background(OPSStyle.Colors.background)
                        .transition(.opacity)
                }

                ScrollView {
                    VStack(spacing: 0) {
                        // Dashboard — only when user has SOMETHING to put in it
                        if hasFinances || hasPipelineView {
                            MoneyDashboardHeader(viewModel: dashboardVM, onStatTap: { stat in
                                if stat == .overdue {
                                    showARDetail = true
                                }
                            })
                            .background(
                                GeometryReader { geo in
                                    Color.clear.preference(
                                        key: HeaderBottomKey.self,
                                        value: geo.frame(in: .named("scroll")).maxY
                                    )
                                }
                            )
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
        }
        .trackScreen("Books")
        .task {
            setupViewModels()
            await dashboardVM.loadData()
            // Default segment fallback: if persisted segment is no longer permitted, jump to first visible.
            if !visibleSegments.contains(selectedSegment), let first = visibleSegments.first {
                selectedSegmentRaw = first.rawValue
            }
        }
    }

    // MARK: - Segmented control

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

    // MARK: - Content per segment

    @ViewBuilder
    private var contentForSegment: some View {
        Group {
            switch selectedSegment {
            case .pipeline:
                PipelineSectionView()
                    .environmentObject(dataController)
                    .environmentObject(permissionStore)
            case .estimates:
                EstimatesListView(embedded: true)
            case .invoices:
                InvoicesListView(embedded: true)
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

    // MARK: - Setup

    private func setupViewModels() {
        guard let companyId = dataController.currentUser?.companyId, !companyId.isEmpty else { return }
        dashboardVM.setup(companyId: companyId, modelContext: modelContext)
        estimateVM.setup(companyId: companyId, modelContext: modelContext)
        invoiceVM.setup(companyId: companyId, modelContext: modelContext)
        expenseVM.setup(companyId: companyId)
    }
}
```

- [ ] **Step 2: Build — expect error because `MoneyDashboardHeader.onStatTap` doesn't accept `.overdue → action` yet**

Run: `xcodebuild -scheme OPS -destination 'generic/platform=iOS' build 2>&1 | grep -E "error:" | head -5`

If the error is about `onStatTap` arg type, that's expected — fixed in Task 28 (dashboard wiring). For now, commit just the new file as a stub:

- [ ] **Step 3: Adjust callsite to use a no-op closure temporarily**

Replace the `MoneyDashboardHeader(viewModel: dashboardVM, onStatTap: { ... })` line with `MoneyDashboardHeader(viewModel: dashboardVM, onStatTap: { _ in })` if the existing API doesn't match. Restore in Task 28.

- [ ] **Step 4: Build & commit**

```bash
xcodebuild -scheme OPS -destination 'generic/platform=iOS' build 2>&1 | tail -5
git add OPS/Views/Books/BooksTabView.swift
git commit -m "Add BooksTabView hub shell with adaptive segmented control"
```

---

### Task 26: Wire `BooksTabView` into `MainTabView`

**Files:**
- Modify: `OPS/Views/MainTabView.swift:226-227`

- [ ] **Step 1: Swap the render call**

Change:
```swift
} else if selectedTab == pipelineTabIndex {
    MoneyTabView()
```
To:
```swift
} else if selectedTab == pipelineTabIndex {
    BooksTabView()
```

- [ ] **Step 2: Update wizard step ID for the renamed tab (line 162)**

Change `wizardStepId: "welcome_pipeline"` to `wizardStepId: "welcome_books"` (or keep — depends on whether wizard step IDs are referenced elsewhere; safer to keep for now and rename in a follow-up sweep).

For Phase 1: keep the wizard ID and only rename the user-facing surface.

- [ ] **Step 3: Build & commit**

```bash
xcodebuild -scheme OPS -destination 'generic/platform=iOS' build 2>&1 | tail -5
git add OPS/Views/MainTabView.swift
git commit -m "Render BooksTabView in the BOOKS tab slot (replaces MoneyTabView)"
```

---

### Task 27: Delete `MoneyTabView.swift`

**Files:**
- Delete: `OPS/Views/Money/MoneyTabView.swift`

- [ ] **Step 1: Verify no remaining consumers**

Run: `grep -rn "MoneyTabView" OPS/ --include='*.swift'`
Expected: zero matches (Task 26 removed the only render site).

- [ ] **Step 2: Delete the file**

```bash
rm OPS/Views/Money/MoneyTabView.swift
```

- [ ] **Step 3: Build (verify Xcode auto-discovery picks up the deletion)**

If `xcodebuild` errors with "file not found" referring to MoneyTabView, the file is still listed in `project.pbxproj` — open Xcode and remove the reference, OR edit `project.pbxproj` manually to remove the file reference and build phase entry.

Run: `xcodebuild -scheme OPS -destination 'generic/platform=iOS' build 2>&1 | tail -5`
Expected: BUILD SUCCEEDED.

- [ ] **Step 4: Commit**

```bash
git add OPS/Views/Money/MoneyTabView.swift OPS.xcodeproj/project.pbxproj
git commit -m "Delete MoneyTabView (replaced by BooksTabView)"
```

---

## Phase 1D — Dashboard Extension + AR Aging Drilldown

### Task 28: Extend `SmartStatCarousel` with pipeline stat cases

**Files:**
- Modify: `OPS/Views/Money/Components/SmartStatCarousel.swift`

- [ ] **Step 1: Add new StatType cases + init params**

In the `StatType` enum (around line 22), add:

```swift
case activeLeads, staleLeads, nextFollowUp
```

Add new optional init parameters at the top of the struct:

```swift
var activeLeadCount: Int = 0
var weightedForecastValue: Double = 0
var staleLeadsCount: Int = 0
var nextFollowUpDue: Date? = nil
```

Update `orderedCards` to include the new cards conditionally — insert them at the end of the active-stages priority list (i.e. after pendingEstimates, before topUnpaid):

```swift
if activeLeadCount > 0 {
    cards.append(CardData(
        type: .activeLeads,
        value: "\(activeLeadCount)",
        label: "ACTIVE LEADS",
        detail: formatCurrency(weightedForecastValue),
        accentColor: OPSStyle.Colors.accountingProfit
    ))
}

if staleLeadsCount > 0 {
    cards.append(CardData(
        type: .staleLeads,
        value: "\(staleLeadsCount)",
        label: "STALE LEADS",
        detail: nil,
        accentColor: OPSStyle.Colors.accountingOverdue
    ))
}

if let next = nextFollowUpDue {
    cards.append(CardData(
        type: .nextFollowUp,
        value: shortDate(next),
        label: "NEXT FOLLOW-UP",
        detail: nil,
        accentColor: OPSStyle.Colors.accountingReceivables
    ))
}
```

Add the helper:

```swift
private func shortDate(_ d: Date) -> String {
    let f = DateFormatter()
    f.dateFormat = "MMM d"
    return f.string(from: d)
}
```

- [ ] **Step 2: Build & commit**

```bash
xcodebuild -scheme OPS -destination 'generic/platform=iOS' build 2>&1 | tail -5
git add OPS/Views/Money/Components/SmartStatCarousel.swift
git commit -m "Extend SmartStatCarousel with active/stale leads and next follow-up stats"
```

---

### Task 29: Extend `MoneyDashboardViewModel` to load opportunities

**Files:**
- Modify: `OPS/ViewModels/MoneyDashboardViewModel.swift`

- [ ] **Step 1: Add private repo + cached opps + 4 new published properties**

Near the existing `private var allInvoices: [InvoiceDTO] = []` block (around line 105):

```swift
private var opportunityRepository: OpportunityRepository?
private var allOpportunities: [OpportunityDTO] = []

@Published var activeLeadCount: Int = 0
@Published var weightedForecastValue: Double = 0
@Published var staleLeadsCount: Int = 0
@Published var nextFollowUpDue: Date? = nil
```

- [ ] **Step 2: Initialize repo in `setup()`**

In the existing `setup()` method, add:

```swift
opportunityRepository = OpportunityRepository(companyId: companyId)
```

- [ ] **Step 3: Add a guarded `fetchOpportunities()` and a permission-aware path through `loadData()`**

Add a helper:

```swift
private func fetchOpportunities() async -> [OpportunityDTO] {
    guard let repo = opportunityRepository else { return [] }
    do { return try await repo.fetchAll() }
    catch { print("[MoneyDashboard] opps load failed: \(error)"); return [] }
}
```

Modify `loadData()` to fan out 4 parallel fetches when pipeline access is granted:

```swift
func loadData() async {
    guard estimateRepository != nil,
          invoiceRepository != nil,
          expenseRepository != nil else { return }

    isLoading = true
    defer { isLoading = false }

    let canSeePipeline = PermissionStore.shared.can("pipeline.view")

    async let estimatesTask = fetchEstimates()
    async let invoicesTask = fetchInvoices()
    async let expensesTask = fetchExpenses()
    async let oppsTask: [OpportunityDTO] = canSeePipeline ? fetchOpportunities() : []

    let (estimates, invoices, expenses, opps) = await (estimatesTask, invoicesTask, expensesTask, oppsTask)

    allEstimates = estimates
    allInvoices = invoices
    allExpenses = expenses
    allOpportunities = opps

    recalculate()
}
```

- [ ] **Step 4: Compute pipeline metrics in `recalculate()`**

At the end of `recalculate()`, add:

```swift
// ── Pipeline metrics (only meaningful if loaded) ──
let activeOpps = allOpportunities.filter { dto in
    let stage = PipelineStage(rawValue: dto.stage)
    let isTerminal = stage?.isTerminal ?? false
    return !isTerminal && dto.deletedAt == nil && dto.archivedAt == nil
}
activeLeadCount = activeOpps.count
weightedForecastValue = activeOpps.reduce(0) { sum, dto in
    let stage = PipelineStage(rawValue: dto.stage) ?? .newLead
    let pct = dto.winProbability ?? stage.winProbability
    let est = dto.estimatedValue ?? 0
    return sum + (est * Double(pct) / 100.0)
}
staleLeadsCount = activeOpps.filter { dto in
    guard let stage = PipelineStage(rawValue: dto.stage),
          let entered = SupabaseDate.parse(dto.stageEnteredAt) else { return false }
    let days = Calendar.current.dateComponents([.day], from: entered, to: Date()).day ?? 0
    return days > stage.staleThresholdDays
}.count
nextFollowUpDue = activeOpps
    .compactMap { $0.nextFollowUpAt.flatMap { SupabaseDate.parse($0) } }
    .filter { $0 >= Date() }
    .min()
```

- [ ] **Step 5: Build & commit**

```bash
xcodebuild -scheme OPS -destination 'generic/platform=iOS' build 2>&1 | tail -5
git add OPS/ViewModels/MoneyDashboardViewModel.swift
git commit -m "Extend MoneyDashboardViewModel with pipeline stats (active/stale/forecast/follow-up)"
```

---

### Task 30: Pass new pipeline stats from `MoneyDashboardHeader` to `SmartStatCarousel`

**Files:**
- Modify: `OPS/Views/Money/Components/MoneyDashboardHeader.swift`

- [ ] **Step 1: Update the `SmartStatCarousel` call site**

Replace the existing carousel construction with:

```swift
SmartStatCarousel(
    overdueCount: viewModel.overdueInvoicesCount,
    overdueValue: viewModel.overdueInvoicesValue,
    pendingEstimatesCount: viewModel.pendingEstimatesCount,
    pendingEstimatesValue: viewModel.pendingEstimatesValue,
    closeRate: viewModel.closeRate,
    avgDaysToPayment: viewModel.avgDaysToPayment,
    expensesTrend: viewModel.expensesTrend,
    topUnpaid: viewModel.topUnpaidInvoices,
    activeLeadCount: viewModel.activeLeadCount,
    weightedForecastValue: viewModel.weightedForecastValue,
    staleLeadsCount: viewModel.staleLeadsCount,
    nextFollowUpDue: viewModel.nextFollowUpDue,
    onStatTap: onStatTap
)
```

- [ ] **Step 2: Build & commit**

```bash
xcodebuild -scheme OPS -destination 'generic/platform=iOS' build 2>&1 | tail -5
git add OPS/Views/Money/Components/MoneyDashboardHeader.swift
git commit -m "Wire pipeline stats from MoneyDashboardViewModel into SmartStatCarousel"
```

---

### Task 31: Build `ARAgingDetailView` (replaces `AccountingDashboard`)

**Files:**
- Create: `OPS/Views/Books/ARAgingDetailView.swift`

- [ ] **Step 1: Write the view**

```swift
//
//  ARAgingDetailView.swift
//  OPS
//
//  Drill-down from the SmartStatCarousel "OVERDUE" tap. Shows AR aging
//  buckets + top outstanding clients. Replaces the orphan AccountingDashboard.
//

import SwiftUI
import Charts

struct ARAgingDetailView: View {
    @EnvironmentObject private var dataController: DataController
    @Environment(\.dismiss) private var dismiss

    @State private var invoices: [Invoice] = []
    @State private var clientNames: [String: String] = [:]
    @State private var isLoading = true
    @State private var loadError: String?

    private struct Bucket: Identifiable {
        let id = UUID()
        let label: String
        let amount: Double
        let color: Color
    }

    private var buckets: [Bucket] {
        let today = Date()
        var b0_30: Double = 0; var b31_60: Double = 0
        var b61_90: Double = 0; var b90: Double = 0
        for inv in invoices where inv.balanceDue > 0 && inv.status != .void {
            guard let due = inv.dueDate else { continue }
            let days = Int(today.timeIntervalSince(due) / 86400)
            if days < 0 { continue }
            switch days {
            case 0...30: b0_30 += inv.balanceDue
            case 31...60: b31_60 += inv.balanceDue
            case 61...90: b61_90 += inv.balanceDue
            default: b90 += inv.balanceDue
            }
        }
        return [
            Bucket(label: "0–30d", amount: b0_30, color: OPSStyle.Colors.accountingReceivables),
            Bucket(label: "31–60d", amount: b31_60, color: OPSStyle.Colors.accountingReceivables),
            Bucket(label: "61–90d", amount: b61_90, color: OPSStyle.Colors.warningStatus),
            Bucket(label: "90d+", amount: b90, color: OPSStyle.Colors.accountingOverdue),
        ]
    }

    private var topOutstanding: [(name: String, amount: Double)] {
        var totals: [String: Double] = [:]
        for inv in invoices where inv.balanceDue > 0 && inv.status != .void {
            let key = inv.clientId ?? "Unknown"
            totals[key, default: 0] += inv.balanceDue
        }
        return totals
            .sorted { $0.value > $1.value }
            .prefix(5)
            .map { (name: clientNames[$0.key] ?? "Unknown", amount: $0.value) }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                OPSStyle.Colors.background.ignoresSafeArea()
                if isLoading {
                    TacticalLoadingBarAnimated()
                        .task { await load() }
                } else if let error = loadError {
                    errorView(error)
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing4) {
                            agingChartSection
                            topOutstandingSection
                        }
                        .padding(OPSStyle.Layout.spacing3)
                    }
                    .refreshable { await load() }
                }
            }
            .navigationTitle("AR AGING")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("DONE") { dismiss() }
                        .foregroundColor(OPSStyle.Colors.primaryAccent)
                }
            }
        }
    }

    private var agingChartSection: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
            Text("AGING BUCKETS")
                .font(OPSStyle.Typography.captionBold)
                .foregroundColor(OPSStyle.Colors.tertiaryText)
            if buckets.allSatisfy({ $0.amount == 0 }) {
                Text("No outstanding invoices")
                    .font(OPSStyle.Typography.body)
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
            } else {
                Chart(buckets) { b in
                    BarMark(
                        x: .value("Amount", b.amount),
                        y: .value("Period", b.label)
                    )
                    .foregroundStyle(b.color)
                    .annotation(position: .trailing) {
                        Text(b.amount, format: .currency(code: "USD").precision(.fractionLength(0)))
                            .font(OPSStyle.Typography.smallCaption)
                            .foregroundColor(OPSStyle.Colors.secondaryText)
                    }
                }
                .chartXAxis(.hidden)
                .frame(height: 180)
            }
        }
    }

    private var topOutstandingSection: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
            Text("TOP OUTSTANDING")
                .font(OPSStyle.Typography.captionBold)
                .foregroundColor(OPSStyle.Colors.tertiaryText)
            if topOutstanding.isEmpty {
                Text("No outstanding balances")
                    .font(OPSStyle.Typography.body)
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(topOutstanding.enumerated()), id: \.offset) { idx, entry in
                        HStack {
                            Text(entry.name)
                                .font(OPSStyle.Typography.body)
                                .foregroundColor(OPSStyle.Colors.primaryText)
                                .lineLimit(1)
                            Spacer()
                            Text(entry.amount, format: .currency(code: "USD").precision(.fractionLength(0)))
                                .font(OPSStyle.Typography.body)
                                .foregroundColor(OPSStyle.Colors.primaryText)
                        }
                        .padding(.horizontal, OPSStyle.Layout.spacing3)
                        .frame(minHeight: OPSStyle.Layout.touchTargetStandard)
                        if idx < topOutstanding.count - 1 {
                            Divider().background(OPSStyle.Colors.cardBorder)
                        }
                    }
                }
                .background(OPSStyle.Colors.cardBackground)
                .overlay(RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius)
                    .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard))
                .clipShape(RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius))
            }
        }
    }

    private func errorView(_ msg: String) -> some View {
        VStack(spacing: OPSStyle.Layout.spacing3) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: OPSStyle.Layout.IconSize.xl))
                .foregroundColor(OPSStyle.Colors.warningStatus)
            Text("COULD NOT LOAD AR DATA")
                .font(OPSStyle.Typography.bodyBold)
                .foregroundColor(OPSStyle.Colors.primaryText)
            Text(msg).font(OPSStyle.Typography.smallCaption).foregroundColor(OPSStyle.Colors.tertiaryText)
            Button("RETRY") { Task { await load() } }
                .foregroundColor(OPSStyle.Colors.primaryAccent)
        }
        .padding(OPSStyle.Layout.spacing4)
    }

    private func load() async {
        guard let companyId = dataController.currentUser?.companyId else { isLoading = false; return }
        loadError = nil
        let repo = AccountingRepository(companyId: companyId)
        do {
            let dtos = try await repo.fetchAllInvoices()
            invoices = dtos.map { $0.toModel() }
            buildClientLookup()
        } catch {
            if !error.isCancellation { loadError = error.localizedDescription }
        }
        isLoading = false
    }

    private func buildClientLookup() {
        guard let companyId = dataController.currentUser?.companyId else { return }
        let clients = dataController.getAllClients(for: companyId)
        clientNames = Dictionary(uniqueKeysWithValues: clients.map { ($0.id, $0.displayName) })
    }
}
```

- [ ] **Step 2: Build & commit**

```bash
xcodebuild -scheme OPS -destination 'generic/platform=iOS' build 2>&1 | tail -5
git add OPS/Views/Books/ARAgingDetailView.swift
git commit -m "Add ARAgingDetailView (drill-down from carousel OVERDUE stat)"
```

---

### Task 32: Restore the BooksTabView onStatTap routing

**Files:**
- Modify: `OPS/Views/Books/BooksTabView.swift` (the `onStatTap` closure on `MoneyDashboardHeader`)

- [ ] **Step 1: Replace the temporary `{ _ in }` closure with the real routing**

Find:
```swift
MoneyDashboardHeader(viewModel: dashboardVM, onStatTap: { _ in })
```

Replace with:
```swift
MoneyDashboardHeader(viewModel: dashboardVM, onStatTap: { stat in
    switch stat {
    case .overdue:
        showARDetail = true
    case .activeLeads, .staleLeads, .nextFollowUp:
        // Jump to Pipeline segment so the user can see the leads.
        selectedSegmentRaw = BooksSection.pipeline.rawValue
    default:
        break
    }
})
```

- [ ] **Step 2: Build & commit**

```bash
xcodebuild -scheme OPS -destination 'generic/platform=iOS' build 2>&1 | tail -5
git add OPS/Views/Books/BooksTabView.swift
git commit -m "Wire SmartStatCarousel taps in BOOKS hub: overdue→AR detail, pipeline stats→Pipeline segment"
```

---

### Task 33: Delete `AccountingDashboard.swift`

**Files:**
- Delete: `OPS/Views/Accounting/AccountingDashboard.swift`

- [ ] **Step 1: Verify no remaining consumers**

Run: `grep -rn "AccountingDashboard" OPS/ --include='*.swift'`
Expected: zero matches.

- [ ] **Step 2: Delete the file (and the empty parent directory)**

```bash
rm OPS/Views/Accounting/AccountingDashboard.swift
rmdir OPS/Views/Accounting 2>/dev/null || true
```

- [ ] **Step 3: Build (handle pbxproj reference removal as in Task 27)**

Run: `xcodebuild -scheme OPS -destination 'generic/platform=iOS' build 2>&1 | tail -5`

- [ ] **Step 4: Commit**

```bash
git add OPS/Views/Accounting OPS.xcodeproj/project.pbxproj
git commit -m "Delete orphan AccountingDashboard (replaced by ARAgingDetailView)"
```

---

## Phase 1E — FAB Integration

### Task 34: Add "Add Lead" item to FAB MONEY group + segment-aware ordering

**Files:**
- Modify: `OPS/Views/Components/FloatingActionMenu.swift`

- [ ] **Step 1: Add the AppStorage key + Add Lead state**

Near the existing `@AppStorage("catalog.selectedSegment")` (around line 110), add:

```swift
@AppStorage("books.selectedSegment") private var booksSelectedSegmentRaw: String = "PIPELINE"
@State private var showingAddLead = false
```

- [ ] **Step 2: Add "Add Lead" item to the MONEY group**

Inside the `if permissionStore.isFeatureEnabled("pipeline")` block that builds the MONEY group (around line 319), prepend a new item:

```swift
groups.append(
    FABMenuGroup(id: "money", title: "MONEY", items: orderedMoneyItems(rawItems: [
        FABMenuItem(
            id: "add-lead",
            icon: "person.badge.plus",
            label: "Add Lead",
            permission: "pipeline.manage",
            disabledInTutorial: true,
            action: {
                showCreateMenu = false
                showingAddLead = true
            }
        ),
        FABMenuItem(
            id: "new-estimate",
            // ... existing definition unchanged ...
        ),
        FABMenuItem(
            id: "new-invoice",
            // ... existing ...
        ),
        FABMenuItem(
            id: "new-payment",
            // ... existing ...
        ),
    ]))
)
```

Add helper that reorders based on active BOOKS segment:

```swift
private func orderedMoneyItems(rawItems: [FABMenuItem]) -> [FABMenuItem] {
    let primaryId: String
    switch booksSelectedSegmentRaw {
    case "PIPELINE":  primaryId = "add-lead"
    case "ESTIMATES": primaryId = "new-estimate"
    case "INVOICES":  primaryId = "new-invoice"
    case "EXPENSES":  primaryId = "new-expense"   // Note: lives in EXPENSES group
    default:          primaryId = "new-estimate"
    }
    if let idx = rawItems.firstIndex(where: { $0.id == primaryId }), idx > 0 {
        var reordered = rawItems
        let primary = reordered.remove(at: idx)
        reordered.insert(primary, at: 0)
        return reordered
    }
    return rawItems
}
```

- [ ] **Step 3: Wire the AddLeadSheet presentation**

Add a `.sheet(isPresented: $showingAddLead)` block alongside existing sheets:

```swift
.sheet(isPresented: $showingAddLead) {
    AddLeadSheet { _ in
        // Toast handled by PINGatedView observer pattern; nothing to do here.
        // Optionally post a NotificationCenter event for Pipeline section to refresh.
        NotificationCenter.default.post(name: Notification.Name("LeadCreatedSuccess"), object: nil)
    }
    .environmentObject(dataController)
}
```

- [ ] **Step 4: Hook a refresh listener in `PipelineSectionView`**

In `PipelineSectionView.swift`, add to the `.task` block:

```swift
.onReceive(NotificationCenter.default.publisher(for: Notification.Name("LeadCreatedSuccess"))) { _ in
    Task { await viewModel.loadData() }
}
```

- [ ] **Step 5: Build & commit**

```bash
xcodebuild -scheme OPS -destination 'generic/platform=iOS' build 2>&1 | tail -5
git add OPS/Views/Components/FloatingActionMenu.swift OPS/Views/Books/Pipeline/PipelineSectionView.swift
git commit -m "Add 'Add Lead' FAB action with segment-aware ordering for BOOKS"
```

---

## Phase 1F — Permission Gating + Auto-Skip Routing

### Task 35: Add auto-skip routing for single-permission users

**Files:**
- Modify: `OPS/Views/MainTabView.swift` (around the BooksTabView render site)

- [ ] **Step 1: Add a helper that determines the user's single visible segment, if any**

Inside `MainTabView`, near the existing `hasPipelineAccess` computed:

```swift
private var visibleBooksSegments: [BooksSection] {
    BooksSection.allCases.filter { permissionStore.can($0.requiredPermission) }
}

private var booksAutoSkipDestination: AnyView? {
    let segs = visibleBooksSegments
    guard segs.count == 1, let only = segs.first else { return nil }
    switch only {
    case .pipeline:  return nil  // pipeline alone still benefits from the hub chrome
    case .estimates: return AnyView(NavigationStack { EstimatesListView() })
    case .invoices:  return AnyView(NavigationStack { InvoicesListView() })
    case .expenses:
        let scopeIsOwn = !permissionStore.hasFullAccess("expenses.view")
        if scopeIsOwn {
            return AnyView(NavigationStack { MyExpensesView() })
        } else {
            return AnyView(NavigationStack { ExpensesListView() })
        }
    }
}
```

- [ ] **Step 2: Replace the `BooksTabView()` render**

```swift
} else if selectedTab == pipelineTabIndex {
    if let destination = booksAutoSkipDestination {
        destination
    } else {
        BooksTabView()
    }
}
```

- [ ] **Step 3: Update tab visibility — show BOOKS tab if ANY of the four segment perms exist**

In the `tabs` computed property, replace the existing pipeline-tab gate:

```swift
if hasPipelineAccess {
    baseTabs.append(TabItem(iconName: "chart.line.uptrend.xyaxis", wizardStepId: "welcome_books"))
}
```

with:

```swift
let hasBooksAccess = permissionStore.can("pipeline.view")
    || permissionStore.can("finances.view")
    || permissionStore.can("estimates.view")
    || permissionStore.can("expenses.view")

if hasBooksAccess {
    baseTabs.append(TabItem(iconName: "chart.line.uptrend.xyaxis", wizardStepId: "welcome_books"))
}
```

And rename the `pipelineTabIndex` computed property + the gating predicate to match (rename `hasPipelineAccess` → `hasBooksAccess` or add a new computed; either way fix consumers like `isPipelineTab` (line 192–194)). Document the rename in the commit.

- [ ] **Step 4: Build & commit**

```bash
xcodebuild -scheme OPS -destination 'generic/platform=iOS' build 2>&1 | tail -5
git add OPS/Views/MainTabView.swift
git commit -m "BOOKS tab visibility uses any-of-4-perms; auto-skip hub for single-permission users"
```

---

## Phase 1G — Verification

### Task 36: Manual test pass against acceptance criteria

This is a structured exploratory test — no code changes, just verification per the spec's acceptance criteria (§15).

- [ ] **Step 1: Build a release-config archive on device**

```bash
xcodebuild -scheme OPS -destination 'generic/platform=iOS' -configuration Release build 2>&1 | tail -5
```
Expected: BUILD SUCCEEDED.

- [ ] **Step 2: Side-load to a real iPhone (per CLAUDE.md "never use simulator")**

Use Xcode's Devices & Simulators → install. Or `xcrun devicectl device install` with a device-attached run.

- [ ] **Step 3: For each of these test users, verify expected behavior**

Use 5 test accounts (one per role):

| Role | Expected behavior |
|---|---|
| Owner | BOOKS tab visible. Hub shows full dashboard + 4 segments. Tap OVERDUE → AR detail. Tap each segment → renders correctly. Add Lead works; lead appears in NEW LEAD stage. Stage move via inline chip writes to `stage_transitions` (verify in Supabase). Soft-delete preserves row in DB. |
| Admin | Same as Owner. |
| Office | Same as Owner. |
| Operator | BOOKS tab visible. Hub renders WITHOUT dashboard (no `finances.view` and no `pipeline.view`); 2-segment control shows only Estimates + Expenses. |
| Crew | BOOKS tab visible. Hub does NOT appear — tap routes directly to `MyExpensesView` (only `expenses.view (own)` is granted). |

- [ ] **Step 4: Verify each acceptance criterion in spec §15**

Walk the checklist from spec §15 box-by-box. Capture screenshots of each state into `docs/superpowers/specs/screenshots/2026-05-07-books/` for the bible update.

- [ ] **Step 5: Verify Supabase side effects**

Run from Supabase MCP `execute_sql`:

```sql
SELECT id, opportunity_id, from_stage, to_stage, transitioned_at, duration_in_stage
FROM stage_transitions
ORDER BY transitioned_at DESC
LIMIT 5;
```
Expected: rows from your test stage moves with non-null `duration_in_stage`.

```sql
SELECT id, deleted_at FROM opportunities WHERE deleted_at IS NOT NULL LIMIT 5;
```
Expected: rows from your test soft-deletes (the row exists, `deleted_at` populated).

- [ ] **Step 6: Update the bible with verified iOS-side parity**

Edit `ops-software-bible/09_FINANCIAL_SYSTEM.md` per spec §12:

- §9.85 — note iOS now models the full opportunity schema additively.
- §9.172 — note iOS writes `stage_transitions` rows on every move via the `move_opportunity_stage` RPC.
- §9.189 — add iOS `OpportunityRepository.moveToStage()` to the equivalence table.
- New subsection — "iOS BOOKS Tab" describing hub structure + segment routing.

Commit the bible updates separately:

```bash
git add ops-software-bible/09_FINANCIAL_SYSTEM.md
git commit -m "Bible: document iOS BOOKS tab + Opportunity model parity"
```

- [ ] **Step 7: Final commit — close the spec drift register**

In the spec file `docs/superpowers/specs/2026-05-07-books-tab-design.md`, mark drift items #11–17 as RESOLVED with a footnote linking to the implementing commit hashes.

```bash
git add docs/superpowers/specs/2026-05-07-books-tab-design.md
git commit -m "Mark BOOKS spec drift register items 11-17 as resolved"
```

---

## Self-Review Notes

After writing all tasks above, run a fresh-eyes pass against the spec:

- ✅ Spec §1 (summary) → Tasks 24–27 (BOOKS shell + MainTabView wiring)
- ✅ Spec §3 (personas) → Task 35 (auto-skip routing)
- ✅ Spec §4.3 (permission matrix) → Task 35
- ✅ Spec §5 (dashboard) → Tasks 28–32
- ✅ Spec §6.1 (stage strip) → Task 14
- ✅ Spec §6.2 (lead card) → Task 13
- ✅ Spec §6.3 (stage transitions atomic RPC) → Task 2 + Task 9 + Task 23
- ✅ Spec §6.4 (Won/Lost terminal) → Task 14 (visual divider) + Task 21 (no chips on terminal in LeadDetailView) + Task 13
- ✅ Spec §6.5 (stale treatment) → Task 13 (visual) + Task 11 (sort logic)
- ✅ Spec §6.6 (Add Lead sheet) → Task 16
- ✅ Spec §6.7 (Lead detail) → Tasks 18, 19, 20, 21, 22
- ✅ Spec §6.8 (states) → Task 23 (PipelineSectionView)
- ✅ Spec §7 (other segments reuse) → Task 25
- ✅ Spec §8 (FAB) → Task 34
- ✅ Spec §9 (AR aging drill-down) → Tasks 31, 33
- ✅ Spec §10.1–10.6 (schema/data layer) → Tasks 3, 4, 5, 6, 7, 8, 9
- ✅ Spec §11 drift register → Tasks 5, 6, 7 (FollowUp bug fixes), 8 (consumer updates), 9 (soft-delete + RPC), 33 (orphan deleted)
- ✅ Spec §12 (bible updates) → Task 36 step 6
- ✅ Spec §13 (animation) → all UI tasks use only `OPSStyle.Animation.standard` and `.fast`; no `.spring` outside out-of-scope drag-reorder
- ✅ Spec §14 (accessibility) → Task 13 (touch targets ≥ 44/88pt), no color-only signals
- ✅ Spec §15 (acceptance criteria) → Task 36 step 4
- ✅ Spec §16 (out of scope Phase 2) → not built (intentionally deferred)
- ✅ Spec §17 (open questions) → Task 2 resolves #1, Task 7 resolves #8, Task 28 resolves #7

**Type consistency check:**

- `Opportunity.title` is `String?` in the model and decoded as `String?` in the DTO — consistent.
- `FollowUp.descriptionText` is the iOS field; `description` is the DB column; DTO maps via CodingKeys — consistent.
- `Activity.bodyText` (iOS) ↔ `body_text` (DB) — consistent.
- `Activity.subject` is optional on iOS and DTO (DB trigger backfills) — consistent.
- `CreateFollowUpDTO.title` is required (non-optional `String`) per bug fix — consistent across the DTO and `AddFollowUpSheet` validation.
- `move_opportunity_stage` RPC params: `p_opportunity_id`, `p_to_stage`, `p_user_id` — match the Postgres function signature in Task 2.

**No placeholders found** — every task has either complete code or a clear "follow this template" note where verbosity is reduced.

---

## Execution Handoff

Plan complete and saved to `docs/superpowers/plans/2026-05-07-books-tab-implementation.md`.

**Two execution options:**

**1. Subagent-Driven (recommended)** — I dispatch a fresh subagent per task, review between tasks, fast iteration. Best for this plan because each task is bounded and self-contained, and there are 36 of them (subagent freshness avoids context degradation).

**2. Inline Execution** — Execute tasks in this session using executing-plans, batch execution with checkpoints for review.

Which approach?




