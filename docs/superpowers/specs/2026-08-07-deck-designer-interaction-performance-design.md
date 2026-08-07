# Deck Designer Interaction Performance Repair

## Problem

The embedded OPS iOS Deck Designer publishes a large `DeckDrawingData` value throughout direct manipulation. SwiftUI then redraws the synchronous canvas and rereads topology and metrics. `DeckDrawingData.detectedSurfaces` and `DeckLevel.detectedSurfaces` currently run the complete planar-face detector on every access, including graph pruning, angular sorting, canonicalization, and SHA-256 surface identifiers. Selection movement compounds that work with repeated vertex lookups, nested snap scans, per-vertex publications, and repeated dimension passes. Saving serializes the drawing more than once on the main actor, while 3D serializes the entire drawing merely to decide whether to rebuild the entire scene.

The previous persisted-JSON decode cache fixes the fullscreen host's repeated decode watchdog, but it does not change any of these live-editor paths.

## Chosen architecture

Use four narrow boundaries instead of replacing the drawing system:

1. **Exact geometry snapshot cache.** Each single-level or level-local graph resolves through an exact ordered key containing only vertex ids/positions and edge endpoint ids. A cache miss computes vertex/edge indexes, ordered positions, closed state, detected surfaces, and canvas-space metrics once. Non-geometric edits such as labels, materials, and dimensions reuse the same snapshot. Geometry edits invalidate naturally because the exact key changes. No hash-only invalidation is accepted.
2. **Frame-coalesced live overlay.** Vertex and selection drags stage their latest vertex positions and alignment guides in a small interaction overlay. Multiple gesture callbacks in one main-loop turn collapse into one publication. The committed drawing and topology snapshot stay unchanged while the finger moves. The canvas resolves active vertex positions through the overlay, so edge, vertex, fill, and dimension rendering remain live.
3. **One-pass commit and deferred durability.** Finger lift applies all staged vertex positions and recalculates affected edge dimensions in one indexed edge pass, then replaces the committed drawing once. The durable save is scheduled after the interaction transaction, and exit/background paths still flush it synchronously. Surface reconciliation and JSON encoding therefore leave the movement call stack. One encoded JSON string feeds both SwiftData and sync-queue payload construction.
4. **Explicit 3D revision.** The builder supplies a monotonically increasing drawing revision to the SceneKit bridge. Identical revisions do nothing; changed revisions rebuild once without JSON change detection. Static scenes remain demand-rendered while camera control retains the current interaction behavior and visual quality.

## Alternatives rejected

- **Eager snapshot rebuild in every `drawingData.didSet`:** simpler, but bulk mutations can still rebuild several times before SwiftUI renders and direct gesture mutation would remain expensive.
- **Canvas/Metal rewrite or immediate DeckKit port:** could raise the ultimate rendering ceiling, but it is much broader than the measured causes, risks drawing/snap/save parity, and violates the bounded-repair instruction.

## Behavioral contract

- Drawing, snapping, selection, undo/redo, 2D rendering, 3D presentation, save/sync, and surface ids remain behaviorally identical.
- A drag update changes only the live overlay. The committed drawing changes once at finger lift.
- Scale-derived edge dimensions update live and commit from the same resolved positions. Manual, laser, and AR dimensions remain preserved and receive the same stale flag rules.
- A pending durability write is flushed by existing close, disappear, inactive, and background paths. Sync still receives the complete reconciled drawing.
- Cache identity is exact. Relevant geometry changes cannot reuse an old snapshot; irrelevant metadata changes do not discard a valid one.

## Proof strategy

Deterministic tests, rather than wall-clock thresholds, will prove the hot-path work bounds:

- repeated reads of a 29-vertex/29-edge closed drawing perform one surface detection;
- a heavier multi-level drawing performs one detection per changed level, not per read;
- a 29-vertex selection move visits each edge once at commit rather than once per moved vertex;
- many submitted drag callbacks schedule one frame publication and retain the latest value;
- live updates leave the committed revision unchanged, while finger lift commits one drawing revision;
- repeated 3D updates with an unchanged revision do not rebuild;
- persistence remains pending during the interaction and becomes durable when flushed.

Focused deck tests and Swift parsing are the iteration loop. At most one combined Xcode verification run is permitted at the end, with worktree-local packages and DerivedData. Physical-device FPS and hitch behavior remain a separate runtime proof boundary.
