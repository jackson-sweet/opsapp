# OPS Changelog

## Version 1.0.2 (Current)
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