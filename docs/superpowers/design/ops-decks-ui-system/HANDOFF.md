# OPS Decks UI System Handoff

This directory is the canonical UI handoff for the standalone OPS Decks app. It was supplied as a Claude Design bundle and must be treated as the source of truth for OPS Decks visual language, app chrome, Pro-tier treatment, and deck-specific semantic tokens.

## Source files

- Primary system: `project/OPS Decks System.dc.html`
- Pro-tier exploration: `project/OPS Decks - Pro Tier.dc.html`
- Reference screenshots: `project/screens/`
- Shared assets: `project/assets/`
- Shared fonts: `project/fonts/`

## Implementation rules

- OPS Decks inherits OPS tactical styling, but the standalone deck surface adds deck-specific semantics through named `--deck-*` tokens.
- No production UI may hardcode colors, fonts, radii, spacing, state colors, material swatches, code statuses, zoning overlays, AR overlays, or Pro-tier colors. Every visual value must map through a token or a Swift equivalent.
- The primary handoff's low-vis Pro treatment is the default Pro identity unless Jackson explicitly chooses a different Pro exploration.
- The drawing canvas, 3D viewport, and AR camera shown in the handoff are native placeholders. Implement the surrounding chrome, inspector, sheets, states, and token bindings from the handoff; keep engines native.
- Compliance language must stay objective-negative. Use copy such as "No code failures detected", "3 code concerns found", "Unknown", and "Manual check". Do not use "safe" or "compliant".
- Code and zoning overlays must render live, inline, and tokenized. Example: an over-span joist gets the concern/blocked token style directly on that member plus an attached alert marker.
- Numbers must use monospaced tabular formatting and real construction units: `9′-2″`, `$4,250`, `40 psf`. Empty values render as `—`.
- iPhone is the field-capture surface, iPad is the design/Pencil surface, and Mac is the three-pane office/permitting surface. Do not collapse these into one generic layout.

## Required deck semantics

The production token layer must include Swift equivalents for the handoff's deck semantics:

- Canvas/grid/dimension tokens
- Framing/member/selection tokens
- Code status tokens: verified, concern, blocked, unknown, manual
- Zoning/site tokens: lot line, setback, envelope, easement
- Material tokens: pressure-treated, cedar, composite, PVC, aluminum, glass, cable, membrane, black metal
- AR/3D overlay tokens
- Tool/chrome/status/Pro tokens

If a required semantic has no existing Swift token, add a named token before implementing the UI. Do not inline the raw handoff value in a view.
