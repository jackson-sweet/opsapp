# iOS bug batch P6 — verified local implementation

Source: iOS `5d0e6da1`; server `2a7f6ff3d`. No production migration, push, phone installation or App Store release occurred in this phase. Live bug rows remain unresolved pending release and acceptance.

## Results

- **159 iOS tests passed; zero failures or skips.** Final combined run exercised 15 focused scheduling, durable outbox, lifecycle, dependency, expiry, automatic reporting and receipt suites. Machine-readable result: [test-summary.json](test-summary.json). Tested source hashes: [source-sha256.txt](source-sha256.txt).
- **30 PostgreSQL assertions passed**, including real anon/authenticated execution and duplicate concurrent reopen requests. Disposable database only.
- Archived scheduling regression first failed against the original source: project remained archived and no reopen command was queued. The final run passes the regression alongside no-op, authority, stale snapshot, rollback, ordering and cleanup cases.

## Behavior

Scheduling changed active work on an archived project reopens it as Accepted (future start) or In progress (start now or earlier), provided project edit authority and an exact archive revision are available. The immutable project command and dependent task write share one local transaction. Replays return historical execution proof without overwriting a newer project status. Forms and batch scheduling use the same durable path.

Permanent sync failures are reported automatically after successful reconciliation opportunities have been exhausted. Reports use scoped identities and allowlisted fingerprints, excluding customer payloads and raw server messages. Transient failures are excluded. The in-memory delivery buffer does not promise restart-durable reporting, and existing manual reports without a dedupe key are not semantically matched.

Reports: archived scheduling `facfecfe-6e28-4a1e-b332-2aa406cc00c6`; automatic sync reports `39654ecf-9adb-4a1c-b926-0077aa4eca14`.

## Retained evidence

- Final result: `/private/tmp/ops-ios-bugs-p6/combined-green-3.xcresult`
- Final log: `/private/tmp/ops-ios-bugs-p6-green-3.log`
- Initial regression: `/private/tmp/ops-ios-bugs-p6/archived-scheduling-red.xcresult`
- SQL output: `/private/tmp/ops-project-reopen-proof.utglAj/sql.log`
- Test command: `/private/tmp/ops-ios-bugs-p6/run-focused.sh`

Final configuration: iPhone 17 simulator, iOS 26.5 (23F77), iPhoneSimulator 27.0 SDK, serial execution with two build jobs. The retained run script points to an existing result bundle; select a new result path before rerunning.

Pending server migration: `20260914210950_project_task_reopen_receipts.sql`. Final live schema read found neither the RPC nor receipt table installed. Applying this migration and distributing iOS require separate authorization. Original-phone offline/reconnect acceptance remains unproven.
