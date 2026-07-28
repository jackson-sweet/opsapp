# Global Keyboard Done — Design

**Date:** 2026-07-25
**Bug:** `eab2d556-3a00-4149-a454-ea8dbcaea412`
**Scope:** Every software keyboard opened by the OPS iOS app.

## Corrected requirement

Every OPS keyboard must expose one canonical `DONE` action. The guarantee must
hold across root screens, navigation destinations, sheets, full-screen covers,
dedicated overlay windows, SwiftUI fields, UIKit fields, secure inputs, text
editors, search fields, and keyboards without a native return key.

`DONE` dismisses the active keyboard. It does not dismiss the current screen,
clear entered data, or commit the surrounding form unless that form already
commits edits when focus ends.

## User and intent

- **Human:** A trades owner or crew member entering information one-handed,
  often outdoors, in motion, or under time pressure.
- **Task:** Finish typing and regain access to the screen without hunting for
  an escape gesture or losing work.
- **Feel:** Native, predictable, quiet, and identical everywhere.
- **Domain:** Field entry, form completion, focus, keyboard, continuity.
- **Signature:** The same trailing uppercase OPS `DONE` control on every
  keyboard.

## Winning architecture

Install one app-lifetime UIKit input-accessory coordinator from
`AppDelegate.application(_:didFinishLaunchingWithOptions:)`.

The coordinator observes editing activation for both UIKit primitives used by
SwiftUI on the supported deployment target:

- `UITextField` covers `TextField`, `SecureField`, search fields, and direct
  UIKit text fields.
- `UITextView` covers `TextEditor` and direct UIKit text views.

OPS-owned UIKit-backed custom editors install the canonical accessory when the
input is created, before it can become first responder. This keeps their focus
and keyboard presentation continuous without reloading input views mid-focus.
For system-managed SwiftUI inputs that cannot be prepared directly, editing
activation remains the fallback installation boundary and reloads the active
input only when required. The accessory weakly retains the exact text input it
belongs to. Its trailing `DONE` button resigns that input directly, avoiding
any ambiguity when OPS has multiple windows or responder chains.

```text
┌──────────────────────────────────┐
│ Current OPS screen or sheet      │
│                                  │
│ [active text / number input]     │
├──────────────────────────────────┤
│                            DONE  │  global OPS accessory
├──────────────────────────────────┤
│          iOS keyboard            │
└──────────────────────────────────┘
```

This sits at the UIKit input boundary rather than the SwiftUI presentation
boundary. It therefore survives every sheet, cover, navigation stack, and
overlay window without asking each screen to opt in.

## Exactly-once rule

The global accessory is the only generic keyboard toolbar. Existing local
SwiftUI keyboard toolbars are removed so a keyboard never displays duplicate
actions. Local form behavior that previously ran from a keyboard-toolbar button
is moved to the form's focus-loss boundary:

- quantity adjustment finishes edit mode when focus ends;
- task notes commit their temporary draft when focus ends, while explicit
  `CANCEL` still discards;
- site-visit notes perform the existing immediate autosave when focus ends.

## Visual-system contract

- Copy remains `DONE`: uppercase, terse, and already approved for authority.
- Button typography uses the canonical Cake Mono button-label UIKit bridge.
- Foreground uses the OPS primary-text token.
- The native input-accessory toolbar reports the OPS minimum touch-target token
  as its stable intrinsic height and uses the system keyboard surface.
- No new color, spacing, radius, icon, animation, or decorative treatment.
- VoiceOver reads the button as `Done`.

## Rejected approaches

### Per-screen SwiftUI modifiers

Rejected because the app currently contains hundreds of inputs and presentation
boundaries. New sheets would silently regress unless every author remembered an
opt-in modifier.

### One toolbar on the SwiftUI app root

Rejected because SwiftUI toolbar preferences do not cross every sheet,
full-screen cover, or dedicated overlay-window boundary. This is the root cause
of the reported failure.

### A floating window above the keyboard

Rejected because it creates a second-window hit-testing, rotation, scene, and
accessibility problem when UIKit already provides the correct input-accessory
contract.

## Verification contract

- Prove the coordinator automatically installs one accessory for a text field
  and a text view after editing begins.
- Prove repeated editing notifications do not stack or replace the canonical
  accessory.
- Prove a prepared custom text view retains the same accessory without
  reloading its input views when editing begins.
- Prove invoking `DONE` resigns a real first responder hosted in a window.
- Prove every former local toolbar side effect remains attached to focus loss.
- Run a repository audit confirming no generic SwiftUI keyboard toolbar remains.
- Compile and run only the focused regression class; reuse the isolated build
  cache and do not run redundant broad builds.
