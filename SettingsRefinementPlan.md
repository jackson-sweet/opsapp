# Settings Views Refinement Plan

## Current State Analysis

After examining the settings views in the OPS application, I've identified several areas where consistency and user experience can be improved.

### Strengths
- Use of a consistent dark color scheme throughout
- Good organization of settings into logical categories
- Well-structured card-based layout for settings sections
- Clear visual hierarchy with headers, sections, and cards

### Areas for Improvement

#### 1. Inconsistent Header Styles
- Different settings screens use varying header designs:
  - Some use a back button + title + edit button
  - Others use just a back button + title
  - Navigation bar appearance is inconsistent across views

#### 2. Inconsistent Card Styling
- Card background opacities vary between views (0.3, 0.6)
- Corner radius values aren't consistently applied (8, 12, 16px)
- Internal padding within cards varies across views

#### 3. Interaction Patterns
- Toggle elements have inconsistent styling
- Button styles vary between views (primary, secondary, text-only)
- Loading states are handled differently across views

#### 4. Typography
- Inconsistent use of font weights and sizes for similar elements
- Section headers use different capitalization and styling

#### 5. Layout Spacing
- Vertical and horizontal spacing between elements varies
- Padding values are inconsistent across similar components

## Refinement Plan

### 1. Create Shared Components

#### A. SettingsHeader Component
```swift
struct SettingsHeader: View {
    var title: String
    var showEditButton: Bool = false
    var isEditing: Bool = false
    var onBackTapped: () -> Void
    var onEditTapped: (() -> Void)? = nil
    
    var body: some View {
        // Standardized header with consistent styling
    }
}
```

#### B. SettingsCard Component
```swift
struct SettingsCard<Content: View>: View {
    var title: String
    var content: Content
    
    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }
    
    var body: some View {
        // Standardized card with consistent styling
    }
}
```

#### C. SettingsToggle Component
```swift
struct SettingsToggle: View {
    var title: String
    var description: String
    @Binding var isOn: Bool
    
    var body: some View {
        // Standardized toggle with consistent styling
    }
}
```

#### D. SettingsButton Styles
- Standardize button styles for primary, secondary, and tertiary actions

### 2. Consistent Typography System

- Define specific text styles for:
  - Section headers
  - Card titles
  - Settings labels
  - Settings values
  - Action buttons
  - Helper text

### 3. Standardized Layout Guidelines

- Consistent padding values:
  - Card external padding: 20pt horizontal, 12pt vertical
  - Card internal padding: 16pt all sides
  - Section spacing: 24pt
  - Element spacing within sections: 16pt
  - Small element spacing: 8pt

### 4. Implementation Strategy

1. Create the shared components in a new Settings/Components directory
2. Refactor SettingsView.swift first to use the new components
3. Then refactor each individual settings screen:
   - ProfileSettingsView
   - OrganizationSettingsView
   - ProjectHistorySettingsView
   - NotificationSettingsView

### 5. Visual Improvements

- Consistent visual feedback for user actions
- Standardized loading states
- Better empty state handling
- Improved accessibility features
- Enhanced animation and transitions
- More responsive layout for different device sizes

## Next Steps

1. Implement the shared components
2. Apply the standardized style to the main SettingsView
3. Refactor each individual settings view
4. Ensure consistent behavior across all settings screens
5. Test on various device sizes and orientations