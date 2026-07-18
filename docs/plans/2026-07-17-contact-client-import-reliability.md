# Contact Client Import Reliability Implementation Plan

> **For Codex:** REQUIRED SUB-SKILL: Use `custom-skills:executing-plans` to implement this plan task-by-task.

**Goal:** Make selecting a phone contact always return and select the successfully saved OPS client while guaranteeing the matching pipeline lead is retried durably and without duplicates.

**Architecture:** Introduce a persisted `ClientLeadAutocreateQueue` that owns the secondary opportunity write. Contact and manual client creation enqueue a client snapshot after the local save and stop treating an opportunity failure as a client-save failure. The queue verifies server client visibility, reuses an existing linked or idempotency-keyed opportunity, and retries transient failures across launch/authentication/foreground/connectivity/timer boundaries while revalidating account scope after every await. Automatic inserts use the live unique `(company_id, source_thread_key)` constraint, so concurrent and ambiguous retries cannot duplicate the lead.

**Tech Stack:** Swift 6, SwiftUI, SwiftData, Supabase Swift, XCTest, UserDefaults.

**Design System:** N/A — no visual or copy changes.

**Required Skills:** `superpowers:systematic-debugging`, `superpowers:test-driven-development`, `supabase:supabase`, `superpowers:verification-before-completion`.

---

### Task 1: Lock the regression with failing tests

**Skills:** `superpowers:test-driven-development`

**Files:**
- Create: `OPSTests/ClientLeadAutocreateQueueTests.swift`
- Create: `OPSTests/PhoneContactImporterTests.swift`
- Modify: `OPSTests/ClientLeadAutocreateTests.swift`

**Design tokens:** N/A

**Step 1:** Add tests proving: failed delivery remains queued; duplicate enqueue for one client stays one item; a new queue instance reloads persisted work; recovered delivery clears work and refreshes leads; a company transition preserves in-flight work; the automatic DTO carries its deterministic source key; the full `PhoneContactImporter.createClient` path returns the exact context-managed save with a nil opportunity while handing the client to the queue.

**Step 2:** Run:

```bash
xcodebuild test -project OPS.xcodeproj -scheme OPS -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' -derivedDataPath /tmp/ops-contact-client-red -only-testing:OPSTests/ClientLeadAutocreateQueueTests -only-testing:OPSTests/PhoneContactImporterTests
```

Expected: FAIL because the queue and import-completion seam do not exist yet.

### Task 2: Implement durable, idempotent lead delivery

**Skills:** `superpowers:test-driven-development`, `supabase:supabase`

**Files:**
- Create: `OPS/Services/ClientLeadAutocreateQueue.swift`
- Modify: `OPS/Services/ClientLeadAutocreate.swift`
- Modify: `OPS/Network/Supabase/Repositories/OpportunityRepository.swift`
- Modify: `OPS/Network/Supabase/DTOs/OpportunityDTOs.swift`
- Modify: `OPS/OPSApp.swift`

**Design tokens:** N/A

**Step 1:** Add the Codable pending snapshot and queue. Persist before delivery, deduplicate by lowercase client ID, serialize/coalesce drains, retain failed items, retry on launch/authentication/foreground/connectivity/60-second timer, revalidate active-company scope after every await, and mirror successful opportunity DTOs into SwiftData.

**Step 2:** Add `OpportunityRepository.fetchFirstActiveLinked(toClientId:)` plus exact `source_thread_key` readback for ambiguous insert recovery.

**Step 3:** Add a `ClientLeadAutocreate.makeOpportunityDTO(for pending:)` overload and deterministic `client-autocreate:<client-id>` source key so retries do not depend on a live SwiftData object and the existing database uniqueness contract guarantees one automatic lead.

**Step 4:** Configure and drain the queue beside `LeadImageService` during app launch.

### Task 3: Move both client-create surfaces onto the queue

**Skills:** `superpowers:test-driven-development`

**Files:**
- Modify: `OPS/Views/Components/Contact/PhoneContactImporter.swift`
- Modify: `OPS/Views/JobBoard/ClientSheet.swift`
- Modify: `OPS/Utilities/DataController.swift`

**Design tokens:** N/A

**Step 1:** Add `DataController.createClientModel`, then have `PhoneContactImporter` enqueue and return that exact context-managed save, post the existing client success event with `leadCreated: false`, and return immediately. Only missing name/local client persistence may throw.

**Step 2:** In `ClientSheet`, replace the blocking direct opportunity insert with the same queue and return the existing queued result (`leadCreated: false`, `opportunityId: nil`).

**Step 3:** Re-run the two focused test classes. Expected: PASS.

### Task 4: Update the system contract

**Skills:** `supabase:supabase`

**Files:**
- Modify: `../ops-software-bible/03_DATA_ARCHITECTURE.md`
- Modify: `../ops-software-bible/10_JOB_LIFECYCLE_AND_DATA_RELATIONSHIPS.md`

**Design tokens:** N/A

**Step 1:** Document client selection as authoritative, the durable retry/idempotency behavior, the current live `source = 'other'` constraint, and the no-migration result.

### Task 5: Verify and commit

**Skills:** `superpowers:verification-before-completion`

**Files:** All files above; do not stage the pre-existing `.DS_Store`, `.dd-local/`, `.spm-local/`, or `OPS.xcodeproj/project.pbxproj` changes.

**Step 1:** Run focused tests on the required iPhone 17 / iOS 26.5 simulator.

**Step 2:** Run a generic device build:

```bash
xcodebuild build -project OPS.xcodeproj -scheme OPS -destination 'generic/platform=iOS' -derivedDataPath /tmp/ops-contact-client-build
```

Expected: `** BUILD SUCCEEDED **`.

**Step 3:** Review path-scoped diffs, re-read the live `clients` / `opportunities` constraints and RLS policies, and confirm no production migration is required.

**Step 4:** Stage only the repair, tests, and documentation. Commit as `fix(project-form): keep contact client save independent of lead retry`. Do not push.
