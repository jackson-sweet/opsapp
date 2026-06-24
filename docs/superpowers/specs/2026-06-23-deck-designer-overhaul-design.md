# Deck Designer — Bug Fixes & Feature Overhaul

**Date:** 2026-06-23
**Status:** Approved direction; Drop 1 spec'd for implementation
**Surface:** iOS app — deck designer (3D viewer in the project-details Deck tab + the 2D designer/canvas)

---

## 1. Context & goals

The deck designer spans a 2D drawing canvas, a JSON-serialized geometry model, and a SceneKit 3D viewer. A batch of issues — some true bugs, some feature gaps — were reported across both the 3D viewer and the 2D designer. This document captures the full scope, the decisions made with Jackson, and a sequenced delivery plan. It then fully specifies **Drop 1** (the no-decision, no-schema fixes), which ships first. Drops 2–6 are captured at roadmap level here and will each get their own spec → plan → implementation cycle so nothing is lost and no single change becomes unreviewable.

**Nothing is deferred out of scope.** Everything reported is being built. Sequencing is for shippability and verification, not for dropping work. The only thing intentionally pushed to a fast-follow (Jackson's call) is the *manual* structural-layer editing UI, which lands right after the structural auto-draw engine it depends on.

---

## 2. Architecture overview

Three stages, one source of truth:

- **Data model (spine).** `DeckDesign` (`OPS/DataModels/DeckDesign.swift`) is a SwiftData model synced to Supabase: `id`, `projectId?`, `companyId`, `title`, `drawingDataJSON` (serialized blob), plus sync fields (`needsSync`, `lastSyncedAt`, `syncPriority`, `deletedAt`, `createdAt`, `updatedAt`). The blob deserializes to `DeckDrawingData` (`OPS/DeckBuilder/Models/DeckGeometry.swift`): `vertices[]`, `edges[]`, `levels[]`, `levelConnections[]`, `surfaces[]`, plus computed `isClosed`, `detectedSurfaces`, `hasAnyClosedSurface`. Atomic types (`DeckVertex`, `DeckEdge`, `DeckLevel`, `RailingConfig`, `StairConfig`, `EdgeType`, `HouseEdgeMaterial`, `AssignedItem`) all live in `DeckGeometry.swift`.
- **2D canvas.** `OPS/Views/Components/Project/Tabs/DeckTab2DView.swift` (read-only viewer in the project tab) and the full editor `OPS/DeckBuilder/Views/DeckCanvasView.swift`. The radial material/feature selector is `AssignmentWheelView.swift` (fixed 8 slots); material sub-picker is `MaterialPickerSheet.swift`; built-in catalog is `BuiltInMaterial.swift`.
- **2D→3D derivation (the hinge).** The 3D viewer never fills from raw edges — it reads **detected surfaces**. `SurfaceDetector.detect()` runs a planar-graph face-walk (prunes degree-≤1 vertices, walks faces, drops the outer face, dedupes). `DeckSurfaceEdgeResolver` decides which edges carry 3D features (rim joists, house edges, railings, stairs).
- **3D viewer.** `DeckScene3DView.swift` hosts the `SCNView` (`allowsCameraControl = true`). `DeckSceneBuilder.swift` builds the scene (lights, camera, ground, per-level surfaces, rim joists, posts, railings, stairs, level connections). Meshes from `DeckMeshGenerator.swift`. The info **badges** are a SwiftUI overlay in `DeckTabView.swift` (`floatingDesignInfo`), not SceneKit nodes. Estimate projection is `ComponentEmitter.swift` → `components[]`, consumed by ops-web's estimate adapter.

---

## 3. Decisions (locked with Jackson, 2026-06-23)

| Topic | Decision |
|-------|----------|
| House edge "types" | Let the user pick the **cladding / house type** when tagging a house edge (stucco / Hardie / brick / stone / vinyl / parapet). These already exist in `HouseEdgeMaterial` but aren't selectable from the wheel. Surface them; expose as configurable wheel items. |
| Gates | First-class: **width + swing direction + hinge side**. Swing arc in 2D, gap-with-posts in 3D. |
| Materials wheel config | **Per-user** wheel layout, stored on-device. A **MORE** slot opens the full catalog to choose what's on the wheel. |
| Structural framing | **Auto-draw, zero input.** App derives BCBC-typical framing from deck size/height. No user inputs in v1. |
| Manual structural layer | Fast-follow after the auto-draw engine. Includes **live code-violation flags** (cantilever too long, joist spacing too wide, undersized joists, beam/span too long, post spacing too wide, footing too shallow) driven by the same rules engine — shown inline on the offending member + a roll-up count, not the global notification rail. |
| Deck name | Read-only **mirror of the parent project name**. The standalone editable title is retired from the UI; the stored column is kept for back-compat. |
| 3D measure selection | Independent per-tab (2D and 3D don't share selection state). |

---

## 4. Delivery roadmap

Each drop is an independently-shippable unit, atomic commits, sequenced for value × risk.

| # | Drop | Scope | Schema |
|---|------|-------|--------|
| **1** | **3D fixes + render reliability** | Remove shadows · level-connection stairs honor flip (+ Codable round-trip test + single-edge visual parity check) · fade badges during pan/zoom · "close the shape" robustness + actionable hint (the "3D doesn't work" cause) · deck name → project name | **None** |
| 2 | House-edge cladding in wheel | Surface `HouseEdgeMaterial` choices when assigning a house edge | None |
| 3 | Configurable wheel + MORE | Per-user wheel layout (on-device prefs), MORE → full catalog picker | Small (user prefs) |
| 4 | Gates | `GateConfig` on `DeckEdge` (width/swing/hinge); 2D arc; 3D gap+posts; migrate legacy `isGate`; keep `ComponentEmitter` footage subtraction | Yes (in blob) |
| 5 | 3D measure tools | SceneKit hit-testing + readout parity with 2D; independent selection | None |
| 6 | BCBC structural auto-framing | One rules engine, two consumers: **auto-draw** compliant framing + **live validation** flags. Replaces hardcoded posts/beams/joists/footings. Feeds `ComponentEmitter`/ops-web. Manual-override UI is its fast-follow. | Yes (largest) |

---

## 5. Drop 1 — detailed spec

Cohesive theme: **the 3D viewer looks right and renders reliably.** No schema change, no migration, no product decisions outstanding. The full 6-drop deck overhaul is a large multi-step initiative, so per branch policy it gets a dedicated branch: **`feat/ios-deck-designer`**, branched from current `main`/HEAD (carrying none of the sibling WIP in the working tree — stage only deck-designer files). All drops land here as atomic commits, one per item, PR'd in stages. Implementation should run in an isolated git worktree to avoid colliding with the parallel sessions touching `DeckSceneBuilder.swift`/`DeckGeometry.swift`.

### 1A — Remove shadows
- **Current:** `DeckSceneBuilder.addLighting(to:)` — `directionalLight.castsShadow = true` (`DeckSceneBuilder.swift:1286`), `shadowMode = .deferred` (1287), `shadowRadius = 3` (1288), `shadowMapSize = 1024×1024` (1289). One ambient + one directional light; no other shadow casters.
- **Change:** Set `castsShadow = false` and delete lines 1287–1289. Confirm no ground-plane shadow-receiver config elsewhere (`addGroundPlane`).
- **Verify:** Build for device; snapshot the 3D scene — geometry reads cleanly with no cast shadow on the ground plane or between members.
- **Risk:** none. Zero data impact.

### 1B — Level-connection stairs honor flip direction
- **Root cause (confirmed):** the per-edge stair path `buildStairs` correctly inverts the outward perpendicular on `stairConfig.flipDirection` (`DeckSceneBuilder.swift:883–884`), but the **level-connection** path `buildLevelConnection` hardcodes the perpendicular with no flip check (`DeckSceneBuilder.swift:1111–1112`: `let nx = -edgeDz/edgeLen; let nz = edgeDx/edgeLen`). So stairs that connect two deck levels always render on the default side regardless of the toggle.
- **Change:** mirror the per-edge form exactly:
  ```swift
  let rawN = (x: -edgeDz / edgeLen, z: edgeDx / edgeLen)
  let nx = connection.stairConfig.flipDirection ? -rawN.x : rawN.x
  let nz = connection.stairConfig.flipDirection ? -rawN.z : rawN.z
  ```
  Keep `tx/tz/midX/midZ` as-is.
- **Defensive:** add a `StairConfig` Codable round-trip unit test (encode `flipDirection = true` → decode → assert `true`) plus a legacy-JSON fixture (missing key → defaults `false`). `StairConfig` uses a custom `init(from:)` with `decodeLegacyBoolIfPresent(forKey: .flipDirection)` (`DeckGeometry.swift:510`) and synthesized encode over `CodingKeys` including `flipDirection` (462–466) — the test locks the round-trip so a future key rename can't silently swallow the toggle.
- **Single-edge parity check (the "often backwards" report):** the per-edge code path is correct, but the user reports single stairs *also* look backwards. During implementation, **visually verify end-to-end**: toggle flip in `StairConfigView` → confirm the 3D perimeter stair lands on the opposite side, and that the 2D canvas (`DeckStairRenderPlanner`) and 3D agree. If the visual check shows divergence (e.g. the toggle writes a field the renderer doesn't read, or 2D/3D disagree on the default side), fix that in this drop. Do **not** close 1B on the code fix alone — the report says "often backwards," which requires observed confirmation (systematic-debugging + visual verification).
- **Verify:** unit test green; visual confirmation of both level-connection and single-edge flips.
- **Risk:** isolated to stair placement; no data change.

### 1C — Fade badges during pan/zoom
- **Current:** badges are a SwiftUI overlay pinned `.topLeading` in `DeckTabView.floatingDesignInfo` (`DeckTabView.swift:96–101, 114–190`), `.allowsHitTesting(false)`. The `SCNView` (`DeckScene3DView.swift`) uses `allowsCameraControl = true` with SceneKit's internal gesture recognizers — no exposed interaction state to drive a fade.
- **Change:**
  1. Surface camera-interaction state. In `DeckScene3DView.makeUIView`, attach a `UIPanGestureRecognizer` and `UIPinchGestureRecognizer` to the `SCNView`, with the `Coordinator` as their delegate returning `true` from `gestureRecognizer(_:shouldRecognizeSimultaneouslyWith:)` so they coexist with SceneKit's built-in camera control. On `.began`/`.changed` → interacting `true`; on `.ended`/`.cancelled`/`.failed` → interacting `false` after a short trailing debounce (~0.25s) to avoid flicker between gesture phases.
  2. Publish interaction state through the existing `Scene3DController` (already an `ObservableObject` shared between the 3D view and its parent) — add `@Published var isInteracting: Bool = false`.
  3. **Wiring:** hoist the `Scene3DController` to `DeckTabView` as `@StateObject` and pass it down through `DeckTab3DView` → `DeckScene3DView` (currently `DeckTab3DView(drawingData:)` owns/creates it; the badges live one level up in `DeckTabView`, so the controller must be observable there). Apply `.opacity(controller.isInteracting ? 0 : 1)` to `floatingDesignInfo`, animated with the OPS easing (`OPSStyle.Animation.fast`/`standard`). Honor `@Environment(\.accessibilityReduceMotion)` — when reduced, skip the fade (badges stay visible).
- **Note on motion budget:** `levelChipView` is documented as "static by design / ambient reference chrome." Fading on *active camera manipulation* is consistent with the budget — the motion communicates a state change (you're moving the camera), and it reverses instantly on release. Reduced-motion users opt out.
- **Verify:** on-device/simulator — badges fade out smoothly while panning/pinching the 3D scene and return on release; reduced-motion keeps them visible.
- **Risk:** low. UI-only; the simultaneous-recognition delegate must not steal gestures from SceneKit's camera control (verify camera still pans/zooms normally).

### 1D — "3D doesn't work" → render reliability
- **Current state (corrected from initial report):** the 3D tab is **not** silently empty. `DeckTabView` gates on `design.drawingData.hasAnyClosedSurface`; when false it shows `incompleteDesignMessage` (`DeckTabView.swift:82–86, 298`). The single-level `DeckSceneBuilder` path also guards `!detected.isEmpty || drawingData.isClosed` (`DeckSceneBuilder.swift:145`). So the real problem is twofold:
  1. **Shapes the user believes are closed don't register as closed.** `isClosed` (`DeckGeometry.swift:790–826`) requires *every* vertex to have exactly 2 neighbors and a single closed walk; `SurfaceDetector` prunes degree-≤1 vertices. Likely culprits: two endpoint vertices that visually coincide but are distinct ids (loop never actually joined), a stray edge/vertex creating a degree-3 node, or snap tolerance failing to merge on close. **This is investigative** — confirm the actual failure with a repro before fixing (systematic-debugging).
  2. **The message is generic** — it doesn't tell the user *what* is wrong or *where*, and it only appears in the 3D tab.
- **Deliverables:**
  - **Robust closing:** snap-to-close in the 2D editor — when a new/dragged vertex lands within snap tolerance of an existing vertex, merge/join so the loop actually closes; and/or an explicit "close shape" affordance that connects the two open endpoints. (Investigate `DeckCanvasView` + `SnapEngine` for the current closing behavior first.)
  - **Actionable feedback:** in the 2D canvas, highlight the open endpoint(s) and show a hint when the perimeter isn't closed; make the 3D `incompleteDesignMessage` name the specific reason and point back to 2D. Copy via `ops-copywriter` (terse, tactical — e.g. "2 open ends — connect them to preview in 3D").
  - **Audit:** confirm `SurfaceDetector` pruning and `isClosed`/`hasAnyClosedSurface` stay consistent (they read pruned vs original vertex sets and can diverge); verify the `SurfaceReconciler` Jaccard rebind (threshold 0.5) doesn't strand per-surface assignments when surfaces split/merge.
- **Verify:** reproduce a "looks closed but won't render" case; confirm snap-to-close fixes it; confirm the hint appears and reads correctly; confirm a genuinely-closed shape still renders.
- **Risk:** touches 2D editing + surface derivation — geometry-adjacent. Keep the closure-detection logic untouched where it's correct; only add merging/snap + messaging. No schema change.

### 1E — Deck name → project name
- **Current:** `DeckDesign.title` (default "Untitled Deck") is independent and editable; the project-tab badge renders `titlePill(design.title)` (`DeckTabView.swift:117`); the builder has an `isEditingTitle` flow (`DeckBuilderViewModel.swift:89`).
- **Change:** render the **parent project's name** wherever the deck title is shown. `DeckTabView` already holds `let project: Project` (`DeckTabView.swift:18`) — change `titlePill(design.title)` → the project's name (confirm the `Project` name property during implementation). In the builder header, show the project name read-only and retire the title-edit affordance. **Keep** the stored `title` column (no migration, no delete) for back-compat.
- **Verify:** deck tab + builder show the project name; renaming the project reflects in the deck title; no orphaned edit UI.
- **Risk:** minimal; display-only. Don't remove the model field.

### Drop 1 testing & sequencing
- Copy `Secrets.xcconfig` is already present in the main tree. Device-target build verification: `xcodebuild -scheme OPS -destination 'generic/platform=iOS' build`. Unit tests (1B round-trip): `xcodebuild test -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5'`.
- Commit order: 1A → 1B → 1E → 1C → 1D (cheap-and-isolated first, investigative last). One atomic commit each.
- Visual QA (1B flip, 1C fade, 1D hint) needs Jackson or computer-use to confirm on a running app — flag as the post-merge verification step.

---

## 6. Roadmap detail for Drops 2–6 (to be deep-spec'd per cycle)

- **Drop 2 — House-edge cladding in wheel.** `EdgeType` stays `houseEdge | deckEdge`; the variation is `HouseEdgeMaterial` (7 cases, `DeckGeometry.swift:272–310`). When the user assigns HOUSE EDGE, present a cladding picker (reuse `MaterialPickerSheet` patterns) and store on `DeckEdge.houseEdgeMaterial`. Expose cladding types as selectable wheel items (sets up Drop 3). No schema change — field already exists.
- **Drop 3 — Configurable wheel + MORE.** Extend the wheel data source (currently `AssignmentWheelView.wheelItems`, fixed 8 slots: 3 catalog + 5 hardcoded) to read a **per-user, on-device** slot configuration. Add a MORE slot → full-catalog picker where the user toggles wheel membership. Persist via `UserDefaults` (per-user, device-local; not synced — note this limitation to Jackson). Default layout migrates from today's fixed set.
- **Drop 4 — Gates.** New `GateConfig` struct (sibling to `RailingConfig`/`StairConfig`) on `DeckEdge`: parametric position (0–1), width, swing direction (toward/away from deck), hinge side (L/R). 2D door-arc symbol in `DeckTab2DView`/`DeckCanvasView` tinted by the railing run; 3D clips the railing mesh at the gate span + posts. Migrate existing `AssignedItem.isGate == true` into a default `GateConfig`. Keep `ComponentEmitter`'s railing-footage subtraction wired to the new struct. Schema rides in the JSON blob — legacy-tolerant Codable.
- **Drop 5 — 3D measure tools.** Add gesture + `SCNView.hitTest` ray-casting to the 3D view, mapping hits back to `(levelId, surfaceId/edgeId/vertexId)`. Reuse the 2D readout card + floating-button chrome. Selection is independent per tab. No schema change.
- **Drop 6 — BCBC structural auto-framing + validation.** One **`StructuralRulesEngine`** (well-bounded, independently testable) with two entry points: `frame(for:) -> StructuralLayout` (auto-draw compliant posts/beams/joists/cantilevers/footings from deck size/height) and `validate(_ layout:) -> [CodeViolation]` (cantilever overhang, joist span/spacing/dimension, beam span, post spacing, footing depth). Consults joist/beam span tables. Replaces the hardcoded constants in `buildSupportPosts`/`buildRimJoist`/`DimensionEngine`. Persist a nullable `StructuralLayout`/override on `DeckLevel`. Extend `ComponentEmitter` to emit `beam`/`footing_spec`/enriched `post_set` rows — **coordinate with ops-web's `design_to_estimate_adapter` in the same change or it's silent estimate data loss.** Manual per-level override UI + inline violation flags (highlighted member + roll-up count) are the fast-follow on top of the engine.

---

## 7. Cross-cutting risks & constraints

- **`DeckDesign` is SwiftData + Supabase synced — every model change is a sync change.** New fields (`GateConfig`, wheel config if ever synced, structural override) ride inside `drawingDataJSON` and must round-trip Codable with legacy-tolerant decoding (default-on-missing, as `flipDirection` already does) and survive version skew (old-app/new-schema both directions). The same default-on-missing pattern is what can silently swallow a toggle — so every new field gets a round-trip test (see 1B).
- **No field-level merge on a shared design.** Sync is last-writer-wins; two sessions editing the same design clobber each other (cf. deck sync stale-overwrite revert `29819f76`). Any new write path inherits this. Favor `updatedAt`/`needsSync` recency guards on inbound merge. **Prod Supabase is free-tier with NO backups** — lost geometry is unrecoverable; be conservative with any destructive geometry change.
- **Estimate-adapter contract (Drop 6).** ops-web consumes `ComponentEmitter`'s `components[]`. Any new emitted component type must be understood by the web adapter or estimates silently lose it. Cross-repo coordination required.
- **Surface-derivation coupling.** `SurfaceDetector` pruning and `isClosed`/`hasAnyClosedSurface` read different vertex sets and can diverge; the `DeckSceneBuilder:145` guard depends on consistency. `SurfaceReconciler`'s Jaccard rebind (0.5) can strand per-surface assignments on split/merge. Relevant to Drop 1D and any geometry-touching drop.
- **Parallel sessions.** `DeckSceneBuilder.swift` (touched by Drops 1/4/5/6) and `DeckGeometry.swift` (Drops 4/6) are hot shared files. Stage by name, commit atomically per item, never bulk-stage. The working tree currently has unrelated WIP (`Project+Gallery.swift`, `ActivityTabView.swift`, untracked test files) — leave it untouched.
- **Skills to invoke per drop:** `ops-copywriter` for any user-facing string (1D hint, gate labels, violation messages); `animation-studio:animation-architect` → `ios-animations` for the 1C fade and any motion; `ops-design` / `mobile-ux-design` for 2D/3D UI (gate symbols, measure UI, wheel settings, violation chrome); `animation-studio:realistic-3d` is **not** applicable (this is schematic CAD, not photoreal) — confirmed, the shadow removal moves *away* from realism toward clean schematic reads.

---

## 8. Future direction — standalone spin-off (decided 2026-06-23, scoped later)

Jackson intends to spin the deck designer out as a **standalone iOS app** with its own cheaper subscription, independent of a full OPS subscription. Goal is **both**: a standalone revenue product *and* a top-of-funnel wedge that upsells deck contractors into full OPS. This is its **own future initiative** — to be brainstormed/spec'd after the deck bug-fix/feature drops here — **not** part of Drops 1–6.

**Favored approach (not yet committed):** "company of one" — each standalone user is silently their own single-person company, reusing the existing Firebase auth, Supabase sync, data model, and company RLS as-is. The new work is then mostly (1) a standalone app shell + simplified onboarding, (2) a deck-only billing entitlement (StoreKit 2 / RevenueCat), and (3) extracting the deck designer into a **shared Swift module** powering two app targets. Avoid forking (double-maintenance). Estimate/cut-list output (`ComponentEmitter`, `VinylCutListEngine`, `EstimateGeneratorService`) is a primary standalone value prop ("design → price → cut").

**Constraint this places on Drops 1–6 (act on it now):** keep the deck designer **modular** and avoid deepening coupling to `Project`/`companyId` where avoidable. Prefer passing the small set of values the designer needs over reaching into `Project`. The 1E "name → project name" change is fine (it reads `project.name` at the tab boundary, not inside the designer core). Don't thread new `Project`/company dependencies *into* the `DeckBuilder/` core; keep that layer extraction-ready.

**Costs to revisit at scoping time:** Apple takes 15% (<$1M/yr, Small Business Program) / 30% above; separate App Store listing (own review, ASO, marketing, support); RevenueCat free under ~$2.5k/mo then ~1%. **Move prod Supabase to Pro ($25/mo) for backups/PITR before any standalone customer data lands** — it is currently free-tier with no backups.
