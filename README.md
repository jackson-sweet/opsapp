# OPS App - Field Operations Management System

## Overview

OPS (Operational Project System) is a specialized iOS app built for trade workers to manage projects and crews in the field. The app prioritizes reliability, simplicity, and offline functionality.

**Status**: LAUNCHED ✅  
**Version**: 1.0  
**Platform**: iOS 17+

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
- Bubble.io account (for backend)
- AWS account (for S3 image storage)

### Setup
1. Clone the repository
2. Open `OPS.xcodeproj` in Xcode
3. Update configuration in `AppConfiguration.swift`:
   - Bubble API endpoints
   - AWS credentials (temporary in `S3UploadService.swift`)
4. Build and run on device/simulator

## Architecture

### Core Stack
- **UI Framework**: SwiftUI
- **Data Persistence**: SwiftData
- **Backend**: Bubble.io REST API
- **Image Storage**: AWS S3
- **Authentication**: Keychain Services

### Design Patterns
- **Architecture**: MVVM (Model-View-ViewModel)
- **Navigation**: Coordinator pattern for onboarding
- **Networking**: Async/await with proper error handling
- **Storage**: Offline-first with background sync

## Key Features

### Field-First Design
- Dark theme optimized for outdoor visibility
- Large touch targets (44pt+) for glove operation
- Offline functionality with automatic sync
- Battery-efficient operation

### Core Functionality
1. **Project Management** - Status tracking from RFQ to completion
2. **Team Coordination** - Role-based permissions and assignments
3. **Image Documentation** - Capture and sync project photos
4. **Calendar Integration** - Schedule visualization and planning
5. **Offline Operation** - Full functionality without connectivity

### Security
- PIN-based app protection
- Secure token storage in Keychain
- Admin role auto-detection
- Encrypted data transmission

## Development Guidelines

### Code Standards
- Use OPS typography system (NO system fonts)
- Follow OPSStyle for all UI components
- Maintain offline-first architecture
- Test with gloves and in sunlight

### Git Workflow
- Feature branches from main
- Clear, descriptive commit messages
- No AI attribution in commits
- Regular rebasing to avoid conflicts

### Testing Requirements
- Manual testing on real devices
- Offline scenario validation
- Performance testing on older devices
- Field condition simulation

## Support

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