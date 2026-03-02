# iOS UI Overhaul — Website Design System Adoption

**Date:** 2026-02-24
**Branch:** `feature/ios-major-version`
**Scope:** Complete visual overhaul of 229 view files + 19 style files to match website design system

---

## 1. Design Decisions

| Decision | Choice |
|----------|--------|
| Target design system | `.interface-design/system.md` (website) |
| Accent color | `#597794`, used as precision tool — mostly monochromatic |
| Text alignment | iOS platform conventions (centered where iOS expects it) |
| Status colors | Keep functional colors (green/amber/red) |
| Corner radii | 2-4px (match website sharp aesthetic) |
| Approach | Tokens-first: update OPSStyle.swift, then cascade + manual cleanup |
| Hardcoded styles | Replace all with OPSStyle token references |
| Unused tokens | Purge from OPSStyle.swift |

---

## 2. Color Palette Changes

### Asset Catalog Updates

| Asset | Current | New | Rationale |
|-------|---------|-----|-----------|
| `AccentPrimary` | `#417394` | `#597794` | Match website accent exactly |
| `AccentColor` (system) | verify | `#597794` | System accent alignment |
| `Background` | `#000000` | `#0A0A0A` | Website near-black |
| `DarkBackground` | `#090C15` (blue tint) | `#0A0A0A` | Remove blue tint, match website |
| `CardBackground` | `#191919` | `#141414` | Website surface high end |
| `CardBackgroundDark` | `#0D0D0D` | `#0D0D0D` | Already matches — no change |
| `TextSecondary` | verify | `#999999` | Website spec |
| `TextTertiary` | verify | `#666666` | Proportional to new secondary |
| `TextInactive` | verify | `#444444` | Proportional to new hierarchy |
| `BackgroundGradientStart` | verify | `#0A0A0A` | Match new background |
| `BackgroundGradientEnd` | verify | `#0A0A0A` | Match new background |

### OPSStyle.Colors Token Changes

| Token | Current | New |
|-------|---------|-----|
| `cardBorder` | `white.opacity(0.2)` | `white.opacity(0.10)` — website spec: ultra-thin 10% |
| `cardBorderSubtle` | `white.opacity(0.05)` | `white.opacity(0.08)` — website spec |
| `inputFieldBorder` | `white.opacity(0.2)` | `white.opacity(0.10)` — match card border |
| `buttonBorder` | `white.opacity(0.4)` | `white.opacity(0.15)` — more restrained |
| `separator` | `white.opacity(0.15)` | `white.opacity(0.10)` — website divider spec |

### Status Colors — NO CHANGE

These stay as-is for field functionality:
- `StatusSuccess` (#34C759 / green)
- `StatusWarning` (amber)
- `StatusError` (#FF3B30 / red)
- All `StatusRFQ`, `StatusEstimated`, etc. job status colors

---

## 3. Corner Radius Changes

All values shift to website's 2-4px range:

| Token | Current | New |
|-------|---------|-----|
| `cornerRadius` | `5.0` | `3.0` |
| `buttonRadius` | `5.0` | `3.0` |
| `smallCornerRadius` | `2.5` | `2.0` |
| `cardCornerRadius` | `8.0` | `4.0` |
| `largeCornerRadius` | `12.0` | `4.0` |

---

## 4. Shadow Elimination

Website spec: "Borders-only on dark backgrounds (no shadows — shadows invisible on near-black)"

- Remove all `Shadow` presets from `OPSStyle.Layout`
- Remove `shadowColor` from `OPSStyle.Colors`
- Remove all `.shadow()` modifiers from views on dark backgrounds
- Replace elevation hierarchy with surface lightness shifts: `#0A0A0A` -> `#0D0D0D` -> `#141414`

---

## 5. Overlay Material

Website spec: ultraThinMaterial for superimposed surfaces.

SwiftUI equivalent for sheets, popups, tooltips, dropdowns:
```swift
.background(.ultraThinMaterial)
```

Replace solid opaque backgrounds on overlays with `.ultraThinMaterial` or:
```swift
Color(red: 10/255, green: 10/255, blue: 10/255).opacity(0.70)
    .background(.ultraThinMaterial)
```

---

## 6. Typography Changes

Fonts already use Mohave + Kosugi — no font family changes needed.

### Button Text Change
Website spec: CTA buttons use Kosugi, ALL CAPS.

| Token | Current | New |
|-------|---------|-----|
| `button` | `Mohave-Regular 16pt` | `Kosugi-Regular 14pt` (ALL CAPS via `.textCase(.uppercase)`) |
| `smallButton` | `Mohave-Medium 14pt` | `Kosugi-Regular 12pt` (ALL CAPS) |

### Section Labels
Website spec: `[ LABEL ]` — Kosugi, all caps, bracketed.
- Add new token: `sectionLabel` — `Kosugi-Regular 12pt`, ALL CAPS, tracked spacing

---

## 7. New OPSStyle Tokens to Add

### 7a. Spacing (fill gaps)

Current: 4, 8, 16, 24, 32. Missing: 12, 20.

| New Token | Value | Justification |
|-----------|-------|---------------|
| `spacing2_5` | `12.0` | 135+ hardcoded `.padding(.vertical, 12)` occurrences |
| `spacing3_5` | `20.0` | 170+ hardcoded `.padding(.horizontal, 20)` occurrences |

### 7b. Icon Sizes

Currently untokenized. 100+ hardcoded icon frame sizes.

| New Token | Value | Usage |
|-----------|-------|-------|
| `iconSizeXS` | `12.0` | Tiny indicators |
| `iconSizeSM` | `16.0` | Inline icons, captions |
| `iconSizeMD` | `20.0` | Standard icons |
| `iconSizeLG` | `24.0` | Section header icons |
| `iconSizeXL` | `32.0` | Action icons, avatars |

### 7c. Border Widths

426 hardcoded `lineWidth: 1` and 60 hardcoded `lineWidth: 2`.

| New Token | Value |
|-----------|-------|
| `borderWidth` | `1.0` |
| `borderWidthThick` | `2.0` |

### 7d. Animation (replace empty namespace)

Both existing tokens (`standard`, `quick`) are unused. Replace entirely:

| New Token | Value | Usage |
|-----------|-------|-------|
| `standard` | `.easeInOut(duration: 0.3)` | Default transitions (119 occurrences) |
| `fast` | `.easeInOut(duration: 0.2)` | Quick responses (108 occurrences) |
| `faster` | `.easeOut(duration: 0.15)` | Micro-interactions (27 occurrences) |
| `spring` | `.spring(response: 0.3, dampingFraction: 0.7)` | Bouncy feedback |
| `springFast` | `.spring(response: 0.2, dampingFraction: 0.7)` | Quick spring |

### 7e. Overlay Colors

Fill gap for `Color.black.opacity(X)` patterns:

| New Token | Value | Count |
|-----------|-------|-------|
| `overlayLight` | `Color.black.opacity(0.5)` | Already exists as `modalOverlay` — alias |
| `overlayMedium` | `Color.black.opacity(0.6)` | 10 occurrences |
| `overlayStrong` | `Color.black.opacity(0.7)` | 6 occurrences, also `imageOverlay` alias |
| `overlayHeavy` | `Color.black.opacity(0.85)` | 4 occurrences |

### 7f. Dot/Indicator Sizes

31 hardcoded `frame(width: 8, height: 8)` and 10 `frame(width: 6, height: 6)`.

| New Token | Value |
|-----------|-------|
| `dotSizeSM` | `6.0` |
| `dotSizeMD` | `8.0` |

---

## 8. OPSStyle Tokens to Purge

### Colors — Unused (0 references)
- `errorText` (alias for errorStatus)
- `successText` (alias for successStatus)
- `warningText` (alias for warningStatus)
- `warningBackground`
- `disabledText` (callers use tertiaryText)
- `inactiveText`
- `statusBackground`
- `todayHighlight`
- `Light.errorStatus`, `Light.inactiveStatus`, `Light.warningStatus`, `Light.successStatus`

### Typography — Unused
- `smallButtonBold`

### Layout — Unused
- `contentPadding`
- `Shadow.card`, `Shadow.elevated`, `Shadow.floating` (entire Shadow enum — also eliminated by design)
- `Opacity.light`, `Opacity.medium`, `Opacity.strong`, `Opacity.heavy` (keep `Opacity.subtle`)

### Icons — 39 Unused Tokens
Remove these never-referenced icon tokens:
`settings`, `menu`, `documents`, `error`, `inProgress`, `incomplete`, `deadline`, `duration`, `teamMember`, `edit`, `share`, `sort`, `calendarFill`, `personCircle`, `personCircleFill`, `personFill`, `gearshape`, `gearshapeFill`, `house`, `houseFill`, `mapFill`, `ellipsis`, `ellipsisCircle`, `ellipsisCircleFill`, `listBullet`, `trashFill`, `pencilCircleFill`, `arrowCounterclockwise`, `magnifyingglass`, `magnifyingglassCircle`, `magnifyingglassCircleFill`, `camera`, `cameraFill`, `squareFill`, `dealWon`, `activityBubble`, `followUpAlarm`, `siteVisitPin`, `paymentDollar`

### Animation — Remove/Replace All
- `standard` and `quick` — 0 references. Replace with new definitions from Section 7d.

### Deprecate `secondaryAccent`
- Only 18 references remain. Website design is monochromatic with single accent.
- Phase: Replace all 18 usages with `primaryAccent` or status colors, then remove token.

---

## 9. Hardcoded Style Replacement Scope

### By category (manual file-by-file work)

| Category | Occurrences | Files | Action |
|----------|-------------|-------|--------|
| `.font(.system(...))` | 688 | 176 | Replace with OPSStyle.Typography tokens |
| `Color(.white/.black/.clear)` | 347 | 129 | Replace with OPSStyle.Colors tokens |
| `Color.white.opacity(X)` bypassing tokens | 118+ | widespread | Use existing/new OPSStyle.Colors tokens |
| `Color.black.opacity(X)` bypassing tokens | 36+ | widespread | Use new overlay tokens |
| `.cornerRadius(number)` | 137 | 61 | Replace with OPSStyle.Layout radius tokens |
| `Color(hex:)` outside OPSStyle | 135 | ~20 | Replace with OPSStyle.Colors tokens or move hex to OPSStyle |
| `.lineWidth: number` | 486 | widespread | Replace with new borderWidth tokens |
| Hardcoded animation durations | 300+ | widespread | Replace with OPSStyle.Animation tokens |
| `.shadow()` on dark backgrounds | widespread | widespread | Remove entirely |
| Hardcoded padding values | 800+ | widespread | Replace with OPSStyle.Layout.spacing tokens |

### Priority order for manual pass
1. Font replacements (highest visual impact, 688 occurrences)
2. Color replacements (347 + 135 + 118 + 36 = 636 occurrences)
3. Corner radius (137 occurrences — auto-cascaded by token change, but hardcoded ones need manual fix)
4. Shadow removal
5. Animation tokens
6. Border widths
7. Padding tokens

---

## 10. Files NOT to Touch

- **Status color definitions** — keep green/amber/red functional colors
- **Tutorial views** — heavy hardcoded offender but may be rewritten separately
- **Debug/Test views** (`MapTapGestureTest.swift`, `TaskTestView.swift`) — low priority
- **Onboarding Light theme** — keep `OPSStyle.Colors.Light` namespace (employee onboarding uses light theme)

---

## 11. Validation

After each phase:
1. Build succeeds in Xcode
2. Visual spot-check on key screens: Home, Job Board, Project Details, Schedule, Settings
3. No regressions in status color readability
4. Touch targets remain >= 44pt minimum
