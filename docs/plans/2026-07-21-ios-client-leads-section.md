# Client Leads Section (iOS) — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use `custom-skills:executing-plans` to implement this plan task-by-task (OPS-tuned; enforces design-system compliance during execution).

**Goal:** Surface a client's pipeline leads (open + a collapsed won/lost history) directly on the client profile screen, with tap-through to the full lead and one-tap create pre-linked to the client.

**Architecture:** A new self-contained `ClientLeadsSection` (its own file) is spliced into `ContactDetailView` above the Projects section. It owns a small `@StateObject ClientLeadsViewModel` that loads leads from Supabase via a new `OpportunityRepository.fetchAllLinked(toClientId:)`, applies row-level view-permission filtering, and splits them into open vs. terminal (history). Leads are **not** SwiftData-synced, so refresh is explicit (task on appear + lead-mutation notifications + sheet dismissal). Tap-through reuses `LeadDetailView` and the existing action sheets; create reuses `AddLeadSheet` seeded with the client.

**Tech Stack:** Swift, SwiftUI, SwiftData (models only), Supabase (`OpportunityRepository`), XCTest (unit + snapshot). Target iOS 17.6 — no iOS-18-only APIs without `#available` + fallback.

**Design System:** No `.interface-design/system.md`. iOS tokens are `OPSStyle` (`ops-ios/OPS/Styles/OPSStyle.swift`) + `ops-design-system/project/DESIGN.md` + `ops-design-system/project/mobile/MOBILE.md`. **Zero hardcoded color/spacing/radius/font values** — every value traces to an `OPSStyle` token or the canonical `PipelineStage.color` mapping.

**Required Skills (executing agent must load):**
- `ops-design` — every styling decision traces to a token; read `DESIGN.md` + `mobile/MOBILE.md`.
- `custom-skills:mobile-ux-design` — outdoor contrast, ≥44pt touch targets, one-glance scannability.
- `ops-copywriter:ops-copywriter` — the section's user-facing strings (product register: terse, confident, no exclamation points, UPPERCASE for authority / sentence case for content).
- `animation-studio:ios-animations` — **only if** any bespoke motion is introduced (none is planned; the section reuses `OPSStyle.Animation.standard`).
- `custom-skills:audit-design-system` — final gate before "done" (Task 9).

**Spec:** `docs/superpowers/specs/2026-07-21-ios-client-leads-section-design.md`

---

## Shared reference — tokens & copy (use verbatim; do not improvise)

**Design tokens** (all from `OPSStyle` unless noted):
- Section wrapper: `SectionCard` (`OPS/Styles/Components/SectionCard.swift`).
- Section header icon: `OPSStyle.Icons.opportunity` (`"arrow.up.right.circle.fill"`).
- Header add icon/label: `OPSStyle.Icons.plus` / `"Add"` (matches Projects).
- Stage dot + badge color: `lead.stage.color` (canonical mapping in `OPS/DataModels/Enums/PipelineStage+Color.swift` — **the** tokenized source; never re-derive a stage color).
- Text: `OPSStyle.Colors.primaryText` (job), `.secondaryText` (value/subtext), `.tertiaryText` (chevron, passive empty).
- Type: `OPSStyle.Typography.body` (job), `.smallCaption` (value + stage badge + history tallies), `.caption` (empty-state subtext), `.captionBold` (show-more).
- Spacing: `OPSStyle.Layout.spacing1 / spacing2 / spacing2_5 / spacing3 / spacing5`.
- Radius: `OPSStyle.Layout.cardCornerRadius`. Border: `OPSStyle.Layout.Border.standard`. Icon sizes: `OPSStyle.Layout.IconSize.xs / xl`.
- Empty-state block surface: `.nestedCard()` (matches Sub Contacts empty state).
- Motion: `OPSStyle.Animation.standard` (show-more / history toggle). Honor reduced-motion.
- Money: `BooksFormat.compact(_:)` (compact currency, e.g. `$42K`). Empty value → omit the line (never "N/A").
- Touch target: every tappable row `.frame(minHeight: 44)` (MOBILE.md).

**Copy** (product register — finalized; `ops-copywriter` may refine wording, not intent):
- Section title: `Leads (<openCount>)` → renders `LEADS (2)`.
- Header action: `Add`.
- History peek line: `// ` + nonzero tallies joined by ` · `, e.g. `// 3 WON · 1 LOST` (numbers mono/tabular via `.smallCaption`).
- Empty (create-enabled): title `No leads yet`, subtext `Create one?`.
- Empty (passive / no create permission): `No leads`.
- Load error: `Couldn't load leads` + a `Retry` affordance.

**pbxproj note:** the project uses Xcode **file-system-synchronized groups** — new `.swift` files under `OPS/…` and `OPSTests/…` are auto-included in their targets. **Do not edit `OPS.xcodeproj/project.pbxproj`** (a sibling session has WIP there). Just create files in the correct folders.

**Coordination:** a sibling session holds uncommitted WIP in the Calendar/schedule area and `project.pbxproj`. Never stage, revert, or touch those files. Stage only this feature's files, by explicit path. Commit onto the current branch (`main`) — this is a contained feature, not a large multi-week buildout; atomic commits per task.

**Build/test commands** (iOS rules):
- Device build check: `xcodebuild -scheme OPS -destination 'generic/platform=iOS' build`
- Test compile: `xcodebuild -scheme OPS -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' build-for-testing`
- Run tests: `xcodebuild -scheme OPS -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' test -only-testing:OPSTests/ClientLeadsViewModelTests`
- Before any `xcodebuild`: `ps aux | grep xcodebuild | grep -v grep` — if a sibling build is running on shared DerivedData, wait or use a worktree-local DerivedData.
- Preserve each file's existing line endings (many Swift files are CRLF/mixed).

---

## Task 1: Repository read path — `fetchAllLinked(toClientId:)`

**Skills:** none (network method; the repository has no unit tests by convention — verified by compile + the manual run in Task 8).

**Files:**
- Modify: `OPS/Network/Supabase/Repositories/OpportunityRepository.swift` (add after `fetchFirstActiveLinked`, ~line 67)

**Step 1: Add the method**

```swift
/// All non-deleted opportunities linked to a client, across every stage
/// (open + terminal). The client Leads section splits open vs. closed
/// in memory. Mirror of `fetchFirstActiveLinked` without the `.limit(1)`.
func fetchAllLinked(toClientId clientId: String) async throws -> [OpportunityDTO] {
    try await client
        .from("opportunities")
        .select()
        .eq("company_id", value: companyId)
        .eq("client_id", value: clientId)
        .is("deleted_at", value: nil)
        .order("created_at", ascending: false)
        .execute()
        .value
}
```

**Step 2: Verify it compiles**

Run: `xcodebuild -scheme OPS -destination 'generic/platform=iOS' build`
Expected: BUILD SUCCEEDED.

**Step 3: Commit**

```bash
git add OPS/Network/Supabase/Repositories/OpportunityRepository.swift
git commit -m "feat(leads): add client-scoped opportunity fetch for client page"
```

---

## Task 2: `ClientLeadsViewModel` (pure split/filter/sort/tally) — TDD

**Skills:** none (pure logic).

**Files:**
- Create: `OPS/ViewModels/ClientLeadsViewModel.swift`
- Test: `OPSTests/ViewModels/ClientLeadsViewModelTests.swift`

**Pre-check (do first):** open `OPS/DataModels/Supabase/Opportunity.swift` and confirm the initializer signature and the optionality of `createdAt`, `updatedAt`, `lastActivityAt`, `actualCloseDate`, plus `isDeleted`, `isArchived`, `assignedTo`, `clientId`, `stage`. Adjust the `??` coalescing in `apply(...)` and the test fixture below to match actual optionality (if a Date field is **non-optional**, drop its `?? .distantPast`).

**Step 1: Write the failing tests**

```swift
import XCTest
@testable import OPS

@MainActor
final class ClientLeadsViewModelTests: XCTestCase {

    // Grant-all policy: pipeline.view == all.
    private func policyAll() -> LeadAccessPolicy {
        LeadAccessPolicy(currentUserId: "u1",
                         permissions: ["pipeline.view": "all"],
                         explicitPermissionKeys: ["pipeline.view"])
    }
    // Assigned-scope policy: only leads assigned to u1 are viewable.
    private func policyAssigned() -> LeadAccessPolicy {
        LeadAccessPolicy(currentUserId: "u1",
                         permissions: ["pipeline.view": "assigned"],
                         explicitPermissionKeys: ["pipeline.view"])
    }

    // Adjust to Opportunity's real initializer. Sets only the fields apply() reads.
    private func lead(id: String, clientId: String, stage: PipelineStage,
                      assignedTo: String? = "u1", archived: Bool = false,
                      deleted: Bool = false, activity: Date = Date(timeIntervalSince1970: 1_000)) -> Opportunity {
        let o = Opportunity(id: id, companyId: "c1", contactName: "N", stage: stage)
        o.clientId = clientId
        o.assignedTo = assignedTo
        o.lastActivityAt = activity
        if archived { o.archivedAt = Date() }
        if deleted { o.deletedAt = Date() }
        return o
    }

    func test_splitsOpenVsTerminal_andExcludesArchivedDeletedAndOtherClients() {
        let vm = ClientLeadsViewModel()
        vm.apply([
            lead(id: "1", clientId: "CL", stage: .quoting),
            lead(id: "2", clientId: "CL", stage: .won),
            lead(id: "3", clientId: "CL", stage: .lost),
            lead(id: "4", clientId: "CL", stage: .newLead, archived: true),   // hidden
            lead(id: "5", clientId: "CL", stage: .quoted, deleted: true),      // hidden
            lead(id: "6", clientId: "OTHER", stage: .newLead),                 // wrong client
        ], clientId: "CL", policy: policyAll())

        XCTAssertEqual(vm.openLeads.map(\.id), ["1"])
        XCTAssertEqual(Set(vm.closedLeads.map(\.id)), ["2", "3"])
        XCTAssertEqual(vm.tally.won, 1)
        XCTAssertEqual(vm.tally.lost, 1)
        XCTAssertEqual(vm.tally.discarded, 0)
        XCTAssertTrue(vm.tally.hasAny)
    }

    func test_assignedScope_hidesLeadsNotAssignedToUser() {
        let vm = ClientLeadsViewModel()
        vm.apply([
            lead(id: "mine", clientId: "CL", stage: .quoting, assignedTo: "u1"),
            lead(id: "theirs", clientId: "CL", stage: .quoting, assignedTo: "u2"),
        ], clientId: "CL", policy: policyAssigned())

        XCTAssertEqual(vm.openLeads.map(\.id), ["mine"])
    }

    func test_openSortedByMostRecentActivity() {
        let vm = ClientLeadsViewModel()
        vm.apply([
            lead(id: "old", clientId: "CL", stage: .quoting, activity: Date(timeIntervalSince1970: 10)),
            lead(id: "new", clientId: "CL", stage: .quoting, activity: Date(timeIntervalSince1970: 99)),
        ], clientId: "CL", policy: policyAll())

        XCTAssertEqual(vm.openLeads.map(\.id), ["new", "old"])
    }

    func test_emptyWhenNothingViewable() {
        let vm = ClientLeadsViewModel()
        vm.apply([], clientId: "CL", policy: policyAll())
        XCTAssertTrue(vm.openLeads.isEmpty)
        XCTAssertTrue(vm.closedLeads.isEmpty)
        XCTAssertFalse(vm.tally.hasAny)
    }
}
```

**Step 2: Run tests — verify they FAIL to compile** (`ClientLeadsViewModel` undefined)

Run: `xcodebuild -scheme OPS -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' build-for-testing`
Expected: FAIL — `cannot find 'ClientLeadsViewModel'`.

**Step 3: Implement**

```swift
//
//  ClientLeadsViewModel.swift
//  OPS
//
//  Loads and shapes a client's pipeline leads for the client-profile Leads
//  section. Leads are not SwiftData-synced, so this fetches via the
//  repository and holds results in memory. `apply` is pure (testable).
//

import Foundation
import SwiftUI

@MainActor
final class ClientLeadsViewModel: ObservableObject {

    enum LoadState: Equatable { case idle, loading, loaded, error }

    struct OutcomeTally: Equatable {
        var won = 0
        var lost = 0
        var discarded = 0
        var hasAny: Bool { won + lost + discarded > 0 }
    }

    @Published private(set) var openLeads: [Opportunity] = []
    @Published private(set) var closedLeads: [Opportunity] = []
    @Published private(set) var tally = OutcomeTally()
    @Published private(set) var loadState: LoadState = .idle

    /// Test seam — inject a fixed lead set. Nil in production (uses the repository).
    var loaderOverride: ((_ companyId: String, _ clientId: String) async throws -> [Opportunity])?

    /// Pure transform: filter to viewable / non-deleted / non-archived / this
    /// client; split open vs. terminal; sort; tally outcomes.
    func apply(_ leads: [Opportunity], clientId: String, policy: LeadAccessPolicy) {
        let visible = leads.filter {
            !$0.isDeleted
            && !$0.isArchived
            && $0.clientId == clientId
            && policy.can(.view, assignedTo: $0.assignedTo)
        }

        openLeads = visible
            .filter { !$0.stage.isTerminal }
            .sorted { openSortKey($0) > openSortKey($1) }

        closedLeads = visible
            .filter { $0.stage.isTerminal }
            .sorted { closedSortKey($0) > closedSortKey($1) }

        var t = OutcomeTally()
        for lead in closedLeads {
            switch lead.stage {
            case .won: t.won += 1
            case .lost: t.lost += 1
            case .discarded: t.discarded += 1
            default: break
            }
        }
        tally = t
    }

    func load(companyId: String, clientId: String, policy: LeadAccessPolicy) async {
        loadState = .loading
        do {
            let leads: [Opportunity]
            if let loaderOverride {
                leads = try await loaderOverride(companyId, clientId)
            } else {
                let repo = OpportunityRepository(companyId: companyId)
                leads = try await repo.fetchAllLinked(toClientId: clientId).map { $0.toModel() }
            }
            apply(leads, clientId: clientId, policy: policy)
            loadState = .loaded
        } catch {
            loadState = .error
        }
    }

    // Most-recent activity first. (Adjust `??` to real optionality — see Task 2 pre-check.)
    private func openSortKey(_ o: Opportunity) -> Date {
        o.lastActivityAt ?? o.updatedAt ?? o.createdAt ?? .distantPast
    }
    // Most-recently closed first.
    private func closedSortKey(_ o: Opportunity) -> Date {
        o.actualCloseDate ?? o.updatedAt ?? o.createdAt ?? .distantPast
    }
}
```

**Step 4: Run tests — verify PASS**

Run: `xcodebuild -scheme OPS -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' test -only-testing:OPSTests/ClientLeadsViewModelTests`
Expected: all 4 tests PASS. (If the `Opportunity(...)` init in the fixture doesn't match, fix the fixture — not the assertions.)

**Step 5: Commit**

```bash
git add OPS/ViewModels/ClientLeadsViewModel.swift OPSTests/ViewModels/ClientLeadsViewModelTests.swift
git commit -m "feat(leads): client leads view model with view-scope filter, split and tally"
```

---

## Task 3: Create-from-client — `LeadForm.init(fromClient:)` + `AddLeadSheet` seed — TDD

**Skills:** none for the form init (logic); `ops-copywriter` already covered the strings.

**Files:**
- Modify: `OPS/Views/Leads/Sheets/LeadFormView.swift` (add init to `struct LeadForm`, ~after line 71)
- Modify: `OPS/Views/Leads/Sheets/AddLeadSheet.swift` (add `seedClient`, custom init, bind known client id in `performCreate`)
- Test: `OPSTests/Views/LeadFormClientSeedTests.swift`

**Step 1: Write the failing test**

```swift
import XCTest
@testable import OPS

final class LeadFormClientSeedTests: XCTestCase {
    func test_initFromClient_prefillsContactFields() {
        let client = Client(id: "cl1", name: "Calloway Homes")
        client.email = "hi@calloway.com"
        client.phoneNumber = "5551234567"
        client.address = "1240 Maple Ave"

        let form = LeadForm(fromClient: client)

        XCTAssertEqual(form.contactName, "Calloway Homes")
        XCTAssertEqual(form.email, "hi@calloway.com")
        XCTAssertEqual(form.phone, "5551234567")
        XCTAssertEqual(form.address, "1240 Maple Ave")
        XCTAssertEqual(form.title, "")          // job stays empty — operator fills it
        XCTAssertEqual(form.stage, .newLead)
    }
}
```
(Confirm `Client`'s initializer in the fixture; set only the fields the test reads.)

**Step 2: Run — verify FAIL** (`LeadForm(fromClient:)` undefined)

Run: `xcodebuild -scheme OPS -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' build-for-testing`
Expected: FAIL.

**Step 3a: Add `LeadForm.init(fromClient:)`** (in `LeadFormView.swift`, after `init(from opportunity:)`)

```swift
/// Hydrate from a client for the "new lead from the client page" path —
/// prefill the contact fields so the operator only enters the job. The known
/// client id is bound by AddLeadSheet, bypassing name-based resolution.
init(fromClient client: Client) {
    contactName = client.name
    phone = client.phoneNumber ?? ""
    email = client.email ?? ""
    address = client.address ?? ""
    if let lat = client.latitude, let lon = client.longitude {
        latitude = lat
        longitude = lon
        lastResolvedAddress = client.address
    }
}
```

**Step 3b: Seed `AddLeadSheet`** — replace `@State private var form = LeadForm()` and add an init + change `performCreate`'s client-id resolution.

Add stored input + custom init (preserves existing call sites via defaults):
```swift
var onSaved: (Opportunity) -> Void = { _ in }
var onStartSiteVisit: ((Opportunity) -> Void)? = nil
private let seedClient: Client?

@State private var form: LeadForm
// … other @State unchanged …

init(seedClient: Client? = nil,
     onSaved: @escaping (Opportunity) -> Void = { _ in },
     onStartSiteVisit: ((Opportunity) -> Void)? = nil) {
    self.seedClient = seedClient
    self.onSaved = onSaved
    self.onStartSiteVisit = onStartSiteVisit
    _form = State(initialValue: seedClient.map { LeadForm(fromClient: $0) } ?? LeadForm())
}
```

In `performCreate()`, replace the `resolveClientId` call with a known-id short-circuit:
```swift
// A lead created from a client's page binds to THAT client directly — no
// fuzzy name match, no duplicate client. Elsewhere, resolve by name as before.
let clientId: String?
if let seedClient {
    clientId = seedClient.id
} else {
    clientId = await resolveClientId(companyId: companyId, name: trimmedName)
}
```

**Step 4: Run — verify PASS**

Run: `xcodebuild -scheme OPS -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' test -only-testing:OPSTests/LeadFormClientSeedTests`
Expected: PASS. Then confirm the whole target still compiles (existing `AddLeadSheet(...)` call sites in `LeadsTabView` must still resolve): `xcodebuild -scheme OPS -destination 'generic/platform=iOS' build` → BUILD SUCCEEDED.

**Step 5: Commit**

```bash
git add OPS/Views/Leads/Sheets/LeadFormView.swift OPS/Views/Leads/Sheets/AddLeadSheet.swift OPSTests/Views/LeadFormClientSeedTests.swift
git commit -m "feat(leads): seed AddLeadSheet from a client and bind its id directly"
```

---

## Task 4: `ClientLeadRow` (presentational row) — snapshot proof

**Skills:** `ops-design` (tokens), `custom-skills:mobile-ux-design` (≥44pt, contrast, scan-first).

**Files:**
- Create: `OPS/Views/Components/Client/ClientLeadRow.swift`
- Test: `OPSTests/Views/ClientLeadRowSnapshotTests.swift` (use the `UIHostingController` + `UIWindow` + `drawHierarchy(afterScreenUpdates:)` harness — mirror `OPSTests/Views/BooksSnapshotTests.swift`; `ImageRenderer` mis-renders asset colors, so do not use it)

**Design tokens:** stage dot/badge `lead.stage.color`; `OPSStyle.Typography.body`/`.smallCaption`; `OPSStyle.Colors.primaryText`/`.secondaryText`/`.tertiaryText`; `OPSStyle.Layout.spacing1/2/2_5/3`, `cardCornerRadius`, `Border.standard`, `IconSize.xs`; value via `BooksFormat.compact`. Row leads with the **job**. `.frame(minHeight: 44)`.

**Step 1: Implement the row** (mirrors the Projects row for visual consistency)

```swift
//
//  ClientLeadRow.swift
//  OPS
//
//  One lead in the client-profile Leads section. Leads with the JOB (title) —
//  the "who" is already the page's subject. Same visual grammar as the
//  Projects rows on ContactDetailView.
//

import SwiftUI

struct ClientLeadRow: View {
    let lead: Opportunity
    /// History rows read quieter than live open leads.
    var isHistory: Bool = false

    var body: some View {
        HStack(spacing: OPSStyle.Layout.spacing2) {
            Circle()
                .fill(lead.stage.color)
                .frame(width: 8, height: 8)

            VStack(alignment: .leading, spacing: 2) {
                Text(primaryLabel)
                    .font(OPSStyle.Typography.body)
                    .foregroundColor(OPSStyle.Colors.primaryText)
                    .lineLimit(1)
                if let valueText {
                    Text(valueText)
                        .font(OPSStyle.Typography.smallCaption)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                }
            }

            Spacer()

            Text(lead.stage.displayName)
                .font(OPSStyle.Typography.smallCaption)
                .foregroundColor(lead.stage.color)
                .padding(.horizontal, OPSStyle.Layout.spacing2)
                .padding(.vertical, OPSStyle.Layout.spacing1)
                .background(RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius)
                    .fill(lead.stage.color.opacity(0.1)))
                .overlay(RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius)
                    .stroke(lead.stage.color.opacity(0.3), lineWidth: OPSStyle.Layout.Border.standard))

            Image(systemName: "chevron.right")
                .font(.system(size: OPSStyle.Layout.IconSize.xs))
                .foregroundColor(OPSStyle.Colors.tertiaryText)
        }
        .padding(.vertical, OPSStyle.Layout.spacing2_5)
        .padding(.horizontal, OPSStyle.Layout.spacing3)
        .frame(minHeight: 44)
        .contentShape(Rectangle())
        .opacity(isHistory ? 0.72 : 1)
    }

    private var primaryLabel: String {
        if let t = lead.title?.trimmingCharacters(in: .whitespaces), !t.isEmpty { return t }
        return lead.displayContactName
    }

    // Won carries actualValue; open leads carry estimatedValue. One rule covers both.
    private var valueText: String? {
        guard let v = lead.actualValue ?? lead.estimatedValue else { return nil }
        return BooksFormat.compact(v)
    }
}
```

**Step 2: Snapshot test** — render an open row and a history (won) row to PNGs in `docs/artifacts/`; assert non-nil images and eyeball. Run:
`xcodebuild -scheme OPS -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' test -only-testing:OPSTests/ClientLeadRowSnapshotTests`
Expected: PASS; PNGs written.

**Step 3: Commit**

```bash
git add OPS/Views/Components/Client/ClientLeadRow.swift OPSTests/Views/ClientLeadRowSnapshotTests.swift
git commit -m "feat(leads): client lead row (job-first, matches project row grammar)"
```

---

## Task 5: `ClientLeadsSection` (assembly: list + history + states + detail host + create)

**Skills:** `ops-design`, `custom-skills:mobile-ux-design`, `ops-copywriter` (all strings from the Shared Reference).

**Files:**
- Create: `OPS/Views/Components/Client/ClientLeadsSection.swift`
- Test: `OPSTests/Views/ClientLeadsSectionSnapshotTests.swift`

**Behavior contract:**
- Wrapped in `SectionCard(icon: OPSStyle.Icons.opportunity, title: "Leads (\(vm.openLeads.count))", actionIcon/Label/onAction: create-gated on `canCreate`)`.
- Body by state: `.loading` → small `ProgressView` (no layout jump); `.error` → `Couldn't load leads` + `Retry` (calls `reload()`); else → open rows (≤5 + `+ N MORE`/`SHOW LESS` via `isExpanded`, `OPSStyle.Animation.standard`) then the history disclosure (present only when `vm.tally.hasAny`), and when both open & closed are empty → the empty state (create block if `canCreate`, else passive `No leads`).
- History disclosure: a tappable `.nestedCard()`-free quiet row showing `// <tallies>` + chevron; toggles `isHistoryExpanded` (light haptic); expanded → `ClientLeadRow(lead:, isHistory: true)` for each `vm.closedLeads` (cap at 5 + expander, same pattern).
- Tap any row → `detailLead = lead`.
- `.navigationDestination(item: $detailLead)` → `LeadDetailView(opportunity:onMarkLost/onEdit/onMarkWon/onConvertLead)` routing to `activeSheet` (see host below), inheriting `dataController` + `permissionStore`.
- `.sheet(item: $activeSheet)` → local `sheetView(for:)` with **three** cases: `.edit → EditLeadSheet`, `.lost → LostReasonSheet().presentationDetents([.medium]).presentationDragIndicator(.visible)`, `.convert → ConvertToProjectSheet`. (Reuse the top-level `LeadsSheet` enum from `LeadsTabView.swift`.)
- `.sheet(isPresented: $showingAddLead)` → `AddLeadSheet(seedClient: client, onSaved: { _ in reload() })`.
- Reload triggers: `.task { reload() }`; `.onChange(of: activeSheet)` and `.onChange(of: detailLead)` → when either returns to `nil`, `reload()`; and `.onReceive` of the merged lead-mutation publisher below → `reload()`. After reload, if `detailLead` is no longer in `openLeads`/`closedLeads` (e.g. converted/deleted), set `detailLead = nil`.
- Resolve `companyId` = `client.companyId ?? dataController.currentUser?.companyId ?? ""`; `policy` = `permissionStore.leadAccessPolicy`; `canCreate` = `policy.canCreate`. (The **section is only mounted when `policy.canViewAny`** — enforced by the caller in Task 6 — so no `canViewAny` check is needed here.)

**Merged lead-mutation publisher** (mirror the names `LeadsTabView` reloads on):
```swift
private static let leadMutationNames: [Notification.Name] = [
    "LeadCreatedSuccess", "LeadUpdatedSuccess", "LeadMarkedLostSuccess",
    "LeadMarkedWonSuccess", "LeadConvertedSuccess", "LeadLinkedProjectSuccess",
    "LeadArchivedSuccess", "LeadDeletedSuccess"
].map(Notification.Name.init) + [.opsLeadsDidChange]

private var leadMutations: some Publisher {
    Publishers.MergeMany(Self.leadMutationNames.map {
        NotificationCenter.default.publisher(for: $0)
    })
}
```
(`import Combine`. Confirm `.opsLeadsDidChange` is declared — it is used in `LeadsTabView.swift:256`.)

**Reference implementation** (adapt to confirmed local APIs):

```swift
//
//  ClientLeadsSection.swift
//  OPS
//
//  The Leads section on the client profile (ContactDetailView), above
//  Projects. Open leads up top (job-first), a collapsed won/lost history
//  peek below, tap-through to the full lead, and create pre-linked to the
//  client. Only mounted when the operator can view pipeline (caller-gated).
//
//  Spec: docs/superpowers/specs/2026-07-21-ios-client-leads-section-design.md
//

import SwiftUI
import Combine

struct ClientLeadsSection: View {
    let client: Client

    @EnvironmentObject private var dataController: DataController
    @EnvironmentObject private var permissionStore: PermissionStore
    @StateObject private var vm = ClientLeadsViewModel()

    @State private var isOpenExpanded = false
    @State private var isHistoryExpanded = false
    @State private var isHistoryListExpanded = false
    @State private var detailLead: Opportunity?
    @State private var activeSheet: LeadsSheet?
    @State private var showingAddLead = false

    private var companyId: String { client.companyId ?? dataController.currentUser?.companyId ?? "" }
    private var policy: LeadAccessPolicy { permissionStore.leadAccessPolicy }
    private var canCreate: Bool { policy.canCreate }

    var body: some View {
        SectionCard(
            icon: OPSStyle.Icons.opportunity,
            title: "Leads (\(vm.openLeads.count))",
            actionIcon: canCreate ? OPSStyle.Icons.plus : nil,
            actionLabel: canCreate ? "Add" : nil,
            onAction: canCreate ? { showingAddLead = true } : nil,
            contentPadding: EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0)
        ) {
            content
        }
        .task { reload() }
        .onChange(of: activeSheet) { if $0 == nil { reload() } }
        .onChange(of: detailLead) { if $0 == nil { reload() } }
        .onReceive(leadMutations) { _ in reload() }
        .navigationDestination(item: $detailLead) { lead in
            LeadDetailView(
                opportunity: lead,
                onMarkLost: { activeSheet = .lost(lead) },
                onEdit:     { activeSheet = .edit(lead) },
                onMarkWon:  { activeSheet = .convert(lead) },
                onConvertLead: { converted in activeSheet = .convert(converted) }
            )
            .environmentObject(dataController)
            .environmentObject(permissionStore)
        }
        .sheet(item: $activeSheet) { sheetView(for: $0) }
        .sheet(isPresented: $showingAddLead) {
            AddLeadSheet(seedClient: client, onSaved: { _ in reload() })
                .environmentObject(dataController)
        }
    }

    // MARK: content states

    @ViewBuilder private var content: some View {
        switch vm.loadState {
        case .loading where vm.openLeads.isEmpty && vm.closedLeads.isEmpty:
            ProgressView()
                .tint(OPSStyle.Colors.secondaryText)
                .frame(maxWidth: .infinity)
                .padding(.vertical, OPSStyle.Layout.spacing5)
        case .error where vm.openLeads.isEmpty && vm.closedLeads.isEmpty:
            errorState
        default:
            if vm.openLeads.isEmpty && !vm.tally.hasAny {
                emptyState
            } else {
                VStack(spacing: 0) {
                    openList
                    if vm.tally.hasAny { historyDisclosure }
                }
            }
        }
    }

    // openList: ForEach over prefix(5)/full with Divider between, tap → detailLead,
    // then a "+ N MORE"/"SHOW LESS" button when > 5 (copy the Projects pattern at
    // ContactDetailView.swift:1211-1291 exactly, swapping ClientLeadRow(lead:) for
    // the inline project row and `selectedProject = project` for `detailLead = lead`).

    // historyDisclosure: a Divider, then a Button toggling isHistoryExpanded (light
    // haptic + OPSStyle.Animation.standard) with label `// \(historyLabel)` in
    // OPSStyle.Typography.smallCaption / .secondaryText and a chevron; when expanded,
    // ForEach vm.closedLeads (prefix 5 / isHistoryListExpanded) as
    // ClientLeadRow(lead:, isHistory: true), tap → detailLead, + expander.

    // emptyState: if canCreate → tappable block (OPSStyle.Icons.opportunity, "No leads
    // yet" / "Create one?") → showingAddLead = true; else passive icon + "No leads"
    // (mirror ContactDetailView.swift:1292-1329).

    // errorState: icon + "Couldn't load leads" + a "Retry" button → reload().

    private var historyLabel: String {
        var parts: [String] = []
        if vm.tally.won > 0 { parts.append("\(vm.tally.won) WON") }
        if vm.tally.lost > 0 { parts.append("\(vm.tally.lost) LOST") }
        if vm.tally.discarded > 0 { parts.append("\(vm.tally.discarded) DISCARDED") }
        return parts.joined(separator: " · ")
    }

    @ViewBuilder private func sheetView(for sheet: LeadsSheet) -> some View {
        switch sheet {
        case .edit(let opp):    EditLeadSheet(opportunity: opp)
        case .lost(let opp):    LostReasonSheet(opportunity: opp)
                                    .presentationDetents([.medium])
                                    .presentationDragIndicator(.visible)
        case .convert(let opp): ConvertToProjectSheet(opportunity: opp)
        default:                EmptyView()   // .add/.log/.wonChooser unused here
        }
    }

    private func reload() {
        let cid = companyId, clid = client.id, pol = policy
        Task {
            await vm.load(companyId: cid, clientId: clid, policy: pol)
            if let open = detailLead,
               !vm.openLeads.contains(where: { $0.id == open.id }),
               !vm.closedLeads.contains(where: { $0.id == open.id }) {
                detailLead = nil
            }
        }
    }

    private static let leadMutationNames: [Notification.Name] = [
        "LeadCreatedSuccess", "LeadUpdatedSuccess", "LeadMarkedLostSuccess",
        "LeadMarkedWonSuccess", "LeadConvertedSuccess", "LeadLinkedProjectSuccess",
        "LeadArchivedSuccess", "LeadDeletedSuccess"
    ].map(Notification.Name.init) + [.opsLeadsDidChange]

    private var leadMutations: some Publisher {
        Publishers.MergeMany(Self.leadMutationNames.map {
            NotificationCenter.default.publisher(for: $0)
        })
    }
}
```

> Fill in the `openList`, `historyDisclosure`, `emptyState`, `errorState` bodies by copying the corresponding Projects-section markup (`ContactDetailView.swift:1211-1329`) so the visual grammar matches exactly. Do not invent new spacing/typography — reuse the tokens listed in the Shared Reference. `.onChange(of:)` uses the iOS-17 two-parameter or zero-parameter form as the codebase already does elsewhere — match the local convention (target is iOS 17.6).

**Snapshot tests** (`ClientLeadsSectionSnapshotTests`, same harness) for: open+history, open-only, history-only (empty open), empty-create, empty-passive. Inject state via `vm.loaderOverride` (or call `vm.apply(...)` on a section-owned VM) with a fixed lead set and a stub environment (`DataController`/`PermissionStore` test instances). PNGs → `docs/artifacts/`.

Run: `xcodebuild -scheme OPS -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' test -only-testing:OPSTests/ClientLeadsSectionSnapshotTests`
Expected: PASS; PNGs written; eyeball each state.

**Commit**

```bash
git add OPS/Views/Components/Client/ClientLeadsSection.swift OPSTests/Views/ClientLeadsSectionSnapshotTests.swift
git commit -m "feat(leads): client leads section — open list, history peek, detail host, create"
```

---

## Task 6: Splice into `ContactDetailView`

**Skills:** `ops-design` (spacing parity).

**Files:**
- Modify: `OPS/Views/Components/User/ContactDetailView.swift` (insert between the Sub Contacts block end at line 221 and the `// Projects section` comment at line 223)

**Step 1: Insert** (client-only, gated on view permission, matching sibling spacing + the `showFullContact` fade)

```swift
                        // Leads section (for clients only, gated on pipeline view) —
                        // positioned ABOVE Projects: a lead is potential work, a
                        // project is won work; time-sensitive leads earn the higher slot.
                        if isClient, let client = client,
                           permissionStore.leadAccessPolicy.canViewAny {
                            ClientLeadsSection(client: client)
                                .padding(.horizontal)
                                .padding(.top, OPSStyle.Layout.spacing3)
                                .opacity(showFullContact ? 1 : 0)
                                .offset(y: showFullContact ? 0 : 20)
                                .animation(.easeInOut(duration: 0.5).delay(0.3), value: showFullContact)
                        }

                        // Projects section
```

**Step 2: Build**

Run: `xcodebuild -scheme OPS -destination 'generic/platform=iOS' build`
Expected: BUILD SUCCEEDED.

**Step 3: Commit**

```bash
git add OPS/Views/Components/User/ContactDetailView.swift
git commit -m "feat(leads): show the leads section on the client profile"
```

---

## Task 7: Full build + test gate

**Files:** none (verification).

**Step 1:** `ps aux | grep xcodebuild | grep -v grep` — ensure no sibling build on shared DerivedData.
**Step 2:** Device build: `xcodebuild -scheme OPS -destination 'generic/platform=iOS' build` → BUILD SUCCEEDED.
**Step 3:** Test build + run the new suites:
`xcodebuild -scheme OPS -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' test -only-testing:OPSTests/ClientLeadsViewModelTests -only-testing:OPSTests/LeadFormClientSeedTests -only-testing:OPSTests/ClientLeadRowSnapshotTests -only-testing:OPSTests/ClientLeadsSectionSnapshotTests`
Expected: all PASS.
**Step 4:** If anything failed, fix (use `superpowers:systematic-debugging`), re-run, then commit fixes.

---

## Task 8: Manual verification + proof (screenshots)

**Files:** proof artifacts → `docs/artifacts/` (delete after unless reference-worthy).

**Steps:**
1. Run OPS in the iOS 26.5 simulator (iPhone 17); sign in (avoid Firebase throttling — clean sim or Google/Apple).
2. Open a client that has both open and closed leads (create a couple via the section's Add + change stages / mark won/lost if needed).
3. Verify, capturing a screenshot of each: (a) section shows open leads job-first with stage badges; (b) history peek line renders `// n WON · m LOST` and expands; (c) tapping a lead opens `LeadDetailView` and an action (e.g. mark lost) reflects back after reload; (d) "Add" opens a lead pre-filled with the client and the saved lead appears linked; (e) a crew/no-pipeline account does **not** see the section.
4. Save screenshots to `docs/artifacts/client-leads-section/`. These are the proof shown to Jackson.

---

## Task 9: Design-system audit

**Skills:** `custom-skills:audit-design-system` (mandatory before "done").

**Steps:** Run the audit over the four new/edited UI files (`ClientLeadRow`, `ClientLeadsSection`, the `ContactDetailView` insertion, `AddLeadSheet` changes). Confirm **zero** hardcoded color/spacing/radius/font values — every value traces to `OPSStyle` or `PipelineStage.color`. Fix any finding, re-run, commit.

```bash
git add -p   # stage only audit fixes in these files, by hunk
git commit -m "style(leads): design-system token compliance for client leads section"
```

---

## Task 10: Update the bible

**Files:** Modify the pipeline/CRM feature doc under `ops-software-bible/` (locate the leads/pipeline section).

**Steps:** Record the client-scoped leads surface on `ContactDetailView` (open + history peek, tap-through, create-from-client) and the new `OpportunityRepository.fetchAllLinked(toClientId:)` read path. Keep it factual and current.

```bash
git add ops-software-bible/<edited-file>.md
git commit -m "docs(bible): client-scoped leads surface on the client profile"
```

---

## Definition of done
- All four test suites pass; device build clean.
- Section renders correctly across states (screenshots in `docs/artifacts/`).
- Tap-through and create-from-client verified live; permission gating verified.
- Design-system audit clean.
- Bible updated.
- All commits atomic, on `main`, no AI attribution, sibling WIP untouched.
- **Not pushed** — pushing is Jackson's call (this ships to customers only in the next App Store build).
