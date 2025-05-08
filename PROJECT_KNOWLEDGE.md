# OPS App Project Knowledge

## Recent Work (2025-05-08)

### UI Revamp
- Updated onboarding UI with modern styling and white buttons on dark background
- Improved typography with more readable headers
- Enhanced form fields with underlined inputs and validation
- Added subtle animations for improved user experience
- Updated login screen and splash screen with smooth transitions

### Authentication Fixes
- Fixed issues with users being logged in but not having user data populated
- Enhanced company code field to handle uppercase input correctly
- Added SwiftData integration to properly save user and company data
- Fixed user creation logic to update existing users when appropriate

### SwiftData Integration
- Fixed compilation errors with FetchDescriptor by avoiding variable shadowing
- Replaced optional binding with non-optional variables and emptiness checks
- Added proper error handling for database operations
- Added detailed debug logging for SwiftData operations

## Architecture Overview

### Key Technologies
- **SwiftUI** for the user interface
- **SwiftData** for local database persistence
- **MVVM Architecture** pattern
- **Combine** for reactive programming
- **Foundation** for core functionality
- **CoreLocation** for location services

### Core Components
- **DataController**: Central repository for app state and database management
- **OnboardingViewModel**: Manages the onboarding flow state and user input
- **UserDefaults**: Used for simple persistence of settings and authentication state
- **SyncManager**: Handles synchronization between local database and remote API
- **ImageSyncManager**: Manages synchronization of images between local storage and remote API

## Database Models

### User
- Primary model for user information (matches Bubble API)
- Contains personal info (name, email, phone) and company association
- Has relationship with projects through assignedProjects

### Company
- Model for company information (matches Bubble API)
- Contains company details (name, logo, contact info, location)
- Stores relationship IDs as comma-separated strings

### Project
- Model for project information
- Contains project details (title, status, dates, location)
- Has relationships with team members (users)

## Onboarding Flow

### Original Flow (11 steps)
1. Welcome
2. Email
3. Password
4. Account Created
5. Organization Join
6. User Info (First/Last Name)
7. Phone Number
8. Company Code
9. Welcome to Company
10. Permissions
11. Completion

### Consolidated Flow (7 steps)
1. Welcome
2. Account Setup (Email/Password)
3. Organization Connection
4. User Details (Name/Phone)
5. Company Code
6. Permissions
7. Field Setup

## Authentication Process
1. User creates account with email/password
2. User fills in personal info
3. User enters company code to join organization
4. User grants necessary permissions
5. User completes onboarding and is logged in
6. DataController loads user data from API or database

## Known Issues and Pending Tasks

### UI Improvements Needed
- Location services and notifications view need more appealing, minimalist design
- Field setup view should simplify syncing preferences
- Use non-technical language for all UI elements, considering the target audience of tradesmen

### Authentication and Session Handling
- Need to test resuming onboarding if user exits app mid-flow
- Ensure proper user state restoration based on how far they got in onboarding
- Verify handling of partial account creation scenarios

### API Integration Issues
- Company information parsing needs improvement (address, email not storing correctly)
- Need to implement API call to fetch team member information
- Need to handle company information updates more efficiently

### Team Member Integration
- Add API endpoint for fetching team members by their user IDs
- Store fetched team members in the local database
- Create UI for displaying team members within organization
- Add team member indicators on project cards

## Development Guidelines

### Code Style
- Use SwiftUI best practices
- Follow MVVM architecture pattern
- Use proper access control for properties and methods
- Keep view code separate from business logic

### Error Handling
- Use proper error types and descriptive error messages
- Handle network errors gracefully with user-friendly messages
- Add detailed logging for debugging

### Testing
- Create preview data for UI testing
- Use mocked data for unit testing
- Test edge cases for authentication flow

### User Experience
- Keep UI simple and intuitive
- Use appropriate typography and colors
- Provide clear feedback for user actions
- Consider offline-first experience

## Target Audience Considerations
- Primary users are tradesmen who may not be tech-savvy
- Avoid technical jargon in the UI
- Provide clear instructions and guidance
- Make workflows straightforward and linear where possible
- Use visual cues and icons to enhance understanding

## Next Steps

1. Enhance Permission Screens
   - Redesign location services and notifications views with a minimalist approach
   - Add clearer explanations of why permissions are needed
   - Create more visually appealing permission request UI

2. Revise Field Setup View
   - Simplify data syncing options
   - Use plain language instead of technical terms
   - Add visual indicators of what each option means

3. Test Onboarding Resume Logic
   - Verify that users can resume onboarding where they left off
   - Ensure authentication state is properly preserved
   - Add recovery paths for interrupted onboarding

4. Improve API Integration
   - Fix company information parsing
   - Add team member fetching functionality
   - Update models to better handle API response structure

5. Enhance Team Member UI
   - Create team member list view with photos and roles
   - Add team member indicators on projects
   - Show team member location on map when available