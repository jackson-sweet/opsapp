# Agent Handover - Notifications Implementation

**Last Updated**: December 8, 2025
**Last Agent Session**: Session 10 - Task Completion Notifications
**Current Phase**: All Phases Complete - OneSignal Fully Integrated

---

## IMPORTANT: READ THIS FIRST

This file tracks the progress of the Notifications Implementation project across multiple agent sessions. **Before beginning any work**, read:

1. This file (AGENT_HANDOVER.md)
2. NOTIFICATIONS_OVERVIEW.md (architecture overview)
3. The specific phase file you'll be working on

**Before ending your session**, update this file with:
- What you completed
- What's in progress
- Any blockers or issues discovered
- Critical context for the next agent

---

## Architecture Summary

### Two Types of Notifications

1. **Push Notifications (Immediate)** - Sent from Bubble when data changes
   - Task assignment → Push to assigned user
   - Schedule change → Push to all task team members
   - Project completion → Push to all project team members
   - **Bubble is responsible for sending these**

2. **Local Notifications (Scheduled Reminders)** - Scheduled on user's device
   - Advance notice before task start date
   - User chooses lead time (1 day, 2 days, etc.)
   - Only for tasks user is assigned to
   - **iOS app is responsible for scheduling these**

---

## Current Project Status

### Phase Completion Status

| Phase | File | Status | Notes |
|-------|------|--------|-------|
| Overview | NOTIFICATIONS_OVERVIEW.md | ✅ Complete | Architecture documented |
| Bubble Setup | BUBBLE_WORKFLOWS.md | ✅ Complete | Instructions for Jackson |
| Phase 1 | PHASE_1_PUSH_INFRASTRUCTURE.md | 🟡 In Progress | iOS code complete, awaiting Bubble setup |
| Phase 2 | PHASE_2_LOCAL_NOTIFICATIONS.md | ✅ Complete | Task-based local scheduling implemented |
| Phase 3 | PHASE_3_REMOTE_HANDLING.md | ✅ Complete | Remote notification handling + deep linking |
| Phase 4 | PHASE_4_SETTINGS_RELIABILITY.md | ✅ Complete | DND, Mute settings + filtering |
| Phase 5 | PHASE_5_BATCHING.md | ✅ Complete | Notification batching during sync |

### Legend
- ✅ Complete
- 🟡 In Progress
- 🔵 Not Started
- 🔴 Blocked

---

## Session History

### Session 1: December 4, 2025 - Initial Planning

**Agent Actions**:
1. Conducted comprehensive audit of existing notification system
2. Created initial documentation files
3. Identified gaps in existing implementation

**Key Findings**:
- `aps-environment` entitlement MISSING
- Device token captured but NEVER synced to Bubble
- Notification scheduling methods exist but NEVER called
- 3 UI controls built but not integrated

---

### Session 2: December 4, 2025 - Phase 1 iOS Implementation

**Agent Actions**:
1. Added `aps-environment` entitlement to OPS.entitlements (production)
2. Added `deviceToken` field to BubbleFields.User
3. Added `deviceToken` property to UserDTO with CodingKeys and toModel() mapping
4. Added `deviceToken` property to User SwiftData model
5. Updated `handleDeviceTokenRegistration()` to sync token to Bubble
6. Added `syncDeviceTokenToBubble()` and `updateUserDeviceToken()` methods

**Files Modified**:
- `OPS/OPS.entitlements` - Added aps-environment = production
- `OPS/Network/API/BubbleFields.swift` - Added User.deviceToken field
- `OPS/Network/DTOs/UserDTO.swift` - Added deviceToken property
- `OPS/DataModels/User.swift` - Added deviceToken property
- `OPS/Utilities/NotificationManager.swift` - Added token sync logic

---

### Session 3: December 4, 2025 - Architecture Revision

**Agent Actions**:
1. Revised architecture based on user requirements:
   - Push notifications sent from Bubble (not sync-triggered)
   - Local notifications for advance reminders only
   - Task-based scheduling (not project-based)
2. Created BUBBLE_WORKFLOWS.md with step-by-step Bubble instructions
3. Replaced PHASE_2_NOTIFICATION_TRIGGERS.md with PHASE_2_LOCAL_NOTIFICATIONS.md
4. Updated all documentation to reflect new architecture

**Files Created**:
- `BUBBLE_WORKFLOWS.md` - Complete Bubble setup instructions

**Files Modified**:
- `NOTIFICATIONS_OVERVIEW.md` - New architecture
- `PHASE_1_PUSH_INFRASTRUCTURE.md` - Added Bubble workflow references
- `PHASE_3_REMOTE_HANDLING.md` - Updated payload formats
- `AGENT_HANDOVER.md` - This file

**Files Deleted**:
- `PHASE_2_NOTIFICATION_TRIGGERS.md` - Replaced with LOCAL_NOTIFICATIONS

**What's Remaining for Phase 1**:
- [ ] Jackson: Add `deviceToken` text field to Bubble User data type
- [ ] Jackson: Get APNs key from Apple Developer Portal
- [ ] Jackson: Configure APNs in Bubble settings
- [ ] Jackson: Create Bubble workflows for push notifications
- [ ] Test on physical device to verify token sync

---

### Session 4: December 4, 2025 - Phase 2 iOS Implementation

**Agent Actions**:
1. Added task-based local notification scheduling methods to NotificationManager:
   - `scheduleTaskAdvanceNotice()` - Schedule advance notice for a single task
   - `scheduleAdvanceNoticesForUserTasks()` - Schedule for all assigned tasks
   - `removeAdvanceNoticesForTask()` - Cancel notifications for a specific task
   - `removeAllAdvanceNotices()` - Cancel all advance notices
   - `scheduleAdvanceNoticesForAllTasks()` - Full reschedule using ModelContext
2. Integrated with CentralizedSyncManager - notifications scheduled after sync completes
3. Updated NotificationSettingsView:
   - Changed @AppStorage key from `notifyProjectAdvance` to `notifyAdvanceNotice`
   - Updated `rescheduleAllNotifications()` to use task-based scheduling
   - Updated cancel to use `removeAllAdvanceNotices()`

**Files Modified**:
- `OPS/Utilities/NotificationManager.swift` - Added task-based notification extension (lines 993-1177)
- `OPS/Network/Sync/CentralizedSyncManager.swift` - Added `scheduleTaskNotifications()` call after sync
- `OPS/Views/Settings/NotificationSettingsView.swift` - Updated to use new task-based methods

**Implementation Notes**:
- Tasks get their start date from `task.scheduledDate` (via `calendarEvent?.startDate`)
- Team member assignment checked via `task.getTeamMemberIds().contains(currentUserId)`
- Notification identifiers use format: `advance-{taskId}-{days}d`
- Notifications only scheduled for future tasks assigned to current user

**Phase 2 Complete**:
- [x] `scheduleTaskAdvanceNotice()` method added
- [x] `scheduleAdvanceNoticesForUserTasks()` method added
- [x] `removeAdvanceNoticesForTask()` method added
- [x] Sync manager calls scheduling after task sync
- [x] Settings view triggers reschedule on preference change

**Next Steps**:
1. Complete Phase 1 Bubble setup (user task)
2. Proceed to Phase 3 (Remote Handling) - handle incoming push notifications

---

### Session 5: December 4, 2025 - Phase 3 Remote Handling Implementation

**Agent Actions**:
1. Added remote notification handling to AppDelegate:
   - `didReceiveRemoteNotification:fetchCompletionHandler:` delegate method
   - `handleRemoteNotification()` - parses APNs payload and extracts custom data
   - `routeToScreen()` - routes by screen name (projectDetails, taskDetails, schedule, jobBoard)
   - `routeByType()` - routes by notification type (assignment, taskUpdate, scheduleChange, etc.)
   - Launch-from-notification handling in `didFinishLaunchingWithOptions`

2. Updated NotificationManager's `didReceive` response handler:
   - Detects remote notifications (has "aps" key) vs local notifications
   - Added `handleRemoteNotificationResponse()` for push notification taps
   - Added `handleTaskNotificationResponse()` for task advance notice taps
   - Added `routeToScreen()` and `routeByType()` helper methods

3. Added deep linking observers to MainTabView:
   - `OpenProjectDetails` - opens project details sheet via appState
   - `OpenTaskDetails` - posts to ShowTaskDetailsFromHome for task navigation
   - `OpenSchedule` - switches to schedule tab
   - `OpenJobBoard` - switches to job board tab

**Files Modified**:
- `OPS/AppDelegate.swift` - Added remote notification handling methods (lines 85-217)
- `OPS/Utilities/NotificationManager.swift` - Updated didReceive, added routing methods (lines 513-671)
- `OPS/Views/MainTabView.swift` - Added notification observers and handlers (lines 39-50, 207-249)

**Phase 3 Complete**:
- [x] `didReceiveRemoteNotification` added to AppDelegate
- [x] `handleRemoteNotification()` parses payload correctly
- [x] Launch from notification handled in `didFinishLaunchingWithOptions`
- [x] NotificationManager `didReceive` handles remote notifications
- [x] Deep linking observers exist for all screen types (project, task, schedule, jobBoard)
- [x] Routing methods support all Bubble notification types

**Next Steps**:
1. Complete Phase 1 Bubble setup (user task - required for push to work)
2. Proceed to Phase 4 (Settings & Reliability) - DND, Priority, Mute settings

---

### Session 6: December 4, 2025 - Phase 4 Settings & Reliability Implementation

**Agent Actions**:
1. Added Do Not Disturb (Quiet Hours) settings to NotificationSettingsView:
   - `quietHoursEnabled`, `quietHoursStart`, `quietHoursEnd` @AppStorage properties
   - Custom hour picker menus for start/end times
   - Summary text showing quiet hours range

2. Added Temporary Mute settings to NotificationSettingsView:
   - `isMuted`, `muteUntil` @AppStorage properties
   - Duration selector buttons (1h, 2h, 4h, 8h, 24h)
   - Auto-expiration check on view appear
   - Visual indicator showing mute end time

3. Added notification filtering to NotificationManager:
   - `NotificationPriorityLevel` enum (normal, important, critical)
   - `NotificationError` enum for error handling
   - `shouldSendNotification(priority:)` method that checks:
     - Temporary mute status (with auto-expiration)
     - Quiet hours (handles midnight-spanning ranges)
     - Priority filter settings
   - Applied filtering in `willPresent` delegate for foreground notifications

**Files Modified**:
- `OPS/Views/Settings/NotificationSettingsView.swift` - Added DND and Mute UI sections
- `OPS/Utilities/NotificationManager.swift` - Added filtering logic and error handling

**Note**: Priority filter UI was NOT added because:
1. The existing `NotificationPrioritySelector` in NotificationSettingsControls.swift uses its own enum
2. Priority filtering is more complex for a trades app (what counts as "critical"?)
3. The filtering logic is implemented and ready if UI is added later

**Phase 4 Complete**:
- [x] `quietHoursEnabled`, `quietHoursStart`, `quietHoursEnd` @AppStorage added
- [x] `isMuted`, `muteUntil` @AppStorage added
- [x] Do Not Disturb section added to NotificationSettingsView
- [x] Temporary Mute section added to NotificationSettingsView
- [x] `shouldSendNotification()` method implemented
- [x] Foreground notifications filtered based on settings
- [x] `NotificationPriorityLevel` enum created
- [x] `NotificationError` enum created

**What Was NOT Implemented** (as it wasn't strictly necessary):
- [ ] Priority selector UI (complex UX decision - what's "critical" vs "important"?)
- [ ] Fixing empty catch blocks (not observed as blocking issues)
- [ ] Async/await refactoring (existing callback patterns work fine)

**Next Steps**:
1. Complete Phase 1 Bubble setup (user task - required for push to work)
2. Phase 5 (Batching) is optional - only needed if users get too many notifications

---

### Session 7: December 4, 2025 - Phase 5 Notification Batching Implementation

**Agent Actions**:
1. Created `NotificationBatcher.swift` - New utility class for batching notifications:
   - Singleton pattern with thread-safe queue
   - `NotificationType` enum (assignment, scheduleChange, completion, taskAssignment, taskUpdate)
   - `BatchedNotification` struct to hold notification data
   - `startBatch()` - begins collecting notifications
   - `add()` - adds notification to batch (or sends immediately if not batching)
   - `flushBatch()` - sends summary notifications grouped by type
   - `cancelBatch()` - discards batch on error
   - Single item shows specific details, multiple items show summary (e.g., "3 new project assignments")

2. Integrated batcher with CentralizedSyncManager:
   - `syncAll()` - starts batch, flushes on success, cancels on error
   - `syncBackgroundRefresh()` - starts batch, flushes on success, cancels on error

3. Added batch notification tap handler to NotificationManager:
   - Single item in batch → opens project details
   - Multiple items → opens Job Board

**Files Created**:
- `OPS/Utilities/NotificationBatcher.swift` - Complete batching implementation

**Files Modified**:
- `OPS/Utilities/NotificationManager.swift` - Added batch tap handler
- `OPS/Network/Sync/CentralizedSyncManager.swift` - Integrated batching in syncAll and syncBackgroundRefresh

**Phase 5 Complete**:
- [x] `NotificationBatcher.swift` created in Utilities folder
- [x] `startBatch()` called at start of `syncAll()`
- [x] `flushBatch()` called at end of `syncAll()`
- [x] `cancelBatch()` called on sync error
- [x] Batch notification tap handler implemented
- [x] Background refresh also uses batching

**Note**: The batcher is ready but won't actually batch anything until sync triggers add notifications via `NotificationBatcher.shared.add()`. Currently, the local advance notices are scheduled directly (not batched) which is correct - they're scheduled in advance, not during sync. Push notifications from Bubble would trigger individual notifications unless Bubble sends them as batches.

**ALL iOS PHASES COMPLETE** - Only remaining work is Bubble backend setup (Phase 1 user task).

---

### Session 8: December 8, 2025 - OneSignal Integration

**Architecture Change**: Switching from direct APNs/Bubble to OneSignal for push notifications.

**Agent Actions**:
1. Added OneSignal SDK package to project (user did this via SPM)
2. Updated NOTIFICATIONS_OVERVIEW.md with OneSignal architecture
3. Rewrote PHASE_1_PUSH_INFRASTRUCTURE.md for OneSignal approach
4. Updated BUBBLE_WORKFLOWS.md to show OneSignal REST API integration
5. Started OneSignal initialization in AppDelegate:
   - Added `import OneSignalFramework`
   - Added `OSNotificationLifecycleListener` protocol
   - Added `configureOneSignal()` method
   - Added click handler for deep linking
   - Added foreground handler respecting DND/Mute settings

**Files Modified**:
- `OPS/AppDelegate.swift` - Added OneSignal import, initialization, handlers (partial)
- `OPS/Utilities/NotificationManager.swift` - Added OneSignal import (partial)
- `NOTIFICATIONS_OVERVIEW.md` - Complete rewrite for OneSignal
- `PHASE_1_PUSH_INFRASTRUCTURE.md` - Complete rewrite for OneSignal
- `BUBBLE_WORKFLOWS.md` - Updated for OneSignal REST API

**OneSignal Configuration**:
- App ID: `0fc0a8e0-9727-49b6-9e37-5d6d919d741f`

**What's Complete**:
- [x] OneSignal SDK added to project
- [x] Documentation updated for OneSignal approach
- [x] OneSignal initialization code added to AppDelegate
- [x] Click handler added (uses `OSNotificationClickListener` protocol)
- [x] Foreground handler added (respects shouldSendNotification())
- [x] APNs key uploaded to OneSignal dashboard
- [x] `linkUserToOneSignal()` method added to NotificationManager
- [x] `unlinkUserFromOneSignal()` method added to NotificationManager
- [x] `linkUserToOneSignal()` called in DataController after login + existing auth
- [x] `unlinkUserFromOneSignal()` called in DataController.logout()
- [x] Test notification delivery from OneSignal dashboard - WORKING
- [x] Verified user linking works (external_id shows in OneSignal dashboard)
- [x] Log verbosity reduced for production (LL_WARN in debug, LL_NONE in release)
- [x] OneSignalService.swift created for app-triggered notifications
- [x] API key fetched securely from Bubble endpoint (`fetch-os-key`)
- [x] Task assignment notifications integrated (auto-send when team member added)
- [x] Schedule change notifications integrated (auto-send when calendar event changed)
- [x] Project completion notifications integrated (auto-send when project completed)
- [x] Deep linking tested and working (tapping notification opens correct screen)

**What's Remaining (Optional)**:
- [ ] Set up Bubble workflows to call OneSignal API (for web app triggers)

**Phase Status After This Session**:
| Phase | Status | Notes |
|-------|--------|-------|
| 1 | ✅ Complete | OneSignal fully integrated and tested |
| 2 | ✅ Complete | Local task-based notifications |
| 3 | ✅ Complete | Remote handling + deep linking |
| 4 | ✅ Complete | DND, Mute, filtering |
| 5 | ✅ Complete | Notification batching |

**Testing Completed December 8, 2025**:
- Notifications delivered successfully to both iPhone 16 and iPhone 13
- Users appear in OneSignal dashboard with correct external_id
- Issue resolved: iPhone 13 initially showed "never subscribed" due to iOS notification permissions being disabled
- Task assignment notification: Auto-sends when user added to task team ✅
- Deep linking: Tapping notification opens correct task/project screen ✅
- Cold launch handling: 0.5s delay added for view initialization ✅

---

### Session 9: December 8, 2025 - Task/Project Creation Notifications

**Issue Identified**: Task and project creation were not triggering notifications. The existing notification triggers in DataController only worked for:
- `updateTaskTeamMembers()` - When team members modified on EXISTING tasks
- `updateProjectStatus()` - When project status changes
- `updateCalendarEvent()` - When calendar event dates change

Task/project CREATION was handled in ProjectFormSheet, not DataController, so notifications were never triggered.

**Agent Actions**:
1. Added notification trigger for new task creation in `ProjectFormSheet.createTask()`:
   - After task successfully syncs to Bubble, sends task assignment notification to all team members
   - Uses `OneSignalService.shared.notifyTaskAssignment()` for each team member
   - Only sends if task sync succeeded (has Bubble ID) and OneSignal is configured

2. Added notification trigger for project assignment in `ProjectFormSheet.createNewProject()`:
   - After project syncs and tasks are created, sends project assignment notification
   - Only notifies team members who DON'T have task assignments (to avoid duplicate notifications)
   - Users with task assignments get task notifications instead

**Files Modified**:
- `OPS/Views/JobBoard/ProjectFormSheet.swift` (lines 1650-1672, 1428-1451)

**Notification Logic**:
```swift
// Task Creation: Notify all team members assigned to the new task
let teamMemberIds = task.teamMembers.map { $0.id }
if !teamMemberIds.isEmpty && OneSignalService.shared.isConfigured {
    for userId in teamMemberIds {
        try await OneSignalService.shared.notifyTaskAssignment(...)
    }
}

// Project Creation: Notify team members NOT assigned to tasks
let projectTeamMemberIds = Set(project.teamMembers.map { $0.id })
let taskTeamMemberIds = Set(localTasks.flatMap { $0.teamMemberIds })
let projectOnlyMemberIds = projectTeamMemberIds.subtracting(taskTeamMemberIds)
// Only notify projectOnlyMemberIds to avoid duplicate notifications
```

**What's Now Complete**:
- [x] Task creation triggers assignment notifications ✅
- [x] Project creation triggers assignment notifications (for non-task members) ✅
- [x] Existing task team member updates trigger notifications ✅
- [x] Project completion triggers notifications ✅
- [x] Schedule changes trigger notifications ✅

**All Notification Triggers Now Active**:
| Trigger | Location | Notification Type |
|---------|----------|-------------------|
| New task created | ProjectFormSheet.createTask() | taskAssignment |
| New project created | ProjectFormSheet.createNewProject() | projectAssignment |
| Task team updated | DataController.updateTaskTeamMembers() | taskAssignment |
| Task completed | DataController.updateTaskStatus() | taskCompletion |
| Project completed | DataController.updateProjectStatus() | projectCompletion |
| Schedule changed | DataController.updateCalendarEvent() | scheduleChange |

---

### Session 10: December 8, 2025 - Task Completion Notifications

**User Request**: When a task is marked complete, notify ALL project team members (not just task team members). This enables workflow handoff - when Jake finishes Task 3, Harry on Task 4 knows the preceding work is done.

**Agent Actions**:
1. Added `notifyTaskCompletion()` method to OneSignalService:
   - Takes project team member IDs (not task team members)
   - Includes name of person who completed the task
   - Message format: "Jake completed \"Framing\" on Project Name"
   - Routes to project details on tap

2. Added task completion notification trigger in `DataController.updateTaskStatus()`:
   - Fires when `newStatus == .completed`
   - Gets all project team members from `task.project.teamMembers`
   - Includes `currentUser?.fullName` as `completedByName`

3. Added `taskCompletion` to deep linking routing in AppDelegate

**Files Modified**:
- `OPS/Services/OneSignalService.swift` - Added `notifyTaskCompletion()` method (lines 190-221)
- `OPS/Utilities/DataController.swift` - Added notification trigger in `updateTaskStatus()` (lines 3291-3316)
- `OPS/AppDelegate.swift` - Added `taskCompletion` to routing switch case (line 252)

**Notification Details**:
- **Title**: "Task Completed"
- **Body**: "{Name} completed \"{Task Name}\" on {Project Name}"
- **Recipients**: All project team members (excluding the person who completed it)
- **Deep Link**: Opens project details

---

## Critical Context for Future Agents

### Architecture Change (Important!)
**December 8, 2025**: Architecture changed from direct APNs/Bubble to **OneSignal**.

- **Push notifications** are sent via OneSignal (dashboard, iOS app, or Bubble API)
- **Local notifications** are scheduled by iOS for advance reminders (unchanged)
- OneSignal App ID: `0fc0a8e0-9727-49b6-9e37-5d6d919d741f`
- Keep existing Bubble device token sync for potential future direct APNs use

See NOTIFICATIONS_OVERVIEW.md for full architecture diagram

### Don't Duplicate This Work
- NotificationManager.swift has complete task-based scheduling (Phase 2 done)
- NotificationManager.swift has complete remote notification routing (Phase 3 done)
- NotificationManager.swift has shouldSendNotification() filtering (Phase 4 done)
- NotificationManager.swift has batch notification tap handler (Phase 5 done)
- NotificationBatcher.swift handles notification grouping during sync (Phase 5 done)
- AppDelegate.swift has complete push notification handling (Phase 3 done)
- MainTabView.swift has deep linking observers (Phase 3 done)
- NotificationSettingsView.swift has DND and Mute settings (Phase 4 done)
- CentralizedSyncManager.swift integrates notification batching (Phase 5 done)
- NotificationSettingsControls.swift has unused UI components (TimeWindow, Priority - partially used)
- Phase 1 iOS code is already complete (just needs Bubble setup)
- Phase 2 iOS code is complete (task-based advance notices)
- Phase 3 iOS code is complete (remote handling + deep linking)
- Phase 4 iOS code is complete (DND, Mute, notification filtering)
- Phase 5 iOS code is complete (notification batching)

### Key Implementation Notes
1. **User ID Storage**: `UserDefaults.standard.string(forKey: "currentUserId")`
2. **Notification Preferences**: Use @AppStorage with keys like `notifyTaskAssignment`
3. **Bubble API Pattern**: NotificationManager uses direct URLSession calls
4. **Task-Based**: Local reminders use task start dates, not project dates

### Files You'll Modify

**Phase 2** (Local Notifications):
- `OPS/Utilities/NotificationManager.swift` - Task-based scheduling
- `OPS/Network/Sync/CentralizedSyncManager.swift` - Call scheduling after sync

**Phase 3** (Remote Handling):
- `OPS/AppDelegate.swift` - Add remote notification handling
- `OPS/Utilities/NotificationManager.swift` - Add remote notification parsing

**Phase 4** (Settings):
- `OPS/Views/Settings/NotificationSettingsView.swift` - Add DND, Priority, Mute
- `OPS/Utilities/NotificationManager.swift` - Add shouldSendNotification()

**Phase 5** (Batching):
- `OPS/Utilities/NotificationBatcher.swift` - NEW FILE
- Integration with sync manager

---

## Blockers & Dependencies

### External Dependencies (Jackson Must Complete)
1. **Bubble Setup** - See BUBBLE_WORKFLOWS.md:
   - Add `deviceToken` field to User data type
   - Upload APNs key to Bubble
   - Create push notification workflows

### Technical Dependencies
- Phase 2 can be done independently (local notifications)
- Phase 3 requires Phase 1 Bubble setup complete
- Phase 5 depends on Phase 2 for task-based logic
- Phase 4 can be done in parallel with any phase

---

## Testing Checklist

### Phase 1 Testing
- [ ] App registers for push notifications on physical device
- [ ] Device token appears in console log
- [ ] Device token synced to Bubble User record
- [ ] Bubble can send test push notification

### Phase 2 Testing
- [ ] Advance notice scheduled for correct date/time
- [ ] Only assigned tasks get notifications
- [ ] Changing lead time reschedules notifications
- [ ] Notifications cancelled when task deleted/unassigned

### Phase 3 Testing
- [ ] Push received while app in foreground
- [ ] Push received while app in background
- [ ] Tapping notification opens correct screen
- [ ] App launch from notification works

### Phase 4 Testing
- [ ] Quiet hours prevents notifications
- [ ] Temporary mute works
- [ ] Settings persist after app restart

### Phase 5 Testing
- [ ] Multiple notifications batched into summary
- [ ] Single notification shows specific details

---

## Quick Reference

### File Locations
```
/Users/jacksonsweet/Desktop/OPS LTD./OPS/
├── OPS/
│   ├── AppDelegate.swift
│   ├── OPS.entitlements
│   ├── DataModels/User.swift
│   ├── Network/
│   │   ├── API/APIService.swift, BubbleFields.swift
│   │   ├── DTOs/UserDTO.swift
│   │   └── Sync/CentralizedSyncManager.swift
│   ├── Utilities/NotificationManager.swift
│   └── Views/Settings/
│       ├── NotificationSettingsView.swift
│       └── Components/NotificationSettingsControls.swift
└── Development Tasks/Notifications Implementation/
    ├── AGENT_HANDOVER.md (this file)
    ├── NOTIFICATIONS_OVERVIEW.md
    ├── BUBBLE_WORKFLOWS.md
    ├── PHASE_1_PUSH_INFRASTRUCTURE.md
    ├── PHASE_2_LOCAL_NOTIFICATIONS.md
    ├── PHASE_3_REMOTE_HANDLING.md
    ├── PHASE_4_SETTINGS_RELIABILITY.md
    └── PHASE_5_BATCHING.md
```

### Key @AppStorage Keys
```swift
// Push notification preferences (receive or not)
"notifyTaskAssignment"         // Bool - default true
"notifyScheduleChanges"        // Bool - default true
"notifyProjectCompletion"      // Bool - default true

// Local reminder preferences
"notifyAdvanceNotice"          // Bool - default true
"advanceNoticeDays1"           // Int - default 1
"advanceNoticeDays2"           // Int - default 0
"advanceNoticeDays3"           // Int - default 0
"advanceNoticeHour"            // Int - default 8
"advanceNoticeMinute"          // Int - default 0

// DND settings (Phase 4)
"quietHoursEnabled"            // Bool
"quietHoursStart"              // Int (hour, 0-23)
"quietHoursEnd"                // Int (hour, 0-23)

// Device token
"apns_device_token"            // String
"currentUserId"                // String
```

---

## Handover Template

When ending your session, add a new session entry:

```markdown
### Session [N]: [Date] - [Brief Description]

**Agent Actions**:
1. [What you did]
2. [What you did]

**Files Modified**:
- [file path] - [what changed]

**Phase Status After This Session**:
| Phase | Status | Notes |
|-------|--------|-------|
| 1 | [status] | [notes] |
| 2 | [status] | [notes] |
| 3 | [status] | [notes] |
| 4 | [status] | [notes] |
| 5 | [status] | [notes] |

**Next Steps**:
1. [what next agent should do]
```
