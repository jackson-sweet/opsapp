# Leads — Discard a lead (iOS) · Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use `custom-skills:executing-plans` to implement this plan task-by-task. Enforce design-system compliance during execution; run `custom-skills:audit-design-system` before calling any UI task done. Preserve existing CRLF/LF line endings per file.

**Goal:** Give the Leads tab a first-class **Discard** action — for leads that were never real (spam, wrong number, duplicate, test data) — distinct from Archive (keep) and Lost (real deal), reachable from the mark-as-lost sheet and the long-press menu, with a first-run explainer then a quick confirm.

**Architecture:** Discard = move the opportunity to the existing terminal `stage = discarded` (the purpose-built "junk" state, PRD §Discard) via the already-live `move_opportunity_stage` RPC — no migration, no new backend, no schema change. A shared `@AppStorage` flag drives "explain once, then quick confirm." UI is built entirely from existing `OPSStyle` tokens and existing sheet primitives.

**Tech Stack:** SwiftUI, SwiftData, Supabase Postgres RPC (`move_opportunity_stage`), iOS 17.6 deployment target.

**Design System:** `OPSStyle` (`ops-ios/OPS/Styles/OPSStyle.swift`) + `ops-design-system/project/mobile/MOBILE.md`. Every value traces to a token. No `.interface-design/system.md` in this repo — `OPSStyle` is the source of truth.

**Required Skills (executing agent must load):** `ops-design`, `custom-skills:mobile-ux-design`, `ops-copywriter:ops-copywriter` (all strings are pre-locked below — do not improvise), `animation-studio:animation-architect` → `animation-studio:ios-animations` (sheet/dialog motion), `custom-skills:wizard-audit` (war-game the explainer/confirm flow before shipping), `custom-skills:audit-design-system` (final gate).

**Verified facts (do not re-litigate):**
- `opportunities.stage` is **plain `text`, no CHECK, no enum** → `'discarded'` is accepted. (Live DB checked.)
- Only UPDATE gate is RLS `role_scope_update` requiring `pipeline.manage` = the `canManage` flag the UI already checks for Archive. (Live DB checked.)
- `move_opportunity_stage(uuid, text, uuid)` accepts any stage, updates `stage`/`stage_entered_at`/`stage_manually_set`/`updated_at`, and inserts an immutable `stage_transitions` audit row. (Function body checked.)
- `PipelineViewModel` holds `currentUserId` (`ViewModels/PipelineViewModel.swift:27`) — no userId threading needed for the list path.
- `Opportunity: Identifiable` (`DataModels/Supabase/Opportunity.swift:13`) — valid for `.sheet(item:)`.
- Triage buckets exclude terminal stages → a discarded lead drops off the board automatically once `stage` flips locally.

**Locked copy (OPS voice — final, verbatim):**
| Slot | String |
|------|--------|
| Explainer title | `DISCARD vs LOST` |
| Explainer — Lost term | `// LOST` |
| Explainer — Lost body | `A real lead you chased and lost. Counts in your win rate.` |
| Explainer — Discard term | `// DISCARD` |
| Explainer — Discard body | `Never a real lead — spam, wrong number, duplicate. Off your board, never a lost deal.` |
| Explainer primary btn | `DISCARD LEAD` |
| Explainer secondary btn | `CANCEL` |
| Repeat confirm title | `Discard this lead?` |
| Repeat confirm body | `Comes off your board. Never counts as a lost deal.` |
| Repeat confirm buttons | `DISCARD` (destructive) · `CANCEL` |
| Lost-sheet link | `Not a real lead? Discard instead` |
| Context-menu label | `Discard` |
| Toast | `// LEAD DISCARDED` (tone `.warning`) |

**Locked visual tokens:**
- Discard SF Symbol: `nosign` (distinct from `pencil`/`archivebox`/`xmark`; destructive role auto-colors it).
- Explainer detent: `.medium` + `.presentationDragIndicator(.visible)` (matches `LostReasonSheet`).
- Rose (destructive) family: `roseTextM` / `roseFillM` / `roseLineM`. Muted contrast text: `text3`, `textMute`. Primary text: `text`. Hairline: `line`. Nested-card fill via `.nestedCard()`.
- Spacing: `spacing1..spacing5`, `spacing2_5=12`, `spacing3_5=20`. Radius: `Layout.buttonRadius = 5`.
- Fonts: `SheetTitleLabel`/`SheetCTAButton` (CakeMono-Light), `// TERM` labels JetBrainsMono-Regular 10 kerning 1.4 uppercase (matches `LostReasonSheet.summaryCard` meta line), body `OPSStyle.Typography.body`.

---

## Pre-flight: isolated workspace

Work in a dedicated worktree to avoid the sibling session's uncommitted WIP on `main` (`project.pbxproj`, `OPSApp.swift`, `TabBarSnapshotTests.swift`) and DerivedData/SPM collisions.

```bash
cd /Users/jacksonsweet/Projects/OPS/ops-ios
git worktree add ../ops-ios-leads-discard -b feat/leads-discard
cp OPS/Utilities/Secrets.xcconfig ../ops-ios-leads-discard/OPS/Utilities/Secrets.xcconfig
```

All builds/tests in the worktree pass `-clonedSourcePackagesDirPath .spm-local`. New Swift files must be added to the `OPS` target in `project.pbxproj` (do this in the worktree only).

Build command (device-target verification):
`xcodebuild -scheme OPS -destination 'generic/platform=iOS' -clonedSourcePackagesDirPath .spm-local build`
Test command:
`xcodebuild -scheme OPS -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' -clonedSourcePackagesDirPath .spm-local test`

---

## Task 1: `PipelineViewModel.discard` (data layer)

**Skills:** none (pure logic). **Files:** Modify `OPS/ViewModels/PipelineViewModel.swift` (after `archive`, ~line 249). Test: `OPSTests/ViewModels/PipelineViewModelDiscardTests.swift` (create).

Reuses `repo.moveToStage(to: .discarded)` — no new repository method (DRY; discard patches no extra fields, unlike markLost/markWon).

**Step 1 — Implement:**
```swift
/// Discard a junk lead — move it to the terminal `.discarded` stage. Unlike
/// mark-lost, records no reason: this was never a real deal. Rides the same
/// atomic `move_opportunity_stage` RPC (writes the stage_transitions audit row)
/// and flips the local model so the lead drops out of the triage buckets.
func discard(opportunityId: String) async throws {
    guard let repo = repository else { return }
    _ = try await repo.moveToStage(opportunityId: opportunityId, to: .discarded, userId: currentUserId)
    if let idx = allOpportunities.firstIndex(where: { $0.id == opportunityId }) {
        allOpportunities[idx].stage = .discarded
        allOpportunities[idx].stageEnteredAt = Date()
        allOpportunities[idx].stageManuallySet = true
    }
}
```

**Step 2 — Test (bucket exclusion is the observable contract):** Assert that an opportunity whose `stage` is `.discarded` is absent from `triageBuckets.all`. If the test harness supports injecting a stub `OpportunityRepository`, also assert `discard` sets the local stage to `.discarded`; otherwise cover the pure bucketization with a hand-built `.discarded` model. Run: `…test -only-testing:OPSTests/PipelineViewModelDiscardTests`. Expected: PASS.

**Step 3 — Commit:** `git add OPS/ViewModels/PipelineViewModel.swift OPSTests/ViewModels/PipelineViewModelDiscardTests.swift && git commit -m "feat(leads): PipelineViewModel.discard — move junk lead to discarded stage"`

---

## Task 2: Feedback toast + success notification

**Skills:** `ops-copywriter` (string pre-locked). **Files:** Modify `OPS/Styles/Components/Feedback.swift` (`enum Lead`, ~line 321).

**Step 1 — Add the toast:**
```swift
enum Lead {
    static let archived      = Toast(label: "// LEAD ARCHIVED", tone: .warning)
    static let discarded     = Toast(label: "// LEAD DISCARDED", tone: .warning)
    static let stageAdvanced = Toast(label: "// STAGE ADVANCED", tone: .success)
}
```

**Step 2 — Notification name:** Reuse the string-literal convention already used for `LeadArchivedSuccess`/`LeadMarkedLostSuccess` (posted where the discard succeeds, Tasks 5–6): `Notification.Name("LeadDiscardedSuccess")`. No central constant needed (matches existing siblings).

**Step 3 — Commit:** `git add OPS/Styles/Components/Feedback.swift && git commit -m "feat(leads): LEAD DISCARDED toast"`

---

## Task 3: `DiscardExplainerSheet` (first-run education)

**Skills:** `ops-design`, `mobile-ux-design`, `ios-animations`. **Files:** Create `OPS/Views/Leads/Sheets/DiscardExplainerSheet.swift`. Add to `OPS` target. Snapshot: extend `OPSTests/Views/BooksSnapshotTests.swift`.

**Design tokens:** `Colors.background`, `.text`, `.text2`, `.text3`, `.textMute`, `.roseTextM`; `Layout.spacing3_5/spacing2_5/spacing2/spacing1`; `SheetTitleLabel(.half)`, `SheetFooterButtonRow`, `SheetCTAButton(.secondary/.destructive)`, `.nestedCard()`. Footer gradient copied from `LostReasonSheet.footerOverlay`.

**Step 1 — Implement:**
```swift
import SwiftUI

/// First-run education shown the first time an operator discards a lead.
/// Contrasts DISCARD (never a real lead — junk) with LOST (a real deal you
/// didn't win). Confirming performs the discard and flips the shared
/// `leads_discard_explainer_seen` flag so subsequent discards use the lighter
/// confirm dialog instead. Half-detent, matches LostReasonSheet chrome.
struct DiscardExplainerSheet: View {
    let opportunity: Opportunity
    /// Async discard performed by the host (VM path or direct-repo path).
    let onConfirm: () async -> Void

    @Environment(\.dismiss) private var dismiss
    @AppStorage("leads_discard_explainer_seen") private var explainerSeen = false
    @State private var isWorking = false

    var body: some View {
        ZStack(alignment: .top) {
            OPSStyle.Colors.background.ignoresSafeArea()

            VStack(spacing: 0) {
                SheetTitleLabel(title: "DISCARD vs LOST", size: .half)
                    .padding(.horizontal, OPSStyle.Layout.spacing3_5)
                    .padding(.top, OPSStyle.Layout.spacing3_5)
                    .padding(.bottom, 14)

                ScrollView {
                    VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2_5) {
                        definitionRow(
                            term: "LOST",
                            termColor: OPSStyle.Colors.text3,
                            body: "A real lead you chased and lost. Counts in your win rate.",
                            bodyColor: OPSStyle.Colors.text2
                        )
                        definitionRow(
                            term: "DISCARD",
                            termColor: OPSStyle.Colors.roseTextM,
                            body: "Never a real lead — spam, wrong number, duplicate. Off your board, never a lost deal.",
                            bodyColor: OPSStyle.Colors.text
                        )
                    }
                    .padding(.horizontal, OPSStyle.Layout.spacing3_5)
                    .padding(.top, OPSStyle.Layout.spacing1)
                    .padding(.bottom, 130)
                }
                .scrollIndicators(.hidden)
            }

            footer
        }
        .preferredColorScheme(.dark)
        .interactiveDismissDisabled(isWorking)
    }

    private func definitionRow(term: String, termColor: Color, body: String, bodyColor: Color) -> some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
            HStack(spacing: 0) {
                Text("// ").foregroundColor(OPSStyle.Colors.textMute)
                Text(term).foregroundColor(termColor)
            }
            .font(.custom("JetBrainsMono-Regular", size: 10))
            .kerning(1.4)
            .textCase(.uppercase)

            Text(body)
                .font(OPSStyle.Typography.body)
                .foregroundColor(bodyColor)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, OPSStyle.Layout.spacing2_5)
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .nestedCard()
    }

    private var footer: some View {
        VStack(spacing: 10) {
            Spacer()
            SheetFooterButtonRow {
                SheetCTAButton(label: "CANCEL", variant: .secondary, action: { dismiss() })
                    .disabled(isWorking)
            } primary: {
                SheetCTAButton(label: "DISCARD LEAD", icon: "nosign",
                               variant: .destructive, isLoading: isWorking) {
                    guard !isWorking else { return }
                    isWorking = true
                    Task {
                        explainerSeen = true       // first run consumed
                        await onConfirm()
                        dismiss()
                    }
                }
            }
            .padding(.horizontal, OPSStyle.Layout.spacing3_5)
            .padding(.bottom, 28)
        }
        .background(
            LinearGradient(colors: [.black.opacity(0), .black.opacity(0.95), .black],
                           startPoint: .top, endPoint: .bottom)
                .frame(height: 160).allowsHitTesting(false),
            alignment: .bottom
        )
        .ignoresSafeArea(edges: .bottom)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
    }
}
```

**Step 2 — Snapshot proof:** add a `BooksSnapshotTests` case rendering `DiscardExplainerSheet` (via `UIHostingController` + `UIWindow` + `drawHierarchy` — `ImageRenderer` can't resolve asset colors). Export PNG to `docs/artifacts/`.

**Step 3 — Build & commit:** device-target build must be clean. `git add OPS/Views/Leads/Sheets/DiscardExplainerSheet.swift OPSTests/Views/BooksSnapshotTests.swift OPS.xcodeproj/project.pbxproj && git commit -m "feat(leads): DiscardExplainerSheet — first-run discard vs lost education"`

---

## Task 4: `LeadDiscardFlow` shared modifier (explainer ↔ confirm router)

**Skills:** `ios-animations`, `wizard-audit`. **Files:** Create `OPS/Views/Leads/Components/LeadDiscardFlow.swift`. Add to target.

One reusable modifier that both list surfaces and the lost sheet attach. Reads the shared `@AppStorage` flag; first run → presents `DiscardExplainerSheet`, thereafter → a native `.confirmationDialog`. The host supplies the async discard via `perform` (VM path vs direct-repo path) so this stays decoupled.

**Step 1 — Implement:**
```swift
import SwiftUI

extension View {
    /// Attaches the discard education/confirm flow. Set `target` to a lead to
    /// start it; the modifier clears `target`, routes to the explainer (first
    /// run) or the quick confirm (repeat), runs `perform`, then fires the
    /// success toast + `LeadDiscardedSuccess` notification and `onDiscarded`.
    func leadDiscardFlow(
        target: Binding<Opportunity?>,
        perform: @escaping (Opportunity) async throws -> Void,
        onDiscarded: @escaping (Opportunity) -> Void = { _ in }
    ) -> some View {
        modifier(LeadDiscardFlow(target: target, perform: perform, onDiscarded: onDiscarded))
    }
}

private struct LeadDiscardFlow: ViewModifier {
    @Binding var target: Opportunity?
    let perform: (Opportunity) async throws -> Void
    let onDiscarded: (Opportunity) -> Void

    @AppStorage("leads_discard_explainer_seen") private var explainerSeen = false
    @State private var explainerLead: Opportunity?
    @State private var confirmLead: Opportunity?

    func body(content: Content) -> some View {
        content
            .onChange(of: target?.id) { _, newID in
                guard newID != nil, let lead = target else { return }
                target = nil
                if explainerSeen { confirmLead = lead } else { explainerLead = lead }
            }
            .sheet(item: $explainerLead) { lead in
                DiscardExplainerSheet(opportunity: lead, onConfirm: { await run(lead) })
                    .presentationDetents([.medium])
                    .presentationDragIndicator(.visible)
            }
            .confirmationDialog(
                "Discard this lead?",
                isPresented: Binding(get: { confirmLead != nil },
                                     set: { if !$0 { confirmLead = nil } }),
                titleVisibility: .visible,
                presenting: confirmLead
            ) { lead in
                Button("DISCARD", role: .destructive) { Task { await run(lead) } }
                Button("CANCEL", role: .cancel) {}
            } message: { _ in
                Text("Comes off your board. Never counts as a lost deal.")
            }
    }

    private func run(_ lead: Opportunity) async {
        do {
            try await perform(lead)
            await MainActor.run {
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                ToastCenter.shared.present(Feedback.Lead.discarded)
                NotificationCenter.default.post(
                    name: Notification.Name("LeadDiscardedSuccess"),
                    object: nil, userInfo: ["leadId": lead.id]
                )
                onDiscarded(lead)
            }
        } catch {
            await MainActor.run {
                ToastCenter.shared.present(Toast(label: "// COULD NOT DISCARD", tone: .error))
            }
        }
    }
}
```

> **Note (`onChange` iOS 17 signature):** target is iOS 17.6 → use the two-parameter `onChange(of:) { _, newID in }`. Do not use the iOS-14 single-param form.
> **wizard-audit:** war-game — double-tap DISCARD (guarded by `isWorking` in the sheet; for the dialog, iOS dismisses on first tap), offline failure (error toast, stage NOT flipped because `perform` throws before the local mutation on the repo path — verify), permission lost mid-session (RLS rejects → error toast), lead already discarded elsewhere via realtime (no-op RPC), backgrounding mid-sheet.

**Step 2 — Build & commit:** `git add OPS/Views/Leads/Components/LeadDiscardFlow.swift OPS.xcodeproj/project.pbxproj && git commit -m "feat(leads): LeadDiscardFlow — shared explainer/confirm discard router"`

---

## Task 5: Shared `LeadCardContextMenu` + wire both list surfaces

**Skills:** `ops-design`, `mobile-ux-design`. **Files:** Create `OPS/Views/Leads/Components/LeadCardContextMenu.swift`; modify `OPS/Views/Leads/LeadsTabView.swift` (`cardFor`, ~390–415) and `OPS/Views/Leads/PipelineStageListView.swift` (`card(for:)`, ~132–157). The two menus are byte-identical today — extract so Edit/Archive/Discard never drift.

**Step 1 — Shared menu:**
```swift
import SwiftUI

/// The long-press menu shared by the triage queue and the by-stage list.
/// Edit + Archive are unchanged; Discard is added for non-terminal leads only
/// (a closed deal can't be junk-discarded). All gated by `canManage`.
struct LeadCardContextMenu: View {
    let lead: Opportunity
    let canManage: Bool
    let onEdit: () -> Void
    let onArchive: () -> Void
    let onDiscard: () -> Void   // sets the host's discard `target`

    var body: some View {
        if canManage {
            Button(action: onEdit) { Label("Edit", systemImage: "pencil") }
            Button(action: onArchive) { Label("Archive", systemImage: "archivebox") }
            if !lead.stage.isTerminal {
                Button(role: .destructive, action: onDiscard) {
                    Label("Discard", systemImage: "nosign")
                }
            }
        }
    }
}
```

**Step 2 — `LeadsTabView`:** add `@State private var discardTarget: Opportunity?`. Replace the inline `.contextMenu { … }` in `cardFor` with:
```swift
.contextMenu {
    LeadCardContextMenu(
        lead: lead, canManage: canManage,
        onEdit: { activeSheet = .edit(lead) },
        onArchive: {
            Task { do {
                try await viewModel.archive(opportunityId: lead.id)
                ToastCenter.shared.present(Feedback.Lead.archived)
            } catch {} }
        },
        onDiscard: { discardTarget = lead }
    )
}
```
Attach once on the tab's root view (same level as `.sheet(item: $activeSheet)`):
```swift
.leadDiscardFlow(
    target: $discardTarget,
    perform: { lead in try await viewModel.discard(opportunityId: lead.id) }
)
```

**Step 3 — `PipelineStageListView`:** identical swap in `card(for:)`, routing `onEdit/onArchive` through its `onRequestSheet`/`viewModel`, `onDiscard: { discardTarget = lead }`, and attach `.leadDiscardFlow(target: $discardTarget, perform: { try await viewModel.discard(opportunityId: $0.id) })` on its root. Add the `@State discardTarget` there too.

**Step 4 — Build, simulator check, commit.** Verify: long-press an open lead → Edit / Archive / **Discard** (red) appear; long-press a won/lost lead → no Discard. `git add …context menu files… && git commit -m "refactor(leads): shared LeadCardContextMenu + wire Discard into both list surfaces"`

---

## Task 6: Mark-as-lost sheet — "Discard instead" escape hatch

**Skills:** `ops-design`, `mobile-ux-design`, `ops-copywriter`. **Files:** Modify `OPS/Views/Leads/Sheets/LostReasonSheet.swift`.

**Design tokens:** link text `OPSStyle.Typography.body` (or `.caption`), "Not a real lead? " in `Colors.textMute`, "Discard instead" in `Colors.roseTextM`; 44pt tap zone; sits inside the existing footer gradient.

**Step 1 — Add state + flow:** add `@State private var discardTarget: Opportunity?`. Attach on the root `ZStack`:
```swift
.leadDiscardFlow(
    target: $discardTarget,
    perform: { lead in
        _ = try await OpportunityRepository(companyId: lead.companyId)
            .moveToStage(opportunityId: lead.id, to: .discarded,
                         userId: dataController.currentUser?.id)
        lead.stage = .discarded
        lead.stageEnteredAt = Date()
    },
    onDiscarded: { _ in dismiss() }   // close the lost sheet on success
)
```

**Step 2 — Add the tertiary link** to `footerOverlay`'s `VStack`, directly below `SheetFooterButtonRow { … }` and before its `.padding(.bottom, 28)` (move the bottom padding onto the link so it is the bottom-most element):
```swift
Button {
    UIImpactFeedbackGenerator(style: .light).impactOccurred()
    discardTarget = opportunity
} label: {
    HStack(spacing: 0) {
        Text("Not a real lead? ").foregroundColor(OPSStyle.Colors.textMute)
        Text("Discard instead").foregroundColor(OPSStyle.Colors.roseTextM)
    }
    .font(OPSStyle.Typography.body)
    .frame(maxWidth: .infinity, minHeight: 44)
    .contentShape(Rectangle())
}
.buttonStyle(PlainButtonStyle())
.disabled(isSaving)
.padding(.horizontal, OPSStyle.Layout.spacing3_5)
.padding(.bottom, 28)
```
Bump the scroll content's `.padding(.bottom, 130)` to `170` so nothing hides behind the taller footer. Increase the footer gradient height (`160` → `200`) to keep the fade covering the added row.

**Step 3 — Build, simulator check, commit.** Verify from a lead detail: rose ✕ → lost sheet → "Not a real lead? Discard instead" sits quietly below Confirm Lost; first tap → explainer, later taps → confirm; on success both dismiss and the lead leaves the board. `git commit -m "feat(leads): Discard-instead escape hatch in mark-as-lost sheet"`

---

## Task 7: Retire the buried, mislabeled Delete

**Skills:** `ops-design`. **Files:** `OPS/Views/Leads/Sheets/EditLeadSheet.swift`, `OPS/Views/Leads/Sheets/LeadFormView.swift` (danger-zone block).

The Edit danger-zone **Delete** (soft-delete → `deleted_at`) promises "restored from the trash," but the iOS `TrashView` restores projects/clients/tasks — **not leads** — so it's a false promise. Discard is now the clear, recoverable path. Remove the **Delete** affordance from the danger zone; **keep Archive**.

- In `EditLeadSheet.swift`: drop `showDeleteConfirm`, the `.confirmationDialog("Delete this lead?" …)`, the `onDelete:` argument, and the `delete()` method.
- In `LeadFormView.swift`: remove the Delete button from the danger-zone layout; keep Archive. Update the danger-zone doc comment.
- **Do NOT** touch `OpportunityRepository.softDelete` or `PipelineViewModel.softDelete` — UI removal only (other callers/tests may reference them).

**Step — Build, commit.** `git commit -m "refactor(leads): retire buried soft-delete in Edit — Discard is the recoverable path"`

---

## Task 8: Docs / bible reconciliation

**Files:** `DataModels/Enums/PipelineStage.swift:19`; `ops-software-bible/01_PRODUCT_REQUIREMENTS.md` (§Discard); `ops-software-bible/10_JOB_LIFECYCLE_AND_DATA_RELATIONSHIPS.md` (discard row, if it asserts server-only).

- `PipelineStage.swift:19` comment: change `// server-only junk state (migration 045); terminal, never in the triage queue` → `// junk state (migration 045); terminal, never in the triage queue. Operator-settable from iOS via move_opportunity_stage (Discard action).`
- Bible §Discard: note the PRD's "No confirmation dialog" is refined for the iOS manual-discard UX per founder direction — **first-run explainer, then a lightweight confirm** — and that manual Discard is now exposed on iOS (mark-as-lost sheet + long-press).

**Step — Commit** (bible edits separate from code if a sibling holds bible WIP — check `git -C ops-software-bible status` first; stage by name). `git commit -m "docs(leads): reconcile discard — operator-settable on iOS, iOS confirm UX"`

---

## Task 9: Verification & proof

**Skills:** `custom-skills:audit-design-system`, `custom-skills:wizard-audit`.

1. **Build clean:** `xcodebuild -scheme OPS -destination 'generic/platform=iOS' -clonedSourcePackagesDirPath .spm-local build` → BUILD SUCCEEDED.
2. **Design-system audit:** run `audit-design-system` over the three new/changed views → zero hardcoded color/spacing/radius/font; every value traces to `OPSStyle`.
3. **Simulator behavioral proof** (screenshots → `docs/artifacts/`):
   - Long-press open lead → Edit/Archive/**Discard**; long-press closed lead → no Discard.
   - First discard → explainer; confirm → lead leaves triage + `// LEAD DISCARDED` toast.
   - Second discard → quick confirm dialog (asserts `leads_discard_explainer_seen` persisted).
   - Lost sheet → "Discard instead" link → same flow, both sheets dismiss.
4. **DB proof (read-only, a test/sandbox company — never prod customer data):** after a simulated discard, confirm `opportunities.stage='discarded'` and a fresh `stage_transitions` row with `to_stage='discarded'`. Use Supabase MCP `execute_sql` (SELECT only).
5. **Snapshot proof:** `DiscardExplainerSheet` + updated `LostReasonSheet` footer PNGs attached.
6. Delete throwaway artifacts once proof is delivered; keep the snapshot references.

**Definition of done:** device build clean, design audit clean, all four behavioral proofs captured, DB shows `stage=discarded` + audit row, buried Delete gone, bible reconciled. Then `finishing-a-development-branch` to decide merge (iOS ships via App Store — no auto-deploy; merge to `main` needs Jackson's go).

---

## Out of scope
- Discarded-leads review/restore screen on iOS (quick-confirm gate makes accidental discard unlikely; recovery is a stage-move by a `pipeline.manage` operator).
- Reclassifying an already-lost lead to discarded (Discard is offered on open leads only).
- Any change to `move_opportunity_stage`, RLS, the `opportunities` schema, or the repo `softDelete` method.
- Web changes (web already carries the `discarded` stage).
