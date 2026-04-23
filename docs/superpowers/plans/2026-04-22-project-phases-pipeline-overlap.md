# Project Phases vs. Pipeline Stages — Overlap Brainstorm

**Bug:** `6c4e5b2b` — "Need to remove RFQ and Estimated phases from projects (pipeline takes over these phases?) or brainstorm this a bit"
**Status:** `triaged` — do **not** remove code. This document captures the overlap and tradeoffs for human decision.
**Date:** 2026-04-22

---

## TL;DR

Projects have two "pre-work" statuses (`RFQ`, `Estimated`) that overlap
conceptually with pipeline stages (`quoting`, `quoted`, `follow_up`,
`negotiation`). The overlap creates two places where the user's "state
of work" lives before a deal is won, which is confusing — but the two
systems are not redundant. Pipeline tracks the **sales conversation**;
project RFQ/Estimated track the **delivery-side scaffolding** (a place
to attach estimates, notes, draft task lists). Removing either side
without redesigning the other would lose data or force users to work
outside the tool.

This doc gives the decision inputs. Pick an option; do not auto-execute.

---

## 1. Where RFQ and Estimated live in iOS code

All paths relative to `OPS/OPS/`.

### 1.1 Status enum (source of truth)
- `DataModels/Status.swift:12` — `case rfq = "rfq"`
- `DataModels/Status.swift:13` — `case estimated = "estimated"`
- `DataModels/Status.swift:77-78` — `rfq → estimated → accepted` (nextStatus)
- `DataModels/Status.swift:89-91` — `estimated → rfq` (previousStatus)
- `DataModels/Status.swift:109-110` — sort order `rfq=0, estimated=1`
- `DataModels/Status.swift:26-28` — legacy title-case decoding

### 1.2 Default project status
- `Views/JobBoard/ProjectFormSheet.swift:74` — `@State selectedStatus: Status = .rfq`
- `Views/JobBoard/ProjectFormSheet.swift:82` — `@AppStorage("defaultProjectStatus") … = Status.rfq.rawValue`
- `Views/JobBoard/ProjectFormSheet.swift:406` — `selectedStatus = .estimated` (auto-bump when estimate added)

### 1.3 Status auto-transitions
- `Utilities/DataController.swift:3503-3504` — if project is rfq/estimated and task goes active → project becomes inProgress
- `Utilities/DataController.swift:3533-3534` — same rule in the schedule path

### 1.4 Staleness / reminders
- `Utilities/StaleEstimateDetector.swift` — whole file exists to detect projects stuck in `.estimated`
- `AppState.swift:347` — `overdueEstimatedProjects` helper

### 1.5 Fallback on missing status from server
- `Network/Supabase/DTOs/CoreEntityConverters.swift:206`
- `Network/Sync/InboundProcessor.swift:632`
- `Utilities/DataController.swift:5103`
- `Utilities/DataActor.swift:679`

### 1.6 UI rendering
- `Styles/OPSStyle.swift:233-236` — colors for rfq / estimated status chips
- `Styles/Components/StatusBadge.swift:126-127` — StatusBadge supports both
- `Map/Annotations/ProjectAnnotationRenderer.swift:61-62` — pin colors
- `Views/JobBoard/JobBoardKanbanView.swift:20` — kanban columns include both
- `Views/JobBoard/UniversalJobBoardCard.swift:2068` — client card badges include both
- `Views/JobBoard/ProjectListFilterSheet.swift:143` — filter chip options
- `Views/JobBoard/UniversalSearchBar.swift:13-24` — search scope supports both
- `Views/JobBoard/JobBoardProjectListView.swift:732-733` — filter-bar chips (currently dead code — not displayed)
- `Views/Calendar Tab/Components/ProjectSearchFilterView.swift:37` — schedule search
- `Views/Calendar Tab/Components/ProjectSearchSheet.swift:164,451` — schedule search sort

### 1.7 Permission / visibility
- `Views/JobBoard/UniversalSearchSheet.swift:63` — **crew role filters OUT rfq/estimated projects** from universal search
- `Services/Spotlight/SpotlightIndexManager.swift:302` — **Spotlight skips rfq/estimated for users without `pipeline.view`**

Implication: crew / operator roles already don't see these statuses
anywhere except on cards they're explicitly assigned to.

---

## 2. Where pipeline stages live

From `DataModels/Enums/PipelineStage.swift` (mobile) and
`ops-software-bible/10_JOB_LIFECYCLE_AND_DATA_RELATIONSHIPS.md`
(canonical):

Stages: `new_lead → qualifying → quoting → quoted → follow_up →
negotiation → won → lost`.

Key lifecycle bible quote (10_JOB_LIFECYCLE, lines 103-112):
> Client auto-created from opportunity contact info
> Project auto-created `(title, clientId, status=RFQ, opportunityId)`
> estimate.projectId = project.id, opportunity.projectId = project.id

And lines 117-118:
> Opportunity (quoted) → Project (Estimated)

So the bible explicitly ties project `RFQ` → pipeline `quoting` and
project `Estimated` → pipeline `quoted`. Today these transitions happen
server-side; the iOS client just reads the resulting project status.

---

## 3. The overlap question

**Who owns the "pre-won" state of a deal?**

- If **pipeline only**: a Project row exists but `status` is a cosmetic
  derivation of the opportunity's stage. Users can't "push a project
  forward" from the Job Board — they have to go to the pipeline Kanban.
  Problem: **crew-tier users don't have `pipeline.view`.** They'd have
  nowhere to see early-stage work for a job they're expected to be
  prepared for.

- If **projects only** (today): two systems drift. Changing pipeline
  stage on the web doesn't always roundtrip to iOS project status
  immediately (inbound sync delay), and vice versa. Users get asked the
  same question in two places: "did we send the estimate?"

- If **both, but cleanly partitioned**: pipeline owns the conversation
  (who, when, how much, stage-advance reasons). Projects own the scope
  + delivery (title, tasks, crew). The overlap at RFQ/Estimated is
  cosmetic only — projects enter the board at `Accepted` once the
  pipeline goes `won`.

---

## 4. Options

### Option A — Remove RFQ and Estimated from `Status`
- Projects start at `accepted` (once the pipeline deal is `won`)
- Pipeline is the only system of record for pre-won work
- **Pros:** eliminates duplicate tracking; simplifies the Job Board to
  "work being done or already done"
- **Cons:**
  - Crew without `pipeline.view` lose visibility into upcoming work
    until a deal is won (breaks the "prep for what's coming" use case)
  - Legacy data: projects currently in `rfq` or `estimated` would need
    a migration — either bump them to `accepted` (may lie about state)
    or soft-hide them (may orphan them)
  - Every auto-advance rule that triggers off `rfq`/`estimated`
    (DataController 3503/3533) needs new triggers or removal
  - Mobile-first offline flow: a user with no pipeline access can't
    create a project in RFQ → requires a server round-trip through
    pipeline, which is bad on bad connections
  - Breaking change to existing Supabase data — non-reversible without
    a history table

### Option B — Keep Status as-is, but surface pipeline stage inline on project cards
- Project keeps `rfq` / `estimated` as delivery-side status
- Job Board cards show a small pipeline badge when the project's
  `opportunityId` resolves to an active opportunity
- **Pros:**
  - No data migration
  - Crew still sees everything they see today
  - Users can tell at a glance whether a project's estimate is still
    being negotiated vs. just sitting waiting to be scheduled
- **Cons:**
  - Adds one more visual element to already-busy cards
  - Requires a new local read path (opportunity lookup by id) — we have
    `opportunityId` on `Project` but no local `Opportunity` model yet
    on iOS (this would be new infrastructure)

### Option C — Deprecate RFQ / Estimated for office-tier, keep for crew-tier
- Office/admin users with `pipeline.view` see projects start at
  `Accepted` on their Job Board (RFQ/Estimated are hidden from them
  because the pipeline is their source of truth)
- Field crew still sees `rfq`/`estimated` — they use the project card
  as their only interface
- **Pros:**
  - Matches the existing permission gating (Universal Search and
    Spotlight already filter these statuses for crew — just extend
    the rule to the Job Board list too)
  - No data model change, just filter logic
- **Cons:**
  - Two different views of the same data for different user tiers —
    extra test surface
  - An office user who wants to see the full project lifecycle has to
    remember to look in two places (pipeline for early, Job Board for
    late) — possibly a net reduction in clarity

---

## 5. Recommended next step

**Before removing anything**, validate which user tier is reporting
this bug:

- If the reporter is an **admin/office user**, the complaint is
  "duplicate tracking makes my Job Board messy" — Option C is the
  lightest win.
- If the reporter is a **field crew member who does NOT have pipeline
  access**, the complaint is different — they probably mean "I see
  projects in RFQ that aren't really mine to push forward", which is a
  wording/UX fix, not a structural one.
- If this came from conversations with multiple roles, **Option B** is
  the safest — it adds information without removing any.

Grep / data migration work should wait until the decision is made.
Until then, keep both systems running side-by-side as they are today.

---

## 6. Code ref appendix

(Copy-paste grep anchors — full file list in §1 above.)

- Every `case .rfq`, `case .estimated` in `DataModels/Status.swift`
- Every `.rfq` or `.estimated` literal across `OPS/Views/**` and
  `OPS/Map/**`
- The fallback `Status(rawValue: dto.status) ?? .rfq` pattern in all
  four sync locations (see §1.5) — **these would become `?? .accepted`
  under Option A** (dangerous if server data has legitimate rfq rows)
- `Utilities/StaleEstimateDetector.swift` — would be deleted under
  Option A, untouched under B/C

---

## 7. What this doc does NOT do

- Does not remove any code
- Does not rename any enum case
- Does not change any Supabase column
- Does not alter any sync path

It's a decision-support document. The bug status stays `triaged`.
