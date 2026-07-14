# LEADS: Address Autocomplete, Photos, Deck Attach, Share Summary — Implementation Plan

> **For Claude:** Executed in-session by the plan author (recon already loaded). Follow task order;每 task ends with a verified state + atomic commit.

**Goal:** Make the Leads surface complete for a deck/trades operator: real address entry with autofill + coordinates, a name-first edit header, photos on the lead, a deck design attached to the lead, client auto-creation on lead save, and a shareable plain-text lead summary with photo packet + 2D deck snapshot.

**Architecture:** All lead data stays on `public.opportunities` (images/lat/lng columns already exist server-side; iOS maps them now). Deck attach = additive `deck_designs.opportunity_id` (nullable uuid) + iOS model/DTO/sync + re-parent inside BOTH convert RPCs. Photos upload through the existing ops-web presign flow into `opportunities/{companyId}/{opportunityId}/…`, stored as full public S3 URLs in `opportunities.images` (matching the web email-extract format). Offline photo adds ride a small durable local queue modeled on ImageSyncManager's proven pattern.

**Tech Stack:** SwiftUI + SwiftData (iOS 17.6 target), Supabase (PostgREST + RPC), MapKit autocomplete (`AddressAutocompleteField`), presigned S3 uploads (`PresignedURLUploadService`).

**Design System:** `ops-design-system/project/DESIGN.md` + `mobile/MOBILE.md`; iOS tokens in `OPS/Styles/OPSStyle.swift`. Zero hardcoded values — reuse the Lead sheet primitives (`LeadField`, `LeadTextInput`, `SheetCTAButton`) and the section idioms already in `OPS/Views/Leads/`.

**Required Skills:** `ops-design`, `custom-skills:mobile-ux-design`, `ops-copywriter` (all loaded).

**Key recon facts (verified this session):**
- `opportunities.images text[]`, `latitude/longitude double precision` exist in prod; iOS `Opportunity` model defers them ("Phase 1 defers AI/location/images").
- Web writes `images` as FULL public S3 URLs (`email-imports/{companyId}/{oppId}/{ts}-{rand}.ext` via server-side puts); web never reads the column. iOS is free to write the same shape from `opportunities/{companyId}/{oppId}/…` via `/api/uploads/presign` (iOS already succeeds with `projects/{companyId}/{projectId}` — verify `path-auth.ts` accepts a second UUID segment before relying on it).
- `/api/uploads/delete` does NOT exist on ops-web — `PresignedURLUploadService.deleteImage` is already best-effort/no-op. Lead photo delete = array PATCH only (+ harmless best-effort call).
- `deck_designs` has `project_id` only; RLS = company_isolation ALL (public role). Web has zero deck_designs code — additive column is iOS+DB only.
- TWO live convert RPCs: iOS → `convert_opportunity_to_project` (unified; copies site-visit photos → `project_photos`, materializes tasks); web → `convert_lead_to_project` (legacy). Carry-over changes must land in BOTH.
- `project_photos.source` enum: site_visit, in_progress, completion, other, measurement, deck_design → use `other` for lead-image carry-over.
- Client-alongside-lead: web email/import paths `ClientService.createClient → createOpportunity(clientId)`; manual paths (web modal, iOS AddLeadSheet) don't create clients — that's bug 1d5ab9aa. iOS fix: match-or-create client at lead save. (Web modal gap → separate spawned task.)
- `CreationPickerView(projectId: String?…)` already optional; `DeckBuilderView(deckDesign:modelContext:syncEngine:projectName:)` fullScreenCover; `DeckTab2DView(drawingData:toolState:)` read-only preview; `DeckRenderer.renderToPNG` for share snapshot; `CameraBatchView { [UIImage] in }` for capture.
- Deck outbound sync = SwiftData insert + `syncEngine.recordOperation(entityType:.deckDesign, changedFields:)`; `DeckDesign.serverMergeFields` drives inbound merge. Site-visit handoff stamps `project_id` this way at conversion.
- EditLeadSheet title = `EDIT · <first-6-uuid>`; DetailHero uses `L-<last-6>` — unify on the hero's form.

---

### Task 1 — Opportunity model parity: images + latitude/longitude

**Files:**
- Modify: `OPS/DataModels/Supabase/Opportunity.swift` (add `images: [String] = []`, `latitude: Double?`, `longitude: Double?`; extend `apply(_:)`)
- Modify: `OPS/Network/Supabase/DTOs/OpportunityDTOs.swift` (OpportunityDTO + CodingKeys + toModel; CreateOpportunityDTO gains latitude/longitude; EditOpportunityPatch gains latitude/longitude with explicit-null encode)
- Test: `OPSTests/Leads/OpportunityImagesMappingTests.swift` (new — DTO→model mapping for images/lat/lng; patch encoding emits explicit nulls)

Steps: write failing mapping test → run (sim test target) → implement → green → commit `feat(leads): map opportunities images + coordinates on iOS`.

### Task 2 — Lead form: tokenized address autocomplete + coordinates

**Files:**
- Modify: `OPS/Views/Leads/Sheets/LeadFormView.swift` (SITE ADDRESS → `AddressAutocompleteField` inside `LeadField`, visual parity check vs OPSStyle tokens; LeadForm gains `latitude/longitude` state + clears coords on manual text change, sets on `onAddressSelected`)
- Modify: `OPS/Views/Leads/Sheets/AddLeadSheet.swift` (pass coords into CreateOpportunityDTO)
- Modify: `OPS/Views/Leads/Sheets/EditLeadSheet.swift` (EditOpportunityPatch carries form coords; hydrate from opportunity)
- Test: `OPSTests/Leads/LeadFormCoordinateTests.swift` (coords cleared on manual edit; kept when address untouched; set on selection)

Commit `feat(leads): address autocomplete with coordinates in lead form`.

### Task 3 — Edit sheet header: name first (+ shared short id)

**Files:**
- Modify: `OPS/DataModels/Supabase/Opportunity.swift` (add `shortDisplayId` = "L-" + last-6 of un-hyphenated uuid, uppercased)
- Modify: `OPS/Views/Leads/Components/DetailHero.swift`, `OPS/Views/Leads/Sheets/ConvertToProjectSheet.swift` (use shared helper)
- Modify: `OPS/Views/Leads/Sheets/EditLeadSheet.swift` (header → eyebrow `// EDIT · L-XXXXXX` above `SheetTitleLabel(displayContactName)`)

Commit `fix(leads): edit sheet titles by lead name, unified L-id`.

### Task 4 — Client match-or-create on lead save (bug 1d5ab9aa)

**Files:**
- Create: `OPS/Services/LeadClientMatcher.swift` (pure matcher: normalized phone digits ≥7 exact-suffix match, lowercased email exact, case-insensitive trimmed name; first match wins in that order) + creation helper via existing client repository/DTO path (verify `ClientSheet.swift` uses; mirror it)
- Modify: `OPS/Views/Leads/Sheets/AddLeadSheet.swift` `performCreate()` (resolve clientId before create; failures fall back to lead-without-client — lead creation must never fail because client creation did)
- Test: `OPSTests/Leads/LeadClientMatcherTests.swift`
- After fix: update `bug_reports` row 1d5ab9aa (status/fix fields).

Commit `fix(leads): create-or-link client when a lead is saved`.

### Task 5 — DB: deck_designs.opportunity_id + convert carry-over (BOTH RPCs)

**Migrations (Supabase `apply_migration`, additive only):**
1. `alter table deck_designs add column opportunity_id uuid references opportunities(id); create index …_opportunity_id_idx on deck_designs(opportunity_id) where opportunity_id is not null;`
2. Replace `convert_opportunity_to_project`: after photo copy — re-parent decks (`project_id is null and opportunity_id = p_opportunity_id` → set project_id) + copy `opportunities.images` → `project_photos` (source `other`, dedup on url) + counts in result.
3. Same additions inside `convert_lead_to_project` (read def first; patch equivalently).

Verify with a sentinel SQL round-trip (insert fake deck w/ opportunity_id in a bogus company is NOT possible under RLS via MCP service role — verify by column existence + function def re-read instead; live behavior covered by iOS E2E later). Update bible §data architecture.

### Task 6 — iOS deck model/sync: opportunityId end-to-end

**Files:**
- Modify: `OPS/DataModels/DeckDesign.swift` (property + init + `isAttached(toOpportunityId:)` + `displayCandidate(forOpportunityId:)`)
- Modify: `OPS/Network/Supabase/DTOs/DeckDesignDTOs.swift` (DTO field + serverMergeFields + toModel/fromModel)
- Modify: `OPS/Network/Supabase/Repositories/DeckDesignRepository.swift` (`fetchForOpportunity`)
- Modify: outbound op sites that record deck creates/updates to include `opportunity_id` (DeckBuilderViewModel — find `recordOperation(entityType: .deckDesign` sites), inbound merge path (wherever serverMergeFields consumed).
- Modify: `OPS/DeckBuilder/Views/CreationPickerView.swift` + `TemplatePickerView` + `SketchCaptureView` creation sites: pass-through `opportunityId: String?`.
- Modify: `OPS/Views/SiteVisits/SiteVisitCaptureViewModel.swift` deck creation → stamp bound opportunityId.
- Test: `OPSTests/Network/DeckDesignOpportunityTests.swift` (DTO round-trip, displayCandidate scoping; mirror DeckDesignSyncTests style)

Commit `feat(deck): deck designs attach to leads (opportunity_id end-to-end)`.

### Task 7 — LeadDetailView: PHOTOS section + DECK section + view model

**Files:**
- Create: `OPS/Services/LeadImageService.swift` (MainActor; add/delete/queue-drain; presign folder `opportunities/{companyId}/{oppId}`; durable pending store via UserDefaults JSON + local files via `ImageFileManager`; drains on connectivity + startup; PATCH via server-state read-modify-write `OpportunityRepository.appendImages/removeImage`)
- Modify: `OPS/Network/Supabase/Repositories/OpportunityRepository.swift` (appendImages/removeImage — fetch-merge-update against server row)
- Create: `OPS/Views/Leads/Components/LeadPhotosSection.swift` (header `// PHOTOS NN`; horizontal 84pt thumb strip newest-first; leading ADD tile when canManage; QUEUED badge on local thumbs; empty+canManage → compact ADD PHOTOS row; hidden when empty+view-only)
- Create: `OPS/Views/Leads/Components/LeadPhotoViewer.swift` (fullScreenCover pager: paging, double-tap/pinch zoom, delete when canManage)
- Create: `OPS/Views/Leads/Components/LeadDeckSection.swift` (header `// DECK DESIGN`; content = `DeckTab2DView` read-only preview + title/updated; tap → DeckBuilderView; empty+canManage+feature-flag → compact START DECK DESIGN row → CreationPickerView(opportunityId:) sheet)
- Modify: `OPS/ViewModels/LeadDetailViewModel.swift` (images from opportunity + deck @Query-equivalent fetch; refresh hooks)
- Modify: `OPS/Views/Leads/LeadDetailView.swift` (place PHOTOS + DECK after SiteVisitLaunchCard, before ActivityTimeline; presentation state for camera/library/viewer/builder/picker)
- Capture: `CameraBatchView` + `PhotosPicker` (max ~20/batch), confirmationDialog TAKE PHOTOS / CHOOSE FROM LIBRARY.

Design tokens: existing Lead section idiom (JBM 10 headers w/ `//`, `commandCard()`/`nestedCard()`, `OPSStyle.Layout.*`, 44pt targets, `-M` earth tones only where semantic). Motion: `OPSStyle.Animation.standard` only.

Commit(s): `feat(leads): photos on the lead — capture, gallery, offline queue` and `feat(leads): deck design section on lead detail`.

### Task 8 — Share lead summary (feature 6b2ef5de)

**Files:**
- Create: `OPS/Services/LeadShareSummaryBuilder.swift` (pure text builder + async packet assembly: download image URLs w/ per-image timeout, local queue images from disk, deck 2D PNG via `DeckRenderer.renderToPNG` of display-candidate design)
- Create/Reuse: activity-view wrapper (rg `UIActivityViewController` first)
- Modify: `OPS/Views/Leads/LeadDetailView.swift` (`DetailNavBar` trailing 44pt share affordance; loading state while assembling)
- Test: `OPSTests/Leads/LeadShareSummaryBuilderTests.swift` (deterministic text: sections, omission of empty fields, activity cap `(+ N earlier)`)
- After: update bug_reports row 6b2ef5de.

Commit `feat(leads): share lead summary — text + photo packet + deck snapshot`.

### Task 9 — Gate

Device build (`generic/platform=iOS`), test suite for new + touched bundles (sim iPhone 17 / OS 26.5), snapshot proofs via UIHostingController harness → `docs/artifacts/leads-photos-deck-share/`, `audit-design-system` pass over new UI, bible updates (03 data architecture: deck_designs.opportunity_id, opportunities.images iOS mapping; 02 workflows: lead photos/deck/share), bug_reports rows, memory updates.

**Out of scope (spawned chips):** web create-lead modal client-autocreate parity; web pipeline surfacing lead photos/decks.
