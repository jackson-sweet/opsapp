# OPS iOS Analytics Contract

OPS separates business truth, product behaviour, and Google conversion signals. No single analytics destination is allowed to claim all three.

**Release state — August 30, 2026:** this contract is implemented and verified on the local analytics-hardening branch. It is not customer-live until the iOS build is released through the App Store and live event readback succeeds. The production Firebase key-event configuration is a separate Google-admin state.

## Source ownership

| Signal | Destination | Purpose |
|---|---|---|
| Companies, trials, projects, task progress, billing | Supabase business records | Canonical business milestones |
| Detailed product behaviour and friction | Supabase `analytics_events` | First-party product analysis |
| Five deliberate conversion events | Firebase Analytics | Google conversion QA and optimization |
| App Store impressions, page views, and downloads | App Store Connect | Storefront discovery, not user-level attribution |

Client events never define whether a company activated or paid. Those milestones are derived from persisted business records.

## Firebase conversion allowlist

The release-candidate `AnalyticsManager` may emit only:

1. `sign_up`
2. `begin_trial`
3. `complete_onboarding`
4. `create_first_project`
5. `purchase`

Screen views, app opens, logins, navigation, CRUD actions, sync failures, and other product behaviour must not be added to Firebase. They belong in `AnalyticsService` and Supabase.

Firebase user properties are limited to conversion segmentation: `user_type`, `subscription_status`, and the configured Firebase user ID. The exact event allowlist is locked by `FirebaseConversionContractTests`.

## Supabase event contract

The release-candidate `AnalyticsService` creates a stable UUID for every product event and queues it durably in `UserDefaults`. The queue preserves order, caps itself at 1,000 events, retries transient failures, and drops permanent poison events so one bad payload cannot block the stream.

Each event carries:

- contract schema version `1`
- explicit `production` or `development` environment
- stable event and session UUIDs
- event type and snake-case name
- bounded app/device context
- allowlisted, scalar, PII-screened properties
- optional bounded duration
- client creation time

The authenticated `append_analytics_events` RPC is the only current delivery path. It verifies the signed Firebase subject, resolves canonical user/company/role/plan on the server, stamps `platform=ios`, rate-limits the user, and inserts by event UUID with idempotent retry semantics. Client-supplied identity is never accepted.

Pre-signup product events remain local until authentication, then bind once to the first authenticated subject without changing their event IDs. Authenticated events are bound to the subject that created them. Legacy ownerless events and events from a different signed-in account are discarded rather than misattributed.

## Privacy boundary

Event properties are allowlisted. Strings are trimmed and capped at 256 UTF-8 bytes; each event accepts at most 25 properties. Nested values and arrays are rejected. The sanitizer rejects emails, URLs, UUIDs, phone-like strings, resource IDs, arbitrary query strings, and noncanonical paths.

Do not collect:

- names, email addresses, phone numbers, or street addresses
- notes or other free-form customer content
- auth tokens or secrets
- full URLs or query strings
- project, task, client, company, or user identifiers in properties

Counts, booleans, stable enum values, status transitions, and coarse UI context are appropriate. Hashing does not make PII appropriate for product analytics.

## Logging

Analytics diagnostics compile only in debug builds and contain event categories or counts, never user IDs or raw payloads. Release builds do not print analytics identifiers or property bodies.

## Business milestones and source health

iOS conversion/product events cannot define trial, activation, first value, paid, or revenue membership. Those metrics are derived on the server from company, project, task, and billing records under the shared growth measurement contract.

The app notification rail recognizes the staged persistent type `analytics_source_failed`. It uses the design-system alert icon and error status colour. Creation, deduplication, and automatic resolution are server-owned; the iOS client only renders the notification returned by the existing notification API.

The registered iOS Firebase/GA property is `514229717`. It is conversion QA only. Search Console, the two web GA properties, and App Store Connect facts are owned and health-checked by OPS-Web.

## Adding telemetry

Before adding a product event:

1. Confirm the behaviour cannot be derived more reliably from a business record.
2. Use a stable snake-case event name.
3. Add only bounded, reusable enum/count/boolean properties.
4. Add any new property key to `AnalyticsEventContract` with sanitizer coverage.
5. Call `AnalyticsService`, not Firebase.
6. Add or update contract tests, including offline/retry behaviour when delivery changes.

Changing the Firebase conversion set is a separate measurement decision. Update the allowlist test and reconcile the event to a canonical Supabase business record before changing it.

## Files

| File | Responsibility |
|---|---|
| `OPS/Utilities/AnalyticsManager.swift` | Firebase conversion allowlist only |
| `OPS/Utilities/Analytics/AnalyticsService.swift` | First-party product event creation and authenticated flush |
| `OPS/Utilities/Analytics/AnalyticsEventQueue.swift` | Contract, sanitizer, durable queue, and RPC encoding |
| `OPS/Utilities/Analytics/AnalyticsFlushPolicy.swift` | Poison/transient delivery disposition |
| `OPSTests/Analytics/` | Contract and Firebase allowlist tests |
| `OPSTests/Sync/AnalyticsFlushPolicyTests.swift` | Offline, retry, duplicate, and poison-batch policy |
