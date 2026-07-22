# Deck Canvas Expanding Workspace — Design

## Product intent

Deck Designer is used by a trades owner or field operator laying out real geometry on a phone. The canvas must feel like reliable drafting paper: the operator always knows where the working surface ends, can never lose the surface through panning, and can keep drawing when the job is larger or positioned outside the original area.

The experience should feel precise, restrained, and continuous. Expansion is infrastructure, not an announcement.

## Root cause

The editor currently has two contradictory coordinate models:

- Grid drawing and finger conversion treat `0...4800` as a fixed workspace.
- Saved geometry, typed perimeter entry, selection moves, paste, rendering, and panning allow coordinates beyond that range, including negative coordinates.

Because the workspace and the area outside it use the same background, the operator cannot see the boundary. Finger input is then clamped while the viewport keeps moving, so a line appears to stop responding at an invisible edge.

## Considered approaches

### 1. Hard 400-foot limit

Draw a stronger border and reject geometry outside `0...4800`.

Rejected. Existing supported workflows and saved drawings contain negative or greater-than-4800 coordinates. Enforcing a hard limit would move, truncate, or invalidate real designs.

### 2. Infinite grid

Remove the finite workspace and render grid dots wherever the viewport travels.

Rejected. It removes the requested boundary, gives operators no spatial recovery cue, and still permits the viewport to become lost in empty space.

### 3. Rebase all geometry near an edge

Translate every stored vertex to keep the drawing centered inside a fixed rectangle.

Rejected. Rewriting persisted coordinates during editing creates unnecessary save churn and risks breaking references, undo history, overlays, and imported calibration.

### 4. Dynamic non-shrinking workspace — selected

Keep geometry coordinates untouched. Start with the existing `4800 × 4800` workspace, then expand its bounds in predictable chunks whenever committed geometry or a live drawing/paste preview approaches an edge. Render the working surface and its border from those same bounds. Constrain viewport movement so at least one touch-target width of the workspace remains recoverable.

This unifies input, rendering, grid, and navigation without migrating saved data.

## Visual treatment

Four boundary treatments were evaluated:

1. Border only — too easy to miss against the existing black canvas.
2. Contrasting workspace fill only — readable, but the exact limit remains ambiguous.
3. Outside gradient/scrim — too decorative and visually unstable during expansion.
4. Tokenized workspace fill plus hairline boundary — selected.

The workspace uses `OPSStyle.Colors.surfaceInput` over the L0 black canvas. Its edge uses `OPSStyle.Colors.inputFieldBorderFocus` at `OPSStyle.Layout.Border.thick`, compensated for zoom so it remains two screen points. Grid dots remain inside the workspace. No accent, warning tone, label, shadow, or animation is introduced.

## Interaction contract

- The initial workspace remains `0,0 ... 4800,4800` for compatibility.
- Existing geometry outside the initial rectangle expands the workspace on open.
- A freehand line, typed perimeter preview, vertex/selection move, or paste preview expands the workspace before it can disappear.
- Expansion adds a safety margin and rounds outward to a fixed growth quantum. It never shrinks during the editing session.
- Screen-to-world conversion is unbounded; the workspace follows intentional geometry instead of clipping it.
- Pinch pan and edge auto-pan use the same offset constraint.
- At least 44 screen points of the workspace remain visible on each axis. If the scaled workspace is smaller than the viewport, it is centered on that axis.
- Expansion is immediate and silent so the active line remains under the operator's finger.
- Undoing or deleting geometry does not collapse the workspace during that session.

## Data and persistence

Workspace bounds are view-session state derived from geometry. They are not persisted and do not change the `deck_designs` payload. Vertex positions, scale calibration, undo snapshots, and material calculations remain untouched.

## Accessibility and failure behavior

- Boundary recognition uses both surface contrast and a line, never colour alone.
- The boundary line is compensated for zoom and remains legible in outdoor glare.
- No motion is required, so reduced-motion behavior is unchanged.
- Non-finite points are ignored by workspace expansion rather than corrupting the bounds.
- Invalid or zero scale falls back safely in pure coordinate helpers; the view continues enforcing its existing `0.15...8.0` zoom range.

## Verification contract

Pure tests cover initial bounds, all four expansion directions, growth quantization, non-shrinking behavior, negative coordinates, screen/world conversion, visible-world calculation, and pan recovery at minimum and maximum zoom. Integration verification covers existing negative-coordinate perimeter tests, selection move/paste regressions, the full DeckBuilder test group, and a generic iOS build.
