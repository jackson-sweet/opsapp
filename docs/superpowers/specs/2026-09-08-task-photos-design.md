# Task Photos — Design

**Bug:** `a290934f` — "Need to be able to attach a photo to a task" (filed from ProjectDetails › Activity, 2026-09-08).
**Status:** approved under the standing contract (spec and plan are the agent's; the founder reviews the built thing).

## The problem

Photos belong to the project. The Activity tab shows one gallery, notes carry
attachments, and the pinned TASK NOTES card shows what each task says — but a
photo cannot say which task it documents. The owner reviewing a job cannot
separate "the vinyl install" from "the curb details"; the crew cannot shoot
evidence *for* the task they are on.

## Decision

Photos gain an optional task link. One photo store, one gallery, one viewer —
a photo may additionally belong to a task. No second photo system.

Rejected: photos-as-task-notes (lives only in the feed, invisible to the
canonical store and to the web) and a separate `task_photos` table (photos are
photos; a second store splits the gallery).

## Data

### Server — `public.project_photos` (additive, migrates in prod directly)

- `task_id uuid null references public.project_tasks(id) on delete set null`
- partial index `(project_id, task_id) where deleted_at is null and task_id is not null`
- column-scoped `grant update (task_id) on public.project_photos to anon, authenticated`
  (the table grants `SELECT, INSERT` only; updates are column-scoped — see the
  existing `deleted_at, is_client_visible, caption, taken_at, thumbnail_url, rendered_url`).
- `public.project_photos_write_guard()` gains a `task_id` rule mirroring the
  soft-delete rule: a change is allowed when the operator is the uploader or
  holds `projects.edit`; the task must belong to the photo's project
  (`project_tasks.project_id` ↔ `project_photos.project_id`, both compared as
  text). Read `private.current_user_has_permission` before writing the scope
  argument — do not guess it.
- Archive the exact applied SQL in `ops-software-bible/migrations/` under the
  ledger version the MCP `apply_migration` records (byte-exact rule).

The web app is untouched (a sibling session owns it); the column is nullable,
so its typed inserts and reads keep working. Leave a one-line note for that
session in the bible update.

### iOS — SwiftData V27

- Live `ProjectPhoto` gains `var taskId: String?` (stored lowercased — task ids
  are Postgres uuids and the app compares ids case-insensitively everywhere).
- The pre-widening shape is frozen as `OPSSchemaLegacyProjectPhotoV26.ProjectPhoto`
  (nested enum, identically named `@Model` class — the `OPSSchemaLegacyDeckDesignV25`
  pattern) and `OPSSchemaCommon.v9ProjectPhotoModels` points at it, so V9–V26 keep
  their released fingerprints. `OPSSchemaCommon.v27ProjectPhotoModel = [ProjectPhoto.self]`;
  `OPSSchemaV27` is V26's list with that substitution; `OPSMigrationPlan` adds the
  schema and a lightweight `addProjectPhotoTaskLinkV26toV27` stage;
  `OPSSchemaCurrent = OPSSchemaV27`; the fingerprint fixture gains `"27.0.0"`.
- `ProjectPhotoDTO.taskId` (`task_id`). Inbound merge (`InboundProcessor.mergeProjectPhoto`,
  `DataActor.mergeProjectPhoto`) adds `"taskId"` to the acceptable-field list and
  copies it; `RealtimeProcessor.upsertProjectPhoto` copies it unless pending.
- Capture: `StagedPhotoDestinations.acceptProject` takes `taskID: String? = nil`
  and stamps the local row. The durable owner context carries the task so a
  batch recovered after the app dies is still task-scoped:
  `owner(companyID:userID:kind:id:taskID:)` → `"project:<id>#task:<taskId>"`;
  the accept/recover guards parse that form alongside `project:<id>` and
  `project-draft:<id>`.
- Delivery: the canonical `project_photos` insert (`ProjectPhotoMirrorRow` built in
  `ImageSyncManager.deliverPortalMirror`) carries `task_id` from the local
  `ProjectPhoto` row for that url (the row exists before the upload is queued).
  `HandoffProjectPhotoInsert` (site-visit handoffs) gains the field too and sends nil.
- Reassign: `ImageSyncManager.setPhotoTask(url:taskId:projectId:)` mirrors
  `setPhotoClientVisibility` exactly (local update, PATCH `task_id`, same
  offline/retry behaviour, same error surfacing).

## Presentation

Reasoned from the moments a crew member and an owner are in — not from the
data model.

1. **Task Details › PHOTOS section.** The task screen is where someone is
   *on* a task; evidence of the work sits with the task's identity, directly
   after the Task Type card and before Material History. A `SectionCard`
   titled `PHOTOS` with the count and the built-in header action `PHOTO`
   (camera icon) opens the same standardized batch camera the project PHOTO
   action uses, pre-scoped to the task. Body: a horizontal strip of thumbnails
   (the gallery's tile treatment) newest first; tap opens the shared viewer
   scoped to this task's photos. Empty body: `No photos yet.` in `secondaryText`.
   Capture is gated exactly as the project PHOTO action is.
2. **Gallery tiles carry the task.** In the Activity carousel, a tile whose
   synced row resolves to a task on this project shows a small `TaskBadge`
   (task title, task colour) at its bottom-leading corner. Nothing on tiles
   without a task.
3. **Pinned TASK NOTES entries show their photos.** Under an entry's note text,
   a compact strip (up to four tiles, then a `+N` tile) of that task's photos;
   tap opens the viewer scoped to the task. Eligibility for the pinned card is
   unchanged (notes decide); photos-only tasks are reached from Task Details
   and the gallery badge.
4. **Viewer: assign in place.** The photo viewer's action bar gains a `TASK`
   action between VISIBLE and ANNOTATE (label shows the assigned task's title,
   uppercase, when set). Gated on `projects.edit` like VISIBLE, and shown only
   for photos that have a synced row (legacy CSV-only urls cannot be tagged).
   It opens a half sheet `ASSIGN TO TASK`: the project's tasks as rows
   (TaskBadge, status chip for terminal tasks, a checkmark on the current
   choice) and a `NONE` row. Choosing commits immediately — medium haptic,
   sheet dismisses, badge updates.

Copy is written through `ops-copywriter:ops-copywriter`; the strings above are
the intended register (UPPERCASE labels, sentence-case content, no
exclamation points).

Every value traces to `OPSStyle` tokens; `custom-skills:audit-design-system`
runs before the work is called done.

## Tests and proof

- `AppUpdateMigrationTests`: released V26 does not reference the widened live
  model; a V26 store with a photo migrates to V27 preserving every field with
  `taskId == nil`; fingerprints immutable.
- DTO decode/encode round-trips `task_id`; the three inbound paths copy it;
  a pending local `taskId` change is protected from an echo.
- Capture: a task-scoped batch stamps the local row and its recorded
  `ProjectPhotoMirrorRow.task_id` (via the `ProjectPhotoMirrorInserting`
  recorder seam); owner context parsing round-trips; recovery keeps the task.
- Presentation: pure mappings (url → task badge; task → strip model; viewer
  action availability) unit-tested; `FixedSizeSnapshot` PNG proofs for the
  PHOTOS section (empty, three photos), a gallery tile with a badge, a pinned
  entry with a strip, and the assign sheet.
- Verdicts come from `.xcresult`, never stdout. Closure on the founder's phone
  is a screenshot of a task with its photos.
