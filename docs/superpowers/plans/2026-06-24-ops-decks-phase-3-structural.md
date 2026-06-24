# OPS Decks — Phase 3 Implementation Plan: Structural Engineering (FULL)

**Date:** 2026-06-24
**Status:** Implementation plan (authored against the LOCKED architecture contract)
**Authoritative contract:** `docs/superpowers/plans/2026-06-24-ops-decks-architecture-contract.md` — every type/signature/schema block below is adopted **verbatim** from it.
**Companions (read first):** `docs/superpowers/specs/2026-06-24-ops-decks-feature-roadmap.md` (§2.1, §3, §4, §7), `docs/superpowers/specs/2026-06-24-ops-decks-standalone-app-design.md` (foundation/carve-out).

> **HEADER NOTE — phase-start refinement.** Bite-sized TDD steps with literal, copy-pasteable Swift are finalized at phase start **once predecessors (P1 + P2) exist**. P3 builds directly on P1's `DeckKit` package, seam protocols, `CodePackageLoader` stub, `unknownBlocks` passthrough, `WasteSettings`, and minimal `PermitMeta`; and on P2's `FramingPlan` block + auto-framing engine (`FramingMember.sizing == nil`). Where P1/P2 types are consumed, this plan uses their **contract-fixed** names/shapes but does **not** invent member-level internals beyond what the contract pins. Concrete `init(from:)` bodies, exact `SpanTable.lookup` argument order, and the production package JSON keys are locked against the real predecessor code at the start of P3, then driven by the TEST STRATEGY blocks below in strict red→green→refactor order.

---

## Goal

Light up **FULL-tier structural engineering** for OPS Decks: turn the *plausible-but-unengineered* frame that P2 produces (`FramingMember.sizing == nil`) into a **code-checked, table-driven, offline, jurisdiction-aware** engineered frame. Concretely, P3 delivers:

1. **Code-rule package format + a real `CodePackageLoader`** — versioned, jurisdiction-keyed, Supabase-stored / ops-web-delivered, offline-first cached. Engines consume a loaded `CodePackage` value; the loader is the only thing that touches I/O. Replaces P1's no-op stub.
2. **Jurisdiction selection UI** — user picks country + province/state + adopted edition; persisted into `DeckDrawingData.permitMeta.jurisdictionId` / `.codeEdition` (the P1-minimal `PermitMeta` block). Drives which package every engine evaluates.
3. **`StructuralSizingEngine`** — pure, table-driven engines: **joist span** (allowable span + deflection), **beam sizing + post-spacing back-solve**, **post sizing + height limit**, **per-column/post tributary LOAD calc**, **cantilever** (2021 adjacent-span limits), and a `sizeAll(...)` convenience that fills every unlocked `FramingMember.sizing`.
4. **Manual framing editor** (select / size / move / lock) — RedX parity. Locked members are excluded from re-derive; the editor never silently restructures the frame.

The product line P3 must hold (roadmap §1, §7): **LIGHT visualizes + prices; the instant the app asserts a member size, span, or load number, that is FULL** and must obey the §6 compliance liability rules — objective-negative claims only, disclaimer-gated, out-of-envelope → hard-stop to a licensed engineer, assumptions surfaced, code-edition stamped.

## Architecture

P3 adds **zero new top-level `drawing_data` blocks** (contract §2.2 — schema ver 3 is "no new block"). It **fills** `FramingMember.sizing` (the `MemberSizingResult` field P2 declared as `nil`) and **reads** `PermitMeta.jurisdictionId`. The version bump to `3` gates the migration/backfill path, never rendering.

Everything new lives in `DeckKit/Sources/DeckKit/Compliance/` (the NEW submodule introduced for P3–P7) and `DeckKit/Sources/DeckKit/Engine/`:

```
DeckKit/Sources/DeckKit/
├─ Engine/
│   └─ StructuralSizingEngine.swift     (NEW) pure sizing/load/cantilever engine
├─ Engine/
│   └─ EngineEnvelope.swift             (P2-owned; CONSUMED here — EngineOutcome /
│                                        EngineCitation / EngineAssumptions / SizedMember /
│                                        MemberSizingResult; P3 does NOT re-declare)
├─ Compliance/                          (NEW submodule, grows P3→P7)
│   ├─ CodePackage.swift                (NEW) the data-package model + lookup structs
│   └─ CodePackageLoaderLive.swift      (NEW) real loader: catalog + download + offline cache;
│                                        consumes the P1 CodePackageLoader protocol +
│                                        CodePackageLoaderError; consumes the P1-owned
│                                        JurisdictionDescriptor (no re-declare)
├─ Capability/
│   └─ DeckCapabilities.swift           (MODIFY by P3) — .structuralSizing/.loadCalc already
│                                        declared in contract; P3 is first consumer
├─ Models/
│   └─ DeckGeometry.swift               (MODIFY) bump schemaVersion handling to 3;
│                                        FramingMember.sizing already declared by P2
└─ Views/
    ├─ Jurisdiction/
    │   ├─ JurisdictionPickerView.swift (NEW) country/state/edition selection + download
    │   └─ CodePackageStatusBadge.swift (NEW) "code data current to [date]" badge
    └─ Framing/
        ├─ FramingEditorView.swift      (NEW) manual select/size/move/lock surface
        ├─ MemberSizingInspector.swift  (NEW) per-member result + assumptions + citation
        └─ FramingSizingViewModel.swift (NEW) orchestrates sizeAll + editor state
```

App-target wiring (both apps depend on DeckKit; **only OPS Decks** supplies `.full` capabilities — OPS supplies `.light`, so these surfaces never render in OPS):

```
OPS Decks/Seams/
└─ DecksAppCodePackageLoader.swift      (NEW) conforms CodePackageLoader; ops-web + cache
OPS/Seams/
└─ OPSCodePackageLoader.swift           (NEW) same impl shape; never invoked under .light
```

Backend (Supabase, company-of-one on the existing project): a **new public table `code_packages`** + a Supabase Storage bucket (`code-packages`) holding the versioned JSON blobs, fronted by an **ops-web delivery endpoint** (`/api/code-packages/catalog`, `/api/code-packages/:jurisdictionId`). Anonymous-read RLS so the catalog is reachable pre-auth and offline-cacheable (mirrors the app-messages anon-read kill-switch pattern in memory).

## Tech Stack

- **Swift / SwiftData / SwiftUI**, iOS 26.x; `DeckKit` + `OPSDesignKit` Swift packages (P1 carve-out).
- **Pure value engines** (`enum` namespace + `static func`), no I/O, no `ModelContext`, no singletons — the `StairCalculator` precedent (`OPS/DeckBuilder/Engine/StairCalculator.swift`).
- **Codable** additive blob growth inside `DeckDrawingData` (`OPS/DeckBuilder/Models/DeckGeometry.swift`), `decodeIfPresent` + default everywhere; `unknownBlocks` passthrough (P1) preserves blocks a build can't parse.
- **Supabase** (`ijeekuhbatykdomumfjx`, FREE tier — watch the 500MB ceiling; packages are small JSON) + Supabase Storage + ops-web delivery; offline file cache in `DeckKit`.
- **Code rules:** IRC 2021 R507 (decks), AWC **DCA6-12** span/beam/footing tables, IRC R311.7 (stairs, already encoded), R312 (guards), R401.4 (presumptive soil); **NBC / BCBC 2024 Part 9.12** (Canada, kPa). Tables ingested **verbatim as data**, never transcribed cell-by-cell into UI (contract §0.5, §6.8).
- **Build verification:** device `xcodebuild -scheme OPS -destination 'generic/platform=iOS'`; tests on `-destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5'` (`build-for-testing` to verify compile, `test` to run). Copy `OPS/Utilities/Secrets.xcconfig` into any worktree first. Grep logs for `BUILD SUCCEEDED` / `TEST SUCCEEDED` (the trailing-echo exit-code gotcha).
- **Styling:** `OPSStyle` / `OPSDesignKit` tokens only — no hardcoded color/spacing/radius/font; numbers in JetBrains Mono, tabular, formatted, empty state `—`.

---

## Contract types this phase OWNS (defined here, consumed by later phases)

Adopted **verbatim** from the contract — restated so the TDD steps and later phases have one local index. (Sub-table struct shapes that the contract leaves as `//` comments are pinned below to the minimum the engines require; their internal field order is finalized at phase start against the real DCA6/BCBC tables.)

- **`StructuralSizingEngine`** (contract §3.1): `joistSpan(...)`, `beamSizing(...)`, `postSizing(...)`, `tributaryLoads(...) -> [PostReaction]`, `cantilever(...)`, `sizeAll(...) -> FramingPlan`; P3-owned result structs `JoistSpanResult`, `BeamSizingResult`, `PostSizingResult`, `CantileverResult`, `PostReaction`. (`MemberSizingResult`/`SizedMember` + the envelope are **P2-owned** — see below.)
- **`CodePackage`** (contract §3.4): `jurisdictionId, edition, publishedDate, unitSystem: PackageUnits, joistSpanTable: SpanTable, beamSpanTable: SpanTable, postHeightTable: PostTable, footingTable: FootingTable, cantileverRules: CantileverRules, guardRules, stairRules, ledgerRules, presumptiveSoilPSF, envelopeLimits: EnvelopeLimits`; `PackageUnits { imperial, metric }`; lookup structs `SpanTable/PostTable/FootingTable/CantileverRules/EnvelopeLimits`.
- **`CodePackageLoaderLive`** — production conformer of the P1 `CodePackageLoader` protocol (contract §1.3), replacing the no-op stub. Consumes the P1-owned `CodePackageLoaderError` (no re-declare).

### Types this phase CONSUMES (owned earlier; do NOT re-declare here)

- **Engine envelope** (`EngineOutcome<T>`, `EngineCitation`, `EngineAssumptions`, `SizedMember`, `MemberSizingResult`) — **P2-owned** (`EngineEnvelope.swift`, contract §3 "Phase ownership" note). P2 is the first consumer via `FramingMember.sizing`; P3 engines reuse them verbatim and FILL `sizing`. P3 must NOT re-declare them.
- **`JurisdictionDescriptor`** — **P1-owned** (`CodePackageLoader.swift`, contract §1.3). P1 ships the full superset shape `{ id, displayName, country, region, availableEditions: [String], latestEdition, latestPublishedDate, isDownloaded }`; `availableJurisdictions()` returns it and the picker consumes it. P3 does NOT re-declare it.
- **`CodePackageLoaderError`** — **P1-owned** (`CodePackageLoader.swift`); `CodePackageLoaderLive` throws/returns it (e.g. cold-miss offline → `.offline`/`.notDownloaded`).

> `FootingTable` / `guardRules` / `stairRules` / `ledgerRules` live in `CodePackage` from P3 (the package is one self-describing artifact) but are **consumed** in P4 (footings) and P7 (compliance). P3 ships them as data + decodes them; P3 engines only read `joistSpanTable`, `beamSpanTable`, `postHeightTable`, `cantileverRules`, `presumptiveSoilPSF`, `envelopeLimits`. This is deliberate: ship the whole package once, light up cells per phase.

---

## File Structure

### New files (DeckKit)

| File | Responsibility (one line) |
|---|---|
| `Compliance/CodePackage.swift` | The code-rule **data** package + all lookup structs (`SpanTable`, `PostTable`, `FootingTable`, `CantileverRules`, `GuardRules`, `StairRules`, `LedgerRules`, `EnvelopeLimits`, `PackageUnits`) + their pure `lookup(...)` helpers. |
| `Compliance/CodePackageCache.swift` | On-device package + catalog file cache (offline-first read, atomic write, edition-versioned filenames). |
| `Compliance/CodePackageLoaderLive.swift` | Real `CodePackageLoader`: ops-web catalog/download via injected fetcher, cache-first, `refreshCatalog`, `activePackage(for:)`. |
| `Engine/StructuralSizingEngine.swift` | Pure joist/beam/post/tributary/cantilever sizing + `sizeAll(...)`; consumes `CodePackage`, returns `EngineOutcome`. |
| `Views/Jurisdiction/JurisdictionPickerView.swift` | Country → region → edition selection sheet; triggers download; writes `PermitMeta.jurisdictionId`/`.codeEdition`. |
| `Views/Jurisdiction/CodePackageStatusBadge.swift` | Compact "code data current to [date]" badge + re-download affordance. |
| `Views/Framing/FramingEditorView.swift` | Manual framing editor canvas overlay: select / resize / move / lock members. |
| `Views/Framing/MemberSizingInspector.swift` | Per-member inspector: size, utilization, limiting check, cited section, surfaced assumptions, out-of-envelope hard-stop. |
| `Views/Framing/FramingSizingViewModel.swift` | Orchestrates `sizeAll`, applies/reverts edits, owns lock state, debounces re-derive. |

> **Consumed, NOT created by P3:** `Engine/EngineEnvelope.swift` (P2-owned — `EngineOutcome`/`EngineCitation`/`EngineAssumptions`/`SizedMember`/`MemberSizingResult`); `Seams/CodePackageLoader.swift` (P1-owned — the protocol + `JurisdictionDescriptor` superset + `CodePackageLoaderError`). P3 imports and uses these; it does not declare them.

### New files (app targets)

| File | Responsibility |
|---|---|
| `OPS Decks/Seams/DecksAppCodePackageLoader.swift` | OPS Decks conformer: ops-web endpoints + on-device cache; provides `.full` jurisdictions. |
| `OPS/Seams/OPSCodePackageLoader.swift` | OPS conformer (same shape); under `.light` capabilities it is never invoked (catalog returns whatever; surfaces hidden). |

### New files (ops-web + Supabase)

| File / object | Responsibility |
|---|---|
| `code_packages` table (migration) | Catalog metadata: `jurisdiction_id, edition, published_date, storage_path, checksum, unit_system, is_latest`. |
| `code-packages` Storage bucket | Versioned JSON blobs (`US-IRC/IRC-2021-DCA6-12.json`, `CA-BC/BCBC-2024-part9.json`, …). |
| `OPS-Web/app/api/code-packages/catalog/route.ts` | Returns the available-jurisdictions catalog (anon-readable). |
| `OPS-Web/app/api/code-packages/[jurisdictionId]/route.ts` | Returns a signed/public download URL (or the blob) for a jurisdiction+edition. |
| ops-web `/admin/code-packages` (stub) | Internal upload/version surface for new editions (out of App Store release loop). |

### Test files (DeckKit test target)

| File | Responsibility |
|---|---|
| `Tests/DeckKitTests/CodePackageTests.swift` | Package decode + `lookup(...)` correctness against checked-in fixtures. |
| `Tests/DeckKitTests/CodePackageLoaderLiveTests.swift` | Cache-first, download-on-miss, refresh, offline-degradation, `activePackage(for:)`. |
| `Tests/DeckKitTests/StructuralSizingEngineTests.swift` | Joist/beam/post/tributary/cantilever against hand-computed expected values + cited section. |
| `Tests/DeckKitTests/StructuralSizingEnvelopeTests.swift` | Out-of-envelope hard-stop coverage (every `EnvelopeLimits` threshold). |
| `Tests/DeckKitTests/FramingSizeAllTests.swift` | `sizeAll` writes `sizing` only on unlocked members; round-trips; `FramingSource` transitions. |
| `Tests/DeckKitTests/DrawingDataV3RoundTripTests.swift` | Schema-ver-3 round-trip + LIGHT-preserves-sizing + malformed-sub-block decodes to nil. |
| `Tests/DeckKitTests/Fixtures/` | `IRC-2021-DCA6-12.fixture.json`, `BCBC-2024-part9.fixture.json` — known subset of real cells. |

---

## Tasks

Ordered for strict dependency flow: **envelope → package data → loader → engine → editor → jurisdiction UI → app wiring → backend → compliance/QA**. Each task is TDD (red→green→refactor); the test target compiles + runs on the simulator destination, device build verifies separately.

---

### Task 1 — P3 engine result structs (build on P2's `EngineEnvelope`)

**Why first:** every engine in P3 (and P4/P7) returns `EngineOutcome<T>`. The envelope itself — `EngineOutcome<T>`, `EngineCitation`, `EngineAssumptions`, `SizedMember`, `MemberSizingResult` — is **P2-owned** (`Engine/EngineEnvelope.swift`, contract §3 "Phase ownership" note; P2 is the first consumer via `FramingMember.sizing`). **P3 does NOT create or re-declare the envelope.** This task instead declares the **P3-specific result payloads** the `StructuralSizingEngine` (Task 4) returns inside that envelope, and locks an envelope round-trip regression so later phases can't break it.

**Interface (P3-owned result structs, verbatim contract §3.1):**

```swift
public struct JoistSpanResult: Codable, Equatable { public var allowableSpanFeet: Double; public var deflectionRatio: String }
public struct BeamSizingResult: Codable, Equatable { public var size: LumberSize; public var plyCount: Int; public var maxPostSpacingFeet: Double }
public struct PostSizingResult: Codable, Equatable { public var size: LumberSize; public var maxHeightFeet: Double }
public struct CantileverResult: Codable, Equatable { public var allowedFeet: Double; public var ok: Bool }
public struct PostReaction: Codable, Equatable { public var footingOrPostId: String; public var reactionLb: Double; public var tributaryAreaSqFt: Double }
```

> The envelope these wrap is P2's, restated here only as a consumed reference (do NOT define):
> `EngineOutcome<T> { case ok(value:citation:assumptions:), case outOfEnvelope(reason:citation:) }`, `EngineCitation { limitingCheck, codeSection, packageEdition }`, `EngineAssumptions { liveLoadPSF, deadLoadPSF, snowLoadPSF?, species, grade, soilBearingPSF?, packageEdition }`, `SizedMember`, `MemberSizingResult { outcome: EngineOutcome<SizedMember> }`.

These P3 structs can be declared alongside `StructuralSizingEngine` (Task 4) or in a small `Engine/StructuralResults.swift` — they are not the envelope.

**TEST STRATEGY** (`EngineEnvelopeTests` — regression-locks the CONSUMED P2 envelope + the new P3 payloads):
- `EngineOutcome<SizedMember>` encodes/decodes both cases stably (P2 defined the custom generic-enum `Codable`; P3 asserts a `.ok` round-trips value+citation+assumptions and `.outOfEnvelope` round-trips reason+citation). Key assertion: discriminator key present so a decoder can pick the case. (Locks the P2 contract before P3 engines depend on it.)
- `EngineOutcome<JoistSpanResult>` / `<BeamSizingResult>` etc. round-trip — proves the P3 payloads slot into the P2 envelope generic.
- `EngineCitation` equality is structural; `packageEdition` is non-empty in any constructed citation (guards §6.6 "edition in force").
- Compliance-string guard helper (used by views, asserted here): a `.ok` outcome **must** carry `assumptions.packageEdition == citation.packageEdition`.

**Dependencies (consumed):** the P2 envelope (`EngineOutcome`/`EngineCitation`/`EngineAssumptions`/`SizedMember`/`MemberSizingResult`, `EngineEnvelope.swift`); `WoodSpecies`, `LumberGrade`, `LumberSize` (P2 `FramingPlan` block, contract §2.4).

**Code/standard refs:** contract §3 (Phase ownership note), §0.4 (result + limiting check + cited section + edition), §6.5/§6.6.

**Risks:** Swift's synthesized `Codable` for the generic `EngineOutcome` enum needs an explicit discriminator — that work is P2's (`EngineEnvelope.swift`); P3 only verifies it round-trips with the P3 payloads. If P2's envelope is missing or mis-decodes, treat it as a P2 gap to flag, not re-implement here.

---

### Task 2 — Code package data model + lookup structs (`CodePackage.swift`)

**Interface (verbatim header, contract §3.4):**

```swift
public struct CodePackage: Codable, Equatable, Sendable {
    public var jurisdictionId: String            // "US-IRC", "CA-BC", ...
    public var edition: String                   // "IRC 2021 / DCA6-12"
    public var publishedDate: Date
    public var unitSystem: PackageUnits          // imperial (psf) | metric (kPa)
    public var joistSpanTable: SpanTable
    public var beamSpanTable: SpanTable
    public var postHeightTable: PostTable
    public var footingTable: FootingTable
    public var cantileverRules: CantileverRules
    public var guardRules: GuardRules
    public var stairRules: StairRules
    public var ledgerRules: LedgerRules
    public var presumptiveSoilPSF: Double
    public var envelopeLimits: EnvelopeLimits
}
public enum PackageUnits: String, Codable, Sendable { case imperial, metric }
```

Lookup structs (shape pinned to engine needs; finalized against real tables at phase start):

```swift
public struct SpanTable: Codable, Equatable, Sendable {
    public var rows: [SpanRow]
    // Allowable span for the closest-matching row, or nil if no covering row.
    public func lookup(size: LumberSize, species: WoodSpecies, grade: LumberGrade,
                       spacingInchesOC: Double, liveLoadPSF: Double) -> SpanRow?
}
public struct SpanRow: Codable, Equatable, Sendable {
    public var size: LumberSize; public var species: WoodSpecies; public var grade: LumberGrade
    public var spacingInchesOC: Double; public var liveLoadPSF: Double
    public var allowableSpanInches: Double; public var deflectionRatio: String   // "L/360"
    public var codeSection: String
}
public struct PostTable: Codable, Equatable, Sendable {
    public var rows: [PostRow]
    public func lookup(size: LumberSize, species: WoodSpecies, axialLoadLb: Double) -> PostRow?
}
public struct PostRow: Codable, Equatable, Sendable {
    public var size: LumberSize; public var species: WoodSpecies
    public var maxAxialLoadLb: Double; public var maxHeightFeet: Double; public var codeSection: String
}
public struct CantileverRules: Codable, Equatable, Sendable {
    // 2021 adjacent-span: cantilever <= backspan/ratioDenominator AND <= per-size cap.
    public var ratioDenominator: Double          // e.g. 4 (1/4 backspan)
    public var maxByJoistSize: [LumberSize: Double]   // feet, IRC R507.6 Fig
    public var codeSection: String
}
public struct EnvelopeLimits: Codable, Equatable, Sendable {
    public var maxTributarySqFt: Double; public var minSoilPSF: Double
    public var maxPostHeightFeet: Double; public var maxSpanInTableInches: Double
}
// FootingTable / GuardRules / StairRules / LedgerRules: decoded + carried in P3,
// consumed P4/P7. Decode-only here; minimal Codable structs.
```

Every lookup struct uses **defensive `init(from:)` with `decodeIfPresent` + default** — the §2.1 pattern (e.g. `DrawingConfig`, `RailingConfig`) so a partial/older package never throws on decode.

**TEST STRATEGY** (`CodePackageTests`, table-driven against `IRC-2021-DCA6-12.fixture.json`):
- Decode the fixture → assert `unitSystem == .imperial`, `presumptiveSoilPSF == 1500`, `edition` non-empty.
- `joistSpanTable.lookup(size:.twoByEight, species:.sprucePineFir, grade:.no2, spacingInchesOC:16, liveLoadPSF:40)` returns the row whose `allowableSpanInches` matches the **hand-entered fixture cell** (e.g. DCA6 SPF #2 2×8 @16" o.c. ≈ 13′-1″ → assert against the fixture value, not from memory) with `deflectionRatio == "L/360"` and `codeSection == "AWC DCA6 Table ..."`.
- `lookup` returns `nil` when no covering row (e.g. spacing 24" absent) — engines convert nil → `outOfEnvelope` (Task 4).
- Metric fixture (`BCBC-2024-part9.fixture.json`): `unitSystem == .metric`, `presumptiveSoilPSF` carries the **kPa-equivalent** value; assert a metric lookup returns metric spans (the unit conversion lives at the engine boundary, Task 4).
- **Fixtures are the test mirror of the production package** (§5.2) — never hand-type cells into UI; the fixture is a *known subset* of the real edition's cells with hand-computed expectations.

**Dependencies:** `LumberSize`, `WoodSpecies`, `LumberGrade`, `FootingType` (P2).

**Code/standard refs:** IRC 2021 R507.5/.6, AWC DCA6-12 Tables; BCBC 2024 Part 9.12; contract §3.4, §6.8.

**Risks:** (a) `[LumberSize: Double]` as a `Codable` dictionary key — `LumberSize` is `String`-raw so it encodes as a JSON object; assert in the round-trip test. (b) Span-table interpolation vs nearest-row: **DCA6 is discrete, not interpolated** — never interpolate a code cell; an uncovered combination is out-of-envelope, not a guess. Asserted in Task 4.

---

### Task 3 — Package cache + live loader (`CodePackageCache.swift`, `CodePackageLoaderLive.swift`)

**Interface (verbatim, P1 protocol, contract §1.3):**

```swift
public protocol CodePackageLoader: Sendable {
    func availableJurisdictions() async throws -> [JurisdictionDescriptor]
    func loadPackage(jurisdictionId: String, edition: String?) async throws -> CodePackage
    func activePackage(for deck: DeckDesign) async throws -> CodePackage?
    func refreshCatalog() async throws
}
```

`CodePackageLoaderLive` is constructed with an injected **fetcher** seam (so tests never hit the network) + a `CodePackageCache`:

```swift
public protocol CodePackageFetching: Sendable {
    func fetchCatalog() async throws -> [JurisdictionDescriptor]
    func fetchPackage(jurisdictionId: String, edition: String?) async throws -> CodePackage
}
public final class CodePackageLoaderLive: CodePackageLoader { /* cache-first, offline-tolerant */ }
```

`activePackage(for:)` resolves `deck.drawingData.permitMeta?.jurisdictionId` (+ `.codeEdition`) → cached package, returning `nil` if no jurisdiction chosen (LIGHT / not-yet-selected). **Offline-first:** `loadPackage` returns a cached package without network when present; only downloads on miss; throws `CodePackageLoaderError.offline` (the P1-owned error enum) on a cold-miss-while-offline, or `.notDownloaded` for an uncached jurisdiction.

**TEST STRATEGY** (`CodePackageLoaderLiveTests`, with a `MockFetcher` + temp-dir cache):
- **Cache hit, no network:** seed the cache, point the fetcher at a `failOnNetwork` flag → `loadPackage` returns the cached value, fetcher never called.
- **Cache miss → download → cache:** empty cache → `loadPackage` calls the fetcher once, writes the cache; a second call hits cache only.
- **`refreshCatalog`** replaces the cached catalog; a superseded edition (`is_latest` flips) is reflected in `availableJurisdictions().latestEdition`.
- **Offline cold miss:** empty cache + `failOnNetwork` → `loadPackage` throws `CodePackageLoaderError.offline` (P1-owned enum; caller shows "download a jurisdiction while online"); assert the exact case.
- **`activePackage(for:)`:** deck with `permitMeta == nil` → `nil`; deck with a `jurisdictionId` whose package is cached → that package; with an uncached jurisdictionId offline → throws `CodePackageLoaderError.notDownloaded`/`.offline` (UI prompts download).
- Concurrency: two simultaneous `loadPackage` for the same id collapse to one fetch (assert fetcher call-count == 1) — guards against double-download.

**Dependencies:** `DeckDesign` (P1, in DeckKit), `CodePackage` (Task 2, P3-owned), `JurisdictionDescriptor` + `CodePackageLoaderError` (P1-owned, `CodePackageLoader.swift` — consumed, not re-declared), P1 `CodePackageLoader` protocol stub it replaces.

**Code/standard refs:** contract §1.3, §3.4, §6.4 ("push code updates without an App Store release", "code data current to [date]").

**Risks:** (a) **Supabase free-tier 500MB ceiling** — packages are small JSON (KBs) and live in Storage, not the DB, so negligible; flagged for transparency. (b) Cache-poisoning analogue to the deck-sync incidents — use **edition-versioned filenames** + checksum validation so a partial/corrupt download never overwrites a good cached package (atomic write to temp then rename). (c) The shared Supabase client throws when unauthed — catalog read must use the **anon-read path** (mirror the app-messages pre-auth kill-switch), so a fresh install can browse jurisdictions before sign-in.

---

### Task 4 — `StructuralSizingEngine` (the core)

**Why:** the FULL-tier headline. Pure, table-driven, offline; every method returns `EngineOutcome` carrying result + limiting check + cited section + assumptions + edition.

**Interface (verbatim, contract §3.1):**

```swift
public enum StructuralSizingEngine {
    public static func joistSpan(
        size: LumberSize, species: WoodSpecies, grade: LumberGrade,
        spacingInchesOC: Double, load: LoadPreset, package: CodePackage
    ) -> EngineOutcome<JoistSpanResult>

    public static func beamSizing(
        tributaryWidthFeet: Double, beamSpanFeet: Double,
        species: WoodSpecies, grade: LumberGrade, load: LoadPreset, package: CodePackage
    ) -> EngineOutcome<BeamSizingResult>

    public static func postSizing(
        axialLoadLb: Double, unbracedHeightFeet: Double,
        species: WoodSpecies, grade: LumberGrade, package: CodePackage
    ) -> EngineOutcome<PostSizingResult>

    public static func tributaryLoads(
        framing: FramingPlan, geometry: DeckDrawingData, load: LoadPreset
    ) -> [PostReaction]

    public static func cantilever(
        backspanFeet: Double, cantileverFeet: Double, joist: JoistSpanResult, package: CodePackage
    ) -> EngineOutcome<CantileverResult>

    public static func sizeAll(
        _ framing: FramingPlan, geometry: DeckDrawingData, package: CodePackage
    ) -> FramingPlan
}
```

Result structs (verbatim §3.1). **P2-owned (consumed, do NOT re-declare):** `MemberSizingResult { outcome: EngineOutcome<SizedMember> }`, `SizedMember { size, plyCount, allowableSpanFeet, actualSpanFeet, utilization }`. **P3-owned (declared in Task 1):** `JoistSpanResult { allowableSpanFeet, deflectionRatio }`, `BeamSizingResult { size, plyCount, maxPostSpacingFeet }`, `PostSizingResult { size, maxHeightFeet }`, `CantileverResult { allowedFeet, ok }`, `PostReaction { footingOrPostId, reactionLb, tributaryAreaSqFt }`.

**Sub-task 4a — `joistSpan`** (red→green): look up `package.joistSpanTable` for size/species/grade/spacing at the **governing** load (`max(load.liveLoadPSF, load.snowLoadPSF ?? 0)` for span selection per roadmap "snow overrides live where governing"); convert table inches→feet; package `JoistSpanResult` + `EngineCitation(limitingCheck:"deflection L/360", codeSection: row.codeSection, packageEdition: package.edition)` + `EngineAssumptions`. No covering row → `.outOfEnvelope(reason:"span/spacing/load combination not in table")`.

**Sub-task 4b — `beamSizing`** (back-solve): from `tributaryWidthFeet × beamSpanFeet × totalLoadPSF`, search `beamSpanTable` for the **smallest size + plyCount** whose allowable beam span ≥ `beamSpanFeet` at that tributary; emit `maxPostSpacingFeet` (the largest spacing whose induced beam span the chosen size still carries). IRC R507.5 + DCA6 beam tables; cite the row. No solution within table → `.outOfEnvelope`.

**Sub-task 4c — `postSizing`:** `package.postHeightTable.lookup(size:species:axialLoadLb:)`; pick smallest size whose `maxAxialLoadLb ≥ axialLoadLb` and `maxHeightFeet ≥ unbracedHeightFeet`. `unbracedHeightFeet > envelopeLimits.maxPostHeightFeet` → `.outOfEnvelope`. IRC R507.4.

**Sub-task 4d — `tributaryLoads`:** pure geometry — for each post/footing member in `framing`, compute tributary area from adjacent beam/joist spans (half-distance to neighboring supports × loaded width), `reactionLb = tributaryAreaSqFt × totalLoadPSF`. IRC R507.1 / Table R301.5. **Not** an `EngineOutcome` (no code pass/fail — it's a load number feeding 4b/4c and P4 footings); returns `[PostReaction]`.

**Sub-task 4e — `cantilever`:** 2021 adjacent-span rule — `allowedFeet = min(backspanFeet / package.cantileverRules.ratioDenominator, package.cantileverRules.maxByJoistSize[joistSize])`; `ok = cantileverFeet <= allowedFeet`. IRC R507.6. Exceeding both the ratio **and** the per-size cap returns `.outOfEnvelope` (not just `ok:false`) when geometry is past the table envelope.

**Sub-task 4f — `sizeAll`:** iterate every member; **skip `locked == true`** (manual editor authority); for joists call `joistSpan` and set `actualSpanFeet` from member geometry → `utilization = actual/allowable`; for beams `beamSizing`; for posts use `tributaryLoads` → `postSizing`; write `MemberSizingResult` into `member.sizing`; set `FramingPlan.generationSource = .autoThenEdited` if any member was previously locked/edited, else `.auto`; bump `generatedAtSchemaVersion = 3`. Returns a new `FramingPlan` (value semantics).

**TEST STRATEGY** (`StructuralSizingEngineTests`, table-driven, fixture-backed):
- **Joist span, in-table:** SPF #2 2×8 @16" o.c. @40 psf live → assert `allowableSpanFeet` equals the fixture cell ÷ 12, `deflectionRatio == "L/360"`, citation section matches; `.ok` carries `assumptions.packageEdition == package.edition`.
- **Snow governs:** same joist with `load.snowLoadPSF = 70` selects the higher-load column → smaller allowable span than the 40-psf case (assert strictly less).
- **Beam back-solve:** tributary 6′, span 9′, SPF #2 → assert the engine picks the documented size+ply (e.g. doubled 2×10) and a `maxPostSpacingFeet` ≤ fixture max; cite R507.5.
- **Post sizing:** axial 4,500 lb, height 8′ → smallest passing size from fixture; height 14′ with `maxPostHeightFeet == 12` → `.outOfEnvelope` (assert case + reason mentions height).
- **Tributary loads:** a rectangular 12′×16′ single-beam deck with N posts → assert each `PostReaction.tributaryAreaSqFt` sums (within ε) to the loaded deck area and `reactionLb == area × (40+10)`; anchor the geometry off computed positions, never literal coordinates baked to a date or device.
- **Cantilever:** backspan 12′, joist 2×10, cantilever 3′ → `allowedFeet == min(12/4, cap)`, `ok == true`; cantilever 5′ → `ok == false`; cantilever 8′ past the table → `.outOfEnvelope`.
- **`sizeAll`:** a P2 `FramingPlan` (all `sizing == nil`) with one member `locked == true` → after `sizeAll`, the locked member's `sizing` stays `nil`, every unlocked member has a non-nil `sizing`, `generatedAtSchemaVersion == 3`.
- Use `XCTUnwrap`/exhaustive `switch` on `EngineOutcome` so a future fourth case can't slip through silently.

**Dependencies:** `FramingPlan`/`FramingMember`/`LoadPreset`/`LumberSize`/`WoodSpecies`/`LumberGrade`/`FramingSource` (P2, §2.4); `EngineOutcome`/`EngineCitation`/`EngineAssumptions`/`SizedMember`/`MemberSizingResult` (P2 envelope, `EngineEnvelope.swift`); the P3 result payloads `JoistSpanResult`/`BeamSizingResult`/`PostSizingResult`/`CantileverResult`/`PostReaction` (Task 1); `DeckDrawingData` geometry + `effectiveScaleFactor`/`PolygonMath.realWorldArea` (existing, for tributary area); `CodePackage` (Task 2).

**Code/standard refs:** IRC 2021 R507.1 (loads), R507.4 (posts), R507.5 (beams), R507.6 (joists/cantilever), Table R301.5; AWC DCA6-12 span/beam tables; contract §3.1, §6.1–6.6.

**Risks:** (a) **Liability** — the engine must never emit a number for an out-of-envelope condition; every path that can't find a covering table row returns `.outOfEnvelope`, asserted in Task 5. (b) Tributary geometry on irregular/multi-level decks is hard; for P3, tributary is computed for rectangular/orthogonal bays (the auto-framer's output); skewed/curved bays exceeding the model → `.outOfEnvelope` rather than a wrong number. (c) Unit conversion: metric packages return kPa-derived loads; convert at the engine boundary via `package.unitSystem`, never deeper.

---

### Task 5 — Out-of-envelope hard-stop coverage (`StructuralSizingEnvelopeTests`)

**Why a dedicated task:** §6.5 is the single highest-liability rule. Out-of-envelope is a **hard stop → "requires a licensed engineer," emit no number.** Every `EnvelopeLimits` threshold gets an explicit failing test.

**TEST STRATEGY:**
- `tributaryAreaSqFt > envelopeLimits.maxTributarySqFt` (drive via a beam with huge tributary) → `beamSizing` returns `.outOfEnvelope`, **no `BeamSizingResult`**; assert exhaustively the value cannot be extracted.
- `soilBearingPSF < envelopeLimits.minSoilPSF` (1500 psf / 75 kPa) → the assumption is surfaced and (for the P4-facing path) flagged; in P3 the engine still sizes wood members but `EngineAssumptions.soilBearingPSF` carries the sub-minimum value so the UI can warn.
- `unbracedHeightFeet > maxPostHeightFeet` → `postSizing` `.outOfEnvelope`.
- span/spacing/load combination not in `joistSpanTable` (24" o.c. when fixture only has 12/16) → `joistSpan` `.outOfEnvelope`.
- cantilever past ratio + cap → `.outOfEnvelope`.
- **String guard:** assert no `.outOfEnvelope` reason string contains "safe", "compliant", "guaranteed", or "will pass" (a unit-level enforcement of §6.1); assert the citation still stamps `packageEdition`.

**Dependencies:** Tasks 1, 2, 4.

**Code/standard refs:** contract §6.5, §6.6; roadmap §7.5.

**Risks:** missing an envelope path means the app emits an unverified engineering number — the exact liability the contract forbids. This task is the gate; treat any uncovered `EnvelopeLimits` field as a failing build.

---

### Task 6 — Schema ver-3 round-trip + LIGHT preservation (`DrawingDataV3RoundTripTests` + `DeckGeometry.swift` bump)

**Why:** P3 fills `FramingMember.sizing`. A `.light` build (OPS) opening a P3-engineered design must render the geometry it understands and **round-trip the `sizing` results untouched** (§1.4 / §0.2). The schema version bumps to **3**.

**Changes:**
- `DeckGeometry.swift`: ensure `DeckDrawingData.schemaVersion` writes `3` on save for designs that have been sized; `DeckDesign.version` migration path recognizes a v3 blob. No new top-level property (contract §2.2 — P3 row is "no new block").
- Confirm P2's `FramingMember.sizing: MemberSizingResult?` decodes with `decodeIfPresent` (it must, per P2 — verified at phase start).

**TEST STRATEGY:**
- **Encode→decode→encode stable:** a sized `DeckDrawingData` → JSON → decode → JSON; assert byte-stable (sorted keys) and `sizing` survives with identical `EngineOutcome`.
- **LIGHT preserves FULL `sizing`:** decode a P3-sized JSON under a `.light` `DeckCapabilities`, mutate an unrelated LIGHT-editable field (e.g. a railing color), re-encode → assert every `FramingMember.sizing` is **byte-identical** to the input (the `unknownBlocks`/declared-optional preservation guarantee). LIGHT never strips engineering it can't author.
- **Malformed sizing sub-block decodes to nil, whole design survives:** inject a `sizing` object with a garbage `outcome` discriminator → assert `DeckDrawingData.fromJSON` still returns a valid design (geometry intact), that member's `sizing == nil`, and no throw.
- **Capability decoupled from version:** a v3 design opens under `.light` (assert capabilities don't gate decode), under `.full` the `sizing` is readable.

**Dependencies:** `FramingPlan`/`FramingMember`/`MemberSizingResult` (P2 + Task 4), `unknownBlocks` passthrough + `AnyCodable` nested support (P1), `DeckCapabilities` (P1, contract §4).

**Code/standard refs:** contract §0.2, §0.3, §1.4, §2.2, §4, §8.1/8.2; memory: crew-blackout & stale-overwrite incidents (poisoned cursor / last-writer-wins) — the reason preservation is mandatory.

**Risks:** the §1.4 backward-preservation only holds if P1 actually shipped `unknownBlocks` + nested `AnyCodable`. **Verify at phase start** that P1's `AnyCodable` carries nested object/array values (today's `OPS/DeckBuilder/Engine/ComponentEmitter.swift` `AnyCodable` is **scalar-only** — confirmed by inspection; P1 extends it). If P1 declared `sizing` as a real optional property (the forward path), preservation is automatic for a `.full`-aware build; the `unknownBlocks` path is the belt-and-suspenders for a LIGHT build that predates the property — assert both.

---

### Task 7 — `FramingSizingViewModel` + manual framing editor (`FramingEditorView`, `MemberSizingInspector`)

**Why:** RedX parity — the user must select / size / move / **lock** members, re-run sizing, and never have the engine silently overwrite a deliberate manual choice.

**Interface (view-model, P3-owned; not a contract type — kept thin):**

```swift
@MainActor final class FramingSizingViewModel: ObservableObject {
    @Published private(set) var framing: FramingPlan
    @Published var selectedMemberId: String?
    init(framing: FramingPlan, geometry: DeckDrawingData, package: CodePackage?, capabilities: DeckCapabilities)
    func sizeAll()                                  // calls StructuralSizingEngine.sizeAll on unlocked members
    func setSize(_ size: LumberSize, ply: Int, for memberId: String)   // manual override -> locks
    func setLocked(_ locked: Bool, for memberId: String)
    func move(memberId: String, start: CGPoint, end: CGPoint)          // re-derive neighbors, respect locks
    var canEngineer: Bool { capabilities.contains(.structuralSizing) && package != nil }
}
```

Editor behavior: selecting a member opens `MemberSizingInspector` showing `SizedMember` (size, plyCount, utilization formatted `%`), the **limiting check**, **cited code section**, **surfaced assumptions** (load/species/grade/edition), and — for `.outOfEnvelope` — a hard-stop card "Requires a licensed engineer" with **no number** and the disclaimer. Manual size/move sets `locked = true` so the next `sizeAll` preserves it (`FramingSource.autoThenEdited`). All gated by `canEngineer`; under `.light` the editor surface is **hidden** (single tasteful "available in OPS Decks Pro" upsell stub permitted per contract §4).

**TEST STRATEGY:**
- View-model unit tests (no UI): `setSize` flips `locked == true` and writes the chosen size; subsequent `sizeAll()` leaves that member untouched while sizing the rest; `setLocked(false)` re-includes it on next `sizeAll`.
- `canEngineer == false` under `.light` capabilities or `package == nil`; `sizeAll()` is a no-op when `!canEngineer` (assert framing unchanged) — LIGHT physically cannot produce a sizing number (§4 rule).
- `move(...)` updates endpoints and marks the member edited; a locked neighbor stays fixed.
- **Snapshot harness** (`ImageRenderer → XCTAttachment`): render `MemberSizingInspector` for (a) an `.ok` sized joist and (b) an `.outOfEnvelope` post; attach for human visual QA. Assert the out-of-envelope render contains the disclaimer text and **no numeric span/size** (string-scan the rendered view model output, since pixels aren't asserted).
- Interactive drag/select QA stays a human step (computer-use) — flagged, not automated.

**Dependencies:** `StructuralSizingEngine.sizeAll` (Task 4), `FramingPlan`/`FramingMember`/`LumberSize` (P2), `CodePackage` (Task 2), `DeckCapabilities` (P1), P2's framing 3D render (`DeckMeshGenerator`) for overlay coordinates, existing `DeckBuilderViewModel`/canvas conventions.

**Code/standard refs:** roadmap §2.1 "Manual framing editor (select/size/move/lock)", "mirrors Chief Architect edit"; contract §3.6 (auto-then-preserve pattern from `DeckTemplateEngine`), §4 (surface hidden under absent capability), §6.2 (disclaimer), §6.5 (hard stop).

**Risks:** SwiftUI `.draggable` drag-end detection caveat (memory: drag-to-reschedule) — member move must detect commit/cancel via the drag preview's `.onDisappear` or it leaks drag state and locks the editor. Engineer the move gesture against that known gotcha.

---

### Task 8 — Jurisdiction selection UI (`JurisdictionPickerView`, `CodePackageStatusBadge`)

**Why:** §6.3 — jurisdiction selection drives the ruleset. The user picks country + region + edition before any sizing; the choice writes `PermitMeta.jurisdictionId`/`.codeEdition`.

**Behavior:**
- `JurisdictionPickerView`: lists `availableJurisdictions()` (catalog), grouped by country → region; shows downloaded vs available; tapping an undownloaded jurisdiction triggers `loadPackage` (download + cache) with progress; on success writes `deck.drawingData.permitMeta = PermitMeta(jurisdictionId:..., codeEdition: selectedEdition)` (the P1-minimal `PermitMeta { jurisdictionId, codeEdition }`).
- `CodePackageStatusBadge`: compact badge rendering `"code data current to \(package.publishedDate, formatted)"` (§6.4) with a re-download/refresh affordance; shown on every compliance/structural surface.
- Offline: if the chosen jurisdiction isn't cached and the device is offline, show "connect to download [jurisdiction] code data" — never silently fall back to a different jurisdiction's tables.
- All copy via `ops-copywriter` voice (terse, tactical, no exclamation, sentence case); all styling via OPSStyle tokens.

**TEST STRATEGY:**
- View-model/state tests: selecting a jurisdiction with a cached package sets `permitMeta` immediately (no network); selecting an uncached one calls the loader's `loadPackage` once then sets `permitMeta`; failure leaves `permitMeta` unchanged and surfaces an error.
- `CodePackageStatusBadge` formats `publishedDate` with the locked formatter (assert string contains the edition date, anchored off the fixture's `publishedDate`, not a literal).
- Snapshot harness for the picker (downloaded/available/downloading states) → XCTAttachment for human QA.
- Round-trip: writing `permitMeta` then `toJSON()`/`fromJSON()` preserves `jurisdictionId`/`codeEdition` (ties to Task 6).

**Dependencies:** `CodePackageLoader` (Task 3), `PermitMeta` (P1-minimal, contract §2.8), `JurisdictionDescriptor` (Task 2), OPSStyle, `ops-copywriter`.

**Code/standard refs:** contract §6.3, §6.4, §2.8; roadmap §7.3/7.4.

**Risks:** AHJ-delegated values (frost, setbacks) are **not** in P3's scope — the picker must not imply the bundled package answers frost/setback; that disclaimer ("verify with your AHJ") is surfaced in P4. P3 keeps the picker scoped to structural editions only.

---

### Task 9 — App-target loader conformers + capability wiring

**Why:** DeckKit's `CodePackageLoaderLive` needs a host fetcher; only OPS Decks (`.full`) exposes the structural surfaces.

**Work:**
- `DecksAppCodePackageLoader` (OPS Decks): a `CodePackageFetching` impl hitting `/api/code-packages/catalog` + `/api/code-packages/:jurisdictionId` with the Firebase token (company-of-one), feeding `CodePackageLoaderLive` + an on-disk cache in the app's Application Support dir.
- `OPSCodePackageLoader` (OPS): same shape; under `.light` the structural surfaces are hidden so it's effectively dormant (catalog may still load for parity but no engine runs).
- Confirm `CapabilityProvider` supplies `.full` to DeckKit in OPS Decks and `.light` in OPS (P1 wiring); P3 is the first consumer of `.structuralSizing` / `.loadCalc`.

**TEST STRATEGY:**
- Fetcher conformance test against a stubbed `URLProtocol` (no live network): catalog endpoint returns a fixture catalog → decodes to `[JurisdictionDescriptor]`; package endpoint returns a fixture blob → decodes to `CodePackage`. Assert the Authorization header carries the token (company-of-one endpoints authorize a deck-only company — verify, per foundation-spec risk §12.4).
- Capability gate: with `.light` capabilities, `FramingSizingViewModel.canEngineer == false` end-to-end (no engine invocation) — re-assert at the app boundary.

**Dependencies:** `CodePackageLoaderLive` + `CodePackageFetching` (Task 3), `CapabilityProvider`/`DeckCapabilities` (P1), ops-web endpoints (Task 10), `ImageUploader`/auth seams (P1) for the token.

**Code/standard refs:** contract §1.3, §4; foundation spec §4.1, §12.4.

**Risks:** ops-web endpoint authorization for a `subscription_plan = 'decks'` company-of-one must succeed (same Firebase auth model) — verify before relying on it; otherwise jurisdictions can't download for standalone users.

---

### Task 10 — Backend: `code_packages` table + Storage + ops-web delivery

**Why:** §6.4 — code rules are **data**, Supabase-stored, ops-web-delivered, updatable **without an App Store release**.

**Work (consult the bible + verify schema via Supabase MCP before migrating):**
- Migration: `code_packages` table (`id, jurisdiction_id, edition, published_date, storage_path, checksum, unit_system, is_latest, created_at`). RLS: **anonymous SELECT** (catalog is public/pre-auth; mirror the app-messages anon-read kill-switch) — code tables are not company-private. No client write (admin/service-role only via ops-web).
- Storage bucket `code-packages` with the versioned JSON blobs; path convention `\(jurisdiction_id)/\(edition).json`.
- ops-web `/api/code-packages/catalog` (lists latest + available editions) and `/api/code-packages/[jurisdictionId]` (returns the package blob or a signed URL); both validate but don't *require* a company (anon catalog).
- ops-web `/admin/code-packages` stub to upload/version a package (out-of-band of App Store).
- Seed the **first two real packages**: `US-IRC` (IRC 2021 / DCA6-12, imperial) and `CA-BC` (BCBC 2024 Part 9, metric), built from the **adopted editions' actual tables** (§6.8 — verbatim ingestion, not cell-by-cell research transcription).
- **Update the OPS Software Bible** (`07_SPECIALIZED_FEATURES.md` + data-model section) with the `code_packages` schema, the delivery endpoints, and the package JSON format.

**TEST STRATEGY:**
- Supabase RLS verification (simulated user via `set_config` jwt claims + rollback, per memory `supabase-rls-trigger-safe-test`): an anonymous role can SELECT the catalog; a client role cannot INSERT/UPDATE.
- ops-web route tests: catalog returns the seeded jurisdictions; package route returns a blob that decodes to a valid `CodePackage` (round-trips through `CodePackage.swift` Task 2 decode in a DeckKit integration test reading the seeded fixture).
- Checksum: the delivered blob's checksum matches the catalog row (guards corrupt-download → cache-poisoning, Task 3).

**Dependencies:** `CodePackage` JSON format (Task 2), ops-web auth, Supabase project (existing). **Cost note:** Storage + DB rows are negligible on the free tier; the foundation spec's Supabase Pro upgrade ($25/mo, for backups before paying-customer data) remains the gating prerequisite — flag, don't block P3 dev.

**Code/standard refs:** contract §3.4, §6.4, §6.8; CLAUDE.md (always verify schema via Supabase MCP, keep the bible updated, cost transparency).

**Risks:** (a) ingesting tables **verbatim** is the legal posture — do not hand-edit cells; build each package from the edition's actual tables and checksum it. (b) IRC Appendix H (overhead) is paywalled — **out of P3 scope** (P6); no roof tables in these packages.

---

### Task 11 — Compliance posture conformance + estimate/BOM integration

**Why:** P3 is the first phase to assert numbers; it must obey **all of §6** and feed the now-engineered members into the existing takeoff additively.

**Work:**
- **Disclaimer gate:** before any structural result renders, require `PermitMeta.disclaimerAcknowledgedAt` (P1/P7 field — P3 sets it on first acknowledgement). Wire the acknowledgement sheet (copy via `ops-copywriter`, the §6.2 verbatim string).
- **Summary string discipline:** P3 surfaces per-member results, not a `ComplianceReport` (that's P7). But every result view obeys §6.1 — no "safe/compliant/guaranteed/will pass"; out-of-envelope → "requires a licensed engineer." Centralize the locked phrasings in a `ComplianceCopy` constant so P7 reuses it.
- **Estimate/BOM:** `ComponentEmitter.emit` gains additive rows (`joist`, `beam`, `post` — never rename an existing `component_type`, per the doc comment) so the lumber takeoff reflects sized members; `EstimateGeneratorService` consumes them as new categories (waste already threaded by P1). Sized members carry real dimensions; unsized (LIGHT) fall back to P2's plausible-frame BOM with no code claim.

**TEST STRATEGY:**
- String-discipline unit test: scan every P3 result/inspector view's user-facing strings for the forbidden words; assert absence (extends Task 5's guard to the UI layer).
- `ComponentEmitter` additive test: a sized `FramingPlan` emits `joist`/`beam`/`post` rows with dimensional metadata; an unsized plan emits the P2 plausible rows; **no existing `component_type` value changes** (regression-lock the existing railing/deck_board/stair_set/gate strings).
- Disclaimer gate test: result surface refuses to render numbers until `disclaimerAcknowledgedAt != nil`.

**Dependencies:** `PermitMeta.disclaimerAcknowledgedAt` (P1-minimal/P7), `ComponentEmitter`/`EstimateGeneratorService` (existing), `MemberSizingResult` (Task 4), `ops-copywriter`.

**Code/standard refs:** contract §6.1, §6.2, §6.5, §6.6, §3.6 (`ComponentEmitter` additive-only); roadmap §7.

**Risks:** scope creep into P7's `ComplianceEngine` — P3 must **not** emit a `ComplianceReport` or "no code failures detected" summary (that's the design-time check engine, P7). P3 asserts only per-member sizing + out-of-envelope hard-stops. Keep the line crisp.

---

### Task 12 — Build verification + full-suite gate

**Work:**
- Device build: `xcodebuild -scheme OPS -destination 'generic/platform=iOS' build` → grep `BUILD SUCCEEDED`.
- Tests compile + run: `xcodebuild -scheme OPS -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' build-for-testing` then `test` → grep `TEST SUCCEEDED`. (Copy `Secrets.xcconfig` into the worktree first; don't fight a sibling session's DerivedData.)
- Confirm DeckKit + both app targets build; OPS (`.light`) shows no structural surfaces; OPS Decks (`.full`) shows them.

**TEST STRATEGY:** the whole P3 test target green; round-trip + envelope tests are the non-negotiable gates. Treat the background-build trailing-echo exit code as untrustworthy — verify via the log grep.

**Dependencies:** all prior tasks.

**Risks:** worktree SourceKit "cannot find type" noise on freshly-written files is index lag — trust `xcodebuild`. Some full-suite failures are sim app-launch denials, not P3 regressions — confirm against a stashed baseline.

---

## Cross-cutting risks & decisions

- **Liability is the dominant constraint.** P3 is the first phase that asserts engineering numbers; the §6 rules are not advisory. The out-of-envelope hard-stop (Task 5) and string discipline (Task 11) are gates, not nice-to-haves. When in doubt, the engine returns `.outOfEnvelope` and the UI says "requires a licensed engineer."
- **Tables are data, ingested verbatim.** Never hand-type or interpolate a code cell. Uncovered combinations are out-of-envelope. Fixtures mirror production packages with hand-computed expectations.
- **Offline-first must hold through the engine.** All sizing is pure + on-device against a cached package; only the loader touches the network, and it's cache-first. A field user with a downloaded jurisdiction engineers a deck with no signal.
- **Schema discipline.** P3 adds no top-level block (ver 3 = "no new block"); it fills `FramingMember.sizing` and reads `PermitMeta.jurisdictionId`. Round-trip + LIGHT-preservation tests are mandatory (the crew-blackout/stale-overwrite incidents are why).
- **Predecessor dependency.** P3 cannot start until P1 (DeckKit carve-out, seams, `CodePackageLoader` stub, `unknownBlocks`, `PermitMeta` minimal, `AnyCodable` nested support) and P2 (`FramingPlan` block + auto-framer producing `sizing == nil`) are merged. Verify each at phase start; the literal TDD steps are finalized then.
- **Cost (transparency):** code packages are small JSON in Supabase Storage (negligible on free tier); the Supabase Pro upgrade ($25/mo for backups) is the standing prerequisite before paying-customer data, flagged in the foundation spec — not introduced by P3. RevenueCat `deck_pro` gates the saved-deck cap, separate from these capabilities.
