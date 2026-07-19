# Leads Tab Redesign — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans (or custom-skills:executing-plans) to implement this plan task-by-task.

**Goal:** Rebuild the iOS Leads surfaces per the approved spec — a chase system that stays truthful without logging (handled_at + auto comeback dates), do-and-stamp quick contact, a chase-console card with an expandable summary band, a dossier-style detail with a map hero and a status dropdown, and a work-first tab summary. Weighted probability retired everywhere.

**Spec (read first, it is the contract):** `docs/superpowers/specs/2026-07-17-leads-tab-redesign-design.md`

**Architecture:** Leads stay network-backed (deliberately outside the SwiftData sync engine — `PipelineViewModel` merge/refresh pipeline unchanged). Two additive nullable columns land on `public.opportunities`. All new mutations ride existing repository paths (`update(_:patch:)`, `ActivityRepository.logActivity`, `moveToStage`). Views are rebuilt in place under `OPS/Views/Leads/`.

**Tech stack:** SwiftUI (iOS 17.6 target — no iOS-18-only APIs), Supabase swift client, XCTest (+ the ImageRenderer/UIHostingController snapshot harness).

**Design system:** `ops-design-system/project/DESIGN.md` + `mobile/MOBILE.md`; iOS tokens in `OPS/Styles/OPSStyle.swift` (+ `OPS/Styles/Components/`). Zero hardcoded color/spacing/radius/font values — every literal below that looks hardcoded (e.g. `9.5`, `1.4` tracking) must be checked against existing OPSStyle tokens first and only kept when the neighboring Leads files already use that exact literal-with-token pattern (they were token-traced in `3199ae24`).

**Required skills for the executor:** `custom-skills:executing-plans`, `custom-skills:mobile-ux-design`, `ops-copywriter:ops-copywriter` (any copy not verbatim in this plan), `animation-studio:ios-animations` (band expand/menu/strip transitions), `custom-skills:audit-design-system` (before final done), `superpowers:verification-before-completion`.

**Worktree ground rules (read before task 1):**
- Work in `/Users/jacksonsweet/Projects/OPS/ops-ios/.worktrees/lead-assignment` on `feat/lead-assignment`. Never touch ios main or other worktrees.
- Every `xcodebuild` call gets `-clonedSourcePackagesDirPath .spm-local` and a worktree-local DerivedData (`-derivedDataPath .dd`).
- Confirm `OPS/Utilities/Secrets.xcconfig` exists in the worktree before the first build; if missing: `cp /Users/jacksonsweet/Projects/OPS/ops-ios/OPS/Utilities/Secrets.xcconfig OPS/Utilities/Secrets.xcconfig`.
- Many Swift files are CRLF/mixed line endings — preserve them; never let an edit normalize a whole file.
- New Swift files are auto-included by Xcode 16 synchronized groups — no `.pbxproj` edits.
- Commands below assume `cd /Users/jacksonsweet/Projects/OPS/ops-ios/.worktrees/lead-assignment`.

**Canonical commands:**
- Unit/snapshot tests: `xcodebuild test -scheme OPS -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' -clonedSourcePackagesDirPath .spm-local -derivedDataPath .dd -only-testing:OPSTests/<TestClass> 2>&1 | tail -20` → expect `** TEST SUCCEEDED **` (grep the log, not the exit code — background shells mask it).
- Device-target build: `xcodebuild -scheme OPS -destination 'generic/platform=iOS' build -clonedSourcePackagesDirPath .spm-local -derivedDataPath .dd 2>&1 | tail -5` → expect `** BUILD SUCCEEDED **`.

---

## Phase 0 — Schema + model groundwork

### Task 1: Apply the additive migration

**Files:** none in-repo (DB change) — record SQL in the commit message of Task 2.

The two columns are nullable and invisible to every shipped client — safe to apply to prod now (free tier; no cost impact). Use the Supabase MCP (`apply_migration`, project `ijeekuhbatykdomumfjx`, name `leads_chase_handled_at_and_summary_stamp`):

```sql
ALTER TABLE public.opportunities
  ADD COLUMN IF NOT EXISTS handled_at timestamptz NULL,
  ADD COLUMN IF NOT EXISTS ai_summary_updated_at timestamptz NULL;
COMMENT ON COLUMN public.opportunities.handled_at IS
  'Operator declared the last inbound handled (chase flip). A newer last_inbound_at re-flips the lead to YOUR MOVE. iOS+web write; both triage engines read.';
COMMENT ON COLUMN public.opportunities.ai_summary_updated_at IS
  'When ai_summary was last written by the agent. Web summary writer sets it; clients show a freshness stamp only when present.';
```

**Verify:** `SELECT column_name FROM information_schema.columns WHERE table_name='opportunities' AND column_name IN ('handled_at','ai_summary_updated_at');` → 2 rows.

### Task 2: DTO + model fields

**Files:**
- Modify: `OPS/Network/Supabase/DTOs/OpportunityDTOs.swift` (OpportunityDTO)
- Modify: `OPS/DataModels/Supabase/Opportunity.swift` (props + `apply`)
- Test: `OPSTests/Pipeline/OpportunityDTODecodeTests.swift` (new)

**Step 1 — failing test.** New test file; decode a fixture WITH and WITHOUT the new keys (executor: copy a minimal valid opportunities JSON from an existing pipeline test fixture if one exists; otherwise build the dictionary inline with the required keys `id/company_id/stage/stage_entered_at/created_at/updated_at` + `contact_name`):

```swift
import XCTest
@testable import OPS

final class OpportunityDTODecodeTests: XCTestCase {
    private func decode(_ extra: String) throws -> OpportunityDTO {
        let json = """
        {"id":"00000000-0000-0000-0000-0000000000aa","company_id":"00000000-0000-0000-0000-0000000000bb",
         "contact_name":"Helen","stage":"quoted","stage_entered_at":"2026-07-08T12:00:00Z",
         "created_at":"2026-07-01T12:00:00Z","updated_at":"2026-07-15T12:00:00Z"\(extra)}
        """
        return try JSONDecoder().decode(OpportunityDTO.self, from: Data(json.utf8))
    }

    func testDecodesWithoutNewColumns() throws {          // shipped-build shape
        let dto = try decode("")
        XCTAssertNil(dto.handledAt); XCTAssertNil(dto.aiSummary); XCTAssertNil(dto.aiSummaryUpdatedAt)
        XCTAssertNil(dto.toModel().handledAt)
    }

    func testDecodesAndMapsNewColumns() throws {
        let dto = try decode(#","handled_at":"2026-07-16T09:00:00Z","ai_summary":"Quote sent.","ai_summary_updated_at":"2026-07-15T09:00:00Z""#)
        XCTAssertEqual(dto.aiSummary, "Quote sent.")
        let model = dto.toModel()
        XCTAssertNotNil(model.handledAt); XCTAssertEqual(model.aiSummary, "Quote sent."); XCTAssertNotNil(model.aiSummaryUpdatedAt)
    }
}
```

**Step 2:** run it (`-only-testing:OPSTests/OpportunityDTODecodeTests`) → FAIL (no such properties).

**Step 3 — implement.**
- `OpportunityDTO`: add `let handledAt: String?`, `let aiSummary: String?`, `let aiSummaryUpdatedAt: String?` + CodingKeys `handled_at` / `ai_summary` / `ai_summary_updated_at` + in `toModel()`: `opp.handledAt = handledAt.flatMap { SupabaseDate.parse($0) }` etc.
- `Opportunity`: add stored props `var handledAt: Date?`, `var aiSummary: String?`, `var aiSummaryUpdatedAt: Date?` in the counters section (keep declaration order), and the three matching lines in `apply(_:)` (the comment there mandates lockstep — a missed field silently never refreshes).

**Step 4:** re-run test → PASS. **Step 5:** commit `feat(leads): read handled_at + ai summary columns into the lead model` (include the Task-1 SQL in the body).

---

## Phase 1 — Chase engine

### Task 3: Bucket rule + vocabulary

**Files:**
- Modify: `OPS/ViewModels/PipelineViewModel.swift` (`triageBuckets` ~line 340-402, `bucketOf` ~406, `TriageBucket.label` ~282, `verbFor` ~440)
- Modify: `OPS/Views/Leads/LeadsTabView.swift` (`chipLabel` ~311, `groupHeaderLabel` ~396)
- Test: `OPSTests/Pipeline/LeadChaseEngineTests.swift` (new)

**Step 1 — failing tests.** Build `Opportunity` instances directly (network-only model — plain init + property sets, no SwiftData context needed):

```swift
import XCTest
@testable import OPS

@MainActor
final class LeadChaseEngineTests: XCTestCase {
    private func lead(stage: PipelineStage = .quoted,
                      direction: String? = nil,
                      lastInbound: Date? = nil,
                      handled: Date? = nil,
                      followUp: Date? = nil) -> Opportunity {
        let o = Opportunity(id: UUID().uuidString.lowercased(), companyId: "c", contactName: "T", stage: stage)
        o.lastMessageDirection = direction
        o.lastInboundAt = lastInbound
        o.handledAt = handled
        o.nextFollowUpAt = followUp
        return o
    }
    private func vm(_ leads: [Opportunity]) -> PipelineViewModel {
        let m = PipelineViewModel(); m.allOpportunities = leads; return m
    }

    func testInboundUnhandledIsYourMove() {
        let l = lead(direction: "in", lastInbound: .now.addingTimeInterval(-3600))
        XCTAssertEqual(vm([l]).bucketOf(l), .waitingOnYou)
    }
    func testHandledAfterInboundLeavesYourMove() {
        let l = lead(direction: "in", lastInbound: .now.addingTimeInterval(-7200), handled: .now.addingTimeInterval(-3600))
        XCTAssertEqual(vm([l]).bucketOf(l), .waitingOnThem)
    }
    func testNewerInboundReflipsToYourMove() {
        let l = lead(direction: "in", lastInbound: .now.addingTimeInterval(-60), handled: .now.addingTimeInterval(-3600))
        XCTAssertEqual(vm([l]).bucketOf(l), .waitingOnYou)
    }
    func testOverdueOutranksHandledState() {   // date buckets stay first-priority
        let l = lead(direction: "in", lastInbound: .now, followUp: Calendar.current.date(byAdding: .day, value: -2, to: .now))
        XCTAssertEqual(vm([l]).bucketOf(l), .overdue)
    }
    func testVocabulary() {
        XCTAssertEqual(PipelineViewModel.TriageBucket.waitingOnYou.label, "YOUR MOVE")
        XCTAssertEqual(PipelineViewModel.TriageBucket.waitingOnThem.label, "WAITING")
    }
}
```

**Step 2:** run → FAIL (handled cases + labels).

**Step 3 — implement.** In BOTH `triageBuckets` (the `for` loop's waiting-on-you branch) and `bucketOf`, replace the direction check with one shared helper on `PipelineViewModel`:

```swift
/// YOUR MOVE = last recorded touch was theirs AND the operator has not
/// declared it handled since. A newer inbound after a flip re-arms it.
nonisolated static func isAwaitingReply(_ opp: Opportunity) -> Bool {
    guard opp.stage != .newLead, opp.lastMessageDirection == "in" else { return false }
    guard let handled = opp.handledAt else { return true }
    guard let inbound = opp.lastInboundAt else { return false }
    return inbound > handled
}
```

Call sites: `if Self.isAwaitingReply(opp) { waitingOnYou.append(opp); continue }` and in `bucketOf`: `if Self.isAwaitingReply(lead) { return .waitingOnYou }`. Labels: `TriageBucket.label` → `.waitingOnYou: "YOUR MOVE"`, `.waitingOnThem: "WAITING"`; same strings in `LeadsTabView.chipLabel`; `groupHeaderLabel` → `"YOUR MOVE"` / `"WAITING"` (keep `"OVERDUE · CHASE NOW"`). `verbFor` `.waitingOnThem` verb stays `CHECK IN`.

**Step 4:** run → PASS. **Step 5:** run the existing suite file for regressions: `-only-testing:OPSTests` is too broad here; run `-only-testing:OPSTests/MoneyLeadsRedesignSnapshotTests` and fix any label-string assertion drift. **Step 6:** commit `feat(leads): handled_at chase rule + YOUR MOVE / WAITING vocabulary`.

### Task 4: markHandled + adjustComeback

**Files:**
- Modify: `OPS/Network/Supabase/DTOs/OpportunityDTOs.swift` (new patch struct)
- Modify: `OPS/ViewModels/PipelineViewModel.swift` (mutations section, after `discard`)
- Test: extend `OPSTests/Pipeline/LeadChaseEngineTests.swift`

**Step 1 — failing tests** for the pure date rule (static, testable without network):

```swift
    func testComebackDefaultsToThreeDays() {
        let d = PipelineViewModel.comebackDate(existing: nil, from: .now)
        XCTAssertEqual(Calendar.current.dateComponents([.day], from: .now, to: d).day, 2) // now+3d starts of day ≈ 2-3; assert via interval instead:
        XCTAssertEqual(d.timeIntervalSinceNow, 3 * 86_400, accuracy: 5)
    }
    func testSoonerFutureFollowUpKept() {
        let tomorrow = Date().addingTimeInterval(86_400)
        XCTAssertEqual(PipelineViewModel.comebackDate(existing: tomorrow, from: .now), tomorrow)
    }
    func testPastDueFollowUpReplaced() {
        let yesterday = Date().addingTimeInterval(-86_400)
        let d = PipelineViewModel.comebackDate(existing: yesterday, from: .now)
        XCTAssertEqual(d.timeIntervalSinceNow, 3 * 86_400, accuracy: 5)
    }
```

**Step 2:** run → FAIL. **Step 3 — implement:**

In `OpportunityDTOs.swift` (near `UpdateOpportunityDTO`):

```swift
/// Chase-flip patch — always emits both keys (explicit values, no nil-drop)
/// so handled_at and the comeback land atomically in one PATCH.
struct MarkHandledPatch: Encodable {
    let handledAt: String
    let nextFollowUpAt: String
    enum CodingKeys: String, CodingKey {
        case handledAt      = "handled_at"
        case nextFollowUpAt = "next_follow_up_at"
    }
}

/// Comeback-only patch (ADJUST on a waiting lead).
struct AdjustComebackPatch: Encodable {
    let nextFollowUpAt: String
    enum CodingKeys: String, CodingKey { case nextFollowUpAt = "next_follow_up_at" }
}
```

In `PipelineViewModel` (mutations section):

```swift
/// Comeback rule (spec §2.2): default now+3d; a sooner FUTURE follow-up is
/// kept; past-due dates are always replaced or an overdue lead could never
/// leave OVERDUE.
nonisolated static func comebackDate(existing: Date?, from now: Date = Date()) -> Date {
    let proposed = now.addingTimeInterval(3 * 86_400)
    if let existing, existing > now, existing < proposed { return existing }
    return proposed
}

/// HANDLED ✓ — declare the ball back in their court and schedule the comeback.
/// Returns the comeback date so the caller can voice the toast.
func markHandled(opportunityId: String) async throws -> Date {
    guard let repo = repository,
          let opp = allOpportunities.first(where: { $0.id == opportunityId }) else {
        throw NSError(domain: "Pipeline", code: 0)
    }
    let now = Date()
    let comeback = Self.comebackDate(existing: opp.nextFollowUpAt, from: now)
    let dto = try await repo.update(opportunityId, patch: MarkHandledPatch(
        handledAt: SupabaseDate.format(now),
        nextFollowUpAt: SupabaseDate.format(comeback)
    ))
    if let idx = allOpportunities.firstIndex(where: { $0.id == opportunityId }) {
        allOpportunities[idx].apply(dto.toModel())
    }
    return comeback
}

/// ADJUST — reschedule when this lead resurfaces.
func adjustComeback(opportunityId: String, to date: Date) async throws {
    guard let repo = repository else { return }
    let dto = try await repo.update(opportunityId, patch: AdjustComebackPatch(
        nextFollowUpAt: SupabaseDate.format(date)
    ))
    if let idx = allOpportunities.firstIndex(where: { $0.id == opportunityId }) {
        allOpportunities[idx].apply(dto.toModel())
    }
}
```

Note `apply(dto.toModel())` (NOT element replacement) — keeps reference identity so a pushed detail stays live, mirroring the merge contract.

**Step 4:** tests PASS. **Step 5:** commit `feat(leads): markHandled + adjustComeback with comeback-date rule`.

---

## Phase 2 — Quick contact = the log

### Task 5: `text_message` activity type

**Files:** Modify `OPS/DataModels/Enums/ActivityType.swift`; extend `LeadChaseEngineTests`.

Steps: failing test `XCTAssertEqual(ActivityType.textMessage.rawValue, "text_message")` + `XCTAssertFalse(ActivityType.textMessage.isSystemGenerated)` → add `case textMessage = "text_message"` (after `.meeting`), icon `"message.fill"`, NOT in `isSystemGenerated`. Grep `switch` statements over `ActivityType` app-wide (`grep -rn "case .meeting" OPS --include="*.swift"`) and add the new case anywhere the compiler demands (labels: `TEXT` / `Text message`). Web parity verified: `ops-web src/lib/types/pipeline.ts:113` `TextMessage = "text_message"`; live `activities.type` rows show no constraint violation risk (unconstrained text + web enum already ships it). Run → PASS → commit `feat(leads): text_message activity type`.

### Task 6: Quick-touch logger service

**Files:**
- Create: `OPS/Services/LeadQuickTouchLogger.swift`
- Modify: `OPS/Network/Supabase/Repositories/OpportunityRepository.swift` (subject fetch)
- Test: `OPSTests/Pipeline/LeadQuickTouchLoggerTests.swift` (new — pure composition tests)

**Step 1 — failing tests:**

```swift
    func testSmsURL() {
        XCTAssertEqual(LeadQuickTouchLogger.smsURLString(phone: "(555) 123-4567"), "sms:5551234567")
    }
    func testMailtoWithThreadSubject() {
        XCTAssertEqual(
            LeadQuickTouchLogger.mailtoURLString(email: "h@x.com", threadSubject: "Roof quote — 1240 Maple Ave"),
            "mailto:h@x.com?subject=Re%3A%20Roof%20quote%20%E2%80%94%201240%20Maple%20Ave")
    }
    func testMailtoNoThread() {
        XCTAssertEqual(LeadQuickTouchLogger.mailtoURLString(email: "h@x.com", threadSubject: nil), "mailto:h@x.com")
    }
    func testReSubjectNotDoubled() {
        XCTAssertEqual(LeadQuickTouchLogger.replySubject(from: "Re: Roof quote"), "Re: Roof quote")
        XCTAssertEqual(LeadQuickTouchLogger.replySubject(from: "Roof quote"), "Re: Roof quote")
    }
```

**Step 2:** FAIL. **Step 3 — implement.**

Repository (in the Fetch section, pattern-match `opportunityId(forEmailThreadId:)`):

```swift
/// Latest email-thread subject for a lead — powers the EMAIL quick action's
/// "Re:" compose. Nil when the lead has no correspondence.
func latestCorrespondenceSubject(for opportunityId: String) async throws -> String? {
    struct Row: Decodable { let subject: String? }
    let rows: [Row] = try await client
        .from("opportunity_correspondence_events")
        .select("subject")
        .eq("opportunity_id", value: opportunityId)
        .not("subject", operator: .is, value: "null")
        .order("occurred_at", ascending: false)
        .limit(1)
        .execute()
        .value
    return rows.first?.subject
}
```

Service — mirrors `MainTabView.autoLogOutboundCall` (MainTabView.swift:1323-1370) exactly: log via `ActivityRepository.logActivity(target: .opportunity(...))`, post `LeadActivityLoggedSuccess`, success toast with `ToastAction("UNDO")` → `OpportunityRepository.deleteActivity`:

```swift
//
//  LeadQuickTouchLogger.swift
//  OPS
//
//  Do-and-stamp quick contact (Leads redesign spec §3). TEXT / EMAIL on the
//  card open the real conversation AND log a fact-only outbound activity with
//  an UNDO toast — the same contract the around-call auto-log established.
//  CALL is NOT here: it keeps the shipped around-call intent flow (CallLogStore).
//

import Foundation
import UIKit

@MainActor
enum LeadQuickTouchLogger {

    // MARK: - URL composition (pure, unit-tested)

    static func smsURLString(phone: String) -> String {
        "sms:" + phone.filter { "0123456789+".contains($0) }
    }

    static func replySubject(from threadSubject: String) -> String {
        threadSubject.lowercased().hasPrefix("re:") ? threadSubject : "Re: \(threadSubject)"
    }

    static func mailtoURLString(email: String, threadSubject: String?) -> String {
        let encoded = email.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        guard let threadSubject, !threadSubject.isEmpty else { return "mailto:\(encoded)" }
        var comps = URLComponents(); comps.scheme = "mailto"; comps.path = email
        comps.queryItems = [URLQueryItem(name: "subject", value: replySubject(from: threadSubject))]
        return comps.string ?? "mailto:\(encoded)"
    }

    // MARK: - Do-and-stamp

    enum Mode { case text, email }

    /// Open the conversation and stamp the touch. Fact-only — no note, ever
    /// (spec §3). Fails soft: if the log write fails (offline), the compose
    /// still opened; show the error toast and move on.
    static func touch(_ mode: Mode, lead: Opportunity, companyId: String, userId: String?) {
        let name = lead.displayContactName
        switch mode {
        case .text:
            guard let phone = lead.contactPhone, !phone.isEmpty,
                  let url = URL(string: smsURLString(phone: phone)) else { return }
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            UIApplication.shared.open(url)
            log(type: .textMessage, subject: "Text to \(name)", lead: lead, companyId: companyId, userId: userId,
                toastLabel: "// TEXT LOGGED — \(name.uppercased())")
        case .email:
            guard let email = lead.contactEmail, !email.isEmpty else { return }
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            Task { @MainActor in
                let subject = try? await OpportunityRepository(companyId: companyId)
                    .latestCorrespondenceSubject(for: lead.id)
                if let url = URL(string: mailtoURLString(email: email, threadSubject: subject)) {
                    UIApplication.shared.open(url)
                }
                log(type: .email, subject: subject.map(replySubject(from:)) ?? "Email to \(name)",
                    lead: lead, companyId: companyId, userId: userId,
                    toastLabel: "// EMAIL LOGGED — \(name.uppercased())")
            }
        }
    }

    private static func log(type: ActivityType, subject: String, lead: Opportunity,
                            companyId: String, userId: String?, toastLabel: String) {
        Task { @MainActor in
            do {
                let created = try await ActivityRepository(companyId: companyId).logActivity(
                    target: .opportunity(lead), type: type, subject: subject,
                    direction: "outbound", createdBy: userId)
                NotificationCenter.default.post(name: Notification.Name("LeadActivityLoggedSuccess"),
                                                object: nil, userInfo: ["leadId": lead.id])
                ToastCenter.shared.present(Toast(
                    label: toastLabel, tone: .success, autoDismissAfter: 6,
                    action: ToastAction(label: "UNDO", accessibilityLabel: "Undo logged touch") {
                        Task { @MainActor in
                            try? await OpportunityRepository(companyId: companyId).deleteActivity(created.id)
                            NotificationCenter.default.post(name: Notification.Name("LeadActivityLoggedSuccess"),
                                                            object: nil, userInfo: ["leadId": lead.id])
                            ToastCenter.shared.present(Toast(label: "// TOUCH REMOVED", tone: .warning))
                        }
                    }))
            } catch {
                ToastCenter.shared.present(Toast(label: Feedback.Err.saveFailed, tone: .error))
            }
        }
    }
}
```

(Check `ActivityRepository.logActivity`'s exact `direction` vocabulary first: the call auto-log passes `"outbound"` — use the same string. Check `Feedback.Err.saveFailed` exists — it's used in `LeadsTabView.advance`.)

**Step 4:** tests PASS. **Step 5:** commit `feat(leads): do-and-stamp quick-touch logger (text/email + undo)`.

### Task 7: TEXT chip in the full log sheet

**Files:** Modify `OPS/Views/Pipeline/UnifiedLogActivitySheet.swift` + `OPS/ViewModels/UnifiedLogActivityViewModel.swift`.

Add `.textMessage` to the TYPE chip row (label `TEXT`), between CALL and EMAIL. Read the view model's type-driven `show*Field` flags and give `.textMessage` the same field set as `.email` minus subject (direction only) — inspect `showDirectionField/showDurationField/showOutcomeField/subjectSection` gating and extend the switches; update the header comment that declared text out of scope. Placeholder copy for notes: `"What did they say?"`. Build the scheme (device target) to prove no missed switch. Commit `feat(leads): TEXT type in the unified log sheet`.

---

## Phase 3 — Standard confirm + status menu

### Task 8: `OPSConfirm`

**Files:**
- Create: `OPS/Styles/Components/OPSConfirm.swift`
- Modify (adopt): `OPS/Views/Components/Common/DeleteConfirmation.swift` stays for its 3 legacy call sites — new component is the standard going forward.

One reusable confirmation modifier, parameterized: `title` (uppercase), `message`, `verb` (confirm button label), `tone` (`.destructive` rose / `.neutral`), `onConfirm`. Implementation: native `.alert` under the hood (matches the app's 53 existing alert confirms — predictable iOS behavior), exposed as:

```swift
extension View {
    func opsConfirm(_ config: Binding<OPSConfirmConfig?>) -> some View { ... }
}
struct OPSConfirmConfig: Identifiable {
    let id = UUID()
    let title: String       // "ARCHIVE LEAD?"
    let message: String     // "It leaves the queue. Restore any time from the by-stage list."
    let verb: String        // "ARCHIVE"
    let isDestructive: Bool // Button(role: .destructive)
    let onConfirm: () -> Void
}
```

Copy register (ops-copywriter): terse, declarative, no exclamation. DISCARD message: `"DESTRUCTIVE. NO UNDO. This lead was never real."` Verify with a snapshot-less unit compile + use in Task 9. Commit `feat(components): OPSConfirm standardized confirmation`.

### Task 9: `LeadStatusMenu`

**Files:**
- Create: `OPS/Views/Leads/Components/LeadStatusMenu.swift`
- Test: snapshot in Task 13's harness.

A SwiftUI `Menu` (native menu = correct dropdown behavior, dims background, 44pt rows) whose label is provided by the host (detail chip / card chip). Content: `// SET STATUS`-style section of the six open stages (current checkmarked via `Label`/checkmark), `WON →`, `Divider()`, `LOST`, `ARCHIVE`, `DISCARD`. API:

```swift
struct LeadStatusMenu<Label: View>: View {
    let lead: Opportunity
    let canEdit: Bool
    let canConvert: Bool
    /// Direct stage pick (open stages only — never .won).
    var onStage: (PipelineStage) -> Void
    var onWon: () -> Void      // parent routes to ConvertToProjectSheet
    var onLost: () -> Void     // parent routes to LostReasonSheet
    var onArchive: () -> Void  // parent shows OPSConfirm then archives
    var onDiscard: () -> Void  // parent runs leadDiscardFlow
    @ViewBuilder var label: () -> Label
}
```

Gating: stages+lost/archive/discard require `canEdit`; WON requires `canConvert`; a viewer with neither renders the label as plain (no menu). Medium haptic on selection. Stage order: `[.newLead, .qualifying, .quoting, .quoted, .followUp, .negotiation]` (the `LeadTriageCard.openStages` list — promote that array to `PipelineStage.openStages` static and reuse). Commit `feat(leads): shared lead status menu`.

---

## Phase 4 — The card

### Task 10: Rebuild `LeadTriageCard`

**Files:**
- Modify: `OPS/Views/Leads/Triage/LeadTriageCard.swift` (full rebuild per spec §4 / mockup card-face-v3)
- Modify: `OPS/Views/Leads/LeadsTabView.swift` (`cardFor` — new closures)
- Modify: `OPS/Views/Leads/PipelineStageListView.swift` (same card API)

**Design tokens:** `.commandCard()`, `OPSStyle.Colors.{roseTextM,tanTextM,opsAccent,text,text2,text3,textMute,line,surfaceInput,olive}`, `OPSStyle.Layout.{spacing*,sidebarHoverRadius,chipRadius,touchTargetMin}`, fonts via existing Leads literals (`JetBrainsMono-Medium` 11/10/9.5/8.5, `Mohave-Medium` 16). Summary band label color: `OPSStyle.Colors.agent*` tokens — check `OPSStyle.swift` for agent/lavender tokens (`grep -n "agent" OPS/Styles/OPSStyle.swift`); if absent, ADD them from DESIGN.md §3 (`#8A7FB8`, soft 0.10, line 0.35) as `Colors.agent`, `agentSoft`, `agentLine` — never inline hex in the view.

New anatomy (spec §4): name+value → job line → **chase strip** (state left, `HANDLED ✓`/`ADJUST` chip right — whole strip one button, min 44pt) → meta row (segments + `QUOTED · 9D ▾` hosting `LeadStatusMenu` + source; **win% dot deleted**) → contact row (`CALL`/`TEXT`/`EMAIL` 36pt-visual buttons + `✎` glyph) → **summary footer band** (full-bleed under a hairline: `// SUMMARY` + `2D AGO ⌄`; only when `lead.aiSummary` non-empty; tap toggles `@State private var summaryExpanded`; expanded: agent-soft background block, 2pt `agentLine` leading rail, body 12.5 `text2`, 150ms opacity+height transition honoring reduced motion).

Strip states/copy (spec §2.3): overdue `→ CHASE · {n}D LATE` (roseTextM), dueToday `→ DUE TODAY` (tanTextM), yourMove `→ YOUR MOVE · {n}D` (opsAccent), waiting `THEIR MOVE · BACK {IN nD|FRI}` (text2, button `ADJUST`), fresh `NEW · 2H` (text2, button hidden — fresh leads have nothing to flip; strip is informational).

New card API:

```swift
struct LeadTriageCard: View {
    let lead: Opportunity
    let viewModel: PipelineViewModel
    let bucket: PipelineViewModel.TriageBucket
    var canEdit: Bool
    var canConvert: Bool
    var onTap: () -> Void
    var onLog: () -> Void                 // ✎ full sheet
    var onHandled: () -> Void             // strip button (yourMove/overdue/dueToday)
    var onAdjust: () -> Void              // strip button (waiting) — opens date chooser
    var onStage: (PipelineStage) -> Void  // status menu stage pick
    var onWon: () -> Void
    var onLost: () -> Void
    var onArchive: () -> Void
    var onDiscard: () -> Void
    var disableSwipe: Bool = false
}
```

Quick contact calls `LeadQuickTouchLogger.touch(...)` internally (needs `companyId` — it's `lead.companyId`; userId via `@EnvironmentObject DataController`). CALL keeps the exact `ContactCard.placeCall` behavior — move that logic into the card (CallLogStore.recordOutbound gate + `tel:`). Terminal leads (`PipelineStageListView` reuse): keep the existing `outcomeStrip` branch, hide contact row + band + menu.

Steps: rebuild → wire `LeadsTabView.cardFor` (handled: `Task { try await viewModel.markHandled }` + comeback toast with `ADJUST` `ToastAction` → presents the date chooser sheet; archive via `OPSConfirm`; discard via existing `discardTarget` flow; onStage → `viewModel.moveToStage`; won→convert sheet; lost→lost sheet) → same in `PipelineStageListView` → device build green → commit `feat(leads): chase-console card (strip flip, quick contact, summary band)`.

### Task 11: Comeback date chooser

**Files:** Create `OPS/Views/Leads/Sheets/ComebackChooserSheet.swift`.

Half sheet (`.presentationDetents([.height(280)])`, drag indicator): title `// NEXT TOUCH`, four rows — `IN 3 DAYS` / `IN 1 WEEK` / `IN 2 WEEKS` / `PICK DATE` (inline `DatePicker` `.graphical` collapsed behind the fourth row). On pick: `viewModel.adjustComeback`, success haptic, dismiss. Presented from: strip `ADJUST`, and the post-HANDLED toast's `ADJUST` action. State lives in `LeadsTabView` (`@State private var comebackTarget: Opportunity?` + `.sheet(item:)`) and `LeadDetailView` (same pattern). Commit `feat(leads): comeback date chooser`.

### Task 12: Swipe = stage

**Files:** Modify `OPS/Views/Leads/Triage/LeadTriageCard.swift`; reference `OPS/Views/JobBoard/UniversalJobBoardCard.swift:43,263-272` for the mechanics.

Port the Job Board gesture verbatim in miniature: `@State swipeOffset`, `highPriorityGesture(DragGesture)` updating offset (clamped ±width), target-stage layer fading in at `abs(offset)/(width*0.4)`, release ≥ threshold commits (right = `stage.next` — `.won` routes through `onWon`, never direct; left = previous open stage, none at `.newLead`), snap back with `OPSStyle.Animation` standard curve; `disableSwipe` short-circuits (sheet contexts). Medium haptic on commit. The target layer shows the destination stage label in that stage's tone (reuse `OPSStyle.Colors.pipelineStageColor(for:)`). Respect reduced motion (opacity only). Test on-sim manually; snapshot the resting state only. Commit `feat(leads): job-board swipe grammar on lead cards`.

---

## Phase 5 — Lead detail

### Task 13: Map hero + reworked hero block

**Files:**
- Create: `OPS/Views/Leads/Components/LeadMapHeader.swift` (adapt `ProjectMapHeader` — `OPS/Views/Components/Project/ProjectMapHeader.swift`, `mapHeight: 320`, gradient stops at :30-32; accept `address/latitude/longitude` instead of `Project`)
- Modify: `OPS/Views/Leads/LeadDetailView.swift` (layer structure per `ProjectDetailsView.swift:380-412` — fixed map behind, scroll content over, 90pt scroll gradient, clear tap-spacer → directions)
- Modify: `OPS/Views/Leads/Components/DetailHero.swift` (title-as-header + subtitles + KPI swap)

DetailHero changes (spec §5): header = `lead.title ?? descriptionText ?? contactName` fallback chain (new computed `heroTitle`); subtitle 1 `contactName · clientName` (client name arrives via new `LeadDetailViewModel.client` — Task 14; contact omitted when it equals the client name case-insensitively); subtitle 2 = address (plain text — the MAP affordance is the map itself). Stage tag REMOVED from the hero (moves to nav chip, next step). KPI strip: `WEIGHTED` cell → `NEXT TOUCH` (`weekday-short` uppercase + `MMM d` sub, from `nextFollowUpAt`, `—` when nil); delete `winProbability`/`weightedValue` reads and the `N% WIN PROB` line. No-address leads: no `LeadMapHeader`, zero layout shift (conditional at the ZStack layer).

Nav row: `DetailNavBar` gains a trailing `LeadStatusMenu` host chip — the stage tag styling from the old hero `StageTag` (move `StageTag` out of DetailHero into `LeadStatusMenu.swift` as the shared chip label + `▾`). Text over map gets the shadow treatment ProjectDetails uses.

Sticky bar: `StickyActionBar` drops `lostButton` + `onMarkLost` (spec §5.11) — `✎ EDIT` + `MARK WON →` only; update `LeadDetailView` call site (LOST now routes via the status menu → `onMarkLost` closure kept on LeadDetailView but fired from the menu).

Snapshot: extend the existing harness (Task 17) with detail states. Commit `feat(leads): detail map hero, title-first hero, status chip nav`.

### Task 14: Detail data — client, files, summary

**Files:**
- Modify: `OPS/ViewModels/LeadDetailViewModel.swift`
- Modify: `OPS/Network/Supabase/Repositories/OpportunityRepository.swift` (attachments fetch)
- Test: `OPSTests/Pipeline/LeadDetailDataTests.swift` (new — ON FILE matching pure logic)

ViewModel additions (all loaded in `loadAll()`'s parallel group, each failing soft like the existing three):

```swift
@Published var client: Client?                 // via ClientRepository.fetchOne(lead.clientId)
@Published var subClients: [SubClient] = []    // via ClientRepository.fetchSubClients(for:)
@Published var attachments: [LeadAttachment] = []
@Published var estimates: [Estimate] = []      // via EstimateRepository's opportunity_id fetch (exists — EstimateRepository.swift:82)
@Published var latestThreadSubject: String?    // latestCorrespondenceSubject (reused by CONTACT sheet email)
```

`LeadAttachment` = small decodable over `email_attachments` (`id, filename, storage_path, source_url, from_email, created_at` — verify column list with a `select *` limit 1 before coding the DTO; storage_path resolves through the existing S3/public URL convention used by `opportunities.images`, check how web builds the URL in `ops-web` before inventing one — `grep -rn "email_attachments" ops-web/.worktrees/lead-assignment/src | head`).

ON FILE logic (pure, tested — mirror web's `DealContactRow` rules read this session):

```swift
enum LeadContactRosterState: Equatable { case mirrorsClient, onFile, notOnFile, noClient }

static func rosterState(contactName: String?, contactEmail: String?, contactPhone: String?,
                        client: Client?, subClients: [SubClient]) -> LeadContactRosterState {
    guard let client else { return .noClient }
    func norm(_ s: String?) -> String { (s ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
    func normPhone(_ s: String?) -> String { (s ?? "").filter(\.isNumber) }
    let mirrors = norm(contactName) == norm(client.name)
        || (!norm(contactEmail).isEmpty && norm(contactEmail) == norm(client.email))
        || (!normPhone(contactPhone).isEmpty && normPhone(contactPhone) == normPhone(client.phoneNumber))
    if mirrors { return .mirrorsClient }
    let onFile = subClients.contains { sc in
        guard sc.deletedAt == nil else { return false }
        if !norm(contactEmail).isEmpty, norm(sc.email) == norm(contactEmail) { return true }
        return !norm(contactName).isEmpty && norm(sc.name) == norm(contactName)
    }
    return onFile ? .onFile : .notOnFile
}
```

(Verify `Client` property names — `grep -n "var name\|var email\|var phoneNumber" OPS/DataModels/Client.swift` — before writing.) `ADD TO CLIENT` action: create a `SubClient` via the path `SubClientEditSheet`/ClientRepository already uses (`grep -rn "createSubClient\|insertSubClient" OPS/Network` — reuse, don't invent). Tests cover: mirrors / on-file-by-email / on-file-by-name / not-on-file / no-client. Commit `feat(leads): detail data layer (client roster, files, estimates, thread subject)`.

### Task 15: Contact pair + details document

**Files:**
- Modify: `OPS/Views/Leads/LeadDetailView.swift`
- Create: `OPS/Views/Leads/Components/LeadDetailsDocument.swift`
- Delete: `OPS/Views/Leads/Components/ContactCard.swift` usage from detail (file deleted once nothing references it)
- Modify: `OPS/Views/Leads/Components/LeadPhotosSection.swift` + `LeadDeckSection.swift` (re-skin as document rows — keep ALL their mechanics: photo add dialog/camera/library/viewer, deck create/open)

Action pair (spec §5.8): full-width `CONTACT ▾` + 44pt `⋯` square. CONTACT = `confirmationDialog` listing `CALL (555) 123-4567` / `TEXT` / `EMAIL helen@…` — CALL runs the around-call path, TEXT/EMAIL run `LeadQuickTouchLogger`. `⋯` = `Menu`: `START SITE VISIT` (existing `showingSiteVisitCapture`, gated `canConvert && !terminal`), `LOG ACTIVITY` (present `UnifiedLogActivitySheet` locally via new `@State`), `SHARE LEAD` (existing `shareLead()` — remove the nav-bar share button), `ARCHIVE`/`DISCARD` are NOT here (status menu owns them).

`LeadDetailsDocument` — L1 card of fixed rows (58pt label column, mono 8.5 labels, `—` empties): `CLIENT` (name + roster subline `HELEN — ON FILE` / `ADD TO CLIENT` button / `—`; tap → nothing in v1 beyond the add action — iOS has no client detail push from here; keep row non-navigating and flag), `PROJECT` (name via existing project resolution if `projectId` set — `grep -rn "projectId" OPS/Views/Leads` for how convert links; tap → project via `appState` deep link used elsewhere), `DECK` (LeadDeckSection content), `PHOTOS` (LeadPhotosSection strip), `FILES` (attachments + estimate rows → `QuickLook`/share sheet via `presentShareSheet`). Delete `SiteVisitLaunchCard` struct; keep `WonNotConvertedCard` untouched above the document. Delete `FollowUpsCard` usage (+ file) — NEXT TOUCH + strip carry it.

Commit `feat(leads): contact pair + fixed details document`.

### Task 16: One activity stream

**Files:**
- Modify: `OPS/Views/Leads/Components/ActivityTimeline.swift` (expansion + direction glyphs + stage entries)
- Create: `OPS/Views/Leads/LeadActivityHistoryView.swift` (VIEW ALL push)
- Delete: `OPS/Views/Leads/Components/StageTimeline.swift` (+ its call site)

Rows: direction glyph (`↓` steel inbound / `↑` olive outbound / type icon otherwise), `Who — type` line, age, `⌄` when the row has body (`bodyText ?? content`), tap toggles inline body (mono-quiet block, 150ms, reduced-motion aware). Stage changes: `stageTransitions` mapped into the same list as `● Stage: QUOTING → QUOTED` rows (merge-sort by date with activities; delete the separate section). Cap at 6 rows + `VIEW ALL → N` footer pushing `LeadActivityHistoryView` (same rows, full list, standard DetailNavBar). VoiceOver: rows announce direction + expanded state. Commit `feat(leads): unified expandable activity stream`.

---

## Phase 6 — Tab top + retirement sweep

### Task 17: Work-first summary

**Files:**
- Modify: `OPS/Views/Leads/Triage/LeadsSummary.swift` (full rebuild per spec §7 / mockup leads-top A)
- Modify: `OPS/ViewModels/PipelineViewModel.swift` (new computeds)
- Modify: `OPS/Views/Leads/LeadsTabView.swift` (`caughtUpHint`)
- Test: extend `LeadChaseEngineTests`

VM computeds (TDD — tests first):

```swift
var needActionCount: Int {          // overdue + dueToday + yourMove
    let b = triageBuckets
    return b.overdue.count + b.dueToday.count + b.waitingOnYou.count
}
var openPipelineValue: Double {     // UNWEIGHTED sum, open leads
    allOpportunities.filter { !$0.stage.isTerminal && !$0.isDeleted && !$0.isArchived }
        .reduce(0) { $0 + ($1.estimatedValue ?? 0) }
}
var wonThisMonthValue: Double {     // won leads with actualCloseDate in the current calendar month
    let cal = Calendar.current
    return allOpportunities.filter { o in
        guard o.stage == .won, !o.isDeleted, let d = o.actualCloseDate else { return false }
        return cal.isDate(d, equalTo: Date(), toGranularity: .month)
    }.reduce(0) { $0 + ($1.actualValue ?? $1.estimatedValue ?? 0) }
}
```

View: hero `N NEED ACTION` (Mohave-Light 38-ish numeral — reuse the CountUpText pattern; numeral tone rose when `overdue > 0`, tan when `needActionCount > 0`, text at zero; label word in the tone), breakdown line in bucket tones, 3-cell tile row (`PIPELINE {compact}` / `OPEN {n}` / `WON · {MMM} {compact}` olive), keep `stageBar`, delete `forecastHero`/`deltaLine`/`velocityLine`/`triageTiles` (tiles superseded by the breakdown + chips). `caughtUpHint` → `"\(openLeadCount) OPEN · PIPELINE \(BooksFormat.compact(openPipelineValue))"`. Do NOT delete `weightedForecastValue`/`forecastDeltaPct` from the VM yet — grep consumers first (`grep -rn "weightedForecastValue\|forecastDeltaPct\|avgVelocityDays" OPS --include="*.swift"`): anything outside Leads (Books/search) keeps them; if Leads-only, delete with this commit. Commit `feat(leads): work-first tab summary`.

### Task 18: Win-probability retirement sweep

**Files:** whatever the grep finds.

`grep -rn "winProbability\|weightedValue\|WIN PROB\|WEIGHTED" OPS --include="*.swift" | grep -v Tests` — for each UI read outside the already-rebuilt files (expect: `ConvertToProjectSheet` summary, `EditLeadSheet`, possibly universal-search/Books surfaces): remove the rendered element (not the model field). Books' `MoneyDashboardViewModel` pipeline lens: if it renders weighted forecast, it keeps working this release (Books redesign owns that surface) — leave non-Leads surfaces untouched but LIST them in the commit body for the record. Device build green. Commit `refactor(leads): retire win-probability renders from lead surfaces`.

### Task 19: Snapshot + full-suite proof

**Files:**
- Modify: `OPSTests/Views/MoneyLeadsRedesignSnapshotTests.swift` (replace dead renders: old card/summary/detail states) — new states: card × (overdue/dueToday/yourMove/waiting/fresh/terminal) × band (collapsed/expanded/none), detail (map/no-address, blanks, roster states), status chip, summary (loaded/zero).
- Harness rules (hard-won): render via the exact production container chain; `ImageRenderer` snapshots animate-to-end for plain modifiers but `Animatable` views render frame 0; asset-catalog colors need `UIHostingController` + `drawHierarchy` — follow the harness's existing patterns.

Run: full `xcodebuild test -scheme OPS -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' -clonedSourcePackagesDirPath .spm-local -derivedDataPath .dd 2>&1 | grep -E "TEST|failed" | tail -10` → `** TEST SUCCEEDED **` (some full-suite failures are sim launch denials — compare against a baseline run before blaming the change). Extract PNGs from the xcresult for Jackson's visual proof (existing extraction pattern in the repo's snapshot workflow). Device build green. Commit `test(leads): snapshot coverage for the redesigned surfaces`.

### Task 20: Docs + handoff

**Files:**
- Modify: `ops-software-bible/` pipeline/leads section (document: handled_at semantics, ai_summary_updated_at, text_message on iOS, the new surfaces) — same session, bible must stay current.
- Create: `/Users/jacksonsweet/Projects/OPS/ops-web/.worktrees/lead-assignment/docs/plans/2026-07-17-leads-chase-parity-handoff.md` — the three web items (spec §9): respect handled_at in web triage; set ai_summary_updated_at in the summary writer; optional chip vocabulary.
- Update the session memory file per its conventions.

Final gate: run `custom-skills:audit-design-system` over the changed Leads files (zero hardcoded values that don't trace to OPSStyle), then `superpowers:verification-before-completion`. Report to Jackson in plain English with the snapshot PNGs.

---

## Execution notes

- **Order is load-bearing:** Phases 0→1→2 are prerequisites for everything visual; 3 before 4/5 (card + detail host the menu); 6 last.
- **Never** route `.won` through `moveToStage` — the repository throws by design (`validateDirectStageMutation`); WON always goes through `ConvertToProjectSheet`.
- The nine `Lead*Success` NotificationCenter names in `LeadsTabView` are the reload contract — every new mutation posts one of the existing names (quick log posts `LeadActivityLoggedSuccess`; markHandled posts `LeadUpdatedSuccess`).
- Sibling sessions may run in parallel elsewhere in the repo — stay inside the lead-assignment worktree, stage by filename, commit atomically per task.
