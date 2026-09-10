# Lightweight verification — P1-1

Run September 6, 2026 in the assigned worktree. No build baton held; these are source checks, not runtime migration or UI proof.

- PASS: xcrun swiftc -frontend -parse on all ten changed/new Swift files (exit 0). No type-check, build, package resolution, or test execution.
- PASS: git diff --check (exit 0).
- PASS: all 25 existing released checksum fixture values are byte-for-byte unchanged; only distinct V26 was appended. V26 expected value comes from the audited widened-debug graph and still requires a runtime assertion.
- PASS: every frozen V16–V25 stored-property declaration exactly matches the pre-8126e38a DeckDesign source (including types, defaults, and unique id attribute). Runtime fingerprints still require XCTest.
- PASS: V26 model registration differs from V25 only in the deck model group.
- PASS: original QA root selection and entire ContentView lifecycle/method tail are byte-for-byte retained; DataController construction now exists only in the storage-ready child.
- PASS: changed existing Swift files preserve their original LF boundaries; no CRLF normalization.
- PASS: new recovery layout and loading view use existing OPSStyle typography, colors, spacing and primary button tokens. No new literal color, spacing, radius, or font sizes. UI screenshots, VoiceOver/dynamic type, and 17.6 runtime proof are unrun.
- PASS: local SDK declares ModelContainer Sendable and ModelConfiguration Sendable on iOS 17; bootstrap transfers configuration/container only, never ModelContext or model instances.

Unrun: 9 new XCTest cases, all existing regression selectors, actual fingerprint creation, synthetic store migration/reopen, recovery screen rendering, device-target build. PM will run these serially.
