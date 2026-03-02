# iOS UI Overhaul — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Overhaul the entire iOS app UI to match the website design system (`.interface-design/system.md`) — monochromatic, sharp, defense-contractor aesthetic with `#597794` accent used sparingly.

**Architecture:** Tokens-first approach. Update asset catalog colors and OPSStyle.swift tokens first so references auto-cascade. Then update component styles. Finally, manual pass to replace all hardcoded values with token references and purge unused tokens.

**Tech Stack:** SwiftUI, Xcode Asset Catalogs, OPSStyle design system

**Design Doc:** `docs/plans/2026-02-24-ui-overhaul-design.md`

---

## Phase 1: Foundation — Asset Catalog + Core Tokens

### Task 1: Update Asset Catalog Color Values

**Files:**
- Modify: `OPS/Assets.xcassets/Colors/AccentPrimary.colorset/Contents.json`
- Modify: `OPS/Assets.xcassets/AccentColor.colorset/Contents.json`
- Modify: `OPS/Assets.xcassets/Colors/Background.colorset/Contents.json`
- Modify: `OPS/Assets.xcassets/Colors/DarkBackground.colorset/Contents.json`
- Modify: `OPS/Assets.xcassets/Colors/CardBackground.colorset/Contents.json`
- Modify: `OPS/Assets.xcassets/Colors/Text/TextSecondary.colorset/Contents.json`
- Modify: `OPS/Assets.xcassets/Colors/TextTertiary.colorset/Contents.json`
- Modify: `OPS/Assets.xcassets/Colors/Text/TextInactive.colorset/Contents.json`
- Modify: `OPS/Assets.xcassets/Colors/BackgroundGradientStart.colorset/Contents.json`
- Modify: `OPS/Assets.xcassets/Colors/BackgroundGradientEnd.colorset/Contents.json`
- Modify: `OPS/Assets.xcassets/Colors/AccentSecondary.colorset/Contents.json`

**Step 1: Update AccentPrimary**
Change both light/dark appearances from `#417394` to `#597794`:
- red: `0x59`, green: `0x77`, blue: `0x94`

**Step 2: Update AccentColor (system)**
Same values as AccentPrimary: `#597794`

**Step 3: Update AccentSecondary**
Change to match AccentPrimary (`#597794`) — this will be deprecated but must not break during transition.

**Step 4: Update Background**
Change from `#000000` to `#0A0A0A`:
- red: `0x0A`, green: `0x0A`, blue: `0x0A`

**Step 5: Update DarkBackground**
Change from `#090C15` to `#0A0A0A` (remove blue tint):
- red: `0x0A`, green: `0x0A`, blue: `0x0A`

**Step 6: Update CardBackground**
Change from `#191919` to `#141414`:
- red: `0x14`, green: `0x14`, blue: `0x14`

**Step 7: Update TextSecondary**
Verify current value, update to `#999999`:
- red: `0x99`, green: `0x99`, blue: `0x99`

**Step 8: Update TextTertiary**
Update to `#666666`:
- red: `0x66`, green: `0x66`, blue: `0x66`

**Step 9: Update TextInactive**
Update to `#444444`:
- red: `0x44`, green: `0x44`, blue: `0x44`

**Step 10: Update BackgroundGradientStart and BackgroundGradientEnd**
Both to `#0A0A0A` (match new background)

**Step 11: Verify — do NOT change these:**
- `CardBackgroundDark` — already `#0D0D0D`, correct
- All `StatusSuccess`, `StatusWarning`, `StatusError` — keep
- All `StatusRFQ`, `StatusEstimated`, etc. job status colors — keep
- `StatusBackground`, `StatusInactive` — keep

---

### Task 2: Update OPSStyle.Colors Token Values

**Files:**
- Modify: `OPS/Styles/OPSStyle.swift` (Colors section, approximately lines 31-163)

**Step 1: Update border opacity tokens**

| Token | Old | New |
|-------|-----|-----|
| `cardBorder` | `white.opacity(0.2)` | `white.opacity(0.10)` |
| `cardBorderSubtle` | `white.opacity(0.05)` | `white.opacity(0.08)` |
| `inputFieldBorder` | `white.opacity(0.2)` | `white.opacity(0.10)` |
| `buttonBorder` | `white.opacity(0.4)` | `white.opacity(0.15)` |
| `separator` | `white.opacity(0.15)` | `white.opacity(0.10)` |

**Step 2: Update the comment on primaryAccent**
Change `// Orange (#FF7733)` to `// Blue-gray (#597794)`

**Step 3: Update the comment on secondaryAccent**
Add `// DEPRECATED — use primaryAccent. Kept temporarily for active-state map indicators.`

**Step 4: Add new overlay color tokens** (after existing overlay tokens, ~line 81)
```swift
static let overlayMedium = Color.black.opacity(0.6)   // Medium overlay (tooltips, dimming)
static let overlayStrong = Color.black.opacity(0.7)    // Strong overlay (popups, menus)
static let overlayHeavy = Color.black.opacity(0.85)    // Heavy overlay (full-screen dimming)
```

---

### Task 3: Update OPSStyle.Layout Corner Radii

**Files:**
- Modify: `OPS/Styles/OPSStyle.swift` (Layout section, approximately lines 198-323)

**Step 1: Update corner radius values**

| Token | Old | New |
|-------|-----|-----|
| `cornerRadius` | `5.0` | `3.0` |
| `buttonRadius` | `5.0` | `3.0` |
| `smallCornerRadius` | `2.5` | `2.0` |
| `cardCornerRadius` | `8.0` | `4.0` |
| `largeCornerRadius` | `12.0` | `4.0` |

---

### Task 4: Add New OPSStyle Tokens

**Files:**
- Modify: `OPS/Styles/OPSStyle.swift`

**Step 1: Add spacing tokens** (in Layout section after `spacing5`)
```swift
static let spacing2_5: CGFloat = 12.0  // Between spacing2 (8) and spacing3 (16)
static let spacing3_5: CGFloat = 20.0  // Between spacing3 (16) and spacing4 (24)
```

**Step 2: Add icon size tokens** (new enum in Layout)
```swift
enum IconSize {
    static let xs: CGFloat = 12.0   // Tiny indicators
    static let sm: CGFloat = 16.0   // Inline icons, captions
    static let md: CGFloat = 20.0   // Standard icons
    static let lg: CGFloat = 24.0   // Section header icons
    static let xl: CGFloat = 32.0   // Action icons, prominent UI
}
```

**Step 3: Add border width tokens** (new enum in Layout)
```swift
enum Border {
    static let standard: CGFloat = 1.0
    static let thick: CGFloat = 2.0
}
```

**Step 4: Add dot/indicator size tokens** (new enum in Layout)
```swift
enum Indicator {
    static let dotSM: CGFloat = 6.0
    static let dotMD: CGFloat = 8.0
}
```

**Step 5: Replace Animation section entirely** (replace lines 326-329)
```swift
enum Animation {
    static let standard = SwiftUI.Animation.easeInOut(duration: 0.3)
    static let fast = SwiftUI.Animation.easeInOut(duration: 0.2)
    static let faster = SwiftUI.Animation.easeOut(duration: 0.15)
    static let spring = SwiftUI.Animation.spring(response: 0.3, dampingFraction: 0.7)
    static let springFast = SwiftUI.Animation.spring(response: 0.2, dampingFraction: 0.7)
}
```

---

### Task 5: Purge Unused Tokens

**Files:**
- Modify: `OPS/Styles/OPSStyle.swift`

**Step 1: Remove unused Color tokens**
Delete these lines:
- `errorText` (alias for errorStatus)
- `successText` (alias for successStatus)
- `warningText` (alias for warningStatus)
- `warningBackground`
- `disabledText`
- `inactiveText`
- `statusBackground`
- `todayHighlight`
- `Light.errorStatus`, `Light.inactiveStatus`, `Light.warningStatus`, `Light.successStatus`

**Step 2: Remove unused Typography token**
Delete: `smallButtonBold`

**Step 3: Remove unused Layout tokens**
Delete:
- `contentPadding`
- Entire `Shadow` enum (`Shadow.card`, `Shadow.elevated`, `Shadow.floating`)
- From `Opacity` enum: `light`, `medium`, `strong`, `heavy` (keep only `subtle`)

**Step 4: Remove unused Icon tokens (39 total)**
Delete all of:
`settings`, `menu`, `documents`, `error`, `inProgress`, `incomplete`, `deadline`, `duration`, `teamMember`, `edit`, `share`, `sort`, `calendarFill`, `personCircle`, `personCircleFill`, `personFill`, `gearshape`, `gearshapeFill`, `house`, `houseFill`, `mapFill`, `ellipsis`, `ellipsisCircle`, `ellipsisCircleFill`, `listBullet`, `trashFill`, `pencilCircleFill`, `arrowCounterclockwise`, `magnifyingglass`, `magnifyingglassCircle`, `magnifyingglassCircleFill`, `camera`, `cameraFill`, `squareFill`, `dealWon`, `activityBubble`, `followUpAlarm`, `siteVisitPin`, `paymentDollar`

**Step 5: Remove shadowColor from Colors**
Delete: `static let shadowColor = Color.black.opacity(0.15)`

---

### Task 6: Update Button Typography

**Files:**
- Modify: `OPS/Styles/Fonts.swift`

**Step 1: Change button font to Kosugi (website CTA spec)**
```swift
/// Button text - Kosugi Regular (14pt) — ALL CAPS via .textCase(.uppercase)
public static var button: Font {
    return Font.custom("Kosugi-Regular", size: 14)
}

/// Small button text - Kosugi Regular (12pt) — ALL CAPS via .textCase(.uppercase)
public static var smallButton: Font {
    return Font.custom("Kosugi-Regular", size: 12)
}
```

**Step 2: Add section label font**
```swift
/// Section label - Kosugi Regular (12pt) — ALL CAPS, tracked
public static var sectionLabel: Font {
    return Font.custom("Kosugi-Regular", size: 12)
}
```

**Step 3: Add sectionLabel to OPSStyle.Typography**
In `OPS/Styles/OPSStyle.swift`, Typography section:
```swift
static let sectionLabel = Font.sectionLabel
```

---

### Task 7: Commit Phase 1

```bash
git add OPS/Assets.xcassets/ OPS/Styles/OPSStyle.swift OPS/Styles/Fonts.swift
git commit -m "Phase 1: Update design tokens — website design system adoption

- Asset catalog: accent #597794, background #0A0A0A, surfaces #0D0D0D/#141414
- Corner radii: 2-4px (sharp aesthetic)
- Border opacities: 10% standard
- New tokens: spacing, icon sizes, border widths, animations, overlays
- Purge 39 unused icons, 8 unused colors, unused shadows/opacity presets
- Button typography: Kosugi ALL CAPS per website spec"
```

---

## Phase 2: Component Styles

### Task 8: Update ButtonStyles.swift

**Files:**
- Modify: `OPS/Styles/Components/ButtonStyles.swift`

**Step 1: Add `.textCase(.uppercase)` to all button label styling**
In each ButtonStyle (`Primary`, `Secondary`, `Destructive`, `Icon`), add `.textCase(.uppercase)` to the label configuration. This makes all buttons ALL CAPS per website spec.

**Step 2: Remove any shadow modifiers from buttons**

**Step 3: Ensure border widths reference `OPSStyle.Layout.Border.standard`**

---

### Task 9: Update CardStyles.swift

**Files:**
- Modify: `OPS/Styles/Components/CardStyles.swift`

**Step 1: Remove all `.shadow()` modifiers from card styles**
Replace `OPSCardStyle.Elevated` — instead of shadow elevation, use lighter surface color (`OPSStyle.Colors.cardBackground`) vs standard (`OPSStyle.Colors.cardBackgroundDark`).

**Step 2: Update border widths to use `OPSStyle.Layout.Border.standard`**

**Step 3: Ensure corner radius params default to `OPSStyle.Layout.cardCornerRadius` (now 4.0)**

---

### Task 10: Update Form Components

**Files:**
- Modify: `OPS/Styles/Components/FormInputs.swift`
- Modify: `OPS/Styles/Components/FormTextField.swift`

**Step 1: Replace any hardcoded corner radius, font, color, or opacity values**
Both files should reference OPSStyle tokens exclusively.

**Step 2: Replace any `.shadow()` calls**

**Step 3: Ensure input borders use `OPSStyle.Colors.inputFieldBorder` (now 10% white)**

---

### Task 11: Update Remaining Styles/Components Files

**Files (13 files):**
- `CategoryCard.swift`
- `ExpandableSection.swift`
- `IconBadge.swift`
- `ListItems.swift`
- `NotesDisplayField.swift`
- `ProfileCard.swift`
- `SectionCard.swift`
- `SegmentedControl.swift`
- `SettingsHeader.swift`
- `StandardSheetToolbar.swift`
- `StatusBadge.swift`
- `TaskLineItem.swift`
- `OPSComponents.swift` (documentation index — update descriptions)

**For each file:**
1. Replace all hardcoded colors with OPSStyle.Colors tokens
2. Replace all hardcoded fonts with OPSStyle.Typography tokens
3. Replace all hardcoded corner radii with OPSStyle.Layout tokens
4. Replace all hardcoded border widths with OPSStyle.Layout.Border tokens
5. Remove all `.shadow()` modifiers on dark backgrounds
6. Replace hardcoded opacity values with OPSStyle.Layout.Opacity or named overlay tokens

---

### Task 12: Remove Duplicate Button Styles

**Files:**
- Modify: `OPS/Views/JobBoard/ProjectManagementSheets.swift`
- Modify: `OPS/Onboarding/Views/Components/OnboardingComponents.swift`

**Step 1: In ProjectManagementSheets.swift**
Remove local `JBPrimaryButtonStyle`, `JBSecondaryButtonStyle`, `DestructiveButtonStyle` definitions. Replace usages with `OPSButtonStyle.Primary`, `OPSButtonStyle.Secondary`, `OPSButtonStyle.Destructive`.

**Step 2: In OnboardingComponents.swift**
Remove local `PrimaryButtonStyle`, `SecondaryButtonStyle`. Replace usages with `OPSButtonStyle.Primary`, `OPSButtonStyle.Secondary`.

---

### Task 13: Remove Legacy ViewModifiers from OPSStyle.swift

**Files:**
- Modify: `OPS/Styles/OPSStyle.swift` (lines 551-665, the legacy section)

**Step 1: Check for any remaining callers of legacy modifiers**
Search for: `.primaryButtonStyle()`, `.secondaryButtonStyle()`, `.iconButtonStyle()`, `.cardStyle(`

**Step 2: If callers exist, migrate them to new `ops*` equivalents**
- `.primaryButtonStyle()` → `.opsPrimaryButtonStyle()`
- `.secondaryButtonStyle()` → `.opsSecondaryButtonStyle()`
- `.iconButtonStyle()` → `.opsIconButtonStyle()`
- `.cardStyle(` → `.opsCardStyle(`

**Step 3: Once no callers remain, delete the legacy `PrimaryButton`, `SecondaryButton`, `IconActionButton` ViewModifiers and their View extensions**

---

### Task 14: Commit Phase 2

```bash
git add OPS/Styles/ OPS/Views/JobBoard/ProjectManagementSheets.swift OPS/Onboarding/
git commit -m "Phase 2: Update component styles — remove shadows, standardize tokens

- ButtonStyles: Kosugi ALL CAPS, remove shadows
- CardStyles: borders-only depth, no shadows
- FormInputs: 10% border opacity
- Remove duplicate button styles in JobBoard and Onboarding
- Migrate legacy ViewModifiers to ops* equivalents"
```

---

## Phase 3: Hardcoded Font Replacement (688 occurrences, 176 files)

This is the largest single category. Process each directory group, replacing `.font(.system(...))` with the appropriate `OPSStyle.Typography` token.

### Font Mapping Guide

| Hardcoded Pattern | Replace With |
|-------------------|-------------|
| `.font(.system(size: 10))` | `.font(OPSStyle.Typography.smallCaption)` |
| `.font(.system(size: 11))` | `.font(OPSStyle.Typography.smallCaption)` |
| `.font(.system(size: 12))` | `.font(OPSStyle.Typography.smallCaption)` |
| `.font(.system(size: 12, weight: .medium))` | `.font(OPSStyle.Typography.captionBold)` |
| `.font(.system(size: 12, weight: .semibold))` | `.font(OPSStyle.Typography.captionBold)` |
| `.font(.system(size: 12, weight: .bold))` | `.font(OPSStyle.Typography.captionBold)` |
| `.font(.system(size: 14))` | `.font(OPSStyle.Typography.caption)` |
| `.font(.system(size: 14, weight: .medium))` | `.font(OPSStyle.Typography.bodyBold)` (14pt Mohave-Medium closest) |
| `.font(.system(size: 14, weight: .semibold))` | `.font(OPSStyle.Typography.bodyEmphasis)` |
| `.font(.system(size: 15))` | `.font(OPSStyle.Typography.cardSubtitle)` |
| `.font(.system(size: 16))` | `.font(OPSStyle.Typography.body)` |
| `.font(.system(size: 16, weight: .medium))` | `.font(OPSStyle.Typography.bodyBold)` |
| `.font(.system(size: 16, weight: .semibold))` | `.font(OPSStyle.Typography.bodyEmphasis)` |
| `.font(.system(size: 18))` | `.font(OPSStyle.Typography.cardTitle)` |
| `.font(.system(size: 18, weight: .medium))` | `.font(OPSStyle.Typography.cardTitle)` |
| `.font(.system(size: 20))` | `.font(OPSStyle.Typography.subtitle)` (closest at 22pt) or new token |
| `.font(.system(size: 20, weight: .medium))` | `.font(OPSStyle.Typography.subtitle)` |
| `.font(.system(size: 22))` | `.font(OPSStyle.Typography.subtitle)` |
| `.font(.system(size: 24))` | `.font(OPSStyle.Typography.title)` (closest at 28pt) or new token |
| `.font(.system(size: 28))` | `.font(OPSStyle.Typography.title)` |
| `.font(.system(size: 32))` | `.font(OPSStyle.Typography.largeTitle)` |
| `.font(.system(size: 48))` | New token needed: `displayLarge` |
| `.font(.system(size: 60))` | New token needed: `displayXL` |

**Before starting Phase 3, add missing typography tokens to Fonts.swift + OPSStyle.swift:**

```swift
// In Fonts.swift:
/// Heading text - Mohave Medium (20pt)
public static var heading: Font {
    return Font.custom("Mohave-Medium", size: 20)
}

/// Large heading text - Mohave SemiBold (24pt)
public static var headingLarge: Font {
    return Font.custom("Mohave-SemiBold", size: 24)
}

/// Display large - Mohave Bold (48pt)
public static var displayLarge: Font {
    return Font.custom("Mohave-Bold", size: 48)
}

/// Display extra large - Mohave Bold (60pt)
public static var displayXL: Font {
    return Font.custom("Mohave-Bold", size: 60)
}
```

```swift
// In OPSStyle.Typography:
static let heading = Font.heading
static let headingLarge = Font.headingLarge
static let displayLarge = Font.displayLarge
static let displayXL = Font.displayXL
```

### Task 15: Replace Hardcoded Fonts — Views/Components/ (69 files)

Process all files in `Views/Components/` and subdirectories:
- Cards/ (5 files)
- Common/ (26 files)
- Client/ (2 files)
- Project/ (9 files)
- Contact/, Event/, Images/, Map/, Scheduling/, Sync/, Task/, Tasks/, Team/, User/ (27 files)

For each file: find all `.font(.system(...))`, replace using mapping guide above. Also replace direct `.font(.body)`, `.font(.caption)` shorthand with `OPSStyle.Typography.*`.

### Task 16: Replace Hardcoded Fonts — Views/JobBoard/ + Calendar/ + Settings/ (57 files)

- JobBoard/ (19 files)
- Calendar Tab/ (15 files)
- Settings/ (23 files)

### Task 17: Replace Hardcoded Fonts — Pipeline/ + Invoices/ + Products/ + Estimates/ + Inventory/ + Accounting/ + Subscription/ (41 files)

- Pipeline/ (12 files)
- Invoices/ (4 files)
- Products/ (2 files)
- Estimates/ (6 files)
- Inventory/ (12 files)
- Accounting/ (1 file)
- Subscription/ (4 files)

### Task 18: Replace Hardcoded Fonts — Map/ + Onboarding/ + Tutorial/ + Top-level views (52 files)

- Map/Views/ (9 files)
- Onboarding/ (23 files)
- Tutorial/ (10 files including Wrappers/Flows)
- Top-level views (10 files including Home/)

### Task 19: Replace Hardcoded Fonts — Navigation/ + Debug/ + V2/ (10 files)

- Navigation/ (1 file)
- Debug/ (8 files)
- V2/ (1 file)

### Task 20: Commit Phase 3

```bash
git add OPS/Styles/Fonts.swift OPS/Styles/OPSStyle.swift OPS/Views/ OPS/Map/ OPS/Onboarding/ OPS/Tutorial/ OPS/Navigation/ OPS/V2/
git commit -m "Phase 3: Replace 688 hardcoded .font(.system()) with OPSStyle.Typography tokens

- Add heading, headingLarge, displayLarge, displayXL typography tokens
- All views now use Mohave/Kosugi via OPSStyle.Typography exclusively
- No more .font(.system()) calls in production views"
```

---

## Phase 4: Hardcoded Color Replacement

### Color Replacement Rules

| Hardcoded Pattern | Replace With |
|-------------------|-------------|
| `Color.white` (as foreground) | `OPSStyle.Colors.primaryText` |
| `Color.white.opacity(0.1)` | `OPSStyle.Colors.subtleBackground` |
| `Color.white.opacity(0.15)` | `OPSStyle.Colors.separator` |
| `Color.white.opacity(0.2)` | `OPSStyle.Colors.cardBorder` |
| `Color.white.opacity(0.05)` | `OPSStyle.Colors.cardBorderSubtle` |
| `Color.white.opacity(0.08)` | `OPSStyle.Colors.cardBorderSubtle` |
| `Color.white.opacity(0.3)` | `OPSStyle.Colors.pinDotNeutral` |
| `Color.white.opacity(0.5)` | `OPSStyle.Colors.pageIndicatorInactive` |
| `Color.black` (as background) | `OPSStyle.Colors.background` |
| `Color.black.opacity(0.5)` | `OPSStyle.Colors.modalOverlay` |
| `Color.black.opacity(0.3)` | `OPSStyle.Colors.avatarOverlay` |
| `Color.black.opacity(0.6)` | `OPSStyle.Colors.overlayMedium` |
| `Color.black.opacity(0.7)` | `OPSStyle.Colors.overlayStrong` |
| `Color.black.opacity(0.85)` | `OPSStyle.Colors.overlayHeavy` |
| `Color.black.opacity(0.8)` | `OPSStyle.Colors.overlayStrong` (closest) |
| `Color.clear` | `Color.clear` (keep — this is a SwiftUI primitive) |
| `Color.gray` | `OPSStyle.Colors.tertiaryText` or `inactiveStatus` by context |
| `Color.red` | `OPSStyle.Colors.errorStatus` |
| `Color.green` | `OPSStyle.Colors.successStatus` |
| `Color.orange` | `OPSStyle.Colors.warningStatus` |
| `Color.blue` | `OPSStyle.Colors.primaryAccent` |

**Note:** `Color(hex:)` calls in DataModels (e.g., `ProjectTask.swift` status colors) should remain — these are data-driven colors, not UI styling.

### Task 21: Replace Hardcoded Colors — Views/Components/ (69 files)

Process all files in Views/Components/ and subdirectories. For each file:
1. Replace `Color.white` foreground uses → `OPSStyle.Colors.primaryText`
2. Replace `Color.white.opacity(X)` → appropriate named token
3. Replace `Color.black.opacity(X)` → appropriate named token
4. Replace `Color.black` background uses → `OPSStyle.Colors.background`
5. Replace color literals (`.red`, `.green`, `.orange`, `.blue`, `.gray`) → OPSStyle equivalents
6. Replace `Color(hex:)` UI styling calls → OPSStyle tokens (leave data model hex colors)

### Task 22: Replace Hardcoded Colors — Views/JobBoard/ + Calendar/ + Settings/ (57 files)

Same process as Task 21.

### Task 23: Replace Hardcoded Colors — Pipeline/ + Invoices/ + Products/ + Estimates/ + Inventory/ + Subscription/ + Accounting/ (41 files)

Same process as Task 21.

### Task 24: Replace Hardcoded Colors — Map/ + Onboarding/ + Tutorial/ + Top-level views + Navigation/ (53 files)

Same process as Task 21.

### Task 25: Commit Phase 4

```bash
git add OPS/Views/ OPS/Map/ OPS/Onboarding/ OPS/Tutorial/ OPS/Navigation/
git commit -m "Phase 4: Replace hardcoded colors with OPSStyle.Colors tokens

- 347 Color(.white/.black) → named tokens
- 118 Color.white.opacity() → subtleBackground/separator/cardBorder
- 36 Color.black.opacity() → overlay tokens
- 62 color literals → status/accent tokens
- 135 Color(hex:) UI styling calls → OPSStyle tokens"
```

---

## Phase 5: Corner Radii, Border Widths, Shadow Removal

### Task 26: Replace Hardcoded Corner Radii (137 occurrences, 61 files)

| Hardcoded Value | Replace With |
|----------------|-------------|
| `.cornerRadius(2)` | `.cornerRadius(OPSStyle.Layout.smallCornerRadius)` |
| `.cornerRadius(3)` | `.cornerRadius(OPSStyle.Layout.cornerRadius)` |
| `.cornerRadius(4)` | `.cornerRadius(OPSStyle.Layout.cardCornerRadius)` |
| `.cornerRadius(5)` | `.cornerRadius(OPSStyle.Layout.cardCornerRadius)` |
| `.cornerRadius(6)` | `.cornerRadius(OPSStyle.Layout.cardCornerRadius)` |
| `.cornerRadius(8)` | `.cornerRadius(OPSStyle.Layout.cardCornerRadius)` |
| `.cornerRadius(10)` | `.cornerRadius(OPSStyle.Layout.largeCornerRadius)` |
| `.cornerRadius(12)` | `.cornerRadius(OPSStyle.Layout.largeCornerRadius)` |
| `.cornerRadius(16)` | `.cornerRadius(OPSStyle.Layout.largeCornerRadius)` |

Process all 61 files across all directories.

### Task 27: Replace Hardcoded Border Widths (486 occurrences)

| Hardcoded Value | Replace With |
|----------------|-------------|
| `lineWidth: 1` | `lineWidth: OPSStyle.Layout.Border.standard` |
| `lineWidth: 1.5` | `lineWidth: OPSStyle.Layout.Border.standard` |
| `lineWidth: 2` | `lineWidth: OPSStyle.Layout.Border.thick` |

Process all files.

### Task 28: Remove All Shadow Modifiers on Dark Backgrounds

Search for `.shadow(` across all view files. Remove every occurrence where the shadow is rendered on a dark background (which is nearly all of them in this app).

**Exception:** Keep shadows on light-theme elements (Onboarding Light theme screens).

### Task 29: Commit Phase 5

```bash
git add OPS/
git commit -m "Phase 5: Corner radii, border widths, shadow removal

- 137 hardcoded cornerRadius → OPSStyle.Layout tokens
- 486 hardcoded lineWidth → OPSStyle.Layout.Border tokens
- Remove all shadows on dark backgrounds (borders-only depth)"
```

---

## Phase 6: Animations, Padding, Overlays

### Task 30: Replace Hardcoded Animation Durations (300+ occurrences)

| Hardcoded Pattern | Replace With |
|-------------------|-------------|
| `.easeInOut(duration: 0.3)` | `OPSStyle.Animation.standard` |
| `.easeInOut(duration: 0.2)` | `OPSStyle.Animation.fast` |
| `.easeOut(duration: 0.15)` | `OPSStyle.Animation.faster` |
| `.spring(response: 0.3, dampingFraction: 0.7)` | `OPSStyle.Animation.spring` |
| `.spring(response: 0.2, dampingFraction: 0.7)` | `OPSStyle.Animation.springFast` |
| `withAnimation(.easeInOut(duration: 0.3))` | `withAnimation(OPSStyle.Animation.standard)` |
| `withAnimation { }` (no argument) | Keep as-is (SwiftUI default is fine) |

Process all files.

### Task 31: Replace Common Hardcoded Padding Values

Priority replacements (highest-count patterns only):

| Hardcoded Pattern | Replace With |
|-------------------|-------------|
| `.padding(.horizontal, 16)` (184x) | `.padding(.horizontal, OPSStyle.Layout.spacing3)` |
| `.padding(.horizontal, 20)` (170x) | `.padding(.horizontal, OPSStyle.Layout.spacing3_5)` |
| `.padding(.vertical, 12)` (135x) | `.padding(.vertical, OPSStyle.Layout.spacing2_5)` |
| `.padding(.vertical, 14)` (88x) | `.padding(.vertical, OPSStyle.Layout.spacing2_5)` |
| `.padding(.vertical, 8)` (77x) | `.padding(.vertical, OPSStyle.Layout.spacing2)` |
| `.padding(.horizontal, 40)` (75x) | `.padding(.horizontal, OPSStyle.Layout.spacing5)` + note: 40 ≠ 32, may need `spacing6 = 40.0` |
| `.padding(.vertical, 16)` (68x) | `.padding(.vertical, OPSStyle.Layout.spacing3)` |
| `.padding(.horizontal, 24)` (54x) | `.padding(.horizontal, OPSStyle.Layout.spacing4)` |
| `.padding(.horizontal, 8)` (59x) | `.padding(.horizontal, OPSStyle.Layout.spacing2)` |

**Note:** `.padding(.horizontal, 40)` appears 75 times but `spacing5 = 32`. Before replacing, decide: add `spacing6 = 40.0`, or adjust these to 32. Ask user if unclear.

### Task 32: Replace Hardcoded Icon Frame Sizes

| Hardcoded Pattern | Replace With |
|-------------------|-------------|
| `.frame(width: 8, height: 8)` (31x) | `.frame(width: OPSStyle.Layout.Indicator.dotMD, height: OPSStyle.Layout.Indicator.dotMD)` |
| `.frame(width: 6, height: 6)` (10x) | `.frame(width: OPSStyle.Layout.Indicator.dotSM, height: OPSStyle.Layout.Indicator.dotSM)` |
| `.frame(width: 16, ...)` | `.frame(width: OPSStyle.Layout.IconSize.sm, ...)` |
| `.frame(width: 20, ...)` | `.frame(width: OPSStyle.Layout.IconSize.md, ...)` |
| `.frame(width: 24, ...)` | `.frame(width: OPSStyle.Layout.IconSize.lg, ...)` |
| `.frame(width: 32, ...)` | `.frame(width: OPSStyle.Layout.IconSize.xl, ...)` |

### Task 33: Adopt ultraThinMaterial for Overlays

Search for sheet/popup/tooltip backgrounds using solid colors. Replace with `.ultraThinMaterial`:

**Key files to check:**
- `StandardSheetToolbar.swift` — sheet backgrounds
- `FilterSheet.swift`, `ProjectListFilterSheet.swift`, `TaskListFilterSheet.swift` — filter sheets
- `ContactDetailSheet.swift` — popup overlay
- `DeletionSheet.swift` — confirmation overlay
- `TutorialInlineSheet.swift`, `TutorialOverlayView.swift` — tutorial overlays
- `FloatingActionMenu.swift` — FAB menu overlay
- `CustomAlert.swift` — alert background
- `LoadingOverlay.swift` — loading screen

For each: replace solid `.background(OPSStyle.Colors.cardBackgroundDark)` or `.background(Color.black.opacity(...))` with `.background(.ultraThinMaterial)` where the element overlays other content.

### Task 34: Commit Phase 6

```bash
git add OPS/
git commit -m "Phase 6: Replace hardcoded animations, padding, icon sizes, adopt ultraThinMaterial

- 300+ animation durations → OPSStyle.Animation tokens
- 800+ padding values → OPSStyle.Layout.spacing tokens
- Icon frame sizes → OPSStyle.Layout.IconSize tokens
- Sheets/popups/tooltips use .ultraThinMaterial"
```

---

## Phase 7: secondaryAccent Migration

### Task 35: Migrate secondaryAccent References (22 references)

Based on the audit, replace each reference contextually:

**Keep as secondaryAccent (valid active-state use — 6 refs):**
- `Map/Views/MapView.swift:232` — active project pin
- `Map/Views/MapViewAlternative.swift:170` — active project pin
- `Map/Views/MapViewAlternative.swift:279,281` — "Current Project" label
- `Map/Views/ProjectMarkerPopup.swift:112` — "CURRENT PROJECT" label
- `Views/Components/Map/ProjectMapAnnotation.swift:97` — active project annotation

**Note:** Since `AccentSecondary` asset now equals `AccentPrimary` (#597794), these will automatically show the new color. No code change needed — just leave the references until a future cleanup pass removes the alias.

**Replace with primaryAccent (interactive elements — 12 refs):**
- `ProjectMapAnnotation.swift:146` — pulse halo → `primaryAccent.opacity(0.15)`
- `CalendarSchedulerSheet.swift:286,302` — filter toggle → `primaryAccent`
- `OpportunityBadgeView.swift:22,26,39,43` — badge icon/label/bg/border → `primaryAccent`
- `TeamMemberListView.swift:119,186` — call button → `primaryAccent`
- `CompanyTeamMembersListView.swift:108,122` — email/call buttons → `primaryAccent`
- `ContactDetailSheet.swift:35` — avatar bg → `primaryAccent`
- `ProjectCard.swift:79` — "Start Project?" text → `primaryAccent`
- `ProjectCarousel.swift:254` — "Start Project?" text → `primaryAccent`
- `ProjectImageView.swift:65` — loading spinner → `primaryAccent`

**Replace with appropriate alternative (2 refs):**
- `DayCell.swift:81` — today's date color → `primaryAccent`
- `WhatsNewView.swift:262` — "In Development" status → `OPSStyle.Colors.warningStatus`

### Task 36: Commit Phase 7

```bash
git add OPS/Views/ OPS/Map/
git commit -m "Phase 7: Migrate secondaryAccent — 16 refs to primaryAccent, 6 kept for active-state"
```

---

## Phase 8: Validation + Documentation Update

### Task 37: Build Verification

**Step 1: Build the project**
```bash
cd OPS && xcodebuild -scheme OPS -destination 'platform=iOS Simulator,name=iPhone 16 Pro' build 2>&1 | tail -20
```
Expected: BUILD SUCCEEDED

**Step 2: Fix any build errors from token changes or removals**

### Task 38: Visual Spot Check

Open the app in simulator and verify these key screens:
1. **Home/Dashboard** — background color, card surfaces, text hierarchy
2. **Job Board** — project cards, status badges, search bar
3. **Project Details** — header, task list, map card
4. **Calendar** — day cells, event cards, filter controls
5. **Settings** — category cards, toggles, section headers
6. **Pipeline** — Kanban columns, opportunity cards
7. **Login/Splash** — branding alignment

Verify:
- Accent color `#597794` appears sparingly (buttons, key interactive elements only)
- Background is near-black (not pure black)
- Corners are sharp (2-4px)
- No visible shadows on dark elements
- Status colors (green/amber/red) still visible and readable
- Touch targets still >= 44pt
- Fonts are Mohave/Kosugi throughout (no system font fallbacks)
- Buttons show ALL CAPS text

### Task 39: Update CLAUDE.md Documentation

**Files:**
- Modify: `OPS/CLAUDE.md`

Update the color palette section, typography section, and UI design guidelines to reflect all new values. Key changes:
- Primary Accent: `#597794` (blue-gray), used sparingly
- Background: `#0A0A0A`
- Card Background: `#141414`
- Corner radii: 2-4px
- Shadows: eliminated on dark backgrounds
- Overlays: ultraThinMaterial
- Buttons: Kosugi ALL CAPS
- Remove all references to orange accent (#FF7733)
- Remove references to secondaryAccent as a separate concept
- Update the Accent Colors section to reflect monochromatic design

### Task 40: Final Commit

```bash
git add OPS/CLAUDE.md
git commit -m "Phase 8: Update CLAUDE.md to reflect new website-aligned design system"
```

---

## Summary

| Phase | Tasks | Estimated Scope |
|-------|-------|----------------|
| 1: Foundation tokens | Tasks 1-7 | ~10 asset JSONs + OPSStyle.swift + Fonts.swift |
| 2: Component styles | Tasks 8-14 | ~19 style files + 2 duplicate-removal files |
| 3: Hardcoded fonts | Tasks 15-20 | ~176 view files (688 replacements) |
| 4: Hardcoded colors | Tasks 21-25 | ~176 view files (636 replacements) |
| 5: Radii + borders + shadows | Tasks 26-29 | ~61+ files (623 replacements) |
| 6: Animations + padding + overlays | Tasks 30-34 | ~176 files (1100+ replacements) |
| 7: secondaryAccent migration | Tasks 35-36 | ~15 files (22 replacements) |
| 8: Validation + docs | Tasks 37-40 | Build + visual check + CLAUDE.md |

**Total: 40 tasks, 8 phases, ~235 files touched**
