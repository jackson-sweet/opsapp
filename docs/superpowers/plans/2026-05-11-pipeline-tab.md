# Pipeline Tab Promotion Implementation Plan

> **STATUS: UNBLOCKED — READY TO EXECUTE (PM-coordinated).**
>
> **Sequencing decision (2026-05-11, user choice — option B):** Reconstruction-first path is now active. Books Phase 2 is DEFERRED until after this Pipeline-tab plan AND the Books reconstruction plan land on main. Order: **Pipeline-tab → Books-UI-Reconstruction → leaner Phase 2.**
>
> Implications for the previous "BLOCKED" warnings:
> 1. ~~Books Phase 2 chunk 2C refactors `PipelineStage` to struct + repository — invalidates Task 1~~ → **OBSOLETE.** Phase 2 is no longer landing first; `PipelineStage` stays as the existing enum. Task 1's `PipelineStage+Color.swift` extension is valid as written.
> 2. ~~Books Phase 2 chunks 2D / 2E / 2G add files in `Books/Pipeline/` that Task 13 must enumerate~~ → **OBSOLETE.** Those chunks land AFTER this plan + Reconstruction; no extra files to move.
> 3. ~~Every `xcodebuild` command must be removed~~ → **OBSOLETE.** The "Don't run xcodebuild" memory was updated 2026-05-11: xcodebuild is now permitted in this project. Standing PM caveat: ask the user to confirm no other terminals are mid-build before invoking, to avoid `DerivedData/build.db` collisions. Use `-destination 'generic/platform=iOS'` (never simulator).
>
> **Coordination with Reconstruction (`2026-05-11-books-ui-reconstruction.md`):** The two plans share these touch points and must land in this order:
> - Pipeline-tab Task 13 moves files OUT of `OPS/Views/Books/Pipeline/` to `OPS/Views/Leads/`
> - Pipeline-tab Task 16 adds the LEADS tab to `MainTabView` while leaving Books's Pipeline-segment infrastructure in place (transient duplication; both build green)
> - Reconstruction Phase C2/C4 then drops Books's `.pipeline` segment + `pipeline.view` from `hasBooksAccess`, removing the duplication
> - Net: brief intentional duplication between this plan landing and Reconstruction landing; ~no broken state at any commit boundary

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Promote Pipeline from a Books-tab segment to a standalone top-level `LEADS` tab in the OPS iOS app, with redesigned primary surface (carousel of stage pages, ball-in-court bar, redesigned cards, 5-card stat carousel header).

**Architecture:** Preserve existing data layer (`Opportunity`, `OpportunityRepository`, `PipelineViewModel`, `StageTransition`). Replace surface layer entirely. New `Leads/` view directory; old `Books/Pipeline/` moved or deleted. New computed VM properties for ball-in-court and stat-card numerics. First iOS use of bible's `PipelineStage` hex colors via new Swift extension (note: Phase 2 may turn this into a property of the new stage struct instead).

**Tech Stack:** Swift 5 + SwiftUI, XCTest for VM tests, Supabase via existing repository pattern, OPSStyle design tokens, JetBrains Mono/Mohave/Cake Mono fonts.

**Spec:** [docs/superpowers/specs/2026-05-11-pipeline-tab-design.md](../specs/2026-05-11-pipeline-tab-design.md)

**Coordination gate:** Phase 3 ("Tab integration") is the rendezvous point with the parent Books reconstruction session. Do NOT start Phase 3 until the Books spec is approved AND that session's diff to `MainTabView.swift` / `BooksSection.swift` is queued. Phases 1–2 can land independently.

**Build command (never use simulator):**

```bash
xcodebuild -scheme OPS -destination 'generic/platform=iOS' build
```

**Test command (VM unit tests):**

```bash
xcodebuild test -scheme OPS -destination 'platform=iOS Simulator,name=iPhone 15' -only-testing:OPSTests/PipelineViewModelTests
```

(Tests run on simulator — only the *app build* must use generic device per `ops-ios/CLAUDE.md`. Per the standing PM caveat, ask the user before invoking xcodebuild from a spawn so concurrent terminals don't race on `DerivedData/build.db`.)

---

## File Structure

### New files (10)

| Path | Responsibility |
|---|---|
| `OPS/DataModels/Enums/PipelineStage+Color.swift` | `Color` property on `PipelineStage` mapping bible hex values |
| `OPS/Views/Leads/LeadsTabView.swift` | Root view, composes header + bar + strip + paged carousel |
| `OPS/Views/Leads/LeadsHeaderCarousel.swift` | Pipeline-scoped 5-card stat carousel (forks SmartStatCarousel pattern) |
| `OPS/Views/Leads/BallInCourtBar.swift` | Severity-tiered floating bar + filter toggle |
| `OPS/Views/Leads/LeadListPage.swift` | Per-stage list page rendered inside the carousel TabView |
| `OPS/Views/Leads/Components/StageStripView.swift` | Redesigned: color pip + mono count + CLOSED expander |
| `OPS/Views/Leads/Components/LeadCardView.swift` | Redesigned: stage-color rail, mono value, urgency chip, swipe actions |
| `OPS/Views/Leads/Components/ForecastBreakdownSheet.swift` | Tap target for weighted-forecast carousel card |
| `OPSTests/Pipeline/PipelineViewModelInCourtTests.swift` | XCTest coverage for new in-court + stat computeds |

### Moved files (7)

`OPS/Views/Books/Pipeline/` → `OPS/Views/Leads/` (preserved as-is, just relocated):

- `AddLeadSheet.swift`
- `EditLeadSheet.swift`
- `LeadDetailView.swift`
- `LeadActionSheet.swift`
- `LeadLogActivitySheet.swift`
- `AddFollowUpSheet.swift`
- `LostReasonSheet.swift`

### Modified files (6)

| Path | Change |
|---|---|
| `OPS/ViewModels/PipelineViewModel.swift` | Add `inCourtCount`, `inCourtBuckets`, `inCourtTotalValue`, `inCourtOpportunityIds`, `closeRate`, `avgVelocityDays`, `staleLeadsTotalValue`, `oldestStaleDescription` computeds + a `currentUserId: String?` settable property |
| `OPS/Utilities/AnalyticsManager.swift` | Add `case books` to `TabName` enum |
| `OPS/Views/Components/Common/AppHeader.swift` | Add `case leads` to `HeaderType` enum |
| `OPS/Views/MainTabView.swift` | New tab between Home and Job Board; rename `pipelineTabIndex` → `booksTabIndex` and `isPipelineTab` → `isBooksTab`; add `leadsTabIndex`; fix analytics; route `WizardNavigateToTarget` "Pipeline" to new tab |
| `OPS/Views/Components/FloatingActionMenu.swift` | Accept `isLeadsTab: Bool`; reorder MONEY group when on Leads tab |
| `OPS/Views/Books/BooksTabView.swift` | (Parent session owns) Remove `.pipeline` segment routing |
| `OPS/Views/Books/BooksSection.swift` | (Parent session owns) Remove `.pipeline` enum case |

### Deleted files (3)

- `OPS/Views/Books/Pipeline/PipelineSectionView.swift` (replaced by `LeadsTabView` + `LeadListPage`)
- `OPS/Views/Books/Pipeline/StageStripView.swift` (replaced by Leads version)
- `OPS/Views/Books/Pipeline/LeadCardView.swift` (replaced by Leads version)

### Bible

- `ops-software-bible/09_FINANCIAL_SYSTEM.md` — Pipeline / CRM section + iOS Implementation subsection rewritten.

---

# Phase 1 — Data layer additions (independent, no coordination required)

These tasks add purely additive code with no integration changes. Safe to land before Books reconstruction is locked.

## Task 1: `PipelineStage` color extension

**Files:**
- Create: `OPS/DataModels/Enums/PipelineStage+Color.swift`

- [ ] **Step 1: Create the extension file**

```swift
//
//  PipelineStage+Color.swift
//  OPS
//
//  Stage color mapping from bible 09_FINANCIAL_SYSTEM.md § Pipeline Stages.
//  First iOS use of stage colors; previously web-only.
//

import SwiftUI

extension PipelineStage {
    /// Color identity for this stage. Used for the stage-color leading rail on
    /// lead cards, the stage strip color pip, and the mini stacked bar in the
    /// LeadsHeaderCarousel's "ACTIVE PIPELINE" card.
    var color: Color {
        switch self {
        case .newLead:     return Color(red: 0.737, green: 0.737, blue: 0.737)  // #BCBCBC
        case .qualifying:  return Color(red: 0.506, green: 0.584, blue: 0.710)  // #8195B5
        case .quoting:     return Color(red: 0.769, green: 0.659, blue: 0.408)  // #C4A868
        case .quoted:      return Color(red: 0.710, green: 0.639, blue: 0.506)  // #B5A381
        case .followUp:    return Color(red: 0.631, green: 0.510, blue: 0.710)  // #A182B5
        case .negotiation: return Color(red: 0.710, green: 0.510, blue: 0.537)  // #B58289
        case .won:         return Color(red: 0.616, green: 0.710, blue: 0.510)  // #9DB582
        case .lost:        return Color(red: 0.420, green: 0.447, blue: 0.502)  // #6B7280
        }
    }
}
```

- [ ] **Step 2: Verify the build**

```bash
xcodebuild -scheme OPS -destination 'generic/platform=iOS' build 2>&1 | tail -20
```

Expected: BUILD SUCCEEDED. No new warnings.

- [ ] **Step 3: Commit**

```bash
git add OPS/DataModels/Enums/PipelineStage+Color.swift
git commit -m "feat(leads): add PipelineStage.color extension from bible hex values"
```

---

## Task 2: Add `currentUserId` setter to `PipelineViewModel`

The in-court computation needs to know who "me" is. Inject via a `setup` overload — keeps the VM testable in isolation.

**Files:**
- Modify: `OPS/ViewModels/PipelineViewModel.swift:13-28`

- [ ] **Step 1: Write the failing test**

Append to `OPSTests/Pipeline/PipelineViewModelTests.swift`:

```swift
func test_currentUserId_canBeSetAfterSetup() {
    let vm = PipelineViewModel()
    vm.setup(companyId: "co", currentUserId: "user-123")
    XCTAssertEqual(vm.currentUserId, "user-123")
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
xcodebuild test -scheme OPS -destination 'platform=iOS Simulator,name=iPhone 15' -only-testing:OPSTests/PipelineViewModelTests/test_currentUserId_canBeSetAfterSetup 2>&1 | tail -10
```

Expected: FAIL — `setup(companyId:currentUserId:)` does not exist.

- [ ] **Step 3: Add the property and overload**

In `OPS/ViewModels/PipelineViewModel.swift`, after line 18 (`@Published var selectedStage`), add:

```swift
    /// Identity of the operator whose pipeline this is. Used by in-court
    /// computations to scope "ball in your court" leads to the current user.
    /// nil → in-court counts return 0.
    @Published var currentUserId: String?
```

Replace the existing `setup(companyId:)` method (line 25) with:

```swift
    func setup(companyId: String, currentUserId: String? = nil) {
        self.companyId = companyId
        self.currentUserId = currentUserId
        self.repository = OpportunityRepository(companyId: companyId)
    }
```

- [ ] **Step 4: Run test to verify it passes**

```bash
xcodebuild test -scheme OPS -destination 'platform=iOS Simulator,name=iPhone 15' -only-testing:OPSTests/PipelineViewModelTests/test_currentUserId_canBeSetAfterSetup 2>&1 | tail -10
```

Expected: PASS.

- [ ] **Step 5: Verify the full suite still passes**

```bash
xcodebuild test -scheme OPS -destination 'platform=iOS Simulator,name=iPhone 15' -only-testing:OPSTests/PipelineViewModelTests 2>&1 | tail -10
```

Expected: PASS (all existing tests + new one).

- [ ] **Step 6: Commit**

```bash
git add OPS/ViewModels/PipelineViewModel.swift OPSTests/Pipeline/PipelineViewModelTests.swift
git commit -m "feat(leads): add currentUserId to PipelineViewModel.setup"
```

---

## Task 3: Add in-court computed properties to `PipelineViewModel`

**Files:**
- Modify: `OPS/ViewModels/PipelineViewModel.swift` (after line 89 — append to the "Derivations" section)
- Create: `OPSTests/Pipeline/PipelineViewModelInCourtTests.swift`

- [ ] **Step 1: Write the failing test file**

Create `OPSTests/Pipeline/PipelineViewModelInCourtTests.swift`:

```swift
//
//  PipelineViewModelInCourtTests.swift
//  OPSTests
//
//  Coverage for ball-in-court derivations on PipelineViewModel.
//

import XCTest
@testable import OPS

@MainActor
final class PipelineViewModelInCourtTests: XCTestCase {

    func makeOpp(
        id: String = UUID().uuidString,
        stage: PipelineStage = .newLead,
        assignedTo: String? = "me",
        nextFollowUpAt: Date? = nil,
        lastActivityAt: Date? = nil,
        stageEnteredAt: Date = Date(),
        estimatedValue: Double? = nil,
        deletedAt: Date? = nil,
        archivedAt: Date? = nil
    ) -> Opportunity {
        let opp = Opportunity(
            id: id,
            companyId: "co",
            contactName: "Test",
            stage: stage,
            stageEnteredAt: stageEnteredAt
        )
        opp.assignedTo = assignedTo
        opp.nextFollowUpAt = nextFollowUpAt
        opp.lastActivityAt = lastActivityAt
        opp.estimatedValue = estimatedValue
        opp.deletedAt = deletedAt
        opp.archivedAt = archivedAt
        return opp
    }

    func test_inCourtCount_isZeroWhenCurrentUserIdNil() {
        let vm = PipelineViewModel()
        vm.allOpportunities = [makeOpp()]
        XCTAssertNil(vm.currentUserId)
        XCTAssertEqual(vm.inCourtCount, 0)
    }

    func test_inCourtCount_excludesTerminalStages() {
        let vm = PipelineViewModel()
        vm.currentUserId = "me"
        let won = makeOpp(stage: .won)
        let lost = makeOpp(stage: .lost)
        vm.allOpportunities = [won, lost]
        XCTAssertEqual(vm.inCourtCount, 0)
    }

    func test_inCourtCount_excludesUnassignedAndOthers() {
        let vm = PipelineViewModel()
        vm.currentUserId = "me"
        let untouched = makeOpp(stage: .newLead, assignedTo: "me")  // untouched (newLead + no activity)
        let other = makeOpp(stage: .newLead, assignedTo: "other-user")
        let unassigned = makeOpp(stage: .newLead, assignedTo: nil)
        vm.allOpportunities = [untouched, other, unassigned]
        XCTAssertEqual(vm.inCourtCount, 1)
    }

    func test_inCourtCount_excludesDeletedAndArchived() {
        let vm = PipelineViewModel()
        vm.currentUserId = "me"
        let active = makeOpp(stage: .newLead)
        let deleted = makeOpp(stage: .newLead, deletedAt: Date())
        let archived = makeOpp(stage: .newLead, archivedAt: Date())
        vm.allOpportunities = [active, deleted, archived]
        XCTAssertEqual(vm.inCourtCount, 1)
    }

    func test_inCourtBuckets_overdueTrumpsStale() {
        let vm = PipelineViewModel()
        vm.currentUserId = "me"
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date())!
        let tenDaysAgo = Calendar.current.date(byAdding: .day, value: -10, to: Date())!

        // Overdue AND stale — should land in OVERDUE bucket only
        let both = makeOpp(stage: .quoting, nextFollowUpAt: yesterday, stageEnteredAt: tenDaysAgo)
        vm.allOpportunities = [both]
        XCTAssertEqual(vm.inCourtBuckets.overdue, 1)
        XCTAssertEqual(vm.inCourtBuckets.stale, 0)
        XCTAssertEqual(vm.inCourtBuckets.untouched, 0)
    }

    func test_inCourtBuckets_staleFallsThroughOverdue() {
        let vm = PipelineViewModel()
        vm.currentUserId = "me"
        let tenDaysAgo = Calendar.current.date(byAdding: .day, value: -10, to: Date())!
        let staleOnly = makeOpp(stage: .quoting, nextFollowUpAt: nil, stageEnteredAt: tenDaysAgo)
        vm.allOpportunities = [staleOnly]
        XCTAssertEqual(vm.inCourtBuckets.overdue, 0)
        XCTAssertEqual(vm.inCourtBuckets.stale, 1)
        XCTAssertEqual(vm.inCourtBuckets.untouched, 0)
    }

    func test_inCourtBuckets_untouchedRequiresNewLeadAndNoActivity() {
        let vm = PipelineViewModel()
        vm.currentUserId = "me"
        let untouchedNew = makeOpp(stage: .newLead, lastActivityAt: nil, stageEnteredAt: Date())
        let touchedNew = makeOpp(stage: .newLead, lastActivityAt: Date(), stageEnteredAt: Date())
        vm.allOpportunities = [untouchedNew, touchedNew]
        XCTAssertEqual(vm.inCourtBuckets.untouched, 1)
        XCTAssertEqual(vm.inCourtCount, 1)  // touchedNew isn't in court (no signal)
    }

    func test_inCourtBuckets_followUpStageRollsIntoStale() {
        let vm = PipelineViewModel()
        vm.currentUserId = "me"
        let inFollowUpStage = makeOpp(stage: .followUp, nextFollowUpAt: nil, stageEnteredAt: Date())
        vm.allOpportunities = [inFollowUpStage]
        XCTAssertEqual(vm.inCourtBuckets.overdue, 0)
        XCTAssertEqual(vm.inCourtBuckets.stale, 1)
        XCTAssertEqual(vm.inCourtBuckets.untouched, 0)
    }

    func test_inCourtTotalValue_sumsEstimatedValues() {
        let vm = PipelineViewModel()
        vm.currentUserId = "me"
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date())!
        let a = makeOpp(stage: .quoting, nextFollowUpAt: yesterday, estimatedValue: 10_000)
        let b = makeOpp(stage: .quoting, nextFollowUpAt: yesterday, estimatedValue: 32_300)
        let c = makeOpp(stage: .quoting, nextFollowUpAt: yesterday, estimatedValue: nil)  // contributes 0
        vm.allOpportunities = [a, b, c]
        XCTAssertEqual(vm.inCourtTotalValue, 42_300, accuracy: 0.01)
    }

    func test_inCourtOpportunityIds_returnsExactSet() {
        let vm = PipelineViewModel()
        vm.currentUserId = "me"
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date())!
        let a = makeOpp(id: "a", stage: .quoting, nextFollowUpAt: yesterday)
        let b = makeOpp(id: "b", stage: .quoting, nextFollowUpAt: nil)  // not in court
        vm.allOpportunities = [a, b]
        XCTAssertEqual(vm.inCourtOpportunityIds, Set(["a"]))
    }
}
```

- [ ] **Step 2: Run tests — verify all 10 fail**

```bash
xcodebuild test -scheme OPS -destination 'platform=iOS Simulator,name=iPhone 15' -only-testing:OPSTests/PipelineViewModelInCourtTests 2>&1 | tail -20
```

Expected: 10 FAIL (`inCourtCount`, `inCourtBuckets`, `inCourtTotalValue`, `inCourtOpportunityIds` undefined).

- [ ] **Step 3: Add the computed properties to `PipelineViewModel`**

In `OPS/ViewModels/PipelineViewModel.swift`, after line 94 (`isPipelineEmpty`), insert:

```swift
    // MARK: - Ball-in-court derivations

    /// Severity buckets — each in-court lead lands in exactly one bucket,
    /// highest severity wins. `followUp`-stage-only signal rolls into stale.
    struct InCourtBuckets: Equatable {
        var overdue: Int
        var stale: Int
        var untouched: Int

        var total: Int { overdue + stale + untouched }
    }

    /// Filtered list — leads where the next move is the current user's.
    /// Returns empty when `currentUserId == nil`.
    private var inCourtOpportunities: [Opportunity] {
        guard let me = currentUserId else { return [] }
        let now = Date()
        return allOpportunities.filter { opp in
            guard opp.assignedTo == me else { return false }
            guard !opp.stage.isTerminal else { return false }
            guard !opp.isDeleted, !opp.isArchived else { return false }

            let isOverdue = (opp.nextFollowUpAt.map { $0 <= now }) ?? false
            let isStale = opp.isStale
            let isFollowUpStage = opp.stage == .followUp
            let isUntouched = (opp.stage == .newLead && opp.lastActivityAt == nil)

            return isOverdue || isStale || isFollowUpStage || isUntouched
        }
    }

    var inCourtCount: Int {
        inCourtOpportunities.count
    }

    var inCourtBuckets: InCourtBuckets {
        let now = Date()
        var b = InCourtBuckets(overdue: 0, stale: 0, untouched: 0)
        for opp in inCourtOpportunities {
            let isOverdue = (opp.nextFollowUpAt.map { $0 <= now }) ?? false
            if isOverdue {
                b.overdue += 1
            } else if opp.isStale || opp.stage == .followUp {
                b.stale += 1
            } else if opp.stage == .newLead && opp.lastActivityAt == nil {
                b.untouched += 1
            }
        }
        return b
    }

    var inCourtTotalValue: Double {
        inCourtOpportunities.reduce(0) { $0 + ($1.estimatedValue ?? 0) }
    }

    var inCourtOpportunityIds: Set<String> {
        Set(inCourtOpportunities.map { $0.id })
    }
```

- [ ] **Step 4: Run tests — verify all pass**

```bash
xcodebuild test -scheme OPS -destination 'platform=iOS Simulator,name=iPhone 15' -only-testing:OPSTests/PipelineViewModelInCourtTests 2>&1 | tail -20
```

Expected: 10 PASS.

- [ ] **Step 5: Commit**

```bash
git add OPS/ViewModels/PipelineViewModel.swift OPSTests/Pipeline/PipelineViewModelInCourtTests.swift
git commit -m "feat(leads): add ball-in-court derivations to PipelineViewModel"
```

---

## Task 4: Add carousel stat computeds to `PipelineViewModel`

For the LeadsHeaderCarousel's CLOSE RATE, VELOCITY, STALE RISK cards.

**Files:**
- Modify: `OPS/ViewModels/PipelineViewModel.swift` (append after Task 3's additions)
- Modify: `OPSTests/Pipeline/PipelineViewModelInCourtTests.swift` (append)

- [ ] **Step 1: Write the failing tests**

Append to `OPSTests/Pipeline/PipelineViewModelInCourtTests.swift`:

```swift
    // MARK: - Stat-card computeds

    func test_staleLeadsTotalValue_sumsStaleEstimates() {
        let vm = PipelineViewModel()
        let tenDaysAgo = Calendar.current.date(byAdding: .day, value: -10, to: Date())!
        let stale1 = makeOpp(stage: .quoting, stageEnteredAt: tenDaysAgo, estimatedValue: 5_000)
        let stale2 = makeOpp(stage: .quoting, stageEnteredAt: tenDaysAgo, estimatedValue: 13_400)
        let fresh = makeOpp(stage: .quoting, stageEnteredAt: Date(), estimatedValue: 1_000_000)
        vm.allOpportunities = [stale1, stale2, fresh]
        XCTAssertEqual(vm.staleLeadsTotalValue, 18_400, accuracy: 0.01)
    }

    func test_oldestStaleDescription_returnsOldestStaleSummary() {
        let vm = PipelineViewModel()
        let fiveDaysAgo = Calendar.current.date(byAdding: .day, value: -5, to: Date())!
        let twelveDaysAgo = Calendar.current.date(byAdding: .day, value: -12, to: Date())!
        let older = makeOpp(stage: .quoting, stageEnteredAt: twelveDaysAgo)
        let newer = makeOpp(stage: .qualifying, stageEnteredAt: fiveDaysAgo)
        vm.allOpportunities = [newer, older]
        // 12d in QUOTING (newLead is 3d threshold; quoting is 5d; older qualifies as stale)
        XCTAssertEqual(vm.oldestStaleDescription, "12D IN QUOTING")
    }

    func test_oldestStaleDescription_nilWhenNoStale() {
        let vm = PipelineViewModel()
        vm.allOpportunities = [makeOpp(stage: .quoting, stageEnteredAt: Date())]
        XCTAssertNil(vm.oldestStaleDescription)
    }

    func test_closeRate_returnsNilWhenInsufficientData() {
        let vm = PipelineViewModel()
        // Only 3 closed in window — below the 5-minimum threshold
        let recently = Calendar.current.date(byAdding: .day, value: -10, to: Date())!
        let won = makeOpp(stage: .won)
        won.actualCloseDate = recently
        let lost = makeOpp(stage: .lost)
        lost.actualCloseDate = recently
        let lost2 = makeOpp(stage: .lost)
        lost2.actualCloseDate = recently
        vm.allOpportunities = [won, lost, lost2]
        XCTAssertNil(vm.closeRate(periodDays: 90))
    }

    func test_closeRate_computesAcrossPeriod() {
        let vm = PipelineViewModel()
        let recently = Calendar.current.date(byAdding: .day, value: -10, to: Date())!
        var opps: [Opportunity] = []
        for _ in 0..<3 {  // 3 won
            let o = makeOpp(stage: .won); o.actualCloseDate = recently; opps.append(o)
        }
        for _ in 0..<5 {  // 5 lost
            let o = makeOpp(stage: .lost); o.actualCloseDate = recently; opps.append(o)
        }
        vm.allOpportunities = opps
        // 3 / (3+5) = 0.375
        XCTAssertEqual(vm.closeRate(periodDays: 90) ?? 0, 0.375, accuracy: 0.001)
    }

    func test_closeRate_excludesClosesOutsidePeriod() {
        let vm = PipelineViewModel()
        let oldClose = Calendar.current.date(byAdding: .day, value: -120, to: Date())!  // outside 90d window
        let recentClose = Calendar.current.date(byAdding: .day, value: -10, to: Date())!
        var opps: [Opportunity] = []
        // 5 within window (3 won, 2 lost)
        for _ in 0..<3 { let o = makeOpp(stage: .won); o.actualCloseDate = recentClose; opps.append(o) }
        for _ in 0..<2 { let o = makeOpp(stage: .lost); o.actualCloseDate = recentClose; opps.append(o) }
        // 5 outside window (should be ignored)
        for _ in 0..<5 { let o = makeOpp(stage: .won); o.actualCloseDate = oldClose; opps.append(o) }
        vm.allOpportunities = opps
        XCTAssertEqual(vm.closeRate(periodDays: 90) ?? 0, 0.6, accuracy: 0.001)  // 3/5
    }
}
```

- [ ] **Step 2: Run tests — verify 6 new tests fail**

```bash
xcodebuild test -scheme OPS -destination 'platform=iOS Simulator,name=iPhone 15' -only-testing:OPSTests/PipelineViewModelInCourtTests 2>&1 | tail -25
```

Expected: 6 FAIL (`staleLeadsTotalValue`, `oldestStaleDescription`, `closeRate` undefined).

- [ ] **Step 3: Add the computed properties + period method**

Append to `OPS/ViewModels/PipelineViewModel.swift` after the in-court derivations:

```swift
    // MARK: - Stat-card computeds

    var staleLeadsTotalValue: Double {
        allOpportunities
            .filter { !$0.stage.isTerminal && !$0.isDeleted && !$0.isArchived && $0.isStale }
            .reduce(0) { $0 + ($1.estimatedValue ?? 0) }
    }

    /// Summary string for the STALE RISK card sub-line, or nil when no stale leads.
    /// Format: `"12D IN QUOTING"` — oldest stale lead's days-in-stage and stage display name.
    var oldestStaleDescription: String? {
        let stale = allOpportunities
            .filter { !$0.stage.isTerminal && !$0.isDeleted && !$0.isArchived && $0.isStale }
        guard let oldest = stale.max(by: { $0.daysInStage < $1.daysInStage }) else { return nil }
        return "\(oldest.daysInStage)D IN \(oldest.stage.displayName)"
    }

    /// Win rate over the given period. Returns nil if fewer than 5 closes in the window.
    /// Period bounded by `actualCloseDate`. Closed = won OR lost.
    func closeRate(periodDays: Int) -> Double? {
        let cutoff = Calendar.current.date(byAdding: .day, value: -periodDays, to: Date()) ?? Date.distantPast
        let closed = allOpportunities.filter { opp in
            guard !opp.isDeleted else { return false }
            guard let closeDate = opp.actualCloseDate else { return false }
            return closeDate >= cutoff && (opp.stage == .won || opp.stage == .lost)
        }
        guard closed.count >= 5 else { return nil }
        let wonCount = closed.filter { $0.stage == .won }.count
        return Double(wonCount) / Double(closed.count)
    }
```

- [ ] **Step 4: Run tests — verify 6 new tests pass**

```bash
xcodebuild test -scheme OPS -destination 'platform=iOS Simulator,name=iPhone 15' -only-testing:OPSTests/PipelineViewModelInCourtTests 2>&1 | tail -10
```

Expected: All PASS (16 total).

- [ ] **Step 5: Commit**

```bash
git add OPS/ViewModels/PipelineViewModel.swift OPSTests/Pipeline/PipelineViewModelInCourtTests.swift
git commit -m "feat(leads): add stat-card computeds (close rate, stale value, oldest stale)"
```

---

## Task 5: Add `.books` case to `TabName` analytics enum

Reclaims the `pipeline` semantic for the actual Pipeline tab and adds the missing Books case.

**Files:**
- Modify: `OPS/Utilities/AnalyticsManager.swift:649-669`

- [ ] **Step 1: Update the enum**

Replace the `TabName` enum (lines 649-669) with:

```swift
/// Tab names for analytics tracking
enum TabName: String {
    case home = "home"
    case pipeline = "pipeline"
    case books = "books"
    case jobBoard = "job_board"
    case inventory = "inventory"
    case schedule = "schedule"
    case settings = "settings"

    /// Base index (without dynamic tabs like inventory)
    /// Note: Actual tab index may vary based on user permissions
    var index: Int {
        switch self {
        case .home: return 0
        case .pipeline: return 1
        case .books: return 2
        case .jobBoard: return 3
        case .inventory: return 4
        case .schedule: return 5
        case .settings: return 6
        }
    }
}
```

- [ ] **Step 2: Verify the build**

```bash
xcodebuild -scheme OPS -destination 'generic/platform=iOS' build 2>&1 | tail -10
```

Expected: BUILD SUCCEEDED. (Callers in `MainTabView` still emit `.pipeline` for what's currently the Books tab — that's fixed in Phase 3, not now. This task adds the case without breaking the current emission.)

- [ ] **Step 3: Commit**

```bash
git add OPS/Utilities/AnalyticsManager.swift
git commit -m "feat(leads): add TabName.books case for analytics"
```

---

## Task 6: Add `.leads` case to `AppHeader.HeaderType`

**Files:**
- Modify: `OPS/Views/Components/Common/AppHeader.swift:72-80`

- [ ] **Step 1: Read the current enum and title resolution**

```bash
sed -n '72,160p' OPS/Views/Components/Common/AppHeader.swift
```

Identify the `headerType` switch that resolves the page title (around line 132).

- [ ] **Step 2: Add the case**

Inside `enum HeaderType`, after `case books`, insert:

```swift
        case leads
```

Inside the title switch (around line 132 — confirm exact line during step 1), add the case before `default:`:

```swift
        case .leads:
            // Title: "LEADS"
            // matches the LEADS tab in MainTabView
            return "LEADS"
```

(Note: the exact return signature depends on what the switch returns — match the existing pattern for `.books`. If `.books` returns a string literal, do the same. If it returns a tuple or different shape, match that exactly.)

- [ ] **Step 3: Verify the build**

```bash
xcodebuild -scheme OPS -destination 'generic/platform=iOS' build 2>&1 | tail -10
```

Expected: BUILD SUCCEEDED.

- [ ] **Step 4: Commit**

```bash
git add OPS/Views/Components/Common/AppHeader.swift
git commit -m "feat(leads): add .leads case to AppHeader.HeaderType"
```

---

# Phase 2 — New components (independent, no coordination required)

These build the visual surface in isolation. They're not yet wired into the tab bar — they sit as new files that can be previewed individually. Safe to land before Books reconstruction is locked.

## Task 7: `StageStripView` — redesigned

**Files:**
- Create: `OPS/Views/Leads/Components/StageStripView.swift`

- [ ] **Step 1: Create the file**

```swift
//
//  StageStripView.swift
//  OPS
//
//  Horizontal pinned strip of pipeline stages for the LEADS tab.
//  Each chip: stage-color pip + name (Mohave) + count (JetBrains Mono).
//  Active stage gets underline indicator. Vertical hairline separates
//  active stages from terminal (Won/Lost), which are revealed by tapping
//  a CLOSED chip and rendered at 0.6 opacity.
//

import SwiftUI

struct StageStripView: View {
    @Binding var selectedStage: PipelineStage
    @Binding var showClosed: Bool
    let countProvider: (PipelineStage) -> Int

    private let activeStages: [PipelineStage] = [
        .newLead, .qualifying, .quoting, .quoted, .followUp, .negotiation
    ]
    private let terminalStages: [PipelineStage] = [.won, .lost]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
                ForEach(activeStages) { stage in
                    pill(for: stage, terminal: false)
                }
                divider
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    withAnimation(OPSStyle.Animation.standard) {
                        showClosed.toggle()
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text("CLOSED")
                            .font(OPSStyle.Typography.captionBold)
                            .foregroundColor(OPSStyle.Colors.secondaryText)
                        Image(systemName: showClosed ? "chevron.left" : "chevron.right")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(OPSStyle.Colors.secondaryText)
                    }
                    .padding(.horizontal, OPSStyle.Layout.spacing2_5)
                    .frame(minHeight: OPSStyle.Layout.touchTargetMin)
                }
                .buttonStyle(PlainButtonStyle())
                if showClosed {
                    ForEach(terminalStages) { stage in
                        pill(for: stage, terminal: true)
                    }
                }
            }
            .padding(.horizontal, OPSStyle.Layout.spacing3)
        }
        .frame(minHeight: 48)
        .background(OPSStyle.Colors.background)
    }

    @ViewBuilder
    private func pill(for stage: PipelineStage, terminal: Bool) -> some View {
        let isSelected = selectedStage == stage
        let count = countProvider(stage)

        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            withAnimation(OPSStyle.Animation.standard) {
                selectedStage = stage
            }
        } label: {
            VStack(spacing: OPSStyle.Layout.spacing1) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(stage.color)
                        .frame(width: 6, height: 6)
                    Text(stage.displayName)
                        .font(isSelected ? OPSStyle.Typography.captionBold : OPSStyle.Typography.caption)
                        .foregroundColor(
                            isSelected ? OPSStyle.Colors.primaryText : OPSStyle.Colors.secondaryText
                        )
                    if count > 0 {
                        Text("\(count)")
                            .font(OPSStyle.Typography.metadata)
                            .foregroundColor(
                                isSelected ? OPSStyle.Colors.primaryAccent : OPSStyle.Colors.tertiaryText
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
        .accessibilityLabel("\(stage.displayName), \(count) leads")
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    private var divider: some View {
        Rectangle()
            .fill(OPSStyle.Colors.cardBorder)
            .frame(width: OPSStyle.Layout.Border.standard, height: 24)
            .padding(.horizontal, OPSStyle.Layout.spacing2)
    }
}
```

- [ ] **Step 2: Verify the build**

```bash
xcodebuild -scheme OPS -destination 'generic/platform=iOS' build 2>&1 | tail -10
```

Expected: BUILD SUCCEEDED.

- [ ] **Step 3: Commit**

```bash
git add OPS/Views/Leads/Components/StageStripView.swift
git commit -m "feat(leads): add redesigned StageStripView with color pip and CLOSED expander"
```

---

## Task 8: `LeadCardView` — redesigned with swipe actions

**Files:**
- Create: `OPS/Views/Leads/Components/LeadCardView.swift`

- [ ] **Step 1: Create the file**

```swift
//
//  LeadCardView.swift
//  OPS
//
//  Lead card for the LEADS tab. Quiet card body — actions revealed via
//  SwiftUI swipe gestures (leading edge → advance stage; trailing edge →
//  WON / LOST). Long-press opens the LeadActionSheet.
//
//  Layout: 3pt stage-color leading rail, Mohave bold title, JetBrains Mono
//  value, mono days-in-stage, one urgency chip (overdue > stale > untouched).
//

import SwiftUI

struct LeadCardView: View {
    let opportunity: Opportunity
    let canManage: Bool
    let isPendingOfflineError: Bool

    var onTap: () -> Void
    var onAdvance: () -> Void
    var onWon: () -> Void
    var onLost: () -> Void
    var onLongPress: () -> Void

    private var displayTitle: String {
        if let t = opportunity.title, !t.isEmpty { return t }
        if !opportunity.contactName.isEmpty { return opportunity.contactName }
        return "UNNAMED LEAD"
    }

    private var valueText: String? {
        guard let v = opportunity.estimatedValue else { return nil }
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: v))
    }

    private var daysInStageNumber: String { "\(opportunity.daysInStage)" }

    /// Highest-severity urgency marker; nil if none.
    private var urgencyChip: (label: String, color: Color)? {
        let isOverdue = (opportunity.nextFollowUpAt.map { $0 <= Date() }) ?? false
        if isOverdue {
            let days = max(1, daysOverdue)
            return ("\(days)D OVERDUE", OPSStyle.Colors.errorStatus)
        }
        if opportunity.isStale {
            return ("STALE", OPSStyle.Colors.warningStatus)
        }
        if opportunity.stage == .newLead && opportunity.lastActivityAt == nil {
            return ("UNTOUCHED", OPSStyle.Colors.tertiaryText)
        }
        return nil
    }

    private var daysOverdue: Int {
        guard let due = opportunity.nextFollowUpAt else { return 0 }
        let diff = Calendar.current.dateComponents([.day], from: due, to: Date()).day ?? 0
        return max(0, diff)
    }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 0) {
                Rectangle()
                    .fill(opportunity.stage.color)
                    .frame(width: 3)
                VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
                    Text(displayTitle)
                        .font(OPSStyle.Typography.bodyBold)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                        .lineLimit(1)
                        .truncationMode(.tail)

                    HStack(spacing: OPSStyle.Layout.spacing2) {
                        if let valueText {
                            Text(valueText)
                                .font(OPSStyle.Typography.dataValue)
                                .foregroundColor(OPSStyle.Colors.primaryText)
                        }
                        Text("·")
                            .foregroundColor(OPSStyle.Colors.tertiaryText)
                        HStack(spacing: 2) {
                            Text(daysInStageNumber)
                                .font(OPSStyle.Typography.metadata)
                                .foregroundColor(OPSStyle.Colors.secondaryText)
                            Text("D IN STAGE")
                                .font(OPSStyle.Typography.smallCaption)
                                .foregroundColor(OPSStyle.Colors.secondaryText)
                        }
                        if let chip = urgencyChip {
                            Text(chip.label)
                                .font(OPSStyle.Typography.captionBold)
                                .foregroundColor(chip.color)
                        }
                        if isPendingOfflineError {
                            Text("OFFLINE — TRY AGAIN")
                                .font(OPSStyle.Typography.captionBold)
                                .foregroundColor(OPSStyle.Colors.errorStatus)
                        }
                        Spacer()
                    }
                }
                .padding(OPSStyle.Layout.spacing3)
            }
            .frame(maxWidth: .infinity, minHeight: 60, alignment: .leading)
            .background(OPSStyle.Colors.cardBackground)
            .overlay(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius)
                    .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
            )
            .clipShape(RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius))
        }
        .buttonStyle(PlainButtonStyle())
        .onLongPressGesture(minimumDuration: 0.5, perform: {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            onLongPress()
        })
        .accessibilityLabel(accessibilityLabel)
        .swipeActions(edge: .leading, allowsFullSwipe: false) {
            if canManage, !opportunity.stage.isTerminal, let next = opportunity.stage.next {
                Button {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    onAdvance()
                } label: {
                    Label("→ \(next.displayName)", systemImage: "arrow.right")
                }
                .tint(OPSStyle.Colors.primaryAccent)
            }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            if canManage, !opportunity.stage.isTerminal {
                Button {
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    onWon()
                } label: {
                    Label("WON", systemImage: "checkmark")
                }
                .tint(OPSStyle.Colors.successStatus)

                Button(role: .destructive) {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    onLost()
                } label: {
                    Label("LOST", systemImage: "xmark")
                }
            }
        }
    }

    private var accessibilityLabel: String {
        var parts: [String] = [displayTitle, opportunity.stage.displayName]
        if let v = valueText { parts.append(v) }
        if let chip = urgencyChip { parts.append(chip.label) }
        return parts.joined(separator: ", ")
    }
}
```

- [ ] **Step 2: Verify the build**

```bash
xcodebuild -scheme OPS -destination 'generic/platform=iOS' build 2>&1 | tail -10
```

Expected: BUILD SUCCEEDED.

- [ ] **Step 3: Commit**

```bash
git add OPS/Views/Leads/Components/LeadCardView.swift
git commit -m "feat(leads): add redesigned LeadCardView with swipe actions and urgency chip"
```

---

## Task 9: `BallInCourtBar`

**Files:**
- Create: `OPS/Views/Leads/BallInCourtBar.swift`

- [ ] **Step 1: Create the file**

```swift
//
//  BallInCourtBar.swift
//  OPS
//
//  Floating bar above the stage strip showing "ball in your court" leads.
//  Severity-tiered leading rail color (red overdue / amber stale / blue
//  untouched). Tap toggles in-place filter across the carousel. Hidden when
//  count == 0.
//

import SwiftUI

struct BallInCourtBar: View {
    let count: Int
    let buckets: PipelineViewModel.InCourtBuckets
    let totalValue: Double
    let filterActive: Bool
    let isOffline: Bool
    let onToggleFilter: () -> Void

    private var railColor: Color {
        if buckets.overdue > 0 { return OPSStyle.Colors.errorStatus }
        if buckets.stale > 0 { return OPSStyle.Colors.warningStatus }
        return OPSStyle.Colors.primaryAccent
    }

    private var stakeText: String? {
        guard totalValue > 0 else { return nil }
        if totalValue >= 10_000 {
            let thousands = Int((totalValue / 1_000).rounded())
            return "$\(thousands)K STAKE"
        }
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        formatter.maximumFractionDigits = 0
        let s = formatter.string(from: NSNumber(value: totalValue)) ?? "$0"
        return "\(s) STAKE"
    }

    var body: some View {
        if count == 0 {
            EmptyView()
        } else {
            Button(action: {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                onToggleFilter()
            }) {
                HStack(spacing: 0) {
                    Rectangle()
                        .fill(railColor)
                        .frame(width: 3)
                    HStack(spacing: OPSStyle.Layout.spacing2) {
                        if filterActive {
                            Text("FILTER ON · \(count) LEADS")
                                .font(OPSStyle.Typography.captionBold)
                                .foregroundColor(OPSStyle.Colors.primaryText)
                            Spacer()
                            HStack(spacing: 4) {
                                Text("CLEAR")
                                    .font(OPSStyle.Typography.captionBold)
                                    .foregroundColor(OPSStyle.Colors.secondaryText)
                                Image(systemName: "xmark")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundColor(OPSStyle.Colors.secondaryText)
                            }
                        } else {
                            HStack(spacing: 4) {
                                Text("\(count)")
                                    .font(OPSStyle.Typography.dataValue)
                                    .foregroundColor(OPSStyle.Colors.primaryText)
                                Text("IN COURT")
                                    .font(OPSStyle.Typography.captionBold)
                                    .foregroundColor(OPSStyle.Colors.primaryText)
                            }
                            if buckets.overdue > 0 {
                                separatorDot
                                Text("\(buckets.overdue) OVERDUE")
                                    .font(OPSStyle.Typography.captionBold)
                                    .foregroundColor(OPSStyle.Colors.errorStatus)
                            }
                            if buckets.stale > 0 {
                                separatorDot
                                Text("\(buckets.stale) STALE")
                                    .font(OPSStyle.Typography.captionBold)
                                    .foregroundColor(OPSStyle.Colors.warningStatus)
                            }
                            if buckets.untouched > 0 {
                                separatorDot
                                Text("\(buckets.untouched) UNTOUCHED")
                                    .font(OPSStyle.Typography.captionBold)
                                    .foregroundColor(OPSStyle.Colors.tertiaryText)
                            }
                            if let stake = stakeText {
                                separatorDot
                                Text(stake)
                                    .font(OPSStyle.Typography.captionBold)
                                    .foregroundColor(OPSStyle.Colors.secondaryText)
                            }
                            if isOffline {
                                separatorDot
                                Text("OFFLINE")
                                    .font(OPSStyle.Typography.captionBold)
                                    .foregroundColor(OPSStyle.Colors.warningStatus)
                            }
                            Spacer(minLength: 0)
                            Image(systemName: filterActive ? "xmark" : "chevron.right")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(OPSStyle.Colors.tertiaryText)
                        }
                    }
                    .padding(.horizontal, OPSStyle.Layout.spacing3)
                }
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .background(OPSStyle.Colors.cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: OPSStyle.Layout.smallCornerRadius))
            }
            .buttonStyle(PlainButtonStyle())
            .padding(.horizontal, OPSStyle.Layout.spacing3)
            .accessibilityLabel(filterActive
                ? "Filter on, \(count) in-court leads. Tap to clear filter."
                : "\(count) leads in your court. Tap to filter."
            )
        }
    }

    private var separatorDot: some View {
        Text("·").foregroundColor(OPSStyle.Colors.tertiaryText)
    }
}
```

- [ ] **Step 2: Verify the build**

```bash
xcodebuild -scheme OPS -destination 'generic/platform=iOS' build 2>&1 | tail -10
```

Expected: BUILD SUCCEEDED.

- [ ] **Step 3: Commit**

```bash
git add OPS/Views/Leads/BallInCourtBar.swift
git commit -m "feat(leads): add BallInCourtBar with severity tiers and filter toggle"
```

---

## Task 10: `LeadsHeaderCarousel`

Forked from `SmartStatCarousel`'s pattern but with Pipeline-only cards. Five cards in fixed order.

**Files:**
- Create: `OPS/Views/Leads/LeadsHeaderCarousel.swift`

- [ ] **Step 1: Create the file**

```swift
//
//  LeadsHeaderCarousel.swift
//  OPS
//
//  5-card swipeable stat carousel for the LEADS tab.
//  Forked from SmartStatCarousel because Pipeline metrics differ from
//  Books's financial metrics; a future refactor may unify both behind a
//  config-driven base.
//

import SwiftUI

struct LeadsHeaderCarousel: View {
    let weightedForecast: Double
    let weightedForecastDelta: Double?  // nil = no prior period data
    let activeLeadCount: Int
    let activePerStage: [(stage: PipelineStage, count: Int)]
    let closeRate: Double?  // nil = insufficient data
    let closeRateWonCount: Int
    let closeRateLostCount: Int
    let avgVelocityDays: Int?
    let avgVelocityDelta: Int?
    let staleLeadsCount: Int
    let staleLeadsTotalValue: Double
    let oldestStaleDescription: String?

    var onForecastTap: (() -> Void)?
    var onActivePipelineTap: (() -> Void)?
    var onStaleRiskTap: (() -> Void)?

    @State private var selectedCard = 0

    private var visibleCards: [Card] {
        var cards: [Card] = [.weightedForecast, .activePipeline, .closeRate, .velocity]
        if staleLeadsCount > 0 { cards.append(.staleRisk) }
        return cards
    }

    enum Card: Hashable {
        case weightedForecast, activePipeline, closeRate, velocity, staleRisk
    }

    var body: some View {
        VStack(spacing: OPSStyle.Layout.spacing2) {
            TabView(selection: $selectedCard) {
                ForEach(Array(visibleCards.enumerated()), id: \.element) { index, card in
                    cardView(for: card)
                        .padding(.horizontal, OPSStyle.Layout.spacing3)
                        .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .frame(height: 100)
            .animation(OPSStyle.Animation.standard, value: selectedCard)

            // Page indicator dots
            HStack(spacing: 8) {
                ForEach(Array(visibleCards.enumerated()), id: \.element) { index, _ in
                    Circle()
                        .fill(index == selectedCard ? OPSStyle.Colors.primaryAccent : OPSStyle.Colors.tertiaryText)
                        .frame(width: 6, height: 6)
                }
            }
            .accessibilityHidden(true)
        }
        .onChange(of: selectedCard) { _, _ in
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
    }

    @ViewBuilder
    private func cardView(for card: Card) -> some View {
        switch card {
        case .weightedForecast: forecastCard
        case .activePipeline:   activePipelineCard
        case .closeRate:        closeRateCard
        case .velocity:         velocityCard
        case .staleRisk:        staleRiskCard
        }
    }

    // MARK: - Cards

    private var forecastCard: some View {
        Button { onForecastTap?() } label: {
            cardChrome {
                VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing1) {
                    Text("WEIGHTED FORECAST")
                        .font(OPSStyle.Typography.category)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                    Text(formatCurrency(weightedForecast))
                        .font(OPSStyle.Typography.dataValueLg)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                    if let delta = weightedForecastDelta {
                        deltaLine(amount: delta, label: "vs LAST 30D")
                    } else {
                        Text("LAST 30D")
                            .font(OPSStyle.Typography.smallCaption)
                            .foregroundColor(OPSStyle.Colors.tertiaryText)
                    }
                }
            }
        }
        .buttonStyle(PlainButtonStyle())
        .accessibilityLabel("Weighted forecast \(formatCurrency(weightedForecast))")
    }

    private var activePipelineCard: some View {
        Button { onActivePipelineTap?() } label: {
            cardChrome {
                VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing1) {
                    Text("ACTIVE PIPELINE")
                        .font(OPSStyle.Typography.category)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                    HStack(spacing: 6) {
                        Text("\(activeLeadCount)")
                            .font(OPSStyle.Typography.dataValueLg)
                            .foregroundColor(OPSStyle.Colors.primaryText)
                        Text("LEADS")
                            .font(OPSStyle.Typography.captionBold)
                            .foregroundColor(OPSStyle.Colors.secondaryText)
                    }
                    miniStackedBar
                }
            }
        }
        .buttonStyle(PlainButtonStyle())
        .accessibilityLabel("\(activeLeadCount) active leads across pipeline")
    }

    private var miniStackedBar: some View {
        let totalCount = max(activePerStage.reduce(0) { $0 + $1.count }, 1)
        return GeometryReader { geo in
            HStack(spacing: 1) {
                ForEach(activePerStage, id: \.stage) { entry in
                    Rectangle()
                        .fill(entry.stage.color)
                        .frame(width: max(2, geo.size.width * CGFloat(entry.count) / CGFloat(totalCount)))
                }
            }
        }
        .frame(height: 4)
        .clipShape(RoundedRectangle(cornerRadius: 2))
    }

    private var closeRateCard: some View {
        cardChrome {
            VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing1) {
                Text("CLOSE RATE")
                    .font(OPSStyle.Typography.category)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
                if let rate = closeRate {
                    Text("\(Int((rate * 100).rounded()))%")
                        .font(OPSStyle.Typography.dataValueLg)
                        .foregroundColor(closeRateColor(rate))
                    Text("\(closeRateWonCount) WON · \(closeRateLostCount) LOST · LAST 90D")
                        .font(OPSStyle.Typography.smallCaption)
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                } else {
                    Text("—")
                        .font(OPSStyle.Typography.dataValueLg)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                    Text("INSUFFICIENT DATA · LAST 90D")
                        .font(OPSStyle.Typography.smallCaption)
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                }
            }
        }
    }

    private func closeRateColor(_ rate: Double) -> Color {
        if rate >= 0.40 { return OPSStyle.Colors.successStatus }
        if rate >= 0.20 { return OPSStyle.Colors.warningStatus }
        return OPSStyle.Colors.errorStatus
    }

    private var velocityCard: some View {
        cardChrome {
            VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing1) {
                Text("VELOCITY")
                    .font(OPSStyle.Typography.category)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
                if let days = avgVelocityDays {
                    HStack(spacing: 4) {
                        Text("\(days)")
                            .font(OPSStyle.Typography.dataValueLg)
                            .foregroundColor(OPSStyle.Colors.primaryText)
                        Text("D AVG")
                            .font(OPSStyle.Typography.captionBold)
                            .foregroundColor(OPSStyle.Colors.secondaryText)
                    }
                    Text("NEW → WON · LAST 90D")
                        .font(OPSStyle.Typography.smallCaption)
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                    if let delta = avgVelocityDelta, delta != 0 {
                        let isFaster = delta < 0
                        Text("\(isFaster ? "▼" : "▲") \(abs(delta))D vs PRIOR 90D")
                            .font(OPSStyle.Typography.smallCaption)
                            .foregroundColor(isFaster ? OPSStyle.Colors.successStatus : OPSStyle.Colors.errorStatus)
                    }
                } else {
                    Text("—")
                        .font(OPSStyle.Typography.dataValueLg)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                    Text("INSUFFICIENT DATA")
                        .font(OPSStyle.Typography.smallCaption)
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                }
            }
        }
    }

    private var staleRiskCard: some View {
        Button { onStaleRiskTap?() } label: {
            cardChrome(railColor: OPSStyle.Colors.warningStatus) {
                VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing1) {
                    Text("STALE RISK")
                        .font(OPSStyle.Typography.category)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                    HStack(spacing: 4) {
                        Text("\(staleLeadsCount)")
                            .font(OPSStyle.Typography.dataValueLg)
                            .foregroundColor(OPSStyle.Colors.primaryText)
                        Text("LEADS")
                            .font(OPSStyle.Typography.captionBold)
                            .foregroundColor(OPSStyle.Colors.secondaryText)
                        if staleLeadsTotalValue > 0 {
                            Text("·")
                                .foregroundColor(OPSStyle.Colors.tertiaryText)
                            Text(formatCurrency(staleLeadsTotalValue))
                                .font(OPSStyle.Typography.dataValue)
                                .foregroundColor(OPSStyle.Colors.primaryText)
                        }
                    }
                    if let oldest = oldestStaleDescription {
                        Text("OLDEST: \(oldest)")
                            .font(OPSStyle.Typography.smallCaption)
                            .foregroundColor(OPSStyle.Colors.tertiaryText)
                    }
                }
            }
        }
        .buttonStyle(PlainButtonStyle())
    }

    // MARK: - Chrome

    @ViewBuilder
    private func cardChrome<Content: View>(
        railColor: Color? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(spacing: 0) {
            if let rail = railColor {
                Rectangle().fill(rail).frame(width: 3)
            }
            content()
                .padding(OPSStyle.Layout.spacing3)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(height: 88)
        .background(OPSStyle.Colors.cardBackground)
        .overlay(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius)
                .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
        )
        .clipShape(RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius))
    }

    // MARK: - Helpers

    private func formatCurrency(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: value)) ?? "$0"
    }

    @ViewBuilder
    private func deltaLine(amount: Double, label: String) -> some View {
        let isUp = amount > 0
        let isFlat = amount == 0
        HStack(spacing: 4) {
            Text(isFlat ? "—" : (isUp ? "▲" : "▼"))
                .font(OPSStyle.Typography.smallCaption)
            Text("\(formatCurrency(abs(amount))) \(label)")
                .font(OPSStyle.Typography.smallCaption)
        }
        .foregroundColor(
            isFlat ? OPSStyle.Colors.tertiaryText :
            (isUp ? OPSStyle.Colors.successStatus : OPSStyle.Colors.errorStatus)
        )
    }
}
```

- [ ] **Step 2: Verify the build**

```bash
xcodebuild -scheme OPS -destination 'generic/platform=iOS' build 2>&1 | tail -10
```

Expected: BUILD SUCCEEDED.

- [ ] **Step 3: Commit**

```bash
git add OPS/Views/Leads/LeadsHeaderCarousel.swift
git commit -m "feat(leads): add LeadsHeaderCarousel with 5 pipeline stat cards"
```

---

## Task 11: `ForecastBreakdownSheet`

Simple sheet listing active leads sorted by weighted value desc. Used as the tap target for the WEIGHTED FORECAST card.

**Files:**
- Create: `OPS/Views/Leads/Components/ForecastBreakdownSheet.swift`

- [ ] **Step 1: Create the file**

```swift
//
//  ForecastBreakdownSheet.swift
//  OPS
//
//  Bottom sheet that breaks down the weighted forecast by lead, sorted
//  by weighted value descending. Tapping a row pushes LeadDetailView.
//

import SwiftUI

struct ForecastBreakdownSheet: View {
    let opportunities: [Opportunity]
    var onSelect: (Opportunity) -> Void

    @Environment(\.dismiss) private var dismiss

    private var sortedActive: [Opportunity] {
        opportunities
            .filter { !$0.stage.isTerminal && !$0.isDeleted && !$0.isArchived }
            .sorted { $0.weightedValue > $1.weightedValue }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: OPSStyle.Layout.spacing2) {
                    ForEach(sortedActive) { opp in
                        Button { onSelect(opp); dismiss() } label: {
                            HStack(spacing: 0) {
                                Rectangle().fill(opp.stage.color).frame(width: 3)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(displayName(for: opp))
                                        .font(OPSStyle.Typography.bodyBold)
                                        .foregroundColor(OPSStyle.Colors.primaryText)
                                    HStack(spacing: 4) {
                                        Text(opp.stage.displayName)
                                            .font(OPSStyle.Typography.smallCaption)
                                            .foregroundColor(OPSStyle.Colors.secondaryText)
                                        Text("·")
                                            .foregroundColor(OPSStyle.Colors.tertiaryText)
                                        Text("\(opp.stage.winProbability)%")
                                            .font(OPSStyle.Typography.metadata)
                                            .foregroundColor(OPSStyle.Colors.secondaryText)
                                    }
                                }
                                .padding(OPSStyle.Layout.spacing3)
                                Spacer()
                                Text(formatCurrency(opp.weightedValue))
                                    .font(OPSStyle.Typography.dataValue)
                                    .foregroundColor(OPSStyle.Colors.primaryText)
                                    .padding(.trailing, OPSStyle.Layout.spacing3)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(OPSStyle.Colors.cardBackground)
                            .clipShape(RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius))
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
                .padding(OPSStyle.Layout.spacing3)
            }
            .background(OPSStyle.Colors.background)
            .navigationTitle("WEIGHTED FORECAST")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("CLOSE") { dismiss() }
                        .font(OPSStyle.Typography.captionBold)
                }
            }
        }
    }

    private func displayName(for opp: Opportunity) -> String {
        if let t = opp.title, !t.isEmpty { return t }
        if !opp.contactName.isEmpty { return opp.contactName }
        return "UNNAMED LEAD"
    }

    private func formatCurrency(_ value: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "USD"
        f.maximumFractionDigits = 0
        return f.string(from: NSNumber(value: value)) ?? "$0"
    }
}
```

- [ ] **Step 2: Verify the build**

```bash
xcodebuild -scheme OPS -destination 'generic/platform=iOS' build 2>&1 | tail -10
```

Expected: BUILD SUCCEEDED.

- [ ] **Step 3: Commit**

```bash
git add OPS/Views/Leads/Components/ForecastBreakdownSheet.swift
git commit -m "feat(leads): add ForecastBreakdownSheet for weighted-forecast card tap target"
```

---

## Task 12: `LeadListPage`

Per-stage list rendered inside the carousel's `TabView`. Wraps a `LazyVStack` of `LeadCardView`s with appropriate empty states.

**Files:**
- Create: `OPS/Views/Leads/LeadListPage.swift`

- [ ] **Step 1: Create the file**

```swift
//
//  LeadListPage.swift
//  OPS
//
//  Single-stage lead list page rendered inside the LeadsTabView carousel.
//

import SwiftUI

struct LeadListPage: View {
    @ObservedObject var viewModel: PipelineViewModel
    let stage: PipelineStage
    let inCourtFilterActive: Bool
    let canManage: Bool

    var onCardTap: (Opportunity) -> Void
    var onAdvance: (Opportunity) -> Void
    var onWon: (Opportunity) -> Void
    var onLost: (Opportunity) -> Void
    var onLongPress: (Opportunity) -> Void

    @State private var pendingOfflineErrorIds: Set<String> = []

    private var leads: [Opportunity] {
        let stageLeads = viewModel.opportunities(in: stage)
        if !inCourtFilterActive { return stageLeads }
        return stageLeads.filter { viewModel.inCourtOpportunityIds.contains($0.id) }
    }

    var body: some View {
        Group {
            if leads.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: OPSStyle.Layout.spacing2) {
                        ForEach(leads) { lead in
                            LeadCardView(
                                opportunity: lead,
                                canManage: canManage,
                                isPendingOfflineError: pendingOfflineErrorIds.contains(lead.id),
                                onTap: { onCardTap(lead) },
                                onAdvance: { onAdvance(lead) },
                                onWon: { onWon(lead) },
                                onLost: { onLost(lead) },
                                onLongPress: { onLongPress(lead) }
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

    @ViewBuilder
    private var emptyState: some View {
        VStack(spacing: OPSStyle.Layout.spacing3) {
            Spacer()
            Text(emptyCopy)
                .font(OPSStyle.Typography.bodyBold)
                .foregroundColor(OPSStyle.Colors.tertiaryText)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyCopy: String {
        if inCourtFilterActive {
            return "NO IN-COURT LEADS IN \(stage.displayName)"
        }
        switch stage {
        case .won:  return "NO WINS YET — KEEP MOVING"
        case .lost: return "NO LOSSES"
        default:    return "NO LEADS IN \(stage.displayName)"
        }
    }
}
```

- [ ] **Step 2: Verify the build**

```bash
xcodebuild -scheme OPS -destination 'generic/platform=iOS' build 2>&1 | tail -10
```

Expected: BUILD SUCCEEDED.

- [ ] **Step 3: Commit**

```bash
git add OPS/Views/Leads/LeadListPage.swift
git commit -m "feat(leads): add LeadListPage per-stage list inside carousel"
```

---

# Phase 3 — Tab integration (RENDEZVOUS POINT)

**STOP. Before starting Phase 3:**
1. Confirm the parent Books reconstruction spec is approved and locked.
2. Confirm that session's `MainTabView.swift` diff is queued — Books removal of `pipeline` segment routing and any other Books-side index recomputations.
3. Decide who lands the shared `MainTabView.swift` edit. Recommend: this session writes the full `MainTabView.swift` diff (since this work changes more of it), and the Books session rebases on top.

## Task 13: Move Pipeline sheets to `Leads/`

Preparatory cleanup. The seven dependent sheets stay structurally identical, just relocate.

**Files:**
- Move 7 files from `OPS/Views/Books/Pipeline/` → `OPS/Views/Leads/`:
  - `AddLeadSheet.swift`
  - `EditLeadSheet.swift`
  - `LeadDetailView.swift`
  - `LeadActionSheet.swift`
  - `LeadLogActivitySheet.swift`
  - `AddFollowUpSheet.swift`
  - `LostReasonSheet.swift`

- [ ] **Step 1: Move the files using git**

```bash
mkdir -p OPS/Views/Leads
git mv OPS/Views/Books/Pipeline/AddLeadSheet.swift OPS/Views/Leads/AddLeadSheet.swift
git mv OPS/Views/Books/Pipeline/EditLeadSheet.swift OPS/Views/Leads/EditLeadSheet.swift
git mv OPS/Views/Books/Pipeline/LeadDetailView.swift OPS/Views/Leads/LeadDetailView.swift
git mv OPS/Views/Books/Pipeline/LeadActionSheet.swift OPS/Views/Leads/LeadActionSheet.swift
git mv OPS/Views/Books/Pipeline/LeadLogActivitySheet.swift OPS/Views/Leads/LeadLogActivitySheet.swift
git mv OPS/Views/Books/Pipeline/AddFollowUpSheet.swift OPS/Views/Leads/AddFollowUpSheet.swift
git mv OPS/Views/Books/Pipeline/LostReasonSheet.swift OPS/Views/Leads/LostReasonSheet.swift
```

- [ ] **Step 2: Verify the build (Xcode project file should auto-pick up the new locations if the group has folder-reference behavior; if not, you'll need to fix the project file)**

```bash
xcodebuild -scheme OPS -destination 'generic/platform=iOS' build 2>&1 | tail -20
```

Expected: BUILD SUCCEEDED. If it fails with "file not found," open `OPS.xcodeproj` in Xcode, manually re-add the moved files to the `Leads/` group, and retry the build before committing.

- [ ] **Step 3: Commit**

```bash
git add -A OPS/Views/
git commit -m "refactor(leads): move pipeline sheets from Books/Pipeline to Leads/"
```

---

## Task 14: Delete the old `PipelineSectionView`, `StageStripView`, and `LeadCardView`

The new versions in `Leads/Components/` supersede them. The old `PipelineSectionView` was only consumed by `BooksTabView.contentForSegment` — the parent Books session will have removed that reference by this point.

**Files:**
- Delete: `OPS/Views/Books/Pipeline/PipelineSectionView.swift`
- Delete: `OPS/Views/Books/Pipeline/StageStripView.swift`
- Delete: `OPS/Views/Books/Pipeline/LeadCardView.swift`

- [ ] **Step 1: Confirm the parent Books work has removed references to `PipelineSectionView`**

```bash
grep -rn "PipelineSectionView\b" OPS/Views 2>&1 | grep -v '/Leads/'
```

Expected: no output (or only references inside `OPS/Views/Leads/` if any). If `BooksTabView.swift` still references it, the Books reconstruction is incomplete — STOP and resolve before proceeding.

- [ ] **Step 2: Delete the files**

```bash
git rm OPS/Views/Books/Pipeline/PipelineSectionView.swift
git rm OPS/Views/Books/Pipeline/StageStripView.swift
git rm OPS/Views/Books/Pipeline/LeadCardView.swift
# Remove the now-empty parent directory
rmdir OPS/Views/Books/Pipeline 2>/dev/null || true
```

- [ ] **Step 3: Verify the build**

```bash
xcodebuild -scheme OPS -destination 'generic/platform=iOS' build 2>&1 | tail -10
```

Expected: BUILD SUCCEEDED.

- [ ] **Step 4: Commit the deletion**

```bash
git add -A
git commit -m "refactor(leads): delete legacy PipelineSectionView, StageStripView, LeadCardView in Books/Pipeline"
```

- [ ] **Step 5: Rename-back from P1-1 workaround**

P1-1 had to rename two new structs to avoid filename/struct collisions with the legacy files we just deleted. Now that the legacy files are gone, restore the canonical names:

```bash
# Rename file basenames
git mv OPS/Views/Leads/Components/LeadStageStrip.swift OPS/Views/Leads/Components/StageStripView.swift
git mv OPS/Views/Leads/Components/LeadCard.swift OPS/Views/Leads/Components/LeadCardView.swift
```

Then update the struct names + headers + the consumer call site:
- `OPS/Views/Leads/Components/StageStripView.swift`: change `struct LeadStageStrip` → `struct StageStripView`. Remove the temporary-name header comment.
- `OPS/Views/Leads/Components/LeadCardView.swift`: change `struct LeadCard` → `struct LeadCardView`. Remove the temporary-name header comment.
- `OPS/Views/Leads/LeadListPage.swift`: line 38 (per P1-1 report) — change `LeadCard(...)` → `LeadCardView(...)`.
- Any other call sites — `grep -rn "LeadStageStrip\b\|LeadCard\b" OPS --include='*.swift'` should return only the type definitions and the `LeadListPage` call site after this update.

Verify build, then commit:

```bash
xcodebuild -scheme OPS -destination 'generic/platform=iOS' build 2>&1 | tail -10
git add -A
git commit -m "refactor(leads): restore canonical names (StageStripView, LeadCardView) after legacy deletion"
```

---

## Task 15: `LeadsTabView` — root view

Composes the surface: header → carousel → bar → strip → paged list.

**Files:**
- Create: `OPS/Views/Leads/LeadsTabView.swift`

- [ ] **Step 1: Create the file**

```swift
//
//  LeadsTabView.swift
//  OPS
//
//  Root view for the LEADS top-level tab. Composes:
//    AppHeader(.leads)
//    LeadsHeaderCarousel  (collapses on scroll)
//    BallInCourtBar       (hidden when count == 0)
//    StageStripView       (sticky)
//    TabView(selection:)  (paged per-stage lists)
//

import SwiftUI

private struct HeaderBottomKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

struct LeadsTabView: View {
    @StateObject private var viewModel = PipelineViewModel()
    @EnvironmentObject private var dataController: DataController
    @EnvironmentObject private var permissionStore: PermissionStore

    @State private var headerCollapsed = false
    @State private var inCourtFilterActive = false
    @State private var showClosedStages = false
    @State private var detailDestination: Opportunity?
    @State private var actionSheetOpportunity: Opportunity?
    @State private var lostReasonOpportunity: Opportunity?
    @State private var showForecastBreakdown = false

    private var canManage: Bool { permissionStore.can("pipeline.manage") }
    private var isOffline: Bool { !dataController.isConnected }

    private var activePerStage: [(stage: PipelineStage, count: Int)] {
        let active: [PipelineStage] = [.newLead, .qualifying, .quoting, .quoted, .followUp, .negotiation]
        return active.map { ($0, viewModel.count(in: $0)) }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                AppHeader(headerType: .leads)
                    .padding(.bottom, 8)

                if headerCollapsed {
                    StageStripView(
                        selectedStage: $viewModel.selectedStage,
                        showClosed: $showClosedStages,
                        countProvider: { viewModel.count(in: $0) }
                    )
                    .background(OPSStyle.Colors.background)
                    .transition(.opacity)
                }

                ScrollView {
                    VStack(spacing: 0) {
                        LeadsHeaderCarousel(
                            weightedForecast: viewModel.weightedForecastValue,
                            weightedForecastDelta: nil,  // v1: no period comparison (requires snapshot history)
                            activeLeadCount: viewModel.activeLeadCount,
                            activePerStage: activePerStage,
                            closeRate: viewModel.closeRate(periodDays: 90),
                            closeRateWonCount: viewModel.count(in: .won),
                            closeRateLostCount: viewModel.count(in: .lost),
                            avgVelocityDays: nil,  // v1: no velocity computation (requires StageTransition aggregation)
                            avgVelocityDelta: nil,
                            staleLeadsCount: viewModel.staleLeadsCount,
                            staleLeadsTotalValue: viewModel.staleLeadsTotalValue,
                            oldestStaleDescription: viewModel.oldestStaleDescription,
                            onForecastTap: { showForecastBreakdown = true },
                            onActivePipelineTap: {
                                if let largest = activePerStage.max(by: { $0.count < $1.count })?.stage {
                                    withAnimation(OPSStyle.Animation.standard) {
                                        viewModel.selectedStage = largest
                                    }
                                }
                            },
                            onStaleRiskTap: {
                                withAnimation(OPSStyle.Animation.standard) {
                                    inCourtFilterActive = true
                                }
                            }
                        )
                        .padding(.bottom, OPSStyle.Layout.spacing3)
                        .background(
                            GeometryReader { geo in
                                Color.clear.preference(
                                    key: HeaderBottomKey.self,
                                    value: geo.frame(in: .named("scroll")).maxY
                                )
                            }
                        )

                        BallInCourtBar(
                            count: viewModel.inCourtCount,
                            buckets: viewModel.inCourtBuckets,
                            totalValue: viewModel.inCourtTotalValue,
                            filterActive: inCourtFilterActive,
                            isOffline: isOffline,
                            onToggleFilter: {
                                withAnimation(OPSStyle.Animation.standard) {
                                    inCourtFilterActive.toggle()
                                }
                            }
                        )
                        .padding(.bottom, OPSStyle.Layout.spacing2)

                        if !headerCollapsed {
                            StageStripView(
                                selectedStage: $viewModel.selectedStage,
                                showClosed: $showClosedStages,
                                countProvider: { viewModel.count(in: $0) }
                            )
                        }

                        carouselContent
                            .frame(minHeight: 400)
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
                        Task { try? await viewModel.moveToStage(opportunityId: lead.id, to: stage, userId: dataController.currentUser?.id) }
                    },
                    onEdit:        { detailDestination = lead },
                    onLogActivity: { detailDestination = lead },
                    onAddFollowUp: { detailDestination = lead },
                    onOpenDetail:  { detailDestination = lead },
                    onArchive:     { Task { try? await viewModel.archive(opportunityId: lead.id) } },
                    onDelete:      { Task { try? await viewModel.softDelete(opportunityId: lead.id) } }
                )
            }
            .sheet(item: $lostReasonOpportunity) { lead in
                LostReasonSheet(opportunityTitle: lead.title ?? lead.contactName) { reason, notes in
                    Task { try? await viewModel.markLost(opportunityId: lead.id, reason: reason, notes: notes, userId: dataController.currentUser?.id) }
                }
            }
            .sheet(isPresented: $showForecastBreakdown) {
                ForecastBreakdownSheet(opportunities: viewModel.allOpportunities) { opp in
                    detailDestination = opp
                }
            }
        }
        .trackScreen("Leads")
        .task {
            if let companyId = dataController.currentUser?.companyId {
                viewModel.setup(companyId: companyId, currentUserId: dataController.currentUser?.id)
                await viewModel.loadData()
            }
        }
        .onAppear {
            // Filter state is never persisted across tab visits.
            inCourtFilterActive = false
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("LeadCreatedSuccess"))) { _ in
            Task { await viewModel.loadData() }
        }
    }

    @ViewBuilder
    private var carouselContent: some View {
        let pages = pagesToRender
        TabView(selection: $viewModel.selectedStage) {
            ForEach(pages, id: \.self) { stage in
                LeadListPage(
                    viewModel: viewModel,
                    stage: stage,
                    inCourtFilterActive: inCourtFilterActive,
                    canManage: canManage,
                    onCardTap: { detailDestination = $0 },
                    onAdvance: { lead in
                        guard let next = lead.stage.next else { return }
                        Task { try? await viewModel.moveToStage(opportunityId: lead.id, to: next, userId: dataController.currentUser?.id) }
                    },
                    onWon:  { lead in
                        Task { try? await viewModel.markWon(opportunityId: lead.id, actualValue: lead.estimatedValue, projectId: nil, userId: dataController.currentUser?.id) }
                    },
                    onLost: { lead in lostReasonOpportunity = lead },
                    onLongPress: { lead in actionSheetOpportunity = lead }
                )
                .tag(stage)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .animation(OPSStyle.Animation.standard, value: viewModel.selectedStage)
    }

    private var pagesToRender: [PipelineStage] {
        let active: [PipelineStage] = [.newLead, .qualifying, .quoting, .quoted, .followUp, .negotiation]
        if showClosedStages {
            return active + [.won, .lost]
        }
        return active
    }
}
```

- [ ] **Step 2: Verify the build**

```bash
xcodebuild -scheme OPS -destination 'generic/platform=iOS' build 2>&1 | tail -10
```

Expected: BUILD SUCCEEDED.

- [ ] **Step 3: Commit**

```bash
git add OPS/Views/Leads/LeadsTabView.swift
git commit -m "feat(leads): add LeadsTabView root composing header, bar, strip, and carousel"
```

---

## Task 16: Modify `MainTabView` — add LEADS tab and rename legacy vars

This is the most surgical change. Coordinates with parent Books work.

**Files:**
- Modify: `OPS/Views/MainTabView.swift` (multiple sections)

- [ ] **Step 1: Read the current state to confirm line numbers**

```bash
grep -n "pipelineTabIndex\|isPipelineTab\|hasBooksAccess\|booksAutoSkipDestination" OPS/Views/MainTabView.swift
```

Confirm the lines match the spec's references. If line numbers have shifted, adjust the edits below accordingly.

- [ ] **Step 2: Add `hasLeadsAccess` and feature-flag check**

In `MainTabView.swift`, near `hasCatalogAccess` (line ~54), add:

```swift
    private var hasLeadsAccess: Bool {
        permissionStore.can("pipeline.view") && permissionStore.isFeatureEnabled("pipeline")
    }
```

In `hasBooksAccess` (line ~141), **remove** the `pipeline.view` disjunct so Books no longer gates on it:

```swift
    private var hasBooksAccess: Bool {
        permissionStore.can("finances.view")
            || permissionStore.can("estimates.view")
            || permissionStore.can("expenses.view")
    }
```

- [ ] **Step 3: Rename legacy `pipelineTabIndex` / `isPipelineTab`**

In `MainTabView.swift`:
- Rename `pipelineTabIndex` → `booksTabIndex` (currently at line ~177).
- Rename `isPipelineTab` → `isBooksTab` (currently at line ~234).
- Update all internal references (line ~659, ~677, etc. where `openExpensesObserver` and `openInvoicesObserver` use `pipelineTabIndex`).

Use a single multi-replace for clarity. Verify with grep:

```bash
grep -n "pipelineTabIndex\|isPipelineTab" OPS/Views/MainTabView.swift
```

Expected after rename: only matches inside comments referencing the rename, if any. The variable references should all be gone.

- [ ] **Step 4: Add `leadsTabIndex` and adjust downstream indices**

Replace the index-computation block (lines ~177-194) with:

```swift
    // Computed tab indices that adapt based on visible tabs (LEADS + BOOKS + catalog).
    private var leadsTabIndex: Int? { hasLeadsAccess ? 1 : nil }
    private var booksTabIndex: Int? {
        guard hasBooksAccess else { return nil }
        return hasLeadsAccess ? 2 : 1
    }
    private var jobBoardTabIndex: Int {
        var idx = 1
        if hasLeadsAccess { idx += 1 }
        if hasBooksAccess { idx += 1 }
        return idx
    }
    private var catalogTabIndex: Int? {
        guard hasCatalogAccess else { return nil }
        return jobBoardTabIndex + 1
    }
    private var scheduleTabIndex: Int {
        var idx = jobBoardTabIndex + 1
        if hasCatalogAccess { idx += 1 }
        return idx
    }
    private var settingsTabIndex: Int {
        return scheduleTabIndex + 1
    }
```

- [ ] **Step 5: Replace `isBooksTab` / add `isLeadsTab`**

Replace the `isPipelineTab` computed (now `isBooksTab` from Step 3) and add `isLeadsTab`:

```swift
    private var isBooksTab: Bool {
        if let idx = booksTabIndex { return selectedTab == idx }
        return false
    }
    private var isLeadsTab: Bool {
        if let idx = leadsTabIndex { return selectedTab == idx }
        return false
    }
```

- [ ] **Step 6: Add the LEADS tab to the `tabs` array**

In the `tabs` computed property (line ~197), insert the leads tab after Home and before BOOKS:

```swift
    private var tabs: [TabItem] {
        var baseTabs: [TabItem] = [
            TabItem(iconName: "house.fill", wizardStepId: "welcome_home")
        ]
        if hasLeadsAccess {
            baseTabs.append(TabItem(
                iconName: "point.3.connected.trianglepath.dotted",
                wizardStepId: "welcome_leads"
            ))
        }
        if hasBooksAccess {
            baseTabs.append(TabItem(
                iconName: "chart.line.uptrend.xyaxis",
                wizardStepId: "welcome_books"
            ))
        }
        baseTabs.append(TabItem(iconName: "briefcase.fill", wizardStepId: "welcome_job_board"))
        if hasCatalogAccess {
            baseTabs.append(TabItem(iconName: "square.stack.3d.up.fill", wizardStepId: "welcome_catalog"))
        }
        baseTabs.append(contentsOf: [
            TabItem(iconName: "calendar", wizardStepId: "welcome_schedule"),
            TabItem(iconName: "gearshape.fill", wizardStepId: "welcome_settings")
        ])
        return baseTabs
    }
```

- [ ] **Step 7: Route the new tab in the content switch**

In the body's content switch (line ~293), insert the LEADS case between Home and Books:

```swift
                if selectedTab == 0 {
                    HomeView()
                } else if selectedTab == leadsTabIndex {
                    LeadsTabView()
                } else if selectedTab == booksTabIndex {
                    if let destination = booksAutoSkipDestination {
                        destination
                    } else {
                        BooksTabView()
                    }
                } else if selectedTab == jobBoardTabIndex {
                    JobBoardView()
                } else if selectedTab == catalogTabIndex {
                    CatalogView()
                } else if selectedTab == scheduleTabIndex {
                    ScheduleView()
                } else if selectedTab == settingsTabIndex {
                    SettingsView()
                } else {
                    HomeView()
                }
```

- [ ] **Step 8: Update tab analytics**

In `onChange(of: selectedTab)` (line ~740), update the `tabName` resolver:

```swift
        .onChange(of: selectedTab) { oldValue, newValue in
            previousTab = oldValue
            let tabName: TabName = {
                if newValue == 0 { return .home }
                if newValue == leadsTabIndex { return .pipeline }
                if newValue == booksTabIndex { return .books }
                if newValue == jobBoardTabIndex { return .jobBoard }
                if newValue == scheduleTabIndex { return .schedule }
                if newValue == settingsTabIndex { return .settings }
                if let cat = catalogTabIndex, newValue == cat { return .inventory }
                return .home
            }()
            AnalyticsManager.shared.trackTabSelected(tabName: tabName)
            AnalyticsService.shared.track(
                eventType: .action,
                eventName: "tab_selected",
                properties: ["tab_name": tabName.rawValue, "tab_index": tabName.index]
            )
        }
```

- [ ] **Step 9: Update `WizardCurrentTabChanged` and `WizardNavigateToTarget` handlers**

In the second `onChange(of: selectedTab)` (line ~925), update the wizard tabName resolver to include leads:

```swift
            let tabName: String
            switch newTab {
            case 0: tabName = "Home"
            case jobBoardTabIndex: tabName = "JobBoard"
            case scheduleTabIndex: tabName = "Schedule"
            case settingsTabIndex: tabName = "Settings"
            default:
                if let cat = catalogTabIndex, newTab == cat { tabName = "Catalog" }
                else if let leads = leadsTabIndex, newTab == leads { tabName = "Pipeline" }
                else if let books = booksTabIndex, newTab == books { tabName = "Books" }
                else { tabName = "Unknown" }
            }
```

In `WizardNavigateToTarget` (line ~822), update the "Pipeline" case to target leads:

```swift
            case "Pipeline":
                if let idx = leadsTabIndex {
                    withAnimation { selectedTab = idx }
                }
```

(The "Books" case, if it exists or is added, should target `booksTabIndex`. The parent Books session may also add a "Books" case.)

- [ ] **Step 10: Update expense / invoice deep-link observers**

In `openExpensesObserver` (line ~657) and `openInvoicesObserver` (line ~675), change the routing:

```swift
        .onReceive(openExpensesObserver) { _ in
            print("[PUSH_NAVIGATION] Opening expenses")
            guard hasBooksAccess, let idx = booksTabIndex else {
                print("[PUSH_NAVIGATION] No books access — expense deep link suppressed")
                return
            }
            withAnimation(OPSStyle.Animation.fast) {
                selectedTab = idx
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                NotificationCenter.default.post(
                    name: Notification.Name("BooksSelectSegment"),
                    object: nil,
                    userInfo: ["segment": BooksSection.expenses.rawValue]
                )
            }
        }

        .onReceive(openInvoicesObserver) { _ in
            print("[PUSH_NAVIGATION] Opening invoices")
            guard hasBooksAccess, let idx = booksTabIndex else { return }
            withAnimation(OPSStyle.Animation.fast) {
                selectedTab = idx
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                NotificationCenter.default.post(
                    name: Notification.Name("BooksSelectSegment"),
                    object: nil,
                    userInfo: ["segment": BooksSection.invoices.rawValue]
                )
            }
        }
```

- [ ] **Step 11: Update `FloatingActionMenu` invocation**

Find the `FloatingActionMenu(...)` call (line ~383) and add `isLeadsTab`:

```swift
            FloatingActionMenu(
                currentTab: selectedTab,
                hasCatalogAccess: hasCatalogAccess,
                isScheduleTab: selectedTab == scheduleTabIndex,
                isCatalogTab: catalogTabIndex != nil && selectedTab == catalogTabIndex,
                isLeadsTab: isLeadsTab
            )
```

- [ ] **Step 12: Verify the build**

```bash
xcodebuild -scheme OPS -destination 'generic/platform=iOS' build 2>&1 | tail -20
```

Expected: BUILD SUCCEEDED. Any errors here are likely caused by Books-session changes not yet merged in or vice versa — resolve via coordination before committing.

- [ ] **Step 13: Commit**

```bash
git add OPS/Views/MainTabView.swift
git commit -m "feat(leads): add LEADS tab to MainTabView, rename legacy pipeline indices, fix analytics"
```

---

## Task 17: Modify `FloatingActionMenu` — add `isLeadsTab` param

Plumbs the new flag through so Add Lead surfaces at the top of MONEY when on LEADS.

**Files:**
- Modify: `OPS/Views/Components/FloatingActionMenu.swift`

- [ ] **Step 1: Read the current signature and MONEY group**

```bash
grep -n "var isScheduleTab\|var isCatalogTab\|isLeadsTab\|booksSelectedSegmentRaw\|Add Lead" OPS/Views/Components/FloatingActionMenu.swift
```

- [ ] **Step 2: Add the parameter**

In the struct declaration (around line 136), add:

```swift
    var isLeadsTab: Bool = false
```

- [ ] **Step 3: Update the MONEY group ordering logic**

Around line 239 (the `switch booksSelectedSegmentRaw` block) and line 345-360 (the pipeline money items block), update so that when `isLeadsTab == true`, `Add Lead` is the first item rendered regardless of `booksSelectedSegmentRaw`. Pseudocode:

```swift
        // When on LEADS tab, the universal grouped menu surfaces Add Lead first
        // in the MONEY group. When on BOOKS or another tab, fall back to the
        // existing books-segment-driven ordering.
        if isLeadsTab && permissionStore.isFeatureEnabled("pipeline") {
            // Insert Add Lead at top of MONEY group
            items.append(FABMenuItem(
                id: "addLead",
                icon: "plus.circle",
                label: "Add Lead",
                permission: "pipeline.manage",
                disabledInTutorial: false,
                action: { showingAddLead = true }
            ))
        }
        // ... existing MONEY items follow (Add Estimate, Add Invoice, Record Payment, etc.)
```

(Exact insertion point depends on how the existing menu code is organized; preserve the existing items and just bump Add Lead to the top when `isLeadsTab` is true. The previous behavior where `booksSelectedSegmentRaw == "PIPELINE"` decided ordering can stay as a fallback — it still applies when the user is on the BOOKS tab and toggles segments.)

- [ ] **Step 4: Verify the build**

```bash
xcodebuild -scheme OPS -destination 'generic/platform=iOS' build 2>&1 | tail -10
```

Expected: BUILD SUCCEEDED.

- [ ] **Step 5: Commit**

```bash
git add OPS/Views/Components/FloatingActionMenu.swift
git commit -m "feat(leads): plumb isLeadsTab through FloatingActionMenu, surface Add Lead first"
```

---

## Task 18: End-to-end manual verification

Required before merging. The build passes — but the new tab needs visual + interaction validation.

- [ ] **Step 1: Build and install on a physical device**

```bash
xcodebuild -scheme OPS -destination 'generic/platform=iOS' build 2>&1 | tail -5
```

Then deploy via Xcode to a paired iPhone (`Cmd-R` in the IDE, or use `xcrun devicectl device install`).

- [ ] **Step 2: Verification checklist**

For an admin user with `pipeline.view`:
- [ ] LEADS tab appears between Home and Job Board in the tab bar.
- [ ] Icon is the three-connected-points symbol.
- [ ] Tapping the tab shows AppHeader "LEADS", carousel of 5 stat cards (or 4 if no stale leads), ball-in-court bar (or hidden if 0), stage strip with color pips, then the active stage's lead list.
- [ ] Swiping the carousel horizontally cycles through the 6 active stages with smooth animation.
- [ ] Tapping a stage chip animates the carousel to that page.
- [ ] Tapping CLOSED reveals Won/Lost chips and pages.
- [ ] Tapping the ball-in-court bar toggles in-place filter; clearing returns to full view.
- [ ] Swipe-left on a lead card reveals ADVANCE; swipe-right reveals WON / LOST.
- [ ] Long-press on a lead card opens the LeadActionSheet.
- [ ] Tapping a lead card pushes LeadDetailView.
- [ ] FAB tap opens the universal menu with Add Lead at the top of MONEY group.

For a user with NO `pipeline.view`:
- [ ] LEADS tab does not appear.
- [ ] Books / Job Board / Schedule / Settings tabs are at the expected positions.
- [ ] Tab analytics emits `pipeline` when LEADS is selected (admin); emits `books` when Books is selected.

Offline:
- [ ] Cached leads still render.
- [ ] Attempting to advance a lead triggers `OFFLINE — TRY AGAIN` chip on the card; revert is visible.

- [ ] **Step 3: Capture any visual issues**

If the visual fidelity drifts from the spec (e.g., layout cramped, colors off, gestures conflicting), file targeted follow-up tasks or fix inline before merge. Do NOT merge with known visual defects per OPS perfection standard.

---

# Phase 4 — Bible update

## Task 19: Update `ops-software-bible/09_FINANCIAL_SYSTEM.md`

**Files:**
- Modify: `ops-software-bible/09_FINANCIAL_SYSTEM.md` (multiple sections)

- [ ] **Step 1: Update § 60-200 (Pipeline / CRM System)**

Replace the iOS-implementation-related paragraphs with text reflecting:
- LEADS is a standalone top-level tab on iOS (was a Books segment).
- iOS view layer lives under `OPS/Views/Leads/`.
- Stage colors are now mapped on iOS via `PipelineStage+Color.swift` extension.
- Stale thresholds are per-stage in iOS (`PipelineStage.staleThresholdDays`); bible's "7 days default" line needs updating to reflect this is configurable per stage in code (and could be moved to `pipeline_stage_configs`).

- [ ] **Step 2: Update § 1151-1158 (PipelineViewModel)**

Replace the stale subsection with the actual VM surface:

```markdown
#### PipelineViewModel

Manages the iOS pipeline opportunity list and derives stat-card and ball-in-court numerics for the LEADS tab.

- **Published state**: `allOpportunities`, `selectedStage`, `currentUserId`, `isLoading`, `loadError`
- **Stage-scoped reads**: `opportunities(in:)`, `count(in:)`
- **Pipeline-wide computeds**: `activeLeadCount`, `weightedForecastValue`, `staleLeadsCount`, `staleLeadsTotalValue`, `oldestStaleDescription`, `nextFollowUpDue`, `isPipelineEmpty`
- **Period-aware computeds**: `closeRate(periodDays:)` — returns nil when fewer than 5 closes in window
- **Ball-in-court**: `inCourtCount`, `inCourtBuckets` (overdue / stale / untouched), `inCourtTotalValue`, `inCourtOpportunityIds`
- **Operations**: `loadData()`, `moveToStage(opportunityId:to:userId:)`, `markWon(opportunityId:actualValue:projectId:userId:)`, `markLost(opportunityId:reason:notes:userId:)`, `addLead(_:)`, `archive(_:)`, `softDelete(_:)`
- **Repository**: `OpportunityRepository` — no offline queueing; mutations fail with a network error when offline.
```

- [ ] **Step 3: Add a new § iOS Leads Views subsection**

After the EstimatesViews subsection, insert:

```markdown
#### Leads Views (10 files)

**Location**: `OPS/OPS/Views/Leads/`

| File | Purpose |
|---|---|
| `LeadsTabView.swift` | Root view of the LEADS top-level tab. Composes AppHeader, swipeable stat carousel, ball-in-court bar, stage strip, and a TabView of per-stage lead pages. Owns filter state and CLOSED-stages expander state. |
| `LeadsHeaderCarousel.swift` | 5-card swipeable stat carousel: WEIGHTED FORECAST / ACTIVE PIPELINE (with mini stacked bar by stage color) / CLOSE RATE / VELOCITY / STALE RISK. Cards drop out when their data isn't available (stale-risk hides at 0 stale leads; close-rate shows "INSUFFICIENT DATA" below 5 closes). |
| `BallInCourtBar.swift` | Severity-tiered floating bar above the stage strip. Rail color reflects highest-severity bucket present (red overdue / amber stale / blue untouched). Tap toggles in-place filter across the carousel. Hidden when count is 0. |
| `LeadListPage.swift` | Per-stage lead list rendered inside the carousel's TabView. Filters through the in-court predicate when filter is active. |
| `Components/StageStripView.swift` | Horizontal stage navigator with stage-color pips, mono counts, underline selection indicator, and a CLOSED chip that expands to reveal Won/Lost pages. |
| `Components/LeadCardView.swift` | Quiet card with stage-color leading rail, mono value, days-in-stage, single urgency chip (overdue > stale > untouched). Swipe-leading: advance. Swipe-trailing: WON / LOST. Long-press: action sheet. |
| `Components/ForecastBreakdownSheet.swift` | Bottom sheet listing active leads sorted by weighted value desc. Opened from the forecast card. |
| `AddLeadSheet.swift` / `EditLeadSheet.swift` / `LeadDetailView.swift` / `LeadActionSheet.swift` / `LeadLogActivitySheet.swift` / `AddFollowUpSheet.swift` / `LostReasonSheet.swift` | Pre-existing supporting sheets, relocated from `Books/Pipeline/`. Behavior unchanged. |
```

- [ ] **Step 4: Update § 1435 (Tab visibility)**

Replace:

> Tab is visible when the operator has ANY of `pipeline.view` / `finances.view` / `estimates.view` / `expenses.view`.

with:

> Two top-level tabs share this section's data:
> - **LEADS** (Pipeline) — visible when the operator has `pipeline.view` AND the `pipeline` feature flag is enabled at the company level.
> - **BOOKS** (Estimates / Invoices / Expenses) — visible when the operator has ANY of `finances.view` / `estimates.view` / `expenses.view`. Pipeline no longer factors into Books visibility.

- [ ] **Step 5: Note `archivedAt` in the Opportunity entity (§ 85-132)**

Append to the entity description:

```typescript
  archivedAt: Date | null;       // Set when archived; soft-archive separate from soft-delete
```

(iOS: `Opportunity.archivedAt: Date?` + `var isArchived: Bool` computed.)

- [ ] **Step 6: Commit**

```bash
git add ops-software-bible/09_FINANCIAL_SYSTEM.md
git commit -m "docs(bible): update Pipeline section for standalone LEADS tab and iOS view layer"
```

---

## Final verification

- [ ] All 19 tasks committed
- [ ] No new build warnings
- [ ] Test suite passes (16 new tests + existing PipelineViewModelTests)
- [ ] Manual device verification checklist complete
- [ ] Bible reflects new IA
- [ ] No references to `pipelineTabIndex` / `isPipelineTab` legacy names remain in code (verify with `grep -rn`)

---

## Self-review notes (plan-author)

**Spec coverage:** Every locked decision in spec §3 maps to a task. Layout in §5 maps to Tasks 7-12 + 15. Ball-in-court bar §6.3 maps to Tasks 3 + 9 + 15. Stat carousel §6.2 maps to Tasks 4 + 10 + 15. FAB §6.8 maps to Task 17. Permission gating §7 maps to Task 16 step 2. Drift catalog §16 corrections are reflected in the actual code (no `pipeline.create`, no QUEUED chip, real token names, feature-flag layer).

**Placeholders:** None. Every step includes complete code or exact commands.

**Type consistency:** `currentUserId` is `String?`. `InCourtBuckets` is a nested struct. `closeRate(periodDays:)` returns `Double?`. `weightedForecast`/`weightedForecastDelta` on `LeadsHeaderCarousel` are `Double` and `Double?`. Naming verified across Tasks 2, 3, 4, 10, 15.

**Out-of-band notes:**
- Velocity card shows `—` in v1; computing actual velocity requires aggregating `StageTransition` rows by `transitionedAt` and `durationInStage`. Deferred to future work — noted in spec §17.
- Weighted-forecast delta needs a snapshot history (e.g., a `pipeline_snapshots` table). Also deferred. Card renders without the delta line in v1.
- `LeadActionSheet`, `LostReasonSheet`, etc. constructors in Task 15 assume the existing API surface from `Books/Pipeline/`. If parameter names changed during the move (Task 13), reconcile during build verification in step 12.

**Frequent commits:** 19 commits, one per logical unit. Tasks 15 and 16 are the largest and least-easily-reverted; recommend running build verification between them.

---

## Resumption checklist (when Books Phase 2 has landed)

Before un-blocking this plan and starting execution, complete the following:

- [ ] **Verify Books Phase 2 chunks 2C-2G are merged.** Look for:
  - `PipelineStage` is a struct (not an enum) — search `OPS/DataModels/Enums/PipelineStage.swift` or wherever Phase 2 relocated it.
  - `PipelineStageRepository` (or equivalent) exists for loading per-company stages.
  - `Opportunity` model has AI-related fields (from chunk 2D).
  - `Opportunity` model has `latitude`, `longitude`, image-url fields (from chunk 2E).
  - Contact-import-to-leads flow exists (from chunk 2G).
- [ ] **Re-run the spec verification pass** (spec § 16). Most drift items invalidated by Phase 2 — rewrite as needed.
- [ ] **Rewrite Task 1.** `PipelineStage+Color.swift` extension is invalidated. Stage color now lives on the struct loaded from `pipeline_stage_configs`. Adjust to consume the struct's color property instead.
- [ ] **Re-check Tasks 3-4.** New computed properties on `PipelineViewModel` may conflict with Phase 2 additions (e.g., if Phase 2 already added some). Diff against the post-Phase-2 VM before writing tests.
- [ ] **Rewrite Task 7-8.** `StageStripView` and `LeadCardView` redesigns referenced enum-based `PipelineStage`. Update to consume the struct.
- [ ] **Re-enumerate Task 13's file move.** `Books/Pipeline/` will contain Phase 2-added files (AI sheet, image gallery, contact import sheet, etc.). Move list needs to be regenerated.
- [ ] **Remove all `xcodebuild` invocations from the plan.** Saved feedback "Don't run xcodebuild" forbids it. Replace each `xcodebuild build` and `xcodebuild test` step with: "ASK USER: 'Please run the build and confirm it passes before continuing.'" The user runs builds and tests themselves.
- [ ] **Remove the BLOCKED status header** (top of this file) and § 0 (spec header) once all the above are complete.
- [ ] **Re-confirm with user that direction holds** — given how much Phase 2 changes, the user may want to revisit Q1-Q7 decisions before executing.

Estimated re-planning effort: ~2 hours for spec/plan reconciliation, then execution proceeds per the (revised) phase ordering.
