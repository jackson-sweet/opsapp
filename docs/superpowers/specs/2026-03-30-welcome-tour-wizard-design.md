# Welcome Tour Wizard — Design Spec

## Overview

A permission-responsive feature tour that fires once when a user first enters the main app after onboarding. Navigates the user tab-by-tab through every feature they have access to, using the existing wizard system's UI and state management.

## Decision: Dynamic Step Builder (Approach 2)

Steps are built dynamically at `WelcomeTourWizard` construction time based on `PermissionStore`. No changes to core wizard types (`WizardStepDefinition`, `WizardDefinitionProtocol`, `WizardStateManager`). When permissions change (e.g., pipeline feature flag enabled), the next time the wizard would be shown it builds with the updated steps. Since this is a one-time tour (completed/dismissed persisted), the primary scenario for permission reactivity is: different users with different roles see different steps.

## Trigger & Lifecycle

- **When:** First `MainTabView` appear when wizard state for `"welcome_tour"` is `.notStarted`
- **Auto-start:** Calls `startWizardDirectly()` — bypasses banner/prompt overlay, goes straight into instruction bar
- **Prerequisite:** Tutorial must be complete (`hasCompletedAppTutorial`) and user must be authenticated
- **Persistence:** Uses existing `WizardStateManager` state tracking (`.completed` / `.dismissed`)
- **No new UserDefaults keys** — wizard system handles it

## Steps

Each step maps to a MainTabView tab. Steps are only included if the user's permissions allow access at construction time.

| Order | Step ID | Tab | targetScreen | Instruction (directional — refine with ops-copywriter) | Permission Gate |
|-------|---------|-----|-------------|-------------------------------------------------------|-----------------|
| 1 | `welcome_home` | Home | `"Home"` | Your command center. Projects, tasks, and crew at a glance. | None (always) |
| 2 | `welcome_pipeline` | Pipeline | `"Pipeline"` | Track leads from first contact to closed deal. | `pipeline.view` |
| 3 | `welcome_job_board` | Job Board | `"JobBoard"` | Every active project. Swipe to move work forward. | None (always) |
| 4 | `welcome_inventory` | Inventory | `"Inventory"` | Your warehouse in your pocket. Track stock and materials. | `inventory.view` (scope: `"all"`) |
| 5 | `welcome_schedule` | Schedule | `"Schedule"` | Your crew's calendar. Who's where, when. | None (always) |
| 6 | `welcome_settings` | Settings | `"Settings"` | Your company, your crew, your rules. | None (always) |

Step order matches tab order in MainTabView (which is also permission-responsive).

**`targetScreen` values** use the existing identifiers from `WizardStateManager.tabTarget(for:)` mapping, with one addition: `"Pipeline"` needs to be added to that mapping.

## Tab Navigation

Navigation already works via the existing `WizardNavigateToTarget` NotificationCenter mechanism:
- `WizardStateManager.navigateToCurrentStep()` posts `"WizardNavigateToTarget"` with `tabTarget`
- `MainTabView` already handles `"Home"`, `"JobBoard"`, `"Schedule"`, `"Inventory"`, `"Settings"`
- **Must add:** `"Pipeline"` case to both:
  1. `WizardStateManager.tabTarget(for:)` — map `"Pipeline"` → `"Pipeline"`
  2. `MainTabView`'s `.onReceive(WizardNavigateToTarget)` — add `case "Pipeline": selectedTab = pipelineTabIndex`

## Step Advancement

**Problem:** The existing instruction bar has SKIP and EXIT buttons but no "NEXT" button. Existing wizards advance via `completionNotification` (the app fires a NotificationCenter notification when the user performs an action). Welcome tour steps are informational — no action to perform.

**Solution:** Each step sets `completionNotification: "WelcomeTourAdvance"`. A "NEXT" button is added to the `WizardInstructionBar` that appears **only when the active wizard is the welcome tour** (checked via `stateManager.activeWizard?.wizardId == "welcome_tour"`). Tapping it posts the `"WelcomeTourAdvance"` notification, which the existing `observeStepCompletion()` picks up and calls `completeCurrentStep()`.

On the **final step**, the button text changes to "GET STARTED" instead of "NEXT".

This keeps the core wizard types and state manager untouched — the only UI change is a conditional button in the instruction bar.

**All steps set `canSkip: false`** since the NEXT button replaces skip functionality. EXIT remains available to dismiss the entire tour.

## Protocol Conformance

`WelcomeTourWizard` must conform to `WizardDefinitionProtocol`, which requires:

```
wizardId: String              → "welcome_tour"
displayName: String           → "WELCOME TOUR"
displayDescription: String    → "A quick look at what you can do."
bulletPoints: [String]        → [] (not shown — no prompt overlay)
iconName: String              → "hand.wave" (or similar)
triggerType: WizardTriggerType → .sequenced
minimumTier: WizardAccessTier  → .field (all users)
requiredPermission: String?   → nil (all users)
bannerText: String            → "" (not shown — auto-starts)
estimatedMinutes: Int         → 1
steps: [WizardStepDefinition] → built dynamically (see above)
```

## Files to Create/Modify

### New Files
- `OPS/Wizard/Definitions/WelcomeTourWizard.swift` — wizard definition with dynamic step builder

### Modified Files
- `OPS/Wizard/Definitions/WizardRegistry.swift` — register the welcome tour
- `OPS/Wizard/Views/WizardInstructionBar.swift` — add conditional "NEXT" / "GET STARTED" button when `activeWizard?.wizardId == "welcome_tour"`
- `OPS/Wizard/State/WizardStateManager.swift` — add `"Pipeline"` to `tabTarget(for:)` mapping
- `OPS/Views/MainTabView.swift` — add Pipeline case to `WizardNavigateToTarget` handler, trigger welcome tour on first appear via `startWizardDirectly()`

## Edge Cases

- **User dismisses mid-tour:** Marked `.dismissed` via existing `exitWizard()`, never shown again
- **User has only 4 tabs (no pipeline, no inventory):** Steps 2 and 4 excluded at construction, tour shows 4 steps
- **User has all 6 tabs:** Full 6-step tour
- **Permissions change after tour completed:** No effect — tour is one-time
- **App killed mid-tour:** Wizard state manager persists current step index; resumes on next launch
- **Wizard system disabled:** Tour does not fire (existing `stateManager.isEnabled` gate)
- **Another wizard already active:** `startWizardDirectly` is guarded — won't interrupt

## Out of Scope

- No custom overlay/spotlight — uses existing wizard instruction bar
- No tutorial V2 integration
- No analytics beyond existing `WizardAnalyticsService` tracking (which fires automatically)
