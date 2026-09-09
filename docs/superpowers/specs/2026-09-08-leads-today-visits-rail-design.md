# Leads — Today's Visits Rail (replaces the START cards)

**Report:** `f77d38fc` — "Site visits list at the top of the Leads tab: UI/UX for that spot is ugly" (Jackson, 2026-09-08).
**Status:** owned by the principal; the founder reviews the render, not this document.

## What is there today

`SiteVisitStartCardsHost` (`OPS/Views/SiteVisits/SiteVisitStartCard.swift`, built 2026-08-11) pins one full glass panel per booked visit above the whole Leads surface: a `// SITE VISIT — 2:00PM` label with a dismiss ×, the name, the address, and a full-width filled START button. Roughly 130 pt per visit, stacked. Two visits push the Leads console below the fold; the filled buttons and the × chips compete with everything under them. It reads as a pile of notifications, not as the morning's plan.

## The moment

Morning, or between jobs. The operator opens Leads. They have one to three site visits today. They need, in a glance: when, who, where — and one deliberate way to start the capture when they are at the door. The rest of the time the list should take almost no room and never ask anything of them.

## Decision

One compact panel, time-led rows, one small action.

```
┌──────────────────────────────────────────────┐
│ // TODAY · 2 VISITS                          │
│ 2:00 PM   Angela Wall                 [START]│
│           4369 Happy Valley Rd, Victoria      │
│ ─────────────────────────────────────────── │
│ 4:30 PM   Kyle Kingsley               [START]│
│           10440 Resthaven Dr, Sidney          │
└──────────────────────────────────────────────┘
```

- **Panel:** a single L1 glass surface (`glassSurface`), `spacing3` inset, sitting where the cards sat. Header `// TODAY · N VISITS` in `miniLabelBold`, tracking 1.2, `text3`. One visit reads `// TODAY · 1 VISIT`.
- **Row (≥ 56 pt):** time in `dataValue` (JetBrains Mono, tabular) in `text`; name in `bodyBold` `text`; address in `smallCaption` `text3`, one line, tail-truncated. Rows are separated by the mobile hairline (`line`), never by cards.
- **START** is a compact 36 pt chip (the sanctioned sub-44 tier — its hit area is padded to 44 pt): outlined, `cardBorder` hairline, `buttonLabel` in `text`, no fill. It is the only verb on the panel and it is small on purpose: starting a capture is deliberate, not ambient. Medium haptic on tap, as today.
- **Tap the row** → open the lead. The lead detail now carries the visit banner (START / REBOOK / CANCEL) being built in the Leads lane, so the two surfaces show the same visit the same way.
- **Dismiss for today** lives behind a long-press context menu on the row (`DISMISS FOR TODAY`), with the same per-visit, expires-with-the-day store as before. The × goes away; dismissing is rare and must not compete with starting.
- **Empty:** nothing rendered, as today.
- **Motion:** rows enter and leave with `OPSStyle.Animation.standard` (opacity + move); Reduce Motion honoured. No bounce.

Height: header + two rows ≈ 140 pt total, against ≈ 270 pt for two cards today.

## Out of scope

Booking from the rail, reordering, and multi-day previews. The week rail in the booking sheet is untouched.

## Proof

`SiteVisitStartCardsRenderTests` writes `docs/artifacts/field-reports-0908/leads-visits-before.png` (current cards) and `leads-visits-after.png` (the rail) at 393 pt wide for the founder's side-by-side. `SiteVisitStartCardTests` (candidate selection, dismissal, expiry) stays green unchanged. A row-model test pins the header copy, the time token, and the 36 pt chip / 44 pt hit target. Closure is the founder's reaction to the render, then the screen on his phone.
