# Deck Builder - Perimeter Entry Mode

**Date:** 2026-06-26
**Status:** Approved interaction direction from Jackson
**Surface:** OPS iOS deck builder, 2D canvas perimeter entry only
**Related:** `OPS/DeckBuilder/Views/DeckCanvasView.swift`, `OPS/DeckBuilder/DeckBuilderViewModel.swift`, `OPS/DeckBuilder/Views/DimensionInputView.swift`, `OPS/DeckBuilder/Views/VoiceDimensionInput.swift`, `docs/superpowers/specs/2026-06-23-deck-designer-overhaul-design.md`, `docs/superpowers/specs/2026-06-24-ops-decks-feature-roadmap.md`

---

## 1. Purpose

Perimeter Entry Mode makes the first deck outline faster on iPhone by replacing finger-precision drawing with an anchor -> direction -> measurement chain. The operator chooses a starting vertex, chooses the direction of the next perimeter edge, enters the exact length in a centered floating control, and commits the line. The typed, wheel-selected, dictated, or laser-fed measurement is the source of truth; the finger only selects intent.

This is scoped to perimeter edges only. It does not change railing assignment, material assignment, stairs, surfaces, framing, structural members, or general-purpose line drawing.

---

## 2. User And Context

**User:** deck and rail operator in the field, often on iPhone, often one-handed, often in sunlight, with a tape measurement in hand.

**Current pain:** the existing draw gesture asks the user to long-press and drag an accurate line with a finger, then correct dimensions later. That works, but it is slow and tedious when the user already knows the measurement.

**Target feeling:** the app behaves like a field tape workflow: pick the corner, pick the turn, enter the number, move to the next corner.

---

## 3. Existing Ground Truth

- `DeckCanvasView` already has separate draw, tap, selection drag, and long-press gesture paths.
- `DeckBuilderViewModel.beginLine(from:)` already snaps a line start to an existing vertex when the start point is near one.
- Empty-space draw starts already defer vertex creation until commit, which prevents orphan vertices.
- `DeckEdge.dimensionSource` already supports `.manual`, `.scale`, `.laser`, and `.ar`.
- `setEdgeDimension(_:inches:source:)` already marks manual/laser dimensions as authoritative and can derive scale from the first manual dimension on a closed shape.
- `DimensionInputView` and `VoiceDimensionInput` already provide text and speech parsing foundations.

The new flow should layer onto these primitives rather than create a separate geometry model.

---

## 4. Interaction Contract

### Entry Points

1. **Long-press empty canvas**
   - Places the first perimeter vertex at the snapped canvas point.
   - Enters Perimeter Entry Mode.
   - Opens the direction selector from that new vertex.

2. **Long-press existing vertex**
   - Enters Perimeter Entry Mode from that vertex.
   - Opens the direction selector.
   - Does not use the normal vertex selection toolbar as the primary path.

3. **Normal tap existing vertex**
   - Keeps current behavior: select vertex and show vertex tools.
   - Vertex toolbar adds a backup action: `DRAW FROM HERE`.

### Chain Flow

```
anchor vertex
  -> direction selector
  -> centered length control
  -> right arrow commits line
  -> new endpoint becomes active anchor
  -> direction selector opens again
```

The operator exits with `DONE`, normal canvas selection, or closing the perimeter back onto the starting vertex.

### Long Press Behavior

Long-press on existing vertex is now intentionally reserved for `DRAW FROM HERE`. There is no current competing long-press-on-vertex behavior in the deck builder. Long-press on an edge keeps assignment/properties behavior separate through existing edge-selection affordances.

---

## 5. Direction Selector

The direction selector is a compact radial control centered on the active vertex.

**Blank or first vertex directions:**
- `UP`
- `RIGHT`
- `DOWN`
- `LEFT`
- `45 UP-RIGHT`
- `45 DOWN-RIGHT`
- `45 DOWN-LEFT`
- `45 UP-LEFT`

**Connected vertex directions:**
- `STRAIGHT`
- `LEFT 90`
- `RIGHT 90`
- `BACK`
- `45 LEFT`
- `45 RIGHT`
- `UP`
- `DOWN`

The connected-vertex mode is relative to the last perimeter edge entering that vertex. This matches the real measuring pattern: continue, turn left, turn right, or backtrack.

**Selection gesture:**
- Long-press opens the wheel.
- Drag through a wedge to preview the candidate line direction.
- Release selects the direction and opens the centered length control.
- Tapping a visible wedge is also allowed for discoverability.

---

## 6. Centered Length Control

No bottom sheet. The length entry appears as a floating command surface in the center of the screen, over the canvas.

```
┌──────────────────────────────────────────┐
│              // LENGTH                   │
│        IMPERIAL              METRIC      │
│                                          │
│   ←     [ FT ] [ IN ] [ FRACTION ]    →  │
│          06     00      0/16             │
│                                          │
│              [ DICTATE ]                 │
└──────────────────────────────────────────┘
```

**Imperial wheels:**
- Feet wheel
- Inches wheel
- Fraction wheel
- The control normalizes overflow. Example: `2' 48"` records as `6'` / `72"` total.

**Metric wheels:**
- Meters wheel
- Centimeters wheel
- Millimeters wheel when precision is needed

**System toggle:**
- `IMPERIAL | METRIC`
- Toggle converts the current selected value, preserving total length.
- The active unit system updates `drawingData.config.measurementSystem` only when the user commits, so accidental toggles do not mutate the whole drawing mid-entry.

**Dictation:**
- `DICTATE` listens for the length only.
- Dictation populates the wheels.
- Dictation never commits automatically.
- User must tap the right arrow to commit.

**Navigation:**
- Left arrow:
  - From length control: return to direction selector.
  - After a committed line: undo the last perimeter-entry commit and return to the previous anchor.
- Right arrow:
  - Commit current line.
  - Center or nudge the new endpoint into view.
  - Make the new endpoint the active anchor.
  - Reopen direction selector.

---

## 7. Data Rules

1. Every line committed through Perimeter Entry Mode creates an edge with `dimensionSource = .manual`.
2. The committed edge dimension is stored in inches internally, consistent with existing `DeckEdge.dimension`.
3. The edge geometry is derived from anchor point, chosen direction, and entered length using the current scale if present.
4. If no drawing scale exists, convert inches to canvas points with the existing prescale fallback so command-entered edges keep exact proportions before calibration. Do not mark the drawing as calibrated until the existing scale logic has enough information to do so.
5. The wheel value is authoritative. The raw finger location is never used as the length.
6. The flow must respect existing snapping and close-shape logic:
   - If the candidate endpoint is within endpoint snap radius of the starting vertex or another existing perimeter vertex, reuse that vertex id.
   - Closing the perimeter exits Perimeter Entry Mode and triggers the existing closed-shape feedback.
7. Manual dimensions that become geometrically stale after later vertex movement keep their current stale-dimension behavior.

---

## 8. States

| State | Behavior |
|---|---|
| Idle | Current deck canvas behavior. Draw/select tools unchanged. |
| Anchor selected | Vertex ring locks visually; direction selector opens. |
| Direction preview | Candidate ray/edge previews from anchor. No edge is committed. |
| Length entry | Centered wheels are active. Canvas dims enough to focus, but geometry remains visible. |
| Dictating | Length control shows waveform/listening state. Wheels update when parsed. |
| Parse failed | Keep prior wheel value. Show `SYS :: LENGTH NOT READ`. |
| Commit failed | Do not create edge. Show exact reason, such as `SYS :: ZERO LENGTH` or `SYS :: EDGE CONFLICT`. |
| Closed perimeter | Exit chain. Show existing closed-shape success and metrics. |
| Offline | Fully available. Speech may require local authorization and capability; wheel/manual entry remains available. |
| Reduced motion | No animated radial expansion. Direction and length controls appear with opacity transition only. |

---

## 9. Wireframe Exploration

### Variant 1: Top-Down Inspector

Strategy: keep all command controls in the existing top header area and leave the canvas unobstructed.

```
┌──────────────────────────────┐
│ PROJECT TITLE / LEVELS       │
│ DIRECTION: LEFT 90           │
│ LENGTH: 6' 0"       COMMIT   │
├──────────────────────────────┤
│                              │
│          CANVAS              │
│                              │
├──────────────────────────────┤
│ TOOLBAR                      │
└──────────────────────────────┘
```

Rejected because the user asked not to use a bottom sheet and the header is already dense. It also separates the measurement wheels from the active vertex.

### Variant 2: Dashboard/Grid Overlay

Strategy: show a compact grid of presets and measurements around the center.

```
┌──────────────────────────────┐
│          CANVAS              │
│   ┌────┐ ┌────┐ ┌────┐      │
│   │ FT │ │ IN │ │ 1/8│      │
│   └────┘ └────┘ └────┘      │
│   ┌────┐ ┌────┐ ┌────┐      │
│   │MIC │ │UNIT│ │NEXT│      │
│   └────┘ └────┘ └────┘      │
├──────────────────────────────┤
│ TOOLBAR                      │
└──────────────────────────────┘
```

Rejected because the grid reads like a control panel instead of a measuring flow. It is more visual bulk than needed.

### Variant 3: Flow-Focused Center Command

Strategy: one centered command surface, left/back and right/continue, with wheels in the middle.

```
┌──────────────────────────────┐
│          CANVAS              │
│                              │
│    ┌──────────────────┐      │
│    │ // LENGTH        │      │
│    │ IMPERIAL METRIC  │      │
│    │ <- FT IN FRAC -> │      │
│    │     DICTATE      │      │
│    └──────────────────┘      │
│                              │
├──────────────────────────────┤
│ TOOLBAR                      │
└──────────────────────────────┘
```

Recommended. It matches the user's approved direction, keeps the current anchor visible, avoids the bottom sheet, and keeps the next action obvious.

### Variant 4: Hybrid Vertex-HUD

Strategy: keep the command control attached near the active vertex and follow it around the canvas.

```
┌──────────────────────────────┐
│          CANVAS              │
│        ● active vertex       │
│       ┌─────────────┐        │
│       │ 6' 0"  ->   │        │
│       │ DICTATE     │        │
│       └─────────────┘        │
├──────────────────────────────┤
│ TOOLBAR                      │
└──────────────────────────────┘
```

Rejected for first implementation because it can collide with screen edges, the user's finger, or small deck geometry. Keep the first build centered and predictable on iPhone.

**Chosen variant:** Variant 3, Flow-Focused Center Command.

---

## 10. Component Spec

| Component | Token/style direction | Notes |
|---|---|---|
| Active vertex ring | `OPSStyle.Colors.primaryAccent`, hairline ring, no glow | Indicates the current anchor. |
| Direction wheel | Existing assignment-wheel interaction pattern, but perimeter-specific slots | No material/catalog actions. |
| Direction preview line | Existing canvas edge stroke style with secondary/preview opacity | No commit until length is confirmed. |
| Length command surface | `OPSStyle.Colors.cardBackground`, `OPSStyle.Colors.cardBorder`, `OPSStyle.Layout.cardCornerRadius` | Centered; never a bottom sheet. |
| Unit toggle | Compact segmented control using design tokens | Active unit is high contrast, not decorative color. |
| Wheels | Native picker/wheel behavior styled with OPS typography | Numbers use mono/tabular style. |
| Dictation button | Icon plus `DICTATE` label | Populates wheels only. |
| Back/continue arrows | Icon buttons, minimum touch target | Left reverses step; right commits. |
| Status line | `SYS :: ...` format | Used for parse/conflict errors. |

All styling must route through `OPSStyle` or `OPSDesignKit` tokens. No hardcoded colors, fonts, spacing, radii, shadows, or spring/bounce animation.

---

## 11. Copy

Approved labels:

- `PERIMETER`
- `DRAW FROM HERE`
- `DIRECTION`
- `LENGTH`
- `DICTATE`
- `IMPERIAL`
- `METRIC`
- `DONE`
- `SYS :: LENGTH NOT READ`
- `SYS :: ZERO LENGTH`
- `SYS :: EDGE CONFLICT`

No emoji, no exclamation points, no tutorial copy inside the working surface. The controls should teach through placement and state, not paragraphs.

---

## 12. Accessibility And Field Conditions

- Minimum touch target: current OPS iOS token minimum, at least 44 pt.
- VoiceOver labels must name the action and current value.
- Unit wheels must be adjustable by VoiceOver increment/decrement.
- Dictation requires clear microphone permission failure handling.
- Reduced motion keeps the interaction functional without radial expansion animation.
- Outdoor readability: high-contrast text, no thin low-alpha numbers, no decorative color.
- One-handed operation: the right arrow must be large enough to commit without precision tapping.

---

## 13. Implementation Boundaries

Implement this design as a perimeter-entry state machine, not as a replacement for the existing draw tool.

Likely state shape:

```swift
enum PerimeterEntryState {
    case inactive
    case choosingDirection(anchorVertexId: String)
    case enteringLength(anchorVertexId: String, direction: PerimeterDirection, draftLengthInches: Double)
}
```

Likely model helpers:

- Find or create anchor vertex from long-press empty canvas.
- Start perimeter entry from existing vertex id.
- Resolve candidate endpoint from anchor, direction, and length.
- Commit one edge as `.manual`.
- Undo last perimeter-entry commit as a single atomic operation.

The final implementation plan must verify whether these helpers belong in `DeckBuilderViewModel` or a small `PerimeterEntryController` owned by the view model. Prefer the latter if it keeps `DeckBuilderViewModel` from absorbing more gesture-specific state.

---

## 14. Testing And Verification

Focused tests:

1. Empty-canvas long-press creates one anchor vertex and no edge until length commit.
2. Existing-vertex long-press enters direction selection without toggling normal selection.
3. Direction plus imperial length creates an edge with correct endpoint and `dimensionSource = .manual`.
4. `2' 48"` normalizes to 72 inches total.
5. Metric toggle preserves total length across unit conversion.
6. Dictation parse updates wheels but does not commit.
7. Right arrow commits one undoable edge and makes the endpoint active.
8. Left arrow from length returns to direction without model mutation.
9. Left arrow after commit removes the last committed perimeter edge and endpoint when safe.
10. Closing to the first vertex reuses the existing vertex id and exits mode.
11. Reduced-motion setting disables radial expansion.
12. Existing assignment wheel behavior for selected edges remains unchanged.

Manual QA:

- iPhone SE width: length control does not clip.
- Dynamic Island device: centered surface does not collide with top floating header.
- One-handed use: long-press vertex, select direction, set length, commit without reaching the top nav.
- Offline mode: manual wheels work with no network.

---

## 15. Open Decisions Resolved

- Bottom dimension sheet: rejected.
- Center floating length control: approved.
- Dictation: supported as wheel population only.
- Unit system: toggle between imperial and metric.
- Trigger: long-press empty canvas and long-press existing vertex.
- Scope: perimeter entry only for the first implementation.
