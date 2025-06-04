# OPS App - Field Operations Management System

## Overview
OPS (Operational Project System) is a specialized iOS app built for trade workers to manage projects and crews in the field. The app prioritizes reliability, simplicity, and offline functionality.

## Key Documentation

### Core Documentation
- [`PROJECT_OVERVIEW.md`](PROJECT_OVERVIEW.md) - High-level project structure and architecture
- [`CURRENT_STATE.md`](CURRENT_STATE.md) - Current implementation status and features
- [`DEVELOPMENT_GUIDE.md`](DEVELOPMENT_GUIDE.md) - Development guidelines and best practices
- [`API_GUIDE.md`](API_GUIDE.md) - Bubble.io API integration details

### Feature Documentation
- [`IMAGE_HANDLING.md`](IMAGE_HANDLING.md) - Complete image upload/fetch system documentation
- [`ONBOARDING_GUIDE.md`](ONBOARDING_GUIDE.md) - Onboarding flow implementation
- [`UI_DESIGN_GUIDELINES.md`](UI_DESIGN_GUIDELINES.md) - UI/UX design standards

### Brand & Design
- [`CLAUDE.md`](CLAUDE.md) - Brand guidelines and development instructions
- [`DESIGN_PHILOSOPHY.md`](DESIGN_PHILOSOPHY.md) - Design principles and philosophy

### Release Planning
- [`MVP_STATUS_UPDATE.md`](MVP_STATUS_UPDATE.md) - Current MVP completion status
- [`MVP_TODO.md`](MVP_TODO.md) - Remaining tasks for MVP
- [`MVP_RELEASE_CHECKLIST.md`](MVP_RELEASE_CHECKLIST.md) - Pre-release checklist

## Quick Start

### Architecture
- **Platform**: iOS 17+ (SwiftUI)
- **Data**: SwiftData with offline-first sync
- **Backend**: Bubble.io API
- **Storage**: AWS S3 for images
- **Design**: Dark theme optimized for field use

### Key Features
1. **Offline-First** - Full functionality without connectivity
2. **Image Management** - Multi-tier storage with automatic sync
3. **Project Tracking** - Status workflow from RFQ to Completed
4. **Team Coordination** - Role-based permissions and assignments
5. **Field-Optimized UI** - Large touch targets, high contrast

### Development Setup
1. Open `OPS.xcodeproj` in Xcode
2. Update AWS credentials in `S3UploadService.swift` (temporary)
3. Configure Bubble API endpoints in `AppConfiguration.swift`
4. Run on iOS 17+ device or simulator

## Technical Stack
- **SwiftUI** - Modern declarative UI
- **SwiftData** - Local persistence
- **Combine** - Reactive programming
- **AWS SDK** - S3 integration
- **MapKit** - Location services
- **PhotosUI** - Image selection

## Support
For detailed information on any component, refer to the documentation files listed above.