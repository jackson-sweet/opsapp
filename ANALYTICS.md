# OPS Analytics & Conversion Tracking

This document details the Firebase Analytics implementation for tracking user behavior and Google Ads conversion events.

## Overview

OPS uses Firebase Analytics to track:
- User acquisition and authentication events
- Screen/page views and navigation patterns
- CRUD operations (create, read, update, delete)
- Status changes and workflow progression
- Subscription and revenue events

All analytics are centralized through `AnalyticsManager.swift`.

## Firebase Configuration

- **SDK Version**: 12.6.0+ (Swift Package Manager)
- **Project ID**: `ops-ios-app`
- **Bundle ID**: `co.opsapp.ops.OPS`
- **Config File**: `GoogleService-Info.plist`
- **Google Ads Integration**: Enabled (`IS_ADS_ENABLED: true`)

Firebase is initialized in `AppDelegate.swift` as the first step in `didFinishLaunchingWithOptions`.

---

## Events Reference

### Authentication Events

| Event | Parameters | Description | Location |
|-------|------------|-------------|----------|
| `sign_up` | `method` (email/apple/google), `user_type` | New user account creation | OnboardingViewModel, DataController |
| `login` | `method`, `user_type` | Returning user login | DataController |

### Onboarding & Trial Events

| Event | Parameters | Description | Location |
|-------|------------|-------------|----------|
| `complete_onboarding` | `user_type`, `has_company` | User completes onboarding flow | OnboardingViewModel |
| `begin_trial` | `user_type`, `trial_days` (default: 30) | Company owner starts trial | OnboardingViewModel |

### Subscription & Revenue Events

| Event | Parameters | Description | Location |
|-------|------------|-------------|----------|
| `purchase` | `item_name`, `price`, `currency`, `user_type` | Subscription purchase (Firebase standard) | SubscriptionManager |
| `subscribe` | `item_name`, `price`, `currency`, `user_type` | Custom subscription event | SubscriptionManager |

### Screen View Events

| Event | Parameters | Description | Location |
|-------|------------|-------------|----------|
| `screen_view` | `screen_name`, `screen_class` | Screen/page viewed | All main views |
| `tab_selected` | `tab_name`, `tab_index` | Tab bar navigation | MainTabView |

**Screen Names Tracked:**
- Main tabs: `home`, `job_board`, `schedule`, `settings`
- Job Board sections: `job_board_dashboard`, `job_board_projects`, `job_board_tasks`, `job_board_clients`
- Detail views: `project_details`, `task_details`, `client_details`
- Forms: `project_form`, `task_form`, `client_form`
- Settings: `profile_settings`, `organization_settings`, `notification_settings`, `app_settings`, `manage_team`, `manage_subscription`
- Subscription: `plan_selection`, `subscription_lockout`
- Auth: `login`, `forgot_password`

### Project Events

| Event | Parameters | Description | Location |
|-------|------------|-------------|----------|
| `create_project` | `project_count`, `user_type` | Project created | ContentView |
| `create_first_project` | `user_type` | First project (high-intent conversion) | AnalyticsManager (auto-triggered) |
| `project_edited` | `project_id` | Project updated | ProjectFormSheet |
| `project_deleted` | - | Project deleted | ProjectDetailsView |
| `project_status_changed` | `old_status`, `new_status` | Status transition | DataController |

### Task Events

| Event | Parameters | Description | Location |
|-------|------------|-------------|----------|
| `task_created` | `task_type`, `has_schedule`, `team_size` | Task created | TaskFormSheet |
| `task_edited` | `task_id` | Task updated | TaskFormSheet |
| `task_deleted` | - | Task deleted | TaskDetailsView |
| `task_status_changed` | `old_status`, `new_status` | Status transition | DataController |
| `task_completed` | `task_type` | Task marked complete (high-value) | DataController |

### Client Events

| Event | Parameters | Description | Location |
|-------|------------|-------------|----------|
| `client_created` | `has_email`, `has_phone`, `has_address`, `import_method` | Client created | ClientSheet |
| `client_edited` | `client_id` | Client updated | ClientSheet |
| `client_deleted` | - | Client deleted | ClientListView |

### Team Member Events

| Event | Parameters | Description | Location |
|-------|------------|-------------|----------|
| `team_member_invited` | `role`, `team_size` | New team member invited | ManageTeamView |
| `team_member_removed` | - | Team member deleted | ManageTeamView |
| `team_member_role_changed` | `old_role`, `new_role` | Role/permission changed | TeamRoleManagementView |

### Engagement Events

| Event | Parameters | Description | Location |
|-------|------------|-------------|----------|
| `navigation_started` | `project_id` | User starts navigation to project | HomeView |
| `search_performed` | `section`, `results_count` | Search executed | Various search components |
| `filter_applied` | `section`, `filter_type` | Filter applied | Filter sheets |
| `image_uploaded` | `image_count`, `context` | Photo uploaded | ProjectFormSheet, ClientSheet |
| `form_abandoned` | `form_type`, `fields_filled` | Form closed without saving | Form sheets |

### Calendar Events

| Event | Parameters | Description | Location |
|-------|------------|-------------|----------|
| `calendar_view_mode_changed` | `view_mode` (month/week) | Calendar view toggled | ScheduleView |
| `calendar_day_selected` | `events_count` | Day selected in calendar | ScheduleView |

---

## User Properties

| Property | Values | Description |
|----------|--------|-------------|
| `user_type` | `company`, `employee` | User account type |
| `subscription_status` | `subscribed`, `free` | Subscription state |

User ID is set via `Analytics.setUserID()` during authentication.

---

## Google Ads Conversion Events

These events are automatically sent to Google Ads through the Firebase-Google Ads integration:

1. **`sign_up`** - Primary acquisition conversion
2. **`purchase`** - Revenue/subscription conversion
3. **`create_first_project`** - High-intent engagement signal
4. **`complete_onboarding`** - Onboarding completion
5. **`task_completed`** - Productivity/engagement signal

---

## Implementation Details

### Adding a New Event

1. Add the tracking method to `AnalyticsManager.swift`:
```swift
func trackNewEvent(param1: String, param2: Int) {
    let parameters: [String: Any] = [
        "param1": param1,
        "param2": param2
    ]
    Analytics.logEvent("new_event", parameters: parameters)
    print("[ANALYTICS] Tracked new_event - param1: \(param1), param2: \(param2)")
}
```

2. Call the method from the appropriate location:
```swift
AnalyticsManager.shared.trackNewEvent(param1: "value", param2: 42)
```

### Adding a New Screen

1. Add the screen name to `ScreenName` enum in `AnalyticsManager.swift`:
```swift
enum ScreenName: String {
    // ... existing cases
    case newScreen = "new_screen"
}
```

2. Add tracking in the view's `onAppear`:
```swift
.onAppear {
    AnalyticsManager.shared.trackScreenView(screenName: .newScreen, screenClass: "NewScreenView")
}
```

---

## Files Reference

| File | Purpose |
|------|---------|
| `OPS/Utilities/AnalyticsManager.swift` | Centralized analytics singleton |
| `OPS/GoogleService-Info.plist` | Firebase configuration |
| `OPS/AppDelegate.swift` | Firebase initialization |

---

## Console Logging

All analytics events log to console with the `[ANALYTICS]` prefix for debugging:
```
[ANALYTICS] Tracked screen_view - screen: home
[ANALYTICS] Tracked task_created - type: Installation, hasSchedule: true, teamSize: 2
[ANALYTICS] Tracked project_status_changed - from: accepted to: inProgress
```

---

## Best Practices

1. **Always use AnalyticsManager** - Don't call `Analytics.logEvent()` directly
2. **Use snake_case** for event names and parameters
3. **Include context** - Add relevant parameters (IDs, counts, types)
4. **Track success, not attempts** - Log events after successful operations
5. **Respect privacy** - Don't log PII (names, emails) in events
6. **Log to console** - Include print statements for debugging
