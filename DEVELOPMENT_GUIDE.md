# OPS App - Development Guide

## Project Overview

The OPS (Operational Project System) app is a field-optimized project management tool for trade workers. It focuses on reliability, simplicity, and functionality in challenging job site conditions.

### Core Architecture
- **Platform**: iOS app using SwiftUI
- **Pattern**: MVVM (Model-View-ViewModel)
- **Local Storage**: SwiftData
- **Backend**: Bubble.io API
- **UI Design**: Dark theme optimized for outdoor visibility
- **Typography**: Custom fonts (Mohave, Kosugi, Bebas Neue)
- **Network Strategy**: Offline-first with background synchronization

## Component Structure

### Data Layer
- **Models**: SwiftData models for `User`, `Project`, `Company`, `TeamMember`
- **Controller**: `DataController.swift` manages data operations
- **Sync**: `SyncManager.swift` handles data synchronization with Bubble

### Network Layer
- **API Service**: `APIService.swift` for communication with Bubble
- **Endpoints**: Organized by entity (Projects, Users, Companies)
- **Authentication**: `AuthManager.swift` handles login, token management
- **Security**: `KeychainManager.swift` for secure credential storage

### UI Components
- **Common UI**: Headers, cards, navigation elements
  - `TabBarPadding`: Consistent padding above tab bar
  - `SegmentedControl`: Reusable picker component
  - `AddressAutocompleteField`: MapKit-based address search
  - `ContactDetailSheet`: Unified contact display
- **Project Components**: Project details, actions, image management
- **Map Components**: Location visualization with stable pin positioning
- **Team Components**: Team member listings and details
- **Calendar Components**: Month/week views with project indicators
  - Snapping week view, project count badges
  - Today's date highlighting
- **Feature Request Components**: +1 voting system
  - Vote button with haptic feedback
  - Feature standardization for vote counting
  - Expandable category sections

## Key Features

1. **Authentication & Onboarding**
   - Step-based user onboarding flow with smart navigation
   - Secure credential storage
   - Company code verification (automatically skipped for users with existing company)
   - Enhanced permission handling with completion callbacks
   - Immediate alerts for denied/restricted permissions

2. **Project Management**
   - Project status tracking
   - Calendar/schedule visualization
   - Project details and documentation
   - Team member assignment

3. **Field Operations**
   - Offline capability
   - Location services for navigation
   - Image capture and storage
   - Status updates from the field

4. **Team Coordination**
   - Team member assignment
   - Contact information
   - Role-based visibility

## Code Guidelines

### Debugging
- Make sure you read through the relevant code before suggesting any changes
- Fully understand the context of the issue before attempting to solve
- Determine the root cause of what is causing the issue in question
- Once the root cause is certain, determine the best solution

### Code Style
- Match existing project style conventions
- Use meaningful variable and function names
- Follow Swift naming conventions
- Structure files consistently with MARK comments
- Create clear boundaries between app layers
- When creating new components, use existing patterns from the codebase
- Always use `.tabBarPadding()` for scrollable content

### Typography Requirements ⚠️ CRITICAL
- **MANDATORY**: All text styling must use `OPSStyle.Typography` definitions
- **FORBIDDEN**: Never use system fonts (`.font(.system())`, `.font(.title)`, `.font(.body)`, etc.)
- **REQUIRED IMPORTS**: Add `import Foundation` and ensure `Fonts.swift` is available
- **CORRECT USAGE**: `Text("Title").font(OPSStyle.Typography.title)`
- **BRAND FONTS ONLY**: Mohave (primary), Kosugi (supporting) - no exceptions
- **CODE REVIEW**: Any PR with system fonts will be rejected

### SwiftUI Patterns
- Use environment objects for dependency injection
- Keep view components small and focused
- Extract complex subviews into separate components
- Use preview providers for all UI components

### Permission Handling Best Practices
- **Use Completion Callbacks**: When requesting permissions, always provide completion handlers for immediate response
- **Handle All States**: Check for `.denied`, `.restricted`, `.notDetermined`, and `.authorized` states
- **Show Immediate Feedback**: Display alerts immediately when permissions are denied
- **Provide Settings Navigation**: Include "Open Settings" options in denial alerts
- **Info.plist Keys**: Always ensure required usage description keys are present
- **Example Pattern**:
  ```swift
  locationManager.requestPermissionIfNeeded { isAllowed in
      if !isAllowed {
          // Show settings prompt immediately
          showLocationDeniedAlert = true
      }
  }
  ```

### Error Handling
- Add appropriate error handling to new code
- Provide user-friendly error messages
- Use Swift's error handling mechanisms consistently
- Always log errors for debugging purposes

### API Integration
- Follow the Bubble.io API structure
- Use the correct endpoint format for data vs. workflow APIs
- Handle offline scenarios gracefully
- Implement proper error handling for API failures

### Image Handling
- **Storage Strategy**: Images use a multi-tier approach (S3 → Local Files → Memory Cache)
- **Offline Support**: All images work offline with automatic sync when connected
- **File Naming**: `{StreetAddress}_IMG_{timestamp}_{index}.jpg`
- **Compression**: JPEG 0.7 quality for optimal size/quality balance
- **Sync Priority**: Images get priority 2 (high) for background sync
- **Error Recovery**: Failed uploads automatically retry on next sync
- **Cache Keys**: SHA256 hashing ensures unique identifiers (no truncation)
- **Duplicate Prevention**: Upload services check existing filenames before generating new ones
- **Deletion Sync**: Images deleted on web are automatically removed from iOS cache
- **Update Flow**: ImageSyncManager is single source of truth for all image operations
- See `IMAGE_HANDLING.md` for complete documentation

## Remaining MVP Tasks

1. **Authentication Flow**
   - Complete user authentication flow testing
   - Test edge cases for login/logout

2. **Data Synchronization**
   - Finalize offline/online sync functionality
   - Test multiple device synchronization

3. **User Onboarding**
   - Complete all onboarding screens
   - Test onboarding flow on different devices

4. **Image Handling**
   - Complete image upload and storage implementation
   - Test image synchronization with spotty connectivity

5. **Project Status Updates**
   - Test project status updates across all states
   - Verify status change APIs work as expected

6. **Feature Request System**
   - **+1 Voting Implementation**: Users can vote on upcoming features
   - **Feature Standardization**: Features are normalized before counting (e.g., "Dark Mode", "dark mode", "Dark mode" all count as the same feature)
   - **Vote Storage**: Uses UserDefaults to track user votes per device
   - **UI Pattern**: Expandable categories with vote buttons showing current count

7. **Push Notifications**
   - Implement push notification registration
   - Add handling for project status update notifications
   - Create user preferences for notification types

8. **Testing**
   - Add automated testing for critical paths
   - Perform field testing in real-world conditions

9. **Performance**
   - Optimize performance for large data sets
   - Test app with realistic data volumes

10. **App Store Preparation**
   - Create app store screenshots and metadata
   - Prepare privacy policy and terms of service

## Development Workflow

1. **Feature Implementation**
   - Use feature flags for major changes
   - Create comprehensive tests
   - Maintain backward compatibility

2. **Code Review**
   - Verify against style guidelines
   - Test on multiple devices
   - Consider offline scenarios

3. **Documentation**
   - Update this guide for major changes
   - Document API changes comprehensively
   - Add code comments for complex logic

## Brand Values

- **Field-First Design**: Dark UI, large touch targets, offline capability
- **Reliability**: Robust error handling, offline-first architecture
- **No Unnecessary Complexity**: Focused feature set, streamlined workflows
- **Built By Trades, For Trades**: Field-optimized UX decisions throughout
