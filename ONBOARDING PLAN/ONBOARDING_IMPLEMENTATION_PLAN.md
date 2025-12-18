# OPS Onboarding Implementation Plan

**Version:** 1.0
**Created:** December 2024
**Purpose:** Complete specification for implementing the new onboarding system

---

## Table of Contents

1. [Overview](#1-overview)
2. [User Flows](#2-user-flows)
3. [Screen Specifications](#3-screen-specifications)
4. [Resume Logic](#4-resume-logic)
5. [State Management](#5-state-management)
6. [Component Library](#6-component-library)
7. [API Integration](#7-api-integration)
8. [Error Handling](#8-error-handling)
9. [File Structure](#9-file-structure)
10. [Files to Delete](#10-files-to-delete)
11. [Implementation Order](#11-implementation-order)

---

## 1. Overview

### Goals
- Simplify onboarding from 15+ screens to 4-5 screens
- Use phase-based transitions within screens (not separate screens)
- Support resume logic for users who signed up on web (Bubble)
- Reuse existing OPSStyle components where possible
- Delete old implementation after verification

### Flows
- **Company Creator:** Welcome → Credentials → ProfileCompany → Ready (4 screens)
- **Employee:** Welcome → Credentials → ProfileJoin → Ready (4 screens)
- **UserType Selection:** Special screen for logged-in users without userType (inserted before flow)

### Design Principles
- Tactical minimalism (dark theme, high contrast)
- Field-first design (large touch targets, readable in sunlight)
- No permissions during onboarding (contextual requests later)
- No billing during onboarding (separate flow)

---

## 2. User Flows

### 2.1 New User - Company Creator

```
[Welcome Screen]
    ↓ Tap "CREATE A COMPANY"
[Credentials Screen] - Phase 1: Email/Password or Social Auth
    ↓ Submit credentials
[Credentials Screen] - Phase 2: Verification (if needed)
    ↓ Verified
[ProfileCompany Screen] - Phase 1: Form (name, phone, company details)
    ↓ Submit all data
[ProfileCompany Screen] - Phase 2: Creating (loading)
    ↓ Success
[ProfileCompany Screen] - Phase 3: Success + Company Code + Invite Option
    ↓ Continue
[Ready Screen] - Welcome message + WelcomeGuideView content
    ↓ "GET STARTED"
[Main App]
```

### 2.2 New User - Employee

```
[Welcome Screen]
    ↓ Tap "JOIN A COMPANY"
[Credentials Screen] - Phase 1: Email/Password or Social Auth
    ↓ Submit credentials
[Credentials Screen] - Phase 2: Verification (if needed)
    ↓ Verified
[ProfileJoin Screen] - Phase 1: Form (name, phone, company code)
    ↓ Submit
[ProfileJoin Screen] - Phase 2: Joining (loading)
    ↓ Success
[Ready Screen] - Welcome message + WelcomeGuideView content
    ↓ "GET STARTED"
[Main App]
```

### 2.3 Existing User - Login

```
[Welcome Screen]
    ↓ Tap "Already have an account?"
[Login Sheet/Screen]
    ↓ Login successful
    ↓ Check hasCompletedAppOnboarding

If TRUE:  → [Main App] (skip onboarding)
If FALSE: → [Resume Point] (determined by user data)
```

### 2.4 Logged-in User Without UserType

```
[UserType Selection Screen] (special, not in main flow)
    ↓ Tap "CREATE A COMPANY" or "JOIN A COMPANY"
    ↓ Sets userType
[Resume appropriate screen based on other user data]
```

---

## 3. Screen Specifications

### 3.1 Welcome Screen

**Purpose:** Entry point, path selection

**Content:**
- OPS logo
- Tagline: "Operations Made Simple" or similar
- Button: "CREATE A COMPANY" → sets flow to .companyCreator
- Button: "JOIN A COMPANY" → sets flow to .employee
- Link: "Already have an account?" → shows login

**Navigation:**
- No back button (first screen)
- Forward: Credentials screen

**Data Collected:** Flow selection only (userType patched to Bubble after account creation in Credentials screen)

---

### 3.2 UserType Selection Screen

**Purpose:** Catch logged-in users without userType

**When Shown:** User is logged in but has no userType set

**Content:**
- Same as Welcome screen but without logo/tagline
- Header: "HOW WILL YOU USE OPS?"
- Button: "CREATE A COMPANY"
- Button: "JOIN A COMPANY"

**Behavior:**
- After selection:
  1. **API CALL:** PATCH user's `userType` field to Bubble
  2. Update local state
  3. Resume to appropriate screen based on other user data

**API Call:**
```swift
// When user taps "CREATE A COMPANY" or "JOIN A COMPANY"
await dataController.updateUserType(userType: "company") // or "employee"
```

---

### 3.3 Credentials Screen

**Purpose:** Account creation or social auth

**Phases:**

**Phase 1 - Input:**
- Email field (pre-filled if from social auth)
- Password field (hidden if social auth)
- "OR" divider
- Google Sign-In button
- Apple Sign-In button
- Continue button

**Phase 2 - Verification (if needed):**
- Verification code field
- Resend code link
- Continue button

**Navigation:**
- Back: Welcome screen (or previous based on flow)
- Forward: ProfileCompany or ProfileJoin (based on flow)

**Data Collected:**
- email
- password (or social auth token)
- userId (after account creation)

**API Calls (in order):**
1. Create account (email/password signup OR social auth)
2. **PATCH userType to Bubble** (set to "company" or "employee" based on flow selection)

**Validation:**
- Email: valid format, not empty
- Password: minimum 8 characters (if not social auth)

---

### 3.4 ProfileCompany Screen (Company Creator Flow)

**Purpose:** Collect profile + company data, create company

**Phases:**

**Phase 1 - Form:**
```
Profile Section:
- First Name (required) - text field
- Last Name (required) - text field
- Phone (required) - text field, US format
- Profile Picture (optional) - ProfileImageUploader

Company Section:
- Company Name (required) - text field
- Industry (required) - DROPDOWN with search (38 options)
- Company Size (required) - PILL BUTTONS (1-2, 3-5, 6-10, 11-20, 20+)
- Company Age (required) - PILL BUTTONS (<1, 1-2, 2-5, 5-10, 10+)
- Address (optional) - autocomplete field
- Company Logo (optional) - ProfileImageUploader with roundedSquare shape
```

**UI Components:**
- Industry: Searchable dropdown picker (due to 38 options)
- Size: Horizontal pill buttons, single select
- Age: Horizontal pill buttons, single select

**Phase 2 - Processing:**
- Loading overlay
- Text: "Creating your company..." OR "Updating your company..." (based on context)
- Progress indicator

**Phase 3 - Success:**
- Success message
- Company code display (generated by Bubble)
- "Copy Code" button
- "Invite Team Members" option (optional)
- Continue button

**Navigation:**
- Back: Credentials screen (phase 1 only)
- Forward: Ready screen

**Data Collected:**
- firstName, lastName, phone, avatar
- companyName, industry, size, age, address, logo
- companyCode (received from Bubble)

**Pre-fill & Edit Behavior:**
- All fields are **editable** even when pre-filled
- User can modify any pre-filled data before submitting

**Button Text Logic:**
```swift
var buttonText: String {
    hasExistingCompany ? "CONTINUE" : "CREATE COMPANY"
}
```

**API Calls:**
- `update_company` endpoint with all company data
  - If `company_id` is passed → **updates existing company**
  - If no `company_id` → **creates new company**
- User profile data updated via DataController

```swift
// API call logic
if let existingCompanyId = user.companyId {
    // Update existing company
    await updateCompany(companyId: existingCompanyId, data: companyData)
} else {
    // Create new company
    await createCompany(data: companyData)
}
```

---

### 3.5 ProfileJoin Screen (Employee Flow)

**Purpose:** Collect profile data + join existing company

**Phases:**

**Phase 1 - Form:**
```
Profile Section:
- First Name (required) - text field
- Last Name (required) - text field
- Phone (required) - text field, US format
- Profile Picture (optional) - ProfileImageUploader

Join Section (conditional):
- IF no existing company: Company Code field (required, with [ ] brackets)
- IF has existing company: Read-only company name display (code field hidden)
```

**Phase 2 - Joining:** (only if no existing company)
- Loading overlay
- "Joining company..." text
- Progress indicator

**Navigation:**
- Back: Credentials screen (phase 1 only)
- Forward: Ready screen

**Data Collected:**
- firstName, lastName, phone, avatar
- companyCode (entered by user) - only if joining new company

**Pre-fill & Edit Behavior:**
- Profile fields are **editable** even when pre-filled
- If user already has company:
  - Company code field is **hidden**
  - Show company name as **read-only display** (e.g., "Joining: ABC Construction")

**Button Text Logic:**
```swift
var buttonText: String {
    hasExistingCompany ? "CONTINUE" : "JOIN COMPANY"
}
```

**API Calls:**
```swift
// Save profile first
await dataController.updateUserProfile(firstName, lastName, phone, avatar)

// Then handle company
if hasExistingCompany {
    // No join_company call needed - just continue to Ready
} else {
    // Join new company
    await joinCompany(code: companyCode)
}
```

**Error Handling:**
- Invalid code: Show error message, form stays filled
- Company not found: Show error message
- Help button at bottom → shows sheet with:
  - Step explanation
  - "CREATE COMPANY INSTEAD?" button (clears userType, restarts flow)

---

### 3.6 Ready Screen

**Purpose:** Completion confirmation, transition to app

**Content:**
- Welcome message with user's name
- Company name confirmation
- WelcomeGuideView content (existing component, adapted)
- "GET STARTED" button

**Navigation:**
- No back button
- Forward: Main app (completes onboarding)

**Actions on Complete:**
- Set `hasCompletedAppOnboarding = true` on user object
- Set `UserDefaults.standard.set(true, forKey: "onboarding_completed")`
- Clear onboarding state from UserDefaults
- Trigger DataController sync

---

## 4. Resume Logic

### 4.1 Resume Decision Tree

When app launches and user is logged in:

```swift
func determineResumeScreen(user: User) -> OnboardingScreen {
    // Step 1: Already completed?
    if user.hasCompletedAppOnboarding == true {
        return .none // Skip to main app
    }

    // Step 2: No user type?
    if user.userType == nil || user.userType.isEmpty {
        return .userTypeSelection
    }

    // Step 3: Profile incomplete? (check BEFORE company)
    if user.firstName.isEmpty || user.lastName.isEmpty {
        // Go to appropriate profile screen
        // If they have a company, it will be pre-populated
        // Button will say "Continue" instead of "Create/Join Company"
        if user.userType == "company" {
            return .profileCompany
        } else {
            return .profileJoin
        }
    }

    // Step 4: No company?
    if user.companyId == nil || user.companyId.isEmpty {
        if user.userType == "company" {
            return .profileCompany // Profile pre-filled
        } else {
            return .profileJoin // Profile pre-filled
        }
    }

    // Has everything - just show ready screen
    return .ready
}
```

### 4.2 Resume Scenarios Table

| Scenario | hasCompletedAppOnboarding | userType | name | companyId | Result |
|----------|--------------------------|----------|------|-----------|--------|
| A | false | null | any | any | UserType Selection |
| B | false | "company" | empty | null | ProfileCompany |
| C | false | "employee" | empty | null | ProfileJoin |
| D | false | "company" | empty | exists | ProfileCompany (pre-fill company, button says "Continue") |
| E | false | "employee" | empty | exists | ProfileJoin (pre-fill company, button says "Continue") |
| F | false | "company" | exists | null | ProfileCompany (pre-fill profile only) |
| G | false | "employee" | exists | null | ProfileJoin (pre-fill profile only) |
| H | false | any | exists | exists | Ready |
| I | true | any | any | any | Skip to Main App |

### 4.3 Pre-filling Logic

When resuming, pre-fill form fields with existing user data:

```swift
// In ProfileCompany/ProfileJoin screens
.onAppear {
    if let user = dataController.currentUser {
        if !user.firstName.isEmpty { firstName = user.firstName }
        if !user.lastName.isEmpty { lastName = user.lastName }
        if !user.phone.isEmpty { phone = user.phone }
        // etc.
    }

    if let company = dataController.currentCompany {
        if !company.name.isEmpty { companyName = company.name }
        // etc.
    }
}

// Button text logic
var submitButtonText: String {
    if hasExistingCompany {
        return "CONTINUE"
    } else if flow == .companyCreator {
        return "CREATE COMPANY"
    } else {
        return "JOIN COMPANY"
    }
}
```

---

## 5. State Management

### 5.1 State Model

```swift
struct OnboardingState: Codable {
    var currentScreen: OnboardingScreen
    var flow: OnboardingFlow?
    var userData: UserData
    var companyData: CompanyData

    enum OnboardingScreen: String, Codable {
        case welcome
        case userTypeSelection
        case credentials
        case profileCompany
        case profileJoin
        case ready
    }

    enum OnboardingFlow: String, Codable {
        case companyCreator
        case employee
    }

    struct UserData: Codable {
        var email: String = ""
        var firstName: String = ""
        var lastName: String = ""
        var phone: String = ""
        var avatarURL: String?
        var userId: String?
    }

    struct CompanyData: Codable {
        var name: String = ""
        var industry: String = ""
        var size: String = ""
        var age: String = ""
        var address: String = ""
        var logoURL: String?
        var companyId: String?
        var companyCode: String?
    }
}
```

### 5.2 Persistence Keys

| Key | Type | Purpose |
|-----|------|---------|
| `onboarding_state_v3` | Data (Codable) | Full onboarding state |
| `onboarding_completed` | Bool | Quick check flag (backward compatible) |

**Note:** Do not migrate from v2. On fresh launch with no v3 state, determine resume point from Bubble user data.

### 5.3 OnboardingManager

```swift
@MainActor
class OnboardingManager: ObservableObject {
    @Published var state: OnboardingState
    @Published var isLoading: Bool = false
    @Published var error: Error?

    private let dataController: DataController
    var onComplete: (() -> Void)?

    // MARK: - Navigation
    func goToScreen(_ screen: OnboardingScreen)
    func goBack()
    func completeOnboarding()

    // MARK: - State Persistence
    func saveState()
    func loadState() -> OnboardingState?
    func clearState()

    // MARK: - Resume Logic
    func determineResumePoint() -> OnboardingScreen

    // MARK: - API Actions
    func createAccount(email: String, password: String) async throws
    func socialAuth(provider: AuthProvider) async throws
    func createCompany() async throws -> String // Returns company code
    func joinCompany(code: String) async throws
    func updateProfile() async throws
}
```

---

## 6. Component Library

### 6.1 Existing Components to Reuse (from OPSStyle)

**Buttons:**
- `OPSButtonStyle.Primary` - Main CTA buttons
- `OPSButtonStyle.Secondary` - Alternative actions
- `OPSButtonStyle.Destructive` - Cancel/error actions
- `OPSButtonStyle.Icon` - Icon buttons

**Form Inputs:**
- `FormField` - Standard text input with label
- `FormTextField` - Alternative text field
- `FormTextEditor` - Multi-line text
- `FormToggle` - Toggle with description
- `RadioOption` - Selection options

**Colors:**
- `OPSStyle.Colors.background` - Main background
- `OPSStyle.Colors.cardBackgroundDark` - Card backgrounds
- `OPSStyle.Colors.primaryText` - Main text
- `OPSStyle.Colors.secondaryText` - Subtle text
- `OPSStyle.Colors.primaryAccent` - Accent color

**Typography:**
- `OPSStyle.Typography.largeTitle` - Screen titles
- `OPSStyle.Typography.title` - Section titles
- `OPSStyle.Typography.body` - Body text
- `OPSStyle.Typography.button` - Button text
- `OPSStyle.Typography.caption` - Labels

**Layout:**
- `OPSStyle.Layout.spacing1-5` - Spacing values
- `OPSStyle.Layout.cornerRadius` - Standard radius
- `OPSStyle.Layout.touchTargetStandard` - Touch target size

### 6.2 New Components to Create

**OnboardingScaffold:**
```swift
struct OnboardingScaffold<Content: View>: View {
    let title: String
    let subtitle: String?
    let showBackButton: Bool
    let onBack: (() -> Void)?
    @ViewBuilder let content: () -> Content
    @ViewBuilder let footer: () -> AnyView?
}
```

**OnboardingProgressBar:**
```swift
struct OnboardingProgressBar: View {
    let currentStep: Int
    let totalSteps: Int
}
```

**SocialAuthButton:**
```swift
struct SocialAuthButton: View {
    enum Provider { case google, apple }
    let provider: Provider
    let action: () -> Void
}
```

**CompanyCodeDisplay:**
```swift
struct CompanyCodeDisplay: View {
    let code: String
    let onCopy: () -> Void
}
```

**OnboardingLoadingOverlay:**
```swift
struct OnboardingLoadingOverlay: View {
    let message: String
}
```

**HelpSheet:**
```swift
struct OnboardingHelpSheet: View {
    let title: String
    let description: String
    let alternateActionTitle: String?
    let onAlternateAction: (() -> Void)?
}
```

---

## 7. API Integration

### 7.1 Endpoints Used

**Authentication:**
- Email/password signup (existing in OnboardingService)
- Google Sign-In (existing)
- Apple Sign-In (existing)

**User:**
- Update user profile (DataController)
- Fetch user data (DataController)

**Company:**
- `update_company` - Create/update company
  - Parameters: name, email, phone, address, industry, size, logo, user (userId), age, name_last, name_first, user_phone, company_id (if updating)
  - Returns: company object with generated company_code
- Join company endpoint (existing in OnboardingService)

### 7.2 Data Flow

```
[User Input] → [OnboardingManager] → [OnboardingService/DataController] → [Bubble API]
                     ↓
              [Update Local State]
                     ↓
              [Persist to UserDefaults]
```

### 7.3 Existing Service Integration

Keep and use `OnboardingService.swift` for:
- `signUpWithEmailPassword()`
- `createCompany()`
- `joinCompany()`
- `updateUserProfile()`

Keep integration with:
- `DataController` for user/company data sync
- `SyncManager` for background sync
- `DataHealthManager` for validation

---

## 8. Error Handling

### 8.1 Validation Errors

| Field | Validation | Error Message |
|-------|------------|---------------|
| Email | Format, not empty | "Enter a valid email address" |
| Password | Min 8 chars | "Password must be at least 8 characters" |
| First Name | Not empty | "First name is required" |
| Last Name | Not empty | "Last name is required" |
| Phone | Valid format | "Enter a valid phone number" |
| Company Name | Not empty | "Company name is required" |
| Company Code | Not empty, valid | "Enter a valid company code" |

### 8.2 API Errors

| Error | User Message | Action |
|-------|--------------|--------|
| Network offline | "No internet connection. Check your connection and try again." | Retry button |
| Invalid company code | "Company code not found. Check the code and try again." | Stay on screen, show help |
| Email already exists | "An account with this email already exists." | Show login option |
| Server error | "Something went wrong. Please try again." | Retry button |
| Rate limited | "Too many attempts. Please wait a moment." | Disable button temporarily |

### 8.3 Help Sheet

Available on ProfileJoin screen when company code fails:

```
Sheet Content:
- Title: "NEED HELP?"
- Body: "The company code is a unique identifier shared by your company admin.
        Ask them for the code, or if you're the admin, create your own company."
- Button: "CREATE COMPANY INSTEAD?" (if userType is employee)
- Button: "JOIN A COMPANY INSTEAD?" (if userType is company)

Action: Clears userType and companyId, returns to UserTypeSelection
```

---

## 9. File Structure

### 9.1 New Files to Create

```
OPS/Onboarding/
├── State/
│   └── OnboardingState.swift              # State model
├── Manager/
│   └── OnboardingManager.swift            # Flow control (replace existing)
├── Components/
│   ├── OnboardingScaffold.swift           # Base screen wrapper
│   ├── OnboardingProgressBar.swift        # Step progress
│   ├── SocialAuthButton.swift             # Google/Apple buttons
│   ├── CompanyCodeDisplay.swift           # Code display + copy
│   ├── OnboardingLoadingOverlay.swift     # Loading state
│   └── OnboardingHelpSheet.swift          # Help modal
├── Screens/
│   ├── WelcomeScreen.swift                # Entry point
│   ├── UserTypeSelectionScreen.swift      # For logged-in users
│   ├── CredentialsScreen.swift            # Email/password/social
│   ├── ProfileCompanyScreen.swift         # Company creator profile
│   ├── ProfileJoinScreen.swift            # Employee profile + code
│   └── ReadyScreen.swift                  # Completion
└── Container/
    └── OnboardingContainer.swift          # Main entry + routing
```

### 9.2 Files to Keep

```
OPS/Onboarding/
├── Services/
│   └── OnboardingService.swift            # Keep - API integration
└── Views/Screens/
    └── WelcomeGuideView.swift             # Keep - Adapt for ReadyScreen
```

---

## 10. Files to Delete

After new implementation is verified and working:

```
DELETE:
OPS/Onboarding/
├── Coordinators/
│   └── OnboardingCoordinator.swift
├── Models/
│   ├── OnboardingModels.swift
│   └── OnboardingState.swift              # Replace with new
├── Manager/
│   └── OnboardingManager.swift            # Replace with new
├── ViewModels/
│   └── OnboardingViewModel.swift
├── Views/
│   ├── OnboardingContainerView.swift
│   ├── Components/
│   │   ├── OnboardingComponents.swift
│   │   └── OnboardingHeader.swift
│   ├── Screens/
│   │   ├── WelcomeView.swift
│   │   ├── EmailView.swift
│   │   ├── UserInfoView.swift
│   │   ├── UserTypeSelectionView.swift
│   │   ├── CompanyCodeInputView.swift
│   │   ├── CompanyCodeDisplayView.swift
│   │   ├── CompanyBasicInfoView.swift
│   │   ├── CompanyAddressView.swift
│   │   ├── CompanyContactView.swift
│   │   ├── CompanyDetailsView.swift
│   │   ├── OrganizationJoinView.swift
│   │   ├── TeamInvitesView.swift
│   │   ├── PermissionsView.swift
│   │   ├── FieldSetupView.swift
│   │   ├── BillingInfoView.swift
│   │   └── CompletionView.swift
│   └── NewOnboarding/
│       └── * (all files)
└── Views/Debug/
    └── OnboardingPreviewView.swift        # If exists
```

---

## 11. Implementation Order

### Phase 1: Foundation
1. Create `OnboardingState.swift` (state model)
2. Create `OnboardingManager.swift` (flow control + resume logic)
3. Create `OnboardingContainer.swift` (main entry + routing)

### Phase 2: Components
4. Create `OnboardingScaffold.swift`
5. Create `OnboardingProgressBar.swift`
6. Create `SocialAuthButton.swift`
7. Create `CompanyCodeDisplay.swift`
8. Create `OnboardingLoadingOverlay.swift`
9. Create `OnboardingHelpSheet.swift`

### Phase 3: Screens
10. Create `WelcomeScreen.swift`
11. Create `UserTypeSelectionScreen.swift`
12. Create `CredentialsScreen.swift`
13. Create `ProfileCompanyScreen.swift`
14. Create `ProfileJoinScreen.swift`
15. Create `ReadyScreen.swift` (integrate WelcomeGuideView)

### Phase 4: Integration
16. Update `ContentView.swift` to use new OnboardingContainer
17. Test all flows (new user, resume, login)
18. Test edge cases (offline, errors)

### Phase 5: Cleanup
19. Verify all functionality works
20. Delete old onboarding files (see Section 10)
21. Clean up UserDefaults keys
22. Final testing

---

## Appendix A: Industry Enum Values

**Source:** `OPS/Onboarding/Models/OnboardingModels.swift`

```swift
enum Industry: String, CaseIterable {
    case architecture = "Architecture"
    case bricklaying = "Bricklaying"
    case cabinetry = "Cabinetry"
    case carpentry = "Carpentry"
    case ceilingInstallations = "Ceiling Installations"
    case concreteFinishing = "Concrete Finishing"
    case consulting = "Consulting"
    case craneOperation = "Crane Operation"
    case deckConstruction = "Deck Construction"
    case deckSurfacing = "Deck Surfacing"
    case demolition = "Demolition"
    case drywall = "Drywall"
    case electrical = "Electrical"
    case excavation = "Excavation"
    case flooring = "Flooring"
    case glazing = "Glazing"
    case hvac = "HVAC"
    case insulation = "Insulation"
    case landscaping = "Landscaping"
    case masonry = "Masonry"
    case metalFabrication = "Metal Fabrication"
    case millwrighting = "Millwrighting"
    case painting = "Painting"
    case plumbing = "Plumbing"
    case railings = "Railings"
    case rebar = "Rebar"
    case renovations = "Renovations"
    case roofing = "Roofing"
    case scaffolding = "Scaffolding"
    case sheetMetal = "Sheet Metal"
    case siding = "Siding"
    case stonework = "Stonework"
    case surveying = "Surveying"
    case tileSetting = "Tile Setting"
    case vinylDeckMembranes = "Vinyl Deck Membranes"
    case waterproofing = "Waterproofing"
    case welding = "Welding"
    case windows = "Windows"
}
```

**Total:** 38 industries

**Note:** Industry is displayed in a searchable picker due to the large number of options.

---

## Appendix B: Company Size Options

**Source:** `OPS/Onboarding/Models/OnboardingModels.swift`

```swift
enum CompanySize: String, CaseIterable {
    case oneToTwo = "1-2"       // Display: "1-2 employees"
    case threeToFive = "3-5"   // Display: "3-5 employees"
    case sixToTen = "6-10"     // Display: "6-10 employees"
    case elevenToTwenty = "11-20" // Display: "11-20 employees"
    case twentyPlus = "20+"    // Display: "20+ employees"
}
```

**UI:** Radio button list (5 options - fits on one screen)

---

## Appendix C: Company Age Options

**Source:** `OPS/Onboarding/Models/OnboardingModels.swift`

```swift
enum CompanyAge: String, CaseIterable {
    case lessThanOne = "<1"    // Display: "Less than 1 year"
    case oneToTwo = "1-2"      // Display: "1-2 years"
    case twoToFive = "2-5"     // Display: "2-5 years"
    case fiveToTen = "5-10"    // Display: "5-10 years"
    case tenPlus = "10+"       // Display: "10+ years"
}
```

**UI:** Radio button list (5 options - fits on one screen)

---

## Appendix D: UserType Values

**Source:** `OPS/DataModels/UserRole.swift` (referenced in OnboardingModels.swift)

```swift
enum UserType: String {
    case employee = "employee"
    case company = "company"   // Account holder / company creator
}
```

**Notes:**
- `employee` = Field crew member joining existing company
- `company` = Account holder creating new company (becomes admin)

---

## Appendix E: Existing Components Reference

### From OPSStyle.swift:

**Button Styles (ButtonStyles.swift):**
- `OPSButtonStyle.Primary` - White/accent background, black text
- `OPSButtonStyle.Secondary` - Outlined with accent border
- `OPSButtonStyle.Destructive` - Red background for delete/cancel
- `OPSButtonStyle.Icon` - Circular icon buttons

**Form Components (FormInputs.swift):**
- `FormField` - Text input with label, supports secure/keyboard types
- `FormTextEditor` - Multi-line text with label
- `FormToggle` - Toggle with title and description
- `RadioOption` - Selection option with title, description, radio circle
- `SearchBar` - Search input with icon and clear button
- `EmptyStateView` - Icon + title + message for empty states

**Form Components (FormTextField.swift):**
- `FormTextField` - Alternative text field with label

### From Current Onboarding (OnboardingComponents.swift):

Components that may be worth keeping or adapting:
- `UnderlineTextField` - Minimalist underline-style text field
- `StandardContinueButton` - White/accent "CONTINUE" button with arrow
- `ProfileImageUploader` - Image picker with upload capability

---

## Appendix F: API Endpoints Reference

### Authentication:

**Email/Password Signup:**
- Via `OnboardingService.signUpWithEmailPassword()`

**Google Sign-In:**
- Endpoint: `/api/1.1/wf/login_google`
- Method: POST
- Parameters:
  - `id_token` (required) - Google ID token
  - `email` (required) - User's email from Google
  - `name` (required) - Full name
  - `given_name` (optional) - First name
  - `family_name` (optional) - Last name
- Returns: `{ status: "success", response: { user: UserDTO, company?: CompanyDTO } }`
- **Note:** Bubble auto-creates user if they don't exist

**Apple Sign-In:**
- Endpoint: `/api/1.1/wf/login_apple`
- Method: POST
- Parameters:
  - `identity_token` (required) - Apple identity token (JWT)
  - `user_identifier` (required) - Apple's unique user ID
  - `email` (optional) - May be relay address
  - `given_name` (optional) - Only on first auth
  - `family_name` (optional) - Only on first auth
- Returns: `{ status: "success", response: { user: UserDTO } }`
- **Note:** Bubble auto-creates user if they don't exist

### Company:

**Create/Update Company:**
- Endpoint: `update_company`
- Parameters: name, email, phone, address, industry (array), size, logo, user (userId), age, name_last, name_first, user_phone, company_id (if updating)
- Returns: Company object with `companyId` (code generated by Bubble, ~32 characters)

**Join Company:**
- Endpoint: `join_company`
- Parameters: company_code, user_id
- Returns: `JoinCompanyResponse` with company data

### User:
- Update profile via `DataController.updateCurrentUser()`
- Fetch user via `DataController.fetchAndSyncCurrentUser()`

---

## Appendix G: Key UserDefaults Keys

| Key | Type | Purpose | Keep/Delete |
|-----|------|---------|-------------|
| `onboarding_state_v3` | Data | New onboarding state | NEW |
| `onboarding_completed` | Bool | Quick completion check | KEEP |
| `onboarding_state_v2` | Data | Old state (full object) | DELETE after migration |
| `last_onboarding_step_v2` | Int | Old step tracking | DELETE after migration |
| `resume_onboarding` | Bool | Old resume flag | DELETE after migration |
| `company_code` | String | Stored company code | KEEP |
| `company_id` | String | Stored company ID | KEEP |
| `user_type` | String | User type selection | KEEP |

---

## Appendix H: UI/UX Specifications

### Company Code Display Format

Company codes are ~32 characters. Display with square brackets:

```
[ ABC123DEF456GHI789JKL012MNO345 ]
```

For input fields, also show brackets:
```swift
HStack {
    Text("[")
        .foregroundColor(OPSStyle.Colors.primaryText)
    TextField("Enter code", text: $companyCode)
    Text("]")
        .foregroundColor(OPSStyle.Colors.primaryText)
}
```

### Phone Number Format

- Format: US format
- No strict validation required
- Just check "not empty"

### Profile Image Uploader

Use existing `ProfileImageUploader` component from `OPS/Views/Components/ProfileImageUploader.swift`:

```swift
ProfileImageUploader(
    config: ImageUploaderConfig(
        currentImageURL: existingURL,
        currentImageData: localImageData,
        placeholderText: "JD", // Initials
        size: 80,
        shape: .circle, // or .roundedSquare(cornerRadius: 12) for company logos
        allowDelete: true,
        backgroundColor: OPSStyle.Colors.primaryAccent,
        uploadButtonText: "UPLOAD PHOTO"
    ),
    onUpload: { image in
        // Handle upload, return URL
        return uploadedURL
    },
    onDelete: {
        // Handle delete
    }
)
```

### Optional Fields

The following fields are optional:
- Profile picture
- Company address
- Company logo

### Form Error Recovery

If company creation/joining fails:
- Form stays filled with user's data
- Show error message
- User can retry without re-entering data

---

## Appendix I: Reusable Components to Use

### From OPS Codebase:

| Component | Location | Usage |
|-----------|----------|-------|
| `ProfileImageUploader` | `Views/Components/ProfileImageUploader.swift` | Profile pic & company logo |
| `OPSButtonStyle.Primary` | `Styles/Components/ButtonStyles.swift` | Main CTA buttons |
| `OPSButtonStyle.Secondary` | `Styles/Components/ButtonStyles.swift` | Secondary actions |
| `FormField` | `Styles/Components/FormInputs.swift` | Text inputs with labels |
| `RadioOption` | `Styles/Components/FormInputs.swift` | Selection options (size, age) |
| `SearchBar` | `Styles/Components/FormInputs.swift` | Industry search |

### From Current Onboarding (evaluate for reuse):

| Component | Location | Notes |
|-----------|----------|-------|
| `UnderlineTextField` | `Onboarding/Views/Components/OnboardingComponents.swift` | Minimalist style - consider adopting |
| `StandardContinueButton` | `Onboarding/Views/Components/OnboardingComponents.swift` | White button with arrow |
| `SignupGoogleButton` | `Onboarding/Views/Screens/WelcomeView.swift` | Google sign-in button |
| `SignupAppleButton` | `Onboarding/Views/Screens/WelcomeView.swift` | Apple sign-in button |

---

**End of Implementation Plan**
