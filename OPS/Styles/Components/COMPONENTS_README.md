# OPS UI Component System

⚠️ NOTE: This file is named COMPONENTS_README.md (not README.md) to avoid build conflicts with other README files in the project.

This directory contains standardized UI components for the OPS app. These components implement consistent styling and behavior across the application.

## Components Overview

### Button Components
- `OPSButtonStyle` - Standardized button styles as view modifiers
- `opsPrimaryButtonStyle()` - Primary action button with solid background
- `opsSecondaryButtonStyle()` - Secondary action button with outline
- `opsDestructiveButtonStyle()` - Destructive/danger button style
- `opsIconButtonStyle()` - Circular icon button style

### Card Components
- `OPSCardStyle` - Card style view modifiers
- `OPSCard` - Standard card container
- `OPSElevatedCard` - Card with elevation and shadow
- `OPSInteractiveCard` - Tappable interactive card
- `OPSAccentCard` - Card with accent-colored border
- `opsCardStyle()` - Apply standard card styling to any view
- `opsElevatedCardStyle()` - Apply elevated card styling to any view
- `opsInteractiveCardStyle()` - Apply interactive card styling to any view
- `opsAccentCardStyle()` - Apply accent card styling to any view

### Form Components
- `FormField` - Text input with label
- `FormTextEditor` - Multi-line text input
- `FormToggle` - Toggle switch with label
- `RadioOption` - Radio button style option
- `SearchBar` - Search input field
- `EmptyStateView` - Empty state messaging

### Layout Components
- `CategoryCard` - Card component for settings categories
- `OrganizationProfileCard` - Organization profile display
- `UserProfileCard` - User profile display
- `SettingsHeader` - Header for settings views
- `SettingsSectionHeader` - Section headers in settings views

### Status & Utility Components
- `StatusBadge` - Standardized status badge with multiple styles
- `IconBadge` - Circular icon badge with configurable size and color
- `ListItem` - Standardized list item row

### Typography
- Font extensions - Standardized typography system
  - Title styles: `largeTitle`, `title`, `subtitle`
  - Heading styles: `heading1`, `heading2`, `heading3`
  - Body text: `body`, `bodyBold`, `bodyEmphasis`, `smallBody`
  - Supporting text: `caption`, `captionBold`, `smallCaption`
  - Card components: `cardTitle`, `cardSubtitle`, `cardBody`
  - Specialized text: `status`, `button`, `smallButton`

## Usage Guidelines

1. **Always prefer these components** over creating custom styles for consistency.

2. **For buttons:**
   ```swift
   Button("Primary Action") { /* action */ }
       .opsPrimaryButtonStyle()
   
   Button("Secondary Action") { /* action */ }
       .opsSecondaryButtonStyle()
   ```

3. **For cards:**
   ```swift
   // Using component
   OPSCard {
       Text("Card Content")
   }
   
   // Using modifier
   VStack {
       Text("Custom Card")
   }
   .opsCardStyle()
   ```

4. **For status badges:**
   ```swift
   // For job statuses
   StatusBadge.forJobStatus(.inProgress)
   
   // Custom status
   StatusBadge(status: "Custom", color: .blue)
   
   // Size variations
   StatusBadge(status: "Small", color: .green, size: .small)
   StatusBadge(status: "Large", color: .red, size: .large)
   
   // Outlined style
   StatusBadge(status: "Outlined", color: .orange, outlined: true)
   ```

5. **For typography:**
   ```swift
   Text("Heading")
       .font(OPSStyle.Typography.title)
   
   Text("Body text")
       .font(OPSStyle.Typography.body)
   ```

## Best Practices

1. Use the correct component for the context - don't use a primary button for secondary actions.

2. Maintain consistent spacing with `OPSStyle.Layout` constants.

3. Use `OPSStyle.Colors` for all color references to ensure theme consistency.

4. Prefer direct implementation of components rather than typealias/imports to avoid compile-time conflicts.

5. Always left-align text throughout the app (not centered).

6. Use uppercase for headers consistently by setting `.uppercased()` on Text views with heading styles.