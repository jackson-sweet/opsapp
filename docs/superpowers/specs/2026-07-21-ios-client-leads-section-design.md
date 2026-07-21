# Client Leads Section — iOS Design

**Date:** 2026-07-21
**Surface:** iOS (`ops-ios`)
**Status:** Approved (product direction) — ready for implementation plan
**Owner:** Agent (Jackson approved the product design)

---

## 1. Goal

Surface a client's leads (pipeline opportunities) directly on the client's profile
screen, so a business owner looking at a client can see the potential work in flight
with them — and act on it — without leaving for the Leads tab.

This is a **surfacing** feature. Leads already exist (`Opportunity`), already carry a
`client_id`, and are already created linked to a client. There is **no new data model,
no migration, no schema change, and no customer-facing change until a new build ships**.

---

## 2. What already exists (grounding facts)

Verified by reading the live sources — not assumed.

- **Client detail screen** = `ContactDetailView` (`OPS/Views/Components/User/ContactDetailView.swift`),
  rendered when initialized with a `Client`. Its body is a `ScrollView` of a
  `VStack(spacing: OPSStyle.Layout.spacing3)` stacking, top→bottom:
  preview card → **Contact Information** → **Sub Contacts** → **Projects** → **Delete**.
  Each section is a `SectionCard` (`OPS/Styles/Components/SectionCard.swift`). The view
  already holds `@EnvironmentObject dataController`, `@EnvironmentObject permissionStore`,
  `@Environment(\.modelContext)`, and computed `isClient` / `canEditClient`.
- **Lead** = `Opportunity` (`OPS/DataModels/Supabase/Opportunity.swift`). Links to a
  client purely by `clientId: String?` — **no SwiftData relationship**. Key fields:
  `stage: PipelineStage`, `title` (job description), `displayContactName`,
  `estimatedValue`, `actualValue`, `assignedTo`, `nextFollowUpAt`, `lastActivityAt`,
  `actualCloseDate`, `archivedAt`/`isArchived`, `deletedAt`/`isDeleted`, `shortDisplayId`.
- **Stages** = `PipelineStage` (`OPS/DataModels/Enums/PipelineStage.swift`):
  open — `newLead, qualifying, quoting, quoted, followUp, negotiation`;
  terminal (`isTerminal == true`) — `won, lost, discarded`. Has `displayName`,
  `shortLabel`, `openStages`. **No color property on the enum** — the Leads UI maps
  stage→color elsewhere; reuse that existing mapping, never invent one.
- **Leads are NOT in the SwiftData sync engine.** Every lead surface fetches from
  Supabase via `OpportunityRepository(companyId:)` and holds results in memory
  (`PipelineViewModel`). There is no `@Query` for leads and no `client.leads`.
- **Client-scoped query already exists** (capped at 1):
  `OpportunityRepository.fetchFirstActiveLinked(toClientId:)` filters
  `company_id == companyId AND client_id == clientId AND deleted_at IS NULL`.
- **Lead detail** = `LeadDetailView(opportunity:onMarkLost:onEdit:onMarkWon:onConvertLead:)`
  (`OPS/Views/Leads/LeadDetailView.swift`). It builds its own `LeadDetailViewModel` +
  chase VM internally; it needs `dataController` + `permissionStore` in the environment;
  its action closures route to a host that presents sheets.
- **Lead action sheets** are self-contained (each takes an `Opportunity`):
  `EditLeadSheet(opportunity:)`, `LostReasonSheet(opportunity:)` (`.medium`),
  `ConvertToProjectSheet(opportunity:)`, `UnifiedLogActivitySheet(...)` (`.large`).
  The routing enum `LeadsSheet` is a top-level type (declared in `LeadsTabView.swift`),
  reusable app-wide.
- **Create-lead** = `AddLeadSheet` → `LeadForm` (`OPS/Views/Leads/Sheets/LeadFormView.swift`)
  → `OpportunityRepository.create(CreateOpportunityDTO)`. `LeadForm` fields:
  `contactName, phone, email, address, title, estimatedValue, source, stage, priority,
  notes, latitude, longitude`. On save, `AddLeadSheet.performCreate()` resolves a
  `clientId` via `resolveClientId(companyId:name:)` (fuzzy phone→email→name match, else
  creates a client) and passes it to the create DTO — so a new lead lands with
  `client_id` set (bug 1d5ab9aa).
- **Permissions** = `LeadAccessPolicy` via `permissionStore.leadAccessPolicy`:
  `canViewAny`, `canCreate`, `can(.view, assignedTo:)`, `scope(for: .view)` returning
  `.all` | `.assigned`. Row-level view scope matters — an `.assigned`-scope user may see
  only leads assigned to them.

---

## 3. Product design

A new **Leads** `SectionCard` on the client profile, placed **directly above the
Projects section**.

### 3.1 Placement rationale
A lead is *potential* work; a project is *won* work. Top→bottom the section order then
reads the way a job actually flows (prospect → job): Contact → Sub Contacts → **Leads** →
Projects. Leads are also the time-sensitive item (they go stale and need chasing), so
they earn the higher, more-scanned slot. Projects (already won) sit below.

### 3.2 Anatomy

**Header** — `SectionCard(icon: <leads/pipeline glyph>, title: "Leads (\(openCount))",
action: "Add")`.
- Count reflects **open** leads only — "Leads (2)" means 2 live. History is tallied
  separately (below), not in the header number.
- The "Add" action is shown only when `leadAccessPolicy.canCreate`. Mirrors the Projects
  header's "+ Add".

**Open leads list** — the client's non-terminal, non-archived, non-deleted leads the
user is allowed to view. Light rows (mirroring the Projects rows, not the tall
`LeadTriageCard`):
- stage-colored dot · **job** (`title`, falling back to `displayContactName` when the
  lead has no title) · trailing value (`estimatedValue`, formatted via `BooksFormat`) +
  stage badge (`stage.displayName`/`shortLabel`, stage color) · chevron.
- **Rows lead with the job, not the person.** On a client's own page the "who" is
  already the page's subject; what the owner scans is *what work is on the table* and
  *where it stands*. (Contrast: the Leads tab leads with contact name because it scans
  across many clients.)
- Sorted by most-recent activity: `lastActivityAt ?? updatedAt ?? createdAt`, descending.
- Capped at 5 with a `+ N MORE` / `SHOW LESS` expander — identical pattern to Projects.
- Tap → opens the lead (see §4.3), with every action intact.

**History peek** — one quiet disclosure row at the bottom of the section, present only
when the client has ≥1 terminal (won/lost/discarded), non-archived, non-deleted lead:
- Collapsed default: a muted mono line of outcome tallies, e.g. `3 WON · 1 LOST`
  (only nonzero outcomes shown; discarded included if present).
- Tap to expand → the closed leads render as lighter, dimmed rows (outcome-colored dot ·
  job · outcome badge; won rows show `actualValue ?? estimatedValue`). Sorted by
  `actualCloseDate ?? updatedAt ?? createdAt`, descending.
- Keeps the section about what's *live* while relationship history stays one tap away
  ("won 3, lost 1 — worth chasing again?"). Won deals still live in full under Projects;
  here they are tally + reference only.

**Empty state** — no open leads and no history:
- `canCreate` → tappable block mirroring the Projects empty state: leads glyph +
  "No leads yet" + "Create one?" → opens create-lead (§4.4).
- otherwise → passive glyph + "No leads".

### 3.3 Visibility & permission behavior
- The **entire section is hidden** unless `isClient && leadAccessPolicy.canViewAny` —
  crew without pipeline visibility never see it, consistent with every other lead
  surface.
- **Row-level filtering:** open and history lists include only leads for which
  `leadAccessPolicy.can(.view, assignedTo: lead.assignedTo)` is true. An `.assigned`-scope
  user sees only their own leads for this client (and may legitimately land on the empty
  state).
- The "Add" affordance is gated on `canCreate`.

### 3.4 States summary
| State | Header | Body |
|---|---|---|
| Open + history | `Leads (n)` + Add? | open rows (≤5 + expander) · history peek |
| Open only | `Leads (n)` + Add? | open rows |
| History only | `Leads (0)` + Add? | empty-ish open + history peek |
| Nothing | `Leads (0)` + Add? | empty state (create or passive) |
| No view permission | — | section absent |
| Loading | `Leads` | subtle loading affordance, no layout jump |
| Load error | `Leads` | quiet retry affordance; never a blocking alert |

---

## 4. Architecture

Isolated, low-blast-radius. New self-contained component + one repository method + three
small additive edits.

### 4.1 New files
- **`OPS/Views/Components/Client/ClientLeadsSection.swift`** — the section View. Owns a
  `@StateObject ClientLeadsViewModel`, renders the `SectionCard` (open list, history
  disclosure, empty/loading/error states), and hosts the lead-detail + action sheets
  (§4.3) and the create flow (§4.4). Keeps `ContactDetailView` lean — the file is already
  ~1710 lines; do not inline this (oversized bodies have caused latent compile breaks in
  this codebase).
- **`OPS/ViewModels/ClientLeadsViewModel.swift`** — `@MainActor final class
  ClientLeadsViewModel: ObservableObject`. Inputs: `companyId`, `clientId`, a
  `LeadAccessPolicy`. `load()` → `OpportunityRepository.fetchAllLinked(toClientId:)` →
  `.toModel()` → row-level view filter → split into `openLeads` (non-terminal,
  non-archived) and `closedLeads` (terminal, non-archived) with the sorts from §3.2 →
  publish + outcome tallies. Publishes `loadState` (idle/loading/loaded/error). Testable
  in isolation.
- Row rendering: a small `private struct ClientLeadRow` inside `ClientLeadsSection.swift`
  (keeps the section body small and snapshot-testable). Reuses the existing
  stage→color mapping and `BooksFormat` value formatting.

### 4.2 Edited files
- **`OPS/Network/Supabase/Repositories/OpportunityRepository.swift`** — add
  `fetchAllLinked(toClientId:) async throws -> [OpportunityDTO]`: identical to
  `fetchFirstActiveLinked` minus `.limit(1)`, returning all non-deleted leads for the
  client across all stages (`order created_at desc`). Terminal-stage rows are returned
  (they are not soft-deleted); the VM splits open vs. closed in memory.
- **`ContactDetailView.swift`** — insert `ClientLeadsSection(client: client)` into the
  body `VStack`, gated on `isClient`, immediately **above** `projectsSection`, with the
  same `.padding(.horizontal)` / `.padding(.top, spacing3)` and the sibling fade-in
  (`showFullContact` opacity/offset) so it matches the surrounding sections. One-line
  insertion; the component is otherwise self-contained.
- **`AddLeadSheet.swift` + `LeadForm`** — additive optional client seed (§4.4).

### 4.3 Tap-through (lead detail + actions)
`ClientLeadsSection` hosts the lead experience itself so actions work fully, **without
touching the shared `LeadsTabView`** (avoids collisions with active Leads work):
- `@State private var detailLead: Opportunity?` → `.navigationDestination(item:)` (the
  client sheet's body is a `NavigationStack`) presenting
  `LeadDetailView(opportunity:onMarkLost:onEdit:onMarkWon:onConvertLead:)`, inheriting
  `dataController` + `permissionStore` from the environment.
- `@State private var activeSheet: LeadsSheet?` → `.sheet(item:)` with a local
  `sheetView(for:)` reproducing only the four detail-action cases
  (`.edit → EditLeadSheet`, `.lost → LostReasonSheet[.medium]`,
  `.convert → ConvertToProjectSheet`, `.log → UnifiedLogActivitySheet[.large]`). These
  reuse the exact same sheet views — the only duplication is the ~15-line routing switch,
  which is isolated and low-risk. `LeadDetailView`'s closures set `activeSheet`
  accordingly, mirroring `LeadsTabView`.
- **Reload triggers** (leads aren't SwiftData-synced, so refresh is explicit): on section
  appear (`.task`), on create/edit/convert/lost completion (observe the same lead-mutation
  notifications `LeadsTabView` already reloads on — e.g. `LeadCreatedSuccess` — enumerate
  exact names during implementation), and on `activeSheet`/`detailLead` returning to nil.
  After a convert/lost, a lead may leave the open set; the VM reload re-splits it into
  history and, if the open detail's lead is gone, dismisses the detail.

### 4.4 Create-from-client
"Add" (and the empty-state "Create one?") opens `AddLeadSheet` seeded for **this** client:
- Additive optional input on `AddLeadSheet`, e.g. `seedClient: Client?` (plus the existing
  `onSaved`). When present, prefill `LeadForm` from the client (`contactName ← name`,
  `email`, `phone`, `address`, and coordinates when available), and in `performCreate()`
  **bind the known `client.id` directly**, bypassing `resolveClientId(...)`. This
  guarantees the new lead links to exactly this client — no fuzzy re-match, no duplicate
  client. `onSaved` → VM reload so the new lead appears immediately.
- Add a `LeadForm.init(fromClient:)` (parallel to the existing `init(from opportunity:)`)
  for the prefill.

### 4.5 Data flow
```
ContactDetailView(client)
  └─ ClientLeadsSection(client)                     [isClient && canViewAny]
       ├─ ClientLeadsViewModel(companyId, clientId, policy)
       │     └─ OpportunityRepository.fetchAllLinked(toClientId:) → [DTO] → toModel()
       │           → filter can(.view, assignedTo:) → split open / closed → publish
       ├─ open rows  → tap → detailLead → LeadDetailView → activeSheet → action sheets
       ├─ history peek (disclosure) → closed rows → tap → same detail host
       └─ Add / empty-create → AddLeadSheet(seedClient: client) → onSaved → VM.reload()
```
`companyId` = `client.companyId ?? dataController.currentUser?.companyId`.

---

## 5. Copy (provisional — finalize via `ops-copywriter`)
- Section title: `Leads (n)` (n = open count).
- Header action: `Add`.
- History peek line: outcome tallies in mono/uppercase, e.g. `3 WON · 1 LOST`
  (empty state `—`, never "N/A"; numbers always formatted).
- Empty state: `No leads yet` / `Create one?` (create-enabled) or `No leads` (passive).
- OPS voice: terse, tactical, sentence case for content / UPPERCASE for authority, no
  emoji, no exclamation points.

---

## 6. Motion & haptics
- Reuse the existing OPS motion tokens already used by the sibling sections
  (`OPSStyle.Animation.standard`, the one easing curve). Section fade-in matches the
  `showFullContact` opacity/offset used by Contact/Projects. Honor
  `prefers-reduced-motion`.
- Haptics: light impact on history-peek expand and on the show-more toggle; the detail /
  action sheets carry their own committal haptics. No haptic spam.
- No new/bespoke animation is introduced; if execution designs any, load
  `animation-studio:animation-architect` first.

---

## 7. Testing & proof
- **Snapshot tests** (via the `OPSTests` `UIHostingController` + `UIWindow` +
  `drawHierarchy` harness — `ImageRenderer` mis-renders asset colors) for
  `ClientLeadsSection` / `ClientLeadRow` states: open+history, open-only, history-only,
  empty (create), empty (passive), no-permission (absent). PNGs → `docs/artifacts/`.
- **Unit tests** for `ClientLeadsViewModel`: open/closed split, terminal & archived &
  deleted filtering, `.assigned`-scope row filtering, outcome tallies, sort order — via a
  seam that lets the fetch be injected (fixed inputs), mirroring the vinyl-orders
  `fixedInputs` snapshot seam.
- **Build:** `xcodebuild -scheme OPS -destination 'generic/platform=iOS'` clean;
  `build-for-testing` on the simulator destination clean.
- **Manual sim run:** open a client with both open and closed leads → section renders,
  rows lead with the job, history peek expands, tap opens the lead, an action (e.g. change
  stage / mark lost) reflects back after reload, "Add" creates a lead pre-linked to the
  client and it appears. Screenshots → `docs/artifacts/`.

---

## 8. Bible update
Update the leads/pipeline section of `ops-software-bible/` (the pipeline/CRM feature doc)
to record the client-scoped leads surface on `ContactDetailView` and the new
`fetchAllLinked(toClientId:)` read path, in the same session the code lands.

---

## 9. Non-goals
- No new lead lifecycle actions — the section reuses the existing detail/create/convert/
  lost/edit flows verbatim.
- No refactor of `LeadsTabView` or extraction of its sheet host (kept local to avoid
  colliding with active Leads work; a later DRY pass is optional, not part of this).
- No SwiftData relationship between `Client` and `Opportunity`, no migration, no schema
  change.
- No archived-lead surfacing (archive = "hide"); excluded from both open and history.
- No inline row actions (swipe/menu) on the client page — verbs live inside the lead.

---

## 10. Risks & coordination
- **`project.pbxproj` collision.** A sibling session currently has uncommitted changes to
  `OPS.xcodeproj/project.pbxproj` (Calendar/schedule long-press work). Adding new Swift
  files edits `project.pbxproj` too. Before adding files: re-check `git status`; add the
  new file references surgically; never stage or revert the sibling's pbxproj/Calendar
  changes. If the pbxproj is mid-flux, coordinate or land the file-add as its own tight,
  reviewable hunk. Commit only this feature's files, by explicit path.
- **`.assigned` scope empty state** is expected, not a bug — an assigned-scope user with
  no leads for this client correctly sees the empty/absent state.
- **Reload completeness** — enumerate the exact lead-mutation notification names during
  implementation so convert/lost/edit reliably refresh the section.
