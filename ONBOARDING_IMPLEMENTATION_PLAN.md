# Onboarding Flow Implementation Plan

This document outlines the step-by-step plan to transition from the current 11-step onboarding flow to the new consolidated 7-step flow.

## Phase 1: Testing Infrastructure

1. **Create Feature Flag**
   - Add a feature flag in `AppConfiguration.swift` to toggle between old and new flows
   ```swift
   struct UX {
       // ...existing code...
       
       // Use the new consolidated onboarding flow
       static let useConsolidatedOnboardingFlow = true
   }
   ```

2. **Update OnboardingPresenter**
   - Modify `OnboardingPresenter.swift` to use the appropriate flow based on the feature flag
   ```swift
   struct OnboardingPresenter {
       // ...existing code...
       
       static func presentOnboarding(from viewController: UIViewController) {
           if AppConfiguration.UX.useConsolidatedOnboardingFlow {
               // Present new flow
               let onboardingView = OnboardingViewV2()
               // Present the view
           } else {
               // Present existing flow
               let onboardingView = OnboardingView()
               // Present the view
           }
       }
   }
   ```

3. **Create Initial Testing Setup**
   - Register all new views with SwiftUI previews
   - Ensure all preview providers include test data

## Phase 2: Implementation Steps

1. **Move New Files to Main Directory**
   - Move all files from `/Updates` directory to their proper locations
   - Ensure proper imports and references

2. **Update OnboardingViewModel**
   - Integrate `OnboardingViewModelExtension.swift` into the main model
   - Add support for the new flow steps
   - Update validation logic to work with consolidated screens

3. **Update OnboardingCoordinator**
   - Add support for the new flow
   - Update any flow-specific method calls

4. **Create Flag-Based Navigation**
   - In `ContentView.swift`, add logic to show the appropriate onboarding flow:
   ```swift
   if !dataController.isAuthenticated {
       if AppConfiguration.UX.useConsolidatedOnboardingFlow {
           OnboardingViewV2()
       } else {
           OnboardingView()
       }
   }
   ```

## Phase 3: Testing and Validation

1. **Create Test Cases**
   - Valid user flow (all info provided correctly)
   - Error handling (invalid email, password too short, etc.)
   - Permission handling (accept/decline)
   - Company code validation
   - Offline mode setup

2. **Verify Data Storage**
   - Check that all user data is properly saved to UserDefaults
   - Ensure company connection works correctly
   - Validate that permissions are properly requested and recorded

3. **Verify API Interactions**
   - Test account creation API call
   - Test company joining API call
   - Ensure proper error handling for API failures

4. **Device Testing**
   - Test on multiple iOS devices (various screen sizes)
   - Verify portrait and landscape orientations
   - Test with reduced motion and accessibility settings

## Phase 4: Rollout Strategy

1. **Controlled Rollout**
   - Set feature flag to `false` by default
   - Add ability to enable via debug menu or settings
   - Create TestFlight build with new flow enabled for beta testers

2. **Full Deployment**
   - After successful beta testing, set feature flag to `true` by default
   - Remove old flow files after several versions
   - Update documentation and design guides

3. **Cleanup**
   - Remove unused assets and resources
   - Update screen references throughout the app
   - Remove feature flag once fully deployed

## Fallback Plan

If issues arise with the new flow:

1. **Immediate Action**
   - Set feature flag to `false` to revert to old flow
   - Create hotfix for critical issues

2. **Investigation**
   - Identify specific failure points
   - Test in isolation with controlled input

3. **Resolution**
   - Fix issues in new flow components
   - Re-test comprehensively before re-enabling

## Migration Notes

For existing users who have partially completed onboarding:

1. **Implementation Considerations**
   - Check `last_onboarding_step` in UserDefaults
   - Map old step values to new consolidated steps
   - Resume at appropriate point in new flow

2. **Edge Cases**
   - Handle users between email/password screens
   - Support users who completed account but not company joining
   - Handle users with partial permissions granted

## Code Structure

```
/OPS/Onboarding/
  /Models/
    OnboardingModels.swift         (Updated with new step enum)
  /ViewModels/
    OnboardingViewModel.swift      (Updated for consolidated screens)
  /Views/
    /Components/
      OnboardingComponents.swift   (Retain existing components)
    /Screens/
      WelcomeView.swift            (Keep existing)
      AccountSetupView.swift       (New consolidated screen)
      UserDetailsView.swift        (New consolidated screen)
      CompanyCodeView.swift        (Keep existing, minor updates)
      ConsolidatedPermissionsView.swift (New consolidated screen)
      FieldSetupView.swift         (New screen)
      CompletionView.swift         (Keep existing, minor updates)
    OnboardingContainerView.swift  (Updated for new flow)
    OnboardingContainerV2.swift    (New flow container during transition)
```

This implementation plan ensures a smooth transition with minimal risk, giving us the ability to toggle between flows if needed during development and testing.