# OPS App UI Design Guidelines

This document outlines the core UI design principles and guidelines for the OPS application. All UI development should adhere to these standards to maintain visual consistency and follow the brand identity.

## Core Design Principles

1. **Field-First Design** - Every aspect of OPS is designed for jobsite conditions, prioritizing legibility in sunlight, ease of use with gloves, and operation in dusty/dirty environments.

2. **Reliability Over Visual Flair** - Functional reliability trumps visual embellishments. The UI should feel dependable and predictable.

3. **Contrast and Legibility** - Dark backgrounds with high-contrast elements ensure readability in bright outdoor conditions.

4. **Touch-Optimized** - All interactive elements must be large enough for gloved finger operation (minimum 44×44pt).

5. **Reduced Visual Noise** - Minimal use of colors, animations, and decorative elements to prevent distraction.

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

## Common Anti-Patterns to Avoid

1. **Never use opacity modifiers on backgrounds** - Use the appropriate solid color
2. **Never use `secondaryAccent` color except for active items** 
3. **Avoid gradients** except for the main background gradient
4. **Avoid complex shadows or blur effects** that may impact performance
5. **Don't center large blocks of text** - Use left alignment for readability
6. **Don't use decorative elements** that don't serve a functional purpose

By following these guidelines, we ensure that the OPS app maintains its field-focused design that emphasizes reliability, usability, and performance in challenging environments.