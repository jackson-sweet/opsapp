# Deck viewer fixes — 2026-09-15 proof

Renders captured by the test suites and a headless browser session while verifying the four deck reports (`f7dd3673`, `1a8e48af`, `5f285f64`, `b130d23f` + `acc0d021`). Plan: `docs/plans/2026-09-15-deck-viewer-fixes.md`.

| File | What it proves |
|---|---|
| `ios-viewer-surface-label-fills-surface.png` | `DeckViewerEdgeLabelRenderingTests.testSurfaceLabelFillsItsSurfaceAndStaysInside` — the surface name fills its surface at the 28pt on-screen ceiling inside a glass pill that never crosses an edge (was 3–6pt on screen). |
| `ios-viewer-custom-edge-caption-scales.png` | Same suite — a custom edge caption now scales with the edge it annotates (11–20pt on screen) instead of a fixed 11pt. |
| `ios-vinyl-workspace-fitted.png` / `ios-vinyl-workspace-zoomed-4x.png` | `VinylOrderWorkspaceSnapshotTests` — the order layout at fit and at 4× zoom: vector-crisp seams, callouts held at screen size, FIT chip present (was a bitmap zoom about the centre). |
| `web-viewer-measure-readout.png` | Playwright against the `deck-viewer` worktree preview — the fullscreen web viewer on project "1121 Oscar St — Deck" with the measure tool snapped to two vertices reading `LENGTH 5' · SEGMENTS 1`. |

Merged simulator pass on the combined iOS tree: 1172 passed, 0 failed, 1 skipped across 118 deck-related test classes (`fable-deckfixes-0915`, iOS 26.5). Web: vitest 183/183 on the deck files; `tsc` clean for the branch's files.
