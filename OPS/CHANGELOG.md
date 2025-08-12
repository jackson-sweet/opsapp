# OPS Changelog

## Version 1.1.0 (Current)
*Release Date: January 2025*

### Major Features
- **Advanced Contact Management System**
  - Sub-contact functionality for managing multiple contacts per client
  - Full CRUD operations for client and sub-client management
  - Contact import/export to device address book
  - Client profile photo support from Bubble's Thumbnail field
  - Role-based permissions for contact editing (Admin/Office only)

- **Enhanced Project Search**
  - Smart project search with filtering by status, client, and date
  - Auto-focusing search fields for faster access
  - Role-based project visibility (field crews see only assigned work)
  - Keyboard management improvements

- **Improved Calendar & Scheduling**
  - Fixed completion date logic (day after last work day)
  - Single-day project handling when start equals completion date
  - "Unscheduled" display for projects without dates
  - Proper date validation (completion only shows if on/after start)

### New Components
- `Client` and `SubClient` data models with full relationship support
- `ClientEditSheet` and `SubClientEditSheet` for contact editing
- `SubClientListView` for managing sub-contacts
- `AddressSearchField` with MapKit autocomplete
- `RefreshIndicator` with loading to success animation
- `ProjectSearchSheet` with smart filtering
- Contact management views (`ContactCreatorView`, `ContactPicker`, `ContactUpdater`)

### UI/UX Improvements
- Consistent card styling with proper borders throughout
- Team members section with unified styling
- Profile settings email field (disabled with grey border)
- All corner radius values use `OPSStyle.Layout.cornerRadius`
- Phone number formatting consistency
- Save/share buttons positioning in expanded views
- Address autocomplete for faster data entry

### Bug Fixes
- Fixed UIActivityViewController presentation conflicts
- Resolved keyboard pushing up main content
- Fixed preview crashes from missing environment objects
- Corrected project sync to remove unassigned projects
- Fixed team member display in project details
- Resolved contact sharing issues
- Fixed date parsing and display logic

### Data & Sync Improvements
- On-demand project refresh with visual feedback
- Profile photo syncing for users and clients
- Better offline handling with automatic sync
- Project removal when users are unassigned
- Enhanced client data refresh with 5-minute cache

### Technical Changes
- Updated to version 1.1.0 in all references
- Dynamic version display using `AppConfiguration.AppInfo`
- Launch screen updated to V1.1.0
- Comprehensive client/contact DTOs and endpoints
- Improved SyncManager with client refresh capabilities
- Enhanced date handling in Project model

## Version 1.0.2
*Release Date: January 2025*

### New Features
- **Sign in with Apple**: Added Apple authentication to comply with App Store requirements
- **Social Sign-Up**: Both Google and Apple sign-in now support account creation
- **Unified Avatar System**: Created consistent UserAvatar component used throughout the app
- **Smart Onboarding**: Social sign-in users skip redundant account setup steps

### Bug Fixes
- Fixed critical bug where projects wouldn't load after login without visiting settings
- Resolved user data contamination between different user sessions  
- Fixed "password is missing" error by updating API to use user ID
- Corrected profile image loading and default avatar display
- Fixed sign out button during onboarding to properly clear all data
- Resolved UI thread warnings during Google Sign-In
- Fixed login form spacing issues with back button cut off
- Cleared user type data on logout to prevent inheritance

### Improvements
- Projects now sync immediately on login with forced sync flag
- Enhanced admin role detection from company data
- Better UserDefaults cleanup on logout
- Improved error handling for authentication flows
- More reliable data synchronization
- Consistent avatar display with first and last initials

### Technical Changes
- Updated `DataController.clearAuthentication()` to remove all user data
- Modified `OnboardingViewModel` to skip setup for authenticated users
- Changed `joinCompany` API to use user ID instead of email/password
- Implemented `UserAvatar` component with image caching
- Added proper cleanup for `user_type` UserDefaults key

## Version 1.0.1
*Release Date: December 2024*

### Initial Release
- Core project management functionality
- Google Sign-In authentication
- Real-time project synchronization
- Offline mode support
- Team member management
- Location-based features
- Push notifications