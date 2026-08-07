# Lead Deck Save and Title Repair Implementation Plan

> **For implementation:** Use `custom-skills:executing-plans` task-by-task.

**Goal:** Closing a saved lead deck returns to the lead immediately, while the persisted design and every lead-owned deck surface use the lead address as the title.

**Architecture:** Keep drawing persistence and durable sync-queue recording on the synchronous close path. Move optional thumbnail rendering/upload into follow-up work that cannot delay dismissal. Centralize lead deck naming as an address-first policy and feed it into creation plus every lead-owned deck display boundary.

**Tech Stack:** SwiftUI, SwiftData, XCTest, existing `SyncEngine`, existing presigned upload service.

**Design System:** `OPS/Styles/OPSStyle.swift` (no visual-token changes).

**Required Skills:** `superpowers:systematic-debugging`, `superpowers:test-driven-development`, `superpowers:verification-before-completion`, `custom-skills:mobile-ux-design`, `custom-skills:ops-design`, `custom-skills:audit-design-system`, `ops-copywriter:ops-copywriter`.

---

### Task 1: Lock the close-save contract with a failing test

**Skills:** `superpowers:test-driven-development`

**Files:**
- Modify: `OPSTests/DeckBuilder/DeckBuilderRegressionTests.swift`
- Modify: `OPS/DeckBuilder/DeckBuilderViewModel.swift`
- Modify: `OPS/DeckBuilder/Views/DeckBuilderView.swift`

1. Add a test with an injected thumbnail renderer/uploader whose upload remains suspended.
2. Assert the new exit-save entry point persists drawing data and returns a follow-up task before that uploader completes.
3. Run the focused test and confirm it fails because the non-blocking API is not implemented.
4. Add the smallest injectable thumbnail boundaries and synchronous exit-save entry point.
5. Make the close button start the follow-up work and dismiss without awaiting it.
6. Release the suspended uploader and assert the thumbnail URL is saved afterward.

### Task 2: Lock the lead-address title contract with failing tests

**Skills:** `superpowers:test-driven-development`, `custom-skills:mobile-ux-design`, `ops-copywriter:ops-copywriter`

**Files:**
- Create: `OPSTests/DeckBuilder/LeadDeckTitlePolicyTests.swift`
- Create: `OPS/DeckBuilder/Models/LeadDeckTitlePolicy.swift`
- Modify: `OPS/DeckBuilder/Views/CreationPickerView.swift`
- Modify: `OPS/DeckBuilder/Views/TemplatePickerView.swift`
- Modify: `OPS/Views/Leads/LeadDetailView.swift`
- Modify: `OPS/Views/Leads/Components/LeadDeckScreen.swift`
- Modify: `OPS/Views/Leads/Components/LeadDeckSection.swift`
- Modify: `OPS/Views/Leads/DaySheet/DaySheetLeadCard.swift`
- Modify: `OPS/Views/Leads/DaySheet/LeadDeckPanel.swift`
- Modify: `OPS/Views/Components/Project/Tabs/DeckTabView.swift`
- Modify: `OPS/Views/Leads/DaySheet/LeadDaySheetView.swift`
- Modify: `OPS/Views/Leads/LeadsTabView.swift`
- Modify: `OPS/Views/SiteVisits/SiteVisitCaptureViewModel.swift`

1. Add literal tests proving a trimmed lead address wins and a missing/blank address preserves the supplied fallback.
2. Run the focused test and confirm the missing policy fails.
3. Implement the pure address-first title policy.
4. Pass the address into lead creation so blank, template, recent-copy, scan, and AR paths persist it.
5. Use the same resolved title for the lead deck rows/panels, tab, pushed screen, fullscreen viewer, builder header, and bound-site-visit creation path.
6. Audit the changed UI against the OPS design system, then run both focused suites.

### Task 3: Document and verify the customer-visible contract

**Skills:** `superpowers:verification-before-completion`

**Files:**
- Modify: `../ops-software-bible/03_DATA_ARCHITECTURE.md`

1. Record that lead deck exit persists locally and queues sync before dismissal, while thumbnail upload is non-blocking.
2. Record that lead-owned deck titles resolve to the trimmed lead address with the existing safe fallback when no address exists.
3. Run focused deck regression and title tests on `iPhone 17, iOS 26.5`.
4. Run a generic iOS device build.
5. Inspect the final diff, stage only named files, and commit atomically without pushing.
