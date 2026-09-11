# Phase 19 phone verification

## Parent integration — 2026-09-11

The complete phase is now integrated with main `b08de104` in `187a36d6` and locally fast-forwarded after one combined app-hosted regression: **138 passed, 2 optional private-store-copy skips, 0 failures**. All historical checksums, populated V27→V28 independent reopen, field recovery, calendar compatibility and settings inputs passed. This supersedes the earlier split-run limitation for the selected suites below, not the signed-device or release limits. Exact source, tests, raw result paths and independent Xcode summary are in [the parent integration report](parent-integration-20260911.md).

## Original phase evidence

Implementation is local and committed through `b15bf20f302fd0c9690e91714114c979ad91d4b4`, from baseline `8553b1b4`. No signed distribution, production migration, company activation, real-provider write, push or release was performed. Independent final integration review is retained in the sibling web phase artifacts.

## Field workflow and custody

The app preserves original bases, exact attempted payloads, originating actors, receipts, explicit conflict decisions and recovery history across fresh contexts and account changes. Parent/media/upload metadata/linked-answer/completion ordering is enforced. Atomic packet discard retains original operations and settles only its exact receipt. Cleared/unknown remote state survives inbound merge, accept-current recovery and the vault. Blank text/measurement clears produce an empty wire value without changing prior audit bytes; false, zero and entered units remain intact.

Initial hosted batch4 passed63/63. Independent review corrections for discard/media/markup passed67/67 in batch5. Batch7 compiled the app and test target and passed68/69; the one failed accept-current fixture used a bare command instead of the actual operation envelope. Corrected batch9 passed5/5. Batch10 then passed6/6 affected field tests after the production blank-clear correction. These are identified runs, not one uninterrupted69-test success.

The Foundation/SwiftData harness also passed10 tests, including independent persisted-store reopen, but its scope is smaller than the hosted application suites. [Harness output](command-tests.log), [reproduction script](run-command-tests.sh).

## Released-store compatibility

SwiftData V28 is reserved for P19 by the parent and active iOS bug coordinator. Commit `b15bf20f` freezes the exact baseline stored shapes of `SyncOperation`, `SiteVisitType` and `SiteVisitChecklistAnswer` for V1–V27. Only V28 registers the new live metadata; the migration plan adds the adjacent V27→V28 stage and updates the existing current alias.

- All27 released checksum fixture entries are byte-identical to baseline. Runtime measurement matched every one; no historic hash was updated to accept model drift.
- The appended V28 fingerprint is `nKgJeuKrTdQESe0YctzHunky4wMIqOpHYSoPkjdozIk=`.
- The populated V27→V28 test compares every original scalar of saved templates, answers and queued operations through migration and a separate container reopen, using the existing HMAC custody snapshot mechanism. All seven newly introduced nullable metadata fields remain nil on migrated rows. No actor or edit base is invented.
- Batch11 ran31 selected cases. Two optional tests requiring a private device-store copy were skipped. The sole failure was the deliberately absent newV28 fixture entry; all old checksums, populated migration, four site-visit migration cases and six field workflows passed.
- After appending only the measuredV28 entry, batch12 passed7/7: released/current checksum coverage, five Deck migration/custody cases and the all-version adjacency assertion. Historical test stores use frozen historical model types. [Batch11](phone-app-tests-11-summary.log), [batch12](phone-app-tests-12-summary.log).

## Visual and runtime limits

The actual conflict review uses OPSStyle tokens and existing button styles. Populated390-point and320-point accessibility snapshots were visually inspected, including wrapped titles, pending/current definitions and actions. The harness verifies nonblank raster content. An earlier oversized blank raster was rejected and replaced; it was not accepted as visual proof. [390-point image](phone-conflict-review-390.png), [320-point image](phone-conflict-review-320-accessibility.png).

All hosted builds used private DerivedData and package caches under `/private/tmp/ops-site-visits-p19`, simulator `FA315A2B-AD37-45C2-937A-816BD34CDCDD`, two build jobs, serial tests and no signing. A test-only Mapbox placeholder enabled hosted startup; no real credential or paid fallback was used. Early compiler/host-startup failures and corrected reruns remain in the numbered summaries. The mistyped-destination batch8 executed no tests and only its own waiting process was stopped. The build baton was released after observed batch12 exit0 to the waiting iOS Bugs coordinator.

Raw results are `/private/tmp/ops-site-visits-p19/phone-tests-N.xcresult`; raw logs are `phone-app-tests-N.log` in the same directory. Concise summaries are committed here. [Hosted reproduction](run-phone-app-tests.sh) requires fresh serial build coordination; the script is not permission to compete with another build.

The companion web PostgreSQL protocol fixture passed69 checks with real simultaneous sessions, captured live schema/helper definitions and synthetic local records. It proves local actor/concurrency/receipt/media/discard/clear behavior. Root's separate combined fixture exercises canonical booking and completion bodies. Neither fixture claims live customer writes. Simulator tests do not establish signed-device network behavior, physical scrolling, VoiceOver, native-host acceptance or App Store release.
