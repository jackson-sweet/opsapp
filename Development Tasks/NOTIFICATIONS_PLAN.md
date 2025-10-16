# Notifications Implementation Plan

## Overview
This document outlines the planned notification system for OPS, including subscription-related notifications and future notification features.

---

## Subscription Notifications

### 1. Grace Period Start Notification
**Trigger**: User's subscription enters grace period (payment failed but still has access)

**Notification Content**:
- **Title**: "Payment Issue Detected"
- **Body**: "There was a problem with your payment. Please update your payment method to continue using OPS."
- **Action**: Deep link to payment settings/subscription management

**Technical Notes**:
- Should be triggered by backend when subscription status changes to grace period
- Use APNs (Apple Push Notification service)
- Priority: High (user needs to take action)
- Should only send once when grace period begins

---

### 2. Grace Period Countdown - 5 Days Remaining
**Trigger**: 5 days remaining until subscription cancellation

**Notification Content**:
- **Title**: "5 Days Until Service Interruption"
- **Body**: "Your OPS subscription will be cancelled in 5 days. Update your payment method now to avoid losing access."
- **Action**: Deep link to payment settings/subscription management

**Technical Notes**:
- Calculate time remaining in grace period
- Send exactly at 5-day mark
- Priority: Critical

---

### 3. Grace Period Countdown - 3 Days Remaining
**Trigger**: 3 days remaining until subscription cancellation

**Notification Content**:
- **Title**: "3 Days Until Service Interruption"
- **Body**: "Your OPS subscription will be cancelled in 3 days. Update your payment method immediately."
- **Action**: Deep link to payment settings/subscription management

**Technical Notes**:
- Send exactly at 3-day mark
- Priority: Critical
- Consider making this notification more prominent (critical alert?)

---

### 4. Grace Period Countdown - 1 Day Remaining
**Trigger**: 1 day (24 hours) remaining until subscription cancellation

**Notification Content**:
- **Title**: "Final Notice: 1 Day Remaining"
- **Body**: "Your OPS subscription will be cancelled tomorrow. Update your payment method now to avoid losing access to your projects."
- **Action**: Deep link to payment settings/subscription management

**Technical Notes**:
- Send exactly at 1-day (24-hour) mark
- Priority: Critical
- Should be most urgent/prominent notification
- Consider time-sensitive notification flag

---

## Implementation Details

### Backend Requirements
- Monitor subscription status changes
- Track grace period start date
- Calculate remaining days in grace period
- Send push notifications via APNs at appropriate intervals
- Handle timezone considerations (send at reasonable local time)

### iOS App Requirements
- Register for push notifications
- Request notification permissions from user
- Handle notification taps and deep linking to subscription settings
- Display subscription status in-app
- Update notification badge if needed

### Deep Linking
All subscription notifications should deep link to:
- Settings > Account > Subscription Management
- Or directly to payment method update screen

### Notification Permissions
- Request notification permission at appropriate time (not on first launch)
- Explain why notifications are important (don't miss important updates about projects and subscription)
- Handle permission denial gracefully

### Testing Considerations
- Test notifications at each interval
- Test deep linking from notifications
- Test with different subscription states
- Test notification appearance in various states (locked screen, notification center, banner)
- Test notification sounds/haptics

---

## Future Notification Types (Planned)

### Project & Task Notifications
- Task due date reminders
- Project milestone notifications
- Team member assignments
- Status change notifications

### Team Collaboration
- Comments on projects/tasks
- @mentions
- Team member check-ins

### System Notifications
- Sync completion (optional)
- Offline mode warnings
- App updates available

---

## Design Guidelines

### Notification Tone
- **Urgent but not alarming**: Subscription notifications should convey urgency without causing panic
- **Actionable**: Always include clear next step
- **Respectful**: Don't over-notify or spam user
- **Professional**: Match OPS brand voice (direct, practical, dependable)

### Notification Timing
- Send subscription notifications at reasonable hours (9 AM - 8 PM user's local time)
- Avoid weekends for non-critical notifications
- Grace period notifications can be sent any day (urgent)

### Notification Settings
Allow users to control:
- ✅ Subscription/billing notifications (should default ON, critical)
- ⚙️ Project/task notifications (configurable)
- ⚙️ Team notifications (configurable)
- ⚙️ System notifications (configurable)

---

## Priority & Timeline

### Phase 1 (High Priority)
1. Grace period start notification
2. 5-day countdown notification
3. 3-day countdown notification
4. 1-day countdown notification

### Phase 2 (Future)
- Project/task notifications
- Team collaboration notifications
- System notifications

---

## Technical Stack

- **Push Service**: Apple Push Notification service (APNs)
- **Backend**: Bubble workflows to trigger notifications
- **iOS Framework**: UserNotifications framework
- **Deep Linking**: Custom URL scheme or Universal Links

---

## Notes

- All subscription notifications are critical and should NOT be suppressible by user
- Consider using critical alerts for final warning (1 day remaining)
- Ensure notification content is clear even when truncated on lock screen
- Test notification delivery reliability
- Monitor notification delivery metrics (sent, delivered, opened)
