# Subscription & Authentication Bugs Found
**Date**: January 23, 2025
**Testing Session**: Manual Testing & Console Analysis

---

## Critical Bugs (Must Fix Immediately)

### 🔴 Bug #1: Subscription Check Never Runs After Login
**Severity**: CRITICAL - Security Issue
**Status**: Newly Discovered ✅

**Description**:
`checkSubscriptionStatus()` is never called after login, allowing users with expired subscriptions to access the app.

**Root Cause**:
- In `OPSApp.swift:145-153`, subscription check is gated behind data health check
- Data health check fails with: `"Minimum data requirements not met"`
- Subscription check is skipped entirely
- Console line 8: `[APP_ACTIVE] ⚠️ Minimum data requirements not met - skipping subscription check`

**Impact**:
- Users with expired trials get full app access
- Users without seats get full app access
- Subscription status is never validated
- Grace period warnings never appear
- Lockout screen never shows

**Evidence**:
- Console logs show NO `[SUBSCRIPTION]` checks after login
- User with trial expired 34 days ago can access everything
- No auth validation occurs

**Files Involved**:
- `OPSApp.swift:145-153` - Subscription check skipped
- `DataHealthManager.swift` - Failing health check

**Proposed Fix**:
1. **Option A**: Fix data health check to pass when company data exists
2. **Option B**: Remove health check gate, always run subscription check after login
3. **Option C**: Add subscription check directly in login flow (before/during sync)

**Recommended**: Option B - Subscription validation should ALWAYS run, regardless of other data

---

### 🔴 Bug #2: Bubble Not Expiring Trial Subscriptions
**Severity**: CRITICAL - Backend Issue
**Status**: Confirmed ✅

**Description**:
Bubble database shows companies with expired trials still have `subscriptionStatus: "trial"` instead of "expired"

**Evidence**:
- Company: Valorant Construction (ID: 1758408703226x689360897862778100)
- `trialEndDate`: 2025-10-20T22:51:44.011Z (expired October 20, 2025 - 34 days ago)
- `subscriptionStatus`: "trial" (should be "expired")
- Current date: November 23, 2025

**Root Cause**:
Bubble's recurring workflow to transition expired trials is either:
1. Not running
2. Failing silently
3. Not configured correctly
4. Disabled

**Impact**:
- Even if iOS app's subscription check worked, backend data is wrong
- Multi-layer failure allowing unauthorized access

**Investigation Needed**:
- [ ] Check Bubble workflows for "Expire trial subscriptions"
- [ ] Check Bubble logs for workflow execution
- [ ] Verify workflow schedule (should be daily)
- [ ] Check workflow conditions and filters
- [ ] Test workflow manually in Bubble

**Proposed Fix**:
1. Enable/fix Bubble recurring workflow
2. Manually update expired trials in database
3. Add iOS defensive check (even if Bubble fails)

---

## High Priority Bugs

### 🟠 Bug #3: Grace Period Notification Crash (FIXED ✅)
**Severity**: HIGH - Crash Bug
**Status**: Fixed in previous session

**Description**:
App crashed with `Fatal error: Range requires lowerBound <= upperBound` when grace period reached 0 days.

**Fix Applied**:
Added guard clause in `SubscriptionManager.swift:459-472`:
```swift
guard daysRemaining > 0 else {
    print("[SUBSCRIPTION] ⚠️ No grace period notifications to schedule")
    return
}
```

**Testing Status**: Needs verification with grace period = 0 scenario

---

### 🟠 Bug #4: Trial Notification Crash (FIXED ✅)
**Severity**: HIGH - Crash Bug
**Status**: Fixed in previous session

**Description**:
App could crash when trial period reached 0 days (same range error as grace period).

**Fix Applied**:
Added guard clause in `SubscriptionManager.swift:441-457`

**Testing Status**: Needs verification with trial = 0 scenario

---

### 🟠 Bug #5: Negative Days Display in UI
**Severity**: MEDIUM - UX Issue
**Status**: Confirmed ✅

**Description**:
Organization Settings shows "Trial ends in (-33) days" instead of "Trial expired"

**Location**: `OrganizationSettingsView.swift:293`

**Current Code**:
```swift
let days = Calendar.current.dateComponents([.day], from: Date(), to: trialEnd).day ?? 0
Text("Trial ends in \(days) days")
```

**Proposed Fix**:
```swift
let days = Calendar.current.dateComponents([.day], from: Date(), to: trialEnd).day ?? 0
if days > 0 {
    Text("Trial ends in \(days) days")
        .font(OPSStyle.Typography.smallCaption)
        .foregroundColor(OPSStyle.Colors.primaryAccent)
} else if days == 0 {
    Text("Trial expires today")
        .font(OPSStyle.Typography.smallCaption)
        .foregroundColor(OPSStyle.Colors.warningStatus)
} else {
    Text("Trial expired")
        .font(OPSStyle.Typography.smallCaption)
        .foregroundColor(OPSStyle.Colors.errorStatus)
}
```

---

## Medium Priority Issues

### 🟡 Issue #1: Data Health Check Too Strict
**Severity**: MEDIUM - Blocks Critical Features
**Status**: Under Investigation

**Description**:
Data health check fails even when company data exists, blocking subscription validation

**Evidence**:
- Console shows company data successfully synced
- Health check still reports "Minimum data requirements not met"
- Unclear what criteria health check is using

**Investigation Needed**:
- [ ] Review `DataHealthManager.hasMinimumRequiredData()` implementation
- [ ] Determine what "minimum data" is required
- [ ] Check if criteria makes sense for subscription validation

---

### 🟡 Issue #2: "TRIAL ENDING" Badge Shows for Expired Trials
**Severity**: MEDIUM - UX Confusion
**Status**: Reported

**Description**:
Home tab header shows "TRIAL ENDING" badge even when trial expired 34 days ago

**Expected**:
- Should show "TRIAL EXPIRED" or no badge at all
- Should trigger lockout screen

**Current Behavior**:
- Shows "TRIAL ENDING" (misleading)
- No lockout occurs

**Note**: This is a symptom of Bug #1 (subscription check not running)

---

### 🟡 Issue #3: seatGraceStartDate Set for Trial Company
**Severity**: LOW - Data Inconsistency
**Status**: Needs Clarification

**Description**:
Company with `subscriptionStatus: "trial"` has `seatGraceStartDate: 10/23/2025 12:24 pm` set

**Questions**:
1. Should trial companies have grace period dates?
2. Is this a data migration artifact?
3. Does this affect any logic?

**From Bubble**:
- `subscriptionStatus`: "trial"
- `seatGraceStartDate`: 2025-10-23T19:24:05.279Z
- `trialEndDate`: 2025-10-20T22:51:44.011Z

**Possible Scenarios**:
- Trial expired, transitioned to grace (but status not updated to "grace")
- Manual data entry error
- Previous payment attempt failed

---

## Testing Summary

### Tests Completed ✅
1. Login with expired trial account
2. Console log analysis
3. Bubble database inspection
4. UI display verification

### Tests Needed ⏳
1. Fix Bug #1, then re-test subscription validation
2. Verify Bubble workflow status
3. Test grace period expiration (days = 0)
4. Test trial expiration (days = 0)
5. Test all subscription status transitions
6. Test seat management edge cases

---

## Immediate Action Items

### Priority 1 (Must Do Today)
1. **Fix Bug #1**: Ensure subscription check runs after login
   - Remove data health gate OR fix health check
   - Verify subscription logs appear in console
   - Confirm expired trials get locked out

2. **Investigate Bubble Workflow**: Why aren't trials expiring?
   - Check workflow configuration
   - Review workflow logs
   - Manually trigger if needed

### Priority 2 (This Week)
3. Fix Bug #5: Negative days display
4. Test grace period & trial notification scheduling
5. Verify all status transitions work correctly

### Priority 3 (Nice to Have)
6. Investigate data health check strictness
7. Clean up inconsistent Bubble data
8. Add comprehensive subscription logging

---

## Questions for Product Team

1. **Data Health Check**: Should subscription validation be gated behind data health check, or should it always run?

2. **Grace Period for Trials**: Is it intentional that trial companies can have `seatGraceStartDate` set?

3. **Expired Trial Behavior**: What should happen when trial expires?
   - Immediate lockout?
   - Transition to grace period?
   - Transition to limited free tier?

4. **Bubble Workflow**: When was the "Expire trial subscriptions" workflow last verified to work?

5. **Notification Strategy**: Current approach schedules all notifications upfront. Should we use recurring daily checks instead?

---

## Related Files

### Critical Files
- `OPSApp.swift` - App lifecycle, subscription check gating
- `SubscriptionManager.swift` - Subscription validation logic
- `DataHealthManager.swift` - Data health check implementation
- `Company.swift` - Trial/grace period calculations
- `OrganizationSettingsView.swift` - UI display

### Bubble Files
- Company data type
- "Expire trial subscriptions" workflow (or equivalent)
- Subscription status option set

### Documentation
- `SUBSCRIPTION_BUG_REPORT.md` - Detailed technical analysis
- `TESTING_PLAN.md` - Comprehensive test scenarios
- `CONSOLE.md` - Raw console output from testing
