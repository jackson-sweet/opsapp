# Site-Visit Form Overhaul Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use custom-skills:executing-plans to implement this plan task-by-task.

**Goal:** Fix the six reported defects in the site-visit capture flow: dead lead search, missing phone-contact import, invisible required fields, non-sequential layout, forced lead→WON conversion on completion, and the full-width success toast.

**Architecture:** All changes stay in the view layer + one repository call and one view-model exit path. The identity panel becomes step 1 of a visibly sequential form (required markers per field group); the type-dependent checklist is step 2. The review sheet gains a SAVE VISIT exit (completes the visit, defaults the lead's stage to QUALIFYING via a user-editable stage row, no conversion) alongside the existing CREATE PROJECT exit. Lead search swaps its empty SwiftData fetch for the network `OpportunityRepository.fetchAll()`. The toast banner becomes content-hugging.

**Tech Stack:** SwiftUI, SwiftData (visit artifacts), Supabase via `OpportunityRepository`, ContactsUI (`ContactPicker`).

**Design System:** `OPS/Styles/OPSStyle.swift` (iOS token source). No hardcoded color/spacing/radius/font values.

**Required Skills:** `custom-skills:mobile-ux-design` (loaded), `ops-copywriter` register for all new labels (terse tactical, UPPERCASE authority), `custom-skills:audit-design-system` before done.

**Pinned APIs (verified):**
- `OpportunityRepository(companyId:).fetchAll() async throws -> [OpportunityDTO]`; `dto.toModel() -> Opportunity` — [OpportunityRepository.swift:25](OPS/Network/Supabase/Repositories/OpportunityRepository.swift)
- `repo.moveToStage(opportunityId:to:userId:) async throws -> OpportunityDTO` — line 166
- `ContactPicker(onContactSelected: (CNContact) -> Void, onDismiss: (() -> Void)?)` — [ContactPicker.swift:11](OPS/Views/Components/Contact/ContactPicker.swift)
- `PipelineStage` cases: newLead, qualifying, quoting, quoted, followUp, negotiation, won, lost, discarded
- Line endings: `SiteVisitCaptureView.swift`, `SiteVisitCaptureViewModel.swift`, `Toast.swift`, `FloatingActionMenu.swift` — **check each with `rg -c $'\r$'` before editing; use python-CRLF edits for any full-CRLF file.**

---

### Task 1: Toast becomes a content-hugging pill

**Files:**
- Modify: `OPS/Styles/Components/Toast.swift` (ToastBanner body, ~line 260; ToastHostView ~line 214)
- Test: `OPSTests/Views/CameraUnificationSnapshotTests.swift` pattern → new `ToastPillSnapshotTests.swift`

**Design tokens:** `OPSStyle.Layout.spacing3` margins, `modalRadius`, `.glassDense()`, tone `*TextM/*LineM` colors — all already in file.

**Step 1:** Snapshot test rendering `ToastBanner` (via ToastHostView with a seeded `ToastCenter.shared.present`) for (a) short label "// VISIT SAVED", (b) long label with action "// LEAD WON · PROJECT CREATED" + VIEW. Assert nothing; PNG proof.
**Step 2:** In `ToastBanner.body`, replace `.frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)` with `.frame(minHeight: 44)` + `.fixedSize(horizontal: false, vertical: true)`; wrap host placement so the pill centers: in `ToastHostView`, the VStack already centers children — add `.frame(maxWidth: .infinity, alignment: .center)` on the banner container and keep `.padding(.horizontal, spacing3)` as the max-width bound. Label gets `.lineLimit(2)`.
**Step 3:** Re-run snapshot; verify pill hugs content, centered, both variants.
**Step 4:** Commit `fix(toast): success pill hugs its content instead of stretching full width`.

### Task 2: Lead search actually searches leads (network) + phone-contact import

**Files:**
- Modify: `OPS/Views/SiteVisits/SiteVisitCaptureView.swift` — `SiteVisitIdentityPanel.loadSearchSources()` (~1416), `searchField` (~1118), body `.task` (~1056)

**Step 1:** Replace the SwiftData `FetchDescriptor<Opportunity>` in `loadSearchSources()` with async network load: `let repo = OpportunityRepository(companyId: viewModel.companyIdentifier); let dtos = (try? await repo.fetchAll()) ?? []; activeLeads = dtos.map { $0.toModel() }.filter { !$0.stage.isTerminal && !$0.isDeleted && !$0.isArchived }`. Keep the client SwiftData fetch. Make `loadSearchSources()` `async`; call from `.task { await loadSearchSources(); syncFromDraft() }` and after lead-create in `footer`. Cache last result in `@State` so typing stays instant (filtering is already local over `activeLeads`).
**Step 2:** Offline fallback: on network failure keep whatever SwiftData returns (current behavior) — `if activeLeads.isEmpty { /* existing local fetch as fallback */ }`.
**Step 3:** Add an IMPORT FROM CONTACTS row under the search field (visible only when unbound): `Button` styled like `suggestionRow` (tokens: `surfaceInput` fill, `line` border, `buttonRadius`), label `IMPORT FROM PHONE CONTACTS`, icon `person.crop.circle.badge.plus`, 44pt min height. Presents `.sheet { ContactPicker(onContactSelected: applyContact) }`. `applyContact(_ contact: CNContact)`: map `givenName/familyName → contactName`, `organizationName → clientName`, first email → `preferredEmail`, first phone → `phoneNumber`, postal address (formatted single line) → `address`; then `commitDraft()`.
**Step 4:** Device-build; snapshot of the identity panel with the import row.
**Step 5:** Commit `fix(site-visits): lead search hits the network store + contacts import`.

### Task 3: Required-field markers on the identity form

**Files:**
- Modify: `SiteVisitCaptureView.swift` — `identityField(...)` (~1297), panel body (~972)

**Required set (matches existing `isComplete`):** NAME (or COMPANY), EMAIL **or** PHONE, ADDRESS.

**Step 1:** Extend `identityField` with `requirement: IdentityFieldRequirement = .optional` (`enum: .required, .requiredGroup(String), .optional`) and a trailing status: REQUIRED in `tanTextM` / DONE checkmark in `oliveTextM` (mirror `SiteVisitChecklistAnswerRow.statusLabel/statusColor` so both halves of the form speak one language). Satisfied = that field (or its group partner) non-empty.
**Step 2:** Mark NAME + COMPANY as one group ("NAME OR COMPANY"), EMAIL + PHONE as one group ("EMAIL OR PHONE"), ADDRESS required. CLIENT NOTES / OTHER EMAILS stay optional (no marker).
**Step 3:** Snapshot: empty form (three REQUIRED markers visible) vs filled form (DONE ticks).
**Step 4:** Commit `feat(site-visits): required-field states on the lead form`.

### Task 4: Sequential checklist layout

**Files:**
- Modify: `SiteVisitCaptureView.swift` — main body (~123-151), `statusStrip` (~400), `checklistPanel` (~568), `SiteVisitIdentityPanel.header` (~1074)

**Step 1:** Reorder scroll content: `SiteVisitIdentityPanel` first, `checklistPanel` second, `quickNotePanel` third, `packetPanel` last; `statusStrip` folds into the header area (or drops — its counts already live in the panels; decide by snapshot).
**Step 2:** Step headers: identity panel header becomes `// 1 · LEAD` + trailing `REQUIRED` chip (tanTextM until complete, then olive DONE); checklist panel header `// 2 · <TYPE> CHECKLIST` + its existing progress `N/M`; notes `// 3 · NOTES`; packet unchanged pattern. Use the existing `panelHeader(_:trailing:)` helper.
**Step 3:** Auto-collapse identity to `collapsedSummary` when complete AND bound (existing behavior keeps working); first incomplete step scrolls into view on open.
**Step 4:** Snapshots: fresh visit (step 1 expanded, REQUIRED chips), mid visit (step 1 collapsed-done, step 2 active).
**Step 5:** Commit `feat(site-visits): sequential numbered form — lead first, type checklist second`.

### Task 5: SAVE VISIT exit — no forced conversion; stage defaults to QUALIFYING

**Files:**
- Modify: `SiteVisitCaptureView.swift` — `SiteVisitReviewSheet` (~1809-2110)
- Modify: `SiteVisitCaptureViewModel.swift` — add `saveVisitWithoutConversion(stage:) async -> Bool`
- Modify (only if needed for dismiss wiring): the three `onCreateProject` parents

**Step 1 (pure logic + test):** `SiteVisitStageDefault.defaultStage(current:) -> PipelineStage` — newLead → .qualifying; qualifying/quoting/quoted/followUp/negotiation → unchanged; terminal → unchanged. Unit-test all cases first (new `OPSTests/Views/SiteVisitStageDefaultTests.swift`).
**Step 2:** Review sheet gains a stage row above the footer: `// LEAD STAGE AFTER VISIT` + horizontal stage chips (non-terminal stages only; selected = `surfaceActive` fill + `line` border, 44pt; JetBrains mono labels), preseeded from `SiteVisitStageDefault.defaultStage(current:)`. Chips only render when a lead is bound.
**Step 3:** VM: `saveVisitWithoutConversion(stage:)` = `completeVisit()` + `postSiteVisitActivityIfNeeded` (existing call path) + if bound lead && stage != current → `OpportunityRepository.moveToStage(...)` (offline: queue failure tolerated — toast still confirms visit save, stage change reported failed via errorToast).
**Step 4:** Footer: primary = `SAVE VISIT` (runs Step 3, dismisses capture flow entirely, presents `Toast("// VISIT SAVED", tone: .success)`); secondary = `CREATE PROJECT` (existing `createProject()` path — conversion stays explicit and user-chosen). BACK remains as the header/leading affordance per `SheetFooterButtonRow` capacity — verify with `custom-skills:mobile-ux-design` one-handed reach.
**Step 5:** Parents: `onCreateProject` unchanged. Add `onSaved` closure (dismiss capture cover; no convert sheet). Wire in FloatingActionMenu, LeadDetailView, LeadsTabView.
**Step 6:** Snapshots: review sheet with stage row (QUALIFYING preselected), both CTAs visible.
**Step 7:** Commit `feat(site-visits): SAVE VISIT completes without conversion; stage defaults to qualifying`.

### Task 6: Deck EDIT opens the linked design

**Files:**
- Modify: `SiteVisitCaptureView.swift` — `startDeckDesign()` (~813) gains `preferredDesignId: String? = nil`; checklist row EDIT passes `answer.answerValue.deckDesignId`
- Modify: `OPS/Views/SiteVisits/SiteVisitDeckDesignResolver.swift` — new first-priority parameter `preferredDesignId`
- Test: extend existing resolver tests (find via `rg -l SiteVisitDeckDesignResolver OPSTests`)

**Step 1 (test first):** resolver returns the design matching `preferredDesignId` (canonicalized) when it exists un-deleted, before artifact/lead fallbacks; falls through when missing.
**Step 2:** Implement resolver change + thread the answer's id through the EDIT button (`onStartDeckDesign` closure gains the id).
**Step 3:** Diagnose-blank followup: after resolver fix, reproduce EDIT with a design whose id resolves but `drawingData` is empty — if `DeckBuilderViewModel` hydration is the true cause (design row present, geometry blank), fix there (read `DeckBuilderViewModel.init` load path). Evidence gate: log the resolved design id + vertex count at open.
**Step 4:** Commit `fix(site-visits): checklist EDIT opens the design linked to that row`.

### Task 7: Verify + close out

**Step 1:** `pgrep xcodebuild` guard → device build with worktree `-derivedDataPath .dd-local -clonedSourcePackagesDirPath .spm-local`.
**Step 2:** Simulator run: all new/updated unit tests + snapshot suites; extract PNGs to `docs/artifacts/site-visit-overhaul/`.
**Step 3:** `custom-skills:audit-design-system` over the diff (zero hardcoded values).
**Step 4:** Bible: update `ops-software-bible/07_SPECIALIZED_FEATURES.md` site-visit flow (save-vs-convert exits, stage default) — hunk-stage only my lines (sibling WIP present).
**Step 5:** Report to Jackson with before/after PNGs. No bug_reports row exists for this report (verified) — chat report only.
