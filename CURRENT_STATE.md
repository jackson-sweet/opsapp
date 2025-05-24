# OPS App - Current State Summary

This document provides a comprehensive overview of the current state of the OPS app as of the latest development session.

## Architecture Overview

### Technology Stack
- **Platform**: iOS app using SwiftUI
- **Architecture**: MVVM (Model-View-ViewModel)
- **Local Storage**: SwiftData for offline-first functionality
- **Backend**: Bubble.io API
- **Minimum iOS Version**: iOS 17.0
- **Typography**: Custom fonts (Mohave, Kosugi, Bebas Neue) - NO system fonts

### Design System
- **Theme**: Dark theme optimized for field conditions
- **Primary Colors**: Near-black background (#000000), Blue accent (#59779F)
- **Touch Targets**: Minimum 44×44pt, preferred 60×60pt for primary actions
- **Layout Grid**: 8pt spacing system
- **Tab Bar Height**: 90pt padding standard

## Recently Implemented Features

### PIN Security System (New)
1. **Simple PIN Authentication**
   - Location: `/Network/Auth/SimplePINManager.swift`
   - Clean, minimal implementation for app entry only
   - 4-digit PIN with individual visual boxes
   - No automatic keyboard display - tap to activate
   
2. **PIN Entry UI**
   - Location: `/Views/SimplePINEntryView.swift`
   - Individual digit boxes with visual feedback
   - Active state indication (brighter borders when focused)
   - Success state: Green borders with haptic feedback
   - Error state: Red borders with shake animation + haptic
   - Smooth fade transition on successful entry

3. **Visual Feedback System**
   - Border color changes: neutral (white), success (green), error (red)
   - Haptic feedback using UINotificationFeedbackGenerator
   - 0.6s delay on success to show green state before dismissing
   - Shake animation on incorrect PIN entry
   - "Tap to enter PIN" guidance text

### UI Components (New)
1. **TabBarPadding Modifier**
   - Location: `/Utilities/TabBarPadding.swift`
   - Usage: `.tabBarPadding()` or `.tabBarPadding(additional: 20)`
   - Provides consistent 90pt padding above tab bar

2. **SegmentedControl**
   - Location: `/Styles/Components/SegmentedControl.swift`
   - Generic, reusable segmented picker with OPS styling
   - Used in calendar for Month/Week switching

3. **AddressAutocompleteField**
   - Location: `/Views/Components/Common/AddressAutocompleteField.swift`
   - MapKit-based address search with 500ms debouncing
   - Prevents keyboard lag, returns MKPlacemark data

4. **StorageOptionSlider**
   - Location: `/Views/Components/Common/StorageOptionSlider.swift`
   - Interactive storage selection for onboarding
   - Options: No Storage, 100MB, 250MB, 500MB, 1GB, 5GB, Unlimited

5. **ContactDetailSheet**
   - Location: `/Views/Components/Common/ContactDetailSheet.swift`
   - Unified contact information display
   - Handles phone, email, and address actions

### Calendar Improvements
1. **Week View**
   - Snapping scroll behavior (`.scrollTargetBehavior(.viewAligned)`)
   - Starts with Monday, shows 5 weekdays
   - Weekend accessible via horizontal scroll
   - Project count badges in top-right corner (matching month view)

2. **Date Styling**
   - Today: Blue text (`secondaryAccent`) with light background (`cardBackground.opacity(0.3)`)
   - Selected: White background with primary text
   - Consistent styling between month and week views

### UI Refinements
1. **Tab Bar**
   - Darker background for better contrast
   - Keyboard-aware hiding with smooth animation
   - Fixed overlap issues with content

2. **Settings View**
   - "What we're working on" moved below divider
   - Button styling changed from filled to bordered
   - Edit button hidden as requested

3. **Navigation**
   - Native swipe-back gesture support
   - Proper back button styling

4. **Map Components**
   - Fixed pin drift issue with correct anchor points
   - Stable positioning during zoom/pan

## Current File Organization

### Key Directories
- `/DataModels/` - SwiftData models
- `/Network/` - API, Auth, and Sync services
- `/Views/` - All UI components organized by feature
- `/Styles/` - Design system components and utilities
- `/Utilities/` - Helper classes and extensions
- `/Onboarding/` - Complete onboarding flow implementation

### Important Files
- `CLAUDE.md` - Brand guidelines and development instructions
- `UI_DESIGN_GUIDELINES.md` - Comprehensive UI/UX guidelines
- `PROJECT_OVERVIEW.md` - High-level project structure
- `DEVELOPMENT_GUIDE.md` - Technical implementation guide
- `MVP_TODO.md` - Current task tracking

## API Integration Status

### Working Endpoints
- User authentication and profile management
- Company/organization data sync
- Project CRUD operations
- Team member management
- Image upload/sync (via Bubble file API)

### Offline Capabilities
- Full offline mode for critical features
- Queue-based sync when connection restored
- Local image caching with FileManager
- Conflict resolution for concurrent edits

## Testing Considerations

### Device Support
- Tested on iOS 17.0+
- Optimized for iPhone (various sizes)
- Dark mode only (no light mode support)
- Landscape orientation locked out

### Field Testing Requirements
- Large touch targets for gloved operation
- High contrast for sunlight readability
- Offline-first architecture
- Battery-efficient operation

## Next Steps

### Immediate Tasks
1. Complete onboarding API integration
2. Add industry selection to onboarding
3. Implement business owner vs. employee flow
4. Test and refine sync mechanisms

### Upcoming Features
- Push notifications for project updates
- Enhanced team communication
- Advanced reporting capabilities
- See `V2_FEATURES.md` for full roadmap

## Development Notes

### Important Conventions
- NEVER use system fonts - always use OPS fonts
- NEVER add Claude as co-author in git commits
- Use Sonnet 4 instead of Opus 4 for development
- Always use `.tabBarPadding()` for scrollable content
- Follow OPS brand voice: direct, practical, field-appropriate

### Code Quality Standards
- Simplicity over complexity
- Field-tested logic (offline scenarios)
- Performance on older devices
- Defensive programming
- Clear error messages with actionable steps

This document represents the current state as of the latest development session. All features listed above have been implemented and tested in the current build.