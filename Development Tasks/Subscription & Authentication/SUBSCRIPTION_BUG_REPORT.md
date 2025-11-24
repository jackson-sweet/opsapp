# Subscription Authentication Bug Report & Debugging Plan
**Date Created**: January 23, 2025
**Status**: Under Investigation

## Critical Bug: Grace Period Notification Range Error

### Bug Description
Fatal crash occurs when company transitions from grace period to expired/trial status due to invalid range in notification scheduling.

**Error Message**:
```
Fatal error: Range requires lowerBound <= upperBound
Location: SubscriptionManager.swift, line 442
```

### Root Cause Analysis

**File**: `SubscriptionManager.swift`
**Line**: 442

```swift
private func scheduleGracePeriodNotifications(daysRemaining: Int) async {
    // Schedule daily notifications during grace period
    for day in 1...daysRemaining {  // ❌ CRASHES when daysRemaining <= 0
        scheduleGracePeriodNotification(daysRemaining: daysRemaining - day + 1)
    }
}
```

**Chain of Events**:
1. Company subscription status is `.grace`
2. Grace period expires (reaches day 0)
3. `Company.daysRemainingInGracePeriod` returns 0 (line 191: `return max(0, days)`)
4. `SubscriptionManager.checkSubscriptionStatus()` calls `scheduleGracePeriodNotifications(daysRemaining: 0)`
5. Code attempts to create range `1...0` which is invalid (lowerBound > upperBound)
6. **Swift crashes with fatal error**

### Console Evidence
```
[SUBSCRIPTION] Current state - Status: grace, Plan: business, Seats: 1/10
[AUTH] ✅ Access granted - grace subscription with seat
[AUTH] ✅ All 5 validation layers passed
Fatal error: Range requires lowerBound <= upperBound
```

**Note**: The auth checks pass, but the app crashes during notification scheduling after status check completes.

---

## Proposed Fixes

### Fix 1: Guard Clause in scheduleGracePeriodNotifications (Priority: CRITICAL)

**Location**: `SubscriptionManager.swift:440-445`

**Current Code**:
```swift
private func scheduleGracePeriodNotifications(daysRemaining: Int) async {
    // Schedule daily notifications during grace period
    for day in 1...daysRemaining {
        scheduleGracePeriodNotification(daysRemaining: daysRemaining - day + 1)
    }
}
```

**Fixed Code**:
```swift
private func scheduleGracePeriodNotifications(daysRemaining: Int) async {
    // Guard against invalid range (daysRemaining must be >= 1 for range 1...daysRemaining)
    guard daysRemaining > 0 else {
        print("[SUBSCRIPTION] ⚠️ No grace period notifications to schedule (days remaining: \(daysRemaining))")
        return
    }

    print("[SUBSCRIPTION] 📅 Scheduling \(daysRemaining) grace period notification(s)")

    // Schedule daily notifications during grace period
    for day in 1...daysRemaining {
        scheduleGracePeriodNotification(daysRemaining: daysRemaining - day + 1)
    }
}
```

### Fix 2: Guard Clause in scheduleTrialNotifications (Priority: HIGH)

**Location**: `SubscriptionManager.swift:429-438`

**Current Code**:
```swift
private func scheduleTrialNotifications(daysRemaining: Int) async {
    // Schedule notifications for days 7, 3, and 1
    let notificationDays = [7, 3, 1]

    for day in notificationDays {
        if daysRemaining >= day {
            scheduleTrialExpiryNotification(daysBeforeExpiry: day)
        }
    }
}
```

**Fixed Code**:
```swift
private func scheduleTrialNotifications(daysRemaining: Int) async {
    guard daysRemaining > 0 else {
        print("[SUBSCRIPTION] ⚠️ No trial notifications to schedule (days remaining: \(daysRemaining))")
        return
    }

    print("[SUBSCRIPTION] 📅 Scheduling trial notifications (days remaining: \(daysRemaining))")

    // Schedule notifications for days 7, 3, and 1
    let notificationDays = [7, 3, 1]

    for day in notificationDays {
        if daysRemaining >= day {
            scheduleTrialExpiryNotification(daysBeforeExpiry: day)
        }
    }
}
```

### Fix 3: Enhanced Logging in checkSubscriptionStatus (Priority: MEDIUM)

Add comprehensive logging around subscription transitions to catch edge cases:

**Location**: `SubscriptionManager.swift:107-181`

Add detailed date and status logging:
```swift
// Add after line 125 (before subscription status check)
print("[SUBSCRIPTION] 📊 Company Date Fields:")
print("[SUBSCRIPTION]    - trialStartDate: \(company.trialStartDate?.formatted() ?? "nil")")
print("[SUBSCRIPTION]    - trialEndDate: \(company.trialEndDate?.formatted() ?? "nil")")
print("[SUBSCRIPTION]    - seatGraceStartDate: \(company.seatGraceStartDate?.formatted() ?? "nil")")
print("[SUBSCRIPTION]    - subscriptionEnd: \(company.subscriptionEnd?.formatted() ?? "nil")")
print("[SUBSCRIPTION]    - subscriptionStatus: \(company.subscriptionStatus ?? "nil")")
print("[SUBSCRIPTION]    - subscriptionPlan: \(company.subscriptionPlan ?? "nil")")

// Add after line 164 (after computing trial/grace days)
print("[SUBSCRIPTION] 📊 Computed Days Remaining:")
print("[SUBSCRIPTION]    - trialDaysRemaining: \(trialDaysRemaining?.description ?? "nil")")
print("[SUBSCRIPTION]    - graceDaysRemaining: \(graceDaysRemaining?.description ?? "nil")")
```

---

## Additional Issues Found in Console

### Issue 1: Calendar Sync - Nil ProjectID Warnings

**Severity**: Medium (Data Integrity)

**Pattern**: Multiple calendar events failing to convert from DTO with nil projectID

**Console Evidence**:
```
[SYNC_CALENDAR] ⚠️ Failed to convert DTO to model for event 1757106868986x707332498883870700
[SYNC_CALENDAR]    - ProjectID: nil
[SYNC_CALENDAR]    - TaskID: 1757106868986x627704676003872800
[SYNC_CALENDAR]    - Title: VINYL INSTALL

[SYNC_CALENDAR] ⚠️ Failed to convert DTO to model for event 1759941002258x501096483456024600
[SYNC_CALENDAR]    - ProjectID: nil
[SYNC_CALENDAR]    - TaskID: 1759941002258x624124640419381200
[SYNC_CALENDAR]    - Title: TEST TASK TYPE 2
```

**Analysis**:
- Events have valid taskID and companyID
- Events have projectID = nil in Bubble database
- This suggests either:
  1. Orphaned tasks (task exists but parent project deleted)
  2. Data integrity issue during task creation in Bubble
  3. Sync issue where projectID wasn't properly saved to Bubble

**Impact**:
- Calendar events for these tasks won't display in app
- Users may lose visibility into scheduled work
- Could affect reporting and team coordination

**Investigation Steps**:
1. Query Bubble directly for these taskIDs to verify projectID field
2. Check if these tasks appear in TaskListView (outside calendar context)
3. Add defensive null handling in calendar event conversion
4. Consider implementing orphaned task detection and cleanup

**Files to Review**:
- `/OPS/API/CalendarEventDTO.swift` - DTO conversion logic
- `/OPS/Managers/SyncManager.swift` - Calendar sync implementation
- `/OPS/DataModels/CalendarEvent.swift` - Model requirements

---

## Testing Plan

### Test Case 1: Grace Period Expiration
**Objective**: Verify app doesn't crash when grace period reaches 0 days

**Setup**:
1. Set company to grace status
2. Set seatGraceStartDate to 7 days ago
3. Open app

**Expected Behavior**:
- App loads without crash
- Console shows: `[SUBSCRIPTION] ⚠️ No grace period notifications to schedule (days remaining: 0)`
- Subscription status transitions appropriately

### Test Case 2: Trial Expiration
**Objective**: Verify app doesn't crash when trial period reaches 0 days

**Setup**:
1. Set company to trial status
2. Set trialEndDate to today or past date
3. Open app

**Expected Behavior**:
- App loads without crash
- Console shows: `[SUBSCRIPTION] ⚠️ No trial notifications to schedule (days remaining: 0)`
- User sees lockout screen if trial expired

### Test Case 3: Subscription Status Transitions
**Objective**: Verify all status transitions log properly

**Transitions to Test**:
- trial → expired
- trial → active
- active → grace
- grace → expired
- grace → active (payment updated)
- active → cancelled

**Expected Behavior**:
- All date fields logged at each transition
- No crashes during any transition
- Appropriate notifications scheduled/cancelled

### Test Case 4: Calendar Sync with Nil ProjectID
**Objective**: Handle orphaned tasks gracefully

**Setup**:
1. Create task in Bubble with nil projectID
2. Trigger calendar sync

**Expected Behavior**:
- Warning logged but no crash
- Event excluded from calendar display
- Consider flagging in UI as "orphaned task"

---

## Implementation Checklist

- [ ] Fix 1: Add guard clause to scheduleGracePeriodNotifications
- [ ] Fix 2: Add guard clause to scheduleTrialNotifications
- [ ] Fix 3: Add enhanced date/status logging to checkSubscriptionStatus
- [ ] Test Case 1: Grace period expiration
- [ ] Test Case 2: Trial expiration
- [ ] Test Case 3: All status transitions
- [ ] Test Case 4: Nil projectID handling
- [ ] Code review: Check for other range iterations that could fail
- [ ] Documentation: Update API_AND_SYNC.md with subscription state machine
- [ ] Monitoring: Add crash analytics for subscription-related errors

---

## Related Files

### Core Files
- `/OPS/Utilities/SubscriptionManager.swift` - Main subscription logic (lines 107-181, 398-515)
- `/OPS/DataModels/Company.swift` - Date calculations (lines 175-196)
- `/OPS/Utilities/SubscriptionEnums.swift` - Status and plan definitions

### Supporting Files
- `/OPS/Views/Subscription/SubscriptionLockoutView.swift` - Lockout UI
- `/OPS/Views/Subscription/GracePeriodBanner.swift` - Warning banner
- `/OPS/API/CompanyDTO.swift` - API data transfer

### Sync-Related Files (Secondary Issue)
- `/OPS/API/CalendarEventDTO.swift` - Event conversion logic
- `/OPS/Managers/SyncManager.swift` - Calendar sync
- `/OPS/DataModels/CalendarEvent.swift` - Event model

---

## Next Steps

1. **Immediate**: Apply Fix 1 (critical crash prevention)
2. **Immediate**: Apply Fix 2 (prevent similar crash)
3. **Short-term**: Add enhanced logging (Fix 3) for better diagnostics
4. **Short-term**: Run all test cases to verify fixes
5. **Medium-term**: Investigate calendar sync nil projectID issue
6. **Long-term**: Add comprehensive crash analytics and monitoring

---

## Critical Bug 2: Expired Trials Not Blocked - Subscription Check Never Runs

### Bug Description
Companies with `subscriptionStatus == "trial"` whose trials have expired (33+ days ago) still have full app access. The UI shows "Trial ends in (-33) days" but users are not locked out.

**Severity**: CRITICAL - Security/Business Logic Issue

### Root Cause Analysis ✅ CONFIRMED

**THE REAL PROBLEM**: `checkSubscriptionStatus()` is **NEVER CALLED** after login, so subscription validation never runs!

#### Evidence from Console Logs

**Expected logs after login**:
```
[SUBSCRIPTION] Checking subscription status...
[SUBSCRIPTION] 📊 Company Date Fields:
[SUBSCRIPTION]    - trialEndDate: ...
[SUBSCRIPTION]    - subscriptionStatus: trial
[AUTH] ❌ Access denied - trial expired
```

**Actual logs from CONSOLE.md**:
```
[LOGIN] 🔄 Starting full sync after login...
[SYNC_ALL] ✅ Complete sync finished
[LOGIN] ✅ Full sync completed successfully
[HOME] 🔄 Initial sync completed, reloading today's projects
```

**NO SUBSCRIPTION CHECK LOGS APPEAR!**

#### Why Subscription Check is Skipped

**Location**: `OPSApp.swift:145-153`

```swift
let hasMinimumData = healthManager.hasMinimumRequiredData()

if !hasMinimumData {
    print("[APP_ACTIVE] ⚠️ Minimum data requirements not met - skipping subscription check")
    return  // ❌ EXITS WITHOUT CHECKING SUBSCRIPTION
}

// Minimum data exists, check subscription
await subscriptionManager.checkSubscriptionStatus()
```

**Console shows** (line 8 in CONSOLE.md):
```
[APP_ACTIVE] ⚠️ Minimum data requirements not met - skipping subscription check
```

This means:
1. Data health check fails
2. Subscription check is skipped
3. `shouldShowLockout` is never updated
4. User gets full access regardless of subscription status

#### Additional Issues

**From Bubble Data**:
- `trialEndDate`: 10/20/2025 03:51 pm (expired 34 days ago)
- `subscriptionStatus`: "trial" (should be "expired")
- Bubble's recurring workflow to expire trials is NOT running or failing

**UI Display Bug** (Secondary):
**Location**: `OrganizationSettingsView.swift:293`
Shows "Trial ends in (-33) days" instead of "Trial expired"

### Part 3: UI Display Bug
**Location**: `OrganizationSettingsView.swift:293`

**Current Code**:
```swift
let days = Calendar.current.dateComponents([.day], from: Date(), to: trialEnd).day ?? 0
Text("Trial ends in \(days) days")
```

**Issue**: This computes days directly without clamping, showing "Trial ends in (-33) days"

**Fix Needed**:
```swift
let days = Calendar.current.dateComponents([.day], from: Date(), to: trialEnd).day ?? 0
if days > 0 {
    Text("Trial ends in \(days) days")
} else {
    Text("Trial expired")
}
```

---

## Questions for Product/Business

1. **Grace Period Behavior**: What should happen when grace period expires?
   - Should app immediately lock out?
   - Should we show a "contact us" screen?
   - Should we allow read-only access?

2. **Trial Period Behavior**: What should happen when trial expires?
   - Immediate lockout?
   - Convert to limited free tier?
   - Extended grace period?

3. **Orphaned Tasks**: Tasks with nil projectID
   - Should we auto-delete these?
   - Should we prevent creation in UI?
   - Should we show in a "needs attention" section?

4. **Notification Strategy**: Current approach schedules all notifications upfront
   - Should we use recurring daily checks instead?
   - Should we batch notifications differently?
   - What about timezone considerations?

5. **Bubble Workflow Status**: Is the "Expire trial subscriptions" workflow running?
   - Check Bubble logs for this workflow
   - Verify it's scheduled to run daily
   - Check if it's encountering errors
