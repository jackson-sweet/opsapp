# Subscription System Testing Guide

## Overview
The subscription system is now fully integrated with Stripe payment processing. This guide walks through testing the complete payment flow.

## Implementation Summary

### 1. Data Models
- **Company**: Added subscription fields (status, plan, seats, Stripe IDs)
- **User**: Added subscription-related permissions
- **DTOs**: Updated to sync subscription data from Bubble

### 2. Core Components
- **SubscriptionManager**: Central coordinator for subscription state
- **SubscriptionLockoutView**: Full-screen paywall for expired subscriptions
- **GracePeriodBanner**: Warning banner for grace period
- **PlanSelectionView**: Plan selection and payment UI
- **SeatManagementView**: Admin interface for managing team seats

### 3. Stripe Integration
- **StripeConfiguration**: SDK setup with test/production keys
- **BubbleSubscriptionService**: Communication with Bubble backend
- **PaymentSheet**: Native iOS payment collection

### 4. UI Updates
- **Home Header**: Shows subscription status badge
- **Organization Settings**: Subscription management section
- **ContentView**: Integrated lockout and grace period UI

## Testing Steps

### 1. Initial Setup
1. Ensure Stripe SDK is installed via Swift Package Manager
2. Verify test keys are configured in StripeConfiguration.swift
3. Check that Bubble workflows are deployed (see BUBBLE_WEBHOOK_SETUP.md)

### 2. Test Subscription States

#### Trial State
1. Create new account (should start in trial)
2. Verify home header shows "TRIAL • X DAYS LEFT"
3. Check that app is fully accessible
4. Navigate to Organization Settings → Subscription
5. Verify trial countdown is displayed

#### Expired State
1. Set company.subscriptionStatus to "expired" in debug
2. Force close and reopen app
3. Verify lockout screen appears immediately
4. Check that only admin users see "Choose Plan" button
5. Non-admin users should see "Contact Admin" message

#### Grace Period
1. Set company.subscriptionStatus to "grace"
2. Set company.gracePeriodEndsAt to future date
3. Verify grace period banner appears at top of app
4. Check that banner is non-dismissible
5. Verify countdown shows correct days remaining

### 3. Test Payment Flow

#### Plan Selection
1. As admin, tap "Choose Plan" from lockout or settings
2. Verify plan cards show correct pricing
3. Toggle between monthly/annual billing
4. Verify price updates correctly
5. Select a plan and tap "Continue with Apple Pay"

#### Payment Collection
1. Verify Stripe PaymentSheet appears
2. Use test card: 4242 4242 4242 4242
3. Complete payment
4. Verify app refreshes subscription status
5. Check that lockout is removed

### 4. Test Seat Management

#### View Current Seats
1. Navigate to Organization Settings → Subscription
2. Tap "Manage Seats"
3. Verify current seat usage is displayed
4. Check visual indicator shows correct proportion

#### Modify Seats
1. Toggle team members on/off
2. Verify available seats updates correctly
3. Try to exceed seat limit
4. Verify upgrade prompt appears when limit reached
5. Save changes and verify sync

### 5. Test Webhook Handling

#### Subscription Events
1. Use Stripe CLI to send test webhooks
2. Test subscription.created event
3. Test invoice.payment_succeeded event
4. Test invoice.payment_failed event
5. Verify app state updates accordingly

## Test Card Numbers

### Successful Payment
- **Number**: 4242 4242 4242 4242
- **Expiry**: Any future date
- **CVC**: Any 3 digits

### Declined Payment
- **Number**: 4000 0000 0000 0002
- **Result**: Card declined

### Insufficient Funds
- **Number**: 4000 0000 0000 9995
- **Result**: Insufficient funds

## Monitoring

### Console Logs
Enable debug logging to see:
- Subscription status checks
- Payment flow progress
- API communication
- Webhook processing

### Debug Commands
```swift
// Force subscription check
subscriptionManager.checkSubscriptionStatus()

// Simulate expired state
dataController.getCompany()?.subscriptionStatus = "expired"

// Clear cached status
subscriptionManager.clearCache()
```

## Common Issues

### Payment Sheet Not Appearing
1. Check Stripe publishable key is set
2. Verify StripeConfiguration.configure() is called
3. Check network connectivity
4. Ensure customer ID exists

### Subscription Not Updating
1. Verify Bubble webhooks are configured
2. Check webhook endpoint is accessible
3. Verify Stripe webhook signature
4. Check Bubble workflow logs

### Seat Management Not Saving
1. Ensure user has admin role
2. Check company sync is enabled
3. Verify API endpoint is responding
4. Check for sync conflicts

## Next Steps

1. **Production Setup**:
   - Replace test Stripe keys with live keys
   - Update Bubble webhook URLs
   - Configure production merchant ID
   - Set up monitoring alerts

2. **Additional Features**:
   - Invoice history view
   - Payment method management
   - Subscription cancellation flow
   - Usage-based billing

3. **Analytics**:
   - Track conversion funnel
   - Monitor churn reasons
   - Analyze plan distribution
   - Track payment failures

## Support

For issues or questions:
- Check Stripe Dashboard for payment logs
- Review Bubble workflow history
- Enable verbose logging in app
- Contact support with subscription ID