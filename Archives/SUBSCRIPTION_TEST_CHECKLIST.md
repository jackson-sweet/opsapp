# Subscription Testing Checklist

## ✅ Setup Complete
- Bubble workflows configured
- Client secret retrieval working
- iOS code updated to handle response

## Testing Steps

### 1. Test New Subscription Creation

#### Prerequisites:
- [ ] Use a test user WITHOUT existing subscription
- [ ] Clear app data if needed (delete and reinstall)
- [ ] Ensure using Stripe TEST mode

#### Test Flow:
1. **Launch app** 
   - Should see trial status or expired state

2. **Navigate to subscription**
   - Go to Organization Settings → Subscription → Change Plan
   - OR if locked out, tap "Choose Plan"

3. **Select a plan**
   - Choose Starter/Team/Business
   - Toggle between Monthly/Annual
   - Verify pricing updates correctly

4. **Initiate payment**
   - Tap "Continue with Apple Pay"
   - Should see debug log: "📱 Bubble Response: ..."

5. **Verify response contains**:
   ```json
   {
     "status": "success",
     "subscription_id": "sub_xxx",
     "payment_intent_client_secret": "pi_xxx_secret_xxx",
     "ephemeral_key": "ek_xxx",
     "customer_id": "cus_xxx"
   }
   ```

### 2. Payment Sheet Presentation

#### Expected Behavior:
- [ ] Stripe PaymentSheet appears
- [ ] Shows selected plan price
- [ ] Apple Pay available (if configured)
- [ ] Card input form available

#### Test Card Numbers:
- **Success**: `4242 4242 4242 4242`
- **Requires Auth**: `4000 0025 0000 3155`
- **Decline**: `4000 0000 0000 0002`

### 3. Complete Payment

#### Steps:
1. Enter test card: `4242 4242 4242 4242`
2. Any future expiry (e.g., 12/34)
3. Any CVC (e.g., 123)
4. Any ZIP (e.g., 12345)
5. Tap "Pay"

#### Verify:
- [ ] Payment processes successfully
- [ ] PaymentSheet dismisses
- [ ] App refreshes subscription status
- [ ] Lockout screen (if shown) disappears
- [ ] Home header shows active plan

### 4. Post-Payment Verification

#### Check UI Updates:
- [ ] Home header shows subscription badge
- [ ] Organization Settings shows correct plan
- [ ] Seat count is accurate
- [ ] No grace period warnings

#### Check Data Sync:
- [ ] Company object has updated subscription fields
- [ ] Bubble dashboard shows active subscription
- [ ] Stripe dashboard shows successful payment

## Troubleshooting

### Payment Sheet Not Appearing

1. **Check console logs for**:
   - Missing client_secret
   - Invalid ephemeral_key
   - Network errors

2. **Verify in response**:
   - `payment_intent_client_secret` is not null
   - Starts with `pi_` and contains `_secret_`
   - Ephemeral key is present

### Payment Fails

1. **Check Stripe Dashboard**:
   - Look for failed payment attempts
   - Check for API errors
   - Verify webhook delivery

2. **Common issues**:
   - Customer already has payment method (subscription auto-paid)
   - Invoice already paid
   - Subscription not in "incomplete" state

### Status Not Updating

1. **Force refresh**:
   - Pull to refresh on home screen
   - Background and foreground app
   - Check Settings → Organization → Subscription

2. **Check Bubble**:
   - Verify webhook is configured
   - Check Company record updated
   - Look for sync errors

## Debug Commands

In Xcode console while app is running:

```swift
// Force subscription check
po subscriptionManager.checkSubscriptionStatus()

// Check current status
po dataController.getCompany()?.subscriptionStatus

// View cached data
po dataController.getCompany()?.subscriptionPlan
```

## Success Criteria

- [ ] Can create new subscription from iOS
- [ ] Payment collected successfully
- [ ] Subscription status updates immediately
- [ ] User can access app features
- [ ] Seat management works correctly

## Next Steps After Testing

1. **Test edge cases**:
   - Network interruption during payment
   - App backgrounding during payment
   - Multiple plan changes
   - Seat limit scenarios

2. **Production readiness**:
   - Switch to live Stripe keys
   - Test with real cards
   - Verify webhook security
   - Monitor error rates