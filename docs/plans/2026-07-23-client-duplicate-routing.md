# Client Duplicate Routing Fix

## Goal

When a standalone create-client sheet finds a suspected duplicate, tapping `USE EXISTING` must keep the sheet open and turn it into the existing client's edit form. No caller may have to coordinate a second sheet presentation.

## Root cause

`ClientSheet` currently dismisses itself and invokes its normal save callback with the duplicate client. The Schedule FAB intentionally ignores that callback, so the only visible result is dismissal. The sheet's immutable input mode prevents it from becoming an edit form in place.

## Implementation

1. Add a focused regression test for a create-to-edit session transition. It must prove that the existing client's persisted fields replace the abandoned create draft and that a staged create-only avatar is cleared.
2. Introduce a small internal client-sheet session model that owns the active mode and editable draft.
3. Drive duplicate checks, toolbar labels, and save routing from the active session mode.
4. On `USE EXISTING`, transition the current session to `.edit(existingClient)` without dismissing or invoking `onSave`.
5. Preserve every caller's save contract: standalone entry points remain open for editing; project creation receives the existing client only after an actual save.

## Verification

- Observe the regression test fail before production changes.
- Run the focused duplicate-routing tests after implementation.
- Run `IOSBugReportRegressionTests`.
- Build the OPS app for a generic iOS device.
- Confirm no hardcoded visual tokens or new copy were introduced.
- Commit only the plan, focused test, and client-sheet production files; merge the commit to local `main` without touching unrelated work.
- Resolve bug report `ed685717-4430-455b-b258-3c7786347bac` with the exact commit and retain human verification.
