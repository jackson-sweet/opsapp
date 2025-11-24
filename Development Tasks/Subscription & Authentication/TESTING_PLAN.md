# Subscription & Authentication Testing Plan
**Date Created**: January 23, 2025
**Status**: Ready for Testing

## Overview
This document outlines the manual tests needed to identify subscription and authentication bugs. We are NOT writing code, just running tests to document issues.

---

## Test 1: Expired Trial Status Bug

### Current Issue
Companies with `subscriptionStatus == "trial"` showing "Trial ends in (-33) days" but still have full app access.

### Test Steps
1. **Login** as a user from a company with expired trial
2. **Observe** the app behavior:
   - Does the app load normally?
   - Can you access all features (Job Board, Calendar, etc.)?
   - Do you see a lockout screen?

3. **Check Console Output** for these logs:
   ```
   [SUBSCRIPTION] 📊 Company Date Fields:
   [SUBSCRIPTION]    - trialStartDate: [RECORD THIS]
   [SUBSCRIPTION]    - trialEndDate: [RECORD THIS]
   [SUBSCRIPTION]    - subscriptionStatus: [RECORD THIS]
   [SUBSCRIPTION]    - subscriptionPlan: [RECORD THIS]

   [SUBSCRIPTION] 📊 Computed Days Remaining:
   [SUBSCRIPTION]    - trialDaysRemaining: [RECORD THIS]

   [AUTH] [RECORD ALL AUTH LOGS]
   ```

4. **Navigate to Settings** → Organization
   - What does the subscription card show?
   - Record the exact text displayed

### Expected Behavior
- If `trialDaysRemaining == 0` and status is "trial", should show lockout screen
- Console should show: `[AUTH] ❌ Access denied - trial expired`

### Questions to Answer
- [ ] What is the actual `trialEndDate` from console?
- [ ] What is `trialDaysRemaining` computed value?
- [ ] What auth decision logs appear?
- [ ] Is lockout screen shown?
- [ ] What does Bubble database show for this company's `subscriptionStatus`?

---

## Test 2: Grace Period Expiration

### Objective
Verify behavior when grace period reaches 0 days.

### Setup
Find or create a company with:
- `subscriptionStatus == "grace"`
- `seatGraceStartDate` set to 7+ days ago

### Test Steps
1. **Login** as user from grace period company
2. **Record console output** for:
   ```
   [SUBSCRIPTION] 📊 Company Date Fields:
   [SUBSCRIPTION]    - seatGraceStartDate: [RECORD THIS]
   [SUBSCRIPTION]    - subscriptionStatus: grace

   [SUBSCRIPTION] 📊 Computed Days Remaining:
   [SUBSCRIPTION]    - graceDaysRemaining: [RECORD THIS]
   ```

3. **Check app behavior**:
   - Does grace period banner show?
   - What does banner text say?
   - Can you still access features?

### Questions to Answer
- [ ] What is `graceDaysRemaining` value?
- [ ] Is banner shown when days = 0?
- [ ] What happens when grace period expires?
- [ ] Does Bubble transition status to "expired"?

---

## Test 3: Seat Management Edge Cases

### Test 3A: User Without Seat (Active Subscription)
**Setup**: Company with `subscriptionStatus == "active"`, user NOT in `seatedEmployeeIds`

**Test Steps**:
1. Login as unseated user
2. Record console: `[AUTH]` logs
3. Verify: Should see lockout screen

**Expected**: `[AUTH] ❌ Access denied - no seat available`

### Test 3B: Admin Without Seat
**Setup**: Company with active subscription, admin user NOT seated

**Test Steps**:
1. Login as unseated admin
2. Record console: `[AUTH]` logs
3. Check if different message appears

**Expected**: `[AUTH] ❌ Access denied - admin user has no seat`

### Test 3C: Exceeded Seat Count
**Setup**: Company with `maxSeats: 3` but 4 users in `seatedEmployeeIds`

**Test Steps**:
1. Login as 4th user
2. Record console: `[AUTH]` logs

**Expected**: `[AUTH] ❌ LAYER 4 FAILED: Seated employees (4) exceed maxSeats (3)`

---

## Test 4: Subscription Status Transitions

### Objective
Test all possible status transitions and verify correct behavior.

### Test 4A: Trial → Active (Payment Successful)
**Simulate**: User upgrades from trial to paid plan

**Monitor**:
- [ ] Bubble updates `subscriptionStatus` to "active"
- [ ] Bubble sets `subscriptionPlan` to chosen plan
- [ ] App updates immediately (or after sync)
- [ ] Trial banner disappears

### Test 4B: Active → Grace (Payment Failed)
**Simulate**: Active subscription payment fails

**Monitor**:
- [ ] Bubble sets `subscriptionStatus` to "grace"
- [ ] Bubble sets `seatGraceStartDate` to current date
- [ ] App shows grace period banner
- [ ] Console shows grace days remaining

### Test 4C: Grace → Expired (Grace Period Ends)
**Simulate**: Grace period expires without payment

**Monitor**:
- [ ] Bubble transitions to "expired" status
- [ ] App shows lockout screen
- [ ] Users cannot access features

### Test 4D: Grace → Active (Payment Recovered)
**Simulate**: User updates payment during grace period

**Monitor**:
- [ ] Status returns to "active"
- [ ] Grace banner disappears
- [ ] Full access restored

### Test 4E: Trial → Expired (Trial Ends, No Payment)
**Simulate**: Trial ends without upgrade

**Monitor**:
- [ ] Bubble transitions from "trial" to "expired"
- [ ] App shows lockout screen
- [ ] Trial banner removed

---

## Test 5: Bubble Workflow Verification

### Objective
Verify Bubble's backend workflows are running correctly.

### Workflows to Check
1. **Expire Trial Subscriptions**
   - Schedule: Daily
   - Action: Set `subscriptionStatus = "expired"` where `trialEndDate < current date`
   - Check: Bubble logs for execution

2. **Expire Grace Periods**
   - Schedule: Daily
   - Action: Set `subscriptionStatus = "expired"` where grace period ended
   - Check: Bubble logs for execution

3. **Update Subscription from Stripe**
   - Trigger: Stripe webhook events
   - Actions: Update status, plan, payment info
   - Check: Webhook logs in Bubble

### Questions to Answer
- [ ] Are these workflows enabled in Bubble?
- [ ] When did they last run successfully?
- [ ] Are there any error logs?
- [ ] What companies are currently in "trial" status past their end date?

---

## Test 6: UI Display Bugs

### Test 6A: Negative Days Display
**Location**: Settings → Organization → Subscription Card

**Test**:
1. Find expired trial company
2. Check subscription card text
3. Record exact text shown

**Current Bug**: Shows "Trial ends in (-33) days"
**Expected**: Should show "Trial expired" or hide when expired

### Test 6B: Grace Period Display
**Location**: Home screen banner

**Test**:
1. Login as grace period user
2. Check banner appearance
3. Record text shown

**Questions**:
- [ ] Does banner show when `graceDaysRemaining == 0`?
- [ ] What text is displayed?
- [ ] Is the styling correct (warning colors)?

---

## Test 7: Notification Scheduling

### Objective
Verify subscription-related notifications are scheduled correctly.

### Test Steps
1. **Login** as trial user with various days remaining
2. **Check console** for notification scheduling:
   ```
   [SUBSCRIPTION] 📅 Scheduling trial notifications (days remaining: X)
   [SUBSCRIPTION] 📅 Scheduling X grace period notification(s)
   ```

3. **Test cases**:
   - Trial: 14 days remaining → Notifications at 7, 3, 1 days
   - Trial: 2 days remaining → Only 1-day notification
   - Trial: 0 days remaining → No crash, warning logged
   - Grace: 7 days → Daily notifications
   - Grace: 0 days → No crash, warning logged

### Questions to Answer
- [ ] Are notifications scheduled without crashing?
- [ ] Are notifications delivered at correct times?
- [ ] What happens when days = 0?

---

## Test 8: Stripe Payment Integration

### Test 8A: Successful Payment
**Test**:
1. Select a plan in subscription view
2. Complete payment in Stripe sheet
3. Observe app behavior

**Monitor**:
- [ ] Stripe sheet closes on success
- [ ] App syncs with Bubble
- [ ] Status updates to "active"
- [ ] Success message shown

### Test 8B: Failed Payment
**Test**:
1. Use test card that fails (4000 0000 0000 0002)
2. Attempt payment
3. Observe error handling

**Monitor**:
- [ ] Error message displayed
- [ ] Status remains unchanged
- [ ] User can retry

### Test 8C: Cancelled Payment
**Test**:
1. Start payment flow
2. Cancel Stripe sheet
3. Check app state

**Monitor**:
- [ ] Sheet closes gracefully
- [ ] No status changes
- [ ] User returned to subscription view

---

## Test 9: Multi-User Scenarios

### Test 9A: Seat Assignment While User Online
**Setup**: Two users logged in from same company

**Test**:
1. Admin adds seat for User B
2. User B's app should update
3. Verify access granted

### Test 9B: Seat Removal While User Online
**Setup**: Seated user actively using app

**Test**:
1. Admin removes user's seat
2. User's app should detect change
3. Verify lockout occurs

### Test 9C: Subscription Downgrade
**Setup**: Company with 5 users on Business plan (10 seats)

**Test**:
1. Admin downgrades to Starter (3 seats)
2. Only 3 users are seated
3. Other 2 users get lockout screen

---

## Test 10: Offline Behavior

### Test 10A: Subscription Check Offline
**Test**:
1. Login while online (active subscription)
2. Turn off internet
3. Force quit and reopen app

**Expected**: App uses cached subscription data, allows access

### Test 10B: Status Change While Offline
**Test**:
1. Admin changes subscription in Bubble
2. User's device is offline
3. User opens app

**Expected**: App uses last known status until next sync

---

## Testing Checklist

### Critical Issues (Test First)
- [ ] Test 1: Expired trial status bug
- [ ] Test 2: Grace period expiration
- [ ] Test 4E: Trial → Expired transition
- [ ] Test 5: Bubble workflow verification

### High Priority
- [ ] Test 3: Seat management edge cases
- [ ] Test 6: UI display bugs
- [ ] Test 7: Notification scheduling
- [ ] Test 8: Stripe integration

### Medium Priority
- [ ] Test 4: All status transitions
- [ ] Test 9: Multi-user scenarios
- [ ] Test 10: Offline behavior

---

## Bug Report Template

For each bug found, document:

```markdown
### Bug: [Short Description]

**Severity**: Critical / High / Medium / Low

**Steps to Reproduce**:
1.
2.
3.

**Expected Behavior**:
[What should happen]

**Actual Behavior**:
[What actually happens]

**Console Logs**:
```
[Paste relevant logs]
```

**Screenshots**:
[If applicable]

**Environment**:
- iOS Version:
- Device:
- Build:

**Root Cause** (if known):
[Analysis]

**Proposed Fix**:
[Solution]
```

---

## Results Summary

### Issues Found
1. **Expired Trial Access** - Status: Under Investigation
2. **Negative Days Display** - Status: Documented
3. **Grace Period Crash** - Status: Fixed ✅
4. **Trial Notification Crash** - Status: Fixed ✅

### Next Steps
1. Complete Test 1 (Expired Trial) with console logs
2. Verify Bubble workflow status (Test 5)
3. Test all status transitions (Test 4)
4. Document additional bugs found
