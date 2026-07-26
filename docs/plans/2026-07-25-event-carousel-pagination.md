# Event Carousel Pagination Implementation Plan

> **For Codex:** REQUIRED SUB-SKILL: Use `custom-skills:executing-plans` to implement this plan task-by-task.

**Goal:** Keep Home carousel pagination clear of project/task content by placing compact dots in a dedicated lane below the card.

**Architecture:** Move pagination ownership from each `EventCardView` into the parent `EventCarousel`. A small reusable layout wrapper will reserve separate vertical regions for card content and pagination, while a focused rendering regression test proves those regions never overlap.

**Tech Stack:** SwiftUI, UIKit rendering harness, XCTest

**Design System:** `/Users/jacksonsweet/Projects/OPS/ops-design-system/project/DESIGN.md` and `/Users/jacksonsweet/Projects/OPS/ops-design-system/project/mobile/MOBILE.md`

**Required Skills:** `custom-skills:ops-design`, `custom-skills:interface-design`, `custom-skills:ui-ux-pro-max`, `custom-skills:mobile-ux-design`, `custom-skills:wireframe`, `custom-skills:audit-design-system`, `superpowers:test-driven-development`, `superpowers:verification-before-completion`

---

### Task 1: Lock the non-overlap behavior

**Skills:** Use TDD and the real SwiftUI rendering harness.

**Files:**
- Create: `OPSTests/Views/EventCarouselPaginationLayoutTests.swift`
- Test: `OPSTests/Views/EventCarouselPaginationLayoutTests.swift`

**Design tokens:** `OPSStyle.Layout.spacing1`, `spacing2`, `spacing3_5`; `OPSStyle.Colors.text3`, `fillNeutral`

1. Mount the production carousel layout in a real `UIHostingController` window.
2. Measure the rendered card and indicator frames and assert their bounds do not intersect.
3. Run only `EventCarouselPaginationLayoutTests` and confirm the test fails before implementation.

### Task 2: Move pagination below the card

**Skills:** Apply OPS interface, mobile UX, and design-system guidance.

**Files:**
- Modify: `OPS/Views/Components/Event/EventCarousel.swift`
- Test: `OPSTests/Views/EventCarouselPaginationLayoutTests.swift`

**Design tokens:** 100pt existing card height; dot size derived from `spacing1`/`spacing2`; 8pt gap and dot spacing from `spacing2`; active `text3`; inactive `fillNeutral`

1. Add a token-derived carousel metrics namespace and a reusable vertical layout wrapper.
2. Keep `TabView` focused on cards and render a maximum-five-dot informational indicator below it.
3. Remove page-count/index responsibilities from `EventCardView`.
4. Run only `EventCarouselPaginationLayoutTests` and confirm it passes.

### Task 3: Audit, document, and land

**Skills:** Use `custom-skills:audit-design-system` and `superpowers:verification-before-completion`.

**Files:**
- Modify: `/Users/jacksonsweet/Projects/OPS/ops-software-bible/02_USER_EXPERIENCE_AND_WORKFLOWS.md`

1. Confirm the diff contains no new hardcoded color, font, spacing, or radius values.
2. Record the Home carousel pagination rule in the Software Bible.
3. Commit the iOS fix and Bible update atomically in their respective repositories.
4. Land the iOS commit onto local `main` without touching the existing Xcode project change.
5. Update only bug `80e7d23a-9a16-4895-b458-f821dc1bb73e` with exact commit and focused-test evidence, then stop for manual verification.
