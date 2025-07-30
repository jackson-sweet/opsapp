# OPS Onboarding Flow

## Overview
The OPS onboarding system guides new users through account setup and company association. The flow adapts based on user type (company vs employee) and authentication method (email/password vs social sign-in).

## Authentication Methods

### Email/Password
Traditional signup requiring:
- Email address
- Password (minimum 8 characters)
- Manual entry of user details

### Social Sign-In
Streamlined authentication via:
- **Sign in with Apple**: Uses Apple ID with optional email relay
- **Google Sign-In**: Uses Google account credentials

Both methods support:
- Automatic account creation for new users
- Seamless login for existing users
- Pre-population of user details (name, email)

## Onboarding Steps

### 1. User Type Selection
Users choose between:
- **Company**: Organization owners/administrators
- **Employee**: Field workers and crew members

### 2. Account Setup (Email/Password only)
- Email and password entry
- Skipped for social sign-in users

### 3. Personal Information
- First and last name
- Phone number
- Pre-filled for social sign-in users

### 4. Company Association
- **Company Users**: Create new organization
- **Employee Users**: Join via company code

### 5. Permissions Setup
- Location access
- Notification preferences
- Optional based on user needs

## Technical Implementation

### State Management
- Handled by `OnboardingViewModel`
- Persists progress in UserDefaults
- Supports resuming interrupted flows

### Data Flow
1. Authentication creates/fetches user
2. User type stored immediately
3. Company data fetched if available
4. Projects synchronized after company association

### Key Components
- `OnboardingContainerView`: Main container
- `OnboardingViewModel`: Business logic
- `OnboardingService`: API communication
- `DataController`: User and company management

## API Integration

### Endpoints Used
- `/login_apple`: Apple Sign-In
- `/login_google`: Google Sign-In  
- `/generate-api-token`: Email/password login
- `/join_company`: Employee company association
- `/create_company`: New organization setup

### Response Handling
- User object always returned
- Company object included if user has association
- Automatic admin detection from company data
- User type preservation across sessions

## Error Handling
- Network failures gracefully handled
- Clear error messages for users
- Automatic retry mechanisms
- Fallback to manual entry if needed

## Best Practices
1. Always clear user data on logout
2. Validate company codes before submission
3. Handle authentication state changes immediately
4. Preserve user progress through interruptions
5. Provide clear navigation options