# Phase 4: Settings Integration & Reliability

**Priority**: P2
**Estimated Effort**: 2-3 hours
**Dependencies**: None (can be done in parallel with other phases)
**Status**: Not Started

---

## Objective

1. Integrate the unused notification settings controls (DND, Priority, Mute)
2. Add proper error handling throughout NotificationManager
3. Fix async/await issues

---

## Part A: Integrate Unused Settings Controls

### Current State

`NotificationSettingsControls.swift` contains three components that are built but never used:
- `NotificationTimeWindow` - Quiet hours selector
- `NotificationPrioritySelector` - All/Important/Critical filter
- `TemporaryMuteControl` - Mute for N hours

---

## Task 4.1: Add Do Not Disturb Section to Settings

### File to Modify
`/Users/jacksonsweet/Desktop/OPS LTD./OPS/OPS/Views/Settings/NotificationSettingsView.swift`

### Add @AppStorage Properties

```swift
@AppStorage("quietHoursEnabled") private var quietHoursEnabled = false
@AppStorage("quietHoursStart") private var quietHoursStart = 22  // 10 PM
@AppStorage("quietHoursEnd") private var quietHoursEnd = 7       // 7 AM
```

### Add UI Section

After the existing sections, add:

```swift
// MARK: - Do Not Disturb Section
SectionCard {
    VStack(alignment: .leading, spacing: 16) {
        // Section header
        HStack {
            Image(systemName: OPSStyle.Icons.moon)
                .foregroundColor(OPSStyle.Colors.secondaryText)
            Text("DO NOT DISTURB")
                .font(OPSStyle.Typography.captionBold)
                .foregroundColor(OPSStyle.Colors.secondaryText)
        }

        // Enable toggle
        SettingsToggle(
            title: "Quiet Hours",
            description: "Silence notifications during set hours",
            isOn: $quietHoursEnabled
        )

        // Time window (only show if enabled)
        if quietHoursEnabled {
            NotificationTimeWindow(
                startHour: $quietHoursStart,
                endHour: $quietHoursEnd
            )
            .padding(.leading, 8)
        }
    }
}
```

---

## Task 4.2: Add Notification Priority Section

### Add @AppStorage Property

```swift
@AppStorage("notificationPriority") private var notificationPriority = "all"
```

### Add UI Section

```swift
// MARK: - Notification Priority Section
SectionCard {
    VStack(alignment: .leading, spacing: 16) {
        HStack {
            Image(systemName: OPSStyle.Icons.bell)
                .foregroundColor(OPSStyle.Colors.secondaryText)
            Text("NOTIFICATION FILTER")
                .font(OPSStyle.Typography.captionBold)
                .foregroundColor(OPSStyle.Colors.secondaryText)
        }

        NotificationPrioritySelector(
            selectedPriority: Binding(
                get: { NotificationPriority(rawValue: notificationPriority) ?? .all },
                set: { notificationPriority = $0.rawValue }
            )
        )
    }
}
```

---

## Task 4.3: Add Temporary Mute Section

### Add @AppStorage Properties

```swift
@AppStorage("isMuted") private var isMuted = false
@AppStorage("muteUntil") private var muteUntil: Double = 0  // Timestamp
```

### Add UI Section

```swift
// MARK: - Temporary Mute Section
SectionCard {
    VStack(alignment: .leading, spacing: 16) {
        HStack {
            Image(systemName: OPSStyle.Icons.bellSlash)
                .foregroundColor(OPSStyle.Colors.secondaryText)
            Text("TEMPORARY MUTE")
                .font(OPSStyle.Typography.captionBold)
                .foregroundColor(OPSStyle.Colors.secondaryText)
        }

        TemporaryMuteControl(
            isMuted: $isMuted,
            muteHours: .constant(1)  // Will need to derive from muteUntil
        )

        // Show mute status
        if isMuted && muteUntil > Date().timeIntervalSince1970 {
            let endDate = Date(timeIntervalSince1970: muteUntil)
            Text("Muted until \(endDate.formatted(date: .omitted, time: .shortened))")
                .font(OPSStyle.Typography.caption)
                .foregroundColor(OPSStyle.Colors.warning)
        }
    }
}
```

---

## Task 4.4: Implement shouldSendNotification() Check

### File to Modify
`/Users/jacksonsweet/Desktop/OPS LTD./OPS/OPS/Utilities/NotificationManager.swift`

### Add Method

```swift
/// Check if notifications should be sent based on user settings
func shouldSendNotification(priority: NotificationPriority = .normal) -> Bool {
    // Check temporary mute
    let isMuted = UserDefaults.standard.bool(forKey: "isMuted")
    let muteUntil = UserDefaults.standard.double(forKey: "muteUntil")
    if isMuted && muteUntil > Date().timeIntervalSince1970 {
        print("[NOTIFICATIONS] Muted until \(Date(timeIntervalSince1970: muteUntil))")
        return false
    }

    // Check quiet hours
    let quietHoursEnabled = UserDefaults.standard.bool(forKey: "quietHoursEnabled")
    if quietHoursEnabled {
        let quietStart = UserDefaults.standard.integer(forKey: "quietHoursStart")
        let quietEnd = UserDefaults.standard.integer(forKey: "quietHoursEnd")
        let currentHour = Calendar.current.component(.hour, from: Date())

        let isInQuietHours: Bool
        if quietStart > quietEnd {
            // Quiet hours span midnight (e.g., 22:00 - 07:00)
            isInQuietHours = currentHour >= quietStart || currentHour < quietEnd
        } else {
            // Quiet hours within same day
            isInQuietHours = currentHour >= quietStart && currentHour < quietEnd
        }

        if isInQuietHours {
            print("[NOTIFICATIONS] Currently in quiet hours (\(quietStart):00 - \(quietEnd):00)")
            return false
        }
    }

    // Check priority filter
    let priorityFilter = UserDefaults.standard.string(forKey: "notificationPriority") ?? "all"
    switch priorityFilter {
    case "important":
        if priority == .normal {
            print("[NOTIFICATIONS] Filtered: only important notifications enabled")
            return false
        }
    case "critical":
        if priority != .critical {
            print("[NOTIFICATIONS] Filtered: only critical notifications enabled")
            return false
        }
    default:
        break  // "all" - send everything
    }

    return true
}

/// Notification priority levels
enum NotificationPriority: String {
    case normal = "normal"
    case important = "important"
    case critical = "critical"
}
```

### Update Notification Scheduling Methods

Add `shouldSendNotification()` check to each scheduling method:

```swift
func scheduleProjectAssignmentNotification(projectId: String, projectName: String) {
    // Check if we should send this notification
    guard shouldSendNotification(priority: .important) else { return }

    // ... existing scheduling code ...
}

func scheduleProjectUpdateNotification(projectId: String, projectName: String, changeDescription: String) {
    guard shouldSendNotification(priority: .normal) else { return }
    // ... existing scheduling code ...
}

func scheduleProjectCompletionNotification(projectId: String, projectName: String) {
    guard shouldSendNotification(priority: .normal) else { return }
    // ... existing scheduling code ...
}

func scheduleProjectAdvanceNotice(project: Project, daysBefore: Int) {
    guard shouldSendNotification(priority: .important) else { return }
    // ... existing scheduling code ...
}
```

---

## Part B: Error Handling

## Task 4.5: Replace Empty Catch Blocks

### File to Modify
`/Users/jacksonsweet/Desktop/OPS LTD./OPS/OPS/Utilities/NotificationManager.swift`

### Find and Replace Pattern

**Find all instances of:**
```swift
} catch {
    // Empty or just print
}
```

**Replace with:**
```swift
} catch {
    print("[NOTIFICATIONS] Error: \(error.localizedDescription)")
    // Optionally track in analytics
    #if DEBUG
    assertionFailure("Notification error: \(error)")
    #endif
}
```

### Specific Locations to Check

Based on audit, empty catch blocks exist around:
- Line ~265-267
- Line ~308-310
- Line ~366-368
- Line ~866

### Add Error Enum

```swift
enum NotificationError: Error, LocalizedError {
    case permissionDenied
    case schedulingFailed(String)
    case tokenSyncFailed(Error)
    case invalidDate

    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "Notification permissions not granted"
        case .schedulingFailed(let reason):
            return "Failed to schedule notification: \(reason)"
        case .tokenSyncFailed(let error):
            return "Failed to sync device token: \(error.localizedDescription)"
        case .invalidDate:
            return "Invalid date for notification"
        }
    }
}
```

---

## Part C: Fix Async/Await Issues

## Task 4.6: Fix Unawaited Async Calls

### Issue 1: getPendingNotificationRequests() not awaited

**Find (around line 382, 899):**
```swift
UNUserNotificationCenter.current().getPendingNotificationRequests { requests in
    // ...
}
```

**Replace with async version:**
```swift
let requests = await UNUserNotificationCenter.current().pendingNotificationRequests()
// Process requests...
```

### Issue 2: Double DispatchQueue.main.async

**Find (around line 198-199):**
```swift
DispatchQueue.main.async {
    DispatchQueue.main.async {
        // ...
    }
}
```

**Replace with single dispatch:**
```swift
DispatchQueue.main.async {
    // ...
}
```

Or better, use `@MainActor`:
```swift
@MainActor
func updateUI() {
    // ...
}
```

---

## Verification Checklist

### Settings Integration
- [ ] `quietHoursEnabled`, `quietHoursStart`, `quietHoursEnd` @AppStorage added
- [ ] `notificationPriority` @AppStorage added
- [ ] `isMuted`, `muteUntil` @AppStorage added
- [ ] Do Not Disturb section added to NotificationSettingsView
- [ ] Priority section added to NotificationSettingsView
- [ ] Temporary Mute section added to NotificationSettingsView
- [ ] `shouldSendNotification()` method implemented
- [ ] All scheduling methods check `shouldSendNotification()` first

### Error Handling
- [ ] All empty catch blocks replaced with logging
- [ ] NotificationError enum created
- [ ] Errors are trackable for debugging

### Async/Await
- [ ] `getPendingNotificationRequests` properly awaited
- [ ] No double DispatchQueue.main.async calls
- [ ] Methods that need main thread use @MainActor

### Testing
- [ ] Test: Quiet hours prevents notifications during set time
- [ ] Test: Temporary mute prevents all notifications
- [ ] Test: Priority filter works correctly
- [ ] Test: Settings persist after app restart
- [ ] Test: Error logging works in debug builds

---

## Next Phase

After Phase 4 is complete:
- `PHASE_5_BATCHING.md` - Notification batching system
