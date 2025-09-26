# Bubble Ephemeral Key API Setup Guide

## Overview
The ephemeral key is required for the iOS app to securely interact with Stripe on behalf of a customer. This guide shows how to set up the API call in Bubble.

## Step 1: API Connector Setup

### Add Stripe API Connection
1. Go to Plugins → API Connector
2. Add a new API if not already configured, name it "Stripe API"
3. Configure the following:

**Authentication:**
- Authentication: Private key in header
- Key name: `Authorization`
- Key value: `Bearer sk_test_YOUR_STRIPE_SECRET_KEY` (or `Bearer sk_live_YOUR_KEY` for production)
- Use a shared header for all calls: ✓

**Base Settings:**
- Base URL: `https://api.stripe.com/v1/`

## Step 2: Create Ephemeral Key Call

### Add New API Call
1. In the Stripe API connector, click "Add another call"
2. Name it: `CreateEphemeralKey`
3. Configure as follows:

**Call Settings:**
- Use as: Action
- Data type: JSON
- Method: POST
- URL: `ephemeral_keys` (not the full URL, just the endpoint)

**Headers:**
- Stripe-Version: `2023-10-16` (REQUIRED - must be exact)
- Content-Type: `application/x-www-form-urlencoded`

**Parameters:**
Add these parameters:

1. **customer** (REQUIRED)
   - Key: `customer`
   - Value: Leave empty (will be dynamic)
   - Private: Unchecked
   - Optional: Unchecked

**Body Type:**
- Select: `x-www-form-urlencoded`
- Body: `customer=<customer>`

## Step 3: Initialize the Call

1. Click "Initialize call"
2. For the customer parameter, enter a test customer ID from your Stripe dashboard (e.g., `cus_xxxxxxxxxxxxx`)
3. The response should look like:
```json
{
  "id": "ephkey_...",
  "object": "ephemeral_key",
  "associated_objects": [...],
  "created": 1234567890,
  "expires": 1234567890,
  "livemode": false,
  "secret": "ek_test_..."
}
```

## Step 4: Use in Workflow

In your `create_subscription_with_payment` workflow:

```
1. Subscribe user to plan (Stripe plugin)
   - Save result as "subscription_result"

2. Create ephemeral key (API Connector - Stripe API - CreateEphemeralKey)
   - customer = Result of step 1's customer_id
   - Save result as "ephemeral_result"

3. Return data as JSON
   {
     "status": "success",
     "subscription_id": "subscription_result's subscription_id",
     "client_secret": "subscription_result's latest_invoice's payment_intent's client_secret",
     "ephemeral_key": "ephemeral_result's secret",
     "customer_id": "subscription_result's customer_id"
   }
```

## Common Errors and Solutions

### Error: "Stripe-Version header is required"
**Solution:** Make sure you include the Stripe-Version header with exact value `2023-10-16`

### Error: "No such customer"
**Solution:** Ensure the customer ID exists in your Stripe account. The customer should be created by the Stripe plugin when subscribing.

### Error: "Invalid API Key provided"
**Solution:** 
- Check that your API key starts with `sk_test_` for test mode or `sk_live_` for production
- Ensure the format is `Bearer sk_test_xxxxx` with a space after Bearer

### Error: "Received unknown parameter"
**Solution:** Make sure you're using `x-www-form-urlencoded` body type, not JSON

### Error: "You passed an empty string for 'customer'"
**Solution:** In the workflow, make sure you're passing the actual customer ID from the previous step, not an empty value

## Alternative: Manual API Call Setup

If the API Connector continues to have issues, you can use a manual API call:

### In Bubble Workflow:
1. Use "API Workflow" → "Make API Request"
2. Configure:
```
URL: https://api.stripe.com/v1/ephemeral_keys
Method: POST
Headers:
  Authorization: Bearer sk_test_YOUR_KEY
  Stripe-Version: 2023-10-16
  Content-Type: application/x-www-form-urlencoded
Body: customer=CUSTOMER_ID_HERE
```

## Testing the Ephemeral Key

### Via Stripe CLI:
```bash
stripe ephemeral-keys create \
  --customer=cus_xxxxxxxxxxxxx \
  --stripe-version=2023-10-16
```

### Via cURL:
```bash
curl https://api.stripe.com/v1/ephemeral_keys \
  -u sk_test_YOUR_KEY: \
  -d customer=cus_xxxxxxxxxxxxx \
  -H "Stripe-Version: 2023-10-16"
```

## Important Notes

1. **Stripe-Version is Critical**: The iOS SDK expects a specific API version. Use exactly `2023-10-16`.

2. **Ephemeral Keys Expire**: They're only valid for a short time (usually 1 hour). Create them fresh for each payment session.

3. **Customer Required**: You must have a valid Stripe customer ID. This is typically created when you first subscribe the user.

4. **Secret vs ID**: Return the `secret` field from the response, not the `id`.

## Debugging Tips

1. **Check Stripe Logs**: Go to Stripe Dashboard → Developers → Logs to see the exact request being made

2. **Verify Customer**: In Stripe Dashboard → Customers, confirm the customer ID exists

3. **Test in API Connector**: Use the "Initialize call" button with a known good customer ID

4. **Check Response**: Make sure you're extracting the `secret` field from the response, not the entire response object

## Need More Help?

If you're still having issues:
1. Share the exact error message you're seeing
2. Check the Stripe Dashboard logs for the failed request
3. Verify your Stripe API version compatibility
4. Ensure your Stripe account has the necessary permissions