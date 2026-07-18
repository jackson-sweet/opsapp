# Contact Client Import Reliability Design

**Problem:** Selecting a device contact in `ProjectFormSheet` saves a local `Client`, then waits for an unrelated pipeline-opportunity request. If that second request fails, the form reports `SAVE FAILED` and never selects the client even though the client already exists. Production readback on 2026-07-17 showed the same split state: a newly created client with no linked opportunity.

**Decision:** Client creation and selection are the authoritative transaction. Pipeline lead creation becomes a durable, idempotent follow-on operation. The app persists one pending lead request per client before attempting the network write, returns the exact context-managed saved client immediately, and retries the lead on launch, authentication, foreground, connectivity recovery, and a bounded timer. Every automatic insert carries `source_thread_key = client-autocreate:<client-id>`; the live unique `(company_id, source_thread_key)` constraint makes overlapping or ambiguous retries database-safe. The queue also checks for an existing active opportunity linked to the client for compatibility with leads created before this key existed.

**Data flow:**

1. `PhoneContactImporter` creates the local client through `DataController.createClientModel`.
2. `DataController.createClientModel` returns the exact SwiftData model it inserted; the importer enqueues a serializable snapshot in `ClientLeadAutocreateQueue` and immediately returns that model to the project form without a second fetch.
3. The project form selects the client and can save the project normally. Its existing success banner truthfully reports `PIPELINE LINK QUEUED` until the follow-on write completes.
4. The queue confirms the client is readable from Supabase, reuses an existing linked or keyed opportunity when present, or creates the standard `ClientLeadAutocreate` opportunity with its deterministic source key.
5. Every confirmed delivery is mirrored into SwiftData, removed from the durable queue, and publishes `opsLeadsDidChange`; a genuinely new insert also publishes the existing `LeadCreatedSuccess` signal.
6. Network, ordering, or transient server failures leave the item queued. No client-selection error is shown for this secondary failure.

**Scope:** The same queue replaces the blocking lead write in manual `ClientSheet` creation, because it has the identical false-failure boundary and already claims a queued fallback in its success banner. No visual layout, copy, database schema, or RLS change is required.

**Failure handling:** Missing contact name and inability to create the local client remain blocking errors. Avatar upload remains best-effort. A lead retry is skipped only after an existing linked/keyed opportunity is found or a new one is confirmed. Queue entries are deduplicated by lowercase client ID and persisted in `UserDefaults` across relaunches. Every delivery captures the active-company scope generation and revalidates it after network awaits; logout, login, or company change leaves any in-flight receipt queued instead of injecting an old-company result into the new session.

**Verification:** Unit tests prove that a failed lead delivery remains queued, duplicate enqueues collapse, persisted work reloads, recovered delivery refreshes the pipeline, company changes preserve the receipt, the deterministic source key is present, and the full contact-import path returns the exact managed save before the lead exists. Focused simulator tests plus a generic-device build prove integration. A final live read verifies the production constraints and confirms no migration was needed.
