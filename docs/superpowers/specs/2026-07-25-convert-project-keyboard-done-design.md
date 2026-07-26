# Convert Project Keyboard Done — Design

**Date:** 2026-07-25
**Bug:** `eab2d556-3a00-4149-a454-ea8dbcaea412`
**Scope:** `ConvertToProjectSheet` on the OPS iOS Leads flow.

## Problem

The app root owns the canonical OPS keyboard `DONE` toolbar, but SwiftUI sheets are separate presentation boundaries. `ConvertToProjectSheet` is presented inside the Leads sheet router and does not attach the shared toolbar itself, so its custom-name, address, value, and notes keyboards can cover the sheet footer without an explicit dismissal action.

## Approved correction

Attach the existing `.opsKeyboardDoneToolbar()` modifier to the root of `ConvertToProjectSheet`.

```text
┌─────────────────────────────┐
│ Convert → Project           │
│                             │
│ [focused form field]        │
├─────────────────────────────┤
│                       DONE  │  keyboard toolbar
├─────────────────────────────┤
│          iOS keyboard       │
└─────────────────────────────┘
```

- `DONE` appears in the standard trailing keyboard-toolbar position for every text or numeric input in the conversion sheet.
- Tapping it resigns the active first responder only.
- Entered data, preflight state, selected match, save state, and sheet presentation remain unchanged.
- The footer actions become reachable again after the keyboard dismisses.

## Rejected approaches

- Applying the modifier to the entire Leads sheet router would broaden the change to unrelated add, edit, lost, and activity sheets and could duplicate controls on sheets that already own keyboard behavior.
- A custom UIKit input accessory would duplicate the established SwiftUI component and create a second visual/interaction contract.

## Visual-system contract

The correction reuses `opsKeyboardDoneToolbar()` exactly. It adds no new color, typography, spacing, radius, motion, icon, or copy. The existing `DONE` label is terse, uppercase, and uses the shared OPS typography and color tokens.

## Verification

- A focused composition regression proves the conversion sheet owns a toolbar modifier inside its presentation boundary.
- The regression is observed failing before the modifier is attached and passing afterward.
- The changed source and test compile through the focused test invocation.
- The final diff introduces no hardcoded visual values.
