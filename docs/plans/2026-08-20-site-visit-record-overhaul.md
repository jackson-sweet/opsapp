# Site Visit Record Overhaul Implementation Plan

> **For Codex:** REQUIRED SUB-SKILL: Use `custom-skills:executing-plans` to implement this plan task-by-task.

**Goal:** Make every completed site visit read as one clear field record that names the recorder, loads its photos, and opens the linked deck without exposing machine identifiers.

**Architecture:** Keep `SiteVisitRecord` as the single presentation model and remove the lead-side duplicate sheet. Resolve recorder identity from `SiteVisit.createdBy`, normalize photo display URLs before the shared view receives them, and preserve the deck ID only as internal navigation state for one explicit open action.

**Tech Stack:** Swift 6, SwiftUI, SwiftData, XCTest, OPS design tokens.

**Design System:** `/Users/jacksonsweet/Projects/OPS/ops-design-system/project/DESIGN.md` and `/Users/jacksonsweet/Projects/OPS/ops-design-system/project/mobile/MOBILE.md`; implementation tokens in `OPS/Styles/OPSStyle.swift`.

**Required Skills:** `superpowers:test-driven-development`, `superpowers:systematic-debugging`, `custom-skills:interface-design`, `custom-skills:mobile-ux-design`, `custom-skills:ops-design`, `ops-copywriter:ops-copywriter`, `custom-skills:audit-design-system`, `supabase:supabase`, `superpowers:verification-before-completion`.

---

### Task 1: Lock the record contract with failing tests

**Skills:** `superpowers:test-driven-development`, `ops-copywriter:ops-copywriter`.

**Files:**
- Modify: `OPSTests/SiteVisits/SiteVisitRecordChecklistTests.swift`
- Modify: `OPSTests/SiteVisits/SiteVisitRecordLocalCaptureTests.swift`
- Modify: `OPSTests/SiteVisits/SiteVisitHandoffDurabilityTests.swift`
- Modify: `OPSTests/Views/SiteVisitRecordSnapshotTests.swift`

**Design tokens:** No visual implementation in this task.

1. Assert a deck checklist answer never places its UUID in display copy.
2. Assert `SiteVisitRecord` retains the internal deck ID while omitting the duplicate deck checklist row.
3. Assert handoff artifacts and the record use the visit recorder rather than the later conversion actor.
4. Assert the photo resolver prefers rendered media and preserves source fallback.
5. Run only the focused test classes and confirm the new assertions fail for the intended reasons.

### Task 2: Repair the shared presentation model

**Skills:** `superpowers:test-driven-development`, `custom-skills:interface-design`.

**Files:**
- Modify: `OPS/DataModels/SiteVisits/SiteVisitRecord.swift`
- Modify: `OPS/DataModels/SiteVisits/SiteVisitCaptureArtifact.swift`
- Modify: `OPS/Views/SiteVisits/SiteVisitProjectHandoff.swift`
- Modify: `OPS/Views/SiteVisits/SiteVisitCaptureViewModel.swift`

**Design tokens:** N/A; this is model and attribution work.

1. Carry the recorder ID through the local payload and use it for generated project records, with legacy fallback to the conversion actor.
2. Keep `deckDesignId` internal to `SiteVisitRecord` and exclude deck-design answers from the visible checklist.
3. Replace legacy deck checklist copy with `DESIGN LINKED` while retaining the UUID in the dedicated metadata field.
4. Add a pure photo display resolver that selects rendered media first and raw media second.
5. Re-run the focused model tests until green.

### Task 3: Replace the duplicated lead sheet with the shared record

**Skills:** `custom-skills:interface-design`, `custom-skills:mobile-ux-design`, `ops-copywriter:ops-copywriter`.

**Files:**
- Modify: `OPS/Views/Leads/DaySheet/LeadSiteVisitPanel.swift`
- Modify: `OPS/Views/Leads/Components/ActivityTimeline.swift`
- Modify: `OPS/Views/Components/Project/Tabs/SiteVisitPacketEntryView.swift`

**Design tokens:** `OPSStyle.Layout.spacing*`, `OPSStyle.Layout.touchTarget*`, `OPSStyle.Colors.*`, and `OPSStyle.Typography.*` only.

1. Resolve the team member from `SiteVisit.createdBy` on lead and project surfaces.
2. Route lead/day-sheet and activity-timeline sheets through `SiteVisitRecordView`.
3. Pass local or normalized remote photo URLs into the shared photo rail and viewer.
4. Resolve the linked `DeckDesign` by the internal ID and present `DeckBuilderView` from the record sheet.
5. Delete the now-unused lead-only record sheet and local-only thumbnail loader.

### Task 4: Establish clear mobile hierarchy and a real deck action

**Skills:** `custom-skills:ops-design`, `custom-skills:interface-design`, `custom-skills:mobile-ux-design`, `ops-copywriter:ops-copywriter`.

**Files:**
- Modify: `OPS/Views/SiteVisits/SiteVisitRecordView.swift`
- Modify: `OPSTests/Views/SiteVisitRecordSnapshotTests.swift`

**Design tokens:** `OPSStyle.Typography.section`, `panelTitle`, `bodyBold`, `smallCaption`, `miniLabel`; `OPSStyle.Colors.text`, `text2`, `text3`, `lineSoft`, `opsAccent`; tokenized spacing/radii/borders and `OPSButtonStyle.Primary`.

1. Use `// FIELD RECORD` as the document eyebrow, `SITE VISIT` as the only screen title, and move the person into a labeled `RECORDED BY` block.
2. Give photo evidence and visit details distinct section titles; keep individual field labels subordinate to values.
3. Replace the inert deck status row with the glove-friendly `OPEN DECK DESIGN` button.
4. Keep the deck ID out of all visible and accessibility strings.
5. Render the iPhone snapshot and inspect title, metadata, section, field, and action hierarchy.

### Task 5: Reconcile documentation and prove completion

**Skills:** `custom-skills:audit-design-system`, `supabase:supabase`, `superpowers:verification-before-completion`.

**Files:**
- Modify: `ops-software-bible/03_DATA_ARCHITECTURE.md` in its own clean checkout if required.

**Design tokens:** Audit for zero new hardcoded styling values.

1. Verify live `site_visits`, `project_photos`, `project_notes`, and `deck_designs` schema fields used by the repair; do not mutate production data.
2. Update the Bible contract for recorder attribution, photo URL precedence, and deck navigation.
3. Run the focused tests, relevant iOS build/test suite, and snapshot harness in worktree-local build/package paths.
4. Inspect the generated PNG and audit Dynamic Type, accessibility labels, touch targets, and token use.
5. Commit the iOS change and Bible update atomically; do not push or release.
