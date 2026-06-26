STATUS: DONE_WITH_CONCERNS

COMMITS MADE:
- `61ef112e` — `feat: preserve future deck drawing blocks`

FILES CHANGED:
- `OPS/DeckBuilder/Models/DeckGeometry.swift`
- `OPS/DeckBuilder/Models/DeckDrawingFutureBlocks.swift`
- `OPSTests/DeckBuilder/DeckDrawingFutureBlocksTests.swift`

COMMANDS RUN:
1. `sed -n '1,260p' .superpowers/sdd/task-2-brief.md`
   - Result: reviewed task brief and exact required interfaces/commands.
2. `sed -n '1,260p' OPS/DeckBuilder/Models/DeckGeometry.swift`
   - Result: inspected existing `DeckDrawingData` serialization.
3. `sed -n '1,240p' OPSTests/DeckBuilder/DeckBuilderRegressionTests.swift`
   - Result: inspected adjacent regression coverage.
4. `xcodebuild test -project OPS.xcodeproj -scheme OPS -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:OPSTests/DeckDrawingFutureBlocksTests -derivedDataPath /private/tmp/ops-ios-tests CODE_SIGNING_ALLOWED=NO`
   - Result: failed before test execution in sandbox. CoreSimulator access denied and SwiftPM resolution failed with repeated `Could not resolve host: github.com`.
5. `git diff --binary -- OPS/DeckBuilder/Models/DeckGeometry.swift OPS/DeckBuilder/Models/DeckDrawingFutureBlocks.swift OPSTests/DeckBuilder/DeckDrawingFutureBlocksTests.swift > /private/tmp/ops-decks-task2.patch`
   - Result: saved scoped patch to support a clean red/green pass.
6. `git apply -R /private/tmp/ops-decks-task2.patch`
   - Result: temporarily restored pre-implementation state for TDD red verification.
7. `xcodebuild test -project OPS.xcodeproj -scheme OPS -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' -only-testing:OPSTests/DeckDrawingFutureBlocksTests -derivedDataPath /private/tmp/ops-ios-tests -clonedSourcePackagesDirPath /Users/jacksonsweet/Projects/OPS/ops-ios/.dd-ptr-fix/SourcePackages -disableAutomaticPackageResolution CODE_SIGNING_ALLOWED=NO`
   - Result: built against cached packages and reached XCTest, but the host app crashed before the test bundle connected: `OPS (43673) encountered an error (Early unexpected exit, operation never finished bootstrapping - no restart will be attempted. (Underlying Error: Test crashed with signal trap before establishing connection.))`
8. `git apply /private/tmp/ops-decks-task2.patch`
   - Result: restored Task 2 implementation.
9. `scripts/verify-ops-decks-style-tokens.sh .`
   - Result: passed with no output.
10. `xcodebuild test-without-building -project OPS.xcodeproj -scheme OPS -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' -only-testing:OPSTests/DeckDrawingFutureBlocksTests -only-testing:OPSTests/DeckBuilderRegressionTests -derivedDataPath /private/tmp/ops-ios-tests CODE_SIGNING_ALLOWED=NO`
   - Result: safer sandbox fallback failed before running tests. CoreSimulator was unavailable in sandbox, then package resolution retried and failed with repeated `Could not resolve host: github.com`.
11. `git diff --check -- OPS/DeckBuilder/Models/DeckGeometry.swift OPS/DeckBuilder/Models/DeckDrawingFutureBlocks.swift OPSTests/DeckBuilder/DeckDrawingFutureBlocksTests.swift`
   - Result: passed.

TDD RED/GREEN EVIDENCE:
- RED:
  - Test file was added first: `OPSTests/DeckBuilder/DeckDrawingFutureBlocksTests.swift`.
  - A clean pre-implementation verification run was attempted after temporarily reversing the scoped patch.
  - The run reached XCTest after a full build with cached packages, but the `OPS` test host crashed during bootstrap before the new test could report its expected assertion failure.
- GREEN:
  - Implementation was restored and self-reviewed.
  - Scanner passed.
  - A post-implementation focused test rerun could not be completed because the available unsandboxed rerun path hit an approval/usage limit, and the sandbox fallback cannot access CoreSimulator or remote package resolution.

COMMAND RESULTS SUMMARY:
- Style-token scanner: PASS
- Diff hygiene (`git diff --check`): PASS
- Focused xcodebuild red run: BLOCKED BY shared `OPS` host bootstrap crash after full build
- Focused xcodebuild green run: BLOCKED BY sandbox/CoreSimulator limits plus unsandboxed approval limit

SELF-REVIEW NOTES:
- Scope stayed inside the brief: one adjacent model file, `DeckGeometry.swift`, and the required test file.
- `DeckDrawingData` changes are additive only: legacy payloads still decode because all existing keys keep their old defaults and unknown keys are stored separately.
- Unknown top-level blocks decode opaquely through `DeckJSONValue` and re-encode in sorted key order without introducing any framing/zoning/rendering behavior.
- No UI, styling, DeckKit packaging, or unrelated branch files were touched.
- Remaining concern is verification, not implementation shape: the shared `OPS` test host currently crashes before the focused unit test bundle can complete.

---

STATUS: DONE_WITH_CONCERNS

COMMITS MADE:
- `25f342f5` — `fix: preserve exact future deck drawing numbers`

FILES CHANGED:
- `OPS/DeckBuilder/Models/DeckDrawingFutureBlocks.swift`
- `OPS/DeckBuilder/Models/DeckGeometry.swift`
- `OPSTests/DeckBuilder/DeckDrawingFutureBlocksTests.swift`
- `.superpowers/sdd/task-2-report.md`

COMMANDS RUN:
1. `scripts/verify-ops-decks-style-tokens.sh .`
   - Result: passed with no output after the review-fix patch.
2. `xcodebuild build-for-testing -project OPS.xcodeproj -scheme OPS -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' -only-testing:OPSTests/DeckDrawingFutureBlocksTests -only-testing:OPSTests/DeckBuilderRegressionTests -derivedDataPath /private/tmp/ops-decks-p1-2-tests -clonedSourcePackagesDirPath /Users/jacksonsweet/Projects/OPS/ops-ios/.dd-ptr-fix/SourcePackages -disableAutomaticPackageResolution CODE_SIGNING_ALLOWED=NO`
   - Result: first rerun failed in `DeckDrawingFutureBlocks.swift` with `error: value of type 'UnicodeScalar' (aka 'Unicode.Scalar') has no member 'hexDigitValue'`.
3. `xcodebuild build-for-testing ... > /private/tmp/ops-decks-p1-2-build.log 2>&1`
   - Result: captured the focused build log, isolated the parser compile failure, then reran after replacing `hexDigitValue` with explicit ASCII hex decoding.
4. `xcodebuild build-for-testing -project OPS.xcodeproj -scheme OPS -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' -only-testing:OPSTests/DeckDrawingFutureBlocksTests -only-testing:OPSTests/DeckBuilderRegressionTests -derivedDataPath /private/tmp/ops-decks-p1-2-tests -clonedSourcePackagesDirPath /Users/jacksonsweet/Projects/OPS/ops-ios/.dd-ptr-fix/SourcePackages -disableAutomaticPackageResolution CODE_SIGNING_ALLOWED=NO`
   - Result: `** TEST BUILD SUCCEEDED **`.
5. `xcodebuild test-without-building -project OPS.xcodeproj -scheme OPS -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' -only-testing:OPSTests/DeckDrawingFutureBlocksTests -only-testing:OPSTests/DeckBuilderRegressionTests -derivedDataPath /private/tmp/ops-decks-p1-2-tests CODE_SIGNING_ALLOWED=NO > /private/tmp/ops-decks-p1-2-test.log 2>&1`
   - Result: compile artifacts launched into XCTest, but the shared host crashed before the test bundle connected: `OPS (82093) encountered an error (Early unexpected exit, operation never finished bootstrapping - no restart will be attempted. (Underlying Error: Test crashed with signal trap before establishing connection.))`
6. `git diff --check -- OPS/DeckBuilder/Models/DeckDrawingFutureBlocks.swift OPS/DeckBuilder/Models/DeckGeometry.swift OPSTests/DeckBuilder/DeckDrawingFutureBlocksTests.swift .superpowers/sdd/task-2-report.md`
   - Result: passed.

COMMAND RESULTS SUMMARY:
- Style-token scanner: PASS
- Focused `build-for-testing`: PASS
- Focused `test-without-building`: FAILED AT XCTest host bootstrap with exact crash string preserved above
- Diff hygiene (`git diff --check`): PASS

FOCUSED VERIFICATION EVIDENCE:
- Unknown future-block numbers now preserve raw JSON tokens as strings inside `DeckJSONValue.number(String)` instead of `Double`.
- `DeckDrawingData.fromJSON(_:)` now harvests unknown top-level blocks with the custom parser after decoding known fields, so future blocks keep nested arrays/objects/nulls plus exact numeric lexemes.
- `DeckDrawingData.toJSON()` now encodes known keys first, then merges only non-colliding, validated future blocks back into the JSON object with raw-number rendering intact.
- `DeckDrawingFutureBlocksTests` now asserts structural round-trip equality and exact numeric-token preservation, and it explicitly checks that `futureBlocks` cannot override known `DeckDrawingData` keys on encode.

SELF-REVIEW NOTES:
- Scope stayed inside the task-2 model/test files plus this report.
- Unknown/future block handling remains opaque; no framing/zoning/code/rendering behavior was added.
- Remaining concern is outside this patch: focused XCTest still cannot execute because the shared `OPS` host crashes before establishing the test connection, even after the focused build succeeds.
