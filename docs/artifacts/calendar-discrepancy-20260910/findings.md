# Deleted task shown as scheduled — September 10, 2026

## Outcome and release boundary

Local iOS repair for a deleted task still shown as TODAY in project details while absent from the calendars. No web change was needed: its live task/scheduled task queries already exclude deleted rows. No live task restoration, reschedule, database migration, policy change, publication, push, device installation, or iOS release was performed.

## Exact evidence

- Canpro company `a612edc0-5c18-4c4d-af97-55b9410dd077`, timezone `America/Vancouver`.
- Erin Young project “541 Prince Robert Ln”, `a0636b77-3545-43fb-b94b-5d95feff74e1`, is live.
- Glass Rail Install `21a203b6-a74e-48b4-8a90-6aa464f5e9d8`: server `deleted_at=2026-08-13T21:54:33Z`, status active, start/end NULL. No live replacement was found in that project.
- Glass Install `0fdd921b-489f-4bfd-aaef-10ce1009c8af`: server `deleted_at=2026-08-13T21:54:30Z`, start/end NULL.
- Reporting screenshot shows both deleted tasks as normal rows and Glass Rail Install as TODAY.
- A read-only copy of the paired iPhone's App Group SwiftData store plus WAL passed SQLite `quick_check`. Each exact task identity appears once and remains linked to the correct project. The phone retains the same August tombstones; this was not an unknown remote deletion or a duplicate-row hypothesis.
- The phone's Glass Rail Install start/end are `2026-09-10T06:00:00Z`, `needsSync=1`, `scheduleLocked=1`. The retained September 10 schedule operation `dbbdc2df-c314-4f60-86b9-795b5f9e402e` was created at `16:17:22.912Z` and marked completed at `16:19:07.656Z`. Its payload contains those dates, duration 1 and the manual schedule lock. The server still has no dates. Older retained September 9 schedule attempts contain `2026-09-10T07:00:00Z`. No restore operation was retained for either glass task.
- Installed app version/build is `3.0.5/3.0.5`; that does not identify its compiled commit. A cleared original error and absent confirmation timestamp do not uniquely prove which historical completion path ran. The pre-fix local settlement code can retire this exact rejected-schedule shape. The source audit also found a details-screen path that treated queueing as server success.
- Live read policy `private.user_can_view_task_columns` hides tombstones. An authenticated empty read cannot distinguish deletion from lost scope/parent visibility. Current iOS source already routes deletion/restoration through the guarded RPCs (local commit `5b254437`). No policy relaxation was needed.

Raw phone data and broad device inventories remain in session scratch, outside version control. This report includes only evidence relevant to the repair. Original deletion actor is not established.

## Repair

- Normal project task lists, selection, navigation, timeline and progress decisions use a shared live identity projection. Completed and cancelled live tasks remain visible. Deleted or wrong-owner relationships and stale live duplicates cannot expose a deleted identity.
- Permission affordances and ordinary controller writes reject a deleted task or parent. Open selections/sheets are cleared on deletion; delayed type changes no longer mutate/save before the guard.
- Schedule changes and nullable clears save task state and its outbox operation in one transaction. Failed staging rolls both back. Dates remain marked NOT SYNCED until confirmed with no other unresolved task edit; acknowledgement clearing is company scoped.
- Delete, restore and later edits retain chronological intent through coalescing. A parked restore continues to hold subsequent edits. Neither empty server reads nor the old local settlement sweep can silently complete a rejected schedule.
- Project schedule displays use live task dates including nil, so a stale project DTO cannot resurrect a cleared date through a cache fallback. A local parent cache refresh never creates a project write from a potentially incomplete, permission-filtered task list.
- Task reschedule notifications require a live task with no outstanding local changes after flush. Ordinary UI keeps the existing design tokens and adds a compact pending label next to dates.

Historical operations already marked completed by an older app are not automatically replayed. Restoring a business task remains an explicit operator decision.

## Verification

Initial red test run reproduced all six targeted defects: 6 failed tests / 16 assertion failures, zero unexpected failures. After the first repair, all 14 new regression tests passed; one older dispatch test required updating because zero-row task updates now correctly enter conservative task reconciliation.

Final focused run: **155 passed, 0 failed, 0 skipped** on the isolated iPhone 17 / iOS 26.5 simulator. This includes 21 new calendar/deletion regressions, existing RPC/Trash/permission/queue/scheduling/copy/card-model coverage and the production UI snapshot test. `ops-calendar-deletion-verified.xcresult` independently reports `Passed` / `totalTestCount=155`.

An intermediate expanded run exposed the stale server-date fallback and a fixture lifetime trap; both were corrected. The fixture now retains every SwiftData container through async sync-engine shutdown, using the existing `SiteVisitLeadCaptureTests` pattern. The final run had no unexpected exit.

Independent code review: no remaining important finding after fixing nullable clears, deleted-task spans, stale type-change commits, full-details pending copy, company scoping and stale project DTO replay. New UI values use existing OPSStyle tokens; both screenshots were inspected for legibility and deleted-task exclusion.

Generic arm64 iPhone build: **BUILD SUCCEEDED**, destination `generic/platform=iOS`, unsigned (`CODE_SIGNING_ALLOWED=NO`), isolated DerivedData. No phone installation or release was performed. A final read-only Supabase check confirmed both exact glass task rows remain deleted with NULL dates.

Visual proof uses synthetic test data:
- [Pending task detail](task_sheet_pending_schedule.png)
- [Project list excludes the deleted task](project_tasks_pending_excludes_deleted.png)

Artifacts remain in `/private/tmp/ops-calendar-deletion-*.log` and the corresponding `.xcresult` bundles. These are simulator/unit-test results, not a signed-in production mutation canary or execution of the repaired binary on the reporting phone.

## Concrete remaining business action

Glass Rail Install is still deleted and unscheduled on the server. If Jackson authorizes recovery, use the explicit restore workflow and separately schedule the exact task for the intended business date. Canpro's September 10 midnight is `2026-09-10T07:00:00Z`; the phone's retained 06:00Z value reflects a different timezone boundary and must not be copied blindly. No recovery, notification, or release is implied by this local code repair.
