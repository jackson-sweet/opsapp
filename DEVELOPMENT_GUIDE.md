# OPS App - Development Guide

**Last Updated**: July 03, 2025  
**Version**: 1.0.2

## Project Overview

The OPS (Operational Project System) app is a field-optimized project management tool for trade workers. It focuses on reliability, simplicity, and functionality in challenging job site conditions.

### Core Architecture
- **Platform**: iOS 17+ app using SwiftUI with UIKit integrations
- **Pattern**: MVVM (Model-View-ViewModel) with Coordinator pattern for complex flows
- **Local Storage**: SwiftData (iOS 17+) with offline-first design
- **Backend**: Bubble.io REST API with rate limiting
- **UI Design**: Dark theme optimized for outdoor visibility (7:1 contrast ratios)
- **Typography**: Custom fonts (Mohave, Kosugi, Bebas Neue) - NO system fonts
- **Network Strategy**: Offline-first with prioritized background synchronization
- **Authentication**: Multi-method (Standard, Google OAuth 2.0, PIN protection)

## Component Structure

### Data Layer
- **Models**: SwiftData models for `User`, `Project`, `Company`, `TeamMember`
- **DTOs**: Data Transfer Objects for clean API communication with Bubble
- **Controller**: `DataController.swift` orchestrates all data operations and services
- **Sync**: `SyncManager.swift` handles bidirectional data synchronization
- **Image Sync**: `ImageSyncManager.swift` manages S3 uploads and Bubble registration

### Network Layer
- **API Service**: `APIService.swift` centralized Bubble API communication
  - Rate limiting (0.5s minimum between requests)
  - 30-second timeout for field conditions
  - Automatic retry with exponential backoff
- **Endpoints**: RESTful API organized by entity (Projects, Users, Companies)
- **Authentication**: `AuthManager.swift` handles multiple auth methods
  - Standard username/password
  - Google Sign-In OAuth
  - Token auto-renewal with 5-minute buffer
- **Security**: `KeychainManager.swift` for secure credential storage
- **Services**: S3UploadService, PresignedURLUploadService for image uploads

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

## Post-MVP Enhancements

### Currently Implemented (MVP Complete)
✅ Authentication with Google Sign-In and PIN security  
✅ Complete onboarding flow for employees and company owners  
✅ Full project management with offline sync  
✅ Image handling with S3 integration  
✅ Team management with role-based permissions  
✅ Calendar with multiple view modes  
✅ Settings suite with 13+ screens  
✅ Feature voting system (+1 implementation)  

### Future Enhancements

1. **Enhanced Communication**
   - In-app messaging between team members
   - Voice notes for project updates
   - Real-time team member location tracking

2. **Advanced Features**
   - Biometric authentication (Face ID/Touch ID)
   - Advanced reporting and analytics
   - Platform expansion (iPad, Apple Watch, CarPlay)
   - Client portal access
   - QuickBooks integration

3. **Testing & Performance**
   - Automated testing for critical paths
   - Performance optimization for large datasets
   - Load testing with 1000+ projects

4. **Push Notifications**
   - Real-time project status updates
   - Team assignment notifications
   - Location-based reminders

5. **Security Enhancements**
   - Remove hardcoded AWS credentials
   - Implement certificate pinning
   - Add audit logging

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
