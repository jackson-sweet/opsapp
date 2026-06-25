# OPS Decks Phase 1 Standalone Foundation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship the Phase 1 OPS Decks foundation: existing deck designer runs in a standalone OPS Decks app target through shared DeckKit/OPSDesignKit seams, with local-first save, company-of-one account path, one-deck entitlement gate, schema preservation for future deck systems, and no styling outside design tokens.

**Architecture:** Implement this in staged cuts so the existing OPS app keeps working at every checkpoint. First add schema-preservation tests and app-agnostic runtime seams while DeckBuilder still lives in the OPS target, then extract styling into `OPSDesignKit`, extract deck logic/UI into `DeckKit`, and add a thin `OPSDecks` app target that supplies its own auth, store, entitlement, and upgrade surfaces. Backend changes are limited to the deck subscription mirror and company-of-one provisioning contract; structural engineering, live code, zoning, permit, and realistic rendering systems are schema-preserved only.

**Tech Stack:** Swift 5.9+/SwiftUI, SwiftData, SceneKit, ARKit behind `#if os(iOS)`, PDFKit, Firebase Auth, Supabase, RevenueCat/StoreKit 2, local Swift packages, Xcode file-system-synchronized groups, OPSDesignKit/OPSStyle tokens.

## Global Constraints

- Phase 1 scope is foundation/carve-out only: no Framing Mode, Structural Mode, live code overlay implementation, parcel/zoning resolver, permit-ready checks, advanced railing/stair config, roof/opening modeling, realistic renderer, or engineering reports.
- OPS Decks targets iPhone first while preserving iPad and Mac architecture; AR code must remain hidden/guarded where ARKit is unavailable.
- The free tier is fully featured for one saved deck; Pro unlocks unlimited saved decks.
- Data stays in the existing Supabase backend using `deck_designs.company_id` RLS; standalone sketches have `project_id = nil`.
- Deck-only billing must never write OPS subscription state into `companies.subscription_*`; mirrored deck entitlement lives in a dedicated `deck_subscriptions` surface.
- Supabase Pro is a hard pre-launch gate before standalone customer data lands.
- Every `drawing_data` schema change must be additive and backward-decodable; unknown/future blocks must round-trip without failing the whole decode.
- All user-visible compliance/zoning/code language stays objective-negative; Phase 1 should not introduce positive compliance claims.
- **No hardcoded styling/design.** New or touched OPS Decks/DeckKit/OPSDesignKit UI code must not introduce literal colors, fonts, spacing, radii, shadow values, icon styles, or animation constants. Use OPSDesignKit/OPSStyle tokens only. Domain material/catalog colors must live in material/catalog data, not UI code.
- Every new button label, empty state, warning, error, paywall line, and onboarding/account string must be governed by `ops-copywriter`. Keep copy in constants or localization resources, never inline inside SwiftUI view layout code.
- Do not work in the dirty shared checkout. Create an isolated worktree before implementation and preserve unrelated changes in `/Users/jacksonsweet/Projects/OPS/ops-ios`.

---

## File Structure

Create:
- `scripts/verify-ops-decks-style-tokens.sh` — static hardcoded-style scanner for new/touched deck standalone surfaces.
- `Packages/OPSDesignKit/Package.swift` — local Swift package for design tokens/components.
- `Packages/OPSDesignKit/Sources/OPSDesignKit/OPSStyle.swift` — moved token source from `OPS/Styles/OPSStyle.swift`, adjusted for package resources.
- `Packages/OPSDesignKit/Sources/OPSDesignKit/OPSDesignKit.swift` — public marker/export file.
- `Packages/OPSDesignKit/Resources/Colors.xcassets/` — copied color asset catalog entries required by OPSStyle.
- `Packages/DeckKit/Package.swift` — local Swift package for the deck designer.
- `Packages/DeckKit/Sources/DeckKit/Runtime/DeckRuntime.swift` — app-agnostic runtime protocols and context.
- `Packages/DeckKit/Sources/DeckKit/Models/DeckDrawingFutureBlocks.swift` — future-block preservation model.
- `Packages/DeckKit/Sources/DeckKit/Support/DeckKitExports.swift` — public marker/export file.
- `Packages/DeckKit/Tests/DeckKitTests/DeckDrawingFutureBlocksTests.swift` — unknown-block preservation tests.
- `Packages/DeckKit/Tests/DeckKitTests/DeckRuntimeStoreTests.swift` — runtime/store seam tests.
- `OPS/DeckBuilder/DeckBuilderHostView.swift` — compatibility wrapper importing DeckKit for the OPS app.
- `OPS/DeckBuilder/OPSDeckRuntimeFactory.swift` — OPS app runtime adapter for DeckKit.
- `OPSDecks/OPSDecksApp.swift` — standalone app entry point.
- `OPSDecks/OPSDecksCopy.swift` — localized user-facing copy constants for the standalone target.
- `OPSDecks/OPSDecksRootView.swift` — minimal standalone shell/library/create/open surface.
- `OPSDecks/OPSDecksRuntimeFactory.swift` — standalone runtime adapter for DeckKit.
- `OPSDecks/DecksEntitlementService.swift` — RevenueCat/StoreKit-facing entitlement abstraction.
- `OPSDecks/DecksCompanyProvisioningService.swift` — company-of-one provisioning client.
- `OPSDecks/DecksAccountDeletionService.swift` — account deletion workflow client.
- `OPSDecks/DecksUpgradeSurface.swift` — minimal upgrade-to-OPS surface.
- `OPSTests/DeckBuilder/DeckDrawingFutureBlocksTests.swift` — temporary test target copy if package tests cannot run until Xcode package wiring lands.
- `OPSTests/OPSDecks/DecksEntitlementGateTests.swift` — one-deck cap unit tests.
- `OPSTests/OPSDecks/DecksProvisioningPayloadTests.swift` — company-of-one payload tests.
- `docs/superpowers/specs/2026-06-25-ops-decks-phase-1-backend-contract.md` — backend contract for provisioning, subscription mirror, and account deletion.

Modify:
- `OPS.xcodeproj/project.pbxproj` — add local packages, package product dependencies, `OPSDecks` app target, app product, and scheme.
- `OPS.xcodeproj/xcshareddata/xcschemes/OPS.xcscheme` — keep OPS scheme valid after package extraction.
- `OPS.xcodeproj/xcshareddata/xcschemes/OPSDecks.xcscheme` — create shared scheme for the standalone target.
- `OPS/DataModels/DeckDesign.swift` — keep model in shared app data layer or move into DeckKit only after SwiftData schema references are updated.
- `OPS/DataModels/Migrations/OPSSchemaCommon.swift` and latest schema file — ensure `DeckDesign` remains in the latest schema after package/module moves.
- `OPS/DeckBuilder/Models/DeckGeometry.swift` or the moved DeckKit copy — preserve future blocks during `fromJSON()`/`toJSON()`.
- `OPS/DeckBuilder/DeckBuilderViewModel.swift` or the moved DeckKit copy — replace direct `ModelContext`/`SyncEngine` dependency with runtime store seam.
- `OPS/DeckBuilder/Views/DeckBuilderView.swift` or the moved DeckKit copy — initialize with `DeckRuntimeContext`, keep existing OPS compatibility initializer.
- `OPS/Styles/OPSStyle.swift` — remove or turn into a compatibility re-export after `OPSDesignKit` is wired.
- `OPS/OPSApp.swift` — import/use OPSDesignKit and keep existing root unchanged.
- `OPS/Info.plist` and generated target settings — ensure existing OPS app behavior remains unchanged.
- `OPSDecks/GoogleService-Info.plist` or environment-specific Firebase config path — add only after app credentials exist; use non-production dev config during implementation.

---

### Task 1: Worktree, Baseline Proof, and Token Scanner

**Files:**
- Create: `scripts/verify-ops-decks-style-tokens.sh`
- Modify: none
- Test: shell scanner and baseline build command

**Interfaces:**
- Consumes: current dirty `ops-ios` checkout state.
- Produces: isolated worktree path and style scanner used by every later task.

- [ ] **Step 1: Create an isolated worktree**

```bash
cd /Users/jacksonsweet/Projects/OPS/ops-ios
git worktree add .worktrees/ops-decks-p1-foundation -b ops-decks/p1-foundation
cd .worktrees/ops-decks-p1-foundation
```

Expected: new worktree opens on branch `ops-decks/p1-foundation`. If the branch exists, inspect with `git worktree list` and choose the next unused branch name `ops-decks/p1-foundation-2`.

- [ ] **Step 2: Confirm no inherited unrelated changes**

```bash
git status --short
```

Expected: clean or only files intentionally copied by worktree setup. If unrelated changes appear, stop and inspect before editing.

- [ ] **Step 3: Create the style-token scanner**

Create `scripts/verify-ops-decks-style-tokens.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-.}"

TARGETS=(
  "$ROOT/OPSDecks"
  "$ROOT/Packages/DeckKit/Sources"
  "$ROOT/Packages/OPSDesignKit/Sources"
)

EXCLUDES='OPSStyle.swift|Package.swift|Generated|Resources|Colors.xcassets'

PATTERN='Color\(red:|Color\([[:space:]]*#[0-9A-Fa-f]|UIColor\(|NSColor\(|\.font\(\.system|Font\.system|\.cornerRadius\([0-9]|\.clipShape\(RoundedRectangle\(cornerRadius:[[:space:]]*[0-9]|\.padding\([0-9]|\.padding\(\.all,[[:space:]]*[0-9]|\.frame\(width:[[:space:]]*[0-9]|\.animation\(\.spring|Animation\.spring|\.shadow\(|boxShadow|#[0-9A-Fa-f]{6}'

found=0
for target in "${TARGETS[@]}"; do
  if [[ -d "$target" ]]; then
    while IFS= read -r line; do
      file="${line%%:*}"
      if [[ ! "$file" =~ $EXCLUDES ]]; then
        echo "$line"
        found=1
      fi
    done < <(rg -n "$PATTERN" "$target" || true)
  fi
done

if [[ "$found" -ne 0 ]]; then
  echo "Hardcoded styling/design values found. Route every value through OPSDesignKit/OPSStyle tokens." >&2
  exit 1
fi
```

- [ ] **Step 4: Make scanner executable and verify it passes before new code exists**

```bash
chmod +x scripts/verify-ops-decks-style-tokens.sh
scripts/verify-ops-decks-style-tokens.sh .
```

Expected: exit 0 with no output. It should ignore the existing `OPS/` app because Phase 1 only gates new/touched standalone/package surfaces.

- [ ] **Step 5: Record baseline build command**

Run:

```bash
xcodebuild -project OPS.xcodeproj -scheme OPS -destination 'generic/platform=iOS Simulator' -derivedDataPath /private/tmp/ops-ios-derived CODE_SIGNING_ALLOWED=NO build
```

Expected: `** BUILD SUCCEEDED **`. If sandboxed Xcode cannot write package caches or simulator logs, rerun with approved escalation and the same command. Preserve exact blocker text if it still fails.

- [ ] **Step 6: Commit**

```bash
git add scripts/verify-ops-decks-style-tokens.sh
git commit -m "chore: add OPS Decks style token scanner"
```

---

### Task 2: Preserve Future `drawing_data` Blocks

**Files:**
- Create: `Packages/DeckKit/Sources/DeckKit/Models/DeckDrawingFutureBlocks.swift` after package creation, or temporarily `OPS/DeckBuilder/Models/DeckDrawingFutureBlocks.swift`
- Modify: `OPS/DeckBuilder/Models/DeckGeometry.swift`
- Test: `OPSTests/DeckBuilder/DeckDrawingFutureBlocksTests.swift`

**Interfaces:**
- Consumes: `DeckDrawingData.toJSON()` and `DeckDrawingData.fromJSON(_:)`.
- Produces: `DeckDrawingData.futureBlocks` and `DeckJSONValue` so future framing/zoning/code/rendering blocks survive round trips.

- [ ] **Step 1: Write the failing future-block test**

Create `OPSTests/DeckBuilder/DeckDrawingFutureBlocksTests.swift`:

```swift
import XCTest
@testable import OPS

final class DeckDrawingFutureBlocksTests: XCTestCase {
    func testUnknownFutureBlocksRoundTripThroughDeckDrawingData() throws {
        let json = """
        {
          "vertices": [],
          "edges": [],
          "framing": {
            "version": 1,
            "members": [{"id": "j1", "kind": "joist", "span": 144}]
          },
          "parcelZoning": {
            "apn": "PID-123",
            "findings": [{"severity": "warning", "code": "REAR_SETBACK_CONCERN"}]
          },
          "codeOverlay": {
            "enabled": true,
            "findings": [{"elementId": "j1", "severity": "violation"}]
          },
          "rendering": {
            "engine": "realitykit",
            "preset": "client_hero"
          }
        }
        """

        let decoded = try XCTUnwrap(DeckDrawingData.fromJSON(json))
        let encoded = decoded.toJSON()

        XCTAssertTrue(encoded.contains("\"framing\""))
        XCTAssertTrue(encoded.contains("\"parcelZoning\""))
        XCTAssertTrue(encoded.contains("\"codeOverlay\""))
        XCTAssertTrue(encoded.contains("\"rendering\""))
        XCTAssertTrue(encoded.contains("REAR_SETBACK_CONCERN"))
    }
}
```

- [ ] **Step 2: Run the test and verify it fails**

```bash
xcodebuild test -project OPS.xcodeproj -scheme OPS -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:OPSTests/DeckDrawingFutureBlocksTests -derivedDataPath /private/tmp/ops-ios-tests CODE_SIGNING_ALLOWED=NO
```

Expected: fail because unknown top-level JSON blocks are discarded.

- [ ] **Step 3: Add a JSON value model**

Create `OPS/DeckBuilder/Models/DeckDrawingFutureBlocks.swift`:

```swift
import Foundation

enum DeckJSONValue: Codable, Equatable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: DeckJSONValue])
    case array([DeckJSONValue])
    case null

    init(from decoder: Decoder) throws {
        let single = try decoder.singleValueContainer()
        if single.decodeNil() {
            self = .null
        } else if let value = try? single.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? single.decode(Double.self) {
            self = .number(value)
        } else if let value = try? single.decode(String.self) {
            self = .string(value)
        } else if let value = try? single.decode([DeckJSONValue].self) {
            self = .array(value)
        } else {
            self = .object(try single.decode([String: DeckJSONValue].self))
        }
    }

    func encode(to encoder: Encoder) throws {
        var single = encoder.singleValueContainer()
        switch self {
        case .string(let value): try single.encode(value)
        case .number(let value): try single.encode(value)
        case .bool(let value): try single.encode(value)
        case .object(let value): try single.encode(value)
        case .array(let value): try single.encode(value)
        case .null: try single.encodeNil()
        }
    }
}

struct DeckDynamicCodingKey: CodingKey, Hashable {
    let stringValue: String
    let intValue: Int?

    init?(stringValue: String) {
        self.stringValue = stringValue
        self.intValue = nil
    }

    init?(intValue: Int) {
        self.stringValue = String(intValue)
        self.intValue = intValue
    }
}
```

- [ ] **Step 4: Modify `DeckDrawingData` to store future blocks**

In `OPS/DeckBuilder/Models/DeckGeometry.swift`, add:

```swift
var futureBlocks: [String: DeckJSONValue] = [:]
```

Then replace synthesized `DeckDrawingData` encoding/decoding with custom init/encode logic that:

```swift
let knownKeys = Set(CodingKeys.allCases.map(\.stringValue))
let dynamic = try decoder.container(keyedBy: DeckDynamicCodingKey.self)
self.futureBlocks = try dynamic.allKeys.reduce(into: [:]) { result, key in
    guard !knownKeys.contains(key.stringValue) else { return }
    result[key.stringValue] = try? dynamic.decode(DeckJSONValue.self, forKey: key)
}
```

And in `encode(to:)`:

```swift
var dynamic = encoder.container(keyedBy: DeckDynamicCodingKey.self)
for (key, value) in futureBlocks.sorted(by: { $0.key < $1.key }) {
    guard let codingKey = DeckDynamicCodingKey(stringValue: key) else { continue }
    try dynamic.encode(value, forKey: codingKey)
}
```

Keep all existing known keys encoded exactly as they are today.

- [ ] **Step 5: Run focused future-block and regression tests**

```bash
xcodebuild test -project OPS.xcodeproj -scheme OPS -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:OPSTests/DeckDrawingFutureBlocksTests -only-testing:OPSTests/DeckBuilderRegressionTests -derivedDataPath /private/tmp/ops-ios-tests CODE_SIGNING_ALLOWED=NO
```

Expected: both test groups pass.

- [ ] **Step 6: Commit**

```bash
git add OPS/DeckBuilder/Models/DeckDrawingFutureBlocks.swift OPS/DeckBuilder/Models/DeckGeometry.swift OPSTests/DeckBuilder/DeckDrawingFutureBlocksTests.swift
git commit -m "feat: preserve future deck drawing blocks"
```

---

### Task 3: Introduce Deck Runtime Seams Before Moving Files

**Files:**
- Create: `OPS/DeckBuilder/Runtime/DeckRuntime.swift`
- Create: `OPSTests/DeckBuilder/DeckRuntimeStoreTests.swift`
- Modify: `OPS/DeckBuilder/DeckBuilderViewModel.swift`
- Modify: `OPS/DeckBuilder/Views/DeckBuilderView.swift`

**Interfaces:**
- Consumes: existing `DeckDesign`, `DeckDrawingData`, `ModelContext`, and `SyncEngine`.
- Produces: `DeckRuntimeContext`, `DeckStore`, `DeckImageUploader`, `DeckOCRService`, and `DeckRuntime` used by both OPS and OPS Decks shells.

- [ ] **Step 1: Write seam tests**

Create `OPSTests/DeckBuilder/DeckRuntimeStoreTests.swift`:

```swift
import XCTest
@testable import OPS

@MainActor
final class DeckRuntimeStoreTests: XCTestCase {
    func testViewModelSaveDelegatesToInjectedDeckStore() {
        let store = SpyDeckStore()
        let runtime = DeckRuntime(
            context: DeckRuntimeContext(companyId: "company-1", projectId: nil, projectName: nil, appSurface: .opsDecks),
            store: store,
            imageUploader: NoopDeckImageUploader(),
            ocrService: NoopDeckOCRService()
        )
        var data = DeckDrawingData()
        data.vertices = [
            DeckVertex(id: "v1", position: .zero),
            DeckVertex(id: "v2", position: CGPoint(x: 120, y: 0))
        ]
        data.edges = [DeckEdge(id: "e1", startVertexId: "v1", endVertexId: "v2")]
        let design = DeckDesign(companyId: "company-1", projectId: nil, drawingDataJSON: data.toJSON())

        let viewModel = DeckBuilderViewModel(deckDesign: design, runtime: runtime)
        viewModel.save()

        XCTAssertEqual(store.savedDesignIds, [design.id])
        XCTAssertEqual(store.savedProjectIds, [nil])
    }
}

@MainActor
private final class SpyDeckStore: DeckStore {
    var savedDesignIds: [String] = []
    var savedProjectIds: [String?] = []

    func save(deckDesign: DeckDesign, drawingData: DeckDrawingData) throws {
        savedDesignIds.append(deckDesign.id)
        savedProjectIds.append(deckDesign.projectId)
    }

    func delete(deckDesign: DeckDesign) throws {}
}
```

- [ ] **Step 2: Run and verify failure**

```bash
xcodebuild test -project OPS.xcodeproj -scheme OPS -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:OPSTests/DeckRuntimeStoreTests -derivedDataPath /private/tmp/ops-ios-tests CODE_SIGNING_ALLOWED=NO
```

Expected: fail because runtime protocols do not exist.

- [ ] **Step 3: Add runtime protocol file**

Create `OPS/DeckBuilder/Runtime/DeckRuntime.swift`:

```swift
import Foundation

enum DeckAppSurface: Equatable {
    case ops
    case opsDecks
}

struct DeckRuntimeContext: Equatable {
    let companyId: String
    let projectId: String?
    let projectName: String?
    let appSurface: DeckAppSurface
}

@MainActor
protocol DeckStore: AnyObject {
    func save(deckDesign: DeckDesign, drawingData: DeckDrawingData) throws
    func delete(deckDesign: DeckDesign) throws
}

protocol DeckImageUploader: AnyObject {}
protocol DeckOCRService: AnyObject {}

final class NoopDeckImageUploader: DeckImageUploader {}
final class NoopDeckOCRService: DeckOCRService {}

struct DeckRuntime {
    let context: DeckRuntimeContext
    let store: DeckStore?
    let imageUploader: DeckImageUploader
    let ocrService: DeckOCRService

    init(
        context: DeckRuntimeContext,
        store: DeckStore?,
        imageUploader: DeckImageUploader = NoopDeckImageUploader(),
        ocrService: DeckOCRService = NoopDeckOCRService()
    ) {
        self.context = context
        self.store = store
        self.imageUploader = imageUploader
        self.ocrService = ocrService
    }
}
```

- [ ] **Step 4: Add OPS-backed store adapter inside `DeckBuilderViewModel.swift` or a separate file**

```swift
@MainActor
final class OPSDeckStore: DeckStore {
    private let modelContext: ModelContext?
    private weak var syncEngine: SyncEngine?

    init(modelContext: ModelContext?, syncEngine: SyncEngine?) {
        self.modelContext = modelContext
        self.syncEngine = syncEngine
    }

    func save(deckDesign: DeckDesign, drawingData: DeckDrawingData) throws {
        deckDesign.drawingData = drawingData
        if deckDesign.modelContext == nil {
            modelContext?.insert(deckDesign)
        }
        try modelContext?.save()
    }

    func delete(deckDesign: DeckDesign) throws {
        deckDesign.deletedAt = Date()
        deckDesign.markForSync()
        try modelContext?.save()
    }
}
```

Keep `enqueueDeckDesignSync()` in the view model for this task so behavior remains identical. Moving sync enqueueing behind `DeckStore` happens in a follow-up after tests pass.

- [ ] **Step 5: Add a runtime initializer while preserving the existing initializer**

Modify `DeckBuilderViewModel`:

```swift
private let runtime: DeckRuntime?

init(deckDesign: DeckDesign, runtime: DeckRuntime) {
    self.deckDesign = deckDesign
    self.modelContext = nil
    self.syncEngine = nil
    self.runtime = runtime
    // continue through the same shared setup path used by the existing initializer
}
```

Refactor shared setup into a private method if needed so both initializers initialize the same state.

- [ ] **Step 6: Route save through runtime store when present**

At the persistence point in `save()`:

```swift
do {
    if let store = runtime?.store {
        try store.save(deckDesign: deckDesign, drawingData: drawingData)
    } else {
        deckDesign.drawingData = drawingData
        if deckDesign.modelContext == nil {
            modelContext?.insert(deckDesign)
        }
        try modelContext?.save()
    }
    isLocallySaved = true
} catch {
    print("[DeckBuilder] Save failed: \(error)")
    ToastCenter.shared.present(Toast(label: Feedback.Err.saveFailed, tone: .error))
}
```

- [ ] **Step 7: Run seam and existing deck tests**

```bash
xcodebuild test -project OPS.xcodeproj -scheme OPS -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:OPSTests/DeckRuntimeStoreTests -only-testing:OPSTests/DeckBuilderRegressionTests -derivedDataPath /private/tmp/ops-ios-tests CODE_SIGNING_ALLOWED=NO
```

Expected: pass.

- [ ] **Step 8: Run style-token scanner**

```bash
scripts/verify-ops-decks-style-tokens.sh .
```

Expected: pass.

- [ ] **Step 9: Commit**

```bash
git add OPS/DeckBuilder/Runtime/DeckRuntime.swift OPS/DeckBuilder/DeckBuilderViewModel.swift OPS/DeckBuilder/Views/DeckBuilderView.swift OPSTests/DeckBuilder/DeckRuntimeStoreTests.swift
git commit -m "feat: add deck runtime seams"
```

---

### Task 4: Create OPSDesignKit and Enforce Tokenized Styling

**Files:**
- Create: `Packages/OPSDesignKit/Package.swift`
- Create: `Packages/OPSDesignKit/Sources/OPSDesignKit/OPSDesignKit.swift`
- Create/Move: `Packages/OPSDesignKit/Sources/OPSDesignKit/OPSStyle.swift`
- Create/Copy: `Packages/OPSDesignKit/Resources/Colors.xcassets`
- Modify: `OPS/Styles/OPSStyle.swift`
- Modify: `OPS.xcodeproj/project.pbxproj`
- Test: `scripts/verify-ops-decks-style-tokens.sh`

**Interfaces:**
- Consumes: existing `OPSStyle` token API.
- Produces: `import OPSDesignKit` module usable by OPS, DeckKit, and OPSDecks.

- [ ] **Step 1: Create package manifest**

Create `Packages/OPSDesignKit/Package.swift`:

```swift
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "OPSDesignKit",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(name: "OPSDesignKit", targets: ["OPSDesignKit"])
    ],
    targets: [
        .target(
            name: "OPSDesignKit",
            resources: [
                .process("Resources")
            ]
        ),
        .testTarget(
            name: "OPSDesignKitTests",
            dependencies: ["OPSDesignKit"]
        )
    ]
)
```

- [ ] **Step 2: Move token source into package**

Use `git mv OPS/Styles/OPSStyle.swift Packages/OPSDesignKit/Sources/OPSDesignKit/OPSStyle.swift`.

Then add this marker file:

```swift
public enum OPSDesignKitModule {
    public static let version = "1"
}
```

- [ ] **Step 3: Adjust package token visibility**

In the moved `OPSStyle.swift`, make the token namespace public:

```swift
public enum OPSStyle { ... }
```

For nested token enums and every token used outside the package, set `public` access. Keep token values sourced from asset names, semantic aliases, and existing token constants. Do not add literal UI styles in DeckKit or OPSDecks to compensate for access errors.

- [ ] **Step 4: Copy required color assets into package resources**

Copy the color asset sets referenced by `OPSStyle` from `OPS/Assets.xcassets/Colors` into:

```text
Packages/OPSDesignKit/Resources/Colors.xcassets
```

If `Color("TokenName")` fails to resolve from package resources, change the implementation inside `OPSStyle` to use a package bundle helper:

```swift
private enum OPSDesignBundle {
    static let bundle = Bundle.module
}

static let opsAccent = Color("AccentPrimary", bundle: OPSDesignBundle.bundle)
```

This helper is allowed only inside `OPSStyle.swift`; call sites must still use tokens.

- [ ] **Step 5: Re-export for existing OPS code if needed**

If broad import churn would make this task too large, create `OPS/Styles/OPSStyle.swift` as a short re-export shim:

```swift
@_exported import OPSDesignKit
```

Only use this shim for the transition. New package/app code must import `OPSDesignKit` directly.

- [ ] **Step 6: Wire local package into Xcode**

Add local package `Packages/OPSDesignKit` to `OPS.xcodeproj` and add product `OPSDesignKit` to the `OPS` and `OPSTests` targets. Because this project uses file-system-synchronized groups, keep source files in the package folder and do not duplicate them under `OPS/`.

- [ ] **Step 7: Build and scan**

```bash
xcodebuild -project OPS.xcodeproj -scheme OPS -destination 'generic/platform=iOS Simulator' -derivedDataPath /private/tmp/ops-ios-derived CODE_SIGNING_ALLOWED=NO build
scripts/verify-ops-decks-style-tokens.sh .
```

Expected: build succeeds and scanner emits no hardcoded styling values.

- [ ] **Step 8: Commit**

```bash
git add Packages/OPSDesignKit OPS/Styles/OPSStyle.swift OPS.xcodeproj/project.pbxproj scripts/verify-ops-decks-style-tokens.sh
git commit -m "feat: extract OPS design tokens"
```

---

### Task 5: Extract DeckKit Package Without Changing Behavior

**Files:**
- Create: `Packages/DeckKit/Package.swift`
- Move: `OPS/DeckBuilder/**` to `Packages/DeckKit/Sources/DeckKit/**`
- Create: `OPS/DeckBuilder/DeckBuilderHostView.swift`
- Modify: imports across moved DeckKit files
- Modify: `OPS.xcodeproj/project.pbxproj`
- Test: existing DeckBuilder tests

**Interfaces:**
- Consumes: app-agnostic runtime seams from Task 3 and `OPSDesignKit` from Task 4.
- Produces: `DeckKit` package product imported by OPS and OPSDecks.

- [ ] **Step 1: Create package manifest**

Create `Packages/DeckKit/Package.swift`:

```swift
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "DeckKit",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(name: "DeckKit", targets: ["DeckKit"])
    ],
    dependencies: [
        .package(path: "../OPSDesignKit")
    ],
    targets: [
        .target(
            name: "DeckKit",
            dependencies: ["OPSDesignKit"],
            resources: []
        ),
        .testTarget(
            name: "DeckKitTests",
            dependencies: ["DeckKit"]
        )
    ]
)
```

- [ ] **Step 2: Move DeckBuilder sources**

```bash
mkdir -p Packages/DeckKit/Sources/DeckKit
git mv OPS/DeckBuilder/* Packages/DeckKit/Sources/DeckKit/
mkdir -p OPS/DeckBuilder
```

- [ ] **Step 3: Update imports**

In moved files:

```swift
import OPSDesignKit
```

Remove direct dependencies on OPS-only types from DeckKit sources. If a moved file references `TaskType`, `Estimate`, `SyncEngine`, `DataController`, `CatalogRepository`, or notification services, route the dependency through a runtime protocol or move that feature behind an OPS-only adapter.

- [ ] **Step 4: Add OPS compatibility host**

Create `OPS/DeckBuilder/DeckBuilderHostView.swift`:

```swift
import SwiftUI
import SwiftData
import DeckKit

struct DeckBuilderHostView: View {
    let deckDesign: DeckDesign
    let modelContext: ModelContext
    let syncEngine: SyncEngine?
    let projectName: String?

    var body: some View {
        DeckBuilderView(
            deckDesign: deckDesign,
            runtime: OPSDeckRuntimeFactory.make(
                deckDesign: deckDesign,
                modelContext: modelContext,
                syncEngine: syncEngine,
                projectName: projectName
            )
        )
    }
}
```

Keep existing call sites compiling either by preserving the old `DeckBuilderView` initializer in DeckKit or by changing call sites to `DeckBuilderHostView`.

- [ ] **Step 5: Wire local package into Xcode**

Add local package `Packages/DeckKit` to `OPS.xcodeproj` and add product `DeckKit` to `OPS` and `OPSTests`.

- [ ] **Step 6: Move package-safe tests**

Move pure engine/model tests into `Packages/DeckKit/Tests/DeckKitTests` only when they no longer rely on OPS app models. Keep integration tests in `OPSTests`.

Initial package-safe candidates:
- `AccuracyModelTests`
- `PolygonMathTests`
- `DimensionEngineTests`
- `StairCalculatorTests`
- `VinylCutListEngineTests`
- `DeckDrawingFutureBlocksTests`

- [ ] **Step 7: Run tests**

```bash
swift test --package-path Packages/DeckKit
xcodebuild test -project OPS.xcodeproj -scheme OPS -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:OPSTests/DeckBuilderRegressionTests -derivedDataPath /private/tmp/ops-ios-tests CODE_SIGNING_ALLOWED=NO
```

Expected: package tests pass and OPS integration tests pass.

- [ ] **Step 8: Run style-token scanner**

```bash
scripts/verify-ops-decks-style-tokens.sh .
```

Expected: pass. Any match under `Packages/DeckKit/Sources` must be replaced with an `OPSStyle` token or moved into material/catalog data.

- [ ] **Step 9: Commit**

```bash
git add Packages/DeckKit OPS/DeckBuilder OPS.xcodeproj/project.pbxproj OPS.xcodeproj/xcshareddata/xcschemes OPSTests
git commit -m "feat: extract deck designer package"
```

---

### Task 6: Add OPS Decks App Target Shell

**Files:**
- Create: `OPSDecks/OPSDecksApp.swift`
- Create: `OPSDecks/OPSDecksCopy.swift`
- Create: `OPSDecks/OPSDecksRootView.swift`
- Create: `OPSDecks/OPSDecksRuntimeFactory.swift`
- Modify: `OPS.xcodeproj/project.pbxproj`
- Create: `OPS.xcodeproj/xcshareddata/xcschemes/OPSDecks.xcscheme`
- Test: standalone target build

**Interfaces:**
- Consumes: `DeckKit`, `OPSDesignKit`, `DeckDesign`, SwiftData schema, and standalone runtime factory.
- Produces: a second app target with bundle id `co.opsapp.ops.decks`.

- [ ] **Step 1: Create standalone app entry**

Create `OPSDecks/OPSDecksApp.swift`:

```swift
import SwiftUI
import SwiftData
import DeckKit
import OPSDesignKit

@main
struct OPSDecksApp: App {
    var body: some Scene {
        WindowGroup {
            OPSDecksRootView()
                .preferredColorScheme(.dark)
        }
    }
}
```

- [ ] **Step 2: Create minimal root**

Create `OPSDecks/OPSDecksCopy.swift`:

```swift
import Foundation

enum OPSDecksCopy {
    static let shellTitle = String(localized: "OPS Decks")
    static let shellSubtitle = String(localized: "Draw the deck. Build the quote. Keep the job moving.")
}
```

Create `OPSDecks/OPSDecksRootView.swift`:

```swift
import SwiftUI
import DeckKit
import OPSDesignKit

struct OPSDecksRootView: View {
    var body: some View {
        ZStack {
            OPSStyle.Colors.background.ignoresSafeArea()
            VStack(spacing: OPSStyle.Layout.spacing4) {
                Text(OPSDecksCopy.shellTitle)
                    .font(OPSStyle.Typography.sectionTitle)
                    .foregroundColor(OPSStyle.Colors.text)
                Text(OPSDecksCopy.shellSubtitle)
                    .font(OPSStyle.Typography.caption)
                    .foregroundColor(OPSStyle.Colors.text3)
            }
            .padding(OPSStyle.Layout.spacing4)
        }
    }
}
```

Do not add inline UI strings to the view. Keep standalone target copy in `OPSDecksCopy.swift` or localization resources so copy review remains auditable.

- [ ] **Step 3: Create runtime factory stub**

Create `OPSDecks/OPSDecksRuntimeFactory.swift`:

```swift
import Foundation
import DeckKit

enum OPSDecksRuntimeFactory {
    static func make(companyId: String, projectName: String? = nil) -> DeckRuntime {
        DeckRuntime(
            context: DeckRuntimeContext(
                companyId: companyId,
                projectId: nil,
                projectName: projectName,
                appSurface: .opsDecks
            ),
            store: nil
        )
    }
}
```

- [ ] **Step 4: Add target to Xcode**

Add app target `OPSDecks` with:

```text
PRODUCT_BUNDLE_IDENTIFIER = co.opsapp.ops.decks
INFOPLIST_KEY_CFBundleDisplayName = OPS Decks
IPHONEOS_DEPLOYMENT_TARGET = 17.6
SUPPORTED_PLATFORMS = iphoneos iphonesimulator
DEVELOPMENT_TEAM = X47H96M34K
```

Add package products:
- `DeckKit`
- `OPSDesignKit`
- Firebase Auth packages only when Sign in with Apple/Firebase wiring lands in Task 8.
- RevenueCat package only when entitlement service lands in Task 9.

- [ ] **Step 5: Create shared scheme**

Create `OPS.xcodeproj/xcshareddata/xcschemes/OPSDecks.xcscheme` by duplicating the OPS scheme and changing buildable target references to the `OPSDecks` target/product.

- [ ] **Step 6: Build standalone shell**

```bash
xcodebuild -project OPS.xcodeproj -scheme OPSDecks -destination 'generic/platform=iOS Simulator' -derivedDataPath /private/tmp/ops-decks-derived CODE_SIGNING_ALLOWED=NO build
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 7: Run style-token scanner**

```bash
scripts/verify-ops-decks-style-tokens.sh .
```

Expected: pass.

- [ ] **Step 8: Commit**

```bash
git add OPSDecks OPS.xcodeproj/project.pbxproj OPS.xcodeproj/xcshareddata/xcschemes/OPSDecks.xcscheme
git commit -m "feat: add OPS Decks app target"
```

---

### Task 7: Company-of-One Backend Contract and Client Payloads

**Files:**
- Create: `docs/superpowers/specs/2026-06-25-ops-decks-phase-1-backend-contract.md`
- Create: `OPSDecks/DecksCompanyProvisioningService.swift`
- Create: `OPSTests/OPSDecks/DecksProvisioningPayloadTests.swift`
- Modify: `ops-software-bible` section covering deck subscriptions and standalone provisioning in the same implementation session

**Interfaces:**
- Consumes: Firebase user id, email, display name.
- Produces: provisioning request/response contract for ops-web/Supabase endpoint.

- [ ] **Step 1: Write backend contract doc**

Create `docs/superpowers/specs/2026-06-25-ops-decks-phase-1-backend-contract.md` with these exact sections:

```markdown
# OPS Decks Phase 1 Backend Contract

## Provision Deck Company

Endpoint owner: ops-web server API.

Request:
- firebase_uid: string
- email: string
- display_name: string?
- source_app: "ops_decks"

Response:
- company_id: uuid
- user_id: uuid
- role: "admin"
- subscription_plan: "decks"

Database effects:
- Create one `companies` row for the deck-only company.
- Create or link one `users` row with `firebase_uid`/`auth_id` and `company_id`.
- Do not write deck entitlement into `companies.subscription_status`.
- Set a clear deck-only origin field or `subscription_plan = 'decks'` so the OPS app can route to upgrade instead of treating this as a lapsed OPS subscription.

## Deck Subscription Mirror

Table: deck_subscriptions

Columns:
- id uuid primary key
- company_id uuid not null references companies(id)
- revenuecat_customer_id text not null
- entitlement text not null
- product_id text not null
- status text not null
- store text not null
- expires_at timestamptz
- last_event_at timestamptz not null
- created_at timestamptz not null default now()
- updated_at timestamptz not null default now()

RLS:
- company-scoped read for the owning company.
- server-only writes through the RevenueCat webhook.

## Account Deletion

Request:
- firebase_uid: string
- company_id: uuid

Effects:
- Soft-delete deck designs.
- Delete or anonymize the deck-only company/user according to OPS account deletion policy.
- Return deletion receipt id and timestamp.
```

- [ ] **Step 2: Write payload tests**

Create `OPSTests/OPSDecks/DecksProvisioningPayloadTests.swift`:

```swift
import XCTest
@testable import OPS

final class DecksProvisioningPayloadTests: XCTestCase {
    func testProvisioningPayloadUsesDeckOnlySourceAndDoesNotContainOPSSubscriptionState() throws {
        let request = DecksCompanyProvisioningRequest(
            firebaseUID: "firebase-123",
            email: "deck@example.com",
            displayName: "Deck Operator"
        )

        let data = try JSONEncoder().encode(request)
        let json = try XCTUnwrap(String(data: data, encoding: .utf8))

        XCTAssertTrue(json.contains("\"source_app\":\"ops_decks\""))
        XCTAssertFalse(json.contains("subscription_status"))
        XCTAssertFalse(json.contains("trial_end_date"))
    }
}
```

- [ ] **Step 3: Add client DTOs**

Create `OPSDecks/DecksCompanyProvisioningService.swift`:

```swift
import Foundation

struct DecksCompanyProvisioningRequest: Encodable, Equatable {
    let firebaseUID: String
    let email: String
    let displayName: String?
    let sourceApp: String = "ops_decks"

    enum CodingKeys: String, CodingKey {
        case firebaseUID = "firebase_uid"
        case email
        case displayName = "display_name"
        case sourceApp = "source_app"
    }
}

struct DecksCompanyProvisioningResponse: Decodable, Equatable {
    let companyId: String
    let userId: String
    let role: String
    let subscriptionPlan: String

    enum CodingKeys: String, CodingKey {
        case companyId = "company_id"
        case userId = "user_id"
        case role
        case subscriptionPlan = "subscription_plan"
    }
}
```

- [ ] **Step 4: Run tests**

```bash
xcodebuild test -project OPS.xcodeproj -scheme OPS -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:OPSTests/DecksProvisioningPayloadTests -derivedDataPath /private/tmp/ops-ios-tests CODE_SIGNING_ALLOWED=NO
```

Expected: pass.

- [ ] **Step 5: Commit**

```bash
git add docs/superpowers/specs/2026-06-25-ops-decks-phase-1-backend-contract.md OPSDecks/DecksCompanyProvisioningService.swift OPSTests/OPSDecks/DecksProvisioningPayloadTests.swift
git commit -m "feat: define OPS Decks provisioning contract"
```

---

### Task 8: One-Deck Entitlement Gate

**Files:**
- Create: `OPSDecks/DecksEntitlementService.swift`
- Create: `OPSTests/OPSDecks/DecksEntitlementGateTests.swift`
- Modify: `OPSDecks/OPSDecksRootView.swift`

**Interfaces:**
- Consumes: saved deck count and `deck_pro` entitlement.
- Produces: deterministic create/save decision: allow first deck, require Pro for second saved deck.

- [ ] **Step 1: Write gate tests**

Create `OPSTests/OPSDecks/DecksEntitlementGateTests.swift`:

```swift
import XCTest
@testable import OPS

final class DecksEntitlementGateTests: XCTestCase {
    func testFreeUserCanSaveFirstDeck() {
        let gate = DecksEntitlementGate(entitlement: .free(savedDeckLimit: 1))
        XCTAssertEqual(gate.decision(savedDeckCount: 0), .allowSave)
    }

    func testFreeUserCannotSaveSecondDeck() {
        let gate = DecksEntitlementGate(entitlement: .free(savedDeckLimit: 1))
        XCTAssertEqual(gate.decision(savedDeckCount: 1), .requiresPro)
    }

    func testProUserCanSaveUnlimitedDecks() {
        let gate = DecksEntitlementGate(entitlement: .pro)
        XCTAssertEqual(gate.decision(savedDeckCount: 99), .allowSave)
    }
}
```

- [ ] **Step 2: Add entitlement gate model**

Create `OPSDecks/DecksEntitlementService.swift`:

```swift
import Foundation

enum DecksEntitlement: Equatable {
    case free(savedDeckLimit: Int)
    case pro
}

enum DeckSaveDecision: Equatable {
    case allowSave
    case requiresPro
}

struct DecksEntitlementGate {
    let entitlement: DecksEntitlement

    func decision(savedDeckCount: Int) -> DeckSaveDecision {
        switch entitlement {
        case .pro:
            return .allowSave
        case .free(let limit):
            return savedDeckCount < limit ? .allowSave : .requiresPro
        }
    }
}
```

- [ ] **Step 3: Wire root surface to gate state**

In `OPSDecksRootView`, create a simple state machine:

```swift
enum OPSDecksCreateState: Equatable {
    case canCreate
    case lockedAtFreeLimit
}
```

Use `OPSStyle` tokens for every visual state. Do not add literal colors, spacing, fonts, or radii.

- [ ] **Step 4: Run tests and scanner**

```bash
xcodebuild test -project OPS.xcodeproj -scheme OPS -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:OPSTests/DecksEntitlementGateTests -derivedDataPath /private/tmp/ops-ios-tests CODE_SIGNING_ALLOWED=NO
scripts/verify-ops-decks-style-tokens.sh .
```

Expected: tests pass and scanner passes.

- [ ] **Step 5: Commit**

```bash
git add OPSDecks/DecksEntitlementService.swift OPSDecks/OPSDecksRootView.swift OPSTests/OPSDecks/DecksEntitlementGateTests.swift
git commit -m "feat: add OPS Decks entitlement gate"
```

---

### Task 9: Account Deletion and Upgrade Surface Contracts

**Files:**
- Create: `OPSDecks/DecksAccountDeletionService.swift`
- Create: `OPSDecks/DecksUpgradeSurface.swift`
- Modify: `OPSDecks/OPSDecksCopy.swift`
- Create: `OPSTests/OPSDecks/DecksAccountDeletionPayloadTests.swift`
- Modify: `OPSDecks/OPSDecksRootView.swift`

**Interfaces:**
- Consumes: company id and firebase uid.
- Produces: account deletion payload and minimal upgrade surface that preserves the same account/company.

- [ ] **Step 1: Write deletion payload test**

Create `OPSTests/OPSDecks/DecksAccountDeletionPayloadTests.swift`:

```swift
import XCTest
@testable import OPS

final class DecksAccountDeletionPayloadTests: XCTestCase {
    func testDeletionPayloadContainsFirebaseAndCompanyOnly() throws {
        let request = DecksAccountDeletionRequest(firebaseUID: "firebase-123", companyId: "company-123")
        let data = try JSONEncoder().encode(request)
        let json = try XCTUnwrap(String(data: data, encoding: .utf8))

        XCTAssertTrue(json.contains("\"firebase_uid\":\"firebase-123\""))
        XCTAssertTrue(json.contains("\"company_id\":\"company-123\""))
        XCTAssertFalse(json.contains("subscription_status"))
    }
}
```

- [ ] **Step 2: Add deletion DTO**

Create `OPSDecks/DecksAccountDeletionService.swift`:

```swift
import Foundation

struct DecksAccountDeletionRequest: Encodable, Equatable {
    let firebaseUID: String
    let companyId: String

    enum CodingKeys: String, CodingKey {
        case firebaseUID = "firebase_uid"
        case companyId = "company_id"
    }
}

struct DecksAccountDeletionReceipt: Decodable, Equatable {
    let receiptId: String
    let deletedAt: Date

    enum CodingKeys: String, CodingKey {
        case receiptId = "receipt_id"
        case deletedAt = "deleted_at"
    }
}
```

- [ ] **Step 3: Add upgrade surface with tokenized styling only**

Extend `OPSDecks/OPSDecksCopy.swift`:

```swift
enum OPSDecksUpgradeCopy {
    static let title = String(localized: "Bring this into OPS")
    static let body = String(localized: "Turn the deck into a live job without redrawing it.")
}
```

Create `OPSDecks/DecksUpgradeSurface.swift`:

```swift
import SwiftUI
import OPSDesignKit

struct DecksUpgradeSurface: View {
    var body: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing3) {
            Text(OPSDecksUpgradeCopy.title)
                .font(OPSStyle.Typography.sectionTitle)
                .foregroundColor(OPSStyle.Colors.text)
            Text(OPSDecksUpgradeCopy.body)
                .font(OPSStyle.Typography.caption)
                .foregroundColor(OPSStyle.Colors.text3)
        }
        .padding(OPSStyle.Layout.spacing4)
        .background(OPSStyle.Colors.glassApprox)
        .overlay(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.panelRadius)
                .stroke(OPSStyle.Colors.glassBorder, lineWidth: OPSStyle.Layout.Border.standard)
        )
        .clipShape(RoundedRectangle(cornerRadius: OPSStyle.Layout.panelRadius))
    }
}
```

Do not place copy literals in `DecksUpgradeSurface`. Keep copy in `OPSDecksCopy.swift` or localization resources.

- [ ] **Step 4: Run tests and scanner**

```bash
xcodebuild test -project OPS.xcodeproj -scheme OPS -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:OPSTests/DecksAccountDeletionPayloadTests -derivedDataPath /private/tmp/ops-ios-tests CODE_SIGNING_ALLOWED=NO
scripts/verify-ops-decks-style-tokens.sh .
```

Expected: tests pass and scanner passes.

- [ ] **Step 5: Commit**

```bash
git add OPSDecks/DecksAccountDeletionService.swift OPSDecks/DecksUpgradeSurface.swift OPSDecks/OPSDecksCopy.swift OPSTests/OPSDecks/DecksAccountDeletionPayloadTests.swift
git commit -m "feat: add OPS Decks account lifecycle contracts"
```

---

### Task 10: Final Integration Verification

**Files:**
- Modify: `docs/superpowers/specs/2026-06-24-ops-decks-standalone-app-design.md` only if implementation changes the Phase 1 contract.
- Modify: `ops-software-bible` relevant iOS/deck sections.
- Test: build, focused tests, package tests, style-token scanner.

**Interfaces:**
- Consumes: all previous tasks.
- Produces: verified Phase 1 foundation branch ready for review.

- [ ] **Step 1: Run style scanner**

```bash
scripts/verify-ops-decks-style-tokens.sh .
```

Expected: exit 0. Any match is a hard blocker.

- [ ] **Step 2: Run package tests**

```bash
swift test --package-path Packages/OPSDesignKit
swift test --package-path Packages/DeckKit
```

Expected: both pass.

- [ ] **Step 3: Run focused xcode tests**

```bash
xcodebuild test -project OPS.xcodeproj -scheme OPS -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:OPSTests/DeckBuilderRegressionTests -only-testing:OPSTests/DeckDrawingFutureBlocksTests -only-testing:OPSTests/DeckRuntimeStoreTests -only-testing:OPSTests/DecksEntitlementGateTests -only-testing:OPSTests/DecksProvisioningPayloadTests -only-testing:OPSTests/DecksAccountDeletionPayloadTests -derivedDataPath /private/tmp/ops-ios-tests CODE_SIGNING_ALLOWED=NO
```

Expected: all selected tests pass.

- [ ] **Step 4: Build OPS and OPS Decks**

```bash
xcodebuild -project OPS.xcodeproj -scheme OPS -destination 'generic/platform=iOS Simulator' -derivedDataPath /private/tmp/ops-ios-derived CODE_SIGNING_ALLOWED=NO build
xcodebuild -project OPS.xcodeproj -scheme OPSDecks -destination 'generic/platform=iOS Simulator' -derivedDataPath /private/tmp/ops-decks-derived CODE_SIGNING_ALLOWED=NO build
```

Expected: both builds end with `** BUILD SUCCEEDED **`.

- [ ] **Step 5: Confirm no broad unrelated edits**

```bash
git status --short
git diff --stat
```

Expected: changes are limited to Phase 1 files, package extraction, project wiring, tests, and docs listed in this plan.

- [ ] **Step 6: Update bible**

Update the relevant OPS Software Bible sections to reflect:
- OPS Decks app target exists.
- `DeckKit` and `OPSDesignKit` are shared packages.
- `drawing_data` preserves unknown future blocks.
- `deck_subscriptions` is the deck-only entitlement mirror contract.
- Styling for OPS Decks/DeckKit must flow through OPSDesignKit tokens.

- [ ] **Step 7: Commit final documentation updates**

```bash
git add docs/superpowers/specs ops-software-bible Packages OPS OPSDecks OPSTests OPS.xcodeproj scripts
git commit -m "docs: document OPS Decks phase 1 foundation"
```

---

## Self-Review Checklist

- Spec coverage: Phase 1 carve-out, shared packages, standalone target, company-of-one path, one-deck gate, account deletion, upgrade surface, offline/local-first save path, and future schema preservation are covered.
- Deferred feature coverage: structural engineering, zoning resolver, live code overlay, permit engine, advanced railing/stairs, roof/openings, and realistic rendering are preserved as future schema/data blocks but not implemented here.
- Token coverage: every task that adds UI code runs `scripts/verify-ops-decks-style-tokens.sh`; token hardcoding is a hard blocker.
- Test coverage: every behavior change has a focused test before implementation plus build/package verification at the end.
- Dirty checkout protection: implementation starts in an isolated worktree and does not revert unrelated files in the main `ops-ios` checkout.
