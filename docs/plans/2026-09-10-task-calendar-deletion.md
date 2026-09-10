# Task calendar deletion repair

**Goal:** Prevent deleted tasks from looking scheduled or accepting ordinary edits; preserve refused schedules and intentional offline restoration.
**Architecture:** One live-task presentation filter, guarded durable schedule writes, conservative shared reconciliation used by both outbound drivers. No server policy or business-record change.
**Tech Stack:** SwiftUI, SwiftData, existing Supabase task RPCs and SyncEngine.
**Design System:** `../ops-design-system/project/DESIGN.md`, `mobile/MOBILE.md`, existing `OPSStyle` components.
**Required Skills:** systematic-debugging, writing-plans, executing-plans, test-driven-development, ops-design, ops-copywriter, audit-design-system, verification-before-completion.

## Evidence established before implementation

Read-only phone database copy passed SQLite quick_check. Exact task `21a203b6-a74e-48b4-8a90-6aa464f5e9d8` occurs once and retains `deletedAt=2026-08-13T21:54:33Z`. Its local September 10 dates are absent on the server. Retained queue contains August 13 delete and September 9/10 schedule updates; no restore. The phone runs 3.0.5, which alone does not identify its compiled commit. Both glass tasks remain linked to the correct local project. Raw database remains in session scratch only.

## Execution

1. Add failing regression tests for deleted-task permission gates, schedule rejection without mutation/outbox, and schedule-bearing terminal rejection preservation. Run only this vertical, serially.
2. Filter project detail task list, selector, previous/next navigation, completion calculations and index recalculation through the same nondeleted relationship projection. Guard ordinary task mutations including stale retained references. Keep completed and cancelled live tasks visible.
3. Move updateTaskSchedule to the existing durable model/outbox transaction. Test rollback on queue failure, active offline scheduling, and explicit Trash restore followed by scheduling. Preserve restore/create ordering through coalescing and backoff.
4. Recognize zero-row task update errors in both outbound drivers. Empty authenticated reads are ambiguous and must not resolve pending work or infer deletion. Preserve rejected schedules through the local tombstone settlement sweep, including duplicate/foreign identities and pending restores. Add clear local pending date indication using existing text tokens.
5. Run focused simulator tests and generic iOS build serially, inspect UI proof, then commit code and update Bible chapters 03/07 with evidence and release limits. No push, release, server changes, live restoration, or notifications are authorized.

## Verification scope

Deleted / active / completed / cancelled; stale parent relationships; duplicate local identity safety; deleted schedule guard; failed atomic queue save; restore then schedule; unresolved create/restore; reconnect and ambiguous server invisibility; existing task RPC split and calendar exclusion. Device database evidence proves the reported chain, not execution of the repaired binary on the phone.

## Implemented refinements from review

Nullable date clears share the durable transaction, and linked parent cache changes roll back with it. Schedule displays read computed live-task dates including nil, which survives a stale server project refresh without a project write. An open deleted-task selection is dismissed; delayed type-change confirmation does not pre-save edits. Full details, popup and project list all retain the pending label. The test fixture uses synthetic identities, an offline sync engine and container ownership through async teardown.

Final focused simulator run: 155 passed, zero failures or skips; production popup and task-list snapshots inspected. Independent review found no remaining important finding. Build/release boundary and the final iPhone build result are recorded in `../artifacts/calendar-discrepancy-20260910/findings.md`.
