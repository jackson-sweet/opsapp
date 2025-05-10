# OPS App - Development Guide

## Project Overview

The OPS (Operational Project System) app is a field-optimized project management tool for trade workers. It focuses on reliability, simplicity, and functionality in challenging job site conditions.

### Core Architecture
- **Platform**: iOS app using SwiftUI
- **Pattern**: MVVM (Model-View-ViewModel)
- **Local Storage**: SwiftData
- **Backend**: Bubble.io API
- **UI Design**: Dark theme optimized for outdoor visibility
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
- **Project Components**: Project details, actions, image management
- **Map Components**: Location visualization
- **Team Components**: Team member listings and details

## Key Features

1. **Authentication & Onboarding**
   - Step-based user onboarding flow
   - Secure credential storage
   - Company code verification

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

### Code Style
- Match existing project style conventions
- Use meaningful variable and function names
- Follow Swift naming conventions
- Structure files consistently with MARK comments
- Create clear boundaries between app layers

### SwiftUI Patterns
- Use environment objects for dependency injection
- Keep view components small and focused
- Extract complex subviews into separate components
- Use preview providers for all UI components

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

6. **Push Notifications**
   - Implement push notification registration
   - Add handling for project status update notifications
   - Create user preferences for notification types

7. **Testing**
   - Add automated testing for critical paths
   - Perform field testing in real-world conditions

8. **Performance**
   - Optimize performance for large data sets
   - Test app with realistic data volumes

9. **App Store Preparation**
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