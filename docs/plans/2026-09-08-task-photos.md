# Task Photos Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use `custom-skills:executing-plans` to implement this plan task-by-task.

**Goal:** Let a photo belong to a task — captured from the task, visible on the task, tagged in the project gallery, assignable from the viewer — on one photo store.

**Architecture:** Additive `task_id` on `project_photos` (server) and `ProjectPhoto.taskId` (SwiftData V27, with the V26 shape frozen so released fingerprints hold). The existing capture → durable batch → `ImageSyncManager` delivery path carries the task through; the three inbound paths copy it back. Presentation reuses the gallery tile, `TaskBadge`, `SectionCard`, `PhotoCommentViewer`, and `.opsSheet`.

**Tech Stack:** SwiftUI, SwiftData (VersionedSchema + lightweight migration), Supabase (PostgREST via supabase-swift), XCTest, `FixedSizeSnapshot`.

**Design System:** `/Users/jacksonsweet/Projects/OPS/ops-design-system/project/DESIGN.md` and `/Users/jacksonsweet/Projects/OPS/ops-design-system/project/mobile/MOBILE.md`; tokens in `OPS/Styles/OPSStyle.swift`.

**Spec:** `docs/superpowers/specs/2026-09-08-task-photos-design.md` — read it first.

**Required Skills:** `ops-design`, `custom-skills:mobile-ux-design`, `custom-skills:interface-design`, `ops-copywriter:ops-copywriter`, `custom-skills:audit-design-system`, `superpowers:test-driven-development`, `superpowers:systematic-debugging`, `superpowers:verification-before-completion`, `supabase:supabase`

**Non-negotiables for the executing agent**
- Any edit to a stored property on a live `@Model` runs `-only-testing:OPSTests/AppUpdateMigrationTests` before commit (fingerprint fixture is the guard).
- `Network/Sync/InboundProcessor.swift`, `RealtimeProcessor.swift`, `Utilities/DataActor.swift`, `Network/ImageSyncManager.swift` are CRLF/mixed: edit with line-scoped CRLF-preserving Python, and confirm `git diff --stat` equals `git diff --ignore-all-space --stat` before committing.
- Verdicts from `xcrun xcresulttool get test-results summary --path <bundle>`; "TEST SUCCEEDED" on stdout proves nothing.
- No `git push`. No AI attribution in commit messages.
- Never guess a Supabase column type, grant, or function body — read it with `execute_sql` first. Production write probes go inside `begin; … rollback;`.

---

### Task 1: Freeze V26's `ProjectPhoto`, widen the live model, add V27

**Skills:** `superpowers:test-driven-development`

**Files:**
- Modify: `OPS/DataModels/Migrations/OPSSchemaCommon.swift` (add `enum OPSSchemaLegacyProjectPhotoV26`, repoint `v9ProjectPhotoModels`, add `v27ProjectPhotoModel`)
- Create: `OPS/DataModels/Migrations/OPSSchemaV27.swift`
- Modify: `OPS/DataModels/Migrations/OPSMigrationPlan.swift` (schemas list + stage)
- Modify: `OPS/DataModels/Migrations/OPSSchemaCurrent.swift` (`typealias OPSSchemaCurrent = OPSSchemaV27`)
- Modify: `OPS/DataModels/Supabase/ProjectPhoto.swift` (`var taskId: String?`)
- Modify: `OPSTests/Fixtures/swiftdata-released-schema-fingerprints.json` (add `"27.0.0"`)
- Test: `OPSTests/DataModels/AppUpdateMigrationTests.swift`

**Step 1: Write the failing tests** (append to `AppUpdateMigrationTests`, mirroring `testV25AddsPrimaryContactProjectionWithoutChangingReleasedProject` and `testV24StoreMigratesToV25PreservingProjectAndPrimaryContact`):

```swift
func testReleasedV26DoesNotReferenceWidenedLiveProjectPhoto() {
    XCTAssertTrue(contains(OPSSchemaLegacyProjectPhotoV26.ProjectPhoto.self, in: OPSSchemaV26.self))
    XCTAssertFalse(contains(ProjectPhoto.self, in: OPSSchemaV26.self), "V26 must keep its released fingerprint")
    XCTAssertTrue(contains(ProjectPhoto.self, in: OPSSchemaV27.self))
}

func testV26StoreMigratesToV27PreservingPhotoAndDefaultingTaskLink() throws {
    try autoreleasepool {
        let sourceSchema = Schema(versionedSchema: OPSSchemaV26.self)
        let container = try ModelContainer(for: sourceSchema, configurations: ModelConfiguration(schema: sourceSchema, url: storeURL))
        let context = ModelContext(container)
        let photo = OPSSchemaLegacyProjectPhotoV26.ProjectPhoto(
            id: "photo-v26", projectId: "project-1", companyId: "company-1",
            url: "https://cdn.example/p.jpg", source: "in_progress", uploadedBy: "user-1",
            caption: "Curb detail", isClientVisible: true)
        context.insert(photo)
        try context.save()
    }
    let targetSchema = Schema(versionedSchema: OPSSchemaV27.self)
    let migrated = try ModelContainer(for: targetSchema, migrationPlan: OPSMigrationPlan.self,
                                      configurations: ModelConfiguration(schema: targetSchema, url: storeURL))
    let photos = try ModelContext(migrated).fetch(FetchDescriptor<ProjectPhoto>())
    let row = try XCTUnwrap(photos.first)
    XCTAssertEqual(photos.count, 1)
    XCTAssertEqual(row.id, "photo-v26")
    XCTAssertEqual(row.caption, "Curb detail")
    XCTAssertTrue(row.isClientVisible)
    XCTAssertNil(row.taskId)
}
```

**Step 2: Run** `-only-testing:OPSTests/AppUpdateMigrationTests` — expected: compile failure (no V27 / legacy enum).

**Step 3: Implement**
- Copy the current `ProjectPhoto` class body into `enum OPSSchemaLegacyProjectPhotoV26 { @Model final class ProjectPhoto { … } }` next to `OPSSchemaLegacyDeckDesignV25` (same entity name, no `taskId`, same init). Point `v9ProjectPhotoModels` at it; add `static let v27ProjectPhotoModel: [any PersistentModel.Type] = [ProjectPhoto.self]`.
- `OPSSchemaV27` = `OPSSchemaV26.models` with `v27ProjectPhotoModel` in place of `v9ProjectPhotoModels`; `versionIdentifier` 27.0.0.
- Add `var taskId: String?` to the live `ProjectPhoto` (after `siteVisitId`), `init(taskId: String? = nil)` storing `taskId?.lowercased()`.
- `OPSMigrationPlan`: append `OPSSchemaV27.self` to `schemas`, add `addProjectPhotoTaskLinkV26toV27 = MigrationStage.lightweight(fromVersion: OPSSchemaV26.self, toVersion: OPSSchemaV27.self)` to `stages` (last).
- Repoint `OPSSchemaCurrent`.

**Step 4: Run the class.** `testDeclaredSchemaChecksumsStayImmutable` will report the missing `27.0.0` fingerprint value; add it to the fixture exactly as reported; re-run until the whole class is green with V1–V26 byte-identical.

**Step 5: Commit** — `feat(photos): freeze V26 project photo and add V27 task link`

---

### Task 2: DTO and the three inbound paths

**Files:**
- Modify: `OPS/Network/Supabase/DTOs/ProjectPhotoDTOs.swift` (`taskId` ↔ `task_id`, `toModel`)
- Modify (CRLF-safe): `OPS/Network/Sync/InboundProcessor.swift:1540-1580`, `OPS/Utilities/DataActor.swift:1790-1830`, `OPS/Network/Sync/RealtimeProcessor.swift:2170-2192`
- Test: the existing project-photo inbound tests (`grep -rn "mergeProjectPhoto\|upsertProjectPhoto\|ProjectPhotoDTO(" OPSTests`) — extend the nearest one per path; create `OPSTests/Sync/ProjectPhotoTaskLinkSyncTests.swift` if none covers a path.

**Step 1: Failing tests** — (a) `ProjectPhotoDTO` decodes `"task_id": "ABC…"` to `taskId` and `toModel().taskId` is lowercased; (b) for each path, an existing row with `taskId == nil` receives the DTO/model value; (c) a row whose `taskId` is in `pendingFields`/pending operation keeps its local value.

**Step 2: Run — fail.**

**Step 3: Implement** — add `"taskId"` to both `acceptableFields` lists and `if accept.contains("taskId") { existing.taskId = dto.taskId?.lowercased() }`; realtime: `if !pendingFields.contains("taskId") { existing.taskId = model.taskId }`; `toModel()` passes `taskId`.

**Step 4: Run — pass.** Confirm CRLF preservation. **Step 5: Commit** — `feat(photos): sync the task link through every inbound path`

---

### Task 3: Capture carries the task (durable)

**Files:**
- Modify: `OPS/Utilities/StagedPhotoDestinations.swift` (`owner(…taskID:)`, `acceptProject(…taskID:)`, `recoverProject`, a `parseOwnerContext` helper)
- Modify (CRLF-safe): `OPS/Network/ImageSyncManager.swift` (`ProjectPhotoMirrorRow.task_id`, `HandoffProjectPhotoInsert.taskId`, `deliverPortalMirror` reads the local row's `taskId` per url)
- Test: `OPSTests/…` nearest `StagedPhotoDestinations` / portal-mirror recorder tests (`grep -rln "ProjectPhotoMirrorInserting\|acceptProject(" OPSTests`)

**Step 1: Failing tests** — owner context `"project:abc#task:def"` parses to (project `abc`, task `def`) and lowercases; `acceptProject(batch, …, taskID:)` stamps `ProjectPhoto.taskId`; a recorded mirror insert for that url carries `task_id`; recovery of a task-scoped batch keeps the task; handoff insert encodes `task_id` as null when absent.

**Step 2: Run — fail.** **Step 3: Implement** (mirror the existing guard exactly; extend the accepted context forms). Look up the local row by `projectId` + `url` inside `deliverPortalMirror` on the manager's context and fill `task_id`. **Step 4: Run — pass.** **Step 5: Commit** — `feat(photos): carry the task through capture, recovery, and delivery`

---

### Task 4: Server column, grant, guard, bible

**Skills:** `supabase:supabase`

**Steps:**
1. `execute_sql`: read `pg_get_functiondef('private.current_user_has_permission'::regproc)` (or the overloads via `\df`-equivalent query on `pg_proc`) and `project_tasks.project_id`'s type. Do not write the guard until you have both.
2. Compose one migration (name `20260908HHMMSS_project_photos_task_link`): `alter table … add column if not exists task_id uuid null references public.project_tasks(id) on delete set null;` the partial index; `grant update (task_id) on public.project_photos to anon, authenticated;` `create or replace function public.project_photos_write_guard()` = the current body plus the task rule from the spec.
3. Probe first inside `begin; … rollback;` (add column, run the guard on a synthetic update), then `apply_migration`.
4. Verify with `information_schema.column_privileges` (never `role_table_grants`) and `pg_get_functiondef`.
5. Archive the byte-exact SQL at `ops-software-bible/migrations/<version>_project_photos_task_link.sql`; update `07_SPECIALIZED_FEATURES.md` § "Synced `project_photos` gallery store" (column list, the task link, the guard rule, a one-line note for the web session) and the V-chain note in `03_DATA_ARCHITECTURE.md` (V27). In the bible repo inspect `git diff <file>` and stage by name — siblings are active there.

**Commit (bible):** `docs(photos): record project_photos.task_id and SwiftData V27`

---

### Task 5: Task Details › PHOTOS section

**Skills:** `ops-design`, `custom-skills:mobile-ux-design`, `ops-copywriter:ops-copywriter`

**Files:**
- Create: `OPS/Views/Components/Project/TaskPhotoStrip.swift` (thumbnail strip, `size: .section | .compact`, `+N` overflow tile, `onTap(index)`)
- Modify: `OPS/Views/Components/Project/TaskDetailsView.swift` (insert `photosSection` after `taskTypeSection`; camera cover mirroring `ProjectActionBar.swift:197-209` with `taskID: task.id`; viewer cover scoped to task photos)
- Test: `OPSTests/Views/TaskPhotoStripTests.swift` (pure model: ordering newest-first, overflow count) and `OPSTests/Views/TaskDetailsPhotosSnapshotTests.swift` (`FixedSizeSnapshot` PNGs: empty, three photos)

**Design tokens:** `SectionCard` (icon `OPSStyle.Icons.camera`-equivalent used by the PHOTO action, `title: "Photos"`, `count`, `actionIcon`, `actionLabel: "PHOTO"`), tile size = the carousel's tile token, `OPSStyle.Layout.spacing2` between tiles, `OPSStyle.Typography.body` + `OPSStyle.Colors.secondaryText` for `No photos yet.`, 44pt tap targets.

Steps: failing snapshot/model tests → implement → run → `custom-skills:audit-design-system` on the new file → commit `feat(tasks): photos on the task with capture from the task`.

---

### Task 6: Gallery badge and pinned-note strip

**Files:**
- Modify: `OPS/Views/Components/Project/Tabs/ActivityTabView.swift` (`ProjectPhotosCarousel` tile overlay; `PinnedTaskNote` gains `photoURLs: [String]`; entry row renders `TaskPhotoStrip(size: .compact)`)
- Create: `OPS/Views/Components/Project/ProjectPhotoTaskIndex.swift` — pure `url → (taskTitle, colour)` and `taskId → [url]` maps from `[ProjectPhoto]` + `project.tasks`
- Test: `OPSTests/Views/ProjectPhotoTaskIndexTests.swift`; extend the Activity snapshot tests (`grep -rln "ActivityTab" OPSTests/Views`) with a badge tile and a pinned entry with a strip.

Badge: `TaskBadge(name:color:size: .small)` bottom-leading, inset `OPSStyle.Layout.spacing1`. Commit `feat(activity): show the task on gallery tiles and pinned task notes`.

---

### Task 7: Assign from the viewer

**Files:**
- Modify (CRLF-safe): `OPS/Network/ImageSyncManager.swift` — `setPhotoTask(url:taskId:projectId:)` mirroring `setPhotoClientVisibility(url:isVisible:projectId:)` (read it fully first; same offline/retry/error surfacing)
- Modify: `OPS/Views/Components/Images/PhotoCommentViewer.swift` — `TASK` action between VISIBLE and ANNOTATE (gated `PermissionStore.shared.can("projects.edit")` and a synced row for the url); `.opsSheet(detents: [.medium])` `AssignTaskSheet`
- Create: `OPS/Views/Components/Images/AssignTaskSheet.swift`
- Test: `OPSTests/Views/AssignTaskSheetTests.swift` (availability rule, row model, selection → call), snapshot PNG of the sheet

Copy (via `ops-copywriter`): action `TASK` / assigned title uppercase; sheet title `ASSIGN TO TASK`; row `NONE`. Haptic: `UIImpactFeedbackGenerator(style: .medium)` on commit. Commit `feat(photos): assign a photo to a task from the viewer`.

---

### Task 8: Full verification and proof

1. Run the whole `OPSTests` suite on your private simulator clone (`-skip-testing:OPSUITests`), verdict from the xcresult; fix anything red that your work touched.
2. `custom-skills:audit-design-system` across every file you created/changed.
3. Collect the proof PNGs into `docs/artifacts/task-photos-20260908/` (never the repo root) and list them in your final report with what each shows.
4. Report: commits (hashes + one line each), test totals from the xcresult, proof paths, the migration version applied, anything left open.
