# Unified Log Activity — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use `superpowers:executing-plans` (or `custom-skills:executing-plans` for OPS design enforcement) to implement this plan task-by-task. Every UI task MUST run through `ops-design`, `custom-skills:mobile-ux-design`, `custom-skills:ui-ux-pro-max`, `ops-copywriter`, and pass `custom-skills:audit-design-system` before it is called done.

**Goal:** Replace the three redundant iOS activity loggers with ONE OPS-native "Log Activity" capture that persists every field it collects, attaches an activity to a lead / client / job, keeps voice-first capture, detects follow-ups, and lets a completed site visit post itself to the timeline.

**Architecture:** A new `ActivityRepository` + `ActivityTarget` enum own the write path (one parent column per row). A single `UnifiedLogActivitySheet` + `UnifiedLogActivityViewModel` — built from the existing `LeadFormView` primitives and the `CallCaptureCoordinator`/dedup/provenance/voice machinery — replaces `LogActivitySheet`, `LeadLogActivitySheet`, and `LogCallSheet`. The `activities` table already supports every parent + field (no schema migration for core capture); the only net-new backend behavior is an **app-side** site-visit auto-post (the iOS `SiteVisit` model is local-only, so a DB trigger can never fire).

**Tech Stack:** SwiftUI (iOS 17.6 target), SwiftData, Supabase (PostgREST via `supabase-swift`), Speech framework, `NSDataDetector`. Backend: Postgres (project `ijeekuhbatykdomumfjx`).

**Design System:** `ops-design-system/project/DESIGN.md` + `ops-design-system/project/mobile/MOBILE.md`; iOS tokens in `ops-ios/OPS/Styles/OPSStyle.swift`. No `.interface-design/system.md` in this repo — DESIGN.md/MOBILE.md are the authority.

**Required Skills:** `ops-design`, `custom-skills:mobile-ux-design`, `custom-skills:ui-ux-pro-max`, `ops-copywriter`, `custom-skills:audit-design-system`, `custom-skills:wizard-audit` (for the capture flow's failure modes), `animation-studio:animation-architect` + `animation-studio:ios-animations` (voice pulse / chip / footer motion).

**Execution environment:** Build this in a **dedicated git worktree** off `ops-ios` `main` (large feature; parallel sessions touch `FloatingActionMenu.swift` and the DTOs). Copy `OPS/Utilities/Secrets.xcconfig` into the worktree and build with `-clonedSourcePackagesDirPath .spm-local -destination 'generic/platform=iOS'`. **Preserve CRLF/mixed line endings** on every edited file (`FloatingActionMenu.swift`, `OpportunityDTOs.swift`, etc.) — do not let the editor normalize to LF.

---

## Ground truth (verified 2026-07-05 against code + live DB)

**Backend (no migration needed for core capture):**
- `activities` parents: `opportunity_id`(uuid, FK opportunities), `client_id`(uuid, **no FK**), `project_id`(**TEXT**, no FK), `site_visit_id`(uuid, FK site_visits), `estimate_id`, `invoice_id`. Exactly one parent per row.
- `company_id` uuid **NOT NULL, no default** — highest-risk field; every insert MUST set it to the operator's `users.company_id`.
- `subject` NOT NULL but backfilled by `trg_activities_default_subject` (BEFORE INSERT) — send `nil`, DB fills a per-type label (`site_visit`→"Site visit", `call`→"Call", etc.), or first line of `content`.
- `tr_activities_first_log_auto_advance` (AFTER INSERT) advances a `new_lead` opportunity → `qualifying` on its first activity and writes a `stage_transitions` row (`transitioned_by = created_by`). No-ops when `opportunity_id IS NULL`. **Preserve — free behavior; just thread `opportunity_id` + `created_by`.**
- RLS: one policy `company_isolation` FOR ALL, `USING (company_id = private.get_user_company_id())`, WITH CHECK null → INSERT reuses USING. `get_user_company_id()` matches JWT `sub` against `users.auth_id`/`firebase_uid` — **never** `auth.uid()`. Firebase-bridge anon insert is safe. anon has full grants. Client-only / project-only inserts are already RLS-legal.
- `created_by` uuid, nullable, **no FK**, empirically = `public.users.id`. Stamp `dataController.currentUser?.id` (Supabase users.id, NOT Firebase UID — same value `SiteVisitCaptureView.swift:806` and `ProjectFormSheet.swift:3082` already use).
- `type` CHECK set (send only these): `note,email,call,meeting,estimate_sent,estimate_accepted,estimate_declined,invoice_sent,payment_received,stage_change,created,won,lost,system,site_visit,site_visit_scheduled`. There is **no** `text`/`sms` value → map SMS to `note` OR add a new value via migration (see Task 0.0). `direction` CHECK: `inbound`/`outbound` only (else NULL). `outcome`/`duration_minutes` unconstrained.
- **Site visits are LOCAL-ONLY in iOS** — zero `from("site_visits")` in the codebase; `SiteVisit` is a local SwiftData entity; `completeVisit()` writes locally only. A DB trigger on `site_visits` can never fire. Auto-post MUST be an app-side `activities` insert.

**iOS (data-loss bug + fragmentation):**
- `LogActivityViewModel.save()` (`LogActivityViewModel.swift:223-232`) hardcodes `subject:nil, direction:nil, outcome:nil, durationMinutes:nil` — collected then discarded. `LeadDetailViewModel.logActivity` (`LeadDetailViewModel.swift:60-76`) threads them correctly = reference implementation, but omits `created_by`.
- Three loggers funnel through `OpportunityRepository.logActivity`: `LogActivityViewModel.save()`, `LeadDetailViewModel.logActivity()` (used by `LeadLogActivitySheet` + `LogCallViewModel`), `MainTabView.autoLogOutboundCall` (`MainTabView.swift:1288`).
- Reusable primitives (all non-private, cross-file consumed today) in `LeadFormView.swift`: `SheetTitleLabel`(661), `SheetStatusLine`(689), `SheetFooterButtonRow`(615), `SheetCTAButton`(531), `LeadField`(273), `LeadChipPicker`+`LeadChipOption`(417/408), `LeadTextInput`/`LeadTextArea`(304/356), `SheetCloseButton`(639). `footerOverlay` gradient block is **copy-pasted** in both lead sheets (`LeadLogActivitySheet.swift:248-296` == `LogCallSheet.swift:393-437`).
- `LogCallSheet` irreplaceable behavior: `CallCaptureCoordinator` (post-call/FAB/Siri bus + dedup), lead mode-lock (`lockedLeadSection`), live phone dedup (`LogCallViewModel` `loadCandidates`/`runDedup`/`findByContactPhone`), call provenance (`call_source`/`caller_number`/`call_started_at`), inline DICTATE voice pill.
- `Activity` @Model already carries `outcome`/`durationMinutes`/`direction`/`createdBy`; they simply have **no render path** in `ActivityTimeline.swift`.
- `Client`/`Project` SwiftData models exist for the picker; `SiteVisitIdentityPanel.loadSearchSources` (`SiteVisitCaptureView.swift:1364-1390`) is the battle-tested cross-source fetch to lift.

**Multi-parent precedent to mirror:** `FollowUp.swift` @Model + `FollowUpDTO` already do `companyId` non-optional, `opportunityId`/`clientId`/`createdBy` nullable.

---

## Scope

**In scope (this plan):**
1. Data layer: `ActivityTarget`, `ActivityRepository`, additive DTO/@Model widening, author stamping, **data-loss fix**.
2. One `UnifiedLogActivitySheet` + VM replacing all three loggers; correspondence-only types; state-aware lead/client/job target; standard `SheetTitleLabel` header + footer CTA; voice DICTATE pill.
3. Voice follow-up detection + parse-on-error fix.
4. `ActivityTimeline` renders outcome/duration.
5. Site-visit → timeline app-side auto-post.
6. Client & Job activity timelines (Phase 6) — needs a minimal client/job detail surface; this is the largest piece and is checkpointed separately.

**Explicitly NOT in scope:** folding `SiteVisitCaptureView` (checklist/measurement/photo/deck) into the logger; changing `project_id` to uuid or adding FKs; backfilling historical rows.

---

## Phase 0 — Data layer foundation (additive; no UI)

### Task 0.0: Decide the SMS/text type (product micro-decision)

**Decision:** The `activities_type_check` has no `text`/`sms`. Two options: (a) map "TEXT" chip → `note` type (zero migration, but loses text/call distinction), or (b) additive migration adding `sms` to the CHECK set. **Recommendation: (b)** — a text message is a distinct correspondence type worth its own filter/icon, and the migration is additive-safe (widening a CHECK never breaks shipped iOS).

**Files:**
- Create migration (apply to `ijeekuhbatykdomumfjx`): drop+recreate `activities_type_check` adding `'sms'` (and keep `site_visit_scheduled`). Additive per [iOS sync constraint].

**Step 1:** Write migration SQL:
```sql
ALTER TABLE public.activities DROP CONSTRAINT activities_type_check;
ALTER TABLE public.activities ADD CONSTRAINT activities_type_check CHECK (type IN (
  'note','email','call','meeting','sms',
  'estimate_sent','estimate_accepted','estimate_declined','invoice_sent','payment_received',
  'stage_change','created','won','lost','system','site_visit','site_visit_scheduled'
));
```
**Step 2:** Apply via Supabase MCP `apply_migration` (name `add_sms_activity_type`). **Step 3:** Verify: `SELECT pg_get_constraintdef(oid) FROM pg_constraint WHERE conname='activities_type_check';` includes `sms`. **Step 4:** Update `ops-software-bible/03_DATA_ARCHITECTURE.md` activities type list. **Step 5:** Commit (`feat(db): add sms to activities type check`).

> If Jackson prefers zero DB change for v1, skip 0.0 and map TEXT→`note`; note the lost distinction. Default to (b).

### Task 0.1: Widen `CreateActivityDTO` (additive)

**Files:** Modify `ops-ios/OPS/Network/Supabase/DTOs/OpportunityDTOs.swift:377-432`.

**Step 1 (test):** Add `OPSTests/DTOs/CreateActivityDTOTests.swift` asserting the synthesized encoder **omits** nil parent keys (PostgREST must not receive `opportunity_id: null` for a client-targeted row):
```swift
func test_encoder_omits_nil_opportunity_id() throws {
    let dto = CreateActivityDTO(clientId: "c1", companyId: "co1", type: "note", createdBy: "u1")
    let json = String(data: try JSONEncoder().encode(dto), encoding: .utf8)!
    XCTAssertFalse(json.contains("opportunity_id"))
    XCTAssertTrue(json.contains("\"client_id\":\"c1\""))
    XCTAssertTrue(json.contains("\"company_id\":\"co1\""))
    XCTAssertTrue(json.contains("\"created_by\":\"u1\""))
}
```
**Step 2:** Run — expect FAIL (compile: `clientId`/`createdBy` don't exist; opportunityId required).
**Step 3 (impl):** Make `opportunityId` `String?`; add `clientId`/`projectId`/`siteVisitId`/`createdBy` (`String?`), CodingKeys `client_id`/`project_id`/`site_visit_id`/`created_by`; keep `companyId`/`type` required; extend the explicit `init` with all new optionals defaulted `nil` (so `MainTabView:1288`, `LeadDetailViewModel:61`, around-call all still compile). Confirm the DTO relies on the **synthesized** `encode` (Swift omits nil optionals) — do NOT hand-write an encoder that force-encodes nils.
**Step 4:** Run — expect PASS. **Step 5:** Commit (`feat(ios): widen CreateActivityDTO to all activity parents + created_by`).

### Task 0.2: Extend `ActivityDTO` decode + toModel

**Files:** Modify `OpportunityDTOs.swift:311-374`.
**Step 1 (test):** decode a JSON fixture with `client_id`/`project_id` → `toModel()` sets `clientId`/`projectId`. **Step 2:** FAIL. **Step 3:** add `clientId`/`projectId` decode (keys `client_id`/`project_id`), set in `toModel()`. **Step 4:** PASS. **Step 5:** Commit.

### Task 0.3: Extend `Activity` @Model additively

**Files:** Modify `ops-ios/OPS/DataModels/Supabase/Activity.swift`; check `DataModels/Migrations/OPSSchema*.swift`.
**Design tokens:** none (model).
**Step 1:** Confirm the SwiftData versioned schema does not pin `opportunityId` non-null in a way that blocks widening (read the latest `OPSSchemaV*` that registers `Activity`). If `Activity` is registered by class reference (not a frozen property list), widening `opportunityId` String→String? + adding `clientId`/`projectId` is a lightweight migration.
**Step 2:** Make `opportunityId: String?`; add `var clientId: String?` and `var projectId: String?` (mirror the nullable call-provenance fields). `createdBy` already exists (`Activity.swift:35`). Keep `init` backward-compatible (post-init assignment for new fields).
**Step 3:** Build (`xcodebuild -scheme OPS -destination 'generic/platform=iOS' -clonedSourcePackagesDirPath .spm-local build`). Expect clean.
**Step 4:** Launch in simulator, confirm existing activities still load (no SwiftData migration crash). **Step 5:** Commit.

**Risk:** nullability widening — if a versioned schema pins `opportunityId` required, add a new `OPSSchemaV<N+1>` + migration stage. Verify before shipping.

### Task 0.4: `ActivityTarget` enum (new)

**Files:** Create `ops-ios/OPS/DataModels/ActivityTarget.swift`.
**Step 1 (test):** `OPSTests/DataModels/ActivityTargetTests.swift` — each case maps to exactly one parent column + id; `unbound` maps to none:
```swift
func test_target_parent_mapping() {
    XCTAssertEqual(ActivityTarget.opportunity(oppFixture).parentKey, .opportunity("opp1"))
    XCTAssertEqual(ActivityTarget.client(clientFixture).parentKey, .client("cli1"))
    XCTAssertEqual(ActivityTarget.project(projFixture).parentKey, .project("prj1"))
    XCTAssertNil(ActivityTarget.unbound.parentKey)
}
```
**Step 2:** FAIL. **Step 3 (impl):**
```swift
enum ActivityTarget: Equatable {
    case opportunity(Opportunity), client(Client), project(Project), unbound
    enum ParentKey: Equatable { case opportunity(String), client(String), project(String) }
    var parentKey: ParentKey? { … }          // exactly one, or nil for .unbound
    var displayName: String { … }            // contactName / client.name / project.title
    var subtitle: String? { … }              // stage / address
    var sourceBadge: String? { … }           // "LEAD" / "CLIENT" / "JOB"
    var companyId: String? { … }
}
```
**Step 4:** PASS. **Step 5:** Commit.

### Task 0.5: `ActivityRepository` (new) — the single write path

**Files:** Create `ops-ios/OPS/Network/Supabase/Repositories/ActivityRepository.swift`. Modify `OpportunityRepository.swift:131-159` to forward.
**Step 1 (test):** `OPSTests/Repositories/ActivityRepositoryTests.swift` — `buildDTO(target:type:...createdBy:)` produces a DTO with exactly one parent set + `company_id` + `created_by` always present; `direction` clamped to `inbound`/`outbound`/nil; empty `outcome`→nil; `durationMinutes==0`→nil.
**Step 2:** FAIL. **Step 3 (impl):**
```swift
final class ActivityRepository {
    private let client; private let companyId: String
    init(companyId: String, client: SupabaseClient = SupabaseManager.shared.client) { … }
    func logActivity(target: ActivityTarget, type: ActivityType,
                     subject: String? = nil, body: String? = nil,
                     direction: String? = nil, outcome: String? = nil, durationMinutes: Int? = nil,
                     callSource: String? = nil, callerNumber: String? = nil, callStartedAt: Date? = nil,
                     siteVisitId: String? = nil, createdBy: String?) async throws -> ActivityDTO {
        let dto = Self.buildDTO(target: target, companyId: companyId, type: type.rawValue,
                                subject: subject, body: body,
                                direction: Self.clampDirection(direction),
                                outcome: outcome?.nilIfBlank, durationMinutes: durationMinutes.flatMap { $0 > 0 ? $0 : nil },
                                callSource: callSource, callerNumber: callerNumber,
                                callStartedAt: callStartedAt.map(SupabaseDate.format), siteVisitId: siteVisitId,
                                createdBy: createdBy)
        return try await client.from("activities").insert(dto).select().single().execute().value
    }
    func deleteActivity(_ id: String) async throws { … }   // moved from OpportunityRepository (verbatim)
    func fetchActivities(byOpportunity: String) async throws -> [ActivityDTO] { … }
    func fetchActivities(byClient: String) async throws -> [ActivityDTO] { … }   // .eq("client_id", …)
    func fetchActivities(byProject: String) async throws -> [ActivityDTO] { … }  // .eq("project_id", …)
    static func buildDTO(...) -> CreateActivityDTO { switch target.parentKey … }
}
```
Keep `OpportunityRepository.logActivity`/`deleteActivity` as thin forwarders to `ActivityRepository` so the three call sites migrate incrementally.
**Step 4:** PASS + build clean. **Step 5:** Commit (`feat(ios): ActivityRepository as unified activities write path`).

### Task 0.6: Migrate call sites + fix the data-loss bug + stamp author

**Files:** `LogActivityViewModel.swift:186-248`, `LeadDetailViewModel.swift:60-76`, `MainTabView.swift:1288-1301`.
**Step 1 (test):** In `LogActivityViewModel`, a save with direction/outcome/duration set produces a DTO carrying them (not nil). (Extract DTO build into a testable func or assert via a repository spy.)
**Step 2:** FAIL (today they're nil).
**Step 3 (impl):**
- `LogActivityViewModel.save()`: call `ActivityRepository.logActivity(target: .opportunity(opportunityId), type: selectedType, subject: nil, body: notesText.nilIfBlank, direction: showDirectionField ? direction : nil, outcome: outcome.nilIfBlank, durationMinutes: showDurationField ? durationMinutes : nil, createdBy: userId)`. **Delete the `nil` hardcodes.**
- `LeadDetailViewModel.logActivity`: route through `ActivityRepository`; inject `dataController.currentUser?.id` as `createdBy` (currently omitted → fixes bug ④). This covers `LeadLogActivitySheet` + `LogCallViewModel`.
- `MainTabView.autoLogOutboundCall`: same, `createdBy` stamped.
**Step 4:** PASS + build. Manual: log a call with direction=inbound, outcome="left voicemail", duration=6 on a lead → confirm the row in DB has all three + `created_by` (`SELECT direction,outcome,duration_minutes,created_by FROM activities ORDER BY created_at DESC LIMIT 1`).
**Step 5:** Commit (`fix(ios): stop discarding activity direction/outcome/duration; stamp created_by`).

> **This single phase already fixes the headline bug (data loss) and author attribution — shippable on its own if we want an early win before the UI rebuild.**

---

## Phase 1 — Voice: follow-up detection + parse-on-error fix

### Task 1.1: Follow-up detection on `ActivityDraft`

**Skills:** none (pure logic).
**Files:** `ops-ios/OPS/Services/VoiceActivityParser.swift`.
**Step 1 (test):** `OPSTests/Services/VoiceActivityParserFollowUpTests.swift`, using an injected reference date (Tue 2026-07-07 10:00 local):
```swift
func test_callback_tuesday_sets_next_future_tuesday() {
    let d = VoiceActivityParser.parse(transcription: "called John, callback Tuesday", opportunities: [], now: ref)
    XCTAssertNotNil(d.suggestedFollowUpDueAt)      // next FUTURE Tue (>= ref+1d), 09:00 local
    XCTAssertEqual(d.suggestedFollowUpTitle, "Follow up with John")
}
func test_incidental_date_without_cue_makes_no_followup() {
    let d = VoiceActivityParser.parse(transcription: "met him Monday about the deck", opportunities: [], now: ref)
    XCTAssertNil(d.suggestedFollowUpDueAt)          // no cue word → no suggestion
}
```
**Step 2:** FAIL. **Step 3 (impl):** add `now: Date = Date()` param (default keeps callers compiling); add `var suggestedFollowUpDueAt: Date?` + `var suggestedFollowUpTitle: String?` to `ActivityDraft` (default nil). After `cleanNotes`, run `detectFollowUp(rawTranscription:now:)`: `NSDataDetector(.date)` over the FULL raw transcript, **gated** by a cue set (`follow up`, `follow-up`, `followup`, `call back`, `callback`, `circle back`, `check in`, `reach out`, `remind me`, `next week`, `next month`); take first date match; roll a past/same-instant result forward to the next future occurrence (`Calendar.current`); default a date-only match to 09:00 local; title = `"Follow up with \(name)"` else `"Follow up"`.
**Step 4:** PASS (include timezone + roll-forward edge tests). **Step 5:** Commit.

**Risks (from research):** pin `Calendar.current`, pass reference date for testability, mandatory roll-forward, never auto-persist.

### Task 1.2: Parse-on-error fix

**Files:** `LogActivitySheet.swift:84-89` (and the equivalent hook in the new unified sheet). 
**Step 1:** The `.onChange(of: speechManager.state)` only fires `parseTranscription()` on `.recording → .idle`; error-terminated dictation goes `.recording → .error` and never parses. **Step 2 (impl):** broaden the condition to also fire on `.recording → .error(...)` when `transcription` is non-empty (the `parseTranscription` empty-guard at `LogActivityViewModel.swift:131` makes this safe), and surface a `SheetStatusLine.error` so the operator gets feedback. **Step 3:** Manual: kill mid-dictation (airplane mode) → partial transcript still parses + error line shows. **Step 4:** Commit. *(Applied in the unified sheet in Phase 3; if Phase 3 lands first, fold this in there.)*

---

## Phase 2 — Timeline renders outcome + duration

### Task 2.1: `ActivityTimeline` metadata micro-line

**Skills:** `ops-design`, `custom-skills:audit-design-system`.
**Files:** `ops-ios/OPS/Views/Leads/Components/ActivityTimeline.swift` (`ActivityRow` ~76-179; previews 201-253).
**Design tokens:** value line `OPSStyle.Typography.metadata` (JetBrains Mono 11) at `Colors.text3`; outcome color via **semantic allowlist only** (`connected`/`answered` → `Colors.olive`; negative outcomes → `roseTextM`; else `text3`); **never `textMute`** for values (decorative-only per `OPSStyle.swift:25,161`). Duration stays neutral `text3`.
**Step 1:** Add a `lineLimit(1)` metadata `HStack` below title/body (after line 96) from `durationMinutes` (`formatDuration`, mirror `ageString` 165-178) + `outcome` (`formatOutcome` title-cases snake_case). Keep the existing direction arrow (139-156) + olive-inbound icon tint (132-136).
**Step 2:** Update both previews to set real `durationMinutes`/`outcome` (stop faking via bodyText).
**Step 3:** Snapshot via `OPSTests/Views/BooksSnapshotTests.swift` harness (render `ActivityTimeline` to PNG) — attach before/after. Verify divider/padding at 52-55/108 with the third line.
**Step 4:** Run `custom-skills:audit-design-system` — zero hardcoded values. **Step 5:** Commit.

> Do NOT touch `ActivityTabView`/`ActivityEntryView` — that is the separate `project_notes` subsystem, not the activities table.

---

## Phase 3 — The unified capture sheet (the core)

> **Skills for ALL of Phase 3:** load `ops-design` + `custom-skills:mobile-ux-design` + `custom-skills:ui-ux-pro-max` for layout/hierarchy, `ops-copywriter` for every string, `animation-studio:animation-architect` → `animation-studio:ios-animations` for the voice pulse / chip-select / footer motion, `custom-skills:wizard-audit` to war-game the capture's failure modes, and `custom-skills:audit-design-system` before each task is called done. Motion uses the one OPS curve `cubic-bezier(0.22,1,0.36,1)`, durations per MOBILE.md §11; honor Reduce Motion.

### Task 3.1: Extract `SheetFooterOverlay` (kill the copy-paste)

**Files:** Create `ops-ios/OPS/Styles/Components/SheetFooterOverlay.swift`; refactor `LeadLogActivitySheet.swift:248-296` and `LogCallSheet.swift:393-437` to use it (temporarily, before they're deleted — this proves the extraction).
**Design tokens:** gradient scrim `black 0 → 0.95 → 1.0`, height 160, `.allowsHitTesting(false)`, `.ignoresSafeArea(edges:.bottom)`; hosts `SheetStatusLine` + `SheetFooterButtonRow`.
**Step 1:** Extract as `struct SheetFooterOverlay<Primary:View>: View { var status: SheetStatusLine.Mode?; var cancelLabel="CANCEL"; let onCancel; @ViewBuilder primary }`. **Step 2:** Point both lead sheets at it; build; visually unchanged (snapshot). **Step 3:** Commit.

### Task 3.2: `ActivityTargetPickerView` (leads + clients + jobs)

**Skills:** `ops-design`, `mobile-ux-design`, `ui-ux-pro-max`, `ops-copywriter`, `audit-design-system`.
**Files:** Rename/generalize `ops-ios/OPS/Views/Pipeline/OpportunityPickerView.swift` → `ActivityTargetPickerView.swift`. New shared loader `ActivityTargetLoader` lifted from `SiteVisitCaptureView.swift:1364-1390`.
**Design tokens:** row = MOBILE.md §7.1 standard row (min 48pt, Mohave 15 primary, JetBrains Mono 10 uppercase secondary); source badge = neutral tag (JetBrains Mono, `Colors.text2`, `line` border, 4px) reading `LEAD`/`CLIENT`/`JOB` — **not** accent, **not** earth-tone. Search field per MOBILE.md §9. Selection = white surface shift, never green.
**Step 1:** `ActivityTargetLoader.load(companyId:)` → fetch-all + in-memory filter (NEVER enum `#Predicate`): Opportunities (`!stage.isTerminal && !isDeleted`), Clients (`companyId==nil || ==X`, `deletedAt==nil`, include `subClients`), Projects (`companyId==X && deletedAt==nil && !status.isTerminal`). Mirror `loadSearchSources`.
**Step 2:** Row model renders name + subtitle + source badge; multi-field lowercase-contains search (reuse `SiteVisitIdentitySuggestion.matches` pattern, add `.project`). Keep the inline **+ New Lead** affordance (leads only).
**Step 3:** Snapshot each source type + empty/search states. **Step 4:** `audit-design-system`. **Step 5:** Commit.

**Design-judgment guard (from research):** activities are 94% opportunity / 7% client / 0% project today. Do NOT present three equal target columns — the picker defaults to the entry point's known parent (Phase 3.4) and only exposes alternates on demand. Avoid the QuickBooks+Sage failure.

### Task 3.3: `UnifiedLogActivityViewModel`

**Files:** Create `ops-ios/OPS/ViewModels/UnifiedLogActivityViewModel.swift`. Move `LogCallViewModel` dedup/provenance logic in before deleting it.
**Step 1 (tests):** entry-point resolution (`leadDetail`/`postCall`/`capture`/`genericFAB` → lock state, default direction, detent, prefilled type); save routes through `ActivityRepository.logActivity` with all fields + `createdBy`; for `type==.call` it threads `resolvedSource`/`PhoneNumber.normalize(number)`/`callStartedAt`; conditional fields resolve to nil when their section is hidden (mirror `LeadLogActivitySheet.swift:300-346`); follow-up `SET` calls the existing `CreateFollowUpDTO → OpportunityRepository.createFollowUp` path with `dueAt` = suggestion, type mapped from activity type.
**Step 2:** FAIL. **Step 3 (impl):** merge:
- `target: ActivityTarget` (+ `initialTarget`), `loadTargets()` via `ActivityTargetLoader`.
- Call facet: mode-lock (`leadIsLocked`/`knownOpportunityId`), live dedup (`loadCandidates`/`runDedup`/`matchLead`/`findByContactPhone`), provenance.
- Voice: `SpeechRecognitionManager` + `applyTranscription` on `.recording→(.idle|.error)`, follow-up suggestion state from `ActivityDraft`.
- `save()` → `ActivityRepository`; then optional `setFollowUp()`; post `LeadActivityLoggedSuccess`; bump `lastActivityAt` for the bound opportunity.
**Step 4:** PASS + build. **Step 5:** Commit.

**Guard:** post-only against a **synced** opportunity id (FK) — for a still-local lead, post against `client_id` or defer. `company_id` always set (highest-risk field). Preserve the first-log auto-advance by threading `opportunity_id` + `created_by`.

### Task 3.4: `UnifiedLogActivitySheet`

**Skills:** all Phase-3 skills; **`ops-copywriter` owns every string.**
**Files:** Create `ops-ios/OPS/Views/Pipeline/UnifiedLogActivitySheet.swift`.
**Design tokens / structure (top→bottom):**
1. **Header** — `SheetTitleLabel("LOG ACTIVITY", size: .full)` (Cake Mono, left, **no `//`**), drag handle for detented entry; `SheetCloseButton` only when target is not locked. Optional context subline `// CALLED <NAME>` (JetBrains Mono, `text3`) when call-provenance present (mirror `LogCallSheet.swift:116-140`).
2. **Voice** — inline DICTATE pill in the NOTE field header (lift `LogCallSheet.swift:329-369`): `SYS :: READY` / `SYS :: LISTENING` + pulse ring + live transcript; folds into body on stop. Motion via `animation-studio:ios-animations`, one OPS curve, Reduce-Motion fallback.
3. **`// TYPE`** — `LeadChipPicker`, correspondence-only: `CALL`, `EMAIL`, `TEXT`, `MEETING`, `NOTE`. **No SITE VISIT chip.** Selection = white surface shift (not green). 4px chips.
4. **`// AGAINST`** — state-aware target zone: locked chip (reuse bound-state UI `SiteVisitCaptureView.swift:1067-1100`, olive `person.crop.circle.badge.checkmark`, X to clear) when `initialTarget != .unbound`; else the `ActivityTargetPickerView` trigger row. Sub-hint (mono, `mute`): "follows to the job when won".
5. **`// DETAIL`** — conditional `DIRECTION` (call/email; segmented OUT/IN), `DURATION` (call/meeting; mono `NN MIN`), `OUTCOME` (all but note) using `LeadField` + `LeadChipPicker`/`LeadTextInput`. Reuse `LeadLogActivitySheet` show-rules. Optional `SUBJECT`.
6. **Follow-up** — when `viewModel.suggestedFollowUp != nil`, a compact row `◆ FOLLOW-UP · <DATE>` + `SET` (tan hairline, semantic; `ops-copywriter` final copy). Never auto-persist.
7. **Footer** — `SheetFooterOverlay` with `SheetStatusLine` (`.syncing`/`.error`) + `SheetFooterButtonRow(CANCEL / primary)`; primary label `LOG` (or `LOG CALL` in call mode); accent fill = the **one** accent element on the sheet.
**Step 1:** Build the view composing the primitives. **Step 2:** Snapshot each entry point (leadDetail locked / genericFAB picker / postCall locked+provenance) + each type's conditional fields, via the snapshot harness — attach PNGs. **Step 3:** `custom-skills:wizard-audit` the flow (no target, offline, permission denied, mic denied, ambiguous match, new-lead-no-contact). **Step 4:** `custom-skills:audit-design-system` → zero hardcoded values; verify no `//` on the title, no green selection, sharp corners, one accent. **Step 5:** Commit.

### Task 3.5: Repoint every entry point

**Files:** `FloatingActionMenu.swift` (`:300-309` Log Activity, `:312-327` Log a Call, `:852-854` sheet, `:858` site-visit cover), the lead-detail LOG action call site, `CallCaptureCoordinator` consumers (`MainTabView` drain), Siri AppIntent chain.
**Step 1:** Collapse FAB "Log Activity" + "Log a Call" into ONE "Log Activity" item presenting `UnifiedLogActivitySheet(initialTarget: .unbound)`. Route `CallCaptureCoordinator.activeRequest` into the unified sheet (type prefilled `.call`, provenance/lock applied) instead of `LogCallSheet`. Leave the `SiteVisitCaptureView` `fullScreenCover` (`:858`) **untouched**.
**Step 2:** Repoint the lead-detail LOG action to `UnifiedLogActivitySheet(initialTarget: .opportunity(opp))` — preserves `LeadActivityLoggedSuccess` + `lastActivityAt`.
**Step 3:** Verify the Siri/App-Shortcut → `CallCaptureCoordinator` → sheet chain (queue/drain + 5-min expiry + `CallCaptureRequest.id` dedup) still lands in the unified sheet. **Step 4:** Build; manual test all three entry points. **Preserve CRLF.** **Step 5:** Commit.

### Task 3.6: Delete the three old loggers

**Files:** Delete `Views/Pipeline/LogActivitySheet.swift`, `ViewModels/LogActivityViewModel.swift`, `Views/Leads/Sheets/LeadLogActivitySheet.swift`, `Views/Leads/Sheets/LogCallSheet.swift` (and `LogCallViewModel.swift` once its logic is fully moved). **Keep** `CallCaptureCoordinator`, the AppIntent, `SiteVisitCaptureView`, and `QuickActionSheetHeader` (still used by `TaskManagementSheets`/`ProjectManagementSheets`).
**Step 1:** Confirm zero references to the deleted symbols (`grep`). **Step 2:** Build clean (watch for `JobBoardView`-style latent stale-call-site breaks). **Step 3:** Full regression pass on the 3 entry points. **Step 4:** Commit (`refactor(ios): delete three legacy activity loggers; unified sheet is the single source`).

---

## Phase 4 — Site-visit → timeline auto-post (app-side)

### Task 4.1: Post an activity on site-visit completion

**Files:** `ops-ios/OPS/Views/SiteVisits/SiteVisitCaptureViewModel.swift` (`completeVisit()` ~524-537).
**Why app-side:** `SiteVisit` is local-only SwiftData — never reaches Postgres — so a DB trigger can't fire. The proven insert path is `ActivityRepository.logActivity`.
**Step 1 (test):** completing a visit bound to an opportunity builds an activity DTO with `type=.siteVisit`, `siteVisitId=visit.id`, `opportunityId` from the bound target, `subject=nil` (trigger backfills "Site visit"), body = notes+checklist summary, `createdBy` set; an **unbound** visit (no opportunity AND no client) produces **no** post; re-completion does **not** double-post (idempotent by stored activity id).
**Step 2:** FAIL. **Step 3 (impl):** after the local `status=.completed`/`completedAt` write, best-effort call `ActivityRepository.logActivity(target:.opportunity(...)/.client(...), type:.siteVisit, subject:nil, body: summary, siteVisitId: visit.id, createdBy: currentUser?.id)`; store the returned activity id on the `SiteVisit` (new nullable local field) for idempotency/offline-retry; skip when unbound; **prefer `client_id`** (no FK) over a possibly-unsynced `opportunity_id` (FK 500s on unsynced leads).
**Step 4:** PASS + manual: complete a visit bound to a lead → activity appears on the lead timeline as "Site visit"; complete again → no duplicate. **Step 5:** Commit.

**Note:** `site_visits.activity_id` reciprocal back-link is moot server-side (rows never sync); the local stored id is the dedup key.

---

## Phase 5 — Verification & QA

### Task 5.1: Build + tests + snapshots
- `xcodebuild -scheme OPS -destination 'generic/platform=iOS' -clonedSourcePackagesDirPath .spm-local build` → clean.
- `xcodebuild test -scheme OPS -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' -clonedSourcePackagesDirPath .spm-local` → parser/DTO/target/repository unit tests pass.
- Snapshot harness PNGs for the unified sheet (3 entry points) + timeline metadata line — attach to the PR.

### Task 5.2: Manual QA matrix (attach evidence)
Entry points × types × targets × states:
- FAB (unbound) → pick LEAD / CLIENT / JOB → each type → **verify DB row has the right single parent + company_id + created_by + direction/outcome/duration** (`SELECT` the last row).
- Lead-detail LOG (locked) → voice "called John, callback Tuesday, left a voicemail" → type=CALL auto, outcome parsed, **follow-up SET** creates a `follow_ups` row (verify), duration/direction persist.
- Post-call / Siri → provenance (`call_source`/`caller_number`/`call_started_at`) present.
- First activity on a `new_lead` → stage auto-advances to `qualifying` + a `stage_transitions` row with `transitioned_by = created_by` (verify trigger still fires).
- Site visit complete (bound) → "Site visit" on the timeline; re-complete → no dupe.
- Offline: log queues/best-effort; error path shows `SheetStatusLine.error`; mic-denied + parse-error paths give feedback.
- Timeline shows outcome + duration.

### Task 5.3: Bible + notification rail
- Update `ops-software-bible/03_DATA_ARCHITECTURE.md` (activities parents/types incl. `sms`) and `02_USER_EXPERIENCE_AND_WORKFLOWS.md` (unified capture flow).
- No web notification needed (mobile-only capture), but confirm `LeadActivityLoggedSuccess` toast still fires.

---

## Phase 6 — Client & Job activity timelines (follow-on; largest piece)

> Jackson chose the **full customer timeline** — history visible on the client and the job, not just the lead. This needs surfaces that don't exist yet (`ClientSheet` is a form; there is no `ClientDetailView`; the project "Activity" tab is `project_notes`, a different subsystem). Checkpoint this separately after Phase 5 ships the capture.

### Task 6.1: Client activity timeline
- Add a client detail surface (or a timeline section within the existing client UI) hosting `ActivityTimeline` fed by `ActivityRepository.fetchActivities(byClient:)`. Reuse `ActivityTimeline` unchanged.
### Task 6.2: Job/project activity timeline
- Add an activities timeline to the project detail (distinct from the `project_notes` "Activity" tab — resolve the naming collision; likely rename one) fed by `fetchActivities(byProject:)`.
### Task 6.3: Continuity on won-conversion
- When a lead converts to a project ([[project_won_conversion_dedup_naming]]), ensure its activity history remains reachable on the resulting client/job (the parent columns already allow it; the display must surface it).

---

## Cross-cutting requirements
- **Additive-only schema** (only Task 0.0's CHECK widening + optional local `SiteVisit.activityId` field). No renames/drops/type changes. [iOS sync constraint]
- **`company_id` on every insert** — the single highest-risk field (NOT NULL, no default, RLS gate).
- **`created_by` = Supabase `users.id`** (`currentUser?.id`), never Firebase UID.
- **CRLF preservation** on `FloatingActionMenu.swift`, `OpportunityDTOs.swift`, and any mixed-ending file.
- **Design gates non-negotiable** on every UI task: `ops-design` + `mobile-ux-design`/`ui-ux-pro-max` + `ops-copywriter` + `audit-design-system` (+ `wizard-audit` for the flow). One accent per screen; selection = white shift; sharp corners; `//` only on section labels/system lines; numbers mono/tabular.
- **Never auto-persist a follow-up.** Detection suggests; the operator taps SET.
- **Don't fold `SiteVisitCaptureView`** into the logger.

## Rollout
Phase 0 is independently shippable (fixes the data-loss bug + author stamping with no UI change) — land it first for an immediate correctness win. Phases 1–5 ship the unified capture. Phase 6 (cross-entity timelines) is the follow-on that fully delivers the "customer timeline" vision.
