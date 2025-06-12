# Onboarding Step Indicator Update Summary

## Changes Made

### 1. Updated OnboardingModels.swift
Added centralized step counting logic with the following new methods:
- `stepNumber(for userType: UserType?) -> Int?` - Returns the step number for a given step and user type
- `totalSteps(for userType: UserType) -> Int` - Returns total steps for each user type
- `getStepIndicator(for userType: UserType?) -> String` - Returns formatted step indicator string

### 2. Updated Step Counting Logic

#### Employee Flow (7 total steps):
1. Account Setup
2. Organization Join
3. User Details
4. Company Code
5. Permissions
6. Field Setup
7. Completion

Not counted: Welcome, User Type Selection, Welcome Guide (not shown for employees)

#### Company Flow (12 total steps):
1. Account Setup
2. User Details
3. Company Basic Info
4. Company Address
5. Company Contact
6. Company Details
7. Company Code Display
8. Team Invites
9. Permissions
10. Field Setup
11. Completion
12. Welcome Guide

Not counted: Welcome, User Type Selection

### 3. Updated All Onboarding Screens
Updated the following screens to use the centralized step counting:
- AccountSetupView.swift
- OrganizationJoinView.swift
- CompanyCodeInputView.swift
- FieldSetupView.swift
- PermissionsView.swift
- CompanyBasicInfoView.swift
- CompanyAddressView.swift
- CompanyContactView.swift
- CompanyDetailsView.swift
- CompanyCodeDisplayView.swift
- TeamInvitesView.swift
- UserInfoView.swift

Each screen now calculates its step number and total steps using:
```swift
private var currentStepNumber: Int {
    return viewModel.currentStep.stepNumber(for: viewModel.selectedUserType) ?? defaultValue
}

private var totalSteps: Int {
    guard let userType = viewModel.selectedUserType else { return defaultTotal }
    return OnboardingStep.totalSteps(for: userType)
}
```

## Benefits
1. **Centralized Logic**: Step counting is now managed in one place
2. **Consistency**: All screens use the same calculation method
3. **Maintainability**: Easy to update step counts or flow in the future
4. **Accuracy**: Step indicators now accurately reflect the actual flow for each user type