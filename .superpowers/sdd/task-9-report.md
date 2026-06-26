## Task 9 Report - 2026-06-26

Status: IMPLEMENTED AND VERIFIED

Commit range:
- Base: `e93655c4`
- Final range after commit: `e93655c4..HEAD`

Files changed:
- Account lifecycle contract:
  - `OPSDecks/DecksAccountDeletionService.swift`
- Upgrade surface:
  - `OPSDecks/DecksUpgradeSurface.swift`
  - `OPSDecks/OPSDecksCopy.swift`
  - `OPSDecks/OPSDecksRootView.swift`
- Standalone tests:
  - `OPSDecksTests/DecksAccountDeletionPayloadTests.swift`
- Report:
  - `.superpowers/sdd/task-9-report.md`

Implemented:
- Added `DecksAccountDeletionRequest` with `firebase_uid` and `company_id` only.
- Added `DecksAccountDeletionReceipt` for deletion receipt id and timestamp decoding.
- Added account deletion payload tests proving the request carries only Firebase/company identity and no OPS subscription state.
- Added deletion receipt decoding coverage with an ISO-8601 timestamp.
- Added `OPSDecksUpgradeCopy` constants for the minimal upgrade surface.
- Added `DecksUpgradeSurface` using `OPSDesignKit` / `OPSStyle` tokens only.
- Refactored `OPSDecksRootView` into sibling shell and upgrade surfaces so the upgrade panel is not nested inside another card.
- Corrected the plan's stale `OPSTests/OPSDecks` test location by placing account deletion tests in `OPSDecksTests`, hosted by the standalone app target.

Verification commands run:
- `scripts/verify-ops-decks-style-tokens.sh .`
  - PASS.
- `git diff --check`
  - PASS.
- `xcodebuild test -project OPS.xcodeproj -scheme OPSDecks -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' -only-testing:OPSDecksTests/DecksAccountDeletionPayloadTests -derivedDataPath /private/tmp/ops-decks-derived CODE_SIGNING_ALLOWED=NO`
  - PASS: `** TEST SUCCEEDED **`.
  - `DecksAccountDeletionPayloadTests`: 2 tests passed.
- `xcodebuild test-without-building -project OPS.xcodeproj -scheme OPSDecks -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' -derivedDataPath /private/tmp/ops-decks-derived CODE_SIGNING_ALLOWED=NO`
  - First full-bundle attempt blocked by transient simulator busy/preflight state:
    - `Simulator device failed to launch co.opsapp.ops.decks.`
    - `The request was denied by service delegate (SBMainWorkspace) for reason: Busy ("Application failed preflight checks").`
  - Retry PASS: `** TEST EXECUTE SUCCEEDED **`.
  - `DecksAccountDeletionPayloadTests`: 2 tests passed.
  - `DecksProvisioningPayloadTests`: 2 tests passed.
  - `DecksEntitlementGateTests`: 4 tests passed.

Self-review notes:
- Account deletion payloads intentionally exclude subscription/trial fields so deleting a deck-only account cannot mutate OPS base-plan state.
- The upgrade surface is passive in Phase 1; it does not claim a live upgrade flow exists yet.
- All upgrade text is centralized in `OPSDecksCopy.swift`.
- The root view keeps glass panels as siblings, not nested cards.
- New UI styling uses only `OPSStyle` tokens for color, typography, spacing, radius, and borders.
