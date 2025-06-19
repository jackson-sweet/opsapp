# OPS App - Onboarding Implementation Guide

## Overview

The OPS app onboarding flow has been streamlined from 11 steps to 7 steps, focusing on field-optimized design. This guide explains both flows and their implementation.

## Onboarding Flows

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
3. User Details (Name/Phone)
4. Company Code (skipped for employees who already have a company)
5. Consolidated Permissions
6. Field Setup
7. Completion

## Implementation Details

### Feature Flag System
Toggle between flows using the feature flag in `AppConfiguration.swift`:

```swift
struct UX {
    // Use the new consolidated onboarding flow
    static let useConsolidatedOnboardingFlow = true
}
```

### Core Components

#### 1. OnboardingViewModel
The view model manages state and navigation for both onboarding flows:

```swift
class OnboardingViewModel: ObservableObject {
    // Original flow steps
    @Published var currentStep: OnboardingStep = .welcome
    
    // New flow steps
    @Published var currentStepV2: OnboardingStepV2 = .welcome
    
    // User input fields
    @Published var email = ""
    @Published var password = ""
    @Published var firstName = ""
    @Published var lastName = ""
    @Published var phone = ""
    @Published var companyCode = ""
    
    // Navigation methods
    func nextStep()
    func previousStep()
    
    // Validation methods
    func validateEmail() -> Bool
    func validatePassword() -> Bool
    func validateUserInfo() -> Bool
    func validateCompanyCode() -> Bool
}
```

#### 2. OnboardingCoordinator
Manages the flow of screens and API interactions:

```swift
class OnboardingCoordinator {
    // Authentication methods
    func createAccount(email: String, password: String) async -> Result<User, AuthError>
    func joinCompany(companyCode: String) async -> Result<Company, APIError>
    
    // Data storage methods
    func saveUserInfo(firstName: String, lastName: String, phone: String)
    
    // Device setup methods
    func requestNotificationPermission()
    func requestLocationPermission()
    func setupOfflineMode()
}
```

#### 3. Consolidated Screens
New screens combine related steps for a more efficient flow:

- **AccountSetupView**: Combines email and password in a single form
- **UserDetailsView**: Combines name and phone fields
- **ConsolidatedPermissionsView**: Presents all permissions together
- **FieldSetupView**: New screen for offline setup and initial sync

#### 4. Smart Navigation
The onboarding flow includes intelligent navigation that adapts to user state:

- **Company Code Skip Logic**: Employees who already have a company automatically skip the company code step
- **Back Navigation**: The back button intelligently skips the company code step when appropriate
- **Permission Handling**: Denied/restricted permissions show immediate prompts to open Settings
- **Completion Callbacks**: LocationManager supports callbacks to handle permission results immediately

## UI Enhancements

### Design Guidelines
- **Typography**: Mohave for headers and body text, Kosugi for supporting text (improved readability)
- **Colors**: Dark background with high contrast for field visibility
- **Touch Targets**: Minimum 56pt height for all interactive elements
- **Field Layout**: Clear labels, input validation, helper text

### Error Handling
- Field validation with immediate feedback
- Contextual help for common errors
- Recovery paths for validation failures

### Accessibility
- High contrast mode support
- Dynamic type compatibility
- VoiceOver optimization

## Implementation Steps

### 1. Create New Screens
```swift
struct AccountSetupView: View {
    @ObservedObject var viewModel: OnboardingViewModel
    
    var body: some View {
        VStack(spacing: 24) {
            // Email field
            VStack(alignment: .leading) {
                Text("EMAIL")
                    .font(.caption)
                    .foregroundColor(.gray)
                
                TextField("Email address", text: $viewModel.email)
                    .keyboardType(.emailAddress)
                    .autocapitalization(.none)
                    .padding()
                    .background(Color.black.opacity(0.3))
                    .cornerRadius(8)
            }
            
            // Password field with similar styling
            // Continue button
        }
        .padding()
    }
}
```

### 2. Update Flow Container
```swift
struct OnboardingContainerV2: View {
    @StateObject var viewModel = OnboardingViewModel()
    
    var body: some View {
        ZStack {
            // Background gradient
            OPSStyle.Colors.backgroundGradient
                .edgesIgnoringSafeArea(.all)
            
            // Content based on current step
            Group {
                switch viewModel.currentStepV2 {
                case .welcome:
                    WelcomeView(viewModel: viewModel)
                case .accountSetup:
                    AccountSetupView(viewModel: viewModel)
                case .userDetails:
                    UserDetailsView(viewModel: viewModel)
                // Other cases
                }
            }
            .transition(.opacity.combined(with: .move(edge: .trailing)))
        }
    }
}
```

### 3. Implement Feature Flag Toggle
```swift
struct ContentView: View {
    @EnvironmentObject var dataController: DataController
    @AppStorage("onboardingComplete") var onboardingComplete = false
    @Environment(\.useConsolidatedOnboarding) var useConsolidatedFlow
    
    var body: some View {
        if !onboardingComplete {
            if useConsolidatedFlow {
                OnboardingContainerV2()
            } else {
                OnboardingContainer()
            }
        } else {
            // Main app content
            MainTabView()
        }
    }
}
```

## Testing

### Test Cases
1. **Account Creation**
   - Valid email/password
   - Invalid email format
   - Password too short
   - Account already exists

2. **Company Connection**
   - Valid company code
   - Invalid company code
   - Network failure during validation

3. **Permission Handling**
   - Accept all permissions
   - Decline specific permissions (shows immediate settings prompt)
   - Handle denied/restricted states with settings navigation
   - Change permissions later

4. **State Preservation**
   - App backgrounded during flow
   - Flow resumed after restart
   - Network connection lost/restored

### Device Testing Matrix
Test on multiple device sizes and iOS versions:
- iPhone SE (smallest supported)
- iPhone 14/15 (standard)
- iPhone 14/15 Pro Max (largest)
- iOS 16, 17 (minimum required versions)

## Migration Strategy

### User State Mapping
For users who started onboarding in the old flow:

```swift
func mapOldStepToNewStep(_ oldStep: OnboardingStep) -> OnboardingStepV2 {
    switch oldStep {
    case .welcome:
        return .welcome
    case .email, .password:
        return .accountSetup
    case .userInfo, .phoneNumber:
        return .userDetails
    case .companyCode:
        return .companyCode
    case .permissions, .notifications:
        return .permissions
    default:
        return .welcome  // Default to start if mapping unclear
    }
}
```

### Data Preservation
All user data is preserved regardless of which flow is used:
- User credentials (email, password)
- Personal info (name, phone)
- Company association
- Permission preferences

## Field-Specific Optimizations

1. **Connection Resilience**
   - Form submissions work with intermittent connectivity
   - Data entered is cached locally before submission

2. **Visual Clarity**
   - High contrast design for outdoor visibility
   - Large touch targets for glove-friendly operation
   - Clear error states visible in bright light

3. **Offline Readiness**
   - Initial data download during onboarding
   - Offline mode toggle with clear indicators
   - Bandwidth usage controls for limited data plans

## Implementation Recommendations

1. **Visual Refinements**
   - Increase text size slightly for better field visibility
   - Add subtle animation to form transitions
   - Improve error message visibility

2. **Flow Optimizations**
   - Add skip options for non-essential steps
   - Allow later completion of some fields
   - Streamline permission explanation language

3. **Technical Improvements**
   - Prefetch company data during email verification
   - Implement parallel validation where possible
   - Improve keyboard handling on form fields