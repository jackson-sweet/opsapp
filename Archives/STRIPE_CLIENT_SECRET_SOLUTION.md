# Stripe Client Secret Retrieval Solution

## Problem
The Bubble Stripe plugin's "Subscribe user to plan" action doesn't directly expose the `client_secret` needed for iOS PaymentSheet when using `payment_behavior: allow_incomplete`.

## Solution

Since Bubble's Stripe plugin may not expose all nested fields, you have several options:

### Option 1: Use Stripe API Connector (Recommended)
Instead of relying on the plugin's limited field exposure, make a direct API call to retrieve the subscription details:

1. **After creating the subscription**, add a Stripe API call:
```
GET /v1/subscriptions/{subscription_id}
Parameters:
- expand[]: latest_invoice.payment_intent
```

2. **Extract the client secret from the response**:
```json
{
  "latest_invoice": {
    "payment_intent": {
      "client_secret": "pi_xxx_secret_xxx"
    }
  }
}
```

### Option 2: Create Payment Intent Separately
If the subscription's payment intent isn't accessible:

1. **Get the subscription's latest invoice ID**
2. **Retrieve the invoice**:
```
GET /v1/invoices/{invoice_id}
```

3. **Get or create the payment intent**:
```
GET /v1/payment_intents/{payment_intent_id}
```

### Option 3: Return Alternative Fields
The iOS code has been updated to handle multiple field names:
- `client_secret` (original)
- `payment_intent_client_secret` (alternative)

In your Bubble workflow, try returning the field with different names to see what works.

## Updated iOS Implementation

The `BubbleSubscriptionService` now handles both field names:

```swift
struct SubscriptionResponse: Codable {
    let payment_intent_client_secret: String? // Alternative field name
    let client_secret: String? // Original field name
    
    // Computed property to get client secret from either field
    var paymentClientSecret: String? {
        return client_secret ?? payment_intent_client_secret
    }
}
```

## Bubble Workflow Implementation

In your `create_subscription_with_payment` workflow:

### Step 1: Subscribe User to Plan
- Use Stripe plugin action
- Set `payment_behavior: allow_incomplete`
- Save result as `subscription_result`

### Step 2: Get Payment Intent (API Connector)
```
Action: Stripe API - Get Subscription
Parameters:
- subscription_id: Result of step 1's subscription_id
- expand: latest_invoice.payment_intent
Save as: subscription_details
```

### Step 3: Create Ephemeral Key
```
Action: Stripe API - Create Ephemeral Key
Parameters:
- customer: Result of step 1's customer_id
- stripe_version: 2023-10-16
Save as: ephemeral_result
```

### Step 4: Return Data
```json
{
  "status": "success",
  "subscription_id": "subscription_result's subscription_id",
  "payment_intent_client_secret": "subscription_details's latest_invoice's payment_intent's client_secret",
  "ephemeral_key": "ephemeral_result's secret",
  "customer_id": "subscription_result's customer_id"
}
```

## Testing the Integration

1. **Enable Debug Logging**: The iOS app will log the Bubble response
2. **Check Field Names**: Look for the actual field names returned
3. **Verify Client Secret Format**: Should start with `pi_` and contain `_secret_`

## Troubleshooting

### If client_secret is still missing:
1. Check Stripe Dashboard logs for the API calls
2. Verify the subscription has `payment_behavior: allow_incomplete`
3. Ensure the subscription has an unpaid invoice with a payment intent
4. Try expanding different fields in the API call

### Alternative: Use Setup Intent
If payment collection at subscription creation isn't working, consider:
1. Create subscription with trial period (no immediate payment)
2. Collect payment method separately using SetupIntent
3. Attach payment method to subscription

## Key Points
- The client secret is nested in: `subscription.latest_invoice.payment_intent.client_secret`
- Bubble plugin may not expose nested fields directly
- API Connector gives you full control over field expansion
- The iOS app now handles multiple field name variations