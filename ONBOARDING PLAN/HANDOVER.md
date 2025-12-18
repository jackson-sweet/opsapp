# Onboarding Implementation Handover

**Created:** December 2024
**Status:** Phase 3 Complete - All Screens Built

---

## Quick Context

We are rebuilding the OPS app's onboarding system from scratch. The current implementation has two parallel systems with 15+ screens. The new implementation simplifies this to 4-5 screens with phase-based transitions.

**Primary Document:** `ONBOARDING_IMPLEMENTATION_PLAN.md` (same folder)

---

## Key Decisions Made

| Decision | Resolution |
|----------|------------|
| Build new or refactor? | **Build fresh**, delete old after verification |
| Permissions screen? | **Delete** - use contextual permission requests in-app |
| Field Setup screen? | **Delete** - auto-assign full storage, changeable in Settings |
| Tutorial/WelcomeGuide? | **Keep** WelcomeGuideView, adapt to new design |
| Industry UI | **Searchable dropdown** (38 options) |
| Size/Age UI | **Pill buttons** for ranges |
| Company code format | Display with **[ brackets ]** |
| Phone validation | US format, just check not empty |
| Profile picture | **Optional**, use existing `ProfileImageUploader` |
| Company address | **Optional** |
| Form error recovery | **Keep form filled** on error, user can retry |
| Social auth | Bubble **auto-creates user** |
| State persistence key | `onboarding_state_v3` (new), keep `onboarding_completed` |

---

## Flows Summary

### Company Creator (4 screens)
```
Welcome → Credentials → ProfileCompany → Ready
```

### Employee (4 screens)
```
Welcome → Credentials → ProfileJoin → Ready
```

### UserType Selection (special)
- Shown when logged-in user has no userType
- Not part of main flow, inserted when needed

---

## API Calls Sequence

### New User - Company Creator
1. **Credentials:** `signUpWithEmailPassword()` OR `login_google` / `login_apple`
2. **Credentials:** PATCH `userType = "company"` to Bubble
3. **ProfileCompany:** `update_company` (creates company, returns code)
4. **Ready:** PATCH `hasCompletedAppOnboarding = true`

### New User - Employee
1. **Credentials:** `signUpWithEmailPassword()` OR `login_google` / `login_apple`
2. **Credentials:** PATCH `userType = "employee"` to Bubble
3. **ProfileJoin:** `join_company` (with company code)
4. **Ready:** PATCH `hasCompletedAppOnboarding = true`

### UserType Selection (resume scenario)
1. PATCH `userType` to Bubble when user selects

---

## Resume Logic

Order of checks (important - name before company):

```
1. hasCompletedAppOnboarding = true? → Main App
2. userType empty? → UserType Selection
3. firstName OR lastName empty? → Profile screen (pre-fill company if exists)
4. companyId empty? → Profile screen (profile pre-filled)
5. All data exists → Ready Screen
```

### Company Handling on Resume

**Company Creator with existing company:**
- Pre-fill all company fields (editable)
- Button says "CONTINUE"
- Calls `update_company` with `company_id` (updates, not creates)

**Employee with existing company:**
- Hide company code field
- Show company name as read-only
- Button says "CONTINUE"
- Just saves profile, skips join_company

---

## Implementation Progress Checklist

### Phase 1: Foundation
- [x] Create `OPS/Onboarding/State/OnboardingState.swift`
- [x] Create `OPS/Onboarding/Manager/OnboardingManager.swift`
- [x] Create `OPS/Onboarding/Container/OnboardingContainer.swift`

### Phase 2: Components
- [x] Create `OnboardingScaffold.swift` (base screen wrapper)
- [x] Create `OnboardingProgressBar.swift`
- [x] Create `SocialAuthButton.swift` (unified Google/Apple buttons)
- [x] Create `CompanyCodeDisplay.swift` (with brackets + input variant)
- [x] Create `OnboardingLoadingOverlay.swift` (with view modifier)
- [x] Create `OnboardingHelpSheet.swift` (with help button component)
- [x] Create `PillButtonGroup.swift` (with flow layout for wrapping)

### Phase 3: Screens
- [x] Create `WelcomeScreen.swift`
- [x] Create `UserTypeSelectionScreen.swift`
- [x] Create `CredentialsScreen.swift`
- [x] Create `ProfileCompanyScreen.swift` (3 phases)
- [x] Create `ProfileJoinScreen.swift` (2 phases)
- [x] Create `ReadyScreen.swift` (integrate WelcomeGuideView)

### Phase 4: Integration
- [ ] Update `ContentView.swift` to use new OnboardingContainer
- [ ] Test new user - company creator flow
- [ ] Test new user - employee flow
- [ ] Test resume scenarios (all 9 cases)
- [ ] Test social auth (Google, Apple)
- [ ] Test error handling (invalid code, network errors)
- [ ] Test pre-fill behavior

### Phase 5: Cleanup
- [ ] Verify all functionality works
- [ ] Delete old onboarding files (see IMPLEMENTATION_PLAN.md Section 10)
- [ ] Clean up old UserDefaults keys
- [ ] Final testing

---

## Files Reference

### To Create (new folder structure)
```
OPS/Onboarding/
├── State/
│   └── OnboardingState.swift ✅
├── Manager/
│   └── OnboardingManager.swift ✅
├── Components/ ✅ (Phase 2 Complete)
│   ├── OnboardingScaffold.swift ✅
│   ├── OnboardingProgressBar.swift ✅
│   ├── SocialAuthButton.swift ✅
│   ├── CompanyCodeDisplay.swift ✅
│   ├── OnboardingLoadingOverlay.swift ✅
│   ├── OnboardingHelpSheet.swift ✅
│   └── PillButtonGroup.swift ✅
├── Screens/ ✅ (Phase 3 Complete)
│   ├── WelcomeScreen.swift ✅
│   ├── UserTypeSelectionScreen.swift ✅
│   ├── CredentialsScreen.swift ✅
│   ├── ProfileCompanyScreen.swift ✅
│   ├── ProfileJoinScreen.swift ✅
│   └── ReadyScreen.swift ✅
└── Container/
    └── OnboardingContainer.swift ✅
```

### To Keep
- `OPS/Onboarding/Services/OnboardingService.swift` - API integration
- `OPS/Onboarding/Views/Screens/WelcomeGuideView.swift` - Adapt for ReadyScreen
- `OPS/Views/Components/ProfileImageUploader.swift` - Reuse for avatars/logos

### To Delete (after verification)
See `ONBOARDING_IMPLEMENTATION_PLAN.md` Section 10 for full list.

---

## Reusable Components

### New Onboarding v3 Components (Phase 2)

| Component | Location | Use For |
|-----------|----------|---------|
| `OnboardingScaffold` | `Onboarding/Components/` | Base screen wrapper with title, subtitle, back button, content, footer |
| `OnboardingProgressBar` | `Onboarding/Components/` | Step progress indicator (continuous or segmented) |
| `SocialAuthButton` | `Onboarding/Components/` | Google/Apple sign-in buttons, `SocialAuthButtonStack` for grouped |
| `CompanyCodeDisplay` | `Onboarding/Components/` | Code display with [ brackets ], `CompanyCodeInput` for input field |
| `OnboardingLoadingOverlay` | `Onboarding/Components/` | Loading modal, `.onboardingLoading()` view modifier |
| `OnboardingHelpSheet` | `Onboarding/Components/` | Help modal with alternate action, `OnboardingHelpButton` component |
| `PillButtonGroup` | `Onboarding/Components/` | Horizontal pill buttons with FlowLayout for wrapping |

### Existing OPS Components

| Component | Location | Use For |
|-----------|----------|---------|
| `ProfileImageUploader` | `Views/Components/` | Profile pic, company logo |
| `OPSButtonStyle.Primary` | `Styles/Components/ButtonStyles.swift` | Main CTAs |
| `OPSButtonStyle.Secondary` | `Styles/Components/ButtonStyles.swift` | Secondary actions |
| `FormField` | `Styles/Components/FormInputs.swift` | Text inputs |
| `RadioOption` | `Styles/Components/FormInputs.swift` | Selection options |
| `Industry` enum | `Onboarding/Models/OnboardingModels.swift` | 38 industry options |
| `CompanySize` enum | `Onboarding/Models/OnboardingModels.swift` | 5 size options |
| `CompanyAge` enum | `Onboarding/Models/OnboardingModels.swift` | 5 age options |

---

## Important Implementation Notes

1. **userType must be PATCHed to Bubble** whenever selected (Welcome flow or UserType Selection)

2. **Check name BEFORE company** in resume logic

3. **Company code display:** Always use `[ CODE_HERE ]` format with brackets

4. **ProfileCompany screen:**
   - Industry = searchable dropdown
   - Size/Age = pill buttons
   - All fields editable even when pre-filled
   - `update_company` with `company_id` = update, without = create

5. **ProfileJoin screen:**
   - If has company: hide code field, show company name read-only
   - If no company: show code field with brackets

6. **Social auth:** Google/Apple auto-create Bubble user, then PATCH userType

7. **Form errors:** Keep form filled, show error, let user retry

---

## Questions for Product (if needed)

None currently - all questions have been answered.

---

## Next Steps

1. **Phase 3 Complete!** All 6 screens created in `OPS/Onboarding/Screens/`
2. **Continue with Phase 4: Integration**
   - Update `ContentView.swift` to use new OnboardingContainer
   - Test all flows (company creator, employee, resume scenarios)
   - Test social auth (Google, Apple)
   - Test error handling and edge cases
3. **Important Testing Notes:**
   - LoginView.swift already integrated with new API (uses `OnboardingManager.shouldShowOnboarding()`)
   - OnboardingPreviewView.swift rewritten for new v3 API (in Debug folder)
   - Verify all API calls work correctly with Bubble backend
4. **After Phase 4 testing passes, proceed to Phase 5: Cleanup**
   - Delete old onboarding files (see Section 10 of IMPLEMENTATION_PLAN.md)
   - Clean up old UserDefaults keys

---

## Phase 3 Implementation Notes

### Completed Tasks
- ✅ All 6 screens created in `OPS/Onboarding/Screens/`
- ✅ OnboardingContainer.swift cleaned up - removed all placeholders, routes to real screens
- ✅ google_logo asset verified (exists in Assets.xcassets)
- ✅ LoginView.swift updated to use new OnboardingManager API
- ✅ OnboardingPreviewView.swift rewritten for new v3 API

### Type Renames (to avoid conflicts)
Several types were renamed during implementation to resolve naming conflicts:
- `OnboardingError` → `OnboardingManagerError` (in OnboardingManager.swift)
- `LoadingOverlayModifier` → `OnboardingLoadingModifier` (in OnboardingLoadingOverlay.swift)
- `OnboardingStepIndicator` → `OnboardingStepIndicatorText` (in OnboardingProgressBar.swift)
- `FlowLayout` → `OnboardingFlowLayout` (in PillButtonGroup.swift)

### OnboardingManager Static Methods Added
New static methods for app integration:
```swift
// Clear persisted onboarding state
static func clearState()

// Check if onboarding should be shown (returns tuple)
@MainActor
static func shouldShowOnboarding(dataController: DataController) -> (Bool, OnboardingManager?)
```

### OnboardingContainer Changes
- Added `onComplete` callback parameter for preview/testing scenarios
- Removed all placeholder screens
- Now routes to actual screen implementations

### Files Deleted
- `OPS/Onboarding/Views/NewOnboarding/` (entire folder - caused duplicate type conflicts)
- `OPS/Onboarding/Models/OnboardingState.swift` (duplicate of State/OnboardingState.swift)

### Screen Implementations Summary

| Screen | Phases | Key Features |
|--------|--------|--------------|
| WelcomeScreen | 1 | OPS logo, CREATE/JOIN buttons, login sheet |
| UserTypeSelectionScreen | 1 | Selection cards for logged-in users without userType |
| CredentialsScreen | 1 | Email/password + SocialAuthButtonStack |
| ProfileCompanyScreen | 3 | form → processing → success (shows company code) |
| ProfileJoinScreen | 2 | form → joining (company code input) |
| ReadyScreen | 1 | Welcome guide pages with billing, GET STARTED button |

### Known Issues / Items Needing Testing

1. **API Integration:** All API calls need testing with live Bubble backend
2. **Social Auth:** Google/Apple sign-in flows need real device testing
3. **Resume Logic:** 9 resume scenarios need verification
4. **Form Pre-fill:** Verify data correctly pre-fills when resuming
5. **Error Handling:** Test invalid company codes, network errors
6. **Phase transitions:** Verify smooth animations between phases

### Phase 1 & 2 Review Notes (from previous agents)

**From Phase 1 Agent:**
- OnboardingManager uses explicit state machine pattern (good for debugging)
- State persistence uses Codable with UserDefaults
- Resume logic follows priority order: name before company check

**From Phase 2 Agent:**
- Components use OPSStyle consistently
- OnboardingScaffold handles SafeArea properly
- PillButtonGroup uses custom OnboardingFlowLayout for wrapping
- SocialAuthButton has fallback for missing google_logo asset

---

## Phase 4 Integration Checklist

Before starting Phase 4, ensure:
1. [ ] Read `ContentView.swift` to understand current onboarding presentation
2. [ ] Understand how `LoginView.swift` currently integrates (already updated)
3. [ ] Review all 9 resume scenarios in this document
4. [ ] Test on simulator first, then real device for social auth

Phase 4 Tasks:
1. [ ] Update `ContentView.swift` to use new OnboardingContainer
2. [ ] Test: New user → Company Creator flow
3. [ ] Test: New user → Employee flow
4. [ ] Test: Resume at each screen (9 scenarios)
5. [ ] Test: Social auth (Google, Apple)
6. [ ] Test: Error handling (invalid code, network errors)
7. [ ] Test: Pre-fill behavior on resume
8. [ ] Test: OnboardingPreviewView in Developer Dashboard

---

**End of Handover**
