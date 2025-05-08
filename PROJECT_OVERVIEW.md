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
  - **Project Components**: Cards, details views, action bars
  - **Map Components**: Location visualization for projects
  - **Image Components**: Photo handling for project documentation

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

## Technical Details

### Style System
- Dark theme optimized for outdoor visibility
- Custom styling system in `OPSStyle.swift` with:
  - Color palette with status-specific colors
  - Typography definitions (using system fonts and Bebas Neue)
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
- Ongoing reorganization of view components
- Migration of images from UserDefaults to FileManager
- Enhancement of field-specific features
- New onboarding flow implementation