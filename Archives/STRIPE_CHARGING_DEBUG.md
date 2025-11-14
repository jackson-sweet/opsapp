# Stripe Payment Not Charging - Debug Guide

## Current Flow Issues

### What's Happening Now:
1. **SetupIntent Created** ✅ - Saves payment method for future use
2. **Payment Method Confirmed** ✅ - Card is validated and attached to customer
3. **Subscription Creation** ❌ - Not automatically charging the card

### The Problem:
SetupIntents are designed to **save payment methods** for future charges, not to charge immediately. After confirming a SetupIntent:
- The payment method is saved to the customer
- No charge is created
- The subscription needs to be created to trigger the first charge

## Required Fix in Bubble `complete_subscription` Workflow

### Step 1: Retrieve the SetupIntent (if provided)
```javascript
// If setup_intent_id is provided
const setupIntent = await stripe.setupIntents.retrieve(setup_intent_id);
const paymentMethodId = setupIntent.payment_method;
```

### Step 2: Set Default Payment Method
```javascript
// Attach the payment method as the customer's default
await stripe.customers.update(customer_id, {
  invoice_settings: {
    default_payment_method: paymentMethodId
  }
});
```

### Step 3: Create the Subscription
```javascript
const subscription = await stripe.subscriptions.create({
  customer: customer_id,
  items: [{ price: price_id }],
  default_payment_method: paymentMethodId,
  payment_behavior: 'default_incomplete', // Will attempt to charge immediately
  expand: ['latest_invoice.payment_intent']
});
```

### Step 4: Check Payment Status
```javascript
// The subscription's first invoice will be created and charged
if (subscription.latest_invoice.payment_intent) {
  const paymentIntent = subscription.latest_invoice.payment_intent;
  
  if (paymentIntent.status === 'succeeded') {
    // Payment successful
    return { 
      subscription_id: subscription.id,
      subscription_active: true,
      payment_status: 'succeeded'
    };
  } else if (paymentIntent.status === 'requires_payment_method') {
    // Payment failed - need to handle
    return {
      subscription_id: subscription.id,
      subscription_active: false,
      payment_status: 'failed',
      error: 'Payment method declined'
    };
  }
}
```

## Quick Debug Steps

1. **Check Stripe Dashboard**:
   - Go to Customers → Find the customer
   - Check if payment method is attached
   - Check if subscription exists
   - Check if any invoices were created
   - Check if any payment intents were created

2. **Add Console Logging** in the app:
   ```swift
   // In completeSubscriptionAfterPayment
   print("🔄 COMPLETING SUBSCRIPTION:")
   print("  - Setup Intent ID: \(setupIntentId ?? "nil")")
   print("  - Price ID: \(priceId)")
   print("  - Company ID: \(companyId)")
   ```

3. **Check Bubble Workflow**:
   - Verify `complete_subscription` creates a Stripe Subscription
   - Check if it's using the correct price_id
   - Verify it's setting the payment method on the subscription

## Alternative: Use PaymentIntent Instead

If immediate charging is needed, consider using PaymentIntent instead of SetupIntent:

### Option 1: Subscription with Trial
Create subscription with a trial period, then charge immediately when trial ends.

### Option 2: PaymentIntent + Subscription
1. Create a PaymentIntent for the first payment
2. After successful payment, create the subscription
3. Set the subscription to start from the next billing period

### Option 3: Subscription with Immediate Invoice
```javascript
const subscription = await stripe.subscriptions.create({
  customer: customer_id,
  items: [{ price: price_id }],
  default_payment_method: payment_method_id,
  payment_behavior: 'default_incomplete',
  payment_settings: {
    payment_method_types: ['card'],
    save_default_payment_method: 'on_subscription'
  },
  expand: ['latest_invoice.payment_intent']
});

// The subscription will create an invoice immediately
// and attempt to charge the default payment method
```

## Testing the Fix

1. **Test with a new customer** to ensure clean state
2. **Use Stripe test cards**:
   - `4242 4242 4242 4242` - Always succeeds
   - `4000 0000 0000 0002` - Always declines
3. **Check webhook logs** in Stripe Dashboard
4. **Monitor the Bubble server logs** for any errors

## Key Points
- SetupIntent = Save card for future use (no immediate charge)
- PaymentIntent = Charge immediately
- Subscription creation = Will charge based on billing cycle
- First subscription invoice = Should charge immediately if configured correctly