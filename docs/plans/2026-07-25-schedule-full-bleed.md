# Schedule Full-Bleed Viewport Implementation Plan

**Goal:** Let the Schedule week viewport extend behind the floating global tab
bar without hiding the final schedule content.

## 1. Protect the viewport policy

- Add focused tests for the Schedule viewport's outer bottom inset.
- Cover week mode with and without the wizard.
- Cover expanded month mode with and without the wizard.
- Run only the new test and confirm it fails before production code changes.

## 2. Remove duplicate outer clearance

- Introduce a small Schedule viewport layout policy.
- Return zero outer inset for week mode.
- Preserve expanded-month wizard clearance using an OPS layout token.
- Keep `DayPageView`'s internal tab-bar clearance in the scroll content.

## 3. Verify the result

- Run only the focused Schedule viewport tests.
- Review the changed UI paths against `DESIGN.md` and `mobile/MOBILE.md`.
- Confirm no unrelated files or visual tokens changed.

## 4. Record and land

- Update the Software Bible's Schedule workflow with the viewport contract.
- Commit the iOS fix and Bible update atomically in their respective repos.
- Land the iOS commit on local `main` without touching unrelated WIP.
- Mark the exact live bug resolved with the landed commit and human review
  required.
