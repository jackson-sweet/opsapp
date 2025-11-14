# Subscription System Testing Guide

## Quick Test Scenarios

### 1. Test Trial Expiry
In `SubscriptionManager.swift`, temporarily modify line ~156:
```swift
// Change this:
if let daysRemaining = trialDaysRemaining, daysRemaining <= 0 {

// To this for testing:
if true { // Force expired trial
```

### 2. Test Grace Period Banner
In `Company.swift`, add to test grace period:
```swift
var shouldShowGracePeriodWarning: Bool {
    return true // Force show grace period banner
}
```

### 3. Test No Seats Available
Modify `Company.swift`:
```swift
var seatedEmployeeIds: String {
    // Add more IDs than maxSeats to trigger no seats
}
```

## Test Payment with Stripe

### Test Cards:
- **Success**: 4242 4242 4242 4242
- **Decline**: 4000 0000 0000 0002
- **Requires Authentication**: 4000 0025 0000 3155

### Test Flow:
1. Open Settings → Organization
2. Tap "Change Plan" or "Choose a Plan"
3. Select a plan (Starter/Team/Business)
4. Toggle Monthly/Annual
5. Tap "Continue with Apple Pay"
6. Enter test card details
7. Verify subscription activates

## Test Seat Management (Admin Only)

1. Go to Settings → Organization → Manage Seats
2. You should see:
   - Current seat usage (e.g., "2 of 3 seats used")
   - List of team members with toggles
   - Upgrade prompt if at capacity

## Verify Sync with Bubble

1. Make a subscription change
2. Check Bubble database to verify:
   - Company.subscription_status updated
   - Company.subscription_plan updated
   - Company.stripe_customer_id created
   - Company.stripe_subscription_id created

## Expected Behaviors

### For Admins:
- Can change plans
- Can manage seats
- See payment options
- Get trial/grace warnings

### For Non-Admins:
- Cannot change plans
- Cannot manage seats  
- See "Contact Admin" messages
- Get locked out if no seat

### Trial Users:
- 30-day countdown
- Full access during trial
- Lockout after expiry
- Prompted to choose plan

### Grace Period:
- 7-day grace for payment issues
- Yellow banner at top
- Limited functionality
- Daily notifications

## Debug Tips

Enable console logging to see subscription state:
```swift
print("🔔 Subscription Status: \(subscriptionManager.subscriptionStatus)")
print("🔔 Has Seat: \(subscriptionManager.userHasSeat)")
print("🔔 Should Lockout: \(subscriptionManager.shouldShowLockout)")
```