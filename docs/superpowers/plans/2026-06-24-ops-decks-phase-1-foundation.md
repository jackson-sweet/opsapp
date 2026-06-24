# OPS Decks — Phase 1: Foundation / Carve-Out — Implementation Plan

**Date:** 2026-06-24
**Status:** Ready for execution (TDD, bite-sized tasks)
**Phase:** P1 of 7 (foundation/carve-out)

**Read first (the binding inputs):**
- Architecture contract (LOCKED): `docs/superpowers/plans/2026-06-24-ops-decks-architecture-contract.md`
- Feature roadmap: `docs/superpowers/specs/2026-06-24-ops-decks-feature-roadmap.md`
- Phase 1 foundation spec: `docs/superpowers/specs/2026-06-24-ops-decks-standalone-app-design.md`

---

## Goal

Stand up **OPS Decks** as a second iOS app target sharing one codebase with OPS, by extracting the existing deck designer (`OPS/DeckBuilder/`, 73 files + `OPS/DataModels/DeckDesign.swift`) into two Swift packages (`OPSDesignKit` for styling tokens, `DeckKit` for the app-agnostic designer), then wiring standalone auth (Sign in with Apple → Firebase → company-of-one `users`/`companies` rows), RevenueCat `deck_pro` entitlement with a free 1-deck gate, same-backend SwiftData/Supabase sync with offline autosave, a `deck_subscriptions` mirror fed by a RevenueCat → ops-web webhook, in-app account deletion, upgrade-to-OPS continuity scaffolding, the two no-engineering correctness wins (per-pattern estimate waste factor; brand-neutral material catalog data model), the client proposal + upgraded render, and a minimal deck library/create/open shell.

**Phase 1 success definition (from spec §1):** a user installs OPS Decks, designs a deck with no account, signs in with Apple at first save, is provisioned as their own one-person company in the *same* Supabase backend, saves the deck, and is correctly gated at the free (1 saved deck) / Pro (unlimited) boundary — with the LIGHT/FULL `drawing_data` round-trip guaranteed and the upgrade-to-OPS data continuity real.

**What this phase does NOT do:** any net-new deck *engineering* (framing, sizing, footings, terrain, openings, compliance, permit output) — those are P2–P7. `CodePackageLoader` ships as a no-op stub. Capability flags are introduced and the LIGHT/FULL split is wired, but every FULL-only engine slot stays empty until its phase.

---

## Architecture

**Module layout (contract §1.1), realized as an Xcode workspace wrapping the existing `OPS.xcodeproj` + two local SPM packages:**

```
OPS.xcworkspace                       ← NEW (wraps the project + packages)
├─ Packages/OPSDesignKit  (SPM)       ← OPSStyle + Styles/Components/* (styling only, no domain logic)
├─ Packages/DeckKit       (SPM)       ← entire deck designer, app-agnostic; depends on OPSDesignKit
│     exposes seams: DeckStore, ImageUploader, OCRService, CodePackageLoader, CapabilityProvider
├─ OPS          (app target)          ← existing app; depends on DeckKit; supplies OPSDeckStore etc.
└─ OPS Decks    (app target)          ← NEW thin shell; depends on DeckKit; supplies DecksApp* seams
```

**Bedrock invariants enforced this phase (contract §0):** one additive backward-decodable `drawing_data` blob; unknown/failed sub-block decodes to `nil` and is *preserved on re-encode* (`unknownBlocks` passthrough); `DeckDesign.version` becomes the live schema version (P1 = 1); DeckKit knows nothing about `Project`/`Company`/`AppState`/`SyncEngine`/`DataController` — it reaches the host only through `companyId: String`/`projectId: String?` primitives + the protocol seams.

**Extraction is mechanical, not a rewrite (spec §4.1):** relocate files, replace global reaches with injected seams/params, confirm `DeckDesign` + sync models reachable from both targets. Coupling to sever: `companyId` (14 files) + `projectId`/`Project` (8 files) → parameters; `SyncEngine` (2) + `DataController` (1) → behind `DeckStore`; thumbnail/photo upload → `ImageUploader`; OCR/AI → `OCRService`. Zero `AppState`/`AuthManager`/`ImageSyncManager` references exist in `DeckBuilder/`, so no app-wide-state seam is needed.

**Company-of-one (spec §5, verified live 2026-06-24):** `deck_designs` RLS is a single `company_isolation` `FOR ALL` policy `company_id = private.get_user_company_id()`. A user sees exactly their company's decks; a company-of-one sees only their own. Provisioning creates one `companies` row (`admin_ids=[uid]`, `subscription_plan='decks'`) + one `users` row (`firebase_uid`/`auth_id` = Firebase `sub`, `company_id` = new company). **Zero deck-specific RLS changes needed.** The only net-new schema object is `deck_subscriptions` (confirmed absent today).

**Billing (spec §6):** RevenueCat over StoreKit 2; entitlement `deck_pro`; free = 1 saved deck, Pro = unlimited. Gate is a client/business rule enforced against the cached RevenueCat receipt (offline-tolerant) using `DeckStore.savedDeckCount`, not RLS. Server mirror `deck_subscriptions` fed by a RevenueCat → ops-web webhook for web/analytics + the upgrade path.

## Tech Stack

- **Swift / SwiftUI / SwiftData**, Xcode 16 synchronized groups (new files auto-included; no `.pbxproj` edits for files added inside an existing target's group — but *package* creation and the new app target DO require project/workspace edits).
- **Local Swift packages** (`Packages/OPSDesignKit`, `Packages/DeckKit`) referenced from `OPS.xcworkspace`.
- **RevenueCat SDK** (new SPM dependency) over **StoreKit 2**. Cost: free under ~$2.5k/mo tracked revenue then ~1% (spec §11).
- **Firebase Auth** + **Sign in with Apple** (`AppleSignInManager`/`FirebaseAuthService` already exist in OPS).
- **Supabase** (project `ijeekuhbatykdomumfjx`, prod) — same backend; `deck_subscriptions` migration via `apply_migration`. **Supabase Pro ($25/mo) is a HARD prerequisite before any standalone customer data lands** (free tier has no backups — memory `supabase-ops-app-free-tier-no-backups`); flagged as a gate, not a code task.
- **ops-web** Next.js endpoint for the RevenueCat webhook (`/api/webhooks/revenuecat`) + reuse of existing presign upload endpoints.
- **Build verification:** device target `xcodebuild -scheme OPS -destination 'generic/platform=iOS'` and `xcodebuild -scheme 'OPS Decks' -destination 'generic/platform=iOS'`. **Tests:** simulator `-destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5'` (`build-for-testing` to verify compile, `test` to run). Copy `OPS/Utilities/Secrets.xcconfig` into any worktree first. Grep build logs for `BUILD SUCCEEDED` / `TEST SUCCEEDED` (memory `xcodebuild-exit-code-masking` — background exit code is the trailing echo, not the build).

---

## Sequencing & ground rules

- **Carve-out ordering (spec §12.5):** the in-flight deck-overhaul work targets the same files. Do the package extraction (Group A) as a coherent block, land it, then everything else builds on `DeckKit`. Before any destructive move, check `git worktree list` / `lsof` for sibling sessions on `DeckBuilder/` (memory `crew-deck-blackout` / parallel-session hazards). Stage by name; never `git add -A`.
- **Group order:** A (packages + extraction) → B (schema/round-trip + version live) → C (seams: DeckStore/ImageUploader/OCRService/CodePackageLoader stub + capability) → D (OPS Decks app target + auth + company-of-one) → E (billing + gate + deck_subscriptions + webhook) → F (account deletion + upgrade scaffolding) → G (waste-factor fix) → H (brand-neutral catalog model) → I (client proposal + upgraded render) → J (minimal library/create/open shell). Within a group, tasks are ordered.
- **Every schema task** adds one optional top-level property on `DeckDrawingData`, `decodeIfPresent` + default, plus round-trip tests (contract §8.1/§8.2). The existing per-struct defensive `init(from:)` pattern (e.g. `RailingConfig`, `StairConfig`) is the template.
- **CRLF caution** (memory `ops-ios-crlf-edit-churn`): preserve original line endings on edited files. **Worktree SourceKit lag** (memory): trust `xcodebuild`, not editor "cannot find type" noise.

---

# GROUP A — Packages + extraction

## Task A1 — Create `OPSDesignKit` package, move `OPSStyle` + `Styles/Components/*`

**Goal:** one shared styling source both app targets and `DeckKit` depend on (contract §1.1 decision: separate package, not vendored).

**Files:**
- Create `Packages/OPSDesignKit/Package.swift` (library product `OPSDesignKit`, platform iOS 17+, no dependencies).
- Create `Packages/OPSDesignKit/Sources/OPSDesignKit/` and MOVE into it: `OPS/Styles/OPSStyle.swift` + every file under `OPS/Styles/Components/` (29 files: `Atmosphere.swift`, `ButtonStyles.swift`, `CardStyles.swift`, …, `View+ErrorToast.swift`).
- Modify each moved file: mark the public API `public` where consumed cross-module (OPSStyle's `Colors`, `Layout`, `Typography`, `Icons` namespaces + component initializers/modifiers). Add `import SwiftUI`.
- Modify `OPS.xcodeproj` + create `OPS.xcworkspace`: add the package, link `OPSDesignKit` to the `OPS` app target. Add `import OPSDesignKit` where `OPSStyle` is referenced app-wide (broad — script the insertion, then compile-fix).
- Create `Packages/OPSDesignKit/Tests/OPSDesignKitTests/OPSStyleTokenTests.swift`.

**Steps:**
1. **Write failing test.** `OPSStyleTokenTests`: assert the package compiles and key tokens are public + stable, e.g.
   ```swift
   import XCTest
   import SwiftUI
   @testable import OPSDesignKit
   final class OPSStyleTokenTests: XCTestCase {
       func testAccentTokenIsPublicAndStable() {
           // Steel-blue accent must remain reachable cross-module.
           XCTAssertNotNil(OPSStyle.Colors.primaryAccent)
       }
       func testSpacingScaleIsPublic() {
           XCTAssertGreaterThan(OPSStyle.Layout.spacing4, OPSStyle.Layout.spacing2)
       }
   }
   ```
2. **Run (expected fail — does not compile):** `swift test --package-path Packages/OPSDesignKit` → fails: `OPSStyle` not found / not public.
3. **Implement:** move files, add `public`, set up `Package.swift`, wire the package into the workspace + OPS target, insert `import OPSDesignKit`.
4. **Run (expected pass):** `swift test --package-path Packages/OPSDesignKit` → `Test Suite 'OPSStyleTokenTests' passed`. Then device build the OPS app: `xcodebuild -scheme OPS -destination 'generic/platform=iOS' build 2>&1 | tee /tmp/a1.log; grep -E 'BUILD (SUCCEEDED|FAILED)' /tmp/a1.log`.
5. **Commit:** `refactor(decks): extract OPSStyle + Styles/Components into OPSDesignKit package`

## Task A2 — Create `DeckKit` package skeleton + move models/engines/rendering (no behavior change)

**Goal:** relocate the geometry models, engines, rendering, 3D, AR, and views into `DeckKit/Sources/DeckKit/` per the submodule map (contract §1.2). Mechanical move; decoupling lands in A3–A5.

**Files:**
- Create `Packages/DeckKit/Package.swift` (library `DeckKit`, iOS 17+, depends on `OPSDesignKit`).
- MOVE `OPS/DataModels/DeckDesign.swift` → `Packages/DeckKit/Sources/DeckKit/Models/DeckDesign.swift`.
- MOVE all 73 files under `OPS/DeckBuilder/` into `Packages/DeckKit/Sources/DeckKit/` preserving the submodule grouping: `Models/` (`DeckGeometry.swift`, `DeckLevel.swift`, `DeckDrawingState.swift`, `BuiltInMaterial.swift`, `ProductUnitDimension.swift`, `SketchScanResult.swift`, `PhotoOverlayState.swift`, `DeckTemplateDefinitions.swift`), `Engine/`, `Rendering/`, `Scene3D/` (the `3D/` files), `AR/`, `Views/`, `Services/`.
- Modify moved files: `public` on every type/initializer/static func consumed across the module boundary (`DeckDrawingData`, `DeckDesign`, `StairCalculator`, `VinylCutListEngine`, `ComponentEmitter`, `EstimateGeneratorService`, `SurfaceDetector`, `DeckTemplateEngine`, `DeckBuilderView`, etc.). Replace `import` of removed OPS types with the seam params introduced in A3–A5 (temporarily compile against TODO stubs is NOT allowed — A2 keeps the files but DOES move out-of-module references; pair A2 tightly with A3 in one branch).
- Create `Packages/DeckKit/Tests/DeckKitTests/` and MOVE the existing deck tests there: `OPSTests/DeckBuilder/*` (StairCalculatorTests, EstimateGeneratorServiceTests, ComponentEmitterTests, VinylCutListEngineTests, MultiLevelTests, DeckBuilderRegressionTests, DeckPerimeterClosureTests, AccuracyModelTests, LevelConnectionStairFlipTests, VinylOffcutInventoryTests, VinylPreviewAnnotationPlannerTests, VinylOrderSelectionTests, DeckSceneSnapshotTests) — change `@testable import OPS` → `@testable import DeckKit`.

**Steps:**
1. **Write failing test (the move IS the failing test):** the moved `StairCalculatorTests` under `DeckKitTests` with `@testable import DeckKit` will not compile until `StairCalculator` is `public` inside `DeckKit`.
2. **Run (expected fail):** `swift test --package-path Packages/DeckKit --filter StairCalculatorTests` → does not compile (`StairCalculator` not found in `DeckKit`).
3. **Implement:** the moves + `public` annotations + the OPSDesignKit dependency.
4. **Run (expected pass):** `swift test --package-path Packages/DeckKit --filter StairCalculatorTests` → passes. (Other engine tests that need no host types pass too; tests needing host types are fixed in A3.)
5. **Commit:** `refactor(decks): relocate DeckBuilder + DeckDesign into DeckKit package`

## Task A3 — Define the four protocol seams + `CapabilityProvider` (signatures verbatim from contract §1.3/§4)

**Goal:** introduce the only sanctioned bridge from `DeckKit` to a host. Signatures are copied verbatim from the contract — no deviation.

**Files:**
- Create `Packages/DeckKit/Sources/DeckKit/Seams/DeckStore.swift` — `public protocol DeckStore: Sendable` with `listDecks`, `loadDeck`, `saveDeck`, `deleteDeck`, `savedDeckCount`, `deckChanges` (exact signatures, contract §1.3).
- Create `Packages/DeckKit/Sources/DeckKit/Seams/ImageUploader.swift` — `public protocol ImageUploader: Sendable` with `uploadThumbnail`, `uploadOverlayImage`, `deleteAsset`.
- Create `Packages/DeckKit/Sources/DeckKit/Seams/OCRService.swift` — `public protocol OCRService: Sendable` with `recognizeText`, `interpretSketch`; plus supporting value types `public struct SketchOCRObservation { text: String; box: CGRect; confidence: Double }`, `public struct SketchScanHints`, `public enum OCRServiceError: Error { case unavailable, lowConfidence, failed(Error) }` (`SketchScanResult` already exists in `Models/`).
- Create `Packages/DeckKit/Sources/DeckKit/Seams/CodePackageLoader.swift` — `public protocol CodePackageLoader: Sendable` with `availableJurisdictions`, `loadPackage`, `activePackage(for:)`, `refreshCatalog`; plus the loader error enum `public enum CodePackageLoaderError: Error { case unavailable, notDownloaded, offline }` (defined here in P1, consumed by P3's `CodePackageLoaderLive`); plus the value types. **`JurisdictionDescriptor` is the P1-owned superset shape (P3 consumes it, does not re-declare it)** — adopt verbatim:
  ```swift
  public struct JurisdictionDescriptor: Codable, Equatable, Sendable, Identifiable {
      public var id: String
      public var displayName: String
      public var country: String
      public var region: String
      public var availableEditions: [String]
      public var latestEdition: String?
      public var latestPublishedDate: Date?
      public var isDownloaded: Bool
  }
  ```
  and `public struct CodePackage: Codable, Equatable, Sendable` (P1 carries only `jurisdictionId`, `edition`, `publishedDate`, `unitSystem` — the full table fields land P3; keep additive).
- Create `Packages/DeckKit/Sources/DeckKit/Capability/DeckCapabilities.swift` — `public struct DeckCapabilities: OptionSet, Sendable` with the exact bit assignments + `.light`/`.full` sets from contract §4; `public protocol CapabilityProvider: Sendable { var capabilities: DeckCapabilities { get } }`.
- Modify the moved `DeckBuilderViewModel` + `DeckBuilderView` to accept `deckStore: DeckStore`, `imageUploader: ImageUploader`, `ocr: OCRService`, `codePackages: CodePackageLoader`, `capabilities: CapabilityProvider` injected at init (replacing the `modelContext`/`syncEngine` direct dependency). Replace the 14-file `companyId` reach and 8-file `Project`/`projectId` reach with the already-present `companyId: String` / `projectId: String?` init params (they're already primitives on `DeckBuilderView` per line 25-31 — extend through the VM and any helper that still reaches a global).
- Create `Packages/DeckKit/Tests/DeckKitTests/Seams/SeamContractTests.swift`.

**Steps:**
1. **Write failing test.** A spy/in-memory `DeckStore` conformance proves the protocol shape compiles and round-trips:
   ```swift
   import XCTest
   @testable import DeckKit
   final class SeamContractTests: XCTestCase {
       func testInMemoryDeckStoreConforms() async throws {
           let store = InMemoryDeckStore()
           let deck = DeckDesign(companyId: "c1")
           try await store.saveDeck(deck)
           let count = try await store.savedDeckCount(companyId: "c1")
           XCTAssertEqual(count, 1)
           let loaded = try await store.loadDeck(id: deck.id)
           XCTAssertEqual(loaded?.id, deck.id)
       }
       func testLightCapabilitiesExcludeStructuralSizing() {
           XCTAssertFalse(DeckCapabilities.light.contains(.structuralSizing))
           XCTAssertTrue(DeckCapabilities.full.contains(.structuralSizing))
           XCTAssertTrue(DeckCapabilities.light.contains(.wasteFactor))
       }
   }
   ```
   (`InMemoryDeckStore` is a test double defined in the test target.)
2. **Run (expected fail):** `swift test --package-path Packages/DeckKit --filter SeamContractTests` → `DeckStore`/`DeckCapabilities` not found.
3. **Implement:** the five seam files + the VM/View injection refactor.
4. **Run (expected pass):** `swift test --package-path Packages/DeckKit --filter SeamContractTests` → passes; full DeckKit suite green: `swift test --package-path Packages/DeckKit 2>&1 | tee /tmp/a3.log; grep -E "Test Suite 'All tests'|error:" /tmp/a3.log`.
5. **Commit:** `feat(decks): add DeckStore/ImageUploader/OCRService/CodePackageLoader seams + capability flags`

## Task A4 — OPS-target seam implementations (`OPSDeckStore`, `OPSImageUploader`, `OPSOCRService`) + rewire OPS call sites

**Goal:** the existing OPS app keeps working end-to-end against `DeckKit` via OPS-flavored seams backed by the existing `SyncEngine` / presign endpoints / `SketchOCR`.

**Files:**
- Create `OPS/DeckBuilder/Host/OPSDeckStore.swift` — `final class OPSDeckStore: DeckStore`, backed by `DataActor` / `ModelContext` + `SyncEngine` (the existing inbound/outbound deck-design path: `DataActor.syncDeckDesigns`, `validDeckDesignColumns`, `DeckDesignRepository`). `deckChanges` bridges the existing `InboundChangeSignal`/Router repaint mechanism into an `AsyncStream` (memory `ios-scheduling-sync-integrity` — inbound snapshot caches need a repaint signal).
- Create `OPS/DeckBuilder/Host/OPSImageUploader.swift` — wraps `PresignedURLUploadService` (S3 server-mediated; no AWS keys — memory `ios-aws-credential-removal`).
- Create `OPS/DeckBuilder/Host/OPSOCRService.swift` — wraps the existing `SketchOCR` + `SketchAIFallback` (now living in DeckKit; the OPS impl calls DeckKit's recognition + the app's network AI fallback).
- Create `OPS/DeckBuilder/Host/OPSDeckCapabilityProvider.swift` — returns `.light` (OPS embeds the LIGHT tier).
- Create `OPS/DeckBuilder/Host/NoopCodePackageLoader.swift` — the P1 stub: `availableJurisdictions` → `[]`, `loadPackage` throws `CodePackageLoaderError.unavailable` (the error enum defined in `CodePackageLoader.swift`, A3), `activePackage(for:)` → `nil`, `refreshCatalog` → no-op (contract §1.3: "ships in P1 as a no-op stub, implemented in P3"). Lives in DeckKit so both targets share it: `Packages/DeckKit/Sources/DeckKit/Seams/NoopCodePackageLoader.swift`.
- Modify `OPS/Views/JobBoard/ProjectFormSheet.swift` and `OPS/Views/Components/Project/ProjectDetailsView.swift` (the two `DeckBuilderView(` call sites) + `OPS/Views/Components/Project/Tabs/DeckTabView.swift` to inject the OPS seams.
- Modify `OPS/DataModels/Migrations/OPSSchemaCommon.swift` line ~495: `DeckDesign.self` now resolves from `DeckKit` (add `import DeckKit`); confirm the SwiftData schema still registers it.

**Steps:**
1. **Write failing test.** `OPSTests/DeckBuilder/OPSDeckStoreTests.swift` (`@testable import OPS`, `import DeckKit`) — an in-memory `ModelContext` round-trip through `OPSDeckStore`:
   ```swift
   func testSaveThenListReturnsDeck() async throws {
       let store = OPSDeckStore(context: inMemoryContext, syncEngine: nil)
       let deck = DeckDesign(companyId: companyId)
       try await store.saveDeck(deck)
       let decks = try await store.listDecks(companyId: companyId)
       XCTAssertEqual(decks.map(\.id), [deck.id])
       XCTAssertTrue(deck.needsSync)        // save marks for sync
   }
   func testSavedDeckCountExcludesSoftDeleted() async throws { /* delete → count drops */ }
   ```
2. **Run (expected fail):** `xcodebuild build-for-testing -scheme OPS -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' 2>&1 | tee /tmp/a4.log; grep -E 'error:|BUILD' /tmp/a4.log` → `OPSDeckStore` not found.
3. **Implement:** the four host impls + the no-op loader + call-site rewiring.
4. **Run (expected pass):** `xcodebuild test -scheme OPS -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' -only-testing:OPSTests/OPSDeckStoreTests 2>&1 | tee /tmp/a4t.log; grep -E 'TEST (SUCCEEDED|FAILED)' /tmp/a4t.log`. Device build: `xcodebuild -scheme OPS -destination 'generic/platform=iOS' build`.
5. **Commit:** `feat(decks): OPS host seam impls + rewire DeckBuilderView call sites onto DeckKit`

---

# GROUP B — Schema: version live + round-trip preservation

## Task B1 — `unknownBlocks` passthrough + extend `AnyCodable` to nested values

**Goal:** a build that doesn't know a top-level `drawing_data` key must round-trip it untouched (contract §1.4, §0.2). This is the keystone of LIGHT/FULL graceful degradation and directly addresses the stale-overwrite/crew-blackout incidents.

**Files:**
- Modify `Packages/DeckKit/Sources/DeckKit/Engine/ComponentEmitter.swift` — extend `AnyCodable` (lines 343-390) to also carry nested `[String: AnyCodable]` (object) and `[AnyCodable]` (array) cases in `init(from:)`/`encode(to:)`/`==` (today scalar-only). Keep all existing scalar behavior identical.
- Modify `Packages/DeckKit/Sources/DeckKit/Models/DeckGeometry.swift` `DeckDrawingData` — add `public var unknownBlocks: [String: AnyCodable]? = nil`. In `init(from:)`, after decoding all known keys, decode the full container into a generic `[String: AnyCodable]` keyed dictionary, subtract the known `CodingKeys` raw values, and stash the remainder in `unknownBlocks`. In a custom `encode(to:)` (currently synthesized via `toJSON`'s `copy.components` path — make `encode(to:)` explicit), re-emit every `unknownBlocks` entry as a top-level key. **Do NOT add `unknownBlocks` to `CodingKeys`** (it is not a real key — it's the catch-all).

**Steps:**
1. **Write failing test.** `Packages/DeckKit/Tests/DeckKitTests/Schema/RoundTripPreservationTests.swift`:
   ```swift
   func testUnknownTopLevelBlockSurvivesRoundTrip() throws {
       // Simulate a FULL-authored design opened by a LIGHT build: inject a
       // "framing" block this build's struct does not declare.
       let fullJSON = """
       {"vertices":[],"edges":[],"framing":{"members":[{"levelId":"L1"}],"loadPreset":{"liveLoadPSF":40}}}
       """
       let data = DeckDrawingData.fromJSON(fullJSON)!
       let reEncoded = data.toJSON()
       XCTAssertTrue(reEncoded.contains("\"framing\""), "FULL block dropped on re-encode")
       XCTAssertTrue(reEncoded.contains("\"liveLoadPSF\""))
   }
   func testNestedAnyCodableEquatable() { /* object/array round-trip equality */ }
   ```
2. **Run (expected fail):** `swift test --package-path Packages/DeckKit --filter RoundTripPreservationTests` → `framing` stripped on re-encode (assertion fails).
3. **Implement:** nested `AnyCodable` + `unknownBlocks` capture/re-emit + explicit `encode(to:)`.
4. **Run (expected pass):** filter passes; full DeckKit suite green (verify no existing `toJSON` snapshot broke).
5. **Commit:** `feat(decks): preserve unknown drawing_data blocks on re-encode (LIGHT/FULL round-trip)`

## Task B2 — `schemaVersion` in-blob + make `DeckDesign.version` the live schema version

**Goal:** self-describing JSON + a live, monotonic schema version (contract §0.3, §2.2 row P1=1). Gates migration/backfill, never rendering.

**Files:**
- Modify `Packages/DeckKit/Sources/DeckKit/Models/DeckGeometry.swift` — add `public var schemaVersion: Int? = nil` to `DeckDrawingData` + `CodingKeys` + `decodeIfPresent`. In `toJSON()`, set `copy.schemaVersion = DeckSchema.current` (= 1) before encode.
- Create `Packages/DeckKit/Sources/DeckKit/Models/DeckSchema.swift` — `public enum DeckSchema { public static let current = 1 }` (the phase-bumped constant; P2 → 2, etc.).
- Modify `Packages/DeckKit/Sources/DeckKit/Models/DeckDesign.swift` — the `drawingData` setter already bumps `updatedAt`/`needsSync`; add `self.version = DeckSchema.current` so the row's `version` column tracks the schema (today it's a dead default-1 field per memory). Keep additive: never downgrade `version` on decode of an older blob.

**Steps:**
1. **Write failing test.** `Packages/DeckKit/Tests/DeckKitTests/Schema/SchemaVersionTests.swift`:
   ```swift
   func testToJSONStampsCurrentSchemaVersion() throws {
       let json = DeckDrawingData().toJSON()
       let decoded = DeckDrawingData.fromJSON(json)!
       XCTAssertEqual(decoded.schemaVersion, DeckSchema.current)
   }
   func testSavingDeckBumpsRowVersionToSchemaCurrent() {
       let deck = DeckDesign(companyId: "c1")
       deck.drawingData = DeckDrawingData()   // setter path
       XCTAssertEqual(deck.version, DeckSchema.current)
   }
   ```
2. **Run (expected fail):** filter fails — `schemaVersion` nil / `DeckSchema` not found.
3. **Implement:** `DeckSchema`, `schemaVersion` field, version bump in setter.
4. **Run (expected pass):** filter passes; suite green.
5. **Commit:** `feat(decks): live DeckDesign.version + in-blob schemaVersion (P1 baseline = 1)`

## Task B3 — Malformed sub-block tolerance test (regression lock for §0.2)

**Goal:** prove a malformed/unknown *sub*-block decodes to `nil`/default without failing whole-design decode — lock the invariant so later phases can't regress it.

**Files:**
- Create `Packages/DeckKit/Tests/DeckKitTests/Schema/MalformedSubBlockTests.swift`.

**Steps:**
1. **Write failing test (guards existing + new behavior):**
   ```swift
   func testGarbagePhotoOverlayDoesNotFailWholeDecode() {
       let json = """
       {"vertices":[{"id":"v1","position":{"x":0,"y":0}}],"photoOverlay":"not-an-object"}
       """
       let data = DeckDrawingData.fromJSON(json)
       XCTAssertNotNil(data, "one bad sub-block must not fail the whole-design decode")
       XCTAssertEqual(data?.vertices.count, 1)
   }
   ```
   If `fromJSON` currently throws on a type-mismatched optional sub-block (synthesized decode of `photoOverlay` as `decodeIfPresent` will throw on a present-but-wrong-type value), harden `init(from:)` to wrap each optional sub-block decode in `try?` so a malformed block falls to `nil` (matching the documented invariant) while a *missing* block stays absent.
2. **Run (expected fail if hardening needed):** filter fails (whole decode returns nil).
3. **Implement:** per-sub-block `try?` tolerance in `DeckDrawingData.init(from:)` (preserve the strict decode for required scalars; only optional sub-blocks get the tolerance). Malformed unknown blocks are simply skipped by the `unknownBlocks` catch-all.
4. **Run (expected pass):** filter passes; suite green.
5. **Commit:** `test(decks): lock graceful sub-block decode tolerance (one bad block never fails the design)`

## Task B4 — `PermitMeta` minimal block (introduced P1, completed P7)

**Goal:** ship the `PermitMeta` block in P1 so jurisdiction selection (`jurisdictionId`/`codeEdition`) and compliance-disclaimer acknowledgement (`disclaimerAcknowledgedAt`) exist before P3 sizing runs (contract §2.2 sequencing note, §2.8). P1 ships ALL THREE minimal fields; the compliance result/setbacks/PE-stamp fields land additively in P7 inside the SAME block — no rename, no new top-level key. `PermitMeta` is **not** a stub.

**Files:**
- Create `Packages/DeckKit/Sources/DeckKit/Models/PermitMeta.swift` — the P1-minimal struct, verbatim from contract §2.8:
  ```swift
  public struct PermitMeta: Codable, Equatable, Sendable {
      public var jurisdictionId: String?
      public var codeEdition: String?
      public var disclaimerAcknowledgedAt: Date?
      // defensive init(from:) with decodeIfPresent + defaults (pattern of §2.1);
      // P7 adds setbacks / lastComplianceRunAt / lastComplianceResult / peStampRequest
      // additively inside this same struct — never rename these three.
  }
  ```
- Modify `Packages/DeckKit/Sources/DeckKit/Models/DeckGeometry.swift` `DeckDrawingData` — add `public var permitMeta: PermitMeta? = nil` + the `CodingKeys` case + the `decodeIfPresent` line in the defensive `init(from:)` (alongside the other optional sub-blocks; wrapped in `try?` per B3's tolerance). Round-trip it through `toJSON()`/`fromJSON()`.

**Steps:**
1. **Write failing test.** `Packages/DeckKit/Tests/DeckKitTests/Schema/PermitMetaRoundTripTests.swift`:
   ```swift
   func testPermitMetaPresentSurvivesRoundTrip() throws {
       var data = DeckDrawingData()
       data.permitMeta = PermitMeta(jurisdictionId: "US-IRC", codeEdition: "IRC 2021",
                                    disclaimerAcknowledgedAt: Date(timeIntervalSince1970: 1_700_000_000))
       let back = DeckDrawingData.fromJSON(data.toJSON())!
       XCTAssertEqual(back.permitMeta?.jurisdictionId, "US-IRC")
       XCTAssertEqual(back.permitMeta?.codeEdition, "IRC 2021")
       XCTAssertNotNil(back.permitMeta?.disclaimerAcknowledgedAt)
   }
   func testPermitMetaAbsentDecodesToNil() throws {
       let json = """
       {"vertices":[],"edges":[]}
       """
       let data = DeckDrawingData.fromJSON(json)
       XCTAssertNotNil(data)
       XCTAssertNil(data?.permitMeta)
   }
   ```
2. **Run (expected fail):** `swift test --package-path Packages/DeckKit --filter PermitMetaRoundTripTests` → `PermitMeta` not found / `permitMeta` nil after round-trip.
3. **Implement:** the `PermitMeta.swift` struct + the `DeckDrawingData` field/CodingKeys/decode wiring.
4. **Run (expected pass):** filter passes; full DeckKit suite green.
5. **Commit:** `feat(decks): add minimal PermitMeta block (jurisdiction + code edition + disclaimer ack)`

---

# GROUP C — already covered structurally in A3 (seams) + the capability injection

> The seams and capability flags land in A3; `NoopCodePackageLoader` in A4. No separate Group C tasks — the contract's §1.3/§4 surface is fully introduced there. (This note prevents a phantom group; the contract maps P1 seams to Group A.)

---

# GROUP D — OPS Decks app target + auth + company-of-one

## Task D1 — Create the `OPS Decks` app target + bundle id + capabilities

**Goal:** a second app target booting `DeckKit`, signed, with Sign in with Apple capability.

**Files:**
- Modify `OPS.xcodeproj` / `OPS.xcworkspace`: new app target `OPS Decks`, bundle id `co.opsapp.ops.decks` (spec §9), product name "OPS Decks". Link `DeckKit` + `OPSDesignKit`. Add the **Sign in with Apple** capability + an `OPS Decks.entitlements`. Reuse the Firebase config (separate `GoogleService-Info.plist` for the new bundle id — provisioning step flagged below).
- Create `OPS Decks/OPSDecksApp.swift` — `@main struct OPSDecksApp: App`, builds the SwiftData `ModelContainer` (registers `DeckDesign` from `DeckKit` + the minimal models the standalone needs), constructs the DecksApp seams, shows the root shell (J1).
- Create `OPS Decks/Info.plist`, `OPS Decks/Assets.xcassets` (placeholder app icon), `OPS Decks/OPS Decks.entitlements`.
- Create `OPS Decks/Secrets.xcconfig` reference (build-setting substitution for `MBX_ACCESS_TOKEN`, mirroring OPS — the standalone reuses Mapbox-less deck rendering, but keep the config slot for parity; document that the standalone holds no AWS keys).

**Steps:**
1. **Write failing test.** `OPSDecksTests/AppBootstrapTests.swift` (new test target `OPSDecksTests`, `@testable import` the app module + `import DeckKit`):
   ```swift
   func testModelContainerRegistersDeckDesign() throws {
       let container = OPSDecksApp.makeModelContainer(inMemory: true)
       let ctx = ModelContext(container)
       let deck = DeckDesign(companyId: "c1")
       ctx.insert(deck)
       try ctx.save()
       let fetched = try ctx.fetch(FetchDescriptor<DeckDesign>())
       XCTAssertEqual(fetched.count, 1)
   }
   ```
   (`makeModelContainer(inMemory:)` is a static factory on `OPSDecksApp` so tests can build the container without launching the UI.)
2. **Run (expected fail):** `xcodebuild build-for-testing -scheme 'OPS Decks' -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5'` → scheme/target/app symbol missing.
3. **Implement:** target, plists, entitlements, `OPSDecksApp` + `makeModelContainer`.
4. **Run (expected pass):** `xcodebuild test -scheme 'OPS Decks' -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' -only-testing:OPSDecksTests/AppBootstrapTests`. Device build: `xcodebuild -scheme 'OPS Decks' -destination 'generic/platform=iOS' build`.
5. **Commit:** `feat(decks): add OPS Decks app target (bundle co.opsapp.ops.decks) booting DeckKit`

> **Provisioning gate (not a code task, flag to Jackson):** App Store Connect app record + bundle id + provisioning profiles + a `GoogleService-Info.plist` for `co.opsapp.ops.decks` in the Firebase console. Sign in with Apple service id. These are Apple/Firebase-portal steps that must precede device/TestFlight (mirrors the share-extension portal gate, memory `ios-share-extension`).

## Task D2 — `DecksAppDeckStore` / `DecksAppImageUploader` / `DecksAppOCRService` (lean seams)

**Goal:** standalone seam impls hitting the same SwiftData models + same Supabase backend + same ops-web presign endpoints (spec §4.1: "both talk to the same backend; the protocol exists for testability, not two storage systems").

**Files:**
- Create `OPS Decks/Host/DecksAppDeckStore.swift` — `final class DecksAppDeckStore: DeckStore`. Backed by a lean Supabase REST + SwiftData layer. Reuse the existing `SupabaseDeckDesignDTO` (from `DeckKit` after A2 moves `DeckDesign`; the DTO stays in OPS — so EITHER move the DTO into DeckKit, OR have the standalone define its own thin DTO). **Decision:** move `OPS/Network/Supabase/DTOs/DeckDesignDTOs.swift` into `Packages/DeckKit/Sources/DeckKit/Sync/DeckDesignDTO.swift` (it depends only on `DeckDesign` + `DeckDrawingData` + `SupabaseDate` — move `SupabaseDate` parse helper or inline a minimal ISO8601 parser into DeckKit to avoid pulling the whole network stack). Mark the DTO `public`.
- Create `OPS Decks/Host/DecksAppImageUploader.swift` — POSTs to the same ops-web presign endpoints (`/api/uploads/presign`, `/api/uploads/delete`) with the standalone user's Firebase token.
- Create `OPS Decks/Host/DecksAppOCRService.swift` — on-device Vision OCR (Apple `VNRecognizeTextRequest`) for `recognizeText`; `interpretSketch` calls the same AI endpoint as OPS or throws `.unavailable` offline (spec §8: OCR requires connectivity, degrades gracefully).
- Create `OPS Decks/Host/DecksAppCapabilityProvider.swift` — returns base `.full` shell (contract §7 P1 row), further gated by the `deck_pro` entitlement for the saved-deck cap in E2 (capabilities ≠ deck-count gate; the cap is enforced in the store/shell, not by stripping capabilities).

**Steps:**
1. **Write failing test.** `OPSDecksTests/DecksAppDeckStoreTests.swift` — local SwiftData round-trip (network mocked):
   ```swift
   func testLocalSaveAndCountAndSoftDelete() async throws {
       let store = DecksAppDeckStore(context: inMemoryContext, network: MockDeckNetwork())
       let d = DeckDesign(companyId: "c1")
       try await store.saveDeck(d)
       XCTAssertEqual(try await store.savedDeckCount(companyId: "c1"), 1)
       try await store.deleteDeck(id: d.id)
       XCTAssertEqual(try await store.savedDeckCount(companyId: "c1"), 0) // soft-deleted excluded
   }
   ```
2. **Run (expected fail):** build-for-testing fails — `DecksAppDeckStore` missing.
3. **Implement:** the three lean seams + the DTO move into DeckKit.
4. **Run (expected pass):** `xcodebuild test -scheme 'OPS Decks' … -only-testing:OPSDecksTests/DecksAppDeckStoreTests`.
5. **Commit:** `feat(decks): standalone DeckStore/ImageUploader/OCRService impls (same backend, lean path)`

## Task D3 — Company-of-one provisioning service

**Goal:** on first sign-in/save, create one `companies` row (`admin_ids=[uid]`, `subscription_plan='decks'`) + one `users` row (`firebase_uid`/`auth_id`=`sub`, `company_id`=new company), so `get_user_company_id()` resolves and RLS isolates automatically (spec §5). Pure-logic core is testable; the network write is behind a protocol.

**Files:**
- Create `OPS Decks/Auth/CompanyOfOneProvisioner.swift` — `struct CompanyOfOneProvisioner`. A pure `func plan(for identity: AppleIdentity, existingUser: UsersRow?) -> ProvisioningPlan` that decides: (a) existing linked user with a company → no-op (return existing companyId); (b) existing user, no company → attach a new deck company; (c) brand-new → create both rows. The actual writes go through a `ProvisioningBackend` protocol (Supabase REST) so the planner is unit-tested without network.
- Define value types: `AppleIdentity { sub, email?, fullName? }`, `ProvisioningPlan { createCompany: CompanyDraft?, createUser: UserDraft?, attachToCompanyId: String?, resolvedCompanyId: String }`, `CompanyDraft { name, adminIds, subscriptionPlan: "decks" }`, `UserDraft { firebaseUid, authId, companyId, role }`.
- Create `OPS Decks/Auth/DecksAuthCoordinator.swift` — orchestrates `AppleSignInManager` (reused from OPS — move it to a shared spot or duplicate the thin wrapper) → `FirebaseAuthService` → `CompanyOfOneProvisioner` → caches identity locally (spec §8: cache identity after first sign-in).

**Steps:**
1. **Write failing test.** `OPSDecksTests/CompanyOfOneProvisionerTests.swift`:
   ```swift
   func testBrandNewUserCreatesCompanyAndUser() {
       let plan = CompanyOfOneProvisioner().plan(
           for: AppleIdentity(sub: "fb_123", email: "a@b.com", fullName: "Dana Lee"),
           existingUser: nil
       )
       XCTAssertNotNil(plan.createCompany)
       XCTAssertEqual(plan.createCompany?.subscriptionPlan, "decks")
       XCTAssertEqual(plan.createCompany?.adminIds, [plan.createUser!.id])
       XCTAssertEqual(plan.createUser?.firebaseUid, "fb_123")
       XCTAssertEqual(plan.resolvedCompanyId, plan.createCompany?.id)
   }
   func testExistingLinkedUserIsNoOp() {
       let existing = UsersRow(id: "u1", firebaseUid: "fb_123", companyId: "co_9")
       let plan = CompanyOfOneProvisioner().plan(for: AppleIdentity(sub: "fb_123"), existingUser: existing)
       XCTAssertNil(plan.createCompany)
       XCTAssertEqual(plan.resolvedCompanyId, "co_9")
   }
   func testCompanyNameDefaultsToNameThenMyDecks() { /* fullName → "Dana Lee"; nil → "My Decks" */ }
   ```
2. **Run (expected fail):** build-for-testing fails — provisioner missing.
3. **Implement:** the planner + value types + the coordinator (coordinator's network path is integration-tested manually; the planner is unit-pure).
4. **Run (expected pass):** `-only-testing:OPSDecksTests/CompanyOfOneProvisionerTests`.
5. **Commit:** `feat(decks): company-of-one provisioning planner (decks-plan company + linked user)`

> **Endpoint-authorization gate (spec §12.4, flag):** confirm ops-web presign/upload + any OCR/AI endpoint authorize a Firebase token whose company is a `subscription_plan='decks'` company. Same auth model — verify with a manual logged-in pass before TestFlight; not a blocking code change here.

---

# GROUP E — Billing + free gate + deck_subscriptions + webhook

## Task E1 — Add RevenueCat SDK + `DeckEntitlementProvider` (offline-tolerant)

**Goal:** wrap RevenueCat behind a protocol so the gate logic is unit-testable and offline-tolerant (reads the cached receipt). Entitlement id `deck_pro` (spec §6).

**Files:**
- Modify `OPS.xcodeproj` / workspace: add the **RevenueCat** SPM package (`https://github.com/RevenueCat/purchases-ios`) to the `OPS Decks` target only.
- Create `OPS Decks/Billing/DeckEntitlementProvider.swift` — `protocol DeckEntitlementProvider { var isPro: Bool { get }; func refresh() async }` + `final class RevenueCatEntitlementProvider: DeckEntitlementProvider` reading `Purchases.shared.customerInfo` for entitlement `"deck_pro"`. Configure RevenueCat in `OPSDecksApp` with the public API key (xcconfig, not committed).
- Create `OPS Decks/Billing/DeckProduct.swift` — product/offering identifiers (monthly `$14.99`, annual `~$99–119`), subscription group constant.

**Steps:**
1. **Write failing test.** `OPSDecksTests/DeckGateTests.swift` uses a fake provider (no SDK call):
   ```swift
   func testFakeEntitlementProviderReportsPro() {
       let p = FakeEntitlementProvider(isPro: true)
       XCTAssertTrue(p.isPro)
   }
   ```
   (The RevenueCat SDK itself isn't unit-tested; the *protocol* and the *gate* are.)
2. **Run (expected fail):** build-for-testing fails — provider type missing.
3. **Implement:** add the SDK dependency, the provider protocol + RevenueCat impl + product ids.
4. **Run (expected pass):** filter passes; `xcodebuild -scheme 'OPS Decks' -destination 'generic/platform=iOS' build`.
5. **Commit:** `feat(decks): RevenueCat deck_pro entitlement provider (offline-tolerant)`

> **Cost note (surface to Jackson):** Apple commission 15% (Small Business Program) → net ~$12.74 on $14.99; RevenueCat free under ~$2.5k/mo tracked, then ~1% (~$0.13/sub). Supabase Pro $25/mo is a hard prerequisite before customer data lands.

## Task E2 — Free 1-deck gate (pure decision function)

**Goal:** the monetization rule — free tier = 1 saved deck, Pro = unlimited (spec §6, §2). Pure function over `(savedDeckCount, isPro)` so it's trivially tested and offline-correct.

**Files:**
- Create `Packages/DeckKit/Sources/DeckKit/Capability/DeckSaveGate.swift` — `public enum DeckSaveGate { public static func canSaveNewDeck(savedDeckCount: Int, isPro: Bool, freeLimit: Int = 1) -> Bool }`. Lives in DeckKit so the shell + the editor both consult one rule. Editing/saving an *existing* deck is always allowed; only *creating a net-new* saved deck past the limit triggers the paywall.
- Modify `OPS Decks/` shell + `DecksAppDeckStore` call site: before persisting a brand-new deck, consult `DeckSaveGate.canSaveNewDeck(savedDeckCount: try await store.savedDeckCount(companyId:), isPro: entitlement.isPro)`; on `false`, present the paywall stub (full paywall UX is Phase 2).

**Steps:**
1. **Write failing test.** `Packages/DeckKit/Tests/DeckKitTests/Capability/DeckSaveGateTests.swift`:
   ```swift
   func testFreeUserBlockedAtSecondDeck() {
       XCTAssertTrue(DeckSaveGate.canSaveNewDeck(savedDeckCount: 0, isPro: false))
       XCTAssertFalse(DeckSaveGate.canSaveNewDeck(savedDeckCount: 1, isPro: false))
   }
   func testProUserUnlimited() {
       XCTAssertTrue(DeckSaveGate.canSaveNewDeck(savedDeckCount: 99, isPro: true))
   }
   ```
2. **Run (expected fail):** `swift test --package-path Packages/DeckKit --filter DeckSaveGateTests` → type missing.
3. **Implement:** `DeckSaveGate` + the shell consult.
4. **Run (expected pass):** filter passes.
5. **Commit:** `feat(decks): free 1-deck save gate (offline-tolerant, deck_pro unlocks unlimited)`

## Task E3 — `deck_subscriptions` table + RLS (Supabase migration)

**Goal:** the one net-new schema object (spec §5, §12.3), mirroring the RevenueCat entitlement server-side for web/analytics + the upgrade path. Kept OUT of `companies.subscription_*` to avoid OPS lockout entanglement. **Confirmed absent in prod 2026-06-24.**

**Files:**
- Create migration (apply via Supabase MCP `apply_migration`, name `create_deck_subscriptions`):
  ```sql
  create table public.deck_subscriptions (
    id uuid primary key default gen_random_uuid(),
    company_id uuid not null references public.companies(id) on delete cascade,
    status text not null,                       -- active | expired | in_grace | paused
    product_id text,                            -- store product identifier
    store text,                                 -- app_store | play_store | promotional
    rc_app_user_id text,                        -- RevenueCat app user id (== firebase sub)
    expires_at timestamptz,
    created_at timestamptz not null default now(),
    updated_at timestamptz
  );
  alter table public.deck_subscriptions enable row level security;
  -- read-only to the owning company (same resolver as deck_designs); writes are
  -- service-role only (the RevenueCat webhook), never the client.
  create policy deck_subscriptions_company_read on public.deck_subscriptions
    for select using (company_id = (select private.get_user_company_id()));
  create unique index deck_subscriptions_company_uidx on public.deck_subscriptions(company_id);
  ```
- Update the bible: `ops-software-bible/` (schema section for billing) — add `deck_subscriptions`.

**Steps:**
1. **Write failing test (DB-level verification, the "test" is the assertion query):** before migration, `SELECT to_regclass('public.deck_subscriptions')` → `null` (already confirmed). After migration, expect non-null + RLS enabled + the company-read policy present.
2. **Run (expected fail):** the pre-migration `to_regclass` is `null`.
3. **Implement:** `apply_migration` with the DDL above.
4. **Run (expected pass):** post-migration `SELECT to_regclass('public.deck_subscriptions')` non-null; `SELECT relrowsecurity FROM pg_class WHERE oid='public.deck_subscriptions'::regclass` → `true`; policy exists. Run `get_advisors` (security) — expect no new RLS warnings.
5. **Commit:** `feat(decks): deck_subscriptions mirror table + company-read RLS` (+ bible update as a separate commit).

## Task E4 — RevenueCat → ops-web webhook endpoint (mirror into `deck_subscriptions`)

**Goal:** RevenueCat posts entitlement events to ops-web; ops-web upserts the `deck_subscriptions` row (service-role) for web/cross-device visibility (spec §5).

**Files (ops-web — `/Users/jacksonsweet/Projects/OPS/OPS-Web/`):**
- Create `OPS-Web/app/api/webhooks/revenuecat/route.ts` — POST handler verifying the RevenueCat `Authorization` shared-secret header, mapping the RC `app_user_id` (== Firebase `sub`) → `users.firebase_uid` → `users.company_id`, then upserting `deck_subscriptions` (`status`/`product_id`/`store`/`expires_at`) with the **service-role** client (bypasses RLS for the write). Idempotent on `company_id`.
- Create `OPS-Web/lib/revenuecat/mapEvent.ts` — pure mapper `rcEvent → DeckSubscriptionUpsert` (status normalization: `INITIAL_PURCHASE`/`RENEWAL` → `active`, `EXPIRATION` → `expired`, `BILLING_ISSUE` → `in_grace`, etc.).
- Create `OPS-Web/__tests__/revenuecat-map.test.ts`.

**Steps:**
1. **Write failing test.** `revenuecat-map.test.ts` (Vitest/Jest per ops-web convention):
   ```ts
   it("maps RENEWAL to active with expires_at", () => {
     const out = mapEvent({ type: "RENEWAL", app_user_id: "fb_123",
       product_id: "deck_pro_monthly", store: "APP_STORE", expiration_at_ms: 1893456000000 });
     expect(out.status).toBe("active");
     expect(out.product_id).toBe("deck_pro_monthly");
     expect(out.expires_at).toBe("2030-01-01T00:00:00.000Z");
   });
   it("maps EXPIRATION to expired", () => {
     expect(mapEvent({ type: "EXPIRATION", app_user_id: "fb_1" }).status).toBe("expired");
   });
   ```
2. **Run (expected fail):** `cd OPS-Web && pnpm test revenuecat-map` (or the repo's runner) → `mapEvent` undefined.
3. **Implement:** the mapper + the route (route does the user→company lookup + service-role upsert).
4. **Run (expected pass):** test green. Manual: a RevenueCat sandbox event hits the endpoint and a `deck_subscriptions` row appears (integration step, flagged).
5. **Commit (in ops-web):** `feat(decks): RevenueCat webhook → deck_subscriptions mirror`

---

# GROUP F — Account deletion + upgrade-to-OPS continuity

## Task F1 — In-app account deletion (Apple requirement)

**Goal:** delete the company-of-one + its decks in-app (spec §9, Apple requirement). Pure deletion *plan* tested; execution behind the backend protocol.

**Files:**
- Create `OPS Decks/Account/AccountDeletionService.swift` — `struct AccountDeletionPlanner` produces a `DeletionPlan` (soft-delete all `deck_designs` for the company → soft-delete/anonymize the `users` row → mark `companies` row deleted IF it's a `subscription_plan='decks'` company with this user as sole admin; **refuse** to delete a company that has been upgraded to a full OPS company or has other members — return `.blocked(reason:)`). Execution via `AccountDeletionBackend` protocol (Supabase) + Firebase user delete + RevenueCat logout.
- Create the deletion confirmation UI in the standalone settings (minimal; copy via `ops-copywriter` skill).

**Steps:**
1. **Write failing test.** `OPSDecksTests/AccountDeletionPlannerTests.swift`:
   ```swift
   func testDeletesSoleAdminDecksCompany() {
       let plan = AccountDeletionPlanner().plan(
           company: CompanyRow(id: "co1", adminIds: ["u1"], subscriptionPlan: "decks", memberCount: 1),
           userId: "u1", deckIds: ["d1","d2"])
       XCTAssertEqual(plan.softDeleteDeckIds, ["d1","d2"])
       XCTAssertTrue(plan.deleteCompany)
   }
   func testBlocksDeletionOfUpgradedOpsCompany() {
       let plan = AccountDeletionPlanner().plan(
           company: CompanyRow(id: "co1", adminIds: ["u1"], subscriptionPlan: "pro", memberCount: 3),
           userId: "u1", deckIds: [])
       XCTAssertFalse(plan.deleteCompany)
       XCTAssertNotNil(plan.blockedReason)
   }
   ```
2. **Run (expected fail):** planner missing.
3. **Implement:** planner + value types + backend protocol + the confirm UI.
4. **Run (expected pass):** `-only-testing:OPSDecksTests/AccountDeletionPlannerTests`.
5. **Commit:** `feat(decks): in-app account deletion (decks company-of-one teardown, blocks upgraded companies)`

## Task F2 — Upgrade-to-OPS continuity scaffolding

**Goal:** Phase 1 only needs the *data/account continuity* real (spec §7): same Apple identity → same `users` → same `company` → every deck already present in full OPS; upgrading flips the company off `'decks'`. The offer UX is Phase 2; here we land the recognizer + the flip operation behind a tested plan.

**Files:**
- Create `Packages/DeckKit/Sources/DeckKit/Upgrade/UpgradeContinuity.swift` — pure `enum UpgradeContinuity` with `static func opsCompanyConversion(from company: CompanyOriginInfo) -> CompanyConversionPlan` (sets `subscription_plan` off `'decks'`, preserves all `deck_designs`, leaves company id/decks untouched) + `static func opsAppShouldRouteToUpgrade(for company: CompanyOriginInfo) -> Bool` (true when `subscription_plan == 'decks'` so the OPS app, if opened by a deck-only user pre-upgrade, routes to upgrade rather than treating it as a lapsed OPS trial — spec §5).
- Modify OPS app's company/subscription state read (where lockout is computed from `companies.subscription_status`/`trial_end_date`) to call `UpgradeContinuity.opsAppShouldRouteToUpgrade` and short-circuit lockout logic for a `'decks'` company (spec §12.3: "verify the OPS app tolerates `subscription_plan='decks'` companies"). Find the read site under `OPS/` company-status logic.

**Steps:**
1. **Write failing test.** `Packages/DeckKit/Tests/DeckKitTests/Upgrade/UpgradeContinuityTests.swift`:
   ```swift
   func testDecksCompanyRoutesToUpgradeNotLockout() {
       XCTAssertTrue(UpgradeContinuity.opsAppShouldRouteToUpgrade(for: .init(subscriptionPlan: "decks")))
       XCTAssertFalse(UpgradeContinuity.opsAppShouldRouteToUpgrade(for: .init(subscriptionPlan: "pro")))
   }
   func testConversionPreservesCompanyAndClearsDecksPlan() {
       let plan = UpgradeContinuity.opsCompanyConversion(from: .init(id: "co1", subscriptionPlan: "decks"))
       XCTAssertEqual(plan.companyId, "co1")          // same company — no migration
       XCTAssertNotEqual(plan.newSubscriptionPlan, "decks")
   }
   ```
2. **Run (expected fail):** `swift test --package-path Packages/DeckKit --filter UpgradeContinuityTests`.
3. **Implement:** the pure helper + the OPS-app lockout short-circuit.
4. **Run (expected pass):** filter passes; OPS device build green (the lockout change compiles).
5. **Commit:** `feat(decks): upgrade-to-OPS continuity (decks-plan recognizer + company conversion plan)`

---

# GROUP G — Estimate per-pattern waste-factor fix (no-engineering win #1)

## Task G1 — `WasteSettings` additive block

**Goal:** the P1 schema block (contract §2.3) fixing the zero-waste under-ordering bug. LIGHT exposes a single global %; per-pattern overrides are stored additively for FULL.

**Files:**
- Create `Packages/DeckKit/Sources/DeckKit/Models/WasteSettings.swift` — `public struct WasteSettings: Codable, Equatable` with `defaultWastePercent: Double = 10.0`, `perPatternWastePercent: [String: Double] = [:]`, + defensive `init(from:)` (`decodeIfPresent` + defaults, the §2.1 pattern).
- Modify `Packages/DeckKit/Sources/DeckKit/Models/DeckGeometry.swift` `DeckDrawingData` — add `public var wasteSettings: WasteSettings? = nil` + `CodingKeys` + `decodeIfPresent`.

**Steps:**
1. **Write failing test.** `Packages/DeckKit/Tests/DeckKitTests/Schema/WasteSettingsRoundTripTests.swift`:
   ```swift
   func testWasteSettingsRoundTrip() {
       var d = DeckDrawingData()
       d.wasteSettings = WasteSettings(defaultWastePercent: 15, perPatternWastePercent: ["diagonal": 18])
       let back = DeckDrawingData.fromJSON(d.toJSON())!
       XCTAssertEqual(back.wasteSettings?.defaultWastePercent, 15)
       XCTAssertEqual(back.wasteSettings?.perPatternWastePercent["diagonal"], 18)
   }
   func testLegacyJSONDecodesWithNilWasteSettings() {
       XCTAssertNil(DeckDrawingData.fromJSON("{\"vertices\":[]}")!.wasteSettings)
   }
   ```
2. **Run (expected fail):** `--filter WasteSettingsRoundTripTests` → property missing.
3. **Implement:** the struct + the field.
4. **Run (expected pass):** filter passes; round-trip preservation suite still green.
5. **Commit:** `feat(decks): WasteSettings drawing_data block (P1 schema)`

## Task G2 — Thread waste factor through area takeoff in `EstimateGeneratorService`

**Goal:** apply the waste % to area-based (`sq ft`) takeoff so the estimate stops under-ordering (roadmap §0; `EstimateGeneratorService.swift:185-194`, the per-surface path at lines 540/557, and the legacy footprint path). A zero-default would be wrong — default 10% when no setting present.

**Files:**
- Modify `Packages/DeckKit/Sources/DeckKit/Engine/EstimateGeneratorService.swift` — thread `wasteSettings` (resolved from `drawingData.wasteSettings ?? WasteSettings()`) into `generateLineItems` → `generateSingleLevelLineItems` → `perSurfaceLineItems` and the legacy footprint branch. For each area item, multiply the billed `quantity` (sq ft) by `(1 + wastePercent/100)`, where `wastePercent` = per-pattern override (when a surface carries a decking pattern — P6 wires the pattern key; in P1 use the surface's `boardMaterial`/default) else `defaultWastePercent`. Round to the existing 2-dp convention. Linear/each/set items are NOT waste-adjusted (waste is an area concept here). Add a `wasteFactor`-gated path so a LIGHT build with the `.wasteFactor` capability (both tiers have it) applies the global %.
- Keep the `GeneratedLineItem` shape unchanged (don't break `EstimateAcceptanceIntegrationTests`); the only change is the `quantity` value for area rows.

**Steps:**
1. **Write failing test.** Extend `Packages/DeckKit/Tests/DeckKitTests/EstimateGeneratorServiceTests.swift` (the moved file):
   ```swift
   func testAreaItemAppliesDefaultTenPercentWaste() {
       let data = makeRectangleDeck(withVinyl: true)   // no wasteSettings → default 10%
       let baselineArea = EstimateGeneratorService.calculateAreaSqFt(drawingData: data)
       let item = EstimateGeneratorService.generateLineItems(from: data).first { $0.category == "Surface" }!
       XCTAssertEqual(item.quantity, (baselineArea * 1.10 * 100).rounded() / 100, accuracy: 0.05)
   }
   func testPerPatternOverrideBeatsDefault() {
       var data = makeRectangleDeck(withVinyl: true)
       data.wasteSettings = WasteSettings(defaultWastePercent: 10, perPatternWastePercent: ["composite": 20])
       // surface boardMaterial defaults to "composite" → 20% applies
       let item = EstimateGeneratorService.generateLineItems(from: data).first { $0.category == "Surface" }!
       let baseline = EstimateGeneratorService.calculateAreaSqFt(drawingData: data)
       XCTAssertEqual(item.quantity, (baseline * 1.20 * 100).rounded() / 100, accuracy: 0.05)
   }
   func testLinearItemsAreNotWasteAdjusted() { /* railing linear ft unchanged */ }
   ```
2. **Run (expected fail):** `--filter EstimateGeneratorServiceTests/testAreaItemAppliesDefaultTenPercentWaste` → area equals baseline (no waste applied) → fails.
3. **Implement:** thread the waste factor through the area paths only.
4. **Run (expected pass):** the new tests pass AND the full moved suite + `EstimateAcceptanceIntegrationTests` stay green (run `xcodebuild test -scheme OPS … -only-testing:OPSTests/EstimateAcceptanceIntegrationTests` — if that test asserts exact area quantities, update its expectations to the +10% values and note the correctness fix in the commit).
5. **Commit:** `fix(decks): apply per-pattern waste factor to area takeoff (stops material under-ordering)`

---

# GROUP H — Brand-neutral material catalog data model (no-engineering win #2)

## Task H1 — `DeckMaterialCatalog` brand-neutral model

**Goal:** the catalog data model (roadmap §2.7 row 1; contract §7 P1 row "brand-neutral catalog model") — family/profile/lengths/coverage/fastener/finish — generalizing today's `BuiltInMaterial` (id/name/subtitle/icon only) without breaking it. Additive: never remove a shipped `BuiltInMaterial.id` (its own doc comment mandates this).

**Files:**
- Create `Packages/DeckKit/Sources/DeckKit/Models/DeckMaterialCatalog.swift`:
  ```swift
  public struct DeckMaterial: Codable, Equatable, Identifiable, Sendable {
      public let id: String                 // stable; maps from BuiltInMaterial.id where applicable
      public var family: MaterialFamily     // decking | railing | fastener | finish | substrate | cladding
      public var profile: String?           // "1x6 grooved", "5/4x6 square"
      public var availableLengthsFeet: [Double]   // [12,16,20] — feeds board-nesting later
      public var coveragePerUnit: Double?         // sq ft per unit (boards) / lin ft (railing)
      public var fastenerSystem: String?          // "hidden_clip" | "face_screw" (string for additivity)
      public var finish: String?                  // "stain" | "sealant" | "factory"
      public var displayName: String
      // defensive init(from:) + decodeIfPresent defaults
  }
  public enum MaterialFamily: String, Codable, CaseIterable, Sendable {
      case decking, railing, fastener, finish, substrate, cladding
  }
  ```
- Add a bridging static `DeckMaterial.from(builtIn:)` that maps each existing `BuiltInMaterial` (linear + area standards) to a `DeckMaterial` so the picker can present the richer model while the legacy ids round-trip. Do **not** alter `BuiltInMaterial` itself.

**Steps:**
1. **Write failing test.** `Packages/DeckKit/Tests/DeckKitTests/Models/DeckMaterialCatalogTests.swift`:
   ```swift
   func testCompositeDeckingMapsFromBuiltIn() {
       let m = DeckMaterial.from(builtIn: BuiltInMaterial.areaStandards.first { $0.id == "std.decking.composite" }!)
       XCTAssertEqual(m.id, "std.decking.composite")
       XCTAssertEqual(m.family, .decking)
       XCTAssertEqual(m.displayName, "Composite Decking")
   }
   func testRoundTripPreservesLengthsAndFastener() {
       let m = DeckMaterial(id: "x", family: .decking, profile: "1x6",
           availableLengthsFeet: [12,16,20], coveragePerUnit: 5.5,
           fastenerSystem: "hidden_clip", finish: "factory", displayName: "X")
       let back = try! JSONDecoder().decode(DeckMaterial.self,
           from: JSONEncoder().encode(m))
       XCTAssertEqual(back, m)
   }
   func testLegacyDecodeFillsDefaults() { /* {"id":"x","family":"decking","displayName":"X"} decodes */ }
   ```
2. **Run (expected fail):** `--filter DeckMaterialCatalogTests` → types missing.
3. **Implement:** the model + the bridge.
4. **Run (expected pass):** filter passes.
5. **Commit:** `feat(decks): brand-neutral DeckMaterial catalog model (generalizes BuiltInMaterial)`

---

# GROUP I — Client proposal + upgraded render (early-revenue deliverable)

## Task I1 — `ClientProposalBuilder` (priced, branded proposal content)

**Goal:** the client proposal deliverable (roadmap §2.8 row "Client proposal"; spec §10 "client proposal + render for early revenue"). A pure builder turning a deck + estimate into branded, priced proposal content; the PDF render reuses `DeckShareRenderer` (the LIGHT marketing artifact — roadmap §6: do NOT extend it into the permit path).

**Files:**
- Create `Packages/DeckKit/Sources/DeckKit/Rendering/ClientProposalBuilder.swift` — `public enum ClientProposalBuilder { public static func build(deck: DeckDesign, lineItems: [EstimateGeneratorService.GeneratedLineItem], branding: ProposalBranding) -> ClientProposal }`. `ClientProposal` carries title, grouped priced sections (by category), subtotal/total (tabular-formatted per CLAUDE.md numbers rule), and the disclaimer-free LIGHT framing (no code/structural claims — this is a sales artifact). `ProposalBranding { companyName, logoURL?, accentHex }`.
- Copy (titles, section labels, CTA) via the `ops-copywriter` skill (terse/tactical voice).

**Steps:**
1. **Write failing test.** `Packages/DeckKit/Tests/DeckKitTests/Rendering/ClientProposalBuilderTests.swift`:
   ```swift
   func testProposalTotalsSumLineItems() {
       let items = [GeneratedLineItem(name:"Composite Decking", description:nil, type:.material,
           quantity: 100, unit:"sq ft", unitPrice: 8.5, productId:nil, taskTypeId:nil,
           category:"Surface", sortOrder:0, isOptional:false)]
       let p = ClientProposalBuilder.build(deck: DeckDesign(companyId:"c"), lineItems: items,
           branding: .init(companyName:"Acme", logoURL:nil, accentHex:"#3F5A73"))
       XCTAssertEqual(p.total, 850.0, accuracy: 0.001)
       XCTAssertEqual(p.sections.first?.category, "Surface")
   }
   func testProposalCarriesNoCodeOrStructuralClaim() {
       // LIGHT sales artifact — must never contain compliance language.
       let p = ClientProposalBuilder.build(deck: DeckDesign(companyId:"c"), lineItems: [], branding: .init(companyName:"Acme", logoURL:nil, accentHex:"#3F5A73"))
       let text = p.allText.lowercased()
       for banned in ["code-compliant","safe","guaranteed","will pass","engineer-stamped"] {
           XCTAssertFalse(text.contains(banned))
       }
   }
   ```
2. **Run (expected fail):** `--filter ClientProposalBuilderTests` → builder missing.
3. **Implement:** the builder + value types.
4. **Run (expected pass):** filter passes.
5. **Commit:** `feat(decks): client proposal builder (priced, branded LIGHT sales artifact)`

## Task I2 — Upgraded client render hook

**Goal:** a "sell-grade" hero render for the proposal (roadmap §2.8 "Upgraded client 3D render"). Photoreal is explicitly deferred (roadmap §8, spec §10 OOS), so P1 = a polished composite of the existing `DeckShareRenderer` PNG + the proposal header, reusing `DeckSceneBuilder`/`DeckScene3DView` for the 3D shot (memory `deck-tab-3d-unified-renderer`: all decks render via `DeckSceneBuilder`).

**Files:**
- Create `Packages/DeckKit/Sources/DeckKit/Rendering/ClientRenderComposer.swift` — `public enum ClientRenderComposer { public static func composeHero(sceneImage: UIImage, proposal: ClientProposal, branding: ProposalBranding) -> UIImage }` (Core Graphics composite; deterministic given inputs → snapshot-testable).
- Tests via the `ImageRenderer → XCTAttachment` snapshot harness (memory `ops-ios-swiftui-snapshot-harness`), mirroring the existing `DeckSceneSnapshotTests` pattern.

**Steps:**
1. **Write failing test.** `Packages/DeckKit/Tests/DeckKitTests/Rendering/ClientRenderComposerTests.swift` — assert output non-nil + expected pixel dimensions + attach for visual QA:
   ```swift
   func testComposeHeroProducesExpectedSize() {
       let scene = UIImage(/* 1x1 placeholder */)
       let img = ClientRenderComposer.composeHero(sceneImage: scene,
           proposal: stubProposal, branding: stubBranding)
       XCTAssertEqual(img.size.width, 1200)   // hero canvas width
       add(XCTAttachment(image: img))         // human visual QA
   }
   ```
2. **Run (expected fail):** composer missing.
3. **Implement:** the Core Graphics composer.
4. **Run (expected pass):** filter passes (interactive visual QA stays a human step — flag for Jackson).
5. **Commit:** `feat(decks): upgraded client hero render composer (reuses DeckShareRenderer + 3D scene)`

---

# GROUP J — Minimal library/create/open shell

## Task J1 — Standalone deck library + create/open shell

**Goal:** the *minimum* surface for the standalone to function (spec §10, §13): list the company-of-one's decks (via `DeckStore.listDecks` + `deckChanges` repaint), create a new deck (gated by `DeckSaveGate`), open into `DeckBuilderView`. The refined library/onboarding/paywall UX is Phase 2.

**Files:**
- Create `OPS Decks/Library/DeckLibraryViewModel.swift` — `@MainActor @Observable`, holds `decks: [DeckDesign]`, subscribes to `deckStore.deckChanges(companyId:)`, exposes `createDeck()` (consults `DeckSaveGate` + entitlement → returns a new `DeckDesign` or signals paywall), `open(_:)`.
- Create `OPS Decks/Library/DeckLibraryView.swift` — list (OPSStyle tokens; numbers tabular per CLAUDE.md; empty state `—`/copy via `ops-copywriter`), a create FAB, navigation into `DeckBuilderView` with the DecksApp seams injected.
- Create `OPS Decks/Library/PaywallStubView.swift` — minimal "Upgrade to OPS Decks Pro" surface shown when the gate blocks (full paywall is Phase 2).
- Wire `OPSDecksApp` root to `DeckLibraryView` (post-auth) / a no-account design-first entry (spec §8: design before any account; save prompts Sign in with Apple).

**Steps:**
1. **Write failing test.** `OPSDecksTests/DeckLibraryViewModelTests.swift` (VM logic, store mocked):
   ```swift
   func testCreateDeckBlockedForFreeUserAtLimit() async {
       let vm = DeckLibraryViewModel(store: MockStore(count: 1),
           entitlement: FakeEntitlementProvider(isPro: false), companyId: "c1")
       let result = await vm.createDeck()
       if case .paywall = result {} else { XCTFail("expected paywall") }
   }
   func testCreateDeckAllowedForPro() async {
       let vm = DeckLibraryViewModel(store: MockStore(count: 5),
           entitlement: FakeEntitlementProvider(isPro: true), companyId: "c1")
       if case .created = await vm.createDeck() {} else { XCTFail("expected created") }
   }
   func testDeckChangesRepaintsList() async { /* push via stream → vm.decks updates */ }
   ```
2. **Run (expected fail):** VM missing.
3. **Implement:** the VM + views + app root wiring.
4. **Run (expected pass):** `-only-testing:OPSDecksTests/DeckLibraryViewModelTests`. Device build: `xcodebuild -scheme 'OPS Decks' -destination 'generic/platform=iOS' build`.
5. **Commit:** `feat(decks): minimal deck library + create/open shell (gate-aware)`

## Task J2 — Full-suite verification + bible update

**Goal:** end-to-end green + docs current (CLAUDE.md: keep the bible updated in the same session).

**Files:**
- Update `ops-software-bible/` — add an "OPS Decks (standalone)" section: the two packages, the seams, the company-of-one model, `deck_subscriptions`, the capability flags, the LIGHT/FULL split, the P1 schema blocks (`schemaVersion`, `WasteSettings`, `unknownBlocks`, and `PermitMeta` — P1 ships the minimal `PermitMeta { jurisdictionId, codeEdition, disclaimerAcknowledgedAt }`, completed in P7; no longer a stub). Reference the contract.

**Steps:**
1. **Run both package suites + both app schemes:**
   ```
   swift test --package-path Packages/OPSDesignKit
   swift test --package-path Packages/DeckKit 2>&1 | tee /tmp/dk.log; grep -E "Test Suite 'All tests'|error:" /tmp/dk.log
   xcodebuild test -scheme OPS -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' 2>&1 | tee /tmp/ops.log; grep -E 'TEST (SUCCEEDED|FAILED)' /tmp/ops.log
   xcodebuild test -scheme 'OPS Decks' -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' 2>&1 | tee /tmp/decks.log; grep -E 'TEST (SUCCEEDED|FAILED)' /tmp/decks.log
   xcodebuild -scheme OPS -destination 'generic/platform=iOS' build 2>&1 | grep -E 'BUILD (SUCCEEDED|FAILED)'
   xcodebuild -scheme 'OPS Decks' -destination 'generic/platform=iOS' build 2>&1 | grep -E 'BUILD (SUCCEEDED|FAILED)'
   ```
   (Grep for `SUCCEEDED` — never trust the background exit code, memory `xcodebuild-exit-code-masking`. `OPSTests` env launch failures may be pre-existing sim denials, not your change — confirm vs a stashed baseline, memory `ios-opstests-env-launch-failures`.)
2. **Implement:** bible update.
3. **Commit:** `docs(bible): document OPS Decks Phase 1 foundation (packages, seams, company-of-one, billing, schema)`

---

## Pre-launch gates (NOT code tasks — surface to Jackson)

1. **Supabase Pro ($25/mo)** before any standalone customer data lands (free tier = no backups; spec §11/§12.2). HARD gate.
2. **Apple/Firebase portal:** App Store Connect record + `co.opsapp.ops.decks` bundle + profiles + `GoogleService-Info.plist` + Sign in with Apple service id + subscription products configured + wired to RevenueCat (spec §9).
3. **ops-web endpoint authorization** for `subscription_plan='decks'` companies (spec §12.4) — verify presign/OCR endpoints accept a deck-only company's Firebase token.
4. **RevenueCat dashboard:** `deck_pro` entitlement + monthly/annual products + the webhook pointed at the ops-web endpoint (E4) with the shared secret.
5. **Interactive visual QA** (library, proposal render, deck editor in the standalone) — human step (memory: computer-use QA needs Jackson present).
6. **Demand-depth pass** (r/Decks + deck FB groups) recommended before heavy Phase 2 (spec §12.7).

## Risks / notes carried from memory

- **Parallel-session hazard on `DeckBuilder/`** — the carve-out moves 73 files; sibling sessions / the in-flight deck-overhaul Drops target the same tree. Land Group A as one coherent branch; check `git worktree list` + `lsof` before moving. Never `git add -A`; stage by name.
- **Inbound merge fragility** — `OPSDeckStore.deckChanges` must post a repaint signal (InboundChangeSignal pattern) or the library won't reflect inbound sync (memory `ios-scheduling-sync-integrity`); guard inbound merges with the updatedAt/needsSync recency check (memory `deck-sync-stale-overwrite-revert`) — the OPS path already has this; the standalone `DecksAppDeckStore` must replicate it.
- **Outbound field allowlist** — `deck_designs` writes filter against `DataActor.validDeckDesignColumns`; the new `version`/`drawing_data` writes are already covered, but verify no new column is silently dropped (memory `ios-outbound-field-allowlist-drift`).
- **CRLF churn** — preserve line endings on edited files (memory). **SourceKit lag** in fresh packages/worktrees — trust `xcodebuild` (memory).
