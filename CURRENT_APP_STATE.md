# OPS App - Current State Overview

Last Updated: May 24, 2025

## Project Summary

OPS (Operational Project System) is a field-first job management iOS app designed specifically for trade workers. Built with SwiftUI and SwiftData, it prioritizes reliability and usability in challenging field conditions with poor connectivity. **Current completion: 87-90% MVP ready**.

## Architecture

- **Platform**: iOS 17+ (SwiftUI)
- **Architecture Pattern**: MVVM (Model-View-ViewModel)
- **Data Persistence**: SwiftData with offline-first approach
- **Backend**: Bubble.io API integration with comprehensive error handling
- **Authentication**: Secure token-based auth with Keychain storage
- **Design**: Dark theme optimized for outdoor visibility and glove-friendly operation

## Core Features Implemented

### 1. Authentication & Onboarding ✅
- **Two onboarding flows**: 
  - Original 11-step flow
  - Consolidated 7-step flow (togglable via feature flag)
- **Secure authentication** with KeychainManager
- **Profile management** with editable user details
- **Company code system** for joining organizations

### 2. Project Management ✅
- **Full CRUD operations** for projects
- **Status tracking**: RFQ, Estimated, Accepted, In Progress, Closed, Completed
- **Project details** including:
  - Client information
  - Location with map integration
  - Team member assignments
  - Project images/documentation
  - Notes and descriptions
- **Offline-first sync** with background synchronization

### 3. Calendar & Scheduling ✅
- **Month grid view** with project indicators
- **Day-based project lists**
- **Calendar controls** for navigation
- **Project cards** showing status and details

### 4. Home Screen ✅
- **Project carousel** for quick access
- **Active project mode** for field work
- **Navigation banner** showing current location
- **Quick actions** for common tasks

### 5. Team Features ✅
- **Team member management**
- **Role-based permissions**
- **Team assignment to projects**
- **Contact information display**

### 6. Settings ✅
Comprehensive settings implementation including:
- **Profile Settings**: User information, home address
- **Organization Settings**: Company details, team management
- **Notification Settings**: Project-specific preferences
- **Map Settings**: Navigation and display options
- **Security Settings**: Password reset, authentication
- **Data Storage Settings**: Cache management
- **Project/Expense History**: Historical data views
- **App Settings**: General preferences

### 7. Image Handling ✅
- **Photo capture** for project documentation
- **Offline image storage** with FileManager
- **Image sync** when connectivity returns
- **Migration** from UserDefaults to FileManager completed

### 8. Map Integration ✅
- **Project location visualization**
- **Turn-by-turn navigation**
- **Map annotations** for projects
- **Location permissions** handling

## Recent Updates

Based on recent commits:
1. **Map zoom system rewrite** - Improved user control and eliminated conflicts
2. **Home address field** - Added to User model and ProfileSettingsView
3. **Profile image removal** - Simplified UI by removing profile photos
4. **Photo uploading** - Enhanced capability for project documentation
5. **Sheet loading fixes** - Resolved issues with project detail sheets

Today's improvements (May 22, 2025):
1. **Tab bar keyboard fix** - Tab bar now hides when keyboard appears
2. **Swipe-back gesture** - Added native iOS swipe-back to all settings views
3. **Map pin drift fix** - Fixed annotation anchor points for stable positioning
4. **Calendar clarity** - Project counts now appear in corner of day cells
5. **Contact sheets** - Added unified contact detail sheets for clients and team members
6. **Address autocomplete** - Added MapKit-based address autocomplete with debouncing
7. **Form field standardization** - Created reusable FormTextField component
8. **Storage options slider** - Interactive storage selection for onboarding
9. **What we're working on** - Added upcoming features section to settings
10. **UI margins fixed** - Added tabBarPadding modifier to all scrollable views
11. **Reusable segmented control** - Created SegmentedControl component used across app

## Typography & Branding

The app uses custom fonts for distinctive branding:
- **Mohave**: Primary font for titles, body text, and UI elements
- **Kosugi**: Supporting font for captions and labels
- **Bebas Neue**: Available but rarely used (display font)

Color scheme:
- Dark theme optimized for outdoor visibility
- Primary accent: #59779F (blue)
- Status-specific colors for project states
- High contrast for field readability

## Data Models

### Core Models:
1. **User**: Authentication, profile, preferences
2. **Project**: Central entity with full field tracking
3. **Company**: Organization management
4. **TeamMember**: Team relationships and permissions

### Key Features:
- Offline-first with sync tracking
- Image storage management
- Location data with validation
- Status workflow tracking

## Current Development Status

### Completed ✅ (90%+ Production Ready)
- **Core authentication and user management** - Complete with PIN and Keychain security
- **Project CRUD with offline support** - Full lifecycle management with background sync
- **Calendar and scheduling** - Month/week/day views with project indicators
- **Settings screens implementation** - 13+ comprehensive settings views
- **Image handling system** - FileManager-based with sync capabilities
- **Map integration** - Navigation, annotations, location tracking
- **Team member features** - Complete role-based management
- **Onboarding flows** - Two complete flows (11-step & 7-step)

### In Progress 🚧 (85-90% Complete)
- **Push notifications** - Framework implemented, needs testing
- **Performance optimizations** - Background sync and large data sets
- **Image compression** - Cellular-optimized uploads
- **Error handling polish** - User-friendly messaging improvements

### Final MVP Tasks (Before June 1) 🎯
- **Phone verification** - Real SMS integration (currently simulated)
- **App Store preparation** - Screenshots, metadata, compliance
- **Field testing** - Final validation with trade workers
- **Performance testing** - Stress testing with large projects

### V2 Features (Post-MVP) 📋
Located in `/V2` directory:
- **Team member-specific notes** - Enhanced communication
- **Team member map locations** - Real-time positioning
- **Certifications & training management** - Skills tracking
- **Enhanced messaging capabilities** - In-app communication
- **Advanced reporting** - Analytics and insights
- **Platform expansion** - iPad and Apple Watch support

## Critical Path to June 1 Release

### Week 1 (May 24-31) - Core Completion
1. **Phone verification integration** - Real SMS API
2. **Push notification testing** - Comprehensive validation
3. **Performance optimization** - Memory and battery usage
4. **Bug fixes** - Address any remaining issues

### Week 2 (June 1-7) - Polish & Testing
1. **App Store assets** - Screenshots, descriptions, metadata
2. **Field testing** - Beta with 3-5 trade crews
3. **Accessibility review** - VoiceOver and contrast
4. **Final QA pass** - Complete feature validation

## Known Issues & Limitations

1. **Phone verification in onboarding is simulated** (HIGH PRIORITY - needs real SMS)
2. **Push notifications need stress testing** (MEDIUM PRIORITY)
3. **Image sync can be bandwidth-intensive** on cellular (optimization needed)
4. **Some settings features marked "Coming Soon"** (acceptable for MVP)
5. **Limited automated test coverage** (manual testing compensates)

## Development Guidelines

- **Field-first design**: Every decision prioritizes field usability
- **Offline reliability**: All features must work without connectivity
- **Large touch targets**: Minimum 44pt, preferred 56pt
- **High contrast**: Dark theme with clear visual hierarchy
- **No unnecessary complexity**: Features must justify their inclusion

## File Organization

The project follows a clear structure:
- `/Views`: All UI components organized by feature
- `/DataModels`: SwiftData models
- `/Network`: API and sync management
- `/Utilities`: Helper classes and extensions
- `/Styles`: Design system components
- `/Onboarding`: Complete onboarding system
- `/V2`: Future features in development

## Next Steps

1. Complete view reorganization
2. Optimize performance for older devices
3. Enhance offline image compression
4. Prepare for App Store submission
5. Implement V2 features based on user feedback