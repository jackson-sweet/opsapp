# Collaborative photo markup — layers, attribution, change-log, before/after (spec)

**Status:** Adversarially-verified design (workflow `wf_3551186b-807`, verdict needs-revision → corrections folded in below as HARD requirements). Ready for a focused build session.

Requested by Jackson (2026-06-23): (1) when user B opens markup on a photo user A already marked up, A's markup is visible in the editor; (2) per-author change log + show/hide toggle; (3) activity-feed before→after **snapshot** card (horizontal, arrow between, subtitle "<name> marked up a photo"); the photo-added subtitle (#4) and timestamp position (#5) are **already fixed** on `fix/ios-jobboard-polish` (`b005c408`).

## Root cause of #1 (verified)
The editor restores strokes ONLY from `existingAnnotation?.localDrawingData` (`PhotoAnnotationView.swift:38-42`), a **device-local** PencilKit blob. Sync ingest never populates it (`PhotoAnnotationDTO.toModel` `PhotoAnnotationDTOs.swift:43-63`; `InboundProcessor.mergePhotoAnnotation` `:1428-1435` both omit it). So a row authored by Nick arrives with `localDrawingData == nil` → Pete opens a **blank** canvas over Nick's marks (Nick's overlay PNG is composited only for read-only display, never into the editor). Compounding: `ProjectPhotosGrid.existingAnnotation(at:)` (`:577-586`) fetches the newest row for the photo with **no author filter** and the editor saves by that row's `id` (`PhotoAnnotationRepository.updateAnnotation` `.eq("id")`), so Pete's save **overwrites Nick's overlay** on the shared row. Also: opening Nick's row and tapping DONE with no strokes routes to `applyEmptyDrawingClear` → soft-deletes Nick's **entire row**.

## Fix — author-scoped layers
Markup becomes **per-author layers** on the same anchor row. The editor composites every *other* author's overlay PNG as a non-editable base under the current user's editable PencilKit canvas; each user edits only their own layer. PencilKit is single-PKDrawing, so peers stay in the base image (correct decomposition).

## Data model — ADDITIVE only (iOS sync constraint; RPC is `RETURNS SETOF … select *`, so new cols auto-surface)
New nullable columns on `public.project_photo_annotations` (live table = 12 cols today):
- `layers jsonb` — array of `{ layerId, authorId, authorName, overlayUrl, strokeRef, visibleDefault, zIndex, createdAt, updatedAt, clearedAt }`.
- `change_log jsonb` — append-only `{ eventId, authorId, authorName, action(added|edited|cleared), strokeDelta, beforeSnapshotUrl, afterSnapshotUrl, at }`.
- `before_snapshot_url text`, `after_snapshot_url text` — most-recent event's baked images (hot feed path).

iOS `PhotoAnnotation` additive fields (mirror the existing `dimensions` computed-accessor pattern `:76-88`): `layersData/changeLogData: Data?` + typed accessors, `beforeSnapshotURL/afterSnapshotURL: String?`, and **local-only** `hiddenAuthorIdsData: Data?` (the show/hide toggle is a per-viewer preference — must never sync). Legacy scalar `annotation_url` stays synced to the current user's own layer for back-compat with pre-update builds.

### HARD CORRECTION 1 — atomic server-side layer merge (PRIMARY path, not optional)
A wholesale `.update(layers).eq("id")` is last-writer-wins and will drop a peer's just-landed layer. The layer write MUST go through a new **SECURITY DEFINER `upsert_markup_layer(annotation_id, layer_json, change_event_json, before_url, after_url)`** RPC that merges the `layers` array server-side by `layerId` (jsonb rebuild) and appends the change event atomically. Client-side union-by-layerId stays only as the local `InboundProcessor` merge. (Additive; identity via the established firebase_uid pattern, never `auth.uid()`.)

### HARD CORRECTION 2 — strokeRef placement (decide before build)
PKDrawing strokes don't round-trip from a PNG, so an author's own strokes need their `PKDrawing.dataRepresentation` persisted to resume cross-device. Do NOT inline base64 in the jsonb (it bloats every `get_photo_annotations_since` pull). Store the stroke blob as an **S3 object via the existing `/api/uploads/presign` path** and keep only its URL (`strokeRef`) in the layer. (Mirrors `uploadAnnotationPNG`.)

## Editor (`PhotoAnnotationView` + `ZoomablePhotoAnnotationCanvas`)
Resolve from the anchor row + current userId: `ownLayer`, `peerLayers` (visible, not locally hidden), raw original. Render stack: raw image → `peerOverlayImageView` (flattened composite of visible peers' overlay PNGs, `isUserInteractionEnabled=false`) → `PKCanvasView` seeded from `ownLayer.strokeRef` (fallback `localDrawingData`). Extract a shared `MarkupOverlayCompositor` from `preCompositeAnnotations`' download+flatten primitive (`:479-500`). Toggling a peer off re-flattens the visible set (instant, local).

### HARD CORRECTION 3 — author-scoped clear
Migrate `applyEmptyDrawingClear` + `AnnotationClearPlanner`: an empty-drawing save sets the current user's `layer.clearedAt` only; the whole-row soft-delete fires **only when the last visible layer is cleared** (preserves the dimensioned-capture branch). Unit-test the "open a peer's row, tap DONE with no marks" case (must NOT delete the peer's layer/row).

## Change-log sheet
Toolbar `square.stack.3d.up` button (author-count badge) → `.sheet([.height(280), .medium])`. One row per author: `[avatar] [name + "<n> marks · <relative>"] [Spacer] [eye toggle]`, 44pt targets, medium-haptic on toggle, eye drives `hiddenAuthorIds` (local). Expandable "ACTIVITY" disclosure = change_log newest-first. No button when the current user is the only author (omit a trivial control). All OPSStyle tokens, glassSurface, OPS voice.

## Snapshots (baked, not live links)
In `saveAnnotation` after the own overlay uploads: **before** = raw + all visible layers minus this event's change; **after** = raw + all visible layers incl. the new own layer (reuse the durable composite). Bake JPEG q0.9 (opaque, frozen pixels), upload via presign to `annotations/<companyId>/<projectId>/snapshots/{before,after}_<eventId>.jpg`, write the scalar cols (most recent) + the change_log event pair (history). Cache `snap_before_/snap_after_<eventId>`. Offline fallback mirrors the overlay path.

### HARD CORRECTION 4 — snapshot retention
Two baked JPEGs accrue per markup **event** indefinitely. Add a retention cap (keep the last N events' before/after pairs; prune older change_log image refs + their S3 objects). **Surface the per-event storage cost to Jackson for sign-off before building** (cost-transparency rule).

## Feed card (`AnnotationEntryView`)
When `beforeSnapshotURL` + `afterSnapshotURL` exist: header unchanged (subtitle already "marked up a photo" via `AnnotationFeedPolicy` — no policy change); body = `HStack[ before 72×72 ][ arrow.right tertiary ][ after 72×72 ]`, each a `PhotoThumbnail` Button (per-tile `onPhotoTap` → its snapshot URL), rounded + cardBorder. Legacy/comment-only rows fall back to today's single thumbnail. Snapshots are frozen — the card never reflects later edits.

## Plan (atomic commits; no push)
1. **DB migration** (additive cols) + the `upsert_markup_layer` SECURITY DEFINER RPC. **Get Jackson's go-ahead** (customer data + storage cost). Mirror SQL to bible; update 03/04/07.
2. iOS model additive fields + Codable `MarkupLayer`/`MarkupChangeEvent` + typed accessors.
3. DTO + repository (`updateLayers` routed through the RPC, NOT `.update().eq(id)`).
4. `InboundProcessor.mergePhotoAnnotation` union-by-layerId merge.
5. `MarkupOverlayCompositor` extraction + overlay cache.
6. Editor peer-base + own-canvas (the #1 fix).
7. Save rewrite (own layer upsert via RPC, change event, author-scoped clear, snapshots).
8. Change-log sheet + toolbar button + eye toggle.
9. Snapshot capture/store/sync + retention cap.
10. Feed before→after card.
11. Lazy-migrate existing `localDrawingData` rows into a layer on next edit.
12. Build (`xcodebuild -scheme OPS -destination generic/platform=iOS`) + tests (union merge, author-scoped clear, snapshot selection, feed policy unchanged) + 2-user cross-author manual check.
13. Bible + atomic commits.

## Skills (mandatory before any UI): brainstorming, mobile-ux-design, animation-architect→ios-animations (editor layer transitions/haptics), ops-design (tokens), ops-copywriter (every string). Build harness: copy `Secrets.xcconfig`, `-clonedSourcePackagesDirPath .spm-local`. Gate via permission, never role.

Full verified design: workflow `wf_3551186b-807`.
