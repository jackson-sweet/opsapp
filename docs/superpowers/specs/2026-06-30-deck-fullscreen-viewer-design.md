# Deck Fullscreen Viewer — Design Spec

**Date:** 2026-06-30
**Surface:** iOS — Project Details → Deck tab (`DeckTabView`)
**Status:** Approved (Jackson, 2026-06-30). Ready for implementation plan.

---

## Purpose

Make complex deck designs viewable and measurable. Today the deck renders inside a
screen-width **1:1 square** in the Project Details scroll view, and the measuring
tools (ruler, select-and-measure) are crammed into that square — 2D only, easy to
miss. This spec adds a **fullscreen focus mode** entered by overscrolling the page,
where the canvas fills the screen and the measuring tools get a real home.

The inline presentation stays as-is ("it looks good now"). Fullscreen is an opt-in
work mode — progressive disclosure, not a redesign of the calm summary.

## User & Context

- **User:** trades operator / crew reviewing a deck design on a project. Outdoors,
  one-handed, distracted. Not a desk power-user.
- **Entry:** already on Project Details, Deck tab selected, a renderable design exists.
- **Primary task in fullscreen:** read the plan clearly + measure distances/areas.

## Platform constraints

- Portrait only (design system v1). Fullscreen solves "cramped" with screen real
  estate + free pan/zoom — no rotation needed.
- iOS deployment target supports `GeometryReader`-based scroll probing (no reliance
  on iOS 18 `onScrollGeometryChange`).
- The global tab bar is a manual `CustomTabBar` ZStack overlay — hidden via
  `.hidesGlobalTabBar()` (token-set controller), NOT `.toolbar(.hidden)`.

---

## Interaction — Enter fullscreen (overscroll-to-expand)

The **only** enter path. No grab handle, no dedicated expand button (per Jackson).

**Gesture:** With the Deck tab active and a renderable design present, the user
scrolls Project Details to the top and **keeps pulling up** (overscroll past the top
boundary). The pull is tracked live; a **medium haptic** fires when it crosses the
commit threshold; releasing past the threshold **commits** to fullscreen; releasing
before it **snaps back** (natural scroll rubber-band).

**Mechanics:**
- Active only when `viewModel.selectedTab == .deck` AND `deckDesign.hasRenderableGeometry`.
- Measure overscroll via a zero-height `GeometryReader` probe as the first child of
  the scroll content, reporting `minY` in a named coordinate space
  (`"projectDetailsDeckScroll"`) through a `PreferenceKey`. `pullDistance = max(0, minY)`.
- `expandProgress = min(1, pullDistance / commitThreshold)`, `commitThreshold = 120pt`.
- **Live feedback:** the pull cue (up-chevron + `PULL TO EXPAND`) fades in over the
  map with `expandProgress` (opacity `min(1, progress×1.4)`); chevron + label brighten
  to the accent once committed. Rendered in `ProjectDetailsView` at the top — the
  inline canvas is below the map fold during overscroll, so the cue (not the canvas)
  carries the feedback.
- **Threshold crossing:** on `expandProgress` crossing `1.0` (guarded so it fires
  once per crossing), fire `UIImpactFeedbackGenerator(style: .medium)` and flip the
  cue label to `RELEASE TO EXPAND`.
- **Release detection:** a simultaneous zero-distance `DragGesture` on the scroll
  content (`.onEnded`) reads the latest `expandProgress`; `>= 1` → commit, else the
  rubber-band returns naturally and the cue fades.
- **Commit:** on finger-up, a simultaneous zero-distance `DragGesture.onEnded` checks
  the tracked pull; `>= 120pt` → `withAnimation(OPSStyle.Animation.standard)` sets
  `isDeckFullscreen = true`. The fullscreen layer enters with a `scale(0.92)+opacity`
  transition — an expand "grow" from ~92% that reads as the canvas blowing up to fill
  the screen. (A shared-element `matchedGeometryEffect` was considered and dropped:
  during a top-overscroll the inline canvas sits below the map fold so a shared-element
  origin isn't visible — and this avoids a SceneKit rebuild flash.) Reduced Motion:
  opacity-only crossfade (no scale).

**Accessibility:** the pull cue itself is non-interactive (`allowsHitTesting(false)`).
The operable VoiceOver path is a custom action "Expand deck to fullscreen" on the
inline deck canvas (`DeckTabView`) — the overscroll gesture isn't operable under
VoiceOver, and Jackson wanted no visible expand button.

## Interaction — Exit fullscreen

- **Close button** (`✕`, top-right, 44×44 tap target, VoiceOver "Close fullscreen")
  → `withAnimation { isDeckFullscreen = false }` shrinks the canvas back into the
  inline frame (matchedGeometry reverse). Light haptic on dismiss.
- **Swipe down to dismiss:** a downward `DragGesture` from the top chrome tracks the
  drag (canvas scales down + dims toward the inline frame); release past threshold
  dismisses, else snaps back. Mirrors the enter gesture. Reduced Motion → crossfade.
- On disappear the fullscreen layer removes its `.hidesGlobalTabBar()` token → the
  tab bar restores.

---

## Fullscreen layout (V4 — Hybrid, from wireframe gate)

Full-screen context: near-opaque canvas, tab bar hidden, edge-to-edge canvas, chrome
that auto-dims during viewport interaction (reuses the existing `isViewportInteracting`
badge-fade).

```
┌──────────────────────────────────────┐
│ MERIDIAN DECK           [ 3D | 2D ] ✕ │  ← top bar (safe-area inset)
│ 2 LVL · 480 FT²                       │  ← compact readout (mono)
│                                  ╭──╮ │
│      ▛▀▀▀▀▀▀▀▜                  │📏│ │  ← tool rail (2D only):
│      ▌  deck   ▐                 ╰──╯ │     📏 measure
│      ▌  plan   ▐                 ╭──╮ │     ⊹  select & measure
│      ▙▄▄▄▄▄▄▄▟                  │⊹ │ │     ▦  dimensions on/off
│   14' 6"                         ╰──╯ │     ⧉  isolate level
│                                  ╭──╮ │     ⤢  fit to screen
│                                  │▦ │ │
│  ┌── SELECTED  2 ──────── CLEAR ┐╰──╯ │
│  │ CEDAR            320 FT²      │╭──╮ │  ← readouts = bottom peek
│  │ RAILING · GLASS   48 FT       │⧉ │ │     sheet (grows w/ content,
│  └───────────────────────────────╯╰──╮ │     dismissible)
│                                  │⤢ │ │
└──────────────────────────────────╰──╯─┘
```

**3D fullscreen:** identical top bar (title · `3D/2D` · close). **No tool rail, no
readouts** — orbit + zoom only (per Jackson). Switching to 3D hides the rail and any
active 2D tool state; switching back to 2D restores it.

### Chrome components

| Element | Spec / token |
|---------|--------------|
| Backdrop | `#0A0A0A` (matches `DeckTab3DView` scene bg) / glass-dense over the map for the transition |
| Top bar height | 52pt content, below top safe area |
| Title | Cake Mono 300, 22px, uppercase, `--text`, left, truncating (`OPSStyle.Typography` screen/title token) |
| Readout | JetBrains Mono, `--text-3`, uppercase, tabular — `"2 LVL · 480 FT²"` (reuses level/area math from `DeckTabView.levelChips`) |
| Mode toggle | existing `SegmentedControl` (3D/2D), 120pt, no accent (design system §4.1) |
| Close | `xmark`, 20pt icon in 44×44 target, `--text-2` |
| Tool rail button | 44×44 circle, `Color.black.opacity(0.6)` idle / `warningStatus` (measure) or `primaryAccent` (select) when active; 1px `white .opacity(0.2)` hairline idle — evolves the existing `DeckTab2DView` tool buttons from 40→44pt |
| Peek sheet | `rgba(10,10,10,0.90)` glass, top hairline, `12px` top radius, drag handle (design system §6.1) |
| Chrome dim | `opacity(isViewportInteracting ? 0 : 1)`, `OPSStyle.Animation.standard`, nil animation under Reduce Motion |

### Tools (2D only)

| Tool | Icon (SF) | Behavior | State |
|------|-----------|----------|-------|
| Measure | `ruler` | Tap two points → live distance. Vertex/edge snap + angle snap. **Exists** in `DeckTab2DView` — relocated to rail. | `measurementMode` |
| Select & measure | `hand.tap` | Tap edges/surfaces → running totals by material/type. **Exists** — relocated. | `selectionMode` |
| Dimensions | `ruler.fill` / `eye.slash` | Toggle per-edge dimension labels (`drawDimensionLabel`) on/off to de-clutter busy plans. **New** — a flag consumed in `canvasContent`. Default ON. | `showDimensions` |
| Isolate level | `square.3.layers.3d` | Multi-level only: focus one level, dim the rest (reuse `drawInactiveLevel`). Cycles levels → all. Hidden for single-level designs. **New.** | `isolatedLevelId: String?` |
| Fit | `arrow.up.left.and.arrow.down.right` | Re-run `centerViewport` to frame the whole deck. **New** — a trigger the canvas observes. | `fitTrigger` counter |

Only one of `measurementMode` / `selectionMode` active at a time (existing mutual
exclusion). `dimensions`, `isolate`, `fit` are independent.

---

## Inline changes (`DeckTabView`)

1. **Tools gone from the inline square.** They lived inside `DeckTab2DView`'s overlay;
   now gated behind `showsTools` (false inline). Inline keeps: `3D/2D` toggle,
   EDIT DESIGN, the floating level chips, and the canvas.
2. **Shared `viewMode` binding** so fullscreen opens in the same mode, plus a
   never-mutated inline `DeckViewerToolState` passed with `showsTools: false`.
3. **`onRequestFullscreen`** — a VoiceOver custom action on the canvas (the accessible
   expand path). The visible pull cue lives in `ProjectDetailsView`, not here.
4. Inline renders read-only: dimensions always on, no isolation/selection/measure.

---

## Architecture

- **New:** `DeckFullscreenViewer.swift` (`Views/Components/Project/Tabs/`) — the
  fullscreen chrome (top bar, tool rail, peek sheet). Inputs narrowed to
  `title: String` + `drawingData: DeckDrawingData` (not the `Project`/`DeckDesign`
  models), so it stays decoupled and is headlessly renderable for snapshot proofs.
- **New:** `DeckViewerToolState` — a `@MainActor ObservableObject` bag: `mode`
  (`.none/.measure/.select`, mutually exclusive), `showDimensions`, `isolatedLevelId`,
  `fitTrigger`, plus the measurement points + selection sets. Owned by the fullscreen
  viewer (with an inert inline instance).
- **New:** `DeckSelectionReadout` — a pure reducer (`drawingData` + selection sets →
  totals by type), extracted from `DeckTab2DView` so the viewer's peek sheet renders
  the same breakdown without owning the canvas.
- **Refactor:** `DeckTab2DView` accepts `toolState` + `showsTools: Bool` (false inline
  → tap gesture + measurement inert and tool state ignored; the draw honors
  `showDimensions` / `isolatedLevelId` / `fitTrigger` only when `showsTools`). Existing
  measure + select logic preserved; its own tool overlay/readout removed (to the viewer).
- **Refactor:** `DeckTab3DView` unchanged; hosted full-bleed in the viewer, no tools.
- **Host:** `ProjectDetailsView` gains `deckToolState` + `deckViewMode` +
  `isDeckFullscreen` + `deckPull`, a scroll `PreferenceKey`/coordinate space, the pull
  cue, and a top ZStack layer (zIndex 30, above nav) presenting `DeckFullscreenViewer`
  with `.hidesGlobalTabBar()` and a `scale(0.92)+opacity` transition.

**Transition note:** the fullscreen layer is a separate view presented over the page
with a `scale(0.92)+opacity` transition — no shared element, so the 3D SceneKit scene
builds once inside the viewer with no rebuild flash.

## Motion (animation-architect brief → ios-animations)

- **Beat:** Transition (inline → focus). An expand "grow" — `scale 0.92 → 1` + fade.
- **Curve:** OPS canonical `cubic-bezier(0.22, 1, 0.36, 1)` (`OPSStyle.Animation.standard`).
  **No spring, no bounce.**
- **Durations:** grow/shrink 300ms; chrome dim 200ms; cue fade 200ms.
- **Haptics:** medium impact at overscroll commit threshold; light impact on close.
  No haptic on the live pull tracking (earned moments only).
- **Reduced Motion:** grow/shrink → 150ms opacity crossfade; no canvas scale preview;
  chrome dim uses nil animation (instant). Honor `accessibilityReduceMotion`.

## States

- **Loading:** none new — geometry is local (SwiftData); fullscreen is only reachable
  once `hasRenderableGeometry` is true. The existing `DeckTabView` remote-repair fetch
  is unchanged.
- **Offline:** fully functional — all geometry + measurement math is local.
- **No scale calibrated:** measure readout shows canvas units with the existing
  `NO SCALE CALIBRATED` hint (unchanged).
- **Single-level design:** isolate-level tool is hidden (nothing to isolate).
- **Empty:** unreachable in fullscreen; inline empty state unchanged.

## Copy (ops-copywriter gate — final)

| String | Value |
|--------|-------|
| Pull cue (below threshold) | `PULL TO EXPAND` |
| Pull cue (past threshold) | `RELEASE TO EXPAND` |
| Pull cue VoiceOver action | Expand deck to fullscreen |
| Measure a11y | Measure distance |
| Select a11y | Select and measure |
| Dimensions a11y | Show dimensions / Hide dimensions |
| Isolate a11y | Isolate level / Show all levels |
| Fit a11y | Fit to screen |
| Close a11y | Close fullscreen |

Existing measure hints (`TAP POINT`, `TAP END`, `NO SCALE CALIBRATED`, `TAP TO RESET`)
and selection readout (`SELECTED n`, `CLEAR`, `TOTAL AREA`, `TOTAL LENGTH`) are retained.

## Anti-patterns to avoid

- Accent color on the tool rail idle state or the mode toggle (design system: accent =
  primary CTA + focus only).
- A second enter affordance (grab handle / big expand button) — Jackson wants pure
  overscroll; discovery is handled by the cue, accessibility by the VoiceOver action.
- Measuring tools in 3D — 3D is view-only.
- Spring/bounce on the grow.
- Blocking the deck's bottom geometry with persistent chrome — readouts are a
  dismissible peek sheet; rail is a thin right column.
- Rebuilding the SceneKit scene mid-transition (camera snap / flash).

## Acceptance criteria (pre-implementation checklist)

- [ ] Overscroll past 120pt at the top of the Deck tab commits to fullscreen; medium
      haptic at threshold; snap-back below threshold.
- [ ] Fullscreen canvas fills the screen; pan/zoom (2D) and orbit (3D) work; tab bar
      hidden; restores on exit.
- [ ] 2D rail: measure, select, dimensions toggle, isolate level (multi-level only),
      fit — all functional; only one of measure/select active at a time.
- [ ] 3D: no tools, orbit/zoom only.
- [ ] Inline tools removed; inline otherwise visually unchanged; pull cue present.
- [ ] All colors/spacing/radii/type via `OPSStyle` tokens — no hardcoded values.
- [ ] Motion uses `OPSStyle.Animation.standard` (no spring); Reduce Motion crossfade
      fallback verified.
- [ ] Touch targets ≥ 44pt; VoiceOver labels/actions present.
- [ ] `audit-design-system` pass clean.
- [ ] Snapshot proof (inline unchanged + fullscreen 2D with tools + fullscreen 3D).
