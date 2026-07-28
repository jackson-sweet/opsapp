# Keyboard Focus Regression Repair

## Outcome

Project Details → Activity accepts focus on the first tap, keeps the keyboard
visible, and presents the global DONE control fully above the keyboard.

## Root Cause

The Activity composer is OPS's custom UIKit-backed text editor. The global DONE
coordinator currently waits until editing has begun, attaches the accessory,
then reloads the active keyboard. That mid-focus reload interrupts SwiftUI's
focus binding and makes the keyboard jump away.

## Implementation

1. Add a focused regression test proving a prepared text view retains the same
   accessory without reloading its input views when editing begins.
2. Give the global keyboard coordinator a preparation API that installs the
   canonical accessory before focus.
3. Prepare the shared mention editor when its `UITextView` is created.
4. Give the accessory a stable intrinsic height using the existing OPS minimum
   touch-target token.
5. Update the design contract and Software Bible with the pre-focus rule.

## Verification

- Preserve the interrupted pre-fix attempt as evidence of the missing
  preparation API; do not repeat it.
- Run one focused post-fix keyboard test pass after unrelated Xcode work clears.
- Confirm no hardcoded visual values and no whitespace errors.
- Preserve all unrelated scheduling work in the primary checkout.
- Stop for manual validation in Project Details → Activity.
