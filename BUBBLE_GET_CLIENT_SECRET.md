# How to Get the Client Secret in Bubble

## The Problem
When you create a subscription with `payment_behavior: allow_incomplete`, Stripe creates a payment intent that needs to be confirmed on the client side. The client secret for this payment intent is nested deep in the subscription object and may not be directly accessible through the Bubble Stripe plugin.

## Solution: Add a Stripe API Call

### Step 1: Set up Stripe API Connector

1. Go to **Plugins → API Connector**
2. Add or edit your "Stripe API" connection
3. Add a new API call named: **Get Subscription with Payment Intent**

**Configuration:**
- **Use as:** Action
- **Data type:** JSON
- **Method:** GET
- **URL:** `subscriptions/[subscription_id]?expand[]=latest_invoice.payment_intent`
- **Headers:**
  - Authorization: `Bearer sk_test_YOUR_SECRET_KEY`
  - Content-Type: `application/json`

**Parameters:**
- **subscription_id** (dynamic):
  - Key: leave empty (it's in the URL)
  - Private: unchecked
  - Optional: unchecked

**Initialize the call:**
1. Replace `[subscription_id]` in the URL with a test subscription ID from your Stripe dashboard
2. Click "Initialize call"
3. You should see the full subscription object with the payment intent expanded

### Step 2: Update Your Workflow

In your `create_subscription_with_payment` workflow:

```
1. Subscribe user to plan (Stripe Plugin)
   - Customer: Company's stripe_customer_id
   - Price: price_id parameter
   - Payment behavior: allow_incomplete
   - Save as: subscription_result

2. Get Subscription with Payment Intent (API Connector)
   - subscription_id: Result of step 1's subscription_id
   - Save as: subscription_details

3. Create ephemeral key (API Connector)
   - Customer: Result of step 1's customer_id
   - Save as: ephemeral_result

4. Return data as JSON
   {
     "status": "success",
     "subscription_id": "Result of step 1's subscription_id",
     "payment_intent_client_secret": "Result of step 2's latest_invoice's payment_intent's client_secret",
     "ephemeral_key": "Result of step 3's secret",
     "customer_id": "Result of step 1's customer_id"
   }
```

## Alternative: Direct Payment Intent Retrieval

If the above doesn't work, try getting the payment intent directly:

### Add Another API Call: Get Payment Intent

**Configuration:**
- **Method:** GET
- **URL:** `payment_intents/[payment_intent_id]`

**In your workflow:**
```
1. Subscribe user to plan
2. Get the subscription details
3. Extract payment_intent_id from latest_invoice
4. Get Payment Intent (using the ID from step 3)
5. Return the client_secret from step 4
```

## How to Find the Right Fields in Bubble

### Debug Approach:
1. After "Subscribe user to plan", add a temporary action:
   - **Log the result** or **Create a thing** to save the entire response
   - Look at what fields are available

2. Common paths to try:
   - `Result of step 1's latest_invoice's payment_intent's client_secret`
   - `Result of step 1's latest_invoice's payment_intent_client_secret`
   - `Result of step 1's invoices's first item's payment_intent's client_secret`

### What the Client Secret Looks Like:
- Starts with `pi_` (payment intent)
- Contains `_secret_`
- Example: `pi_3ABC123DEF456GHI_secret_XYZ789`

## Minimal Test Workflow

To quickly test if you can get the client secret:

```
1. Subscribe user to plan
   - Save as: sub_result

2. Return data as JSON
   - Try different field paths:
   {
     "test1": "Result of step 1's latest_invoice's payment_intent's client_secret",
     "test2": "Result of step 1's latest_invoice's payment_intent",
     "test3": "Result of step 1's latest_invoice",
     "test4": "Result of step 1's invoices"
   }

3. Check the response to see which fields have data
```

## If All Else Fails: Two-Step Process

Instead of getting the client secret immediately:

### Option 1: Create Setup Intent First
1. Create a SetupIntent for collecting payment method
2. Collect payment method using SetupIntent's client secret
3. Then create the subscription with the saved payment method

### Option 2: Use Trial Period
1. Create subscription with a 1-second trial (no immediate payment)
2. Create a SetupIntent to collect payment method
3. Attach payment method to customer
4. Update subscription to remove trial

## Quick Fix for Testing

If you just want to test the flow without the actual payment:

In your Bubble workflow, return a dummy client secret:
```json
{
  "status": "success",
  "subscription_id": "sub_test123",
  "payment_intent_client_secret": "pi_test_secret_dummy",
  "ephemeral_key": "ek_test_dummy",
  "customer_id": "cus_test123"
}
```

This will fail at payment confirmation but will let you test the UI flow.

## Need More Help?

1. **Check Stripe Logs**: Dashboard → Developers → Logs
   - Look for the subscription creation
   - Click to see the full response object
   - Find the path to client_secret

2. **Use Stripe CLI**: Test the API directly
   ```bash
   stripe subscriptions retrieve sub_xxx \
     --expand latest_invoice.payment_intent
   ```
   Look for: `latest_invoice.payment_intent.client_secret`

3. **Contact Bubble Support**: Ask specifically:
   - "How do I access nested fields from the Stripe plugin's Subscribe action?"
   - "How do I get the payment_intent.client_secret from a subscription?"