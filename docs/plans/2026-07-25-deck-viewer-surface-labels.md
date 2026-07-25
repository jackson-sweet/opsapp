# Deck Viewer Surface Labels Implementation Plan

> **For Codex:** REQUIRED SUB-SKILL: Use `custom-skills:executing-plans` to implement this plan task by task.

**Goal:** Make every unnamed disconnected deck surface identifiable in the expanded 2D viewer without changing stored deck data or adding clutter to the inline preview.

**Architecture:** Keep surface names presentation-only. A pure resolver will apply the existing OPS precedence of explicit surface label, then assigned material name, then the canonical `Surface N` fallback only when the expanded viewer requests it. `DeckTab2DView` will enumerate the detector's stable face order per level and pass that ordinal into the resolver. The existing centroid annotation will be brought onto OPS typography, color, border, spacing, and radius tokens.

**Tech Stack:** Swift 6, SwiftUI `Canvas`, XCTest, Xcode filesystem-synchronized groups.

**Design System:** `/Users/jacksonsweet/Projects/OPS/ops-design-system/project/DESIGN.md`, `/Users/jacksonsweet/Projects/OPS/ops-design-system/project/mobile/MOBILE.md`, and `OPS/Styles/OPSStyle.swift`.

**Required Skills:** `custom-skills:ops-design`, `custom-skills:interface-design`, `custom-skills:mobile-ux-design`, `custom-skills:ui-ux-pro-max`, `ops-copywriter:ops-copywriter`, `custom-skills:audit-design-system`, `superpowers:test-driven-development`, `superpowers:verification-before-completion`.

## Product intent

- **Operator:** A field user inspecting a deck drawing fullscreen, often in glare or distraction.
- **Immediate goal:** Distinguish disconnected surface faces without entering edit mode.
- **Visual feel:** Quiet drafting notation. Existing geometry remains dominant; labels are compact, monochrome, and non-interactive.
- **Scope boundary:** Expanded 2D only. Explicit names and material names continue to render everywhere. Inline previews remain uncluttered. No 3D work, persistence change, migration, or writeback.
- **Copy:** Reuse the established `Surface N` nomenclature already used by deck materials and vinyl-order flows; introduce no new copy register.

### Task 1: Add the failing surface-label regression

**Files:**
- Create: `OPSTests/DeckBuilder/DeckViewerSurfaceLabelResolverTests.swift`

1. Build two disconnected unnamed closed faces.
2. Resolve their expanded-view labels in canonical detected-face order.
3. Assert the literal labels are `Surface 1` and `Surface 2`.
4. Assert explicit labels and assigned material names outrank the generated fallback, while inline mode receives no fallback.
5. Run only this test and confirm it fails because the production resolver does not yet exist.

### Task 2: Implement the presentation-only resolver

**Files:**
- Create: `OPS/Views/Components/Project/Tabs/DeckViewerSurfaceLabelResolver.swift`
- Modify: `OPS/Views/Components/Project/Tabs/DeckTab2DView.swift`

1. Add the pure precedence resolver.
2. Enumerate detected faces in their canonical order for single-level drawings.
3. Enumerate detected faces independently within each level so numbering restarts per level.
4. Supply fallback ordinals only when `showsTools` is true.
5. Keep explicit-label and assigned-material rendering unchanged in inline mode.

### Task 3: Tokenize and visually prove the annotation

**Files:**
- Modify: `OPS/Views/Components/Project/Tabs/DeckTab2DView.swift`
- Modify: `OPSTests/Views/DeckFullscreenSnapshotTests.swift`

1. Resolve the annotation text with `OPSStyle.Typography.microLabel` and `OPSStyle.Colors.text`.
2. Measure the real resolved text instead of estimating width by character count.
3. Use `OPSStyle` glass, line, spacing, border-width, and chip-radius tokens.
4. Add one isolated fullscreen snapshot fixture with two unnamed disconnected faces.
5. Run the focused unit regression and the one snapshot case in a single green test invocation.
6. Inspect the emitted PNG for readable, non-overlapping `Surface 1` and `Surface 2` annotations.

### Task 4: Audit, document, and integrate

**Files:**
- Modify: `ops-software-bible/07_SPECIALIZED_FEATURES.md` using path-scoped partial staging.

1. Audit the diff for hardcoded styling, accessibility regressions, inline-preview changes, and accidental persistence changes.
2. Update the Bible's Project Details 2D viewer contract with expanded fallback precedence and per-level numbering.
3. Commit the iOS fix atomically.
4. Fast-forward local `main` only if its HEAD and unrelated dirty state are unchanged.
5. Record the exact commit and manual verification checklist on only bug `1133c34a-5a19-4225-a5e6-3fecdb354da2`, then read it back.
6. Do not push.
