# OPS UI Design Guidelines

**Purpose**: This document provides Claude (AI assistant) with complete UI design standards, OPSStyle reference, and field-first design principles. This ensures all generated UI code maintains brand consistency and field usability.

**Last Updated**: November 18, 2025

---

## Table of Contents
1. [Design Philosophy](#design-philosophy)
2. [OPSStyle System](#opsstyle-system)
3. [Typography](#typography)
4. [Color System](#color-system)
5. [Layout & Spacing](#layout--spacing)
6. [Component Patterns](#component-patterns)
7. [Gesture Patterns](#gesture-patterns)
8. [Field-First Requirements](#field-first-requirements)
9. [Common Anti-Patterns](#common-anti-patterns)

---

## Design Philosophy

### Brand Essence: Dependable Field Partner

OPS exists to make trade workers' lives easier through technology that "just works" in any environment—dirt, gloves, sunlight, poor connectivity.

### Core Brand Values

1. **Built By Trades, For Trades**
   - Created by actual trade workers
   - Understands real challenges of field work
   - Not designed by "tech people who've never swung a hammer"

2. **No Unnecessary Complexity**
   - No features they'll never use
   - No processes that waste time
   - Every function serves a clear purpose

3. **Reliability Above All**
   - Works when other technologies fail
   - Maintains dependability in harsh conditions
   - Offline-first architecture

4. **Field-First Design**
   - Designed for job sites, not offices
   - Embraces dirt, gloves, sunlight, noise
   - High contrast, large targets, minimal text entry

5. **Time Is Money**
   - Every minute managing software is a minute not billing
   - Quick actions, minimal taps
   - Respect user's time

### Steve Jobs Design Principles (Applied)

1. **Simplicity as Ultimate Sophistication**
   - "Simple can be harder than complex"
   - Deeply understand needs to eliminate unnecessary elements

2. **Human-Centered, Not Technology-Driven**
   - "Start with customer experience, work backwards to technology"
   - Interface adapts to natural human behavior in field

3. **Progressive Disclosure**
   - Reveal complexity gradually
   - Show only what's relevant to current task

4. **Contextual Intelligence**
   - Smart assumptions based on location, time, task patterns
   - Always allow user override

5. **Obsessive Attention to Detail**
   - Perfect every aspect
   - Anticipate edge cases and friction points

---

## OPSStyle System

**Location**: `/Styles/OPSStyle.swift`

**Purpose**: Centralized design system constants. **Never hardcode values.**

### OPSStyle.Colors

#### Background Colors
```swift
// Primary backgrounds - ALWAYS solid, never use opacity
static let background = Color(hex: "#000000")              // Near-black main background
static let cardBackground = Color(hex: "#0D0D0D")          // Card background
static let cardBackgroundDark = cardBackground.opacity(0.8) // Darker variant

// CRITICAL: Never use .opacity() on background colors
// ✅ CORRECT: OPSStyle.Colors.background
// ❌ WRONG: OPSStyle.Colors.background.opacity(0.5)
```

#### Accent Colors
```swift
static let primaryAccent = Color(hex: "#59779F")     // Blue - interactive elements
static let secondaryAccent = Color(hex: "#A5B368")   // ONLY for active items/projects

// Usage Rules:
// - primaryAccent: Buttons, clickable icons, navigation (< 10% of visible UI)
// - secondaryAccent: ONLY indicate active state, never decoration
```

#### Text Colors
```swift
static let primaryText = Color.white                     // Main text content
static let secondaryText = Color.white.opacity(0.7)      // Supporting text, labels
static let tertiaryText = Color.white.opacity(0.5)       // Hints, disabled text
```

#### Border Colors (Added Oct 1, 2025)
```swift
static let cardBorder = Color.white.opacity(0.1)         // Standard card borders
static let cardBorderSubtle = Color.white.opacity(0.05)  // Subtle borders

// CRITICAL: Always use these constants
// ✅ CORRECT: .stroke(OPSStyle.Colors.cardBorder, lineWidth: 1)
// ❌ WRONG: .stroke(Color.white.opacity(0.1), lineWidth: 1)
```

#### Status Colors
```swift
static let successStatus = Color(hex: "#A5B368")   // Muted green
static let warningStatus = Color(hex: "#C4A868")   // Amber
static let errorStatus = Color(hex: "#931A32")     // Deep red
```

#### Project Status Colors
```swift
static let rfqStatus = Color(hex: "#6B7280")       // Gray
static let estimatedStatus = Color(hex: "#F59E0B") // Orange
static let acceptedStatus = Color(hex: "#3B82F6")  // Blue
static let inProgressStatus = Color(hex: "#8B5CF6") // Purple
static let completedStatus = Color(hex: "#10B981")  // Green
static let closedStatus = Color(hex: "#6B7280")     // Gray
static let archivedStatus = Color(hex: "#4B5563")   // Dark gray
```

---

## Typography

### Critical Rules

**MANDATORY**:
- ✅ **ALL text must use** `OPSStyle.Typography` definitions
- ❌ **NEVER use** system fonts: `.font(.system())`, `.font(.title)`, `.font(.body)`
- ❌ **NEVER use** hardcoded sizes: `.font(.system(size: 16))`
- **Required imports**: `import Foundation` + ensure `Fonts.swift` available

### Font Families

**Primary**: Mohave
- Weights: Light, Regular, Medium, SemiBold, Bold
- Use for: Titles, body text, buttons, most UI elements
- Modern, clean, highly legible at all sizes

**Supporting**: Kosugi
- Weight: Regular
- Use for: Subtitles, captions, labels, supporting text
- Excellent small-size legibility, provides visual contrast

**Display**: Bebas Neue
- Weight: Regular
- Use for: Special branding moments ONLY (not regular UI)
- Condensed display font

### OPSStyle.Typography

```swift
// Headers and Titles
static let largeTitle = Font.custom("Mohave-Bold", size: 32)
static let title = Font.custom("Mohave-SemiBold", size: 28)
static let subtitle = Font.custom("Kosugi-Regular", size: 22)

// Body Text
static let body = Font.custom("Mohave-Regular", size: 16)
static let bodyBold = Font.custom("Mohave-Medium", size: 16)
static let bodyEmphasis = Font.custom("Mohave-SemiBold", size: 16)
static let smallBody = Font.custom("Mohave-Light", size: 14)

// Supporting Text
static let caption = Font.custom("Kosugi-Regular", size: 14)
static let captionBold = Font.custom("Kosugi-Regular", size: 14).weight(.semibold)
static let smallCaption = Font.custom("Kosugi-Regular", size: 12)

// UI Elements
static let button = Font.custom("Mohave-SemiBold", size: 16)
static let smallButton = Font.custom("Mohave-Medium", size: 14)
static let status = Font.custom("Mohave-Medium", size: 12)

// Cards
static let cardTitle = Font.custom("Mohave-Medium", size: 18)
static let cardSubtitle = Font.custom("Kosugi-Regular", size: 15)
static let cardBody = Font.custom("Mohave-Regular", size: 14)
```

### Usage Examples

```swift
// ✅ CORRECT
Text("Project Title").font(OPSStyle.Typography.title)
Text("Description").font(OPSStyle.Typography.body)
Text("Status").font(OPSStyle.Typography.status)
Text("Button").font(OPSStyle.Typography.button)

// ❌ WRONG - Will be rejected in code review
Text("Project Title").font(.title)                    // System font
Text("Description").font(.body)                       // System font
Text("Status").font(.caption)                         // System font
Text("Button").font(.system(size: 16))               // Hardcoded
```

### Typography Best Practices

- Maintain consistent font usage across similar UI elements
- Ensure sufficient line spacing for field readability
- Test all text at maximum dynamic type sizes
- Use sentence case for most text (not ALL CAPS except section headers)
- Section headers use `.textCase(.uppercase)` programmatically

---

## Color System

### Background Usage Rules

```swift
// ✅ CORRECT: Solid backgrounds
ZStack {
    OPSStyle.Colors.background.ignoresSafeArea()
    // Content
}

VStack {
    // ...
}
.background(OPSStyle.Colors.cardBackground)

// ❌ WRONG: Opacity modifiers on backgrounds
.background(OPSStyle.Colors.background.opacity(0.5))  // NEVER
```

### Accent Color Guidelines

**Primary Accent** (`OPSStyle.Colors.primaryAccent`):
- Must be < 10% of visible UI colors
- Use for:
  - Primary buttons
  - Clickable icons
  - Main call-to-action elements
  - Navigation elements
  - Interactive state indicators

**Secondary Accent** (`OPSStyle.Colors.secondaryAccent`):
- **ONLY** use to indicate active projects or active state
- **NEVER** use for:
  - General UI decoration
  - Non-active items
  - Backgrounds
  - Borders

### Text Color Hierarchy

```swift
// Primary: Main content
Text("Project Name")
    .foregroundColor(OPSStyle.Colors.primaryText)

// Secondary: Labels, supporting info
Text("Created by:")
    .foregroundColor(OPSStyle.Colors.secondaryText)

// Tertiary: Hints, disabled
Text("No projects found")
    .foregroundColor(OPSStyle.Colors.tertiaryText)
```

### Icon Colors

```swift
// Clickable icons
Image(systemName: OPSStyle.Icons.plusCircle)
    .foregroundColor(OPSStyle.Colors.primaryAccent)

// Non-clickable/informational icons
Image(systemName: OPSStyle.Icons.calendar)
    .foregroundColor(OPSStyle.Colors.primaryText)

// Status icons
Image(systemName: OPSStyle.Icons.checkmarkCircle)
    .foregroundColor(OPSStyle.Colors.successStatus)
```

---

## Layout & Spacing

### OPSStyle.Layout

```swift
static let cornerRadius: CGFloat = 12                // Standard corner radius
static let cardPadding: CGFloat = 16                 // Inside card padding
static let screenMargin: CGFloat = 20                // Screen edge margins
static let cardSpacing: CGFloat = 16                 // Between cards
static let sectionSpacing: CGFloat = 24              // Between sections
static let minimumTouchTarget: CGFloat = 44          // Minimum tap target
static let preferredTouchTarget: CGFloat = 60        // Preferred for primary actions
```

### Grid System

**8pt Layout Grid**: All spacing should be multiples of 8pt.

```swift
// ✅ CORRECT: 8pt multiples
.padding(8)
.padding(16)
.padding(24)
.spacing(16)

// ❌ WRONG: Non-8pt values
.padding(15)
.spacing(10)
```

### Touch Targets

```swift
// Minimum touch target (accessibility requirement)
.frame(minWidth: 44, minHeight: 44)

// Preferred for primary actions
Button(action: createProject) {
    // ...
}
.frame(width: 60, height: 60)

// ❌ WRONG: Too small for gloves
Button(action: delete) {
    Image(systemName: "trash")
}
.frame(width: 30, height: 30)  // Too small!
```

### Screen Organization

**Critical actions at bottom** for thumb accessibility:
```swift
VStack {
    // Header at top
    // Content in middle
    // Primary actions at bottom (easier to reach with thumb)
    Spacer()
    Button("Create Project") { }
        .padding(.bottom, 20)
}
```

---

## Component Patterns

### Section Layout Pattern

**CRITICAL**: Consistency is paramount. Same components must look identical everywhere.

```swift
// ✅ CORRECT: Section header above card
VStack(alignment: .leading, spacing: 8) {
    // Section header (outside card)
    Text("TEAM MEMBERS")
        .font(OPSStyle.Typography.captionBold)
        .foregroundColor(OPSStyle.Colors.secondaryText)
        .textCase(.uppercase)

    // Card with content
    VStack {
        // Card content
    }
    .padding(.vertical, 14)
    .padding(.horizontal, 16)
    .background(
        RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
            .fill(OPSStyle.Colors.cardBackgroundDark.opacity(0.8))
            .overlay(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                    .stroke(OPSStyle.Colors.cardBorder, lineWidth: 1)
            )
    )
}

// ❌ WRONG: Section header inside card
VStack {
    Text("TEAM MEMBERS")  // Don't put header inside card
    // Content
}
.background(...)
```

### Card Styling

```swift
extension View {
    func cardStyle() -> some View {
        self
            .background(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                    .fill(OPSStyle.Colors.cardBackgroundDark)
                    .overlay(
                        RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                            .stroke(OPSStyle.Colors.cardBorder, lineWidth: 1)
                    )
            )
    }
}

// Usage
VStack {
    // Content
}
.padding(16)
.cardStyle()
```

### Button Styles

#### Primary Button
```swift
Button(action: save) {
    Text("Save")
        .font(OPSStyle.Typography.button)
        .foregroundColor(.white)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
}
.background(OPSStyle.Colors.primaryAccent)
.cornerRadius(OPSStyle.Layout.cornerRadius)
```

#### Secondary Button
```swift
Button(action: cancel) {
    Text("Cancel")
        .font(OPSStyle.Typography.button)
        .foregroundColor(OPSStyle.Colors.primaryAccent)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
}
.background(Color.black)
.overlay(
    RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
        .stroke(OPSStyle.Colors.primaryAccent, lineWidth: 2)
)
```

#### Text Button
```swift
Button("Skip") {
    // action
}
.font(OPSStyle.Typography.button)
.foregroundColor(OPSStyle.Colors.primaryAccent)
```

### Form Components

#### Pills & Section Containers (Brighter Borders)
```swift
// For structural elements that group content
HStack {
    // Content
}
.padding(12)
.overlay(
    RoundedRectangle(cornerRadius: 8)
        .stroke(OPSStyle.Colors.secondaryText, lineWidth: 1)
)

// Used for: OptionalSectionPills, ExpandableSections
```

#### Input Fields (Darker Borders)
```swift
// For actual input elements - subtle until focused
TextField("Enter name", text: $name)
    .padding(12)
    .background(OPSStyle.Colors.cardBackground)
    .overlay(
        RoundedRectangle(cornerRadius: 8)
            .stroke(isFocused ? OPSStyle.Colors.primaryAccent : Color.white.opacity(0.1), lineWidth: 1)
    )

// Used for: TextFields, TextEditors, Pickers
```

**Visual Hierarchy**: Structural elements (pills/sections) are more visible, inputs are subtle until focused.

### Icons

**OPSStyle.Icons** - Centralized SF Symbol Constants

**CRITICAL**: Always use `OPSStyle.Icons` constants, never hardcode strings.

```swift
// ✅ CORRECT
Image(systemName: OPSStyle.Icons.calendar)
Image(systemName: OPSStyle.Icons.personFill)
Image(systemName: OPSStyle.Icons.checkmarkSquare)

// ❌ WRONG
Image(systemName: "calendar")           // Hardcoded
Image(systemName: "person.fill")        // Hardcoded
Image(systemName: "checkmark.square")   // Hardcoded
```

### Full-Screen Overlays (Tactical/Minimalist Style)

For important system prompts like lockouts, role assignment, or seat management. Reference implementations: `SubscriptionLockoutView.swift`, `SeatManagementView.swift`, `UnassignedRolesOverlay.swift`.

**Key Principles**:
- Pure black background (0.85 opacity for overlays)
- Small fonts throughout (caption, smallCaption, captionBold)
- Generous spacing between elements
- No card backgrounds - floating content
- White primary buttons, tertiaryText for secondary actions
- No avatars or heavy visual elements
- Header left-aligned with icon on right

```swift
// Header pattern
HStack(alignment: .top, spacing: 0) {
    VStack(alignment: .leading, spacing: 2) {
        Text("TITLE HERE")
            .font(OPSStyle.Typography.bodyBold)
            .foregroundColor(OPSStyle.Colors.primaryText)

        Text("Subtitle description")
            .font(OPSStyle.Typography.caption)
            .foregroundColor(OPSStyle.Colors.secondaryText)
    }

    Spacer()

    Image(systemName: "icon.name")
        .font(.system(size: 20))
        .foregroundColor(OPSStyle.Colors.tertiaryText)
}
.padding(.horizontal, 24)
```

```swift
// List row pattern (no card background)
HStack(spacing: 12) {
    VStack(alignment: .leading, spacing: 2) {
        Text("Primary Text")
            .font(OPSStyle.Typography.caption)
            .foregroundColor(OPSStyle.Colors.primaryText)

        Text("secondary text")
            .font(OPSStyle.Typography.smallCaption)
            .foregroundColor(OPSStyle.Colors.tertiaryText)
    }

    Spacer()

    // Action or status indicator
    Image(systemName: "chevron.down")
        .font(.system(size: 12, weight: .medium))
        .foregroundColor(OPSStyle.Colors.tertiaryText)
}
.padding(.vertical, 16)
.padding(.horizontal, 24)

// Divider between rows
Rectangle()
    .fill(OPSStyle.Colors.tertiaryText.opacity(0.2))
    .frame(height: 1)
    .padding(.horizontal, 24)
```

```swift
// Primary button (white on black)
Button(action: save) {
    Text("SAVE")
        .font(OPSStyle.Typography.captionBold)
        .foregroundColor(.black)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(isEnabled ? Color.white : Color.white.opacity(0.3))
        .cornerRadius(OPSStyle.Layout.cornerRadius)
}
.padding(.horizontal, 24)

// Tertiary text button
Button(action: dismiss) {
    Text("REMIND ME LATER")
        .font(OPSStyle.Typography.smallCaption)
        .foregroundColor(OPSStyle.Colors.tertiaryText)
}
```

**Expandable Selection Pattern** (with descriptions):
```swift
// Collapsed state shows: Name | SELECTED VALUE | chevron
// Expanded state reveals options with descriptions

VStack(spacing: 16) {
    // Option with circle selector
    Button(action: selectOption) {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 18))
                .foregroundColor(isSelected ? OPSStyle.Colors.primaryText : OPSStyle.Colors.tertiaryText)

            VStack(alignment: .leading, spacing: 4) {
                Text("OPTION TITLE")
                    .font(OPSStyle.Typography.captionBold)
                    .foregroundColor(isSelected ? OPSStyle.Colors.primaryText : OPSStyle.Colors.secondaryText)

                Text("Description of what this option does and when to use it.")
                    .font(OPSStyle.Typography.smallCaption)
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
            }

            Spacer()
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 16)
        .background(isSelected ? OPSStyle.Colors.subtleBackground : Color.clear)
        .cornerRadius(OPSStyle.Layout.cornerRadius)
        .overlay(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                .stroke(OPSStyle.Colors.tertiaryText.opacity(0.2), lineWidth: 1)
        )
    }
    .buttonStyle(PlainButtonStyle())
}
```

**Animation TODO**: Current expand/collapse animations use basic `.easeInOut`. Could be improved with spring animations and staggered content reveals.

---

## Gesture Patterns

### Swipe-to-Change-Status

**40% Threshold** with haptic feedback:

```swift
@State private var swipeOffset: CGFloat = 0
@State private var isDragging = false

var body: some View {
    cardContent
        .offset(x: swipeOffset)
        .gesture(
            DragGesture()
                .onChanged { value in
                    // Only horizontal swipes
                    if abs(value.translation.width) > abs(value.translation.height) {
                        isDragging = true
                        swipeOffset = value.translation.width
                    }

                    // Haptic at 40% threshold
                    if abs(swipeOffset) > cardWidth * 0.4 && !hasTriggeredHaptic {
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        hasTriggeredHaptic = true
                    }
                }
                .onEnded { value in
                    if abs(swipeOffset) > cardWidth * 0.4 {
                        // Trigger status change
                        changeStatus()
                    }

                    // Animate back
                    withAnimation(.spring(response: 0.3)) {
                        swipeOffset = 0
                        isDragging = false
                    }
                }
        )
}
```

**Features**:
- 40% threshold before status change
- Directional detection (horizontal vs vertical)
- Minimum 20pt drag distance prevents accidental triggers
- RevealedStatusCard shows target status behind
- Fade-in based on swipe progress
- Multi-phase animation sequence

### Collapsible Sections

**Pattern**: `[ CLOSED ] ------------------ [ 5 ]`

```swift
struct CollapsibleSection<Content: View>: View {
    let title: String
    let count: Int
    @Binding var isExpanded: Bool
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text("[ \(title.uppercased()) ]")
                    .font(OPSStyle.Typography.captionBold)
                    .foregroundColor(OPSStyle.Colors.secondaryText)

                Rectangle()
                    .fill(OPSStyle.Colors.secondaryText)
                    .frame(height: 1)

                Text("[ \(count) ]")
                    .font(OPSStyle.Typography.caption)
                    .foregroundColor(OPSStyle.Colors.secondaryText)

                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .foregroundColor(OPSStyle.Colors.secondaryText)
            }
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    isExpanded.toggle()
                }
            }

            // Content
            if isExpanded {
                content()
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }
}
```

---

## Field-First Requirements

### Testing Checklist

**Test with Gloves**:
- All touch targets work with reduced precision
- Minimum 44×44pt, prefer 60×60pt for primary actions
- No small tap targets (<44pt)

**Test in Sunlight**:
- Contrast ratios verified:
  - Normal text: Minimum 7:1
  - Large text: Minimum 4.5:1
- Dark theme prevents glare
- No subtle color differences for important distinctions

**Test Offline**:
- All critical features work without connectivity
- Changes saved locally with needsSync flag
- Sync when connection restored
- No data loss

**Test on Older Devices**:
- Support 3-year-old hardware minimum
- Smooth performance (no lag)
- Memory efficient
- Battery friendly (dark theme helps)

### Performance Requirements

- **Text sizes**: Minimum 16pt, prefer 18-20pt for important info
- **Touch targets**: Minimum 44×44pt (accessibility), prefer 60×60pt
- **Offline storage**: Cache all data needed for current day's work
- **Sync strategy**: Queue changes locally, sync opportunistically
- **Error handling**: Always provide actionable next steps
- **Every millisecond counts** on older devices

---

## Common Anti-Patterns

### What to Avoid

1. **❌ Never use opacity modifiers on backgrounds**
   - Use appropriate solid color instead
   - Exception: cardBackgroundDark uses opacity

2. **❌ Never use secondaryAccent except for active items**
   - Only for active projects/tasks
   - Not for decoration

3. **❌ Avoid gradients** except main background gradient
   - Stick to solid colors
   - Gradients impact performance

4. **❌ Avoid complex shadows or blur effects**
   - Simple shadows only
   - Blurs hurt performance on older devices

5. **❌ Don't center large blocks of text**
   - Use left alignment for readability
   - Center only for titles/headers

6. **❌ Don't use decorative elements**
   - Everything serves a functional purpose
   - No decoration for decoration's sake

7. **❌ Never sacrifice functionality for aesthetics**
   - Field usability always comes first
   - Pretty but unusable = failure

8. **❌ Avoid tiny touch targets**
   - Remember users wear gloves
   - Minimum 44×44pt required

9. **❌ Don't use low contrast**
   - Must be readable in direct sunlight
   - Test outdoors in bright conditions

10. **❌ Avoid complex gestures**
    - Simple taps and swipes only
    - No multi-finger gestures
    - No long press for critical functions

11. **❌ Never hardcode SF Symbol strings**
    - Always use OPSStyle.Icons constants
    - Enables centralized updates

12. **❌ Avoid .id() modifiers on TabView or NavigationStack**
    - Causes view recreation
    - Performance issues
    - SwiftData model invalidation

13. **❌ Never hardcode border colors**
    - Always use `OPSStyle.Colors.cardBorder` or `cardBorderSubtle`
    - Never `Color.white.opacity(0.1)` inline

14. **❌ Never nest cards within cards**
    - No double backgrounds
    - Single visual hierarchy level

### Quick Decision Matrix

When in doubt:
1. Choose **reliability** over features
2. Choose **simplicity** over flexibility
3. Choose **clarity** over cleverness
4. Choose **field needs** over office preferences
5. Choose **proven patterns** over innovation

---

## Accessibility

### VoiceOver Support

```swift
// Card accessibility
cardContent
    .accessibilityElement(children: .combine)
    .accessibilityLabel("Project: \(project.name)")
    .accessibilityHint("Tap to view details")
    .accessibilityAddTraits(.isButton)

// Button accessibility
Button(action: delete) {
    Image(systemName: OPSStyle.Icons.trash)
}
.accessibilityLabel("Delete project")
.accessibilityHint("Permanently removes this project")
```

### Dynamic Type Support

- All text respects Dynamic Type settings
- Maintain minimum touch targets at all sizes
- Adjust layout for larger text sizes
- Test at maximum accessibility sizes

### Color Contrast

- Ensure 7:1 ratio for normal text
- Ensure 4.5:1 ratio for large text (18pt+)
- Use OPSStyle colors (already compliant)
- Test in high contrast modes

---

## Voice & Tone in UI

### Brand Voice Principles

- **Direct** - Get to the point without unnecessary words
- **Practical** - Focus on solutions, not theory
- **Dependable** - Communicate consistently and reliably
- **Genuine** - Avoid corporate speak and marketing hype
- **Field-Appropriate** - Simple language without being condescending

### UI Copy Examples

**DO SAY**:
- "No signal? No problem. Your changes will sync when you're back online."
- "Tap once to update status. Done."
- "Can't connect right now. We'll save your changes and try again."

**DON'T SAY**:
- "Network synchronization failure. Retry or check system settings."
- "Please ensure optimal connectivity for best performance."
- "An error occurred while processing your request. Please try again later."

---

## Measuring Success

A successful OPS interface:
- ✅ Can be operated with work gloves on
- ✅ Remains readable in direct sunlight
- ✅ Loads quickly even on 3-year-old devices
- ✅ Works fully offline and syncs seamlessly
- ✅ Reduces time-to-task completion
- ✅ Feels "invisible" - users focus on work, not the app

---

**End of UI_GUIDELINES.md**

This document provides Claude with complete UI design standards for maintaining brand consistency and field-first usability in all generated code.
