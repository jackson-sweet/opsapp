# OPS App - Project Overview

## App Purpose
OPS (Operational Project System) is a specialized project management app built specifically for trade workers. It focuses on providing reliable, field-first functionality that works in challenging job site conditions with minimal complexity.

## Architecture
- **Platform**: iOS app using SwiftUI
- **Pattern**: MVVM (Model-View-ViewModel)
- **Data Storage**: SwiftData for local persistence
- **Backend Integration**: Bubble.io API for remote data

## Core Components

### App Structure
- **Entry Point**: `OPSApp.swift` - Sets up the SwiftData container and initializes core services
- **Root View**: `ContentView.swift` - Handles authentication state and displays appropriate screens
- **Main UI**: `MainTabView.swift` - Tab-based navigation when authenticated

### Data Layer
- **Models**: SwiftData models for `User`, `Project`, `Company`
- **Controller**: `DataController.swift` manages data operations
- **Sync**: Offline-first architecture with background synchronization
  - `SyncManager.swift` handles data synchronization with Bubble backend
  - `ImageSyncManager.swift` for offline image handling
  - `ConnectivityMonitor.swift` tracks network availability

### Network Layer
- **API Service**: `APIService.swift` for communication with Bubble backend
- **Endpoints**: Organized by entity (Projects, Users, Companies)
- **Authentication**: `AuthManager.swift` handles login, token management
- **Security**: `KeychainManager.swift` for secure credential storage

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

### Features
1. **Authentication & Onboarding**
   - Step-based user onboarding flow
   - Secure credential storage

2. **Project Management**
   - Project status tracking (RFQ, Estimated, Accepted, In Progress, etc.)
   - Calendar/schedule visualization
   - Project details and documentation

3. **Field Operations**
   - Offline capability for use in areas with poor connectivity
   - Location services for project mapping
   - Image capture and annotation

4. **Team Coordination**
   - Team member assignment and tracking
   - Permission-based access

5. **Image Management**
   - Multi-tier storage (S3, local files, memory cache)
   - Offline capture with automatic sync
   - AWS S3 integration for cloud storage
   - Bubble.io registration for project association
   - Automatic migration from legacy UserDefaults storage
   - **Recent Fixes**:
     - Deletion sync from web to iOS
     - SHA256 cache keys prevent duplicate display
     - Unique filename generation prevents overwrites
     - Single source of truth for image updates

## Technical Details

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
- Background synchronization at defined intervals
- Prioritized sync for critical data
- Image storage with FileManager (migrated from UserDefaults)

### Configuration
- Centralized app configuration in `AppConfiguration.swift`
- Environment-specific settings

## Brand Alignment
The codebase reflects the OPS brand values:
- **Field-First Design**: Dark UI, large touch targets, offline capability
- **Reliability**: Robust error handling, offline-first architecture
- **No Unnecessary Complexity**: Focused feature set, streamlined workflows
- **Built By Trades, For Trades**: Field-optimized UX decisions throughout

## Current Development
- Enhanced calendar with week view and improved navigation
- Refined settings UI with "What we're working on" section
- Improved form components with standardized styling
- Tab bar keyboard handling for better UX
- Native swipe-back gesture support

## Recent Improvements
- Added reusable `SegmentedControl` component for consistent UI
- Implemented `TabBarPadding` modifier for content layout
- Created `AddressAutocompleteField` with MapKit integration
- Fixed map pin drift issues with proper anchor points
- Enhanced calendar with snapping week view and project counts
- Updated all UI components to use OPS fonts (no system fonts)
- Refined button styling to use borders instead of filled backgrounds