# OPS App UI Design Guidelines

This document outlines the core UI design principles and guidelines for the OPS application. All UI development should adhere to these standards to maintain visual consistency and follow the brand identity.

## Design Philosophy

### Core Brand Values
1. **Built By Trades, For Trades** - Created by actual trade workers who understand the real challenges of managing projects and crews in the field, not tech people who've "never swung a hammer."

2. **No Unnecessary Complexity** - We don't burden users with features they'll never use or processes that take more time than they save. Every function serves a clear purpose.

3. **Reliability Above All** - In the field, reliability isn't a feature—it's a requirement. OPS works when other technologies fail.

4. **Field-First Design** - Every aspect of OPS is designed for the realities of job sites, not office environments. We embrace dirt, gloves, sunlight, and noise.

5. **Time Is Money** - We respect that every minute spent managing software is a minute not spent on billable work.

### Design Principles (Inspired by Steve Jobs)

1. **Simplicity as Ultimate Sophistication** - "Simple can be harder than complex." We deeply understand user needs to eliminate unnecessary elements.

2. **Human-Centered, Not Technology-Driven** - "Start with the customer experience and work backwards to the technology." The interface adapts to natural human behavior in field conditions.

3. **Progressive Disclosure** - Reveal complex functionality gradually, showing only what's relevant to the current task.

4. **Contextual Intelligence** - Make smart assumptions based on location, time, and task patterns while allowing user override.

5. **Obsessive Attention to Detail** - Perfect every aspect, anticipating edge cases and potential friction points in field use.

### Practical Implementation

1. **Offline-First Architecture** - All critical operations work locally first with intelligent sync when connected.

2. **Field-Optimized Interface** - Dark mode default, large touch targets (60×60px preferred), minimal text entry, high contrast.

3. **Simplified Workflows** - One-tap status updates, photo documentation without app switching, minimal steps for common tasks.

4. **Reliable Performance** - Battery-efficient operation, quick loading on older devices, graceful degradation.

5. **Clear Visual Hierarchy** - Three levels: Primary (current task), Secondary (supporting info), Tertiary (background info).

## Typography

The OPS app uses custom fonts to create a distinctive brand identity while maintaining excellent readability in field conditions:

### Font Families

- **Mohave** (Primary Font)
  - Used for: Titles, body text, buttons, and most UI elements
  - Weights: Light, Regular, Medium, SemiBold, Bold
  - Characteristics: Modern, clean, highly legible at all sizes

- **Kosugi** (Supporting Font)
  - Used for: Subtitles, captions, labels, and supporting text
  - Weight: Regular
  - Characteristics: Excellent small-size legibility, provides visual contrast

- **Bebas Neue** (Display Font)
  - Used for: Special branding moments only (not part of regular UI)
  - Weight: Regular
  - Characteristics: Condensed display font

### Font Usage Guidelines

1. **Headers and Titles**
   - Large Title: `Font.largeTitle` (Mohave Bold, 32pt)
   - Title: `Font.title` (Mohave SemiBold, 28pt)
   - Subtitle: `Font.subtitle` (Kosugi Regular, 22pt)

2. **Body Text**
   - Body: `Font.body` (Mohave Regular, 16pt)
   - Body Bold: `Font.bodyBold` (Mohave Medium, 16pt)
   - Body Emphasis: `Font.bodyEmphasis` (Mohave SemiBold, 16pt)
   - Small Body: `Font.smallBody` (Mohave Light, 14pt)

3. **Supporting Text**
   - Caption: `Font.caption` (Kosugi Regular, 14pt)
   - Small Caption: `Font.smallCaption` (Kosugi Regular, 12pt)

4. **UI Elements**
   - Button: `Font.button` (Mohave SemiBold, 16pt)
   - Small Button: `Font.smallButton` (Mohave Medium, 14pt)
   - Status: `Font.status` (Mohave Medium, 12pt)

5. **Cards**
   - Card Title: `Font.cardTitle` (Mohave Medium, 18pt)
   - Card Subtitle: `Font.cardSubtitle` (Kosugi Regular, 15pt)
   - Card Body: `Font.cardBody` (Mohave Regular, 14pt)

### Typography Best Practices

- Always use the custom Font extensions defined in `Fonts.swift`
- Never use system fonts unless specifically required for platform integration
- Maintain consistent font usage across similar UI elements
- Ensure sufficient line spacing for field readability
- Test all text at maximum dynamic type sizes
- **IMPORTANT**: All UI text must use OPS fonts (Mohave, Kosugi) - no `.system()` fonts allowed

## Color Usage Guidelines

### Background Colors
- **Primary Background**: Always use solid `OPSStyle.Colors.background` (near black) for main screens.
- **Card Background**: Use `OPSStyle.Colors.cardBackground` or `OPSStyle.Colors.cardBackgroundDark` for cards and content containers.
- **IMPORTANT**: Never use opacity modifiers (e.g., `.opacity(0.5)`) on background colors. Instead, use the appropriate solid color for the context.

### Accent Colors
- **Primary Accent** (`OPSStyle.Colors.primaryAccent`): Use for:
  - Primary interactive elements (buttons, clickable icons)
  - Main call-to-action elements
  - Navigation elements
  - Must be less than 10% of visible UI colors

- **Secondary Accent** (`OPSStyle.Colors.secondaryAccent`): 
  - **ONLY** use to indicate active projects or active state
  - Never use for general UI elements, decoration, or non-active items

### Text Colors
- **Primary Text** (`OPSStyle.Colors.primaryText`): Use for:
  - Main text content
  - Non-clickable icons
  - Headers and titles

- **Secondary Text** (`OPSStyle.Colors.secondaryText`): Use for:
  - Supporting text
  - Labels
  - Subtitles and captions

- **Tertiary Text** (`OPSStyle.Colors.tertiaryText`): Use for:
  - Hints and less important information
  - Disabled text

### Status Colors
- Use appropriate status colors for their semantic meaning only:
  - `OPSStyle.Colors.successStatus`: For successful actions/operations
  - `OPSStyle.Colors.warningStatus`: For warnings and caution states
  - `OPSStyle.Colors.errorStatus`: For errors and destructive actions

## Component Styling Guidelines

### Buttons
1. **Primary Button**: 
   - Background: `OPSStyle.Colors.primaryAccent`
   - Text: White
   - Used for main actions on a screen

2. **Secondary Button**:
   - Background: Black
   - Text/Border: `OPSStyle.Colors.primaryAccent`
   - Used for alternative actions

3. **Text Button**:
   - No background
   - Text: `OPSStyle.Colors.primaryAccent`
   - Used for tertiary actions

### Cards
- **Always use solid backgrounds** without opacity modifiers
- Corner radius should be consistent: `OPSStyle.Layout.cornerRadius`
- Shadow (if used) should be solid black without opacity: `.shadow(color: Color.black, radius: 4, x: 0, y: 2)`

### Icons
- **Clickable Icons**: Use `OPSStyle.Colors.primaryAccent`
- **Non-clickable/Informational Icons**: Use `OPSStyle.Colors.primaryText`
- **Status Icons**: Use appropriate status color

### Text Fields
- Background: Slightly lighter than card background
- Border: Minimal, subtle border
- Focus state: Primary accent color border

## Specific UI Patterns

### Navigation Bar
- Background: Solid black
- Title: White, centered or left-aligned
- Icons: Primary accent for interactive elements

### Tab Bar
- Background: Solid black
- Selected Tab: Primary accent color
- Unselected Tab: Secondary text color

### Lists
- Dividers: Use `OPSStyle.Colors.secondaryText` without opacity
- Row highlighting: Avoid or use very subtle effect

### Status Indicators
- Always use `StatusBadge` component
- Use appropriate semantic colors from `OPSStyle.Colors`

## Dark Mode
- The app is dark mode by default for better outdoor visibility
- Never rely on subtle color differences for important UI distinctions

## Accessibility
- Ensure touch targets are minimum 44×44pt
- Maintain text hierarchy for screen readers
- Use sufficient color contrast (minimum 4.5:1 ratio)

## Voice & Tone in UI

### Brand Voice Principles
- **Direct** - Get to the point without unnecessary words
- **Practical** - Focus on solutions, not theory
- **Dependable** - Communicate consistently and reliably
- **Genuine** - Avoid corporate speak and marketing hype
- **Field-Appropriate** - Simple language without being condescending

### UI Copy Examples
**DO SAY:**
- "No signal? No problem. Your changes will sync when you're back online."
- "Tap once to update status. Done."
- "Can't connect right now. We'll save your changes and try again."

**DON'T SAY:**
- "Network synchronization failure. Retry or check system settings."
- "Please ensure optimal connectivity for best performance."

## Component Patterns

### Layout Modifiers
1. **Tab Bar Padding**
   - Always use `.tabBarPadding()` for content that might scroll behind tab bar
   - Standard padding: 90pt
   - Additional padding when needed: `.tabBarPadding(additional: 20)`

### Navigation Components
1. **Segmented Controls**
   - Use `SegmentedControl` for switching between views (e.g., Month/Week in calendar)
   - Maintains OPS black/white styling with accent highlights
   - Supports generic types for flexible data binding

### Form Components
1. **Address Fields**
   - Use `AddressAutocompleteField` for any address input
   - Includes 500ms debouncing to prevent keyboard lag
   - Returns full `MKPlacemark` data for location services

2. **Standard Text Fields**
   - Use `FormTextField` for consistent styling across all forms
   - Includes floating labels and error state handling

### Contact Display
1. **Contact Sheets**
   - Use `ContactDetailSheet` for any contact information display
   - Handles phone, email, and address actions consistently
   - Follows OPS styling patterns

### Calendar Patterns
1. **Week View**
   - Starts with Monday, shows 5 weekdays by default
   - Snaps to days for precise selection
   - Project counts appear as corner badges (matching month view)

2. **Date Styling**
   - Today: Blue text (`secondaryAccent`) with light background (`cardBackground.opacity(0.3)`)
   - Selected: White background with primary text
   - Project counts: Small blue circles in top-right corner

## Common Anti-Patterns to Avoid

1. **Never use opacity modifiers on backgrounds** - Use the appropriate solid color
2. **Never use `secondaryAccent` color except for active items** 
3. **Avoid gradients** except for the main background gradient
4. **Avoid complex shadows or blur effects** that may impact performance
5. **Don't center large blocks of text** - Use left alignment for readability
6. **Don't use decorative elements** that don't serve a functional purpose
7. **Never sacrifice functionality for aesthetics** - Field usability always comes first
8. **Avoid tiny touch targets** - Remember users wear gloves
9. **Don't use low contrast** - Must be readable in direct sunlight
10. **Avoid complex gestures** - Simple taps and swipes only

## Measuring Success

A successful OPS interface:
- Can be operated with work gloves on
- Remains readable in direct sunlight
- Loads quickly even on 3-year-old devices
- Works fully offline and syncs seamlessly
- Reduces time-to-task completion
- Feels "invisible" - users focus on their work, not the app

By following these guidelines, we ensure that the OPS app maintains its promise of being a dependable field partner that "just works" in any environment.