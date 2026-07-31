# SITE VISIT CLOUD SYNC — durable phone capture, cross-device resume, and project handoff

Design spec · 2026-07-31 · initiative `SITE VISIT CLOUD SYNC` (single phase, P1)

Status: approved by Jackson on 2026-07-31. The product decision is that an unfinished visit syncs as an `in_progress` draft and can be resumed on another assigned phone before the operator completes it.

This specification supersedes the local-only site-visit decision in `docs/superpowers/specs/2026-07-22-sync-recovery-design.md` §7. It does not replace that design's retry classification, Pending Work surface, or recovery actions; it makes the visit itself a first-class sync bundle within them.

## 1 · Why this matches the field workflow

The operator's mental model is one site visit, not a collection of local drafts followed by unrelated project notes and photos. The system therefore has to preserve one durable visit identity from the first meaningful capture through completion and eventual project conversion.

The phone remains instant and fully usable without signal. Supabase becomes the durable shared copy whenever connectivity exists. `SAVE VISIT` completes the visit; it is not the first time the app attempts to protect the work.

The workflow guarantees:

1. Notes, measurements, checklist answers, identity details, photos, annotations, and deck references survive app termination.
2. An in-progress visit can resume on another authorized phone after its captured records reach Supabase.
3. A completed visit and its timeline activity commit together and retry without duplication.
4. Project conversion reuses the visit packet and media rather than creating disconnected copies.
5. Account export and deletion include every server-side piece of the visit.

## 2 · Verified starting point

- iOS `SiteVisit` is currently SwiftData-only. `SyncEntityType` has no site-visit cases, and the phone never writes the existing `public.site_visits` table.
- The capture children already have durable local identities: `SiteVisitCaptureArtifact`, `SiteVisitChecklistAnswer`, and `SiteVisitIdentityDraft`.
- Completion currently best-effort inserts an `activities` row using a local visit UUID. The foreign key cannot succeed when the parent visit does not exist in Supabase, and the error is not allowed to block the success state.
- Project handoff has independent note and photo paths. Those paths can partially succeed without proving that the site visit itself exists in the cloud.
- The live database already has `site_visits`, `activities.site_visit_id`, and `project_photos.site_visit_id`. `project_photos.project_id` is required, so it cannot be the pre-project capture store.
- The live `project_photos` uniqueness contract already deduplicates active site-visit photos by company, project, visit, and URL.
- The connected-phone audit found visit children whose parent records had been deleted locally, including data belonging to more than one company. Recovery must precede any destructive cleanup.
- The account-deletion work classifies `site_visits` as company-scoped on text `company_id`, soft-deleted, and customer-exported; `project_photos` follows the same text/soft/export contract, while `activities.company_id` is UUID and hard-deleted.

## 3 · Approaches considered

### A — normalized durable visit packet (chosen)

Keep `site_visits` as the parent and add typed child tables for artifacts, checklist answers, and the onsite identity draft. Local sync operations express explicit parent and media dependencies. This gives row-level retry, clean cross-device merging, referential integrity, and complete export/deletion coverage.

### B — one JSONB capture packet on `site_visits` (rejected)

This minimizes tables, but every edit rewrites the entire packet. Concurrent phones can overwrite unrelated work, large media metadata produces increasingly expensive writes, and individual failed items cannot retry or recover independently.

### C — completion-only upload (rejected)

This makes fewer cloud writes, but the visit remains exposed until the final button press. A lost phone, app failure, or interrupted upload can erase an entire field visit. It also prevents honest cross-device resume.

## 4 · Chosen architecture

### 4.1 Existing parent: `public.site_visits`

`site_visits.id` is the durable identity used by iOS, web, activities, project photos, project notes metadata, and recovery. iOS must generate lowercase UUID strings; Postgres stores the UUID value. `company_id` remains text and must never be treated as a UUID merely because current values may look UUID-shaped.

The iOS model gains the server lifecycle states and remote timestamps needed to map the live table:

- `scheduled`: created remotely or scheduled but not yet started.
- `in_progress`: the first meaningful capture has occurred.
- `completed`: the operator deliberately completed the visit.
- `cancelled`: the visit was cancelled.

Status is monotonic for synchronization: a stale device cannot move a `completed` or `cancelled` visit back to `in_progress`. Post-completion amendments to child records remain allowed and do not create another completion activity.

For an ad-hoc visit, `scheduled_at` uses the visit's local creation time. For a scheduled visit, iOS preserves the server time. `created_by` and `assignee_ids` use the existing OPS/Firebase identities expected by the live policies.

The legacy parent summary columns (`notes`, `measurements`, and `photos[]`) remain compatibility projections for existing web screens and older clients. The normalized child records are the canonical capture packet. The completion transaction regenerates those summary fields from active children rather than accepting divergent client summaries.

### 4.2 New business-data child: `public.site_visit_artifacts`

One row represents one independently recoverable capture artifact. Common relational columns stay typed; only kind-specific details use versioned JSONB.

Required contract:

- UUID primary key.
- `site_visit_id uuid not null` with a real single-column foreign key to `site_visits(id)`.
- `company_id text not null`, validated against the parent visit by trigger or constraint-safe write function.
- Constrained `kind`: note, transcript, measurement, photo, annotated_photo, dimensioned_photo, or deck_design.
- Typed common fields for source, title, body, capture time, creator, storage URLs, thumbnail URL, and optional deck-design UUID.
- Versioned JSONB payload only for kind-specific metadata such as structured dimensions and annotation descriptors.
- `created_at`, `updated_at`, and nullable `deleted_at`.
- Indexes on `(company_id, site_visit_id)` and active media lookup paths.

No `local://` file path or other device-private identifier may reach Supabase. A media artifact may exist locally while offline; its cloud row becomes resumable on other devices only after the bytes have uploaded and storage URLs are available.

### 4.3 New business-data child: `public.site_visit_checklist_answers`

Each answer remains independently editable and retryable. The row snapshots the field definition used during capture so a later template change cannot rewrite history.

Required contract:

- UUID primary key, text `company_id`, and a real `site_visit_id → site_visits.id` foreign key.
- Stable field identity plus snapshotted label, answer kind, required state, and display order.
- Versioned JSONB answer value with database validation for the supported scalar and structured answer forms.
- Capture/update timestamps, creator, and nullable `deleted_at`.
- Unique active answer per visit and field identity.
- Index on `(company_id, site_visit_id)`.

### 4.4 New business-data child: `public.site_visit_identity_drafts`

This one-to-one row protects onsite customer details before the visit is linked to an existing lead or client. It is business data, not temporary sync machinery.

Required contract:

- `site_visit_id` as the primary key and foreign key to `site_visits(id)`.
- Text `company_id` plus optional opportunity/client/sub-client references using their live database types.
- Contact name, company/client name, preferred email, additional emails, phone, address, and operator notes.
- `created_at`, `updated_at`, and nullable `deleted_at`.
- No search-only or transient UI state.

When the visit is bound to an existing or newly created lead, both the parent and identity row receive the durable references. The original onsite snapshot remains available as part of the visit record and customer export.

### 4.5 No server sync outbox

The retry queue remains in the account-scoped SwiftData store. Supabase stores customer business records and idempotent lifecycle results, not immutable transport receipts. This avoids unnecessary server machinery and keeps account erasure straightforward.

If a later requirement introduces a server receipt, event, delivery, or outbox table, it must ship with all of the following in the same migration:

- Company-data manifest classification, privilege snapshot, export decision, purge allowlist, and deletion rehearsal fixture.
- Normal UPDATE/DELETE immutability.
- A DELETE-only account-closure exception guarded by the exact transaction-local company marker set exclusively inside the allowlisted SECURITY DEFINER purge helper.
- Empty transaction-local request claims, `OLD.company_id` equality with the marker, and no trigger disabling or `session_replication_role` changes.

## 5 · Save and synchronization lifecycle

### 5.1 Starting or resuming

- A scheduled cloud visit downloads through inbound sync and uses its server UUID.
- An ad-hoc capture creates a local parent immediately, but does not create cloud noise until the operator makes the first meaningful change.
- The first note, measurement, checklist answer, identity field, photo, annotation, or deck attachment moves the parent to `in_progress` and records a parent-create sync operation in the same local transaction.

The local save, child mutation, and sync-operation creation must either all commit or all fail. The view cannot dismiss or report success when SwiftData reports a failure.

### 5.2 Dependency order

The outbound dependency graph is:

1. `site_visits` parent create/upsert.
2. Non-media child rows and media-upload tasks.
3. Media artifact rows after their storage URLs exist.
4. The completion operation after every capture operation that existed at the time of completion.
5. Project handoff rows after the visit and required project parent exist.

Edits to the same local row may coalesce, but the completion operation may not be folded into a generic create/update. It is a distinct lifecycle command with explicit dependencies.

Network failure leaves the local transaction safe and the bundle pending. Authentication, policy, validation, or permanent contract failures park the affected work in the existing Pending Work system with the server error preserved. No failure is swallowed.

### 5.3 Cross-device inbound merge

Inbound sync adds entity routes and DTOs for the parent and all three child contracts. Rows with unsent local operations are protected from inbound overwrite until their outbound operation resolves. Separate artifacts and checklist answers merge independently. If two phones update the same row, the last server-accepted mutation wins; completion and cancellation remain monotonic.

An assigned operator may resume an in-progress visit on another phone as soon as its parent and captured rows are readable under RLS. Media still pending on the original offline phone remains visibly pending rather than appearing as a completed upload.

### 5.4 Completion is one transaction

iOS and web both call one idempotent database completion contract. It must:

1. Lock and authorize the visit using the existing Firebase-aware company and assignment rules.
2. Reject cross-company access and stale attempts to reopen a terminal visit.
3. Build the legacy parent summaries from active normalized child rows.
4. Set status and completion time.
5. Create or reuse the one canonical `type='site_visit'` activity when the visit has a valid opportunity, client, or project timeline parent.
6. Store the activity UUID back on `site_visits.activity_id`.
7. Return the completed visit and activity identity.

The activity uniqueness rule is scoped to the completion activity for a visit, so a retry cannot double-post. The implementation must resolve the canonical UUID company identity required by `activities.company_id`; it must not cast the text site-visit company ID blindly.

A fully unbound visit may complete without a timeline activity. Later binding invokes the same idempotent activity materialization inside the binding operation, producing exactly one activity once a valid timeline parent exists.

The existing web implementation's split update plus best-effort activity insert is retired in favor of this shared contract.

## 6 · Media and project conversion

Pre-project media uploads to a company- and visit-scoped storage key. The authorization contract verifies access to the visit rather than requiring a project ID. Original, rendered, and thumbnail objects are recorded on the artifact row.

When the opportunity converts to a project:

- Existing conversion/handoff logic reads the durable visit identity and active packet.
- `project_photos` rows set `source='site_visit'` and the real `site_visit_id`.
- The project photo points to the already-uploaded object; conversion does not upload a duplicate.
- Existing active-photo uniqueness prevents retry duplicates.
- The site-visit artifact remains the source owner of the storage object. Deleting a project-photo projection must not delete bytes still referenced by the source visit.
- The consolidated project note keeps the visit UUID in its structured metadata and is created idempotently.
- Deck designs retain their existing durable entity identity and are linked through the visit artifact reference.

Account purge is the final owner cleanup for visit storage. Normal record deletion performs reference-aware cleanup and never removes an object still used by another active business record.

## 7 · Recovery of existing phone data

Before normal synchronization starts on the upgraded app, a one-time local repair scans child records whose `siteVisitId` has no parent.

- Group children by canonicalized UUID, company, and opportunity/client evidence.
- Recreate one local parent per valid group using the earliest capture time.
- Preserve the UUID while canonicalizing its string representation to lowercase across all children.
- Mark a group completed only when a durable local project packet proves completion; otherwise restore it as `in_progress` for operator review.
- Re-enqueue recoverable media using the existing restart-surviving upload queue.
- Queue cloud sync only when the group's company matches the signed-in company.
- Quarantine other-company groups until that company signs in. Never attach them to the current company or silently delete them.

The repair is idempotent, records its schema/migration completion locally, and is covered by fixtures representing parentless photos, checklist answers, identity drafts, and mixed-company residue.

## 8 · Sign-out and account closure

Normal sign-out must inspect the full visit bundle, not only parent records.

- If no unsynced visit work exists, sign-out deletes the local parent, artifacts, checklist answers, identity drafts, and related sync operations together.
- If unsynced work exists, the app attempts an immediate drain when online. It cannot silently continue with data loss.
- If work still cannot sync, sign-out requires an explicit destructive choice or lets the operator remain signed in and resolve the bundle. Final wording is owned by the OPS copy skill during implementation.
- After successful account closure, the app wipes the matching company's complete local dataset only after the server purge succeeds.

The server account-closure contract includes the three new tables in the same manifest version and transaction as `site_visits`:

- Company scope: direct `company_id`, live type text.
- Delete strategy: soft delete.
- Customer export: included.
- Dependency: each child is ordered before `site_visits` through its real single-column foreign key.
- Privileges and any definer-purge requirements are explicit and rehearsed; no broad DELETE grant is added to immutable machinery.

The implementation must be based on the finalized transactional `public.purge_company_data(company_id, manifest_plan)` work after its route/manifest rehearsal has landed. It must regenerate the live scope and privilege snapshots and add visit fixtures to the deletion rehearsal.

## 9 · Security and integrity

- RLS is enabled on every new public table.
- Policies use OPS's Firebase JWT bridge and existing public-role company/assignment helpers; they do not assume `auth.uid()` semantics or authenticated-role-only access.
- Child access is allowed only when both direct company scope and parent visit scope agree.
- Parent and foreign-key columns are indexed for RLS and join performance.
- Inserts and updates reject a child `company_id` that differs from its parent.
- Storage authorization uses the visit's company and assignment scope.
- Service-role and application grants follow least privilege and are captured in the account-deletion privilege snapshot.
- Migrations are additive for compatibility with released iOS clients. Existing parent columns and behavior remain readable throughout rollout.

## 10 · Rollout order

1. Land and rehearse the transactional company-data purge work.
2. Apply the additive visit-child schema, constraints, indexes, RLS, grants, completion contract, manifest entries, export coverage, purge coverage, and Software Bible update as one server contract.
3. Update web completion to use the shared transaction while retaining its existing read model.
4. Ship iOS local schema additions, DTOs, repositories, outbound dependencies, inbound merge, media authorization, completion command, and RecoveryInventory bundling.
5. Run the one-time orphan reconstruction before the first upgraded sync cycle.
6. Verify against a controlled authenticated tenant, then ship iOS through the normal release path.

The server contract must be backward-compatible before the new phone build reaches users. No destructive migration or production backfill is part of the client release.

## 11 · Verification and release proof

### Database contract

- Column types, foreign keys, indexes, RLS policies, grants, and function security verified from the live catalog.
- Parent-first writes and cross-company child writes tested through the same anon/Firebase claims used by the applications.
- Completion retried concurrently and proven to create one activity.
- Terminal-state downgrade rejected.
- Account export includes the parent and every child.
- Transactional account purge removes/soft-deletes the complete visit fixture and related activity/project projections without disabling triggers or foreign keys.
- Supabase security and performance advisors reviewed after the migration.

### iOS

- Local transaction failure does not dismiss the capture flow or report success.
- Capture offline, terminate the app, relaunch, edit, and complete while still offline.
- Reconnect and prove parent → children/media → completion dependency order.
- Protect unsent local edits from inbound overwrite.
- Resume the in-progress visit on a second authorized phone.
- Retry permanent and transient failures through the existing Pending Work behaviors.
- Reconstruct orphan groups, including mixed-company fixtures, without loss or cross-company leakage.
- Sign-out drains or explicitly blocks/discards pending work and then wipes every visit child.
- Focused tests, full simulator test gate, and generic physical-device build pass using isolated DerivedData.

### End-to-end release proof

On a physical phone under a controlled authenticated company:

1. Begin a visit with poor or disabled connectivity.
2. Capture identity, notes, checklist answers, a normal photo, an annotated/dimensioned photo, and a deck reference.
3. Kill and relaunch the app and confirm local continuity.
4. Restore connectivity and directly read back the parent and every child from Supabase.
5. Resume on a second assigned phone.
6. Complete from one phone and retry from the other; prove one completion activity.
7. Convert the lead to a project and prove project note/photo provenance with no duplicated media.
8. Export the company and verify the full visit packet.
9. Rehearse transactional company deletion against the same fixture and verify no visit rows, projections, or storage objects remain.

## 12 · Cost and operational impact

No new subscription or third-party service is required. In-progress photo upload moves Supabase storage and transfer usage earlier in the workflow. Reusing the same storage object during project conversion prevents double storage. Row-level autosave adds small database write volume; the reliability benefit is intentional and the expected cost is negligible relative to media storage.

## 13 · Acceptance criteria

The work is complete only when all of the following are true:

- A real phone-created visit appears in `site_visits` before completion after the first meaningful capture and connectivity.
- The full visit packet is durable, resumable, and company-scoped.
- `SAVE VISIT` cannot report success when the local transaction fails.
- Offline completion eventually produces exactly one server completion and, when linkable, exactly one activity.
- Project conversion preserves the visit UUID and reuses media without duplicate rows or bytes.
- Existing orphaned phone data is reconstructed or quarantined, never silently discarded or cross-attached.
- Sign-out cannot silently erase unsynced work and removes all visit children after safe completion/discard.
- Customer export and transactional account deletion cover every server-side visit record and storage object.
- iOS, web, database, account-lifecycle, and physical-phone proof all pass.

## 14 · Source references

- `OPS/DataModels/Supabase/SiteVisit.swift`
- `OPS/DataModels/SiteVisits/SiteVisitCaptureArtifact.swift`
- `OPS/DataModels/SiteVisits/SiteVisitType.swift` (`SiteVisitChecklistAnswer`)
- `OPS/DataModels/SiteVisits/SiteVisitIdentityDraft.swift`
- `OPS/Views/SiteVisits/SiteVisitCaptureViewModel.swift`
- `OPS/Network/Sync/SyncTypes.swift`
- `OPS/Network/Sync/OutboundProcessor.swift`
- `OPS/Network/Sync/InboundProcessor.swift`
- `OPS/Network/Sync/RecoveryInventory.swift`
- `../ops-web/src/lib/api/services/site-visit-service.ts`
- `../ops-web-data-cascade/src/lib/data/company-data-manifest.ts`
- `../ops-software-bible/03_DATA_ARCHITECTURE.md`
- `../ops-software-bible/10_JOB_LIFECYCLE_AND_DATA_RELATIONSHIPS.md`
