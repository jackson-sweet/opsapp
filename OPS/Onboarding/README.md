# OPS App Onboarding System

## Overview

The onboarding system provides a comprehensive flow for user registration and initial app setup. It handles:

1. User welcome and introduction
2. Phone number collection and verification
3. Email and password creation
4. Company association via company code
5. Permission requests (location)
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

## Notes for Future Developers

- The phone verification flow is currently simulated (doesn't send real SMS codes)
- For production, connect real SMS verification service
- Company code validation could be enhanced with real-time company lookup
- Consider adding analytics events at key onboarding steps