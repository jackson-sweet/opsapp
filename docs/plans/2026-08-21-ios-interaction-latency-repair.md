# iOS Interaction Latency Repair

> Execution: use `custom-skills:executing-plans`; regression contracts are written before production changes.

## Outcome

Calendar entry and week navigation must never wait on SwiftData work, a tab tap must expose its destination immediately, and Deck Designer edits must persist locally without producing cloud work until the editor is exited.

## Product and design boundary

- **Human:** a trades owner using OPS between job sites, often one-handed and in poor connectivity.
- **Job:** move between operational areas, scan another week, and edit a deck without waiting for storage or networking.
- **Feel:** immediate, stable, and decisive.
- **Palette / depth / surfaces / typography / spacing:** unchanged. Existing `OPSStyle` and the mobile design system remain authoritative.
- **Motion:** keep the tab bar's pressed and active-indicator feedback, but do not animate entire retained screen trees during primary-tab selection. The content destination changes immediately.

## Task 1 — Calendar snapshot contract

**Files:**
- Modify: `OPS/Utilities/CalendarScheduleSnapshot.swift`
- Modify: `OPS/Utilities/DataActor+CalendarGrid.swift`
- Modify: `OPS/ViewModels/CalendarViewModel.swift`
- Test: `OPSTests/CalendarGridDataActorTests.swift`
- Add or modify: focused calendar view-model tests under `OPSTests/`

1. Add failing tests for a date-bounded 21-day actor snapshot and cache coverage across adjacent-week navigation.
2. Make the actor query only records that can overlap the snapshot window.
3. Replace synchronous initial/navigation rebuilds with one cancellable async reload.
4. Publish `selectedDate` immediately; use an existing snapshot whenever it covers the requested week, and prefetch the next window in the background.
5. Remove the rendering-time SwiftData fallback from `scheduledTasks(for:)`.
6. Cancel stale work and discard out-of-date results.

## Task 2 — Immediate primary-tab switching

**Files:**
- Modify: `OPS/Views/Components/Common/KeepAliveTabContainer.swift`
- Modify: `OPS/Views/Components/Common/CustomTabBar.swift`
- Modify if needed: `OPS/Views/MainTabView.swift`
- Test: `OPSTests/Views/KeepAliveTabContainerTests.swift`

1. Add a regression contract proving the selected retained slot is the only interactive/visible destination without a full-screen transition.
2. Keep mounted tab roots alive, but make slot visibility and hit-testing switch without implicit animation.
3. Remove the broad selection animation around the tab binding.
4. Preserve the tab bar's tokenized 200ms indicator feedback and immediate touch-down acknowledgement.

## Task 3 — Local edit session, one exit sync

**Files:**
- Modify: `OPS/DeckBuilder/DeckBuilderViewModel.swift`
- Modify: the Deck Builder host view containing close/disappear/scene-phase hooks
- Modify if needed: `OPS/Network/Sync/SyncEngine.swift`
- Test: `OPSTests/DeckBuilder/DeckBuilderRegressionTests.swift`
- Test: `OPSTests/Network/DeckDesignSyncTests.swift`
- Test: `OPSTests/Sync/DeckDesignLinkSyncTests.swift`

1. Add failing tests proving repeated `save()` calls persist local drawing state and create zero sync operations while editing.
2. Add failing tests proving the exit boundary enqueues only the latest revision once, even when close and `onDisappear` both fire; backgrounding with the editor still open remains local-only.
3. Make `save()` local-only and remove the initializer's eager sync.
4. Track local drawing revisions and the most recently queued revision.
5. On interruption, flush locally only. At the actual exit boundary, record the latest payload with deferred push, then trigger background sync after dismissal.
6. Keep thumbnail rendering/upload after the editor boundary and avoid duplicating the final design operation.

## Task 4 — Documentation and proof

**Files:**
- Modify: `ops-software-bible/02_USER_EXPERIENCE_AND_WORKFLOWS.md`
- Modify: `ops-software-bible/06_TECHNICAL_ARCHITECTURE.md`

1. Document the calendar snapshot window and no-render-fetch rule.
2. Document immediate tab content switching with retained tab state.
3. Document Deck Designer's local edit-session and exit-sync boundary.
4. Run the focused calendar, tab, and deck regression suites.
5. Run one clean generic-iOS build using worktree-local package and DerivedData paths.
6. Review only touched files for design tokens, concurrency safety, duplicate sync paths, and unrelated changes; make one atomic local commit.

## Acceptance evidence

- Calendar navigation contains no synchronous SwiftData fetch on the main actor.
- `scheduledTasks(for:)` is cache-only.
- A tab selection changes the active retained screen without a screen-wide transition.
- Deck editing and app interruption create no `SyncOperation`; actual editor exit creates one current operation per drawing revision.
- Focused tests pass and the generic iOS build succeeds.
- Real-device acceptance remains required before calling the customer-facing lag fixed.
