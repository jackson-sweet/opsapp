# OPS App - Onboarding Implementation Guide

**Last Updated**: July 03, 2025  
**Version**: 1.0.2

## Overview

The OPS app onboarding provides different flows for employees vs company owners, with intelligent navigation and robust error handling. The system uses a coordinator pattern for complex flow management.

## Onboarding Flows

### Employee Flow (6 steps)
1. **Welcome** → User Type Selection → Account Setup (email/password)
2. **Organization Join** (account created confirmation)
3. **User Details** (first name, last name, phone)
4. **Company Code** (enter code to join company)
5. **Permissions** (location and notifications)
6. **Field Setup** → **Completion**

### Company Owner Flow (11 steps)
1. **Welcome** → User Type Selection → Account Setup (email/password)
2. **Organization Join** (account created confirmation)
3. **User Details** (personal information)
4. **Company Basic Info** (name and logo - optional)
5. **Company Address** (location with map)
6. **Company Contact** (email and phone)
7. **Company Details** (industry, size, age)
8. **Company Code** (display generated code)
9. **Team Invites** (invite team members)
10. **Permissions** (location and notifications)
11. **Field Setup** → **Completion**

## Implementation Details

### Key Features
- **Adaptive Theming**: Light theme for employees, dark theme for company owners
- **Smart Navigation**: Automatically skips completed steps when resuming
- **Step Indicators**: Progress tracking with accurate step counts
- **Data Persistence**: All form data saved progressively in UserDefaults
- **Error Recovery**: Robust handling of API failures with clear messaging
- **Permission Handling**: Immediate alerts for denied permissions with Settings navigation

### Core Components

#### 1. OnboardingViewModel
The view model manages state and navigation for the onboarding flow:

```swift
class OnboardingViewModel: ObservableObject {
    // Current step management
    @Published var currentStep: OnboardingStep = .welcome
    @Published var selectedUserType: UserType?
    
    // User input fields
    @Published var email = ""
    @Published var password = ""
    @Published var firstName = ""
    @Published var lastName = ""
    @Published var phoneNumber = ""
    @Published var companyCode = ""
    
    // Company fields (for owners)
    @Published var companyName = ""
    @Published var companyAddress = ""
    @Published var companyEmail = ""
    @Published var companyPhone = ""
    @Published var companyIndustry: Industry?
    @Published var companySize: CompanySize?
    @Published var companyAge: CompanyAge?
    @Published var teamInviteEmails: [String] = []
    
    // State management
    @Published var isSignedUp = false
    @Published var isCompanyJoined = false
    @Published var userId = ""
    
    // Navigation methods
    func moveToNextStep()
    func moveToPreviousStep()
    
    // API methods
    func submitEmailPasswordSignUp() async throws -> Bool
    func createCompany() async throws
    func joinCompany() async throws -> Bool
    func sendTeamInvitations() async throws
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

#### 3. Key Screens

**Common Screens (Both Flows)**:
- **WelcomeView**: Initial screen with app branding
- **UserTypeSelectionView**: Choose between Employee/Company Owner
- **EmailView**: Account creation with email/password
- **OrganizationJoinView**: Account created confirmation
- **UserInfoView**: Personal details collection
- **PermissionsView**: Location and notification permissions
- **FieldSetupView**: Offline data preparation
- **CompletionView**: Animated completion before welcome guide

**Company Owner Specific**:
- **CompanyBasicInfoView**: Company name and optional logo
- **CompanyAddressView**: Location with map integration
- **CompanyContactView**: Business contact details
- **CompanyDetailsView**: Industry, size, and age selection
- **CompanyCodeDisplayView**: Shows generated company code
- **TeamInvitesView**: Email invitations for team members

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

## Recent Bug Fixes (v1.0.2)

### Fixed Issues
1. **User Type Persistence**: User type is now only saved after successful signup
2. **Team Invite Navigation**: Removed duplicate switch case that skipped team invites
3. **Company Data Loading**: Company objects properly stored in SwiftData during onboarding
4. **Back Navigation**: Disabled back button after account creation to prevent re-signup
5. **Account Created Screen**: Fixed navigation to show for all user types
6. **Step Numbering**: Corrected step calculations for accurate progress display

### Implementation Notes
- User type stored in `selected_user_type` key in UserDefaults
- Company data synced using `createCompany()` and `joinCompany()` methods
- SwiftData integration ensures offline access to company information
- Navigation logic in `OnboardingModels.swift` uses enum-based flow control