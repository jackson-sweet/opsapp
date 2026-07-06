# Project Details — Photos & Activity Feed (Workstream I2) — Design Spec

Date: 2026-07-04 · Chip: BUG BURNDOWN P1-1-8 · Surface: iOS `ProjectDetailsView` Activity tab

Covers six bugs: `4353812f` (comment absent from feed until reopen), `488778ac` (photo comments in feed),
`e7ef2c88` (photo ordering), `e1f073ed` (carousel newest-first + comment subtitle + comment badge),
`7649fd48` (site-visit packet entry redesign), `f9e00eb9` (note delete broken).

## Verified root causes (live code + prod data)

1. **Feed staleness** — `PhotoCommentsViewModel.postComment/deleteComment/saveEdit` write ProjectNotes
   into SwiftData but never signal `ProjectNotesViewModel` (its `.projectNoteReceived` observer only fires
   for realtime inbound from OTHER devices). Own comments appear only after screen reopen.
2. **Photo ordering** — `Project.mergedGalleryImageURLs` renders legacy CSV order first, then synced
   `project_photos` rows sorted `createdAt` ASC. A new photo (appended to CSV) lands *before* the
   synced block → "inserted mid-list". In-flight upload tiles append at the END of the carousel.
3. **Photo comments in feed** — comments ARE ProjectNotes (with `photoURL` set) and do reach the feed,
   but render as bare notes: no "commented on a photo" context, no thumbnail of the photo.
4. **Site-visit packet** — `SiteVisitProjectHandoff.insertProjectNotes` posts ONE text-wall note
   (`"SITE VISIT PACKET\n\n…"` + `MEASURE ::` lines). Not scannable, not tappable. Worse: it sets
   `needsSync = true` but never records a sync operation, and project notes have **no outbound sweep**
   → prod has **zero** packet notes ever synced (verified). Packets are stranded on the author's device.
5. **Note delete** — both ViewModels call `ProjectNoteRepository.softDelete` directly: no retry
   (create has 3 attempts), no offline queueing (offline delete = instant revert + error), no 0-row
   verification (an RLS/identity blip yields a silent no-op "success" and the note resurrects on next
   fetch). The durable path (`DataController.deleteProjectNote` → tombstone + `recordOperation` →
   OutboundProcessor generic delete) exists but has **zero callers**. The ViewModel-level merges
   (`mergeFetchedNotes`, `PhotoCommentsViewModel.loadComments`) overwrite `deletedAt` unconditionally,
   so a not-yet-pushed tombstone is resurrected by any concurrent fetch.
6. **`event_kind` blind spot** — live `project_notes` has `event_kind` + `content_metadata` columns
   (web already writes `event_kind='status_change'`, metadata `{from,to}`), but the iOS model/DTO drop
   both. iOS renders status changes as bogus user notes ("Team Member / Status changed").

## Approaches considered (site-visit packet)

- **A. Rich system entry via `event_kind='site_visit'` + `content_metadata` (CHOSEN).** One feed card
  per site visit; structured metadata drives a compact summary + tap-through detail sheet. Content
  column keeps the plain-text packet so web/legacy clients render unchanged. Joins the established
  web `event_kind` convention; columns already live (no migration); fixes transport via the op queue.
- **B. Decompose the packet into individual notes/entries.** Floods the feed with N cards at
  conversion; destroys the "site visit happened" moment; ordering interleaves confusingly. Rejected.
- **C. Better-formatted text note.** Still a wall, still not tappable, still doesn't sync. Rejected.

## Design — feed entries (Activity tab)

The feed keeps one card grammar (avatar · name + timestamp · action subtitle), extended per kind:

### 1. Photo-comment card (`photoURL != nil`)
```
┌──────────────────────────────────────────────┐
│ (avatar) Harrison Sweet  2h ago          ⋯   │
│          commented on a photo                │
│ ┌────────┐  Looks tight against the fascia — │
│ │ thumb  │  reroute the downspout left.      │
│ │ 64×64  │                                   │
│ └────────┘                                   │
└──────────────────────────────────────────────┘
```
- Subtitle `commented on a photo` — identical grammar to the annotation card's "marked up a photo".
- 64pt `PhotoThumbnail` (hairline border, `cornerRadius`) + comment text side by side — the exact
  `AnnotationEntryView` body layout, but with the note card's own-note edit/delete menu preserved.
- Tap thumbnail → `PhotoCommentViewer` at that photo.

### 2. Site-visit packet card (`event_kind == 'site_visit'`)
```
┌──────────────────────────────────────────────┐
│ (avatar) Jackson Sweet  3d ago   [SITE VISIT]│
│          completed a site visit              │
│ 4 PHOTOS · 2 MEASUREMENTS · NOTES · CHECKLIST│
│                                          ›   │
└──────────────────────────────────────────────┘
```
- `SITE VISIT` tag: tan semantic (DESIGN.md lists site visit as a tan meaning) — tan text /
  `tan`-soft fill / `tan`-line border, JetBrains Mono caps (OPSStyle `StatusBadge`-class treatment).
- Summary line: JetBrains Mono smallCaption, tertiary, `·` separators; only non-zero parts shown.
- Whole card tappable → packet sheet. Trailing `›` affordance. No text wall on the card.

### 3. Status-change line (`event_kind == 'status_change'`)
```
   ⟳  Dana changed status   ESTIMATED → ARCHIVED   2d ago
```
- A quiet single-line system row (no glass card): 16pt `arrow.triangle.2.circlepath` icon in
  tertiary, "changed status" sentence-case, statuses uppercase mono secondary, timestamp trailing.
- Unknown future `event_kind` values fall back to the plain note card rendering content text.

### 4. Site-visit packet sheet (tap-through)
`.sheet` large detent, glass-dense, drag handle + `SITE VISIT` title (Cake Mono-class header via
OPSStyle), author + date metadata line (mono). Sections render only when non-empty:
- `// PHOTOS` — horizontal 72pt thumbnail strip of `ProjectPhoto` rows with this `site_visit_id`
  (fallback: `source == 'site_visit'` when ids are absent); tap → `PhotoCommentViewer` on that photo.
- `// MEASUREMENTS` — rows: label (body) + value (JetBrains Mono, trailing).
- `// NOTES` — body text blocks.
- `// CHECKLIST` — rows with olive check glyphs.
All content renders from `content_metadata` + synced `project_photos` (never from device-local
capture artifacts) so the sheet works on every teammate's device.

### 5. Carousel comment badge
- Bottom-leading corner of each 72pt thumbnail: `bubble.left.fill` 10pt + mono count, dark fill
  (`Color.black.opacity(0.65)` — matches the existing delete-badge treatment), 4pt corner radius
  (tag radius; no pills), 4pt inset. Informational only (tile tap opens the viewer thread).
- Count = the photo's comment thread size as the viewer computes it: notes with `photoURL == url`
  plus non-empty-content notes whose attachments contain the url. Live via the notes ViewModel.
- Hidden in wiggle/edit mode (delete affordance owns the tile) and when count is 0.

## Data & sync design

- **Model**: `ProjectNote.eventKind: String?` + `ProjectNote.contentMetadataJSON: String?` (raw JSON
  string). SwiftData schema V13 (lightweight; two optional fields), added to the migration plan.
- **DTO**: `event_kind` (String?), `content_metadata` (JSON object → stored raw). All four inbound
  merge paths (DataActor, InboundProcessor, RealtimeProcessor, VM merges) map the new fields.
- **Packet metadata shape** (written by the handoff, read by the sheet):
  `{"site_visit_id","photo_count","measurements":[{"label","value"}],"notes":[…],"checklist":[…]}`
- **Packet transport**: `SiteVisitProjectHandoff.insertProjectNotes` now records a `create` op via
  `SyncEngine.recordOperation(.projectNote…)` with `event_kind` + `content_metadata` in the payload
  (generic outbound insert carries arbitrary columns). Content keeps the plain-text packet.
- **Durable delete/edit**: ViewModel delete/edit routes through the queued-op path
  (tombstone/edit + `needsSync` + `recordOperation`), which the existing inbound field-guards
  already protect. VM-level merges skip rows with `needsSync == true` (local wins until pushed).
  Direct `softDelete`/`updateContent` repo calls are no longer used by the UI.
- **Ordering**: `Project+Gallery` becomes date-aware: per-URL timestamp = ProjectPhoto `takenAt ??
  createdAt`, else timestamp parsed from the URL filename (web `<millis>-<rand>.jpg`, iOS
  `*_IMG_<epoch>_…`, `note_<epoch>_…`, `local_project_<pid>_<epoch>_…`), else `.distantPast`
  (legacy CSV keeps its relative order at the tail). Sort newest-first, stable. In-flight upload
  tiles render at the FRONT of the carousel. Viewer/carousel/counts all flow through the helper,
  so tapped indexes stay consistent.
- **Live refresh**: a shared `ProjectNoteChangeSignal.post(projectId:)` fires `.projectNoteReceived`
  after every local note mutation in both ViewModels (post/delete/edit, optimistic + confirmed);
  both ViewModels already observe it. Observers reload from local — idempotent and cheap.

## States
- **Loading**: unchanged (feed spinner). Sheet: content renders from already-local data — no spinner.
- **Empty**: packet card only exists when the packet has content; sheet sections omit when empty;
  badge hidden at 0.
- **Error**: delete/edit no longer show transient network errors — they queue (offline-safe).
  Post keeps its existing error banner + composer-restore behavior.
- **Offline**: delete/edit tombstone locally and sync when signal returns (matches app sync doctrine).

## Haptics
- Packet card tap → light impact (navigation-grade). Delete confirm keeps its existing pattern.
  No haptics on badges/counts (information, not interaction).

## Accessibility
- Badge carries `accessibilityLabel("N comments")`; packet card labels "Site visit — 4 photos, 2
  measurements"; status line reads naturally ("Dana changed status from Estimated to Archived").
- All touch targets ≥44pt (cards/rows/strips); text ≥ smallCaption tokens; no color-only signals
  (tan tag carries the SITE VISIT label; badge pairs icon + count).

## Copy (product register)
"commented on a photo" · "completed a site visit" · `SITE VISIT` · `// PHOTOS` `// MEASUREMENTS`
`// NOTES` `// CHECKLIST` · "changed status" + `ESTIMATED → ARCHIVED` · counts always mono.

## Out of scope
Web rendering of `site_visit` notes (content fallback keeps it readable); annotation subsystem
(sibling chip P1-1-6); post/create queueing (posts keep explicit fail-and-restore UX by design).
