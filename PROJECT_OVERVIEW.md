# OPS App - Project Overview

**Last Updated**: August 2025  
**Version**: 1.2.0  
**Status**: Production

## App Purpose
OPS (Operational Project System) is a specialized project management app built specifically for trade workers. It focuses on providing reliable, field-first functionality that works in challenging job site conditions with minimal complexity. The app has been designed "by trades, for trades" with every feature optimized for real-world field operations.

## Architecture
- **Platform**: iOS 17+ app using SwiftUI with UIKit integrations
- **Pattern**: MVVM (Model-View-ViewModel) with Coordinator pattern for complex flows
- **Data Storage**: SwiftData for local persistence with offline-first design
- **Backend Integration**: Bubble.io REST API for remote data
- **Image Storage**: AWS S3 with local FileManager caching
- **Authentication**: Multi-method (Standard, Google OAuth, PIN protection)

## Core Components

### App Structure
- **Entry Point**: `OPSApp.swift` - Sets up the SwiftData container and initializes core services
- **Root View**: `ContentView.swift` - Handles authentication state and displays appropriate screens
- **Main UI**: `MainTabView.swift` - Tab-based navigation when authenticated

### Data Layer
- **Models**: SwiftData models for `User`, `Project`, `Company`, `TeamMember`, `CalendarEvent`
- **Controller**: `DataController.swift` orchestrates all data operations and services
- **Sync**: Sophisticated offline-first architecture with prioritized background synchronization
  - `SyncManager.swift` handles bidirectional data sync with conflict resolution
  - `ImageSyncManager.swift` manages S3 uploads and Bubble registration
  - `ConnectivityMonitor.swift` provides real-time network status
  - Smart sync with chunked processing (20 projects at a time)
  - 3-tier priority system for sync operations

### Network Layer
- **API Service**: `APIService.swift` centralized Bubble API communication
  - Rate limiting (0.5s minimum between requests)
  - Automatic retry with exponential backoff
  - 30-second timeout for field conditions
  - Comprehensive error handling
- **Endpoints**: RESTful API organized by entity (Projects, Users, Companies)
- **Authentication**: `AuthManager.swift` manages multiple auth methods
  - Standard username/password login
  - Google Sign-In OAuth integration
  - Token auto-renewal with 5-minute buffer
- **Security**: `KeychainManager.swift` for secure credential storage
- **DTOs**: Data Transfer Objects for clean API communication

### UI Components
- Organized by functionality:
  - **Common UI**: Shared components like headers, navigation elements
    - `TabBarPadding`: Consistent 90pt padding above tab bar
    - `SegmentedControl`: Reusable picker with OPS styling
    - `AddressAutocompleteField`: MapKit-based address search with debouncing
    - `ContactDetailSheet`: Unified contact information display
  - **Project Components**: Cards, details views, action bars
  - **Map Components**: Location visualization for projects with stable pin positioning
  - **Image Components**: Photo handling for project documentation
  - **Calendar Components**: Month and week views with project indicators
    - Snapping week view starting with Monday
    - Project count badges in day cells
    - Today's date highlighting with blue text

### Core Features (200+ Swift files)

1. **Authentication & Onboarding (20 dedicated files)**
   - Coordinator-based onboarding flow with intelligent navigation
   - Multi-step setup: Welcome → User Type → Company Setup → Permissions → Completion
   - Enhanced permission handling with completion callbacks
   - Smart navigation (skips company code for existing members)
   - Role-based welcome messages
   - Google Sign-In integration
   - PIN security system

2. **Project Management (Core Feature)**
   - Comprehensive status workflow: RFQ → Estimated → Accepted → In Progress → Completed → Closed
   - Real-time project tracking with start/stop functionality
   - Team member assignment with role-based permissions
   - Rich project details: client info, location, notes, images
   - Offline-first with automatic sync when connected
   - Priority-based sync system

3. **Field Operations**
   - Full offline functionality with SwiftData persistence
   - Advanced location services:
     - Live navigation with turn-by-turn directions
     - Project location mapping with stable pins
     - Route tracking and updates
     - Permission handling with clear UI feedback
   - Image management:
     - Offline capture with local storage
     - Automatic S3 upload when connected
     - Multi-tier caching (S3 → Local Files → Memory)
     - Duplicate prevention with SHA256 hashing

4. **Team Coordination**
   - Comprehensive team member management
   - Three role types: Field Crew, Office Crew, Admin
   - Contact integration (phone, email, address)
   - Permission-based feature access
   - Lightweight TeamMember model for efficient display
   - Real-time sync of team changes

5. **Image Management System**
   - **Storage Architecture**:
     - AWS S3 for cloud storage
     - Local FileManager for offline access
     - Memory cache for performance
   - **Smart Features**:
     - Offline capture with "local://" URL scheme
     - Automatic compression and resizing
     - Queue-based upload management
     - Presigned URL support
   - **Recent Improvements**:
     - Bidirectional deletion sync
     - SHA256-based deduplication
     - Unique filename generation
     - Migration from UserDefaults
     - Single source of truth pattern

6. **Calendar & Scheduling**
   - **CalendarEvent-Centric Design**: All calendar functionality built around CalendarEvent entities as single source of truth
   - **Apple Calendar-like Experience**: Continuous vertical scrolling through months with seamless transitions
   - **Three view modes**: Month grid with lazy loading, Week list, Day detail
   - **Smart Month Detection**: Visible month automatically updates as user scrolls
   - **Month Snapping**: Calendar intelligently snaps to nearest month when scrolling ends
   - **Performance Optimized**: Lazy loading of events only for visible months
   - **Event Caching**: Efficient caching system for calendar event counts
   - **Today Card**: Always displays today's date with event count
   - **Dynamic Month Picker**: Shows currently visible month, updates while scrolling
   - **Scheduling Mode Support**: Respects project vs task-level event display based on project.eventType
   - Project count indicators on calendar days with subtle dots
   - Today highlighting with blue accent
   - Smart date picker with popover presentation
   - Project filtering by date with role-based visibility

7. **Settings & Configuration (13+ screens)**
   - Profile management with home address
   - Organization settings with company details
   - Notification preferences by project type
   - Map settings for navigation options
   - Security settings with PIN management
   - Data storage controls with cache management
   - Project/Expense history views
   - "What We're Working On" feature voting
   - Bug reporting functionality

## File Structure & Organization

### Swift Files Distribution (200+ total)
- **Views**: 90+ files - Comprehensive UI implementation
- **Onboarding**: 25+ files - Complete user setup system with coordinator pattern
- **Network**: 20+ files - API and sync infrastructure
- **Utilities**: 20+ files - Helpers and managers
- **Styles**: 15+ files - Design system components
- **Data Models**: 10+ files - Core business objects with DTOs
- **Services**: 8+ files - Service layer architecture
- **View Models**: 5+ files - Business logic separation
- **Configuration**: 5+ files - App settings and constants
- **Core App**: 3 files - App lifecycle management

## CalendarEvent-Centric Architecture

### Single Source of Truth for Calendar Display
Version 1.2.0 introduces a CalendarEvent-centric architecture that fundamentally changes how calendar information is managed and displayed:

- **CalendarEvents as Primary Display Entity**: All calendar display logic now flows through `CalendarEvent` entities rather than deriving information from projects or tasks directly
- **Unified Data Flow**: Calendar views query CalendarEvents exclusively, ensuring consistent behavior across all calendar interfaces
- **Centralized Filtering Logic**: The `shouldDisplay` property on CalendarEvent handles all complex filtering rules in one location

### Event Type System & Scheduling Modes
The architecture supports two distinct scheduling approaches through the project's `eventType` property:

- **Project-Level Events** (`project.eventType == .project`):
  - Only project-level CalendarEvents are displayed
  - Tasks inherit project scheduling but don't show individually
  - Simplified view for projects managed as single units

- **Task-Level Events** (`project.eventType == .task`):
  - Only task-level CalendarEvents are displayed
  - Each task can have independent scheduling
  - Granular control for complex project workflows

### shouldDisplay Property Logic
The `CalendarEvent.shouldDisplay` computed property encapsulates complex filtering logic:
- Respects project scheduling mode (project vs task events)
- Applies user role permissions
- Handles project status filtering
- Manages visibility rules consistently across all calendar views

## Technical Architecture

### SwiftData Defensive Patterns
To ensure data integrity and prevent crashes in the multi-threaded environment, OPS implements strict defensive patterns:

#### Model Passing Rules
- **Never pass SwiftData models to background tasks**: Always pass primitive IDs (String, UUID) instead
- **Always fetch fresh models from context**: Each operation should fetch the latest model state from the appropriate ModelContext
- **Use autoreleasepool for batch operations**: Wrap large data processing in autoreleasepool blocks to manage memory efficiently

#### Example Pattern:
```swift
// Correct: Pass ID to background task
Task.detached {
    await processProject(projectId: project.id)
}

// Incorrect: Never pass model directly
Task.detached {
    await processProject(project: project) // ❌ Can cause crashes
}

// Correct: Fetch fresh model in background context
func processProject(projectId: String) async {
    let context = ModelContext(sharedModelContainer)
    guard let project = await context.fetch(Project.self, projectId) else { return }
    // Work with fresh model
}
```

#### Memory Management
- Use `autoreleasepool` for operations processing multiple models
- Always work with the appropriate ModelContext for the current thread
- Implement proper error handling for model fetch operations

### Style System
- Dark theme optimized for outdoor visibility
- Custom styling system in `OPSStyle.swift` with:
  - Color palette with status-specific colors
  - Typography definitions using custom fonts:
    - Mohave (primary font for titles, body text, and UI elements)
    - Kosugi (supporting font for captions and labels)
    - Bebas Neue (available but rarely used)
  - Layout constants (including larger touch targets for field use)

### Sync Strategy
- **Intelligent Background Sync**:
  - Triggered by connectivity changes
  - Respects user preferences (auto-update toggle)
  - Priority-based queue (1-3, highest first)
  - Chunked processing for memory efficiency
- **Conflict Resolution**:
  - Local changes preserved until explicit sync
  - Smart deduplication for users
  - Relationship maintenance during sync
- **Image Sync**:
  - Queue-based upload management
  - Automatic retry on failure
  - Progress tracking and UI feedback

### Configuration
- Centralized app configuration in `AppConfiguration.swift`
- Environment-specific settings

## Brand Alignment
The codebase reflects the OPS brand values:
- **Field-First Design**: Dark UI, large touch targets, offline capability
- **Reliability**: Robust error handling, offline-first architecture
- **No Unnecessary Complexity**: Focused feature set, streamlined workflows
- **Built By Trades, For Trades**: Field-optimized UX decisions throughout

## Performance & Optimization

### Current Metrics
- **App Launch**: <3 seconds on 3-year-old devices
- **Memory Usage**: Optimized with image caching limits
- **Offline Storage**: Efficient SwiftData schema
- **Network**: Rate-limited API calls, chunked sync
- **Battery**: Dark theme, minimal background processing

### Field-Tested Features
- **Glove Operation**: All touch targets 44pt+
- **Sunlight Readability**: High contrast dark theme
- **Offline Reliability**: Full functionality without connection
- **Error Recovery**: Graceful handling with clear feedback
- **Data Integrity**: Transaction-based updates

## Security Implementation

### Multi-Layer Security
1. **Authentication**: Token-based with auto-renewal
2. **Storage**: Keychain for credentials, encrypted SwiftData
3. **Network**: HTTPS only, certificate pinning ready
4. **Access**: Role-based permissions throughout
5. **Session**: Background PIN reset, token expiration

## Future Architecture Considerations

### Planned Improvements
- Modularization of large view files
- Enhanced test coverage
- Performance monitoring integration
- Advanced caching strategies
- Widget support preparation

## Data Models ✅ ENHANCED

### Core Model Properties

#### User Model ✅ UPDATED
- **isCompanyAdmin**: ✅ Boolean property indicating company administration privileges
  - Controls access to company-wide settings and management features
  - Used throughout the app for permission-based UI rendering
  - Automatically synced from Bubble backend during user authentication
  - Fixed admin role detection issues

#### CalendarEvent Model ✅ FULLY IMPLEMENTED
- **shouldDisplay**: ✅ Computed property that handles complex visibility logic
  - Respects project scheduling mode (project vs task events)
  - Applies user role permissions and project status filtering
  - Central point for all calendar display decisions
  - Performance optimized with cached projectEventType
- **projectEventType**: ✅ Cached project scheduling mode for efficient filtering
- **spannedDates**: ✅ Computed property for multi-day event handling
- **swiftUIColor**: ✅ Color conversion for UI display
- **displayIcon**: ✅ Task type icon integration

#### Project Model ✅ ENHANCED
- **eventType**: ✅ Enum property defining scheduling approach
  - `.project`: Project-level scheduling (tasks inherit project dates)
  - `.task`: Task-level scheduling (individual task scheduling)
  - Determines which CalendarEvents are displayed in calendar views
- **primaryCalendarEvent**: ✅ Relationship for project-level scheduling
- **tasks**: ✅ Relationship array for task-based scheduling
- **effectiveEventType**: ✅ Computed property with backward compatibility

#### ProjectTask Model ✅ NEW
- **Complete SwiftData model** with status workflow and team assignment
- **CalendarEvent relationship** for individual task scheduling
- **TaskType relationship** for visual consistency and categorization
- **Real-time sync** support with needsSync flags

#### TaskType Model ✅ NEW
- **Predefined task templates** (Quote, Work, Service Call, Inspection, Follow Up)
- **Custom colors and SF Symbol icons** for visual distinction
- **Company-specific customization** support

## Recent Major Updates (v1.2.0)

### CalendarEvent-Centric Architecture (September 2025) ✅ COMPLETED
- ✅ Successfully migrated all calendar logic to use CalendarEvent entities as single source of truth
- ✅ Implemented shouldDisplay property for centralized filtering logic with performance caching
- ✅ Added complete support for dual scheduling modes (project vs task events)
- ✅ Enhanced calendar performance through unified data flow and batch processing
- ✅ Fixed infinite loop issues in MonthGridView with proper scroll state management
- ✅ Eliminated verbose debug logging that caused console spam
- ✅ Implemented Apple Calendar-like continuous scrolling with month snapping
- ✅ Enhanced visible month tracking with dynamic month picker updates

### Task-Based Scheduling System (September 2025) ✅ IMPLEMENTED
- ✅ Complete ProjectTask model with status workflow and team assignment
- ✅ TaskType system with predefined templates and custom colors/icons
- ✅ TaskDetailsView with comprehensive task management matching ProjectDetailsView structure
- ✅ Real-time task status and notes sync with immediate API updates
- ✅ Previous/Next task navigation cards for seamless workflow
- ✅ Haptic feedback on status changes with user permission respect
- ✅ Individual team member assignment per task with full contact integration

### Previous Updates (v1.0.2)

### Onboarding Bug Fixes (July 3)
- Fixed user type persistence before signup completion
- Resolved team invite navigation for company owners
- Ensured company/project data loads during onboarding
- Disabled back navigation after account creation
- Fixed account created screen display
- Corrected step numbering for different user types

### Permission System Overhaul
- Enhanced LocationManager with completion callbacks
- Immediate alerts for denied/restricted permissions
- Direct navigation to Settings app when needed
- All required Info.plist keys added

### Onboarding Refinements
- Smart company code skipping for existing members
- Role-based welcome messages
- Simplified completion animation
- Improved back navigation logic

### UI/UX Enhancements
- Location disabled overlay on maps
- Standardized SettingsToggle component
- Redesigned project action bar with blur effect
- Bug reporting functionality
- Consistent empty state messaging

### Component Library
- `SegmentedControl`: Reusable picker with OPS styling
- `TabBarPadding`: Consistent 90pt bottom spacing
- `AddressAutocompleteField`: MapKit-powered address search
- `ContactDetailSheet`: Unified contact display
- `ImagePicker`: Camera/gallery integration
- `ProjectActionBar`: Standardized project controls