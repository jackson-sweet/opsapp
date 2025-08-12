# OPS App - Field Operations Management System

## Overview

OPS (Operational Project System) is a specialized iOS app built for trade workers to manage projects and crews in the field. The app prioritizes reliability, simplicity, and offline functionality. Built "by trades, for trades," OPS transforms how field crews manage their daily operations.

**Status**: LAUNCHED ✅  
**Version**: 1.1.0  
**Platform**: iOS 17+  
**Architecture**: 200+ Swift files implementing comprehensive field management
**Backend**: Bubble.io with AWS S3 for media storage

## Key Documentation

### Essential Guides
- [`CURRENT_STATE.md`](CURRENT_STATE.md) - Current implementation status and features
- [`MVP_GUIDE.md`](MVP_GUIDE.md) - MVP status, release criteria, and roadmap
- [`PROJECT_OVERVIEW.md`](PROJECT_OVERVIEW.md) - High-level architecture and structure
- [`DEVELOPMENT_GUIDE.md`](DEVELOPMENT_GUIDE.md) - Development guidelines and best practices

### Technical Documentation
- [`API_GUIDE.md`](API_GUIDE.md) - Bubble.io API integration details
- [`IMAGE_HANDLING.md`](IMAGE_HANDLING.md) - Complete image upload/sync system
- [`ONBOARDING_GUIDE.md`](ONBOARDING_GUIDE.md) - Onboarding flow implementation

### Design & Brand
- [`CLAUDE.md`](CLAUDE.md) - Brand guidelines and development instructions
- [`DESIGN_PHILOSOPHY.md`](DESIGN_PHILOSOPHY.md) - Core design principles
- [`UI_DESIGN_GUIDELINES.md`](UI_DESIGN_GUIDELINES.md) - Comprehensive UI/UX standards

### Future Development
- [`V2_FEATURES.md`](V2_FEATURES.md) - Post-MVP feature roadmap
- [`SettingsRefinementPlan.md`](SettingsRefinementPlan.md) - Settings UI improvements

## Quick Start

### Prerequisites
- Xcode 15+
- iOS 17+ device or simulator
- Bubble.io account (for backend API)
- AWS account (for S3 image storage)
- Google Cloud Console account (for Google Sign-In)

### Setup
1. Clone the repository
2. Open `OPS.xcodeproj` in Xcode
3. Update configuration in `AppConfiguration.swift`:
   - Bubble API endpoints
   - API keys
4. Configure AWS credentials in `S3UploadService.swift` (temporary solution)
5. Set up Google Sign-In:
   - Add your `GoogleService-Info.plist`
   - Update URL schemes in Info.plist
6. Build and run on device/simulator

## Architecture

### Core Stack
- **UI Framework**: SwiftUI with UIKit integrations
- **Data Persistence**: SwiftData (iOS 17+) with offline-first design
- **Backend**: Bubble.io REST API with rate limiting
- **Image Storage**: AWS S3 with multi-tier caching system
- **Authentication**: Keychain Services + Google OAuth 2.0
- **Navigation**: MapKit with turn-by-turn directions
- **Permissions**: Enhanced handling with completion callbacks
- **Real-time Updates**: Combine framework for reactive programming

### Design Patterns
- **Architecture**: MVVM (Model-View-ViewModel)
- **Navigation**: Coordinator pattern for onboarding, tab-based for main app
- **Networking**: Async/await with retry logic and rate limiting
- **Storage**: Offline-first with prioritized background sync
- **State Management**: ObservableObject with @Published properties
- **Dependency Injection**: Environment objects for shared services

## Key Features

### Field-First Design
- Dark theme optimized for outdoor visibility (7:1 contrast ratios)
- Large touch targets (44pt minimum, 60pt preferred) for glove operation
- Full offline functionality with automatic sync when connected
- Battery-efficient operation with minimal background processing
- 30-second network timeouts for poor connectivity
- Intelligent sync prioritization based on data importance

### Core Functionality
1. **Project Management** 
   - Six-stage status workflow (RFQ → Estimated → Accepted → In Progress → Completed → Closed)
   - Real-time start/stop tracking
   - Rich project details with client information
   
2. **Team Coordination** 
   - Three role types: Field Crew, Office Crew, Admin
   - Contact integration for quick communication
   - Smart team member assignment
   
3. **Image Documentation** 
   - Offline capture with local storage
   - Automatic S3 upload with compression
   - Multi-tier caching system
   - Bidirectional deletion sync
   
4. **Calendar Integration** 
   - Month, week, and day views
   - Project count indicators
   - Smart navigation with date picker
   
5. **Offline Operation** 
   - SwiftData persistence for all features
   - Queue-based sync with retry logic
   - Conflict resolution preserving local changes

### Security
- Multi-layer authentication (Standard login, Google OAuth, PIN protection)
- Secure token storage in iOS Keychain with auto-renewal
- Role-based access control throughout the app
- Admin role auto-detection from company settings
- Encrypted HTTPS data transmission
- Background session management with PIN reset

## Development Guidelines

### Code Standards
- Use OPS typography system (Mohave, Kosugi - NO system fonts)
- Follow OPSStyle for all UI components with consistent spacing
- Maintain offline-first architecture in all features
- Test with gloves and in sunlight for field readability
- Minimum 44pt touch targets for all interactive elements
- Handle all error states with user-friendly messages
- Implement proper loading states for all async operations

### Git Workflow
- Feature branches from main
- Clear, descriptive commit messages
- No AI attribution in commits
- Regular rebasing to avoid conflicts

### Testing Requirements
- Manual testing on real devices (iPhone 12 or newer)
- Offline scenario validation (airplane mode testing)
- Performance testing on 3-year-old devices
- Field condition simulation:
  - Bright sunlight readability
  - Glove operation accuracy
  - Poor network connectivity
  - Low battery scenarios
- Permission handling edge cases
- Sync conflict resolution

## Support

### Current Features (v1.0.2)
- ✅ Complete authentication system with Google Sign-In
- ✅ Comprehensive onboarding flow with smart navigation
- ✅ Full project management with offline sync
- ✅ Advanced calendar with multiple view modes
- ✅ 13+ settings screens for complete customization
- ✅ Team management with role-based permissions
- ✅ Image system with S3 integration
- ✅ Live navigation with turn-by-turn directions
- ✅ Enhanced permission handling with user guidance

### Documentation
See the documentation files listed above for detailed information on specific topics.

### Reporting Issues
1. Check existing documentation
2. Test in offline mode
3. Provide device/iOS version
4. Include steps to reproduce

## License

Copyright © 2025 OPS App. All rights reserved.

---

**Built by trades, for trades.** 🔨