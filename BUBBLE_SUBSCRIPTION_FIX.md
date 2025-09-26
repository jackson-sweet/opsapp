# Fix for Stripe Subscription Not Charging

## The Problem
The subscription is being created with status `incomplete` and `default_payment_method: null`, which means:
- The subscription exists but is waiting for payment
- No payment method is attached to charge
- The invoice is created but unpaid

## The Solution

### In Bubble's `complete_subscription` Workflow

You need to attach the payment method from the SetupIntent to the subscription. Here are two approaches:

### Option 1: Set Default Payment Method on Customer First (Recommended)

Before creating the subscription:

1. **Get the payment method from SetupIntent**:
```javascript
// If you have the setup_intent_id
const setupIntent = await stripe.setupIntents.retrieve(setup_intent_id);
const paymentMethodId = setupIntent.payment_method;
```

2. **Update customer's default payment method**:
```javascript
await stripe.customers.update(customer_id, {
  invoice_settings: {
    default_payment_method: paymentMethodId
  }
});
```

3. **Then create the subscription** (it will use the customer's default):
```javascript
const subscription = await stripe.subscriptions.create({
  customer: customer_id,
  items: [{ price: price_id }],
  // The subscription will automatically use the customer's default payment method
});
```

### Option 2: Set Payment Method Directly on Subscription

Create the subscription with the payment method:

```javascript
const subscription = await stripe.subscriptions.create({
  customer: customer_id,
  items: [{ price: price_id }],
  default_payment_method: paymentMethodId, // Add this line
  payment_behavior: 'default_incomplete',
  expand: ['latest_invoice.payment_intent']
});
```

### Option 3: If You Don't Have the SetupIntent ID

If the setup_intent_id isn't being passed, you can get the customer's payment methods:

```javascript
// List the customer's payment methods
const paymentMethods = await stripe.paymentMethods.list({
  customer: customer_id,
  type: 'card',
  limit: 1
});

// Use the most recent one
const paymentMethodId = paymentMethods.data[0]?.id;

// Create subscription with this payment method
const subscription = await stripe.subscriptions.create({
  customer: customer_id,
  items: [{ price: price_id }],
  default_payment_method: paymentMethodId
});
```

## Bubble Implementation Steps

1. **Modify the "Create Subscription" action** in Bubble:
   - Add a step before creating subscription to get customer's payment methods
   - Or pass the setup_intent_id from the app to the workflow

2. **In the Stripe plugin "Create Subscription" action**:
   - Add the `default_payment_method` parameter
   - Set it to the payment method ID from the SetupIntent or customer

3. **Alternative Quick Fix** - Update existing incomplete subscription:
   ```javascript
   // After creating the subscription, if it's incomplete
   if (subscription.status === 'incomplete') {
     // Get customer's payment method
     const paymentMethods = await stripe.paymentMethods.list({
       customer: customer_id,
       type: 'card',
       limit: 1
     });
     
     if (paymentMethods.data.length > 0) {
       // Update the subscription with the payment method
       await stripe.subscriptions.update(subscription.id, {
         default_payment_method: paymentMethods.data[0].id
       });
       
       // Pay the invoice
       await stripe.invoices.pay(subscription.latest_invoice);
     }
   }
   ```

## Testing

After implementing the fix:
1. The subscription status should be `active` or `trialing` (not `incomplete`)
2. The `default_payment_method` should have a value
3. The `latest_invoice` should show as paid
4. The customer should receive a charge on their card

## Quick Debug

Check in Stripe Dashboard:
1. Go to the subscription `sub_1S9zHEEooJoYGoIwfjks3Pbh`
2. Check if it shows "Incomplete" status
3. Check the invoice `in_1S9zHEEooJoYGoIwfPFXHLXZ`
4. The invoice will show "Open" or "Uncollectible" instead of "Paid"

The fix is to ensure the payment method from the SetupIntent is attached to the subscription when creating it.