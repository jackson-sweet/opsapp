# Project Details — Photos & Activity Feed (I2) Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use `custom-skills:executing-plans` to implement this plan task-by-task.

**Goal:** Fix six ProjectDetails bugs: live photo-comment feed entries with proper presentation, newest-first photo ordering, carousel comment badges, a redesigned (and actually syncing) site-visit packet entry, and durable note deletion.

**Architecture:** All feed data stays on `project_notes` (iOS-canonical). Two live-but-unmapped columns (`event_kind`, `content_metadata`) join the iOS model (SwiftData V13, lightweight). Feed rendering branches by kind (user note / photo comment / site-visit packet / status change). Deletes/edits move from direct fire-and-revert repo calls onto the existing queued-sync path with merge guards. Gallery ordering becomes date-resolved newest-first in the single `Project+Gallery` authority.

**Tech Stack:** SwiftUI, SwiftData (VersionedSchema V13), Supabase (PostgREST + AnyJSON), existing SyncEngine/OutboundProcessor queue.

**Design System:** `ops-design-system/project/DESIGN.md` + `mobile/MOBILE.md`, tokens via `OPS/Styles/OPSStyle.swift` (tan semantic = site visit: `OPSStyle.Colors.tan/tanSoft/tanLine`, mobile deltas `tanFillM/tanLineM`).

**Required Skills:** `custom-skills:executing-plans`, `ops-design` (loaded), `custom-skills:mobile-ux-design` (loaded), `ops-copywriter` (loaded), `superpowers:verification-before-completion` before closing.

**Spec:** `docs/superpowers/specs/2026-07-04-project-activity-photos-design.md` (root causes, layouts, copy).

---

### Task 1: `event_kind` + `content_metadata` reach the iOS model (schema V13)

**Files:**
- Modify: `OPS/DataModels/Supabase/ProjectNote.swift` — add `var eventKind: String?`, `var contentMetadataJSON: String?`
- Modify: `OPS/Network/Supabase/DTOs/ProjectNoteDTOs.swift` — DTO gains `eventKind: String?` (`event_kind`), `contentMetadata: AnyJSON?` (`content_metadata`, `import Supabase`); `toModel()` maps both (AnyJSON → JSON string)
- Create: `OPS/DataModels/Migrations/OPSSchemaV13.swift` — same model list as V12, version 13.0.0
- Modify: `OPS/DataModels/Migrations/OPSMigrationPlan.swift` — register V13 + lightweight stage V12→V13
- Modify merge paths to carry the two fields (guarded like `deletedAt`):
  `OPS/Utilities/DataActor.swift` (`mergeProjectNote`), `OPS/Network/Sync/InboundProcessor.swift` (`mergeProjectNote`), `OPS/Network/Sync/RealtimeProcessor.swift` (`upsertProjectNote`), `OPS/ViewModels/ProjectNotesViewModel.swift` (`mergeFetchedNotes`), `OPS/ViewModels/PhotoCommentsViewModel.swift` (`loadComments` upsert)

Steps: implement → device-target build → commit `feat(notes): map event_kind + content_metadata into the iOS model (schema V13)`.

### Task 2: Durable delete/edit + tombstone merge guards + live change signal

**Files:**
- Create: `OPS/Utilities/ProjectNoteChangeSignal.swift` — `static func post(projectId:)` firing `.projectNoteReceived` with `["projectId": …]` on main
- Modify: `OPS/Utilities/DataController.swift` — `createProjectNote` payload gains `event_kind`/`content_metadata` when set (used by Task 5)
- Modify: `OPS/ViewModels/ProjectNotesViewModel.swift` —
  - `deleteNote`: tombstone + `needsSync = true` + `dataController.deleteProjectNote` (queued, offline-safe; no revert); keep `removeNotePhotosFromProject` branch; post signal. Fallback to the old direct path only when `dataController == nil`.
  - `updateNoteContent`: route via `dataController.updateProjectNoteContent`; post signal.
  - `postNote`: post signal after optimistic insert, server replace, and revert.
  - `mergeFetchedNotes`: skip rows with `existing.needsSync == true` (pending local truth wins).
- Modify: `OPS/ViewModels/PhotoCommentsViewModel.swift` — `setup` gains `dataController:`; `deleteComment`/`saveEdit` route durable; `postComment` + both post signal; upsert loop skips `needsSync` rows.
- Modify: `OPS/Views/Components/Images/PhotoCommentViewer.swift` — pass `dataController` into `setup`.
- Test: `OPSTests/ProjectNoteMergeGuardTests.swift` — in-memory container: (a) un-synced tombstone survives `mergeFetchedNotes` with a live server row; (b) synced rows still update; (c) tombstone from server (deletedAt set) still applies.

Steps: failing tests → implement → tests pass → device build → commit `fix(notes): durable queued delete/edit, tombstone merge guards, live feed signal`.

### Task 3: Newest-first gallery ordering (single authority)

**Files:**
- Modify: `OPS/DataModels/Project+Gallery.swift` — date-resolved merge:
  - `GalleryPhotoDate.parse(url:)` — web `^(\d{13})-`, iOS `_IMG_(\d+(\.\d+)?)_`, `note_(\d+(\.\d+)?)_`, `local_project_…_(\d+(\.\d+)?)_` (epoch seconds may be fractional; 13-digit = millis)
  - `mergedGalleryImageURLs(syncedPhotos: [ProjectPhoto])` — per-URL date = row `takenAt ?? createdAt`, else parsed, else `.distantPast`; stable newest-first sort; dedupe; gallery-eligible filter inside
  - context overload fetches rows (any sort) and delegates
- Modify: `OPS/Views/Components/Project/Tabs/ActivityTabView.swift` — carousel passes `syncedPhotos` rows; in-flight upload tiles move to the FRONT of the row (update comment); static fallback unchanged call-through
- Test: `OPSTests/GalleryOrderingTests.swift` — parser cases (4 formats + garbage) and merge cases (row-dated beats CSV position; CSV-web-dated ordered; unparseable tail keeps CSV order; dedupe; deck_design excluded)

Steps: failing tests → implement → tests pass → device build → commit `fix(photos): newest-first gallery ordering across carousel, grid, viewer`.

### Task 4: Photo-comment feed card + carousel comment badges

**Files:**
- Modify: `OPS/Views/Components/Project/Tabs/ActivityEntryView.swift` — `photoURL` branch: subtitle `commented on a photo`; body = 64pt `PhotoThumbnail` (hairline, tap → viewer) + mention-highlighted text; attachments strip stays for attachment-bearing notes; menu unchanged
- Modify: `OPS/Views/Components/Project/Tabs/ActivityTabView.swift` —
  - compute `commentCounts: [String: Int]` from `notesViewModel.notes` (photoURL match, or attachments-contains with non-empty content), pass to both carousels
  - `PhotoCommentCountBadge` (new private view): `bubble.left.fill` 10pt + mono count, `Color.black.opacity(0.65)` fill, 4pt radius, bottom-leading 4pt inset, `accessibilityLabel("\(n) comments")`; hidden at 0 or in edit mode

**Design tokens:** `OPSStyle.Typography.smallCaption` (subtitle), `.caption`/mono count, `OPSStyle.Colors.tertiaryText`, `OPSStyle.Layout.cornerRadius`/`cardCornerRadius`, badge fill matches `PhotoDeleteBadge` convention.

Steps: implement → device build → commit `feat(activity): photo-comment cards with context + carousel comment badges`.

### Task 5: Site-visit packet — structured metadata + real transport

**Files:**
- Modify: `OPS/Views/SiteVisits/SiteVisitProjectHandoff.swift` — `apply(...)` gains `dataController: DataController?`; `insertProjectNotes` builds `event_kind='site_visit'` + `content_metadata` `{site_visit_id, photo_count, measurements:[{label,value}], notes:[…], checklist:[…]}` (content keeps the legacy text packet for web) and creates via `dataController.createProjectNote` (queued op → actually syncs; falls back to plain insert when nil)
- Modify: `OPS/Views/Leads/Sheets/ConvertToProjectSheet.swift` — pass `dataController`
- Test: `OPSTests/SiteVisitPacketNoteTests.swift` — metadata JSON correctness (labels/values/checklist), content fallback preserved, event kind set

Steps: failing tests → implement → tests pass → device build → commit `fix(site-visit): packet note carries structured metadata and actually syncs`.

### Task 6: Feed rendering — packet card + packet sheet + status-change line

**Files:**
- Create: `OPS/Views/Components/Project/Tabs/SiteVisitPacketEntryView.swift` — card (header grammar + tan `SITE VISIT` tag `tan`/`tanSoft`/`tanLine` mobile deltas, mono summary line `4 PHOTOS · 2 MEASUREMENTS · …`, trailing `›`, whole-card tap + light haptic) + `SiteVisitPacketSheet` (large-detent sheet: `SITE VISIT` title, author/date mono meta, `// PHOTOS` 72pt strip via `@Query` on `siteVisitId` fallback `source == 'site_visit'`, `// MEASUREMENTS` label+mono value rows, `// NOTES`, `// CHECKLIST` olive checks; sections omit when empty; photo tap → `PhotoCommentViewer` fullScreenCover)
- Create (same file): `StatusChangeEntryView` — quiet line: `arrow.triangle.2.circlepath` 16pt tertiary + "changed status" + `FROM → TO` mono caps + timestamp
- Modify: `OPS/Views/Components/Project/Tabs/ActivityTabView.swift` — feed branch by `note.eventKind`: `site_visit` → packet card, `status_change` → status line, other non-nil → plain card fallback; system entries never show the edit/delete menu

**Design tokens:** tan semantic set, `glassSurface()`, `OPSStyle.Typography` scale, `OPSStyle.Colors.successStatus`-class olive for checks (use the earth-tone olive token), spacing tokens only.

Steps: implement → device build → commit `feat(activity): site-visit packet entry + detail sheet, status-change system line`.

### Task 7: Verification & closeout

- `ps aux | grep xcodebuild` guard → device-target build (`-clonedSourcePackagesDirPath .spm-local`)
- Copy `Secrets.xcconfig` → run new unit tests on simulator destination
- Snapshot proofs (UIHostingController + UIWindow + `drawHierarchy` harness — NOT ImageRenderer): feed composite (photo-comment card, packet card, status line), packet sheet, carousel with badges + newest-first fixture → `docs/artifacts/`
- Update `ops-software-bible` (project_notes `event_kind` usage: `status_change` (web), `site_visit` (iOS); packet metadata shape)
- Bug rows → `resolved` + `fix_commit` + `fix_notes` (verify columns first); plain-English report

---
No new animation systems (existing `OPSStyle.Animation` tokens only). No server schema changes (columns already live). CRLF: preserve per-file endings.
