# Settings & Security Wizard Fixes — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix all audit findings for the SettingsSecurityWizard so every step triggers, navigates, glows, and completes correctly for all roles.

**Architecture:** Seven targeted edits across 5 files — wizard definition (instruction text), state manager (auto-nav on step transitions), SettingsView (trigger + wizardTargets), OrganizationSettingsView (move notification), ProfileSettingsView (add screen dismissed), NotificationSettingsView (fix notification semantics).

**Tech Stack:** SwiftUI, NotificationCenter, WizardStateManager, OPSStyle

---

### Task 1: Add wizard trigger in SettingsView

**Files:**
- Modify: `OPS/OPS/Views/SettingsView.swift`

SettingsView currently has NO `@Environment(\.wizardTriggerService)` and never calls `evaluateTrigger` for the settings_security wizard. Without this, the wizard never fires.

- [ ] **Step 1: Add the wizard trigger environment property**

In `SettingsView.swift`, after line 15 (`@EnvironmentObject private var permissionStore: PermissionStore`), add:

```swift
@Environment(\.wizardTriggerService) private var wizardTriggerService
```

- [ ] **Step 2: Add evaluateTrigger call in the view's .onAppear**

Find the existing `.onAppear` on the main SettingsView body (or add one if none exists). The `.onAppear` should be on the outermost container that's already present. Search for existing `.onAppear` in SettingsView first. Add the trigger call:

```swift
.onAppear {
    // Wizard system: evaluate settings & security wizard trigger
    if let wizard = WizardRegistry.contextualWizard(for: "settings_security") {
        wizardTriggerService?.evaluateTrigger(for: wizard, context: "settings_tab_visit")
    }
}
```

If an `.onAppear` already exists on the main body, append this code inside the existing closure. Do NOT add a second `.onAppear`.

- [ ] **Step 3: Verify import**

Confirm `WizardRegistry` is accessible. It's a top-level struct in `OPS/OPS/Wizard/Definitions/WizardRegistry.swift` — no import needed beyond the existing module scope.

- [ ] **Step 4: Build**

```bash
cd /Users/jacksonsweet/Projects/OPS/OPS && xcodebuild -scheme OPS -destination 'generic/platform=iOS' build 2>&1 | tail -5
```

Expected: BUILD SUCCEEDED

- [ ] **Step 5: Commit**

```bash
cd /Users/jacksonsweet/Projects/OPS/OPS && git add OPS/Views/SettingsView.swift && git commit -m "fix(wizard): add settings_security trigger in SettingsView.onAppear"
```

---

### Task 2: Add auto-navigation on step transitions (systemic fix)

**Files:**
- Modify: `OPS/OPS/Wizard/State/WizardStateManager.swift:432-483`

`completeCurrentStep()` advances the step index and updates instruction text but never calls `navigateToCurrentStep()` or `requestDeepNavigation()`. When the new step's `targetScreen` differs from the completed step's, the user is stranded on the wrong screen with no guidance.

- [ ] **Step 1: Capture the previous step's targetScreen before advancing**

In `completeCurrentStep()` at `WizardStateManager.swift`, BEFORE the line `state.advanceStep(totalSteps: totalSteps)` (line 458), capture the old targetScreen:

```swift
        let previousTargetScreen = currentStep?.targetScreen
```

This line goes immediately before `state.advanceStep(totalSteps: totalSteps)`.

- [ ] **Step 2: Add auto-navigation after step advancement**

After the existing `TutorialHaptics.lightTap()` call (line 482), and BEFORE the closing `}` of `completeCurrentStep()`, add:

```swift
        // Auto-navigate when the new step targets a different screen
        if let newTarget = currentStep?.targetScreen,
           newTarget != previousTargetScreen {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                self?.navigateToCurrentStep()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    self?.requestDeepNavigation()
                }
            }
        }
```

- [ ] **Step 3: Build**

```bash
cd /Users/jacksonsweet/Projects/OPS/OPS && xcodebuild -scheme OPS -destination 'generic/platform=iOS' build 2>&1 | tail -5
```

Expected: BUILD SUCCEEDED

- [ ] **Step 4: Commit**

```bash
cd /Users/jacksonsweet/Projects/OPS/OPS && git add OPS/Wizard/State/WizardStateManager.swift && git commit -m "fix(wizard): auto-navigate when step transitions change targetScreen"
```

---

### Task 3: Fix step 2 — move notification to OrganizationSettingsView

**Files:**
- Modify: `OPS/OPS/Views/Settings/OrganizationSettingsView.swift:102-104`
- Modify: `OPS/OPS/Views/Settings/Organization/OrganizationDetailsView.swift:219-222`

The `WizardCompanyInfoViewed` notification currently fires inside `OrganizationDetailsView.onAppear` (a sub-screen of OrganizationSettingsView). The wizard step says "VIEW YOUR ORGANIZATION" — the OrganizationSettingsView hub already shows the company contact card with name, logo, phone, email, address, and team count. Viewing this hub IS viewing your organization. Move the notification to the hub.

- [ ] **Step 1: Add notification to OrganizationSettingsView.onAppear**

In `OrganizationSettingsView.swift`, the existing `.onAppear` at line 102-104 is:

```swift
.onAppear {
    loadOrganizationData()
}
```

Change it to:

```swift
.onAppear {
    loadOrganizationData()
    NotificationCenter.default.post(name: Notification.Name("WizardCompanyInfoViewed"), object: nil)
}
```

- [ ] **Step 2: Remove notification from OrganizationDetailsView.onAppear**

In `OrganizationDetailsView.swift`, the `.onAppear` at line 219-222 is:

```swift
.onAppear {
    loadOrganizationData()
    NotificationCenter.default.post(name: Notification.Name("WizardCompanyInfoViewed"), object: nil)
}
```

Remove the notification post line, leaving:

```swift
.onAppear {
    loadOrganizationData()
}
```

- [ ] **Step 3: Add WizardScreenDismissed to OrganizationSettingsView**

OrganizationSettingsView has no `.onDisappear`. Add one after the `.onAppear` block (after line 104):

```swift
.onDisappear {
    NotificationCenter.default.post(
        name: Notification.Name("WizardScreenDismissed"),
        object: nil,
        userInfo: ["screen": "Settings"]
    )
}
```

- [ ] **Step 4: Build**

```bash
cd /Users/jacksonsweet/Projects/OPS/OPS && xcodebuild -scheme OPS -destination 'generic/platform=iOS' build 2>&1 | tail -5
```

Expected: BUILD SUCCEEDED

- [ ] **Step 5: Commit**

```bash
cd /Users/jacksonsweet/Projects/OPS/OPS && git add OPS/Views/Settings/OrganizationSettingsView.swift OPS/Views/Settings/Organization/OrganizationDetailsView.swift && git commit -m "fix(wizard): move WizardCompanyInfoViewed to OrganizationSettingsView hub"
```

---

### Task 4: Add WizardScreenDismissed to ProfileSettingsView

**Files:**
- Modify: `OPS/OPS/Views/Settings/ProfileSettingsView.swift:309-312`

ProfileSettingsView posts `WizardProfileViewed` on `.onAppear` but never posts `WizardScreenDismissed` on `.onDisappear`. If the wizard ever changes to require actual profile edits (not just viewing), the exit prompt needs this.

- [ ] **Step 1: Add .onDisappear**

In `ProfileSettingsView.swift`, the current `.onAppear` block at line 310-312 is:

```swift
.trackScreen("Settings.Profile")
.onAppear {
    NotificationCenter.default.post(name: Notification.Name("WizardProfileViewed"), object: nil)
}
```

Add an `.onDisappear` immediately after the `.onAppear` closing brace:

```swift
.trackScreen("Settings.Profile")
.onAppear {
    NotificationCenter.default.post(name: Notification.Name("WizardProfileViewed"), object: nil)
}
.onDisappear {
    NotificationCenter.default.post(
        name: Notification.Name("WizardScreenDismissed"),
        object: nil,
        userInfo: ["screen": "Settings"]
    )
}
```

- [ ] **Step 2: Build**

```bash
cd /Users/jacksonsweet/Projects/OPS/OPS && xcodebuild -scheme OPS -destination 'generic/platform=iOS' build 2>&1 | tail -5
```

Expected: BUILD SUCCEEDED

- [ ] **Step 3: Commit**

```bash
cd /Users/jacksonsweet/Projects/OPS/OPS && git add OPS/Views/Settings/ProfileSettingsView.swift && git commit -m "fix(wizard): add WizardScreenDismissed to ProfileSettingsView"
```

---

### Task 5: Add all missing wizardTarget modifiers

**Files:**
- Modify: `OPS/OPS/Views/SettingsView.swift` (profile card, Organization row, Notifications row, Security & Privacy row)

Four elements need `.wizardTarget()` modifiers for the orange glow to guide users.

- [ ] **Step 1: Add wizardTarget to profile card**

In `SettingsView.swift`, the profile card ends at line 805:

```swift
        }
        .buttonStyle(PlainButtonStyle())
    }
```

Change it to:

```swift
        }
        .buttonStyle(PlainButtonStyle())
        .wizardTarget("open_profile", style: .row)
    }
```

- [ ] **Step 2: Add wizardTarget to Organization row**

In `SettingsView.swift`, the Organization settingsRow at lines 360-364 is:

```swift
                                settingsRow(
                                    icon: "building.2",
                                    title: "Organization",
                                    action: { activeDestination = .organization }
                                )
```

Add the modifier after the closing `)`:

```swift
                                settingsRow(
                                    icon: "building.2",
                                    title: "Organization",
                                    action: { activeDestination = .organization }
                                )
                                .wizardTarget("open_company", style: .row)
```

- [ ] **Step 3: Add wizardTarget to Notifications row**

In `SettingsView.swift`, the Notifications settingsRow at lines 380-384:

```swift
                                settingsRow(
                                    icon: OPSStyle.Icons.bellFill,
                                    title: "Notifications",
                                    action: { activeDestination = .notifications }
                                )
```

Add the modifier:

```swift
                                settingsRow(
                                    icon: OPSStyle.Icons.bellFill,
                                    title: "Notifications",
                                    action: { activeDestination = .notifications }
                                )
                                .wizardTarget("configure_notifications", style: .row)
```

- [ ] **Step 4: Add wizardTarget to Security & Privacy row**

In `SettingsView.swift`, the Security & Privacy settingsRow at lines 404-408:

```swift
                                settingsRow(
                                    icon: "lock",
                                    title: "Security & Privacy",
                                    action: { activeDestination = .security }
                                )
```

Add the modifier:

```swift
                                settingsRow(
                                    icon: "lock",
                                    title: "Security & Privacy",
                                    action: { activeDestination = .security }
                                )
                                .wizardTarget("enable_pin", style: .row)
```

- [ ] **Step 5: Build**

```bash
cd /Users/jacksonsweet/Projects/OPS/OPS && xcodebuild -scheme OPS -destination 'generic/platform=iOS' build 2>&1 | tail -5
```

Expected: BUILD SUCCEEDED

- [ ] **Step 6: Commit**

```bash
cd /Users/jacksonsweet/Projects/OPS/OPS && git add OPS/Views/SettingsView.swift && git commit -m "fix(wizard): add wizardTarget modifiers for all settings_security steps"
```

---

### Task 6: Fix wizard definition — instruction text and descriptions

**Files:**
- Modify: `OPS/OPS/Wizard/Definitions/SettingsSecurityWizard.swift`

Three text issues to fix:
1. Step 3 instruction "SET UP A PIN" doesn't match UI label "LOCK IT DOWN" / "Require PIN on App Launch"
2. Step 3 description says "Go to Security & Privacy" but wizard auto-navigates
3. Step 4 instruction "CONFIGURE NOTIFICATIONS" implies action but step auto-completes on view

- [ ] **Step 1: Replace the entire steps array**

In `SettingsSecurityWizard.swift`, replace the `let steps: [WizardStepDefinition]` array (lines 31-64) with:

```swift
    let steps: [WizardStepDefinition] = [
        WizardStepDefinition(
            id: "open_profile",
            instruction: "OPEN YOUR PROFILE",
            description: "Tap your name card at the top to view your profile details.",
            targetScreen: "Settings",
            canSkip: false,
            completionNotification: "WizardProfileViewed"
        ),
        WizardStepDefinition(
            id: "open_company",
            instruction: "VIEW YOUR ORGANIZATION",
            description: "Review your company name, logo, and contact information.",
            targetScreen: "Settings",
            canSkip: true,
            completionNotification: "WizardCompanyInfoViewed"
        ),
        WizardStepDefinition(
            id: "enable_pin",
            instruction: "ENABLE PIN LOCK",
            description: "Toggle on PIN lock to protect your data on this device.",
            targetScreen: "SecuritySettings",
            canSkip: true,
            completionNotification: "WizardPINEnabled"
        ),
        WizardStepDefinition(
            id: "configure_notifications",
            instruction: "VIEW NOTIFICATION SETTINGS",
            description: "Review your alert preferences and quiet hours.",
            targetScreen: "NotificationSettings",
            canSkip: true,
            completionNotification: "WizardNotificationsConfigured"
        )
    ]
```

Changes from original:
- Step 1 description: "Add your name, phone, and photo…" → "Tap your name card at the top to view your profile details." (directs the user to the exact element)
- Step 2 description: "Check your organization name, logo, and contact information." → "Review your company name, logo, and contact information." (matches hub screen content)
- Step 3 instruction: "SET UP A PIN" → "ENABLE PIN LOCK" (matches UI concept "LOCK IT DOWN" / "Require PIN on App Launch")
- Step 3 description: "Go to Security & Privacy and enable PIN lock…" → "Toggle on PIN lock to protect your data on this device." (wizard auto-navigates, so no "go to" needed)
- Step 4 instruction: "CONFIGURE NOTIFICATIONS" → "VIEW NOTIFICATION SETTINGS" (honest — step completes on view)
- Step 4 description: "Choose which alerts you get and set quiet hours." → "Review your alert preferences and quiet hours." (view, not configure)

- [ ] **Step 2: Update the file header comment**

Replace the audit comment at lines 9-12:

```swift
//  Audit fixes (2026-03-26):
//  - open_profile: canSkip=false — auto-completes by opening the screen
//  - enable_pin: canSkip=true — auto-skipped when PIN already enabled
```

With:

```swift
//  Audit fixes (2026-03-30):
//  - open_profile: canSkip=false, description directs to name card
//  - open_company: notification moved to OrganizationSettingsView hub
//  - enable_pin: instruction matches UI ("ENABLE PIN LOCK"), auto-skip when PIN enabled
//  - configure_notifications: renamed to VIEW — auto-completes on screen open
//  - Added trigger in SettingsView.onAppear
//  - Added wizardTarget modifiers for all steps
//  - Added WizardScreenDismissed to Profile and Organization screens
```

- [ ] **Step 3: Build**

```bash
cd /Users/jacksonsweet/Projects/OPS/OPS && xcodebuild -scheme OPS -destination 'generic/platform=iOS' build 2>&1 | tail -5
```

Expected: BUILD SUCCEEDED

- [ ] **Step 4: Commit**

```bash
cd /Users/jacksonsweet/Projects/OPS/OPS && git add OPS/Wizard/Definitions/SettingsSecurityWizard.swift && git commit -m "fix(wizard): update settings_security instruction text and descriptions"
```

---

### Task 7: Narrow step 4 wizardTarget on NotificationSettingsView

**Files:**
- Modify: `OPS/OPS/Views/Settings/NotificationSettingsView.swift:159`

The `.wizardTarget("configure_notifications")` is applied to the entire ScrollView. It should target the first visible section instead — the notification permission status card — for a focused glow.

- [ ] **Step 1: Move wizardTarget from ScrollView to the notification status card**

In `NotificationSettingsView.swift`, the current structure at lines 110-160 has the `.wizardTarget` on the ScrollView at line 159. Remove it from there and add it to the `notificationStatusCard` instead.

Current (line 159):
```swift
                .wizardTarget("configure_notifications")
```

Remove that line. Then find the `notificationStatusCard` reference at line 113:

```swift
                        // Permission Status Card
                        notificationStatusCard
```

Add the modifier:

```swift
                        // Permission Status Card
                        notificationStatusCard
                            .wizardTarget("configure_notifications", style: .row)
```

- [ ] **Step 2: Build**

```bash
cd /Users/jacksonsweet/Projects/OPS/OPS && xcodebuild -scheme OPS -destination 'generic/platform=iOS' build 2>&1 | tail -5
```

Expected: BUILD SUCCEEDED

- [ ] **Step 3: Commit**

```bash
cd /Users/jacksonsweet/Projects/OPS/OPS && git add OPS/Views/Settings/NotificationSettingsView.swift && git commit -m "fix(wizard): narrow configure_notifications target to status card"
```

---

### Task 8: Final verification build

**Files:** None (verification only)

- [ ] **Step 1: Clean build to verify all changes compile together**

```bash
cd /Users/jacksonsweet/Projects/OPS/OPS && xcodebuild -scheme OPS -destination 'generic/platform=iOS' clean build 2>&1 | tail -10
```

Expected: BUILD SUCCEEDED

- [ ] **Step 2: Verify all wizardTarget step IDs are used**

Grep for each step ID to confirm the modifier exists:

```bash
cd /Users/jacksonsweet/Projects/OPS/OPS && grep -rn 'wizardTarget.*open_profile\|wizardTarget.*open_company\|wizardTarget.*enable_pin\|wizardTarget.*configure_notifications' OPS/
```

Expected: At least one hit per step ID:
- `open_profile` in SettingsView.swift (profile card)
- `open_company` in SettingsView.swift (Organization row)
- `enable_pin` in SettingsView.swift (Security row) AND SecuritySettingsView.swift (PIN toggle)
- `configure_notifications` in SettingsView.swift (Notifications row) AND NotificationSettingsView.swift (status card)

- [ ] **Step 3: Verify all notifications have both post and observe**

```bash
cd /Users/jacksonsweet/Projects/OPS/OPS && grep -rn 'WizardProfileViewed\|WizardCompanyInfoViewed\|WizardPINEnabled\|WizardNotificationsConfigured' OPS/
```

Expected: Each notification appears in:
1. The wizard definition (completionNotification)
2. The view that posts it (.onAppear or button action)

- [ ] **Step 4: Verify WizardScreenDismissed posts exist for all targetScreens**

```bash
cd /Users/jacksonsweet/Projects/OPS/OPS && grep -rn 'WizardScreenDismissed' OPS/
```

Expected posts for screens: "Settings" (Profile + Organization), "SecuritySettings", "NotificationSettings"

- [ ] **Step 5: Verify trigger exists**

```bash
cd /Users/jacksonsweet/Projects/OPS/OPS && grep -rn 'settings_security' OPS/
```

Expected: Hit in SettingsView.swift (`evaluateTrigger`), WizardStateManager.swift (deep nav), SettingsSecurityWizard.swift (definition)
