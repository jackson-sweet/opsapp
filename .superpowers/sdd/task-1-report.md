DONE

Commits made:
- `f7ddbc38` `chore: add OPS Decks style token scanner`

Files changed:
- `scripts/verify-ops-decks-style-tokens.sh`
- `docs/superpowers/plans/2026-06-25-ops-decks-phase-1-standalone-foundation.md`

Commands run:
- `git status --short`
- `chmod +x scripts/verify-ops-decks-style-tokens.sh && scripts/verify-ops-decks-style-tokens.sh .`
- `xcodebuild -project OPS.xcodeproj -scheme OPS -destination 'generic/platform=iOS Simulator' -derivedDataPath /private/tmp/ops-ios-derived CODE_SIGNING_ALLOWED=NO build`
- `xcodebuild -project OPS.xcodeproj -scheme OPS -destination 'generic/platform=iOS Simulator' -derivedDataPath /private/tmp/ops-ios-derived CODE_SIGNING_ALLOWED=NO build` with escalated privileges

Command results:
- `git status --short` showed only the copied plan as an untracked file before edits.
- The style-token scanner exited `0` with no output.
- The first `xcodebuild` attempt failed in the sandbox with package resolution/network and simulator-service blockers, including:
  - `Could not resolve host: github.com`
  - `CoreSimulatorService connection became invalid. Simulator services will no longer be available.`
  - `Error opening log file (/Users/jacksonsweet/Library/Logs/CoreSimulator/CoreSimulator.com.apple.dt.xcodebuild.log): Operation not permitted`
- The escalated `xcodebuild` run completed successfully and ended with `** BUILD SUCCEEDED **`.

Self-review notes:
- The scanner is limited to `OPSDecks`, `Packages/DeckKit/Sources`, and `Packages/OPSDesignKit/Sources`, which matches the task brief and avoids gating the existing `OPS/` app surface.
- The scanner blocks literal colors, fonts, spacing, radii, shadows, icon styles, and animation constants using the exact pattern from the brief.
- I preserved the copied plan file unchanged and committed it with the scanner, per the branch artifact requirement.
