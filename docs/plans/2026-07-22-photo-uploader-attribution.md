# Photo uploader attribution implementation plan

**Goal:** Make Settings > Photos show and filter by the person who actually uploaded each photo, using the canonical `project_photos.uploaded_by` identity while preserving legacy gallery photos.

**Required Skills:** `supabase:supabase`, `superpowers:systematic-debugging`, `superpowers:test-driven-development`, `custom-skills:mobile-ux-design`, `custom-skills:interface-design`, `custom-skills:ops-design`, `ops-copywriter:ops-copywriter`, `custom-skills:audit-design-system`, `superpowers:verification-before-completion`, `superpowers:finishing-a-development-branch`

## Product contract

- The uploader is `project_photos.uploaded_by`, resolved to a same-company `public.users.id`. Annotation authors never become uploaders.
- A photo's canonical date is `taken_at ?? created_at`. Legacy-only photos retain filename/annotation/project fallback dates and never receive invented uploader attribution.
- Synced-only photos appear; soft-deleted photos and `deck_design` renders do not.
- A canonical tombstone suppresses the same URL if it remains in the legacy CSV, and protocol-relative / HTTPS aliases represent one photo.
- Photo Info states `Uploaded by <name>`. Missing historical identity uses a non-identifying fallback and never exposes a raw ID.
- Photos with no defensible date stay explicitly undated instead of receiving an invented ancient or current timestamp.
- Uploader filters are built from the uploaders represented by the current gallery, including historical users whose local name record still exists.
- Both All Photos and notification deep links use the canonical-plus-legacy gallery merge for storage totals.
- No layout or motion changes. Existing OPS mobile tokens, filter chips, metadata row, and touch targets remain intact.

## Task 1: Lock the broken identity contract with focused tests

**Files:**
- Add: `OPSTests/Views/PhotoGalleryAttributionTests.swift`
- Add: `OPS/Views/Settings/PhotoGalleryMetadataResolver.swift`

1. Add tests where uploader A owns a canonical row and annotator B adds a note; assert uploader A and the canonical capture date win while B's note remains.
2. Add project/company scoping, legacy-only, malformed-uploader, and uploader-filter cases.
3. Run only the new tests and record the expected red failure before production implementation.

## Task 2: Consume canonical photo rows throughout All Photos

**Files:**
- Modify: `OPS/Views/Settings/AllPhotosGalleryView.swift`
- Modify: `OPS/Views/Settings/PhotoFilterSheet.swift`
- Modify: `OPS/Views/Settings/PhotoGalleryViewer.swift`
- Modify: `OPS/Views/Settings/PhotoStorageManagementView.swift`

1. Query `ProjectPhoto` and `User` alongside projects and annotations.
2. Build each project's URLs with `mergedGalleryImageURLs(syncedPhotos:)`, then resolve uploader/date/note through the tested project-and-company-scoped metadata resolver.
3. Rename the ambiguous `PhotoItem.authorId` field to `uploaderId`, carry the resolved display name, and filter only on that canonical ID.
4. Generate filter options from the gallery's actual uploader set rather than annotation authors.
5. Make Photo Info explicitly say `Uploaded by <name>` or `Uploader unavailable`.
6. Use the enriched gallery items for storage breakdowns when the All Photos entry point supplies them; on notification navigation, query `ProjectPhoto` and run the same canonical-plus-legacy merge so synced-only photos and tombstones remain correct.

## Task 2A: Close adversarial merge and fallback edges

**Files:**
- Modify: `OPS/DataModels/Project+Gallery.swift`
- Extend: `OPSTests/GalleryOrderingTests.swift`
- Extend: `OPSTests/ProjectGalleryFilterTests.swift`
- Extend: `OPSTests/Views/PhotoGalleryAttributionTests.swift`

1. Canonicalize protocol-relative and HTTPS URL aliases for identity, metadata lookup, deduplication, and tombstone suppression.
2. Keep all canonical rows available to the merge so a failed CSV delete cannot resurrect a soft-deleted or non-gallery photo.
3. Make the gallery date optional when no canonical, filename, annotation, or project date exists; render honest unavailable labels and exclude undated photos only when a date filter is active.

## Task 3: Heal stale local uploader values on every inbound path

**Files:**
- Modify: `OPS/DataModels/Supabase/ProjectPhoto.swift`
- Modify: `OPS/Utilities/DataActor.swift`
- Modify: `OPS/Network/Sync/InboundProcessor.swift`
- Modify: `OPS/Network/Sync/RealtimeProcessor.swift`
- Extend: `OPSTests/Views/PhotoGalleryAttributionTests.swift`

1. Add one tested canonical UUID normalizer and inbound uploader application rule.
2. Include `uploadedBy` in protected-field merge handling for actor pull, legacy pull, and legacy realtime paths.
3. Verify a blank/stale local row heals from a valid incoming uploader while malformed or locally protected values do not overwrite attribution.

## Task 4: Verify, commit, merge, and hand off for human review

1. Run the new attribution suite plus existing gallery ordering/filter and project-photo DTO/sync coverage.
2. Run the design-system audit; confirm all touched UI still uses `OPSStyle` tokens and accessible existing controls.
3. Build the complete iOS target using the worktree-local package cache and a unique DerivedData directory.
4. Inspect the final diff, commit atomically, and update the live bug row with exact test/build evidence.
5. Merge the fix into local `main` without pushing, verify branch ancestry and a clean fix worktree, then stop for Jackson's device verification.
