# Welcome Tour Wizard Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a permission-responsive feature tour that auto-starts on first app entry, navigating users tab-by-tab through every feature they have access to.

**Architecture:** Dynamic step builder constructs wizard steps based on `PermissionStore` at init time. Uses the existing wizard system for state persistence, analytics, and instruction bar UI. A conditional "NEXT" button in the instruction bar fires a NotificationCenter notification that the existing `observeStepCompletion()` picks up.

**Tech Stack:** Swift, SwiftUI, SwiftData (WizardState model), existing Wizard system infrastructure

**Spec:** `docs/superpowers/specs/2026-03-30-welcome-tour-wizard-design.md`

---

## File Map

| Action | File | Responsibility |
|--------|------|---------------|
| Create | `OPS/OPS/Wizard/Definitions/WelcomeTourWizard.swift` | Wizard definition with dynamic permission-gated step builder |
| Modify | `OPS/OPS/Wizard/Definitions/WizardRegistry.swift` | Register welcome tour in the registry |
| Modify | `OPS/OPS/Wizard/Views/WizardInstructionBar.swift` | Add conditional NEXT / GET STARTED button for welcome tour |
| Modify | `OPS/OPS/Wizard/State/WizardStateManager.swift` | Add `"Pipeline"` to `tabTarget(for:)` mapping |
| Modify | `OPS/OPS/Views/MainTabView.swift` | Add Pipeline case to nav handler + trigger welcome tour on first appear |

---

### Task 1: Create WelcomeTourWizard Definition

**Files:**
- Create: `OPS/OPS/Wizard/Definitions/WelcomeTourWizard.swift`

- [ ] **Step 1: Create the wizard definition file**

```swift
//
//  WelcomeTourWizard.swift
//  OPS
//
//  Permission-responsive feature tour. Steps are built dynamically
//  based on the user's current permissions — different users see
//  different tabs.
//

import Foundation

struct WelcomeTourWizard: WizardDefinitionProtocol {
    let wizardId = "welcome_tour"
    let displayName = "WELCOME TOUR"
    let displayDescription = "A quick look at what you can do."
    let bulletPoints: [String] = []
    let iconName = "hand.wave"
    let triggerType: WizardTriggerType = .sequenced
    let minimumTier: WizardAccessTier = .field
    let requiredPermission: String? = nil
    let bannerText = "Take a quick tour of your workspace."
    let estimatedMinutes = 1

    /// Steps built dynamically based on current permissions.
    /// Order matches MainTabView tab order.
    let steps: [WizardStepDefinition]

    init(permissionStore: PermissionStore = .shared) {
        var built: [WizardStepDefinition] = []

        // Home — always present
        built.append(WizardStepDefinition(
            id: "welcome_home",
            instruction: "YOUR COMMAND CENTER",
            description: "Projects, tasks, and crew — all at a glance.",
            targetScreen: "Home",
            canSkip: false,
            completionNotification: "WelcomeTourAdvance"
        ))

        // Pipeline — gated by pipeline.view
        if permissionStore.can("pipeline.view") {
            built.append(WizardStepDefinition(
                id: "welcome_pipeline",
                instruction: "YOUR PIPELINE",
                description: "Track leads from first contact to closed deal.",
                targetScreen: "Pipeline",
                canSkip: false,
                completionNotification: "WelcomeTourAdvance"
            ))
        }

        // Job Board — always present
        built.append(WizardStepDefinition(
            id: "welcome_job_board",
            instruction: "YOUR JOB BOARD",
            description: "Every active project. Swipe to move work forward.",
            targetScreen: "JobBoard",
            canSkip: false,
            completionNotification: "WelcomeTourAdvance"
        ))

        // Inventory — gated by inventory.view with "all" scope
        if permissionStore.can("inventory.view", requiredScope: "all") {
            built.append(WizardStepDefinition(
                id: "welcome_inventory",
                instruction: "YOUR INVENTORY",
                description: "Your warehouse in your pocket. Track stock and materials.",
                targetScreen: "Inventory",
                canSkip: false,
                completionNotification: "WelcomeTourAdvance"
            ))
        }

        // Schedule — always present
        built.append(WizardStepDefinition(
            id: "welcome_schedule",
            instruction: "YOUR SCHEDULE",
            description: "Your crew's calendar. Who's where, when.",
            targetScreen: "Schedule",
            canSkip: false,
            completionNotification: "WelcomeTourAdvance"
        ))

        // Settings — always present
        built.append(WizardStepDefinition(
            id: "welcome_settings",
            instruction: "YOUR SETTINGS",
            description: "Your company, your crew, your rules.",
            targetScreen: "Settings",
            canSkip: false,
            completionNotification: "WelcomeTourAdvance"
        ))

        self.steps = built
    }
}
```

- [ ] **Step 2: Verify it builds**

Run:
```bash
cd /Users/jacksonsweet/Projects/OPS/OPS && xcodebuild -scheme OPS -destination 'generic/platform=iOS' build 2>&1 | tail -5
```

Expected: BUILD SUCCEEDED (or warnings only — no errors referencing WelcomeTourWizard)

- [ ] **Step 3: Commit**

```bash
cd /Users/jacksonsweet/Projects/OPS/OPS && git add OPS/Wizard/Definitions/WelcomeTourWizard.swift && git commit -m "feat(wizard): add WelcomeTourWizard definition with dynamic permission-gated steps"
```

---

### Task 2: Register in WizardRegistry

**Files:**
- Modify: `OPS/OPS/Wizard/Definitions/WizardRegistry.swift`

- [ ] **Step 1: Add WelcomeTourWizard to the registry**

In `WizardRegistry.swift`, add the welcome tour to the `allWizards` array. It must be instantiated with default `PermissionStore.shared` so step filtering happens at construction time.

Change the `allWizards` property from:

```swift
static let allWizards: [any WizardDefinitionProtocol] = [
    // Sequenced
    ProjectLifecycleWizard(),
    // Contextual
```

To:

```swift
static let allWizards: [any WizardDefinitionProtocol] = [
    // Welcome tour (auto-starts on first app entry)
    WelcomeTourWizard(),
    // Sequenced
    ProjectLifecycleWizard(),
    // Contextual
```

- [ ] **Step 2: Verify it builds**

Run:
```bash
cd /Users/jacksonsweet/Projects/OPS/OPS && xcodebuild -scheme OPS -destination 'generic/platform=iOS' build 2>&1 | tail -5
```

Expected: BUILD SUCCEEDED

- [ ] **Step 3: Commit**

```bash
cd /Users/jacksonsweet/Projects/OPS/OPS && git add OPS/Wizard/Definitions/WizardRegistry.swift && git commit -m "feat(wizard): register WelcomeTourWizard in WizardRegistry"
```

---

### Task 3: Add Pipeline to Tab Navigation Mapping

**Files:**
- Modify: `OPS/OPS/Wizard/State/WizardStateManager.swift` (line ~690, `tabTarget(for:)` method)
- Modify: `OPS/OPS/Views/MainTabView.swift` (line ~401, `WizardNavigateToTarget` handler)

- [ ] **Step 1: Add Pipeline case to `tabTarget(for:)` in WizardStateManager**

In `WizardStateManager.swift`, find the `tabTarget(for:)` static method (around line 690). Add `"Pipeline"` to the switch:

Change:

```swift
static func tabTarget(for targetScreen: String) -> String? {
    switch targetScreen {
    // Home tab
    case "Home":
        return "Home"
    // Job Board tab
    case "JobBoard", "FABMenu", "ProjectForm", "ClientForm", "TaskForm":
        return "JobBoard"
```

To:

```swift
static func tabTarget(for targetScreen: String) -> String? {
    switch targetScreen {
    // Home tab
    case "Home":
        return "Home"
    // Pipeline tab
    case "Pipeline":
        return "Pipeline"
    // Job Board tab
    case "JobBoard", "FABMenu", "ProjectForm", "ClientForm", "TaskForm":
        return "JobBoard"
```

- [ ] **Step 2: Add Pipeline case to MainTabView's WizardNavigateToTarget handler**

In `MainTabView.swift`, find the `.onReceive(WizardNavigateToTarget)` handler (around line 401). Add the Pipeline case:

Change:

```swift
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("WizardNavigateToTarget"))) { notification in
            guard let tabTarget = notification.userInfo?["tabTarget"] as? String else { return }
            switch tabTarget {
            case "Home":
                withAnimation { selectedTab = 0 }
            case "JobBoard":
                withAnimation { selectedTab = jobBoardTabIndex }
            case "Schedule":
```

To:

```swift
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("WizardNavigateToTarget"))) { notification in
            guard let tabTarget = notification.userInfo?["tabTarget"] as? String else { return }
            switch tabTarget {
            case "Home":
                withAnimation { selectedTab = 0 }
            case "Pipeline":
                if let idx = pipelineTabIndex {
                    withAnimation { selectedTab = idx }
                }
            case "JobBoard":
                withAnimation { selectedTab = jobBoardTabIndex }
            case "Schedule":
```

- [ ] **Step 3: Verify it builds**

Run:
```bash
cd /Users/jacksonsweet/Projects/OPS/OPS && xcodebuild -scheme OPS -destination 'generic/platform=iOS' build 2>&1 | tail -5
```

Expected: BUILD SUCCEEDED

- [ ] **Step 4: Commit**

```bash
cd /Users/jacksonsweet/Projects/OPS/OPS && git add OPS/Wizard/State/WizardStateManager.swift OPS/Views/MainTabView.swift && git commit -m "feat(wizard): add Pipeline to tab navigation mapping for wizard system"
```

---

### Task 4: Add NEXT Button to WizardInstructionBar

**Files:**
- Modify: `OPS/OPS/Wizard/Views/WizardInstructionBar.swift`

The existing instruction bar has SKIP and EXIT buttons. Welcome tour steps need a NEXT button (and GET STARTED on the final step). This button posts the `"WelcomeTourAdvance"` notification that `observeStepCompletion()` picks up.

- [ ] **Step 1: Add the NEXT / GET STARTED button**

In `WizardInstructionBar.swift`, find the action buttons `HStack` inside the active (non-paused) branch (around line 87). Add the NEXT button before the Spacer, between the SKIP block and `Spacer()`:

Change:

```swift
                    // Action buttons
                    HStack(spacing: 12) {
                        // Skip button
                        if let step = stateManager.currentStep, step.canSkip {
                            Button {
                                TutorialHaptics.lightTap()
                                stateManager.skipCurrentStep()
                            } label: {
                                Text("SKIP")
                                    .font(OPSStyle.Typography.captionBold)
                                    .foregroundColor(OPSStyle.Colors.secondaryText)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 8)
                                    .background(OPSStyle.Colors.background.opacity(0.5))
                                    .cornerRadius(OPSStyle.Layout.smallCornerRadius)
                            }
                        }

                        Spacer()
```

To:

```swift
                    // Action buttons
                    HStack(spacing: 12) {
                        // Skip button (hidden for welcome tour — NEXT replaces it)
                        if let step = stateManager.currentStep, step.canSkip {
                            Button {
                                TutorialHaptics.lightTap()
                                stateManager.skipCurrentStep()
                            } label: {
                                Text("SKIP")
                                    .font(OPSStyle.Typography.captionBold)
                                    .foregroundColor(OPSStyle.Colors.secondaryText)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 8)
                                    .background(OPSStyle.Colors.background.opacity(0.5))
                                    .cornerRadius(OPSStyle.Layout.smallCornerRadius)
                            }
                        }

                        // NEXT button for welcome tour (informational steps)
                        if stateManager.activeWizard?.wizardId == "welcome_tour" {
                            let isLastStep = stateManager.currentStepIndex >= stateManager.totalSteps - 1
                            Button {
                                TutorialHaptics.mediumTap()
                                NotificationCenter.default.post(
                                    name: Notification.Name("WelcomeTourAdvance"),
                                    object: nil
                                )
                            } label: {
                                Text(isLastStep ? "GET STARTED" : "NEXT")
                                    .font(OPSStyle.Typography.captionBold)
                                    .foregroundColor(OPSStyle.Colors.invertedText)
                                    .tracking(1.2)
                                    .padding(.horizontal, 20)
                                    .padding(.vertical, 8)
                                    .background(OPSStyle.Colors.wizardAccent)
                                    .cornerRadius(OPSStyle.Layout.smallCornerRadius)
                            }
                        }

                        Spacer()
```

- [ ] **Step 2: Verify it builds**

Run:
```bash
cd /Users/jacksonsweet/Projects/OPS/OPS && xcodebuild -scheme OPS -destination 'generic/platform=iOS' build 2>&1 | tail -5
```

Expected: BUILD SUCCEEDED

- [ ] **Step 3: Commit**

```bash
cd /Users/jacksonsweet/Projects/OPS/OPS && git add OPS/Wizard/Views/WizardInstructionBar.swift && git commit -m "feat(wizard): add NEXT/GET STARTED button to instruction bar for welcome tour"
```

---

### Task 5: Trigger Welcome Tour on First MainTabView Appear

**Files:**
- Modify: `OPS/OPS/Views/MainTabView.swift`

The welcome tour auto-starts via `startWizardDirectly()` on first MainTabView appear, before other wizard evaluations. It fires only when the wizard state for `"welcome_tour"` is `.notStarted`.

- [ ] **Step 1: Add welcome tour trigger to evaluateWizardTriggers**

In `MainTabView.swift`, find the `evaluateWizardTriggers()` method (around line 529). Add the welcome tour check **before** the sequenced wizard evaluation:

Change:

```swift
    private func evaluateWizardTriggers() {
        guard let triggerService = wizardTriggerService else { return }
        guard let modelContext = dataController.modelContext else { return }

        let companyId = dataController.currentUser?.companyId ?? ""

        // Count projects for the current user's company
        var projectDescriptor = FetchDescriptor<Project>(
```

To:

```swift
    private func evaluateWizardTriggers() {
        guard let triggerService = wizardTriggerService else { return }
        guard let modelContext = dataController.modelContext else { return }

        // Welcome tour: auto-start on first app entry (before other wizards)
        if let stateManager = wizardStateManager {
            let welcomeWizard = WelcomeTourWizard(permissionStore: permissionStore)
            if welcomeWizard.steps.count > 0,
               let state = stateManager.wizardState(for: "welcome_tour"),
               state.status == .notStarted {
                stateManager.startWizardDirectly(welcomeWizard)
                return // Don't evaluate other wizards — welcome tour takes priority
            }
        }

        let companyId = dataController.currentUser?.companyId ?? ""

        // Count projects for the current user's company
        var projectDescriptor = FetchDescriptor<Project>(
```

- [ ] **Step 2: Verify it builds**

Run:
```bash
cd /Users/jacksonsweet/Projects/OPS/OPS && xcodebuild -scheme OPS -destination 'generic/platform=iOS' build 2>&1 | tail -5
```

Expected: BUILD SUCCEEDED

- [ ] **Step 3: Commit**

```bash
cd /Users/jacksonsweet/Projects/OPS/OPS && git add OPS/Views/MainTabView.swift && git commit -m "feat(wizard): trigger welcome tour on first MainTabView appear"
```

---

### Task 6: Verify Full Build and Test on Device

- [ ] **Step 1: Full clean build**

Run:
```bash
cd /Users/jacksonsweet/Projects/OPS/OPS && xcodebuild -scheme OPS -destination 'generic/platform=iOS' clean build 2>&1 | tail -10
```

Expected: BUILD SUCCEEDED

- [ ] **Step 2: Verify no warnings related to wizard files**

Run:
```bash
cd /Users/jacksonsweet/Projects/OPS/OPS && xcodebuild -scheme OPS -destination 'generic/platform=iOS' build 2>&1 | grep -i "warning.*wizard\|warning.*WelcomeTour" || echo "No wizard warnings"
```

Expected: "No wizard warnings"

- [ ] **Step 3: Commit all remaining changes (if any)**

```bash
cd /Users/jacksonsweet/Projects/OPS/OPS && git status
```

If clean: done. If uncommitted changes remain, stage and commit.
