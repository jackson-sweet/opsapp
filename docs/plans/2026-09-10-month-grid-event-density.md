# Month Grid Event Density Implementation Plan

**Goal:** Restore visible month event density without shrinking independent mobile touch targets.

**Architecture:** One token-backed geometry value controls planner capacity and rendered rows. Below the existing 180pt expanded threshold, event bars are visual previews and the full day cell owns interaction and VoiceOver summary. Expanded event controls retain 44pt rows. Weekly clipping is extracted unchanged into the planner candidate so week-boundary visibility can be tested.

**Tech Stack:** SwiftUI, XCTest. iOS 17.6 compatible.

**Design System:** `/Users/jacksonsweet/Projects/OPS/ops-design-system/project/DESIGN.md` and `mobile/MOBILE.md`; `OPSStyle.Layout` calendar, spacing, and touch-target tokens.

**Required Skills:** systematic-debugging, writing-plans, executing-plans, ops-design, mobile-ux-design, interface-design, ui-ux-pro-max, ops-copywriter, audit-design-system, test-driven-development, verification-before-completion.

1. Add focused regression cases in `OPSTests/MonthGridEventSlotPlannerTests.swift`: three/five visible events at default height, exact overflow, compact minimum height, full-size expanded actions, week-boundary continuation, and collision/count invariants across all supported heights.
2. Share row geometry between `MonthGridEventSlotPlanner`, `EventBar`, and overflow indicators in `OPS/Views/Calendar Tab/MonthGridView.swift`. Keep task-cache/filter semantics and expanded action code unchanged.
3. Route overview interaction through the full day cell, with complete event titles available to VoiceOver. Keep the day-detail/scope badge/holiday/site-visit regions unchanged. Pass the visible week dates to expanded bar interactions and cover week-2 continuation day routing through the shared resolver.
4. Run source-only checks and inspect the exact diff. Parent owns the build baton: no Xcode, simulator, or Swift package build/test in this subtask. Explicitly mark XCTest and visual/runtime proof pending.
5. Commit only these owned implementation/test files and this plan. Provide a draft Bible note for the parent; do not edit shared Bible or integrate main.
