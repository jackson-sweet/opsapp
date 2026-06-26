## Task 7 Report - 2026-06-26

Status: IMPLEMENTED AND VERIFIED

Commit range:
- Base: `4252196d`
- Final range after commit: `4252196d..HEAD`

Files changed:
- Backend/client contract:
  - `docs/superpowers/specs/2026-06-25-ops-decks-phase-1-backend-contract.md`
  - `OPSDecks/DecksCompanyProvisioningService.swift`
- Standalone tests:
  - `OPSDecksTests/DecksProvisioningPayloadTests.swift`
  - `OPS.xcodeproj/project.pbxproj`
  - `OPS.xcodeproj/xcshareddata/xcschemes/OPSDecks.xcscheme`
- Report:
  - `.superpowers/sdd/task-7-report.md`

Related bible updates:
- `/Users/jacksonsweet/Projects/OPS/ops-software-bible/03_DATA_ARCHITECTURE.md`
- `/Users/jacksonsweet/Projects/OPS/ops-software-bible/12_SUBSCRIPTION_MANAGEMENT.md`

Implemented:
- Added the Phase 1 backend contract for deck-only company provisioning, `deck_subscriptions`, and account deletion.
- Added `DecksCompanyProvisioningRequest` and `DecksCompanyProvisioningResponse` DTOs for the standalone target.
- Corrected the plan's stale `OPSTests/OPSDecks` test location by adding a dedicated `OPSDecksTests` target hosted by `OPSDecks`.
- Added focused payload tests proving the request encodes `source_app = "ops_decks"` and does not carry OPS base subscription fields.
- Added response decoding coverage for the company-of-one identity payload.
- Wired `OPSDecksTests` into the shared `OPSDecks` scheme.
- Updated the OPS Software Bible to document standalone `deck_designs` behavior and the RevenueCat-backed deck subscription mirror without changing Stripe-owned OPS subscription fields.

Verification commands run:
- `scripts/verify-ops-decks-style-tokens.sh .`
  - PASS.
- `plutil -lint OPS.xcodeproj/project.pbxproj`
  - PASS: `OPS.xcodeproj/project.pbxproj: OK`.
- `git diff --check`
  - PASS.
- `xcodebuild build-for-testing -project OPS.xcodeproj -scheme OPSDecks -destination 'generic/platform=iOS Simulator' -derivedDataPath /private/tmp/ops-decks-derived CODE_SIGNING_ALLOWED=NO`
  - PASS: `** TEST BUILD SUCCEEDED **`.
- `xcodebuild test -project OPS.xcodeproj -scheme OPSDecks -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:OPSDecksTests/DecksProvisioningPayloadTests -derivedDataPath /private/tmp/ops-decks-derived CODE_SIGNING_ALLOWED=NO`
  - BLOCKED by unavailable simulator destination.
  - Exact blocker:
    - `Unable to find a device matching the provided destination specifier: { platform:iOS Simulator, OS:latest, name:iPhone 16 }`
- `xcodebuild test -project OPS.xcodeproj -scheme OPSDecks -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' -only-testing:OPSDecksTests/DecksProvisioningPayloadTests -derivedDataPath /private/tmp/ops-decks-derived CODE_SIGNING_ALLOWED=NO`
  - Built successfully, then first simulator launch was blocked by transient simulator busy/preflight state.
  - Exact blocker:
    - `Simulator device failed to launch co.opsapp.ops.decks.`
    - `The request was denied by service delegate (SBMainWorkspace) for reason: Busy ("Application failed preflight checks").`
- `xcodebuild test-without-building -project OPS.xcodeproj -scheme OPSDecks -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' -only-testing:OPSDecksTests/DecksProvisioningPayloadTests -derivedDataPath /private/tmp/ops-decks-derived CODE_SIGNING_ALLOWED=NO`
  - PASS: `** TEST EXECUTE SUCCEEDED **`.
  - `DecksProvisioningPayloadTests.testProvisioningPayloadUsesDeckOnlySourceAndDoesNotContainOPSSubscriptionState()` passed.
  - `DecksProvisioningPayloadTests.testProvisioningResponseDecodesDeckOnlyCompanyIdentity()` passed.

Self-review notes:
- The Task 7 DTO is data-only and introduces no UI styling surface.
- The test target intentionally depends on `OPSDecks`, not `OPS`, so standalone provisioning tests do not bootstrap the full OPS app host.
- The backend contract keeps deck entitlement out of `companies.subscription_status`, `trial_end_date`, and other OPS base-plan subscription fields.
- The bible repository already had unrelated dirty edits before this task; only the deck standalone/provisioning subscription notes are Task 7 work.
