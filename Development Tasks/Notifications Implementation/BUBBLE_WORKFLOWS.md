# Bubble + OneSignal Integration (Optional/Future)

**Last Updated**: December 8, 2025
**Owner**: Jackson (Bubble implementation)
**Status**: Optional - Not Required for Initial Launch

---

## Overview

This document describes how to trigger push notifications from Bubble using OneSignal's REST API. This is **optional** - notifications can also be:
1. Sent manually from the OneSignal dashboard
2. Triggered from the iOS app

---

## When to Use Bubble-Triggered Notifications

Use Bubble workflows to send notifications when:
- Changes happen on the Bubble web app (not the iOS app)
- You want server-side control over notification logic
- You need to notify users who aren't currently using the app

---

## Prerequisites

### OneSignal Setup (Already Complete)
- [x] OneSignal account created
- [x] OneSignal app created
- [x] App ID: `0fc0a8e0-9727-49b6-9e37-5d6d919d741f`
- [ ] APNs key uploaded to OneSignal (required for delivery)

### Get OneSignal REST API Key
1. Go to OneSignal Dashboard → Settings → Keys & IDs
2. Copy the **REST API Key** (starts with `os_v2_app_...` or similar)
3. Store this securely - you'll need it for Bubble API calls

---

## Option 1: Using Bubble's API Connector

### Step 1: Set Up API Connector

1. In Bubble Editor → Plugins → Add "API Connector" (if not already added)
2. Add new API:
   - **API Name**: OneSignal
   - **Authentication**: None (we'll add header manually)

### Step 2: Create "Send Notification" Call

Add new API call:
- **Name**: Send Notification
- **Use as**: Action
- **Method**: POST
- **URL**: `https://onesignal.com/api/v1/notifications`

**Headers**:
| Key | Value |
|-----|-------|
| Content-Type | application/json |
| Authorization | Basic [YOUR_REST_API_KEY] |

**Body (JSON)**:
```json
{
  "app_id": "0fc0a8e0-9727-49b6-9e37-5d6d919d741f",
  "include_aliases": {
    "external_id": ["<user_id>"]
  },
  "target_channel": "push",
  "headings": {"en": "<title>"},
  "contents": {"en": "<body>"},
  "data": {
    "type": "<notification_type>",
    "projectId": "<project_id>",
    "taskId": "<task_id>",
    "screen": "<screen>"
  }
}
```

**Parameters** (mark as dynamic):
- `user_id` - The Bubble user's unique ID
- `title` - Notification title
- `body` - Notification body text
- `notification_type` - e.g., "taskAssignment", "scheduleChange"
- `project_id` - Project unique ID
- `task_id` - Task unique ID (optional)
- `screen` - Screen to open: "taskDetails", "projectDetails", "jobBoard"

### Step 3: Initialize the Call

Click "Initialize call" with test values to verify it works.

---

## Option 2: Create Multiple API Calls for Each Notification Type

For cleaner workflows, create separate API calls:

### API Call: Notify Task Assignment

**Body**:
```json
{
  "app_id": "0fc0a8e0-9727-49b6-9e37-5d6d919d741f",
  "include_aliases": {
    "external_id": ["<user_id>"]
  },
  "target_channel": "push",
  "headings": {"en": "New Task Assignment"},
  "contents": {"en": "You've been assigned to <task_name> on <project_name>"},
  "data": {
    "type": "taskAssignment",
    "projectId": "<project_id>",
    "taskId": "<task_id>",
    "screen": "taskDetails"
  }
}
```

### API Call: Notify Schedule Change

**Body**:
```json
{
  "app_id": "0fc0a8e0-9727-49b6-9e37-5d6d919d741f",
  "include_aliases": {
    "external_id": ["<user_id>"]
  },
  "target_channel": "push",
  "headings": {"en": "Schedule Update"},
  "contents": {"en": "<task_name> on <project_name>: Schedule has been updated"},
  "data": {
    "type": "scheduleChange",
    "projectId": "<project_id>",
    "taskId": "<task_id>",
    "screen": "taskDetails"
  }
}
```

### API Call: Notify Project Completion

**Body**:
```json
{
  "app_id": "0fc0a8e0-9727-49b6-9e37-5d6d919d741f",
  "include_aliases": {
    "external_id": ["<user_id>"]
  },
  "target_channel": "push",
  "headings": {"en": "Project Completed"},
  "contents": {"en": "<project_name> has been marked as completed"},
  "data": {
    "type": "projectCompletion",
    "projectId": "<project_id>",
    "screen": "projectDetails"
  }
}
```

---

## Bubble Workflow Examples

### Workflow 1: Task Assignment Notification

**Trigger**: Database trigger - When Task's assignedTo is modified

**Conditions**:
- New assignee is not the same as current user (don't notify yourself)
- Task has a project

**Actions**:
1. For each new user in assignedTo list:
   - OneSignal - Notify Task Assignment
     - user_id: This User's unique id
     - task_name: This Task's name
     - project_name: This Task's Project's name
     - project_id: This Task's Project's unique id
     - task_id: This Task's unique id

### Workflow 2: Schedule Change Notification

**Trigger**: Database trigger - When Task's startDate or endDate is modified

**Conditions**:
- Task has team members assigned
- Dates actually changed (not just touched)

**Actions**:
1. For each user in Task's team members:
   - Only when: This User is not Current User
   - OneSignal - Notify Schedule Change
     - user_id: This User's unique id
     - (other params as above)

### Workflow 3: Project Completion Notification

**Trigger**: Database trigger - When Project's status changes to "Completed"

**Conditions**:
- Previous status was not "Completed"

**Actions**:
1. Get all unique team members across all project tasks
2. For each team member:
   - Only when: This User is not Current User
   - OneSignal - Notify Project Completion
     - user_id: This User's unique id
     - project_name: This Project's name
     - project_id: This Project's unique id

---

## Sending to Multiple Users at Once

Instead of looping, you can send to multiple users in one API call:

```json
{
  "app_id": "0fc0a8e0-9727-49b6-9e37-5d6d919d741f",
  "include_aliases": {
    "external_id": ["user_id_1", "user_id_2", "user_id_3"]
  },
  "target_channel": "push",
  "headings": {"en": "Schedule Update"},
  "contents": {"en": "Task schedule has been updated"}
}
```

In Bubble, you'd need to format the user IDs as a JSON array.

---

## Important Notes

### Don't Notify the Actor
Always add a condition to exclude the user who made the change:
```
Only when: This User is not Current User
```

### Handle Missing External IDs
If a user hasn't opened the iOS app yet, they won't have a OneSignal subscription. The API call will succeed but no notification will be delivered.

### Rate Limits
OneSignal has rate limits. For bulk notifications, consider:
- Using segments instead of individual targeting
- Batching API calls
- Using OneSignal's scheduled delivery

### Error Handling
The API Connector doesn't show errors by default. For debugging:
1. Check OneSignal Dashboard → Delivery for failed notifications
2. Add error handling to your workflows

---

## Alternative: Direct APNs (Legacy)

The original plan used direct APNs from Bubble. This is still possible but requires:
1. APNs key configured in Bubble (not OneSignal)
2. Device token stored on User record
3. Bubble's native push notification action

This approach is NOT recommended now that OneSignal is integrated, but the device token sync code remains in the iOS app for potential future use.

---

## Testing Checklist

- [ ] API Connector configured with correct API key
- [ ] Test notification sent successfully
- [ ] Notification appears on iOS device
- [ ] Tapping notification opens correct screen
- [ ] Workflow only notifies relevant users (not actor)
