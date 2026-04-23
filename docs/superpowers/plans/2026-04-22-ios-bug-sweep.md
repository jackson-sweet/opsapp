# iOS Bug Sweep — 2026-04-22

## Goal

Drain the entire iOS open-bug backlog in one coordinated parallel pass: **32 actionable bugs** (30 `bug_reports` + 2 `qa_bugs`) split across **6 agents** working in isolated git worktrees, then integrated into one PR.

## Triage baseline (already completed in main thread)

Closed 11 bugs verified as already fixed:
- **bug_reports (8)** closed on 2026-04-22 — all fixed on `feat/photo-storage-capacity`, ship to main when that merges:
  - `60b3fecf` team seat badge → `67d6fe3`
  - `900f502c` day-sheet card spacing → `45eb21f`
  - `f2fd494f` filter sheet on tasks tab → `0faa2b3`
  - `14da5b6b` Mapbox invalid 64-size warning → `8a79644`
  - `4a3389d7` SwiftUI publishing-in-view-update → `f1e1410`
  - `913d9964` Rail task-type creation crash → `1cf99e3`
  - `91fe5417` duplicate task from project details → `858fa5e`
  - `d0a4474a` mention-grant view access → G9 series (`a0c4d38`/`11386ba`/`a9a36c0`/`c63a703`/`8a03f2f`/`83b6336`/`a8b6fe6`/`2a63d06`/`3be2497`)
- **qa_bugs (3)** closed — all covered by `2c1cd1c` already in main:
  - `3d87a999` TaskFormSheet past-date crash
  - `3dba878f` duplicate task rows (echo-race DB dupes; `858fa5e` adds belt-and-suspenders dedup)
  - `bf36d9e3` orphan task in local cache

Feature requests deferred (not part of this sweep): `e3996ac3`, `4f00c2d7`, `f7943de0`.

## Branch strategy

- **Primary branch:** `fix/ios-bug-sweep-2026-04-22` cut from `main` once `feat/photo-storage-capacity` merges.
- **Agent D** starts early: already branched as `fix/wizard-states-sync` from `feat/photo-storage-capacity` HEAD at `/Users/jacksonsweet/Projects/OPS/ios-worktrees/agent-d-wizard-sync/`. After photo-storage merges, rebase this onto updated main, then merge into the sweep branch.
- Agents A, C, E, F, G get worktrees cut from the sweep branch. Each on a sub-branch: `fix/deck-builder-sweep`, `fix/onboarding-auth-sweep`, `fix/project-details-sweep`, `fix/job-board-sweep`, `fix/home-search-notif-sweep`.
- Each sub-branch merges back into `fix/ios-bug-sweep-2026-04-22`. One PR to main at the end.

## Agent assignments (32 bugs total)

### Agent A — Deck Builder + AR (10 bugs)

**Owns:** `OPS/OPS/DeckBuilder/**`, AR scanner files under that tree. Do not touch non-DeckBuilder files.

**Bugs:**
1. `7a895c5a` — "Deck builder need to allow multiple select tool for tapping to add to selection etc"
2. `9d636a4b` — "Deck builder canvas: title and UI not laid out right. Needs to appear floating and have correct margins etc"
3. `8a40b3e3` — "Deck builder canvas area fill does not quite work right. Often filling outside the edges when dealing with construction moles shapes"
4. `fbaa6745` — "Entering dimensions manually does not work if user enters apostrophe to denote feet or quotation to denote inch"
5. `97d39b6a` — "Scan drawing does not work at all. Also takes multiple scans much too quickly. Should be a manual trigger, before snap is taken"
6. `bd5a3203` — "Deck design: canvas snap is not right — looks like 1'8 snap increments?"
7. `0c902a06` — "Deck design: nowhere to enter deck builder settings"
8. `eab5a659` — "Deck builder canvas dimensions/annotations need to scale up/down as user zooms in or out to a min/max size"
9. `89c2027a` — "AR deck scan AR labels not oriented properly"
10. `87931519` — "AR deck scan still glitchy. It becomes very slow after drawing large measurements"

**Acceptance:** Each bug individually commit-able. Test apostrophe/quote parsing in dimension entry with real character input. Scan-drawing manual trigger must have a UI affordance (tap-to-capture button instead of auto). Zoom-based dimension scaling must cap at min/max so text never becomes microscopic or fill-the-screen.

---

### Agent C — Onboarding / Auth (3 bugs)

**Owns:** `OnboardingService.swift`, `OnboardingManager.swift`, `CodeEntryScreen.swift`, `LoginScreen.swift`, `DataController.swift` (auth methods only — do not touch sync methods which belong to Agent D).

**Bugs:**
1. **`b00e9120` (qa_bugs, HIGH, requires_human_review)** — "iOS onboarding: Join Crew fails silently, bounces back to code entry — user never joined to company"
   - Root cause: `OnboardingService.joinCompany` still calls Bubble `/wf/join_company`; new users created via Google sign-in live in Firebase+Supabase only, so Bubble can't resolve the user param.
   - Fix: migrate `joinCompany` to call the Supabase RPC `public.join_user_to_company(p_user_id UUID, p_company_id UUID)` — same RPC ops-web `/api/auth/join-company` uses (verified working in production).
   - Must add a visible error path so silent bounces stop. If the RPC returns an error, surface it in the UI.
   - Existing Supabase client: `SupabaseService.shared.client`.
2. `a24e3f02` — "Wrong password when using email with says email signed up with Apple/Google sign in, not wrong password"
   - Fix: detect when the provided email already has a Firebase provider set to `apple.com` or `google.com` and show a provider-specific error.
3. `986359fd` — "Pressing check access when locked out doesn't show fail or success"
   - Fix: lockout-screen access-check button currently has no feedback. Add success/failure states with haptic (success: light notification; failure: error notification).

**Acceptance:** Agent C must verify the Supabase RPC signature via MCP before writing the call. Use `supabase_execute_sql` with a schema query on `public.join_user_to_company` if the call shape is unclear.

---

### Agent D — Sync infra: wizard_states (1 qa_bug, architectural) — STARTED

**Worktree:** `/Users/jacksonsweet/Projects/OPS/ios-worktrees/agent-d-wizard-sync/` on branch `fix/wizard-states-sync` (from `feat/photo-storage-capacity` HEAD).

**Owns:** `OPS/OPS/DataModels/WizardState.swift` (minor changes allowed), new files under `OPS/OPS/Network/Supabase/Repositories/`, new files under `OPS/OPS/Network/Supabase/DTOs/`, `OPS/OPS/Network/Sync/SyncTypes.swift`, `OPS/OPS/Network/Sync/InboundProcessor.swift`, `OPS/OPS/Network/Sync/OutboundProcessor.swift`, `OPS/OPS/Wizard/State/WizardStateManager.swift` (sync trigger hook only).

**Bug:**
- **`092f0152` (qa_bugs, MEDIUM, frequency=always)** — "wizard_states Supabase table is orphaned — iOS wizard progress never syncs"
  - Server side is complete: `public.wizard_states` exists with RLS (INSERT/SELECT/UPDATE scoped to `user_id = private.resolve_uid()::text`, role=`public` — Firebase JWT bridge compatible).
  - iOS side is entirely missing: no repository, no DTO, no sync case, not in `syncOrder`, `WizardStateManager` sets `needsSync=true` but nothing drains it.
  - **Wizard progress is per-device only today.** Users re-see completed wizards on any other device.

**Follow the DeckDesign pattern exactly** — `DeckDesignRepository.swift`, `DeckDesignDTOs.swift`, `syncOrder` entry, `syncEntityType` case, `mergeDeckDesign`, `OutboundProcessor.handleDeckDesign`, `validDeckDesignColumns` whitelist.

**Table schema (verified in Supabase on 2026-04-22):**
```
wizard_states:
  id                  uuid PK (default gen_random_uuid())
  wizard_id           text NOT NULL
  user_id             text NOT NULL
  status              text NOT NULL default 'not_started'
  current_step_index  int  NOT NULL default 0
  do_not_show         bool NOT NULL default false
  completed_at        timestamptz NULL
  total_duration_ms   int  NOT NULL default 0
  steps_skipped       int  NOT NULL default 0
  last_active_at      timestamptz NULL
  current_session_id  text NOT NULL
  created_at          timestamptz NULL default now()
  updated_at          timestamptz NULL default now()
```

Note: no `company_id` column — wizard_states is user-scoped, not company-scoped. No soft-delete column.

**Conflict resolution:** last-write-wins by `updated_at`, falling back to `last_active_at`.

**Acceptance:**
- New `WizardStateRepository` + `WizardStateDTOs` follow DeckDesign structure.
- `.wizardState` case added to `SyncEntityType` enum (and `supabaseTable` → `"wizard_states"`, `syncPriority` = 7 grouping with other user-scoped entities).
- Entry in `InboundProcessor.syncOrder` (after `.projectTask`, before `.deckDesign` — user-level data, no FK dependency on projects).
- `syncEntityType` switch case routes to a new `syncWizardStates(since:context:)`.
- `mergeWizardState` writes fields honoring `acceptableFields` guard.
- `OutboundProcessor.handleWizardState` with `validWizardStateColumns` whitelist. No arrays, all simple scalars.
- `WizardStateManager` drain trigger — when `needsSync=true` is set, enqueue a `SyncOperation` for the WizardState id so OutboundProcessor picks it up on the next push cycle.
- Include the entity in delta sync `since` map defaults.
- Do NOT add to any new migration — the server table already exists and RLS is correct.

**Commits:** one commit per file area, in this order:
1. `feat(sync): SyncEntityType.wizardState + syncPriority + supabaseTable`
2. `feat(sync): WizardStateDTO + CreateWizardStateDTO`
3. `feat(sync): WizardStateRepository`
4. `feat(sync): InboundProcessor.syncWizardStates + mergeWizardState + syncOrder entry`
5. `feat(sync): OutboundProcessor.handleWizardState + validWizardStateColumns`
6. `feat(wizard): WizardStateManager enqueues sync op on needsSync`

---

### Agent E — ProjectDetails + Project create + Map (7 bugs)

**Owns:** `OPS/OPS/Views/Components/Project/ProjectDetailsView.swift`, `ProjectDetailsViewModel.swift`, `OPS/OPS/Views/JobBoard/ProjectFormSheet.swift`, scheduler sheet, quick actions bar, `OPS/OPS/Views/Components/Map/MiniMapView.swift` and related map wiring. Do not touch ProjectDetails task list (owned by nothing — already resolved).

**Bugs:**
1. **`d40120ea` (CRASH — prioritize first)** — "App crashed when saving mark sherwood project. Perhaps because custom text in address field? (Address was not indexable by the maps address field)"
   - Repro: enter non-indexable address text into the address field of project edit form, save.
   - Fix: guard geocoder failure path. Custom text must be saved as the address string without requiring a lat/long resolution. Map pin falls back to project `city`/`postalCode` or shows empty-state.
2. `a2f7e6fa` — "Too much black space above the title on the gradient that covers map. The gradient should be pulled down further to reveal more map, and the title should be closer to the blend of the gradient"
3. `f7c663c7` — "Reschedule button from quick actions in schedule just opens project details view"
   - Fix: must open the scheduler sheet directly, not the project details view.
4. `f3604d52` — "Need to add 'clear' button to scheduler sheet"
5. `1b7e59f7` — "Add share option to iPhone, to upload photo to a project directly"
   - Implement iOS Share Extension accepting images, photos route to the selected project's photos.
6. `bec71df9` — "Some projects' project details view map is not showing address"
   - Fix: debug why `MiniMapView` sometimes fails to resolve address → coordinates. Ensure retry on first-render if coordinates are nil but address string exists.
7. `f86cf554` — "Still creating local duplicate project when creating project from project form sheet. Also need to add ability to record a deck design from within project form sheet"
   - Duplicate fix: mirror the TaskFormSheet dedup pattern (`858fa5e`) on project create — dedupe after cascade + 3s later, winner by `needsSync=true` then freshest `lastSyncedAt`.
   - Deck design recording: add a button in ProjectFormSheet → launch deck design capture flow → attach result to project on create.

---

### Agent F — Job Board / Wizard / Project list (6 bugs)

**Owns:** `OPS/OPS/Views/JobBoard/**` (except TaskFormSheet which is already resolved), `OPS/OPS/Views/MainTabView.swift` (tab transitions), WizardBanner components.

**Bugs:**
1. `da5743d8` — "Need to show badges for completed when project is completed, or closed when closed, or archived when archived"
   - Add status badges on project cards in the list.
2. `00fdb024` — "Tab to tab transitions (schedule to job board to home to settings etc) do not have proper animations — to job board is a horizontal swipe in, otherwise fade in/out. Need to standardize"
   - Standardize: all tab transitions use a horizontal swipe. Document the convention.
3. `74fcaac1` — "Wizard banner dismisses very glitchy. Not smooth animation"
   - Fix dismiss animation: use `withAnimation(.easeInOut(duration: ...))` + proper `.transition` modifier; ensure the banner's height collapse is synced with the opacity fade.
4. `ae77d32a` — "Job board wizard is not great — the see closed projects step closed button is hidden by the wizard banner at bottom. Also, no completed wizard confirmation. Also wizard does not mention swiping to change statuses"
   - Three sub-fixes: (a) anchor the closed-projects button above wizard banner, (b) show completion confirmation, (c) add swipe-to-change-status step.
5. `6c4e5b2b` (triaged) — "Need to remove RFQ and Estimated phases from projects (pipeline takes over these phases?) or brainstorm this a bit"
   - Flag for human brainstorm — do NOT unilaterally remove. File a short doc `docs/superpowers/plans/2026-04-22-project-phases-pipeline-overlap.md` with current code refs + the overlap question and mark the bug as `triaged` with a pointer.
6. `92f34567` — "Project list needs to default to sort by latest edited/created"
   - Default sort: `updatedAt` desc (fallback to `createdAt` desc). Persist user override in `@AppStorage`.

---

### Agent G — Home / Search / Notifications / Settings (5 bugs)

**Owns:** Home tab view, `UniversalSearchSheet.swift`, Spotlight indexing glue, `NotificationListView.swift`, `OPS/OPS/Views/Settings/**` (search bar only — do not touch photo storage settings, those belong to the photo-storage branch).

**Bugs:**
1. `7186ac66` — "The spotlight search result for client opens client form sheet editing. Should just open client contact"
   - Fix: client Spotlight handler must route to the client details/contact view, not the form sheet.
2. `3add35ff` — "Need to redesign notifications list (too much text)"
   - Condense: title (16pt bold) + single-line body (14pt) + timestamp. No long-form descriptions in the cell. Move detail to the tap-through target.
3. `89777d09` — "Need notification for items stacking up in task review and payment review etc"
   - Create notification emitters for: unseen items in task-review queue (>5), payment-review queue (>3). Use the existing notification rail (see `ops-software-bible/07_SPECIALIZED_FEATURES.md` Section 14). Daily cap on cadence.
4. `3f72c738` — "Search needs to index sub contacts too"
   - Extend Spotlight indexing to include `SubClient` rows. Add to `SpotlightIndexManager` + `SpotlightBackfillCoordinator`.
5. `ebd7fe66` — "Remove settings bar from page content, and instead replace the search button in app header on settings view with an input field that grows to full width when clicked, and searches settings specifically"
   - UX change: remove the inline settings-search bar in the settings content. Wire up the AppHeader search button (on Settings tab only) to expand-to-input. Scope the search to settings fields only.

---

## Conventions (ALL agents must follow)

### Design tokens
Use `OPSStyle` exclusively — never hardcode color, font, spacing, or radius values. Reference:
- `OPS/OPS/Styles/OPSStyle.swift`
- `OPS/OPS/Styles/Components/**`

### Build verification
Per `OPS/CLAUDE.md`: never use the simulator. Build with:
```
xcodebuild -scheme OPS -destination 'generic/platform=iOS'
```

### Commit format
- Prefix: `fix(<area>):` or `feat(<area>):` — e.g. `fix(deck-builder): clamp dimension label scale at min/max zoom`
- Second line blank
- Third line: `Bug <id> — <short description>.`
- Never include Claude or AI as co-author.

### Supabase row closure
After each bug is fixed and pushed, update the corresponding Supabase row:
```sql
-- bug_reports
UPDATE public.bug_reports SET status='resolved', resolved_at=now(), updated_at=now(),
  resolution_notes='Fixed in <SHA> on fix/ios-bug-sweep-2026-04-22. <brief>'
WHERE id='<bug_id>';

-- qa_bugs
UPDATE public.qa_bugs SET status='closed', verified=true, verified_at=now(), closed_at=now(),
  updated_at=now(), fix_commit='<SHA>', fix_branch='fix/ios-bug-sweep-2026-04-22',
  fix_notes='<brief>', verification_notes='<how verified>'
WHERE id='<bug_id>';
```

### Field-first checks (from OPS/CLAUDE.md)
- Touch targets ≥44×44pt (60×60 for primary actions)
- Text ≥16pt, primary info ≥18pt
- Haptics on meaningful interactions

### Testing
Agents do not build-verify themselves — main thread runs `xcodebuild` after merging all sub-branches into `fix/ios-bug-sweep-2026-04-22`.

## Integration order

Once all agents report completion:
1. Build-verify `fix/wizard-states-sync` standalone → if green, merge to sweep branch.
2. Merge A, C, E, F, G sub-branches into sweep branch one at a time, build-verify after each merge.
3. Open one PR: `fix/ios-bug-sweep-2026-04-22 → main`.
4. Batch-update Supabase rows (all 32) pointing to their respective commits.
