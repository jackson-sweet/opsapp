# OPS Onboarding Redesign Plan

## Current State Analysis

### Files Reviewed
- **Core Architecture**: OnboardingCoordinator.swift, OnboardingModels.swift, OnboardingService.swift, OnboardingViewModel.swift (~1800 lines)
- **Container/Presenter**: OnboardingContainerView.swift, OnboardingPresenter.swift, OnboardingView.swift
- **Screen Views (16)**: WelcomeView, UserTypeSelectionView, EmailView, OrganizationJoinView, UserInfoView, CompanyCodeInputView, PermissionsView, FieldSetupView, CompanyBasicInfoView, CompanyAddressView, CompanyContactView, CompanyDetailsView, CompanyCodeDisplayView, TeamInvitesView, BillingInfoView, WelcomeGuideView, CompletionView, CompanyCreationLoadingView
- **Components**: OnboardingComponents.swift, OnboardingHeader.swift, OnboardingPreviewHelpers.swift
- **Related Files**: ContentView.swift, OPSApp.swift, LoginView.swift, AuthManager.swift, User.swift, DataHealthManager.swift

---

## Critical Issues Identified

### 1. State Management Fragmentation
**Severity: HIGH**

Onboarding state is scattered across multiple locations with no single source of truth:

| Location | Data Stored |
|----------|-------------|
| `OnboardingViewModel` | email, password, firstName, lastName, phoneNumber, companyName, companyCode, selectedUserType, currentStep |
| `UserDefaults` | 20+ keys including user_id, is_authenticated, onboarding_completed, resume_onboarding, last_onboarding_step_v2, selected_user_type, user_email, user_password, user_first_name, etc. |
| `KeychainManager` | token, tokenExpiration, userId, username, password |
| `DataController` | isAuthenticated, currentUser |

**Problems:**
- Sync between these locations is manual and error-prone
- No mechanism to ensure consistency
- Difficult to determine "current state" when resuming

### 2. Complex/Fragile Resume Logic
**Severity: HIGH**

Resume logic is spread across multiple files:

```
LoginView.checkResumeOnboarding() - Lines 513-566
ContentView.onAppear - Lines 57-78 (special resume_onboarding handling)
DataHealthManager.performHealthCheck() - Company/user validation
```

**Problems:**
- Multiple code paths for resuming
- Hard to predict which path will execute
- `resume_onboarding` flag can get stale

### 3. Inconsistent ViewModel Pattern
**Severity: MEDIUM**

Views use different patterns for accessing the ViewModel:
- `@EnvironmentObject var onboardingViewModel: OnboardingViewModel` (TeamInvitesView, CompletionView, WelcomeGuideView)
- `@ObservedObject var viewModel: OnboardingViewModel` (most other views)

**Problems:**
- Views could accidentally access different instances
- Confusing for developers
- Potential for state desync

### 4. Step Number Logic is Error-Prone
**Severity: MEDIUM**

`OnboardingStep.stepNumber(for:)` returns optional Int and has complex conditional logic:
```swift
func stepNumber(for userType: UserType?) -> Int? {
    // 50+ lines of conditional logic
}
```

**Problems:**
- Total steps vary by user type (12 for company, 7 for employee)
- Progress bar calculation scattered across views
- No central validation that steps are complete

### 5. No Clear State Machine
**Severity: HIGH**

Current flow relies on sequential step traversal but:
- `canMoveToNextStep()` only validates current screen
- No validation that prerequisites are met when jumping steps
- `setStepBasedOnUserData()` tries to infer state but has gaps

### 6. Edge Cases Not Handled

| Scenario | Current Behavior |
|----------|------------------|
| User logs out mid-onboarding | `resume_onboarding` flag may persist, causing confusion |
| User completes partial onboarding on web | No sync with web state |
| Social login without company | Shows onboarding but may skip needed steps |
| App killed during API call | State may be inconsistent |
| User already exists in Bubble | May create duplicate or fail silently |

### 7. Redundant API Calls
**Severity: LOW**

- `OnboardingService.signUp()` creates user
- `OnboardingService.createCompany()` creates company and does full sync
- Multiple places call `syncManager.fullSync()`

### 8. Theme Logic Scattered
**Severity: LOW**

`shouldUseLightTheme` computed property checked in nearly every view:
```swift
private var backgroundColor: Color {
    viewModel.shouldUseLightTheme ? OPSStyle.Colors.Light.background : OPSStyle.Colors.background
}
```
This is repeated in 10+ places.

---

## Current Flow Diagrams

### Company Creator Flow (12 steps)
```
Welcome → UserTypeSelection → Email → UserInfo → OrganizationJoin → Permissions →
FieldSetup → CompanyBasicInfo → CompanyAddress → CompanyContact → CompanyDetails →
CompanyCodeDisplay → TeamInvites → Completion → WelcomeGuide (with BillingInfo)
```

### Employee Flow (7 steps)
```
Welcome → UserTypeSelection → Email → UserInfo → CompanyCode → Permissions →
FieldSetup → Completion → WelcomeGuide (with BillingInfo)
```

### Shared Steps
- Welcome
- UserTypeSelection
- Email (signup)
- UserInfo
- Permissions
- FieldSetup
- Completion
- WelcomeGuide

---

## Redesign Proposal

### Core Principles

1. **Single Source of Truth**: All onboarding state in ONE place
2. **State Machine**: Explicit states with valid transitions
3. **Recoverable**: Can resume from any point after app kill/logout
4. **Server-Synced**: Onboarding progress saved to Bubble
5. **Validated**: Each state transition validates prerequisites
6. **Simplified**: Remove redundant steps and consolidate

### Proposed Architecture

#### 1. OnboardingState (New State Machine)

```swift
enum OnboardingPhase: Int, Codable {
    case notStarted = 0
    case accountCreation = 1      // Email, Password
    case profileSetup = 2         // Name, Phone
    case organizationSetup = 3    // Create or Join company
    case permissionsSetup = 4     // Location, Notifications
    case appPreferences = 5       // Offline storage
    case completion = 6           // Welcome guide, billing
    case completed = 7
}

struct OnboardingState: Codable {
    var phase: OnboardingPhase
    var userType: UserType?
    var userId: String?
    var companyId: String?

    // Account data
    var email: String?
    var hasCreatedAccount: Bool

    // Profile data
    var firstName: String?
    var lastName: String?
    var phone: String?
    var hasCompletedProfile: Bool

    // Organization data
    var companyName: String?
    var companyCode: String?
    var hasOrganization: Bool

    // Permissions
    var hasLocationPermission: Bool
    var hasNotificationPermission: Bool

    // Preferences
    var offlineStorageMB: Int?

    var isComplete: Bool {
        phase == .completed
    }
}
```

#### 2. OnboardingManager (New Centralized Manager)

```swift
@MainActor
class OnboardingManager: ObservableObject {
    @Published private(set) var state: OnboardingState

    // Computed navigation
    var currentScreen: OnboardingScreen { ... }
    var canProceed: Bool { ... }
    var progress: Double { ... }

    // Actions
    func advance() async throws { ... }
    func goBack() { ... }
    func saveAndExit() async { ... }
    func resume() async { ... }

    // State persistence
    private func persist() { ... }
    private func restore() -> OnboardingState? { ... }
    private func syncToServer() async { ... }
}
```

#### 3. Simplified Screen Structure

```swift
enum OnboardingScreen {
    // Shared screens
    case welcome
    case accountType         // Company vs Employee
    case credentials         // Email + Password (skip if social login)
    case profile             // Name + Phone (combined)
    case permissions         // Location + Notifications (combined)
    case preferences         // Offline storage

    // Employee-only
    case companyCode         // Enter company code to join

    // Company creator-only
    case companyDetails      // Name, address, contact (consolidated)
    case companyCodeDisplay  // Show generated code
    case billing             // Trial/upgrade info

    // Final screens
    case tutorial            // Welcome guide (includes team invites for company)
    case complete
}
```

**Revised Flows:**

**Company Creator (8 screens):**
```
Welcome → AccountType → Credentials* → Profile → CompanyDetails →
CompanyCodeDisplay → Permissions → Preferences → Billing → Tutorial (w/ TeamInvites) → Complete
```

**Employee (7 screens):**
```
Welcome → AccountType → Credentials* → Profile → CompanyCode →
Permissions → Preferences → Tutorial → Complete
```

*Credentials skipped if social login successful

**Consolidation:**
- Merge Email + Password into `credentials`
- Merge FirstName/LastName/Phone into `profile`
- Merge CompanyBasicInfo/Address/Contact into `companyDetails`
- Merge Location/Notifications into `permissions` (already done)
- TeamInvites moved into Tutorial screen for company users
- Billing only shown to company creators at end

#### 4. Storage Strategy

```swift
// Single UserDefaults key for all onboarding state
UserDefaults.standard.set(encodedState, forKey: "onboarding_state")

// Bubble field on User model
User.onboardingPhase: Int
User.onboardingState: JSON (stringified state)
```

#### 5. Resume Strategy

```swift
func determineStartingPoint() async -> OnboardingScreen {
    // 1. Check local state
    if let localState = restoreLocalState() {
        // 2. Check server state
        if let serverState = await fetchServerState() {
            // Use whichever is further along
            return max(localState, serverState).currentScreen
        }
        return localState.currentScreen
    }

    // 3. Check if user exists in Bubble
    if let existingUser = await checkExistingUser() {
        return inferStateFromUser(existingUser)
    }

    return .welcome
}
```

---

## Implementation Phases

### Phase 1: Foundation (COMPLETED)
- [x] Create `OnboardingState` model → `OPS/Onboarding/Models/OnboardingState.swift`
- [x] Create `OnboardingManager` class → `OPS/Onboarding/Manager/OnboardingManager.swift`
- [x] Create `OnboardingScreen` enum → included in OnboardingState.swift
- [x] Implement state persistence (local) → JSON to UserDefaults with key `onboarding_state_v2`
- [x] Add convenience methods to OnboardingService for manager integration
- [ ] Write unit tests for state transitions

### Phase 2: Screen Consolidation (COMPLETED)
All new screens created in `OPS/Onboarding/Views/NewOnboarding/Screens/`:
- [x] `WelcomeScreen.swift` - Brand intro
- [x] `AccountTypeScreen.swift` - Company vs Employee selection
- [x] `CredentialsScreen.swift` - Combined email + password
- [x] `ProfileScreen.swift` - Combined name + phone
- [x] `CompanyCodeScreen.swift` - Employee enters code to join
- [x] `CompanyDetailsScreen.swift` - Consolidated company info (name, address, contact)
- [x] `CompanyCodeDisplayScreen.swift` - Shows generated code for company creators
- [x] `PermissionsScreen.swift` - Location + Notifications
- [x] `PreferencesScreen.swift` - Offline storage settings
- [x] `BillingScreen.swift` - Trial/plan info for company creators
- [x] `TutorialScreen.swift` - Feature guide + team invites for company creators
- [x] `CompleteScreen.swift` - Success confirmation

Container and Components:
- [x] `OnboardingContainerView.swift` - Main router with progress bar
- [x] `NewOnboardingView.swift` - Entry point with factory methods
- [x] Reusable components: OnboardingProgressBar, LoadingOverlay, ErrorToast, OnboardingScreenLayout, OnboardingPrimaryButton, OnboardingSecondaryButton, OnboardingTextField

### Phase 3: Integration (COMPLETED)
- [x] Update LoginView to use NewOnboardingContainerView instead of old OnboardingView
- [x] Update LoginView "GET SIGNED UP" button to create fresh OnboardingManager
- [x] Update LoginView login success handler to use OnboardingManager.shouldShowOnboarding()
- [x] Update LoginView Apple Sign-In handler for new onboarding
- [x] Update LoginView Google Sign-In handler for new onboarding
- [x] Update LoginView checkResumeOnboarding() to use OnboardingManager
- [x] Update ContentView to check for incomplete onboarding using OnboardingManager
- [ ] Test all flows: fresh signup, social login, resume scenarios
- [ ] Remove old onboarding files after testing

### Phase 4: Cleanup
- [ ] Delete old screen files (EmailView, UserInfoView, CompanyBasicInfoView, etc.)
- [ ] Delete OnboardingViewModel and OnboardingCoordinator
- [ ] Clean up scattered UserDefaults keys
- [ ] Update any remaining references to old onboarding

### Phase 5: Polish
- [ ] Add Bubble fields for onboarding tracking (server sync)
- [ ] Add analytics/logging for debugging
- [ ] Write unit tests for state transitions

---

## UserDefaults Keys to Consolidate

### Current Keys (To Remove)
```
resume_onboarding
last_onboarding_step_v2
selected_user_type
user_type
user_type_raw
user_email
user_password
user_first_name
user_last_name
user_phone_number
company_code
company_id
Company Name
has_joined_company
currentUserCompanyId
location_permission_granted
notifications_permission_granted
offlineStorageLimitMB
cacheImages
cacheProjectData
```

### New Keys (Single Source)
```
onboarding_state (JSON-encoded OnboardingState)
```

### Keys to Keep
```
is_authenticated
onboarding_completed
user_id (needed by DataHealthManager)
has_launched_before
```

---

## Decisions Made

1. **Team Invites**: Move to welcome/tutorial screens for company users (not during main onboarding)
2. **Billing**: Show at end of company onboarding flow
3. **Web App Sync**: Web has separate flow - no need to sync onboarding steps
4. **Social Login**: Skip credentials screen entirely if social login succeeds
5. **Login Flow**: Current login functionality works perfectly - don't modify

---

## Files Created

```
OPS/Onboarding/
├── Models/
│   └── OnboardingState.swift ✅
├── Manager/
│   └── OnboardingManager.swift ✅
└── Views/
    └── NewOnboarding/
        ├── OnboardingContainerView.swift ✅ (includes progress bar, loading overlay, error toast, reusable components)
        ├── NewOnboardingView.swift ✅ (entry point with factory methods)
        └── Screens/
            ├── WelcomeScreen.swift ✅
            ├── AccountTypeScreen.swift ✅
            ├── CredentialsScreen.swift ✅
            ├── ProfileScreen.swift ✅
            ├── CompanyCodeScreen.swift ✅
            ├── CompanyDetailsScreen.swift ✅
            ├── CompanyCodeDisplayScreen.swift ✅
            ├── PermissionsScreen.swift ✅
            ├── PreferencesScreen.swift ✅
            ├── BillingScreen.swift ✅
            ├── TutorialScreen.swift ✅
            └── CompleteScreen.swift ✅
```

## Files to Delete (After Migration Complete)

```
- OnboardingCoordinator.swift (logic moves to OnboardingManager)
- OnboardingModels.swift (replaced by OnboardingState)
- EmailView.swift (merged into CredentialsScreen)
- UserInfoView.swift (merged into ProfileScreen)
- CompanyCodeInputView.swift (merged into OrganizationScreen)
- CompanyBasicInfoView.swift (merged into CompanyDetailsScreen)
- CompanyAddressView.swift (merged into CompanyDetailsScreen)
- CompanyContactView.swift (merged into CompanyDetailsScreen)
- TeamInvitesView.swift (moved to Settings)
- CompanyCodeDisplayView.swift (inline in OrganizationScreen)
```

---

## Next Steps

1. Review this plan and ask any clarifying questions
2. Decide on Phase 1 implementation approach
3. Create the new state model and manager
4. Begin incremental migration

---

*Document created: $(date)*
*Last updated: $(date)*
