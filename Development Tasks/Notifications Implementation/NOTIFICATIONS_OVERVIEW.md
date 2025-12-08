# OPS Notifications System - Complete Overview

**Last Updated**: December 8, 2025
**Status**: ✅ All Phases Complete | OneSignal Integration Tested & Working

---

## Project Goal

Implement a complete notification system for the OPS iOS app:

1. **Push Notifications (Immediate)** - Sent via OneSignal
   - Task assignment → Push to assigned user
   - Task completion → Push to all project team members (workflow handoff)
   - Schedule changes → Push to all affected team members
   - Project completion → Push to all assigned team members
   - Manual notifications from OneSignal dashboard

2. **Local Notifications (Scheduled Reminders)** - Scheduled on user's device
   - Advance notice before task start date (user chooses lead time: 1 day, 2 days, etc.)
   - Only for tasks user is assigned to

3. **User Preference Controls**
   - Users can disable specific notification types they don't want to receive
   - Do Not Disturb (quiet hours)
   - Temporary mute
   - Default: All notifications enabled

---

## Architecture Overview

### Push Notifications (Real-Time) - OneSignal

```
Event occurs (task assigned, schedule changed, etc.)
         ↓
iOS app calls OneSignal API to send notification
  - OR -
Admin sends from OneSignal dashboard
  - OR -
Bubble workflow calls OneSignal REST API (future)
         ↓
OneSignal delivers push via APNs
         ↓
User receives push notification immediately
```

**OneSignal is responsible for:**
- Managing device subscriptions (Player IDs)
- Delivering push notifications via APNs
- Providing dashboard for manual notifications
- Analytics and delivery tracking

**iOS app is responsible for:**
- Initializing OneSignal SDK
- Linking user ID to OneSignal (External User ID)
- Triggering notifications via OneSignal API when events occur
- Receiving and displaying push notifications
- Handling notification taps (deep linking)

**Bubble (optional, future):**
- Can trigger notifications via OneSignal REST API
- Keep device token sync for potential direct APNs use

### Local Notifications (Scheduled Reminders)

```
App syncs tasks from Bubble
         ↓
For each task user is assigned to:
         ↓
Calculate reminder date (task start - user's lead time preference)
         ↓
Schedule local notification on device
         ↓
iOS delivers notification at scheduled time
```

**iOS app is responsible for:**
- Reading user's advance notice preferences
- Scheduling local notifications based on task start dates
- Rescheduling when tasks are updated
- Cancelling when tasks are deleted/unassigned

---

## Notification Types Summary

| Type | Trigger | Delivery | Recipients | Source |
|------|---------|----------|------------|--------|
| Task Assignment | User added to task | Push (immediate) | Task team members | OneSignal |
| Task Completion | Task marked complete | Push (immediate) | All project team | OneSignal |
| Schedule Change | Task dates modified | Push (immediate) | Task team members | OneSignal |
| Project Assignment | User added to project | Push (immediate) | New member | OneSignal |
| Project Completion | Project marked complete | Push (immediate) | Project team | OneSignal |
| Advance Reminder | X days before task start | Local (scheduled) | Self | iOS |
| Manual Announcement | Admin sends from dashboard | Push (immediate) | Selected users | OneSignal Dashboard |

---

## OneSignal Configuration

### App ID
```
0fc0a8e0-9727-49b6-9e37-5d6d919d741f
```

### Key Concepts

1. **Player ID** - OneSignal's internal device identifier (auto-generated)
2. **External User ID** - Your app's user ID linked to OneSignal for targeting
3. **Tags** - Custom key-value pairs for segmentation (e.g., role, company)

### User Targeting Options

| Method | Use Case |
|--------|----------|
| Player ID | Target specific device |
| External User ID | Target user across devices |
| Tags | Target by role, company, etc. |
| Segments | Target groups defined in dashboard |

---

## Current State (December 8, 2025)

### What's Complete (iOS)

| Component | File | Status |
|-----------|------|--------|
| NotificationManager | `OPS/Utilities/NotificationManager.swift` | ✅ Complete |
| Permission flow | NotificationManager | ✅ Working |
| Local advance reminders | NotificationManager | ✅ Task-based scheduling |
| NotificationSettingsView | `OPS/Views/Settings/NotificationSettingsView.swift` | ✅ Complete with DND/Mute |
| Device token capture | AppDelegate + NotificationManager | ✅ Working |
| Device token sync to Bubble | NotificationManager | ✅ Implemented |
| Remote notification handling | AppDelegate | ✅ Deep linking works |
| Notification batching | NotificationBatcher.swift | ✅ Implemented |
| OneSignal SDK | AppDelegate | ✅ Complete |

### Testing Status (December 8, 2025)

| Test | Status |
|------|--------|
| OneSignal SDK initialization | ✅ Working |
| OneSignal click handler | ✅ Working |
| OneSignal foreground handler | ✅ Working |
| External User ID linking | ✅ Working |
| Notification delivery (iPhone 16) | ✅ Working |
| Notification delivery (iPhone 13) | ✅ Working |
| OneSignal API trigger methods | 🔵 Optional - not implemented |

---

## Implementation Phases (Revised for OneSignal)

| Phase | Priority | Description | Status |
|-------|----------|-------------|--------|
| 1 | P0 | Push infrastructure (iOS + OneSignal) | ✅ Complete |
| 2 | P1 | Local notifications (task-based scheduling) | ✅ Complete |
| 3 | P1 | Handle incoming push notifications (deep linking) | ✅ Complete |
| 4 | P2 | Settings integration (DND, Priority, Mute) | ✅ Complete |
| 5 | P1 | Notification batching | ✅ Complete |

---

## User Preference Settings

### Push Notification Preferences (receive or not)
- `notifyTaskAssignment` - Receive when assigned to task (default: true)
- `notifyScheduleChanges` - Receive when dates change (default: true)
- `notifyProjectCompletion` - Receive when project completes (default: true)

### Local Reminder Preferences
- `notifyAdvanceNotice` - Enable advance reminders (default: true)
- `advanceNoticeDays1` - First lead time in days (default: 1)
- `advanceNoticeDays2` - Second lead time (default: 0 = disabled)
- `advanceNoticeDays3` - Third lead time (default: 0 = disabled)
- `advanceNoticeHour` - What time to send reminder (default: 8)
- `advanceNoticeMinute` - Minute of reminder time (default: 0)

### DND & Mute Settings (Phase 4 - Complete)
- `quietHoursEnabled` - Enable quiet hours
- `quietHoursStart` - Start hour (0-23)
- `quietHoursEnd` - End hour (0-23)
- `isMuted` - Temporary mute active
- `muteUntil` - Mute expiration timestamp

---

## Related Documentation

- `PHASE_1_PUSH_INFRASTRUCTURE.md` - OneSignal setup + iOS integration
- `PHASE_2_LOCAL_NOTIFICATIONS.md` - Task-based local notification scheduling
- `PHASE_3_REMOTE_HANDLING.md` - Handle incoming push, deep linking
- `PHASE_4_SETTINGS_RELIABILITY.md` - Settings and error handling
- `PHASE_5_BATCHING.md` - Batch multiple notifications
- `BUBBLE_WORKFLOWS.md` - Bubble + OneSignal integration (future)
- `AGENT_HANDOVER.md` - Session tracking and handover notes
