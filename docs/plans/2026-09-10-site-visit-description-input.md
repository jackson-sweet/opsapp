# Site visit description input implementation plan

**Goal:** Align the description text and placeholder with the other settings fields and prepare the canonical keyboard accessory before editing.

**Architecture:** Keep the `FormTextEditor` API and its single production call site in site-visit settings. Give the shared multiline input explicit UIKit text-container insets so the caret, text, and placeholder all share the same tokenized origin. Reuse the app's existing keyboard accessory coordinator.

**Tech stack:** SwiftUI, UIKit, XCTest.

**Design system:** `/Users/jacksonsweet/Projects/OPS/ops-design-system/project/DESIGN.md`, `mobile/MOBILE.md`, and `OPSStyle.swift`.

**Required skills:** `superpowers:systematic-debugging`, `custom-skills:writing-plans`, `custom-skills:executing-plans`, `custom-skills:ops-design`, `custom-skills:mobile-ux-design`, `custom-skills:interface-design`, `custom-skills:ui-ux-pro-max`, `custom-skills:audit-design-system`, `ops-copywriter:ops-copywriter`, `superpowers:verification-before-completion`.

## Intent and evidence

The owner is setting up a reusable checklist, then returning to field work. The screenshot shows the empty placeholder inset while the caret and typed description sit near the left border. The shared editor paints `surfaceInput` twice and leaves the text container on implicit system insets. Other settings fields already use the canonical form primitives. The separate keyboard screenshot has no visible software keyboard, so its original failure mechanism is unverified.

Use the existing monochrome input surface and neutral focus border to make every editable area recognizable. Keep `Typography.uiBody`, `Colors.text`, `Colors.text3`, `Layout.spacing3`, `Layout.buttonRadius`, and `Layout.Border.standard`; add no visual tokens or copy.

## Steps

1. Add rendered UIKit regression coverage for the description input: insets, placeholder, accessible label, multiline bindings, external value changes, read-only state, and prepared canonical DONE behavior.
2. Repair only the `FormTextEditor` implementation in `OPS/Styles/Components/FormInputs.swift`. Preserve focus through SwiftUI updates and avoid changing selection during ordinary typing or marked-text composition.
3. Run source syntax validation, diff hygiene, line-ending verification, and a token audit. Do not run Xcode, simulators, or Swift package tests in this worktree; the parent owns the serial build baton and will run the authored UIKit tests.
4. Commit the isolated change. Deliver the exact commit, source findings, validation limits, and proposed Bible text to the parent. Do not integrate main or mutate bug metadata from this task.
