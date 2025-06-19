# OPS App Onboarding System

## Overview

The onboarding system provides a comprehensive flow for user registration and initial app setup. It handles:

1. User welcome and introduction
2. Phone number collection and verification
3. Email and password creation
4. Company association via company code (intelligently skipped for users already in a company)
5. Permission requests (location and notifications) with proper denied/restricted state handling
6. Account creation via Bubble API

## Architecture

The onboarding system follows the MVVM (Model-View-ViewModel) pattern with a coordinator:

- **Models**: Data structures and API response types
- **ViewModels**: Business logic and state management
- **Views**: UI components and screens
- **Coordinator**: Flow management and persistence

## Integration with Bubble API

The system integrates with a Bubble backend using the `sign_user_up` endpoint, which accepts:
- `user_email` - User's email address
- `user_password` - User's chosen password
- `company_code` - Optional company identifier code

The API responds with:
- `user_id` - The created user's ID
- `company_joined` - "yes" or "no" indicating if company association was successful
- `error_message` - Optional error details

## File Structure

```
Onboarding/
├── Models/
│   └── OnboardingModels.swift      # Data models for onboarding
├── ViewModels/
│   └── OnboardingViewModel.swift   # Business logic and state
├── Coordinators/
│   └── OnboardingCoordinator.swift # Flow management
├── Services/
│   └── OnboardingService.swift     # API integration
├── Views/
│   ├── Components/
│   │   └── OnboardingComponents.swift  # Shared UI components
│   ├── Screens/
│   │   ├── WelcomeView.swift       # Initial welcome screen
│   │   ├── PhoneNumberView.swift   # Phone number entry
│   │   ├── VerifyPhoneView.swift   # Phone verification
│   │   ├── EmailView.swift         # Email entry
│   │   ├── PasswordView.swift      # Password creation
│   │   ├── CompanyCodeView.swift   # Company code entry
│   │   ├── PermissionsView.swift   # Location permission
│   │   └── CompletionView.swift    # Completion screen
│   └── OnboardingContainerView.swift  # Main container
└── README.md                       # Documentation
```

## Usage

To integrate the onboarding system into your app:

```swift
// In your main ContentView or App
struct MainApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .withOnboarding()  // Adds onboarding overlay
        }
    }
}
```

## Testing and Development

For testing purposes, you can reset the onboarding state:

```swift
// In a settings or debug view
@StateObject private var coordinator = OnboardingCoordinator()

Button("Reset Onboarding") {
    coordinator.resetOnboarding()
}
```

## Customization

To customize the appearance:
- Edit the `OnboardingComponents.swift` file for shared styles
- Modify individual screen views for specific layouts
- Update `OPSStyle.swift` for global color themes

## Key Features

### Smart Navigation
- **Company Code Skip Logic**: The flow automatically skips the company code step for employees who already have a company
- **Intelligent Back Navigation**: Back button properly skips company code when navigating from permissions if user already has a company
- **Permission Completion Callbacks**: LocationManager supports completion handlers to immediately respond to permission denials

### Permission Handling
- **Immediate Feedback**: When permissions are denied, alerts appear immediately with "Open Settings" options
- **Denied/Restricted States**: Proper handling of both denied and restricted permission states
- **Settings Integration**: Direct navigation to app settings when permissions need to be changed

## Notes for Future Developers

- The phone verification flow is currently simulated (doesn't send real SMS codes)
- For production, connect real SMS verification service
- Company code validation could be enhanced with real-time company lookup
- Consider adding analytics events at key onboarding steps
- Ensure Info.plist contains all required permission description keys for location and notifications