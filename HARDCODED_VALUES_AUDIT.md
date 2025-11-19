# Hardcoded Values Audit Report
**Date**: November 18, 2025
**Codebase**: OPS iOS App (283 Swift files)

## Executive Summary

Initial analysis significantly underestimated the scope of hardcoded values in the codebase. This comprehensive audit reveals **5,077 total instances** of hardcoded styling values across **150+ files**.

### Key Findings

| Category | Instances | Files | Status |
|----------|-----------|-------|--------|
| Color names | 1,015 | 100+ | ❌ Major violations |
| Color initializers | 357 | 32 | ⚠️ Mixed (some legitimate) |
| Icon strings | 498 | 122 | ❌ Major violations |
| Corner radius | 508 | 81 | ⚠️ Many violations |
| Padding values | 1,904 | 133+ | ⚠️ Context-dependent |
| Opacity values | 795 | 61+ | ⚠️ Context-dependent |
| **TOTAL** | **5,077** | **150+** | **Needs remediation** |

## Detailed Analysis

### 1. Hardcoded Colors (1,372 total instances)

#### 1.1 Color Names: 1,015 instances
**Pattern**: `.white`, `.black`, `.blue`, `.red`, `.green`, `.gray`, etc.

**Examples of violations**:
```swift
// ❌ WRONG: Hardcoded colors
.foregroundColor(.white)  // Should use OPSStyle.Colors.primaryText
.background(.black)       // Should use OPSStyle.Colors.background
.foregroundColor(.blue)   // Should use OPSStyle.Colors.primaryAccent

// ✅ CORRECT: OPSStyle references
.foregroundColor(OPSStyle.Colors.primaryText)
.background(OPSStyle.Colors.background)
.foregroundColor(OPSStyle.Colors.primaryAccent)
```

**Breakdown by color**:
- `.white`: ~400 instances (most should be `primaryText`)
- `.black`: ~300 instances (most should be `background` or `cardBackground`)
- `.gray`: ~150 instances (should be `secondaryText`, `tertiaryText`, or `cardBackground`)
- `.blue`, `.red`, `.green`, etc.: ~165 instances (should use status colors or accents)

**Legitimate exceptions**:
- Onboarding flows (intentionally use light theme with white backgrounds)
- Some modal overlays require pure black backgrounds
- Estimated: ~200 instances are legitimate

**Violations to fix**: ~815 instances

#### 1.2 Color Initializers: 357 instances
**Pattern**: `Color(red:green:blue:)`, `Color(hex:)`, `Color(uiColor:)`

**Top violators**:
- `OPS/Views/JobBoard/TaskTypeEditSheet.swift`: 74 instances
- `OPS/Views/Settings/TaskSettingsView.swift`: 147 instances
- `OPS/Views/JobBoard/TaskTypeFormSheet.swift`: 73 instances

**Examples**:
```swift
// ❌ WRONG: Task type color pickers creating colors on the fly
Color(red: Double(red), green: Double(green), blue: Double(blue))

// These are legitimate for color pickers, but should cache to named constants
```

**Assessment**:
- ~220 instances in TaskType color pickers (legitimate use)
- ~80 instances in OPSStyle.swift defining the color system (legitimate)
- ~57 instances scattered throughout views (violations - should use OPSStyle)

**Violations to fix**: ~57 instances

### 2. Hardcoded Icons: 498 instances

**Pattern**: `systemName: "icon.name"` not using `OPSStyle.Icons`

**Current state**:
- OPSStyle.Icons defines: ~60 icons
- Total icon usage: 498 instances
- **438 icons are hardcoded strings** (88% violation rate)

**Top violators (files with most hardcoded icons)**:
```
OPS/Views/Settings/TaskSettingsView.swift
OPS/Views/JobBoard/TaskFormSheet.swift
OPS/Views/Components/Project/ProjectDetailsView.swift
OPS/Views/Components/Project/TaskDetailsView.swift
OPS/Views/Settings/SettingsView.swift
```

**Examples of violations**:
```swift
// ❌ WRONG: Hardcoded icon strings
Image(systemName: "chevron.right")
Image(systemName: "person.circle.fill")
Image(systemName: "calendar.badge.clock")

// ✅ CORRECT: OPSStyle references
Image(systemName: OPSStyle.Icons.chevronRight)
Image(systemName: OPSStyle.Icons.personCircleFill)
Image(systemName: OPSStyle.Icons.calendar)  // Need to add calendar.badge.clock
```

**Missing icons from OPSStyle.Icons**:
- Badge variants: `calendar.badge.clock`, `person.badge.plus`, etc.
- Navigation: `arrow.left`, `arrow.right`, `arrow.up`, `arrow.down`
- Actions: `square.and.arrow.up`, `doc.on.doc`, `link`
- System: `gear`, `info.circle`, `exclamationmark.circle`
- ~200+ more SF Symbols used but not defined

**Violations to fix**: ~438 instances (either migrate to existing Icons or add to OPSStyle.Icons)

### 3. Hardcoded Corner Radius: 508 instances

**Pattern**: `.cornerRadius(N)` or `cornerRadius: N` where N is hardcoded

**OPSStyle provides**:
- `OPSStyle.Layout.cornerRadius = 5.0`
- `OPSStyle.Layout.buttonRadius = 5.0`

**Hardcoded values found**:
- `2`, `2.5`: ~40 instances (status badges, small elements)
- `4`, `5`: ~180 instances (many should use OPSStyle.Layout.cornerRadius)
- `6`, `8`: ~120 instances (cards, containers)
- `10`, `12`: ~80 instances (larger cards, modals)
- `16`, `20`, `40`: ~88 instances (special UI elements)

**Examples**:
```swift
// ❌ WRONG: Hardcoded values
.cornerRadius(5)  // Should use OPSStyle.Layout.cornerRadius
.cornerRadius(8)  // Context-specific, but could be OPSStyle.Layout.cardRadius

// ✅ CORRECT: OPSStyle references
.cornerRadius(OPSStyle.Layout.cornerRadius)
.cornerRadius(OPSStyle.Layout.buttonRadius)
```

**Assessment**:
- ~180 instances using `5` should reference OPSStyle
- ~300 instances are context-specific sizes (legitimate if intentional)
- **Recommendation**: Add more corner radius constants to OPSStyle.Layout:
  - `smallCornerRadius = 2.5` (for badges)
  - `cardCornerRadius = 8.0` (for cards)
  - `largeCornerRadius = 12.0` (for modals)

**Violations to fix**: ~180 instances (using 5 but not referencing OPSStyle)

### 4. Hardcoded Padding: 1,904 instances

**Pattern**: `.padding(N)`, `.padding(.horizontal, N)`, etc.

**OPSStyle provides**:
- `spacing1 = 4.0`
- `spacing2 = 8.0`
- `spacing3 = 16.0`
- `spacing4 = 24.0`
- `spacing5 = 32.0`
- `contentPadding = EdgeInsets(...)`

**Common hardcoded values**:
- `4`, `8`, `16`, `24`, `32`: These match OPSStyle.Layout spacings
- `12`, `14`, `18`, `20`: Custom values between defined spacings

**Examples**:
```swift
// ❌ WRONG: Hardcoded spacing
.padding(16)
.padding(.horizontal, 8)

// ✅ CORRECT: OPSStyle references
.padding(OPSStyle.Layout.spacing3)
.padding(.horizontal, OPSStyle.Layout.spacing2)
```

**Assessment**:
- This is the largest category of violations
- Most padding values match defined spacings but don't reference them
- Estimated ~1,200 instances should use OPSStyle.Layout.spacing

**Violations to fix**: ~1,200 instances

### 5. Hardcoded Opacity: 795 instances

**Pattern**: `.opacity(N)` where N is a decimal value

**Common values**:
- `0.1`, `0.2`: Subtle overlays, disabled states
- `0.3`, `0.4`, `0.5`: Medium opacity overlays
- `0.6`, `0.7`, `0.8`: High opacity, loading states
- `0.9`: Almost full opacity

**OPSStyle does NOT provide**: Opacity constants

**Recommendation**: Add opacity constants to OPSStyle.Layout or new OPSStyle.Opacity enum:
```swift
enum Opacity {
    static let subtle = 0.1
    static let light = 0.3
    static let medium = 0.5
    static let strong = 0.7
    static let heavy = 0.9
}
```

**Assessment**: These are context-dependent, but standardization would improve consistency

**Violations to fix**: ~795 instances (if opacity constants are added to OPSStyle)

### 6. Hardcoded Shadows: 42 files

**Pattern**: `.shadow(color:, radius:, x:, y:)` with hardcoded values

**Common patterns**:
```swift
.shadow(color: Color.black.opacity(0.2), radius: 4, x: 0, y: 2)
.shadow(color: Color.black.opacity(0.1), radius: 2, x: 0, y: 1)
```

**Recommendation**: Add shadow presets to OPSStyle:
```swift
enum Shadow {
    static let card = (color: Color.black.opacity(0.1), radius: 4.0, x: 0.0, y: 2.0)
    static let elevated = (color: Color.black.opacity(0.2), radius: 8.0, x: 0.0, y: 4.0)
}
```

## Priority Violations by Impact

### High Priority (Breaking brand consistency)

1. **Color violations**: 815 instances
   - Impact: Inconsistent UI, doesn't respect dark theme, poor brand consistency
   - Files: 100+ files
   - Fix effort: Medium (find/replace with verification)

2. **Icon violations**: 438 instances
   - Impact: Cannot update icons globally, inconsistent iconography
   - Files: 122 files
   - Fix effort: High (requires adding 200+ icons to OPSStyle.Icons first)

### Medium Priority (Code maintainability)

3. **Padding violations**: ~1,200 instances
   - Impact: Inconsistent spacing, difficult to adjust layout globally
   - Files: 133+ files
   - Fix effort: High (very large scope)

4. **Corner radius violations**: 180 instances
   - Impact: Inconsistent UI feel, cannot update globally
   - Files: 81 files
   - Fix effort: Low-Medium

### Low Priority (Nice to have)

5. **Opacity values**: 795 instances
   - Impact: Minor - opacity is often context-specific
   - Recommendation: Add constants for common values
   - Fix effort: Medium

6. **Shadow values**: 42 files
   - Impact: Minor - shadows are relatively consistent
   - Recommendation: Create shadow presets
   - Fix effort: Low

## Recommended Expansion of OPSStyle

### 1. Expand OPSStyle.Icons (High Priority)

Add ~200 commonly used SF Symbols:

```swift
// Navigation
static let arrowLeft = "arrow.left"
static let arrowRight = "arrow.right"
static let arrowUp = "arrow.up"
static let arrowDown = "arrow.down"

// Badges
static let calendarBadgeClock = "calendar.badge.clock"
static let personBadgePlus = "person.badge.plus"

// Actions
static let squareAndArrowUp = "square.and.arrow.up"
static let docOnDoc = "doc.on.doc"
static let link = "link"

// System
static let gear = "gear"
static let infoCircle = "info.circle"
static let exclamationmarkCircle = "exclamationmark.circle"

// ... ~200 more
```

### 2. Expand OPSStyle.Layout (Medium Priority)

Add corner radius variants:

```swift
// Corner radius
static let smallCornerRadius = 2.5  // Badges, small elements
static let cornerRadius = 5.0       // Standard (existing)
static let cardCornerRadius = 8.0   // Cards, containers
static let largeCornerRadius = 12.0 // Modals, sheets
```

Add opacity constants:

```swift
enum Opacity {
    static let subtle = 0.1    // Disabled, very light overlays
    static let light = 0.3     // Light overlays
    static let medium = 0.5    // Medium overlays
    static let strong = 0.7    // Strong overlays
    static let heavy = 0.9     // Almost opaque
}
```

Add shadow presets:

```swift
enum Shadow {
    static let none = (color: Color.clear, radius: 0.0, x: 0.0, y: 0.0)
    static let subtle = (color: Color.black.opacity(0.05), radius: 2.0, x: 0.0, y: 1.0)
    static let card = (color: Color.black.opacity(0.1), radius: 4.0, x: 0.0, y: 2.0)
    static let elevated = (color: Color.black.opacity(0.2), radius: 8.0, x: 0.0, y: 4.0)
    static let floating = (color: Color.black.opacity(0.3), radius: 12.0, x: 0.0, y: 6.0)
}
```

## Remediation Plan

### Phase 1: Expand OPSStyle (1-2 hours)
1. Add 200+ icons to OPSStyle.Icons
2. Add corner radius variants to OPSStyle.Layout
3. Add opacity constants to OPSStyle.Layout
4. Add shadow presets to OPSStyle.Layout

### Phase 2: Fix High Priority Violations (15-20 hours)
1. Migrate 815 color violations
2. Migrate 438 icon violations

### Phase 3: Fix Medium Priority Violations (20-25 hours)
1. Migrate 1,200 padding violations
2. Migrate 180 corner radius violations

### Phase 4: Fix Low Priority Violations (8-10 hours)
1. Migrate opacity values (if constants added)
2. Migrate shadow values (if presets added)

### Total Estimated Effort: 44-57 hours

## Verification Strategy

After remediation:

1. **Grep searches** to verify no hardcoded values remain:
   ```bash
   grep -r "\.foregroundColor(\.white)" --include="*.swift" OPS
   grep -r "systemName: \"" --include="*.swift" OPS | grep -v "OPSStyle.Icons"
   grep -r "\.padding([0-9]" --include="*.swift" OPS | grep -v "OPSStyle.Layout"
   ```

2. **Build and test** to ensure no regressions

3. **Visual inspection** of key screens to verify consistent styling

## Conclusion

The initial estimate of "~50 color instances in 20 files" was off by **27x** (actual: 1,372 color instances in 100+ files).

The actual scope of hardcoded values is:
- **5,077 total instances** across **150+ files**
- **Estimated 2,633 true violations** requiring remediation
- **44-57 hours of work** to fully remediate

This audit provides the accurate scope needed for the CONSOLIDATION_PLAN.md to be executable.
