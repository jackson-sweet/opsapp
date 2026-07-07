# Project Details — Photos & Activity Feed (I2) — visual proof

Rendered by `OPSTests/Views/ActivityFeedSnapshotTests` on the iPhone 17 Pro
simulator via the `UIHostingController` + `UIWindow` + `drawHierarchy` harness
(asset-catalog colors resolve correctly — `ImageRenderer` renders them yellow).
Full I2 suite: **24/24 tests passed**.

| File | Bug | What it proves |
|------|-----|----------------|
| `feed_photo_comment_card.png` | 488778ac / e1f073ed | A photo comment reads as a comment — "commented on a photo" subtitle + thumbnail-beside-text card |
| `feed_site_visit_packet_card.png` | 7649fd48 | The redesigned site-visit packet: tan `SITE VISIT` tag, "N PHOTOS · N MEASUREMENTS · …" scannable summary, tappable (chevron) into a detail sheet — no more raw text wall |
| `feed_status_change_line.png` | (bonus) | `status_change` system notes render as a quiet two-row line (`FROM → TO` on its own line), not a bogus "Team Member / Status changed" user note |
| `carousel_comment_badge.png` | e1f073ed | Comment badge (bubble glyph + count) on carousel thumbnails that carry a thread |

Not pictured (verified by logic tests, not snapshots):
- Newest-first photo ordering (`GalleryOrderingTests`, 10 cases)
- Durable note delete + tombstone merge guard (`ProjectNotesMergeTests`)
- Packet structured-metadata builder (`SiteVisitPacketNoteTests`, 6 cases)
